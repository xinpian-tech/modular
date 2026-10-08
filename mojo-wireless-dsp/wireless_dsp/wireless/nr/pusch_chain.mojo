"""Single-layer NR PUSCH CPU reference transmit/receive chain.

This module intentionally implements a small, explicit standards profile rather
than pretending to be a scheduler or a complete UE/gNB stack.  It covers one
UL-SCH codeword and one layer on a contiguous allocation, ordinary QAM, one
configuration-type-1 port-0 DM-RS symbol (two CDM groups without data), and
either CP-OFDM or one-PRB DFT-s-OFDM.  Frequency hopping, UCI multiplexing,
PTRS, multiple layers/ports, pi/2-BPSK, MCS/TBS selection, configured
DM-RS-position lookup, and transform-precoded allocations wider than one PRB
are outside this reference profile.

The coding order follows TS 38.212 clauses 6.2.1/6.2.2/6.2.5, while scrambling,
modulation, transform precoding, and DM-RS follow TS 38.211 clauses 6.3.1 and
6.4.1.1.  Every intermediate is retained so tests and hardware models can use
the implementation as a reproducible golden chain.
"""

from std.collections import Span
from std.math import cos, exp, isfinite, log, sin
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import (
    ofdm_modulate,
    ofdm_demodulate,
    zero_forcing_equalize_siso,
)
from wireless_dsp.modem import qam_map, qam_demapper_llr_piecewise
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
    checkpoint_metadata_2d,
)
from .grid import NRResourceGrid, nr_ls_channel_estimate_comb2
from .pdsch import nr_transport_crc_append, nr_transport_crc_check
from .ldpc_profile import NRLDPCProfile, nr_ldpc_profile
from .ldpc_segmentation import (
    nr_ldpc_segment,
    nr_ldpc_desegment,
    nr_ldpc_encode_code_blocks,
    nr_ldpc_rate_match_code_blocks,
    nr_ldpc_rate_recover_code_blocks,
    nr_ldpc_decode_code_blocks,
)
from .uplink import (
    nr_pusch_scramble,
    nr_pusch_descramble_llrs,
    nr_pusch_transform_precoding,
    nr_pusch_transform_deprecoding,
    nr_pusch_dmrs,
)

comptime _TWO_PI = 6.283185307179586476925286766559


def _pusch_phi_6() -> List[Int]:
    """TS 38.211 Table 5.2.2.2-1, flattened by sequence group ``u``."""
    return [
        -3, -1, 3, 3, -1, -3,
        -3, 3, -1, -1, 3, -3,
        -3, -3, -3, 3, 1, -3,
        1, 1, 1, 3, -1, -3,
        1, 1, 1, -3, -1, 3,
        -3, 1, -1, -3, -3, -3,
        -3, 1, 3, -3, -3, -3,
        -3, -1, 1, -3, 1, -1,
        -3, -1, -3, 1, -3, -3,
        -3, -3, 1, -3, 3, -3,
        -3, 1, 3, 1, -3, -3,
        -3, -1, -3, 1, 1, -3,
        1, 1, 3, -1, -3, 3,
        1, 1, 3, 3, -1, 3,
        1, 1, 1, -3, 3, -1,
        1, 1, 1, -1, 3, -3,
        -3, -1, -1, -1, 3, -1,
        -3, -3, -1, 1, -1, -3,
        -3, -3, -3, 1, -3, -1,
        -3, 1, 1, -3, -1, -3,
        -3, 3, -3, 1, 1, -3,
        -3, 1, -3, -3, -3, -1,
        1, 1, -3, 3, 1, 3,
        1, 1, -3, -3, 1, -3,
        1, 1, 3, -1, 3, 3,
        1, 1, -3, 1, 3, 3,
        1, 1, -1, -1, 3, -1,
        1, 1, -1, 3, -1, -1,
        1, 1, -1, 3, -3, -1,
        1, 1, -3, 1, -1, -1,
    ]


