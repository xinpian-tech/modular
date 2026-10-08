"""Composable CPU-golden NR PDSCH coding and receive-chain orchestration."""

from std.collections import Span
from std.math import frexp, isfinite, ldexp
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import ofdm_modulate, ofdm_demodulate
from wireless_dsp.modem import qam_map, qam_demapper_llr_piecewise
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)
from .grid import (
    NRResourceGrid,
    nr_pdsch_dmrs_c_init,
    nr_map_pdsch_comb2,
    nr_extract_pdsch_comb2,
    nr_extract_dmrs_comb2,
    nr_ls_channel_estimate_comb2,
    nr_equalize_pdsch_comb2,
)
from .pdsch import (
    nr_pdsch_scramble,
    nr_pdsch_dmrs,
    nr_pdsch_descramble_llrs,
    nr_transport_crc_append,
    nr_transport_crc_check,
)
from .ldpc_profile import NRLDPCProfile, nr_ldpc_profile
from .ldpc_segmentation import (
    nr_ldpc_segment,
    nr_ldpc_desegment,
    nr_ldpc_encode_code_blocks,
    nr_ldpc_rate_match_code_blocks,
    nr_ldpc_rate_recover_code_blocks,
    nr_ldpc_decode_code_blocks,
)


def _pdsch_safe_frexp64(value: Float64) -> Tuple[Float64, Int32]:
    """Return a correct decomposition for normal and subnormal Float64."""
    if value == 0.0:
        return (value, Int32(0))
    if abs(value) < 2.2250738585072014e-308:
        var scaled = frexp(value * 18014398509481984.0)
        return (
            scaled[0], scaled[1].cast[DType.int32]() - Int32(54)
        )
    var parts = frexp(value)
    return (parts[0], parts[1].cast[DType.int32]())


def _scale_llr_by_channel_power(
    llr: Float64, channel: Complex64
) raises -> Float64:
    """Return ``llr * |channel|^2`` without a bad square intermediate."""
    if (
        not isfinite(llr)
        or not isfinite(channel.re)
        or not isfinite(channel.im)
    ):
        raise Error("PDSCH LLR scaling inputs must be finite")
    if llr == 0.0:
        return llr
    var scale = max(abs(channel.re), abs(channel.im))
    if scale == 0.0:
        raise Error("PDSCH channel estimate is singular")
    var normalized_re = channel.re / scale
    var normalized_im = channel.im / scale
    var normalized_energy = (
        normalized_re * normalized_re + normalized_im * normalized_im
    )
    var llr_parts = _pdsch_safe_frexp64(llr)
    var scale_parts = _pdsch_safe_frexp64(scale)
    var energy_parts = _pdsch_safe_frexp64(normalized_energy)
    var mantissa = (
        llr_parts[0]
        * scale_parts[0]
        * scale_parts[0]
        * energy_parts[0]
    )
    var exponent = (
        llr_parts[1] + 2 * scale_parts[1] + energy_parts[1]
    )
    var canonical = _pdsch_safe_frexp64(mantissa)
    mantissa = canonical[0]
    exponent += canonical[1]
    if exponent < -1074:
        return -0.0 if mantissa < 0.0 else 0.0
    if exponent > 1024:
        raise Error("PDSCH channel-scaled LLR is not representable")
    var result: Float64
    if exponent <= -1022:
        result = (
            ldexp(mantissa, exponent + Int32(1022))
            * 2.2250738585072014e-308
        )
    elif exponent == 1024:
        result = ldexp(mantissa, Int32(1023)) * 2.0
    else:
        result = ldexp(mantissa, exponent)
    if not isfinite(result):
        raise Error("PDSCH channel-scaled LLR is not representable")
    return result