def _pusch_low_papr_sequence_6(
    group: Int, cyclic_shift_index: Int
) raises -> List[Complex64]:
    """One-PRB transform-PUSCH DM-RS base sequence for ``delta=1``."""
    if group < 0 or group >= 30 or cyclic_shift_index < 0 or cyclic_shift_index > 11:
        raise Error("invalid transform-precoded PUSCH DM-RS configuration")
    var phi = _pusch_phi_6()
    var result = List[Complex64](capacity=6)
    for n in range(6):
        var angle = (
            3.1415926535897932384626433832795
            * Float64(phi[6 * group + n]) / 4.0
            + _TWO_PI * Float64(cyclic_shift_index * n) / 12.0
        )
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


struct NRPUSCHConfig(ImplicitlyCopyable):
    """Waveform and allocation parameters for the supported PUSCH profile.

    Grid row numbers are slot-relative OFDM symbol numbers.  ``symbol_count``
    therefore describes a prefix of one normal-CP slot and ``dmrs_symbol`` is
    both the grid row and the value used in the standardized DM-RS initializer.
    A constant explicit CP is used for every row to keep the waveform primitive
    independent of sampling-rate/numerology policy.  ``n_id`` is the PUSCH data
    scrambling identity; the keyword-only ``dmrs_n_id`` can select the distinct
    16-bit DM-RS identity and defaults to ``n_id``.
    """

    var fft_size: Int
    var cyclic_prefix: Int
    var symbol_count: Int
    var dmrs_symbol: Int
    var first_subcarrier: Int
    var resource_blocks: Int
    var slot: Int
    var n_id: Int
    var dmrs_n_id: Int
    var n_scid: Int
    var rnti: Int
    var codeword: Int
    var transform_precoding: Bool
    var dmrs_cyclic_shift: Int

    def __init__(
        out self,
        fft_size: Int,
        cyclic_prefix: Int,
        symbol_count: Int,
        dmrs_symbol: Int,
        first_subcarrier: Int,
        resource_blocks: Int,
        slot: Int,
        n_id: Int,
        n_scid: Int,
        rnti: Int,
        codeword: Int = 0,
        *,
        dmrs_n_id: Int = -1,
        transform_precoding: Bool = False,
        dmrs_cyclic_shift: Int = 0,
    ) raises:
        if fft_size < 2 or (fft_size & (fft_size - 1)) != 0:
            raise Error("PUSCH reference FFT size must be a power of two")
        if cyclic_prefix < 0 or cyclic_prefix > fft_size:
            raise Error("invalid PUSCH cyclic-prefix length")
        if symbol_count < 2 or symbol_count > 14:
            raise Error("PUSCH reference allocation must contain 2..14 symbols")
        if dmrs_symbol < 0 or dmrs_symbol >= symbol_count:
            raise Error("PUSCH DM-RS symbol is outside the allocation")
        if resource_blocks < 1 or first_subcarrier < 0:
            raise Error("invalid PUSCH contiguous resource allocation")
        if resource_blocks > fft_size // 12:
            raise Error("PUSCH allocation dimensions overflow the FFT grid")
        var allocation_subcarriers = 12 * resource_blocks
        if first_subcarrier > fft_size - allocation_subcarriers:
            raise Error("PUSCH allocation exceeds the FFT grid")
        if (
            allocation_subcarriers > Int.MAX // (symbol_count - 1)
            or fft_size > Int.MAX // symbol_count
            or cyclic_prefix > Int.MAX - fft_size
            or fft_size + cyclic_prefix > Int.MAX // symbol_count
        ):
            raise Error("PUSCH derived dimensions overflow Int")
        if slot < 0 or n_id < 0 or n_id > 1023:
            raise Error("invalid PUSCH slot or scrambling identity")
        var resolved_dmrs_n_id = n_id if dmrs_n_id < 0 else dmrs_n_id
        if resolved_dmrs_n_id < 0 or resolved_dmrs_n_id > 65535:
            raise Error("PUSCH DM-RS identity must be in [0,65535]")
        if n_scid < 0 or n_scid > 1 or rnti < 0 or rnti > 0xFFFF:
            raise Error("invalid PUSCH N_SCID or RNTI")
        if codeword != 0:
            raise Error("the single-layer PUSCH profile uses codeword zero")
        if dmrs_cyclic_shift < 0 or dmrs_cyclic_shift > 11:
            raise Error("PUSCH DM-RS cyclic shift must be in [0,11]")
        if transform_precoding and resource_blocks != 1:
            raise Error(
                "this DFT-s-OFDM reference profile supports exactly one PRB"
            )
        if not transform_precoding and dmrs_cyclic_shift != 0:
            raise Error("cyclic-shift DM-RS is used only with transform precoding")
        self.fft_size = fft_size
        self.cyclic_prefix = cyclic_prefix
        self.symbol_count = symbol_count
        self.dmrs_symbol = dmrs_symbol
        self.first_subcarrier = first_subcarrier
        self.resource_blocks = resource_blocks
        self.slot = slot
        self.n_id = n_id
        self.dmrs_n_id = resolved_dmrs_n_id
        self.n_scid = n_scid
        self.rnti = rnti
        self.codeword = codeword
        self.transform_precoding = transform_precoding
        self.dmrs_cyclic_shift = dmrs_cyclic_shift