struct NRPDSCHWaveformConfig(ImplicitlyCopyable):
    """One-symbol single-layer comb-2 PDSCH waveform allocation.

    This bounded reference profile maps one configuration-type-1 DM-RS port
    and its data REs into one OFDM symbol.  Each scheduled PRB therefore has
    six DM-RS REs and six data REs.  The explicit one-symbol scope keeps TBS
    accounting, waveform energy, and sample-domain noise auditable.
    """

    var fft_size: Int
    var cyclic_prefix: Int
    var first_subcarrier: Int
    var resource_blocks: Int
    var slot: Int
    var dmrs_symbol: Int
    var n_id: Int
    var n_scid: Int
    var dmrs_offset: Int
    var rnti: Int
    var codeword: Int

    def __init__(
        out self,
        fft_size: Int,
        cyclic_prefix: Int,
        first_subcarrier: Int,
        resource_blocks: Int,
        slot: Int,
        dmrs_symbol: Int,
        n_id: Int,
        n_scid: Int,
        dmrs_offset: Int,
        rnti: Int,
        codeword: Int = 0,
    ) raises:
        if fft_size < 2 or (fft_size & (fft_size - 1)) != 0:
            raise Error("PDSCH reference FFT size must be a power of two")
        if cyclic_prefix < 0 or cyclic_prefix > fft_size:
            raise Error("invalid PDSCH cyclic-prefix length")
        if resource_blocks < 1 or resource_blocks > 275:
            raise Error("PDSCH scheduled PRBs must be in [1,275]")
        if resource_blocks > fft_size // 12 or first_subcarrier < 0:
            raise Error("invalid PDSCH contiguous resource allocation")
        var allocation = 12 * resource_blocks
        if first_subcarrier > fft_size - allocation:
            raise Error("PDSCH allocation exceeds the FFT grid")
        if fft_size > Int.MAX - cyclic_prefix:
            raise Error("PDSCH waveform length overflows Int")
        if slot < 0 or dmrs_symbol < 0 or dmrs_symbol > 13:
            raise Error("invalid PDSCH slot or DM-RS symbol")
        if n_id < 0 or n_id > 1023 or n_scid < 0 or n_scid > 1:
            raise Error("invalid PDSCH identity or N_SCID")
        if dmrs_offset < 0 or dmrs_offset > 1:
            raise Error("PDSCH comb-2 offset must be zero or one")
        if rnti < 0 or rnti > 0xFFFF or codeword < 0 or codeword > 1:
            raise Error("invalid PDSCH RNTI or codeword")
        self.fft_size = fft_size
        self.cyclic_prefix = cyclic_prefix
        self.first_subcarrier = first_subcarrier
        self.resource_blocks = resource_blocks
        self.slot = slot
        self.dmrs_symbol = dmrs_symbol
        self.n_id = n_id
        self.n_scid = n_scid
        self.dmrs_offset = dmrs_offset
        self.rnti = rnti
        self.codeword = codeword

    def validate(self) raises:
        _ = NRPDSCHWaveformConfig(
            self.fft_size,
            self.cyclic_prefix,
            self.first_subcarrier,
            self.resource_blocks,
            self.slot,
            self.dmrs_symbol,
            self.n_id,
            self.n_scid,
            self.dmrs_offset,
            self.rnti,
            self.codeword,
        )

    def allocation_subcarriers(self) -> Int:
        return 12 * self.resource_blocks

    def dmrs_re_count(self) -> Int:
        return 6 * self.resource_blocks

    def data_re_count(self) -> Int:
        return 6 * self.resource_blocks

    def coded_bit_capacity(self, modulation_order: Int) raises -> Int:
        _validate_pdsch_modulation(modulation_order)
        if self.data_re_count() > Int.MAX // modulation_order:
            raise Error("PDSCH coded-bit capacity overflows Int")
        return self.data_re_count() * modulation_order


def nr_pdsch_grid_to_waveform(
    config: NRPDSCHWaveformConfig, grid: NRResourceGrid
) raises -> List[Complex64]:
    """OFDM-modulate the single-symbol PDSCH grid with its configured CP."""
    config.validate()
    if grid.symbol_count != 1 or grid.subcarrier_count != config.fft_size:
        raise Error("PDSCH resource grid dimensions do not match the config")
    var spectrum = List[Complex64](capacity=config.fft_size)
    for subcarrier in range(config.fft_size):
        spectrum.append(grid[0, subcarrier])
    return ofdm_modulate(Span(spectrum), config.cyclic_prefix)


def nr_pdsch_waveform_to_grid(
    config: NRPDSCHWaveformConfig, waveform: Span[Complex64, ...]
) raises -> NRResourceGrid:
    """Remove the configured CP and FFT one PDSCH waveform symbol."""
    config.validate()
    if len(waveform) != config.fft_size + config.cyclic_prefix:
        raise Error("PDSCH waveform length does not match the config")
    var spectrum = ofdm_demodulate(
        waveform, config.fft_size, config.cyclic_prefix
    )
    var grid = NRResourceGrid(1, config.fft_size)
    for subcarrier in range(config.fft_size):
        grid[0, subcarrier] = spectrum[subcarrier]
    return grid^


struct NRPDSCHTransmitBlock(Movable):
    """Intermediate checkpoints required to reproduce a PDSCH transmission."""

    var profile: NRLDPCProfile
    var transport_block: List[UInt8]
    var encoded_null_mask: List[UInt8]
    var rate_matched_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var symbols: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        var profile: NRLDPCProfile,
        var transport_block: List[UInt8],
        var encoded_null_mask: List[UInt8],
        var rate_matched_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var symbols: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.profile = profile^
        self.transport_block = transport_block^
        self.encoded_null_mask = encoded_null_mask^
        self.rate_matched_bits = rate_matched_bits^
        self.scrambled_bits = scrambled_bits^
        self.symbols = symbols^
        self.checkpoint_metadata = checkpoint_metadata^


struct NRPDSCHDecodeResult(Movable):
    """Decoded transport block plus each observable receive-chain stage."""

    var payload: List[UInt8]
    var transport_block: List[UInt8]
    var iterations: List[Int]
    var received_data: List[Complex64]
    var channel_estimate: List[Complex64]
    var equalized_symbols: List[Complex64]
    var demapper_llrs: List[Float64]
    var descrambled_llrs: List[Float64]
    var rate_recovered_llrs: List[Float64]
    var checkpoint_metadata: List[CheckpointMetadata]
    var transport_crc_ok: Bool
    var code_block_crc_ok: Bool
    var ldpc_converged: Bool

    def __init__(
        out self,
        var payload: List[UInt8],
        var transport_block: List[UInt8],
        var iterations: List[Int],
        var received_data: List[Complex64],
        var channel_estimate: List[Complex64],
        var equalized_symbols: List[Complex64],
        var demapper_llrs: List[Float64],
        var descrambled_llrs: List[Float64],
        var rate_recovered_llrs: List[Float64],
        var checkpoint_metadata: List[CheckpointMetadata],
        transport_crc_ok: Bool,
        code_block_crc_ok: Bool,
        ldpc_converged: Bool,
    ):
        self.payload = payload^
        self.transport_block = transport_block^
        self.iterations = iterations^
        self.received_data = received_data^
        self.channel_estimate = channel_estimate^
        self.equalized_symbols = equalized_symbols^
        self.demapper_llrs = demapper_llrs^
        self.descrambled_llrs = descrambled_llrs^
        self.rate_recovered_llrs = rate_recovered_llrs^
        self.checkpoint_metadata = checkpoint_metadata^
        self.transport_crc_ok = transport_crc_ok
        self.code_block_crc_ok = code_block_crc_ok
        self.ldpc_converged = ldpc_converged


def _nr_pdsch_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    transport_block: Int,
    encoded_null_mask: Int,
    rate_matched_bits: Int,
    scrambled_bits: Int,
    symbols: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=5)
    for stage, length in [
        ("transport-block", transport_block),
        ("encoded-null-mask", encoded_null_mask),
        ("rate-matched-bits", rate_matched_bits),
        ("scrambled-bits", scrambled_bits),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "uint8",
            length,
            q_format="binary-u1",
            layout="bit-per-byte",
        ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "qam-symbols",
        "complex64",
        symbols,
        layout="iq-interleaved",
    ))
    return result^


def _nr_pdsch_rx_checkpoint_metadata(
    testcase_id: StringSlice,
    received_data: Int,
    channel_estimate: Int,
    equalized_symbols: Int,
    demapper_llrs: Int,
    descrambled_llrs: Int,
    rate_recovered_llrs: Int,
    iterations: Int,
    transport_block: Int,
    payload: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=9)
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "received-data",
        "complex64",
        received_data,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "channel-estimate",
        "complex64",
        channel_estimate,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "equalized-symbols",
        "complex64",
        equalized_symbols,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "demapper-llrs", "float64", demapper_llrs
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "descrambled-llrs", "float64", descrambled_llrs
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "rate-recovered-llrs",
        "float64",
        rate_recovered_llrs,
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "ldpc-iterations",
        "int",
        iterations,
        q_format="integer",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "transport-block",
        "uint8",
        transport_block,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "payload",
        "uint8",
        payload,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    return result^


def _validate_pdsch_modulation(modulation_order: Int) raises:
    if (
        modulation_order != 2 and modulation_order != 4
        and modulation_order != 6 and modulation_order != 8
        and modulation_order != 10
    ):
        raise Error("NR PDSCH modulation order must be 2, 4, 6, 8, or 10")