struct NRPUSCHTransmitBlock(Movable):
    """PUSCH encoder, mapper, and waveform checkpoints."""

    var profile: NRLDPCProfile
    var transport_block: List[UInt8]
    var encoded_null_mask: List[UInt8]
    var rate_matched_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var modulated_symbols: List[Complex64]
    var mapped_data_symbols: List[Complex64]
    var dmrs: List[Complex64]
    var grid: NRResourceGrid
    var waveform: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        var profile: NRLDPCProfile,
        var transport_block: List[UInt8],
        var encoded_null_mask: List[UInt8],
        var rate_matched_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var modulated_symbols: List[Complex64],
        var mapped_data_symbols: List[Complex64],
        var dmrs: List[Complex64],
        var grid: NRResourceGrid,
        var waveform: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.profile = profile^
        self.transport_block = transport_block^
        self.encoded_null_mask = encoded_null_mask^
        self.rate_matched_bits = rate_matched_bits^
        self.scrambled_bits = scrambled_bits^
        self.modulated_symbols = modulated_symbols^
        self.mapped_data_symbols = mapped_data_symbols^
        self.dmrs = dmrs^
        self.grid = grid^
        self.waveform = waveform^
        self.checkpoint_metadata = checkpoint_metadata^


struct NRPUSCHDecodeResult(Movable):
    """Decoded UL-SCH bits, RX checkpoints, and independent status."""

    var payload: List[UInt8]
    var transport_block: List[UInt8]
    var received_grid: NRResourceGrid
    var channel_estimate: List[Complex64]
    var equalized_symbols: List[Complex64]
    var demapper_llrs: List[Float64]
    var descrambled_llrs: List[Float64]
    var rate_recovered_llrs: List[Float64]
    var iterations: List[Int]
    var checkpoint_metadata: List[CheckpointMetadata]
    var transport_crc_ok: Bool
    var code_block_crc_ok: Bool
    var ldpc_converged: Bool

    def __init__(
        out self,
        var payload: List[UInt8],
        var transport_block: List[UInt8],
        var received_grid: NRResourceGrid,
        var channel_estimate: List[Complex64],
        var equalized_symbols: List[Complex64],
        var demapper_llrs: List[Float64],
        var descrambled_llrs: List[Float64],
        var rate_recovered_llrs: List[Float64],
        var iterations: List[Int],
        var checkpoint_metadata: List[CheckpointMetadata],
        transport_crc_ok: Bool,
        code_block_crc_ok: Bool,
        ldpc_converged: Bool,
    ):
        self.payload = payload^
        self.transport_block = transport_block^
        self.received_grid = received_grid^
        self.channel_estimate = channel_estimate^
        self.equalized_symbols = equalized_symbols^
        self.demapper_llrs = demapper_llrs^
        self.descrambled_llrs = descrambled_llrs^
        self.rate_recovered_llrs = rate_recovered_llrs^
        self.iterations = iterations^
        self.checkpoint_metadata = checkpoint_metadata^
        self.transport_crc_ok = transport_crc_ok
        self.code_block_crc_ok = code_block_crc_ok
        self.ldpc_converged = ldpc_converged


def _nr_pusch_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    payload: Int,
    transport_block: Int,
    encoded_null_mask: Int,
    rate_matched_bits: Int,
    scrambled_bits: Int,
    modulated_symbols: Int,
    mapped_data_symbols: Int,
    dmrs: Int,
    grid_rows: Int,
    grid_columns: Int,
    waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=10)
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "payload-input",
        "uint8",
        payload,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "transport-block-with-crc",
        "uint8",
        transport_block,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "encoded-null-mask",
        "uint8",
        encoded_null_mask,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "rate-matched-bits",
        "uint8",
        rate_matched_bits,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "scrambled-bits",
        "uint8",
        scrambled_bits,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "modulated-symbols",
        "complex64",
        modulated_symbols,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "mapped-data-symbols",
        "complex64",
        mapped_data_symbols,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "dmrs",
        "complex64",
        dmrs,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_2d(
        testcase_id,
        "resource-grid",
        "complex64",
        grid_rows,
        grid_columns,
        row_stride=grid_columns,
        layout="row-major-iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "waveform",
        "complex64",
        waveform,
        layout="iq-interleaved",
    ))
    return result^


def _nr_pusch_rx_checkpoint_metadata(
    testcase_id: StringSlice,
    waveform: Int,
    grid_rows: Int,
    grid_columns: Int,
    channel_estimate: Int,
    equalized_symbols: Int,
    demapper_llrs: Int,
    descrambled_llrs: Int,
    rate_recovered_llrs: Int,
    iterations: Int,
    transport_block: Int,
    payload: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=13)
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "received-waveform",
        "complex64",
        waveform,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_2d(
        testcase_id,
        "received-grid",
        "complex64",
        grid_rows,
        grid_columns,
        row_stride=grid_columns,
        layout="row-major-iq-interleaved",
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
        "decoded-transport-block",
        "uint8",
        transport_block,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "decoded-payload",
        "uint8",
        payload,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    for stage in ["transport-crc-ok", "code-block-crc-ok", "ldpc-converged"]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "bool",
            1,
            q_format="boolean",
            layout="scalar",
        ))
    return result^


def _validate_pusch_modulation(modulation_order: Int) raises:
    # Ordinary PUSCH QAM from TS 38.211 6.3.1.2.  pi/2-BPSK is deliberately
    # excluded because it has a distinct mapper and DM-RS configuration.
    if (
        modulation_order != 2 and modulation_order != 4
        and modulation_order != 6 and modulation_order != 8
        and modulation_order != 10
    ):
        raise Error("PUSCH Qm must be 2, 4, 6, 8, or 10")


def nr_pusch_allocation_subcarriers(config: NRPUSCHConfig) -> Int:
    return 12 * config.resource_blocks


def nr_pusch_data_re_count(config: NRPUSCHConfig) -> Int:
    """Data RE count with two DM-RS CDM groups excluding the full pilot row."""
    return (config.symbol_count - 1) * nr_pusch_allocation_subcarriers(config)


def nr_pusch_coded_bit_capacity(
    config: NRPUSCHConfig, modulation_order: Int
) raises -> Int:
    _validate_pusch_modulation(modulation_order)
    var data_re = nr_pusch_data_re_count(config)
    if data_re > Int.MAX // modulation_order:
        raise Error("PUSCH coded-bit capacity overflows Int")
    return data_re * modulation_order