def nr_pdsch_encode_transport_block(
    payload: Span[UInt8, ...],
    target_code_rate: Float64,
    modulation_order: Int,
    redundancy_version: Int,
    output_bits: Int,
    rnti: Int,
    codeword: Int,
    n_id: Int,
    *,
    testcase_id: StringSlice = "nr-pdsch-tx",
) raises -> NRPDSCHTransmitBlock:
    """CRC, segment, LDPC encode/rate-match, scramble, and QAM-map a TB."""
    _validate_pdsch_modulation(modulation_order)
    if output_bits < 1 or output_bits % modulation_order != 0:
        raise Error("PDSCH output length must contain complete QAM symbols")
    for i in range(len(payload)):
        if payload[i] > 1:
            raise Error("PDSCH payload must contain only zero and one")

    var profile = nr_ldpc_profile(len(payload), target_code_rate)
    var transport_block = nr_transport_crc_append(payload)
    var segments = nr_ldpc_segment(Span(transport_block), profile)
    var encoded = nr_ldpc_encode_code_blocks(segments, profile)
    var rate_matched = nr_ldpc_rate_match_code_blocks(
        encoded,
        profile,
        redundancy_version,
        output_bits,
        modulation_order,
        1,
    )
    var scrambled = nr_pdsch_scramble(
        Span(rate_matched), rnti, codeword, n_id
    )
    var symbols = qam_map(Span(scrambled), modulation_order)
    var null_mask = encoded.null_mask.copy()
    var checkpoint_metadata = _nr_pdsch_tx_checkpoint_metadata(
        testcase_id,
        len(transport_block),
        len(null_mask),
        len(rate_matched),
        len(scrambled),
        len(symbols),
    )
    return NRPDSCHTransmitBlock(
        profile^,
        transport_block^,
        null_mask^,
        rate_matched^,
        scrambled^,
        symbols^,
        checkpoint_metadata^,
    )


def nr_pdsch_decode_grid_comb2(
    grid: NRResourceGrid,
    symbol: Int,
    first_subcarrier: Int,
    allocation_size: Int,
    dmrs_offset: Int,
    known_dmrs: Span[Complex64, ...],
    encoded_null_mask: Span[UInt8, ...],
    profile: NRLDPCProfile,
    payload_bits: Int,
    modulation_order: Int,
    redundancy_version: Int,
    rnti: Int,
    codeword: Int,
    n_id: Int,
    noise_variance: Float64,
    *,
    max_iterations: Int = 30,
    normalization: Float64 = 0.8,
    offset: Float64 = 0.0,
    testcase_id: StringSlice = "nr-pdsch-rx-comb2",
) raises -> NRPDSCHDecodeResult:
    """Execute the complete single-layer comb-2 PDSCH CPU receive chain.

    Stages are resource extraction, LS/interpolation, ZF equalization, soft
    demapping, descrambling, rate recovery, LDPC, CB CRC, and transport CRC.
    ``noise_variance`` is the common pre-equalization complex FFT-bin N0.
    The implementation applies the equivalent ``N0 / |H_hat[k]|^2``
    independently to every data tone after zero forcing.
    """
    _validate_pdsch_modulation(modulation_order)
    if (
        payload_bits < 0
        or not isfinite(noise_variance)
        or noise_variance <= 0.0
    ):
        raise Error("invalid PDSCH decoder payload or noise variance")
    if len(encoded_null_mask) != profile.code_blocks * profile.encoded_bits:
        raise Error("PDSCH LDPC null mask does not match the profile")

    var received_data = nr_extract_pdsch_comb2(
        grid, symbol, first_subcarrier, allocation_size, dmrs_offset
    )
    var received_dmrs = nr_extract_dmrs_comb2(
        grid, symbol, first_subcarrier, allocation_size, dmrs_offset
    )
    var channel = nr_ls_channel_estimate_comb2(
        Span(received_dmrs), known_dmrs, allocation_size, dmrs_offset
    )
    var equalized = nr_equalize_pdsch_comb2(
        Span(received_data), Span(channel), dmrs_offset
    )
    var llrs = qam_demapper_llr_piecewise(
        Span(equalized), modulation_order, noise_variance
    )
    # ZF divides the sample by h, so its noise variance is N0/|h|^2.
    # The max-log/piecewise LLR is linear in 1/N0; multiplying each symbol's
    # LLRs by |h|^2 applies the equivalent per-subcarrier variance without a
    # second demapper allocation.
    var data_symbol = 0
    for local in range(len(channel)):
        if local % 2 != dmrs_offset:
            for bit in range(modulation_order):
                var llr_index = data_symbol * modulation_order + bit
                llrs[llr_index] = _scale_llr_by_channel_power(
                    llrs[llr_index], channel[local]
                )
            data_symbol += 1
    var descrambled = nr_pdsch_descramble_llrs(
        Span(llrs), rnti, codeword, n_id
    )
    var recovered = nr_ldpc_rate_recover_code_blocks(
        Span(descrambled),
        encoded_null_mask,
        profile,
        redundancy_version,
        modulation_order,
        1,
    )
    var decoded = nr_ldpc_decode_code_blocks(
        Span(recovered),
        encoded_null_mask,
        profile,
        max_iterations=max_iterations,
        normalization=normalization,
        offset=offset,
    )
    var desegmented = nr_ldpc_desegment(Span(decoded.bits), profile)
    var transport_crc_ok = nr_transport_crc_check(
        Span(desegmented.bits), payload_bits
    )
    var payload = List[UInt8](capacity=payload_bits)
    for i in range(payload_bits):
        payload.append(desegmented.bits[i])
    var iterations = decoded.iterations.copy()
    var transport_block = desegmented.bits.copy()
    var checkpoint_metadata = _nr_pdsch_rx_checkpoint_metadata(
        testcase_id,
        len(received_data),
        len(channel),
        len(equalized),
        len(llrs),
        len(descrambled),
        len(recovered),
        len(iterations),
        len(transport_block),
        len(payload),
    )
    return NRPDSCHDecodeResult(
        payload^,
        transport_block^,
        iterations^,
        received_data^,
        channel^,
        equalized^,
        llrs^,
        descrambled^,
        recovered^,
        checkpoint_metadata^,
        transport_crc_ok,
        desegmented.code_block_crc_ok,
        decoded.converged,
    )