def nr_pusch_reference_dmrs(config: NRPUSCHConfig) raises -> List[Complex64]:
    """Generate the reference-profile port-0 DM-RS sequence.

    CP-OFDM uses the TS 38.211 6.4.1.1.1.1 Gold/QPSK sequence on the
    configuration-type-1 delta-0 comb.  The supported one-PRB DFT-s-OFDM
    profile uses the clause 5.2.2 type-1 length-6 low-PAPR base sequence for
    ``delta=1``, with neither group nor sequence hopping, ``u=N_ID mod 30`` and
    ``v=0``.  Both modes map their sequence onto the even type-1 comb.
    """
    var allocation = nr_pusch_allocation_subcarriers(config)
    if config.transform_precoding:
        return _pusch_low_papr_sequence_6(
            config.dmrs_n_id % 30, config.dmrs_cyclic_shift
        )
    return nr_pusch_dmrs(
        config.slot,
        config.dmrs_symbol,
        config.dmrs_n_id,
        config.n_scid,
        allocation // 2,
    )


def nr_map_pusch_single_layer(
    config: NRPUSCHConfig,
    data: Span[Complex64, ...],
    dmrs: Span[Complex64, ...],
) raises -> NRResourceGrid:
    """Map data and the reserved DM-RS row into a slot-local FFT grid."""
    var allocation = nr_pusch_allocation_subcarriers(config)
    if len(data) != nr_pusch_data_re_count(config):
        raise Error("PUSCH data count does not fill the configured data symbols")
    var expected_dmrs = allocation // 2
    if len(dmrs) != expected_dmrs:
        raise Error("PUSCH DM-RS count does not match the configured allocation")
    # Validate the complete mapping before constructing any partial grid.
    for index in range(len(data)):
        if not isfinite(data[index].re) or not isfinite(data[index].im):
            raise Error("PUSCH data symbols must be finite")
    for index in range(len(dmrs)):
        if not isfinite(dmrs[index].re) or not isfinite(dmrs[index].im):
            raise Error("PUSCH DM-RS symbols must be finite")
    var grid = NRResourceGrid(config.symbol_count, config.fft_size)
    var data_index = 0
    for symbol in range(config.symbol_count):
        if symbol == config.dmrs_symbol:
            # Port 0, configuration type 1 has frequency offset Delta=0.  With
            # two CDM groups without data, the complementary comb stays unused.
            for local in range(0, allocation, 2):
                var pilot = local // 2
                grid[symbol, config.first_subcarrier + local] = Complex64(
                    dmrs[pilot].re, dmrs[pilot].im
                )
        else:
            for local in range(allocation):
                grid[symbol, config.first_subcarrier + local] = Complex64(
                    data[data_index].re, data[data_index].im
                )
                data_index += 1
    return grid^


def nr_pusch_grid_to_waveform(
    config: NRPUSCHConfig, grid: NRResourceGrid
) raises -> List[Complex64]:
    """OFDM-modulate every configured grid row and concatenate the symbols."""
    if (
        grid.symbol_count != config.symbol_count
        or grid.subcarrier_count != config.fft_size
    ):
        raise Error("PUSCH resource grid dimensions do not match the config")
    var result = List[Complex64](
        capacity=config.symbol_count * (config.fft_size + config.cyclic_prefix)
    )
    for symbol in range(config.symbol_count):
        var spectrum = List[Complex64](capacity=config.fft_size)
        for subcarrier in range(config.fft_size):
            spectrum.append(grid[symbol, subcarrier])
        var samples = ofdm_modulate(Span(spectrum), config.cyclic_prefix)
        for value in samples:
            if not isfinite(value.re) or not isfinite(value.im):
                raise Error("PUSCH waveform samples must remain finite")
            result.append(value)
    return result^


def nr_pusch_waveform_to_grid(
    config: NRPUSCHConfig, waveform: Span[Complex64, ...]
) raises -> NRResourceGrid:
    """Split a waveform at exact OFDM boundaries, remove CP, and FFT it."""
    var samples_per_symbol = config.fft_size + config.cyclic_prefix
    if len(waveform) != config.symbol_count * samples_per_symbol:
        raise Error("PUSCH waveform length does not match the configured grid")
    for index in range(len(waveform)):
        if not isfinite(waveform[index].re) or not isfinite(waveform[index].im):
            raise Error("PUSCH waveform samples must be finite")
    var grid = NRResourceGrid(config.symbol_count, config.fft_size)
    for symbol in range(config.symbol_count):
        var samples = List[Complex64](capacity=samples_per_symbol)
        var offset = symbol * samples_per_symbol
        for i in range(samples_per_symbol):
            samples.append(waveform[offset + i])
        var spectrum = ofdm_demodulate(
            Span(samples), config.fft_size, config.cyclic_prefix
        )
        for subcarrier in range(config.fft_size):
            if (
                not isfinite(spectrum[subcarrier].re)
                or not isfinite(spectrum[subcarrier].im)
            ):
                raise Error("PUSCH FFT output must remain finite")
            grid[symbol, subcarrier] = spectrum[subcarrier]
    return grid^


def _pusch_transform_data_symbols(
    config: NRPUSCHConfig, symbols: Span[Complex64, ...]
) raises -> List[Complex64]:
    var allocation = nr_pusch_allocation_subcarriers(config)
    if len(symbols) != nr_pusch_data_re_count(config):
        raise Error("PUSCH modulation output does not fill the allocation")
    if not config.transform_precoding:
        var copied = List[Complex64](capacity=len(symbols))
        for i in range(len(symbols)):
            copied.append(Complex64(symbols[i].re, symbols[i].im))
        return copied^
    var result = List[Complex64](capacity=len(symbols))
    for symbol in range(config.symbol_count - 1):
        var block = List[Complex64](capacity=allocation)
        for local in range(allocation):
            block.append(symbols[symbol * allocation + local])
        var spread = nr_pusch_transform_precoding(Span(block))
        for value in spread:
            result.append(value)
    return result^


def nr_pusch_encode_transport_block(
    payload: Span[UInt8, ...],
    target_code_rate: Float64,
    modulation_order: Int,
    redundancy_version: Int,
    config: NRPUSCHConfig,
    *,
    testcase_id: StringSlice = "nr-pusch-tx",
) raises -> NRPUSCHTransmitBlock:
    """Execute UL-SCH CRC through PUSCH waveform generation."""
    _validate_pusch_modulation(modulation_order)
    for i in range(len(payload)):
        if payload[i] > 1:
            raise Error("PUSCH payload must contain only zero and one")
    var output_bits = nr_pusch_coded_bit_capacity(config, modulation_order)
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
    var scrambled = nr_pusch_scramble(
        Span(rate_matched), config.rnti, config.codeword, config.n_id
    )
    var modulated = qam_map(Span(scrambled), modulation_order)
    var mapped_data = _pusch_transform_data_symbols(config, Span(modulated))
    var dmrs = nr_pusch_reference_dmrs(config)
    var grid = nr_map_pusch_single_layer(
        config, Span(mapped_data), Span(dmrs)
    )
    var waveform = nr_pusch_grid_to_waveform(config, grid)
    var null_mask = encoded.null_mask.copy()
    var checkpoint_metadata = _nr_pusch_tx_checkpoint_metadata(
        testcase_id,
        len(payload),
        len(transport_block),
        len(null_mask),
        len(rate_matched),
        len(scrambled),
        len(modulated),
        len(mapped_data),
        len(dmrs),
        grid.symbol_count,
        grid.subcarrier_count,
        len(waveform),
    )
    return NRPUSCHTransmitBlock(
        profile^,
        transport_block^,
        null_mask^,
        rate_matched^,
        scrambled^,
        modulated^,
        mapped_data^,
        dmrs^,
        grid^,
        waveform^,
        checkpoint_metadata^,
    )