def nr_pdsch_decode_waveform_comb2(
    waveform: Span[Complex64, ...],
    config: NRPDSCHWaveformConfig,
    encoded_null_mask: Span[UInt8, ...],
    profile: NRLDPCProfile,
    payload_bits: Int,
    modulation_order: Int,
    redundancy_version: Int,
    sample_noise_variance: Float64,
    *,
    max_iterations: Int = 30,
    normalization: Float64 = 0.8,
    offset: Float64 = 0.0,
    testcase_id: StringSlice = "nr-pdsch-rx-waveform-comb2",
) raises -> NRPDSCHDecodeResult:
    """Decode sample-domain CP-OFDM with rigorous per-tone post-ZF N0.

    The IFFT uses ``1/N`` and the forward FFT is unscaled, so the common
    pre-equalization FFT-bin variance is ``N * sample_noise_variance``.
    ``nr_pdsch_decode_grid_comb2`` then applies each data tone's independent
    ``N * sample_noise_variance / |H_hat[k]|^2`` reliability.
    """
    config.validate()
    if not isfinite(sample_noise_variance) or sample_noise_variance <= 0.0:
        raise Error("PDSCH sample-domain noise variance must be positive")
    var frequency_noise = (
        sample_noise_variance * Float64(config.fft_size)
    )
    if not isfinite(frequency_noise) or frequency_noise <= 0.0:
        raise Error("PDSCH FFT-bin noise variance is unrepresentable")
    var grid = nr_pdsch_waveform_to_grid(config, waveform)
    var dmrs = nr_pdsch_dmrs(
        nr_pdsch_dmrs_c_init(
            config.slot,
            config.dmrs_symbol,
            config.n_id,
            config.n_scid,
        ),
        config.dmrs_re_count(),
    )
    return nr_pdsch_decode_grid_comb2(
        grid,
        0,
        config.first_subcarrier,
        config.allocation_subcarriers(),
        config.dmrs_offset,
        Span(dmrs),
        encoded_null_mask,
        profile,
        payload_bits,
        modulation_order,
        redundancy_version,
        config.rnti,
        config.codeword,
        config.n_id,
        frequency_noise,
        max_iterations=max_iterations,
        normalization=normalization,
        offset=offset,
        testcase_id=testcase_id,
    )