def _pusch_channel_estimate(
    config: NRPUSCHConfig,
    grid: NRResourceGrid,
    known_dmrs: Span[Complex64, ...],
) raises -> List[Complex64]:
    var allocation = nr_pusch_allocation_subcarriers(config)
    var received = List[Complex64](capacity=allocation // 2)
    for local in range(0, allocation, 2):
        received.append(
            grid[config.dmrs_symbol, config.first_subcarrier + local]
        )
    return nr_ls_channel_estimate_comb2(
        Span(received), known_dmrs, allocation, 0
    )


def _pusch_equalized_data(
    config: NRPUSCHConfig,
    grid: NRResourceGrid,
    channel: Span[Complex64, ...],
) raises -> List[Complex64]:
    var allocation = nr_pusch_allocation_subcarriers(config)
    if len(channel) != allocation:
        raise Error("PUSCH channel estimate does not span the allocation")
    var result = List[Complex64](capacity=nr_pusch_data_re_count(config))
    for symbol in range(config.symbol_count):
        if symbol == config.dmrs_symbol:
            continue
        var received = List[Complex64](capacity=allocation)
        for local in range(allocation):
            received.append(grid[symbol, config.first_subcarrier + local])
        var equalized = zero_forcing_equalize_siso(Span(received), channel)
        if config.transform_precoding:
            var despread = nr_pusch_transform_deprecoding(Span(equalized))
            for value in despread:
                result.append(value)
        else:
            for value in equalized:
                result.append(value)
    return result^


def _pusch_noise_after_zf(
    sample_noise_variance: Float64,
    fft_size: Int,
    channel: Complex64,
) raises -> Float64:
    """Convert sample-domain complex N0 to one post-ZF subcarrier N0.

    The PUSCH OFDM pair uses a ``1/N`` inverse transform and an unscaled
    forward transform.  FFT-bin noise variance is therefore
    ``N * sample_noise_variance`` before equalization and
    ``N * sample_noise_variance / |H[k]|^2`` after ZF.
    """
    var magnitude = channel.magnitude()
    if not isfinite(magnitude) or magnitude <= 0.0:
        raise Error("PUSCH per-tone noise scaling requires non-zero channel")
    var frequency_noise = sample_noise_variance * Float64(fft_size)
    if isfinite(frequency_noise) and frequency_noise > 0.0:
        var direct = frequency_noise / magnitude / magnitude
        if isfinite(direct) and direct > 0.0:
            return direct
    var result = exp(
        log(sample_noise_variance)
        + log(Float64(fft_size))
        - 2.0 * log(magnitude)
    )
    if not isfinite(result) or result <= 0.0:
        raise Error("PUSCH post-ZF per-tone noise variance is unrepresentable")
    return result


def _pusch_per_tone_llrs(
    config: NRPUSCHConfig,
    equalized: Span[Complex64, ...],
    channel: Span[Complex64, ...],
    modulation_order: Int,
    sample_noise_variance: Float64,
) raises -> List[Float64]:
    """Demap CP-OFDM data with explicit post-ZF variance for every tone."""
    if config.transform_precoding:
        raise Error("per-tone PUSCH N0 is defined here only for CP-OFDM")
    var allocation = nr_pusch_allocation_subcarriers(config)
    if len(channel) != allocation or len(equalized) % allocation != 0:
        raise Error("PUSCH per-tone demapper dimensions are inconsistent")
    var result = List[Float64](
        capacity=len(equalized) * modulation_order
    )
    for symbol_index in range(len(equalized)):
        var local = symbol_index % allocation
        var tone_noise = _pusch_noise_after_zf(
            sample_noise_variance,
            config.fft_size,
            Complex64(channel[local].re, channel[local].im),
        )
        var one_sample: List[Complex64] = [
            Complex64(
                equalized[symbol_index].re,
                equalized[symbol_index].im,
            )
        ]
        var tone_llrs = qam_demapper_llr_piecewise(
            Span(one_sample), modulation_order, tone_noise
        )
        for llr in tone_llrs:
            result.append(llr)
    return result^


def nr_pusch_decode_waveform(
    waveform: Span[Complex64, ...],
    config: NRPUSCHConfig,
    encoded_null_mask: Span[UInt8, ...],
    profile: NRLDPCProfile,
    payload_bits: Int,
    modulation_order: Int,
    redundancy_version: Int,
    equalized_noise_variance: Float64 = -1.0,
    *,
    sample_noise_variance: Float64 = -1.0,
    max_iterations: Int = 30,
    normalization: Float64 = 0.8,
    offset: Float64 = 0.0,
    testcase_id: StringSlice = "nr-pusch-rx",
) raises -> NRPUSCHDecodeResult:
    """Execute OFDM RX through UL-SCH LDPC/CB-CRC/TB-CRC checks.

    Existing callers may pass the scalar ``equalized_noise_variance`` after
    SISO ZF.  CP-OFDM sample-domain simulations instead omit that positional
    argument and pass ``sample_noise_variance``.  The latter is converted to
    a distinct ``N * N0 / |H[k]|^2`` for every data tone; exactly one noise
    representation must be positive.  Transform-precoded PUSCH retains the
    scalar interface because deprecoding mixes per-tone noise.
    """
    _validate_pusch_modulation(modulation_order)
    var scalar_noise = (
        isfinite(equalized_noise_variance)
        and equalized_noise_variance > 0.0
    )
    var sample_noise = (
        isfinite(sample_noise_variance) and sample_noise_variance > 0.0
    )
    if payload_bits < 0 or scalar_noise == sample_noise:
        raise Error("invalid PUSCH decoder payload or noise variance")
    if sample_noise and config.transform_precoding:
        raise Error("sample-domain per-tone N0 requires CP-OFDM PUSCH")
    if len(encoded_null_mask) != profile.code_blocks * profile.encoded_bits:
        raise Error("PUSCH LDPC null mask does not match the profile")
    if profile.transport_block_bits != payload_bits + profile.transport_crc_bits:
        raise Error("PUSCH payload length does not match the LDPC profile")

    var grid = nr_pusch_waveform_to_grid(config, waveform)
    var dmrs = nr_pusch_reference_dmrs(config)
    var channel = _pusch_channel_estimate(config, grid, Span(dmrs))
    var equalized = _pusch_equalized_data(config, grid, Span(channel))
    var llrs: List[Float64]
    if sample_noise:
        llrs = _pusch_per_tone_llrs(
            config,
            Span(equalized),
            Span(channel),
            modulation_order,
            sample_noise_variance,
        )
    else:
        llrs = qam_demapper_llr_piecewise(
            Span(equalized), modulation_order, equalized_noise_variance
        )
    var descrambled = nr_pusch_descramble_llrs(
        Span(llrs), config.rnti, config.codeword, config.n_id
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
    var transport_block = desegmented.bits.copy()
    var channel_copy = channel.copy()
    var equalized_copy = equalized.copy()
    var llrs_copy = llrs.copy()
    var descrambled_copy = descrambled.copy()
    var recovered_copy = recovered.copy()
    var iterations = decoded.iterations.copy()
    var checkpoint_metadata = _nr_pusch_rx_checkpoint_metadata(
        testcase_id,
        len(waveform),
        grid.symbol_count,
        grid.subcarrier_count,
        len(channel),
        len(equalized),
        len(llrs),
        len(descrambled),
        len(recovered),
        len(iterations),
        len(transport_block),
        len(payload),
    )
    return NRPUSCHDecodeResult(
        payload^,
        transport_block^,
        grid^,
        channel_copy^,
        equalized_copy^,
        llrs_copy^,
        descrambled_copy^,
        recovered_copy^,
        iterations^,
        checkpoint_metadata^,
        transport_crc_ok,
        desegmented.code_block_crc_ok,
        decoded.converged,
    )
