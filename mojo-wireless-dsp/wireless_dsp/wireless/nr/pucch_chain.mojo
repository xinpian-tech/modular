"""Single-PRB NR PUCCH format-2 CPU reference transmit/receive chain.

This is deliberately a small physical-channel profile rather than a complete
PUCCH implementation.  It covers one layer, exactly one PRB, one or two
consecutive normal-CP symbols, no intra-slot frequency hopping, QPSK, and a
flat complex channel.  UCI coding follows TS 38.212 clause 6.3.1 and physical
scrambling, modulation, DM-RS, and resource mapping follow TS 38.211 clauses
6.3.2.5 and 6.4.1.3.2.

The waveform contains only the configured consecutive PUCCH symbols (not the
otherwise empty portions of a slot), but each symbol uses its standardized
normal-CP length and its absolute slot-relative symbol number for DM-RS.  The
receiver uses a single LS channel estimate averaged over all DM-RS REs.  This
is appropriate for the explicit flat, single-layer profile; frequency-selective
estimation, hopping, multiple PRBs/layers, and PUCCH formats 0/1/3/4 are outside
this module.
"""

from std.collections import Span
from std.math import frexp, isfinite, ldexp, sqrt
from wireless_dsp.channel import add_awgn
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import complex_divide, ofdm_modulate, ofdm_demodulate
from wireless_dsp.modem import qam_map, qam_demapper_llr_piecewise
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
    checkpoint_metadata_2d,
)
from .grid import NRResourceGrid, nr_normal_cp_samples
from .pucch import nr_pucch_scramble, nr_pucch_format2_modulate
from .pucch_resources import (
    nr_pucch_format2_dmrs,
    nr_map_pucch_format2,
    nr_extract_pucch_format2_data,
    nr_extract_pucch_format2_dmrs,
)
from .uci import (
    nr_pucch_uci_capacity,
    nr_uci_encode,
    nr_uci_decode,
)


def _pucch_safe_frexp64(value: Float64) -> Tuple[Float64, Int32]:
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


struct NRPUCCHFormat2Config(ImplicitlyCopyable):
    """Configuration of the supported format-2 waveform profile.

    ``slot_in_frame`` is the numerology-specific slot number in a 10 ms radio
    frame.  ``first_subcarrier`` is an unshifted FFT-bin index and must be PRB
    aligned.  The supported allocation is always one PRB and one layer.
    """

    var fft_size: Int
    var numerology: Int
    var slot_in_frame: Int
    var start_symbol: Int
    var symbol_count: Int
    var first_subcarrier: Int
    var n_id: Int
    var dmrs_n_id: Int
    var rnti: Int

    def __init__(
        out self,
        fft_size: Int,
        numerology: Int,
        slot_in_frame: Int,
        start_symbol: Int,
        symbol_count: Int,
        first_subcarrier: Int,
        n_id: Int,
        dmrs_n_id: Int,
        rnti: Int,
    ) raises:
        if (
            fft_size < 128 or fft_size % 128 != 0
            or (fft_size & (fft_size - 1)) != 0
            or fft_size > Int.MAX // 256
        ):
            raise Error(
                "PUCCH format-2 FFT size must be a power-of-two multiple of 128"
            )
        if numerology < 0 or numerology > 4:
            raise Error("PUCCH format-2 numerology must be in [0,4]")
        if slot_in_frame < 0 or slot_in_frame >= 10 * (1 << numerology):
            raise Error("PUCCH format-2 slot must be within the radio frame")
        if symbol_count < 1 or symbol_count > 2:
            raise Error("PUCCH format 2 occupies one or two OFDM symbols")
        if start_symbol < 0 or start_symbol > 14 - symbol_count:
            raise Error("PUCCH format-2 symbols are outside the normal-CP slot")
        if (
            first_subcarrier < 0 or first_subcarrier % 12 != 0
            or first_subcarrier > fft_size - 12
        ):
            raise Error("PUCCH format-2 one-PRB allocation is invalid")
        if n_id < 0 or n_id > 1023:
            raise Error("PUCCH scrambling identity must be in [0,1023]")
        if dmrs_n_id < 0 or dmrs_n_id > 65535:
            raise Error("PUCCH DM-RS identity must be in [0,65535]")
        if rnti < 0 or rnti > 0xFFFF:
            raise Error("PUCCH RNTI must be in [0,65535]")
        self.fft_size = fft_size
        self.numerology = numerology
        self.slot_in_frame = slot_in_frame
        self.start_symbol = start_symbol
        self.symbol_count = symbol_count
        self.first_subcarrier = first_subcarrier
        self.n_id = n_id
        self.dmrs_n_id = dmrs_n_id
        self.rnti = rnti


struct NRPUCCHFormat2TransmitResult(Movable):
    """UCI-to-waveform checkpoints for the supported format-2 profile."""

    var payload: List[UInt8]
    var coded_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var data_symbols: List[Complex64]
    var dmrs: List[Complex64]
    var grid: NRResourceGrid
    var waveform: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]
    var uci_scheme: Int
    var code_blocks: Int
    var payload_checksum: UInt64
    var coded_bits_checksum: UInt64
    var scrambled_bits_checksum: UInt64
    var grid_energy: Float64
    var waveform_energy: Float64

    def __init__(
        out self,
        var payload: List[UInt8],
        var coded_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var data_symbols: List[Complex64],
        var dmrs: List[Complex64],
        var grid: NRResourceGrid,
        var waveform: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
        uci_scheme: Int,
        code_blocks: Int,
        payload_checksum: UInt64,
        coded_bits_checksum: UInt64,
        scrambled_bits_checksum: UInt64,
        grid_energy: Float64,
        waveform_energy: Float64,
    ):
        self.payload = payload^
        self.coded_bits = coded_bits^
        self.scrambled_bits = scrambled_bits^
        self.data_symbols = data_symbols^
        self.dmrs = dmrs^
        self.grid = grid^
        self.waveform = waveform^
        self.checkpoint_metadata = checkpoint_metadata^
        self.uci_scheme = uci_scheme
        self.code_blocks = code_blocks
        self.payload_checksum = payload_checksum
        self.coded_bits_checksum = coded_bits_checksum
        self.scrambled_bits_checksum = scrambled_bits_checksum
        self.grid_energy = grid_energy
        self.waveform_energy = waveform_energy


struct NRPUCCHFormat2DecodeResult(Movable):
    """Waveform-to-UCI checkpoints and quality/status measurements."""

    var payload: List[UInt8]
    var grid: NRResourceGrid
    var received_dmrs: List[Complex64]
    var dmrs_ls_estimates: List[Complex64]
    var channel_estimate: Complex64
    var equalized_symbols: List[Complex64]
    var raw_llrs: List[Float64]
    var descrambled_llrs: List[Float64]
    var hard_coded_bits: List[UInt8]
    var checkpoint_metadata: List[CheckpointMetadata]
    var uci_scheme: Int
    var code_blocks: Int
    var crc_ok: Bool
    var parity_ok: Bool
    var hard_coded_bits_checksum: UInt64
    var equalized_noise_variance: Float64
    var decision_directed_evm: Float64
    var maximum_symbol_error: Float64

    def __init__(
        out self,
        var payload: List[UInt8],
        var grid: NRResourceGrid,
        var received_dmrs: List[Complex64],
        var dmrs_ls_estimates: List[Complex64],
        channel_estimate: Complex64,
        var equalized_symbols: List[Complex64],
        var raw_llrs: List[Float64],
        var descrambled_llrs: List[Float64],
        var hard_coded_bits: List[UInt8],
        var checkpoint_metadata: List[CheckpointMetadata],
        uci_scheme: Int,
        code_blocks: Int,
        crc_ok: Bool,
        parity_ok: Bool,
        hard_coded_bits_checksum: UInt64,
        equalized_noise_variance: Float64,
        decision_directed_evm: Float64,
        maximum_symbol_error: Float64,
    ):
        self.payload = payload^
        self.grid = grid^
        self.received_dmrs = received_dmrs^
        self.dmrs_ls_estimates = dmrs_ls_estimates^
        self.channel_estimate = channel_estimate
        self.equalized_symbols = equalized_symbols^
        self.raw_llrs = raw_llrs^
        self.descrambled_llrs = descrambled_llrs^
        self.hard_coded_bits = hard_coded_bits^
        self.checkpoint_metadata = checkpoint_metadata^
        self.uci_scheme = uci_scheme
        self.code_blocks = code_blocks
        self.crc_ok = crc_ok
        self.parity_ok = parity_ok
        self.hard_coded_bits_checksum = hard_coded_bits_checksum
        self.equalized_noise_variance = equalized_noise_variance
        self.decision_directed_evm = decision_directed_evm
        self.maximum_symbol_error = maximum_symbol_error


def _nr_pucch_format2_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    payload: Int,
    coded_bits: Int,
    scrambled_bits: Int,
    data_symbols: Int,
    dmrs: Int,
    grid_rows: Int,
    grid_columns: Int,
    waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=7)
    for stage, length in [
        ("payload", payload),
        ("coded-bits", coded_bits),
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
    for stage, length in [
        ("data-symbols", data_symbols),
        ("dmrs", dmrs),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "complex64",
            length,
            layout="iq-interleaved",
        ))
    result.append(checkpoint_metadata_2d(
        testcase_id,
        "transmit-grid",
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


def _nr_pucch_format2_rx_checkpoint_metadata(
    testcase_id: StringSlice,
    grid_rows: Int,
    grid_columns: Int,
    received_dmrs: Int,
    dmrs_ls_estimates: Int,
    equalized_symbols: Int,
    raw_llrs: Int,
    descrambled_llrs: Int,
    hard_coded_bits: Int,
    payload: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=9)
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
        "received-dmrs",
        "complex64",
        received_dmrs,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "dmrs-ls-estimates",
        "complex64",
        dmrs_ls_estimates,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "channel-estimate",
        "complex64",
        1,
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
        testcase_id, "raw-llrs", "float64", raw_llrs
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "descrambled-llrs", "float64", descrambled_llrs
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "hard-coded-bits",
        "uint8",
        hard_coded_bits,
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


def nr_pucch_format2_coded_bit_capacity(
    config: NRPUCCHFormat2Config
) raises -> Int:
    """Return E for one PRB of format 2 (16 QPSK bits per symbol)."""
    return nr_pucch_uci_capacity(2, 1, config.symbol_count)


def nr_pucch_format2_bits_checksum(bits: Span[UInt8, ...]) raises -> UInt64:
    """Return a deterministic FNV-1a checksum for a binary checkpoint."""
    var result = UInt64(14695981039346656037)
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("PUCCH checkpoint input must be binary")
        result ^= UInt64(bits[index])
        result *= UInt64(1099511628211)
    return result


def _complex_energy(values: Span[Complex64, ...]) -> Float64:
    var energy = 0.0
    for index in range(len(values)):
        var value = Complex64(values[index].re, values[index].im)
        energy += value.magnitude_squared()
    return energy


def _grid_energy(grid: NRResourceGrid) -> Float64:
    return _complex_energy(Span(grid.values))


def _symbol_error(
    actual: Span[Complex64, ...], reference: Span[Complex64, ...]
) raises -> Tuple[Float64, Float64]:
    if len(actual) == 0 or len(actual) != len(reference):
        raise Error("PUCCH EVM vectors must be equal and non-empty")
    var error_energy = 0.0
    var reference_energy = 0.0
    var maximum_squared = 0.0
    for index in range(len(actual)):
        var actual_value = Complex64(actual[index].re, actual[index].im)
        var reference_value = Complex64(
            reference[index].re, reference[index].im
        )
        var dr = actual_value.re - reference_value.re
        var di = actual_value.im - reference_value.im
        var error = dr * dr + di * di
        error_energy += error
        reference_energy += reference_value.magnitude_squared()
        maximum_squared = max(maximum_squared, error)
    if reference_energy <= 0.0:
        raise Error("PUCCH EVM reference has zero energy")
    return (
        sqrt(error_energy / reference_energy), sqrt(maximum_squared)
    )


def nr_pucch_format2_reference_dmrs(
    config: NRPUCCHFormat2Config
) raises -> List[Complex64]:
    """Generate all four-per-symbol DM-RS values in grid mapping order."""
    var result = List[Complex64](capacity=4 * config.symbol_count)
    for local_symbol in range(config.symbol_count):
        var dmrs = nr_pucch_format2_dmrs(
            config.slot_in_frame,
            config.start_symbol + local_symbol,
            config.dmrs_n_id,
            1,
        )
        for value in dmrs:
            result.append(value)
    return result^


def nr_pucch_format2_waveform_sample_count(
    config: NRPUCCHFormat2Config
) raises -> Int:
    """Return the samples in the allocation-only, normal-CP waveform."""
    var result = 0
    var slot_in_subframe = config.slot_in_frame % (1 << config.numerology)
    for local_symbol in range(config.symbol_count):
        result += config.fft_size + nr_normal_cp_samples(
            config.fft_size,
            config.start_symbol + local_symbol,
            config.numerology,
            slot_in_subframe=slot_in_subframe,
        )
    return result


def nr_pucch_format2_grid_to_waveform(
    config: NRPUCCHFormat2Config, grid: NRResourceGrid
) raises -> List[Complex64]:
    """OFDM-modulate the one/two configured grid rows with normal CP."""
    if grid.symbol_count != 14 or grid.subcarrier_count != config.fft_size:
        raise Error("PUCCH format-2 grid dimensions do not match the config")
    var result = List[Complex64](
        capacity=nr_pucch_format2_waveform_sample_count(config)
    )
    var slot_in_subframe = config.slot_in_frame % (1 << config.numerology)
    for local_symbol in range(config.symbol_count):
        var symbol = config.start_symbol + local_symbol
        var spectrum = List[Complex64](capacity=config.fft_size)
        for subcarrier in range(config.fft_size):
            spectrum.append(grid[symbol, subcarrier])
        var cyclic_prefix = nr_normal_cp_samples(
            config.fft_size,
            symbol,
            config.numerology,
            slot_in_subframe=slot_in_subframe,
        )
        var samples = ofdm_modulate(Span(spectrum), cyclic_prefix)
        for value in samples:
            if not isfinite(value.re) or not isfinite(value.im):
                raise Error("PUCCH waveform samples must remain finite")
            result.append(value)
    return result^


def nr_pucch_format2_waveform_to_grid(
    config: NRPUCCHFormat2Config, waveform: Span[Complex64, ...]
) raises -> NRResourceGrid:
    """Split the allocation-only waveform, remove normal CP, and FFT it."""
    if len(waveform) != nr_pucch_format2_waveform_sample_count(config):
        raise Error("PUCCH format-2 waveform length does not match the config")
    for index in range(len(waveform)):
        if not isfinite(waveform[index].re) or not isfinite(waveform[index].im):
            raise Error("PUCCH waveform samples must be finite")
    var grid = NRResourceGrid(14, config.fft_size)
    var slot_in_subframe = config.slot_in_frame % (1 << config.numerology)
    var offset = 0
    for local_symbol in range(config.symbol_count):
        var symbol = config.start_symbol + local_symbol
        var cyclic_prefix = nr_normal_cp_samples(
            config.fft_size,
            symbol,
            config.numerology,
            slot_in_subframe=slot_in_subframe,
        )
        var samples_per_symbol = config.fft_size + cyclic_prefix
        var samples = List[Complex64](capacity=samples_per_symbol)
        for index in range(samples_per_symbol):
            samples.append(waveform[offset + index])
        var spectrum = ofdm_demodulate(
            Span(samples), config.fft_size, cyclic_prefix
        )
        for subcarrier in range(config.fft_size):
            if (
                not isfinite(spectrum[subcarrier].re)
                or not isfinite(spectrum[subcarrier].im)
            ):
                raise Error("PUCCH FFT output must remain finite")
            grid[symbol, subcarrier] = spectrum[subcarrier]
        offset += samples_per_symbol
    return grid^


def nr_pucch_format2_encode(
    payload: Span[UInt8, ...],
    config: NRPUCCHFormat2Config,
    *,
    testcase_id: StringSlice = "nr-pucch-format2-tx",
) raises -> NRPUCCHFormat2TransmitResult:
    """Execute UCI channel coding through normal-CP waveform generation."""
    var capacity = nr_pucch_format2_coded_bit_capacity(config)
    var encoded = nr_uci_encode(payload, capacity)
    var coded_bits = encoded.bits.copy()
    var scrambled_bits = nr_pucch_scramble(
        Span(coded_bits), config.rnti, config.n_id
    )
    var data_symbols = nr_pucch_format2_modulate(
        Span(coded_bits), config.rnti, config.n_id
    )
    var dmrs = nr_pucch_format2_reference_dmrs(config)
    var grid = NRResourceGrid(14, config.fft_size)
    nr_map_pucch_format2(
        grid,
        config.start_symbol,
        config.first_subcarrier,
        1,
        config.symbol_count,
        Span(data_symbols),
        Span(dmrs),
    )
    var waveform = nr_pucch_format2_grid_to_waveform(config, grid)
    var payload_copy = List[UInt8](capacity=len(payload))
    for index in range(len(payload)):
        payload_copy.append(payload[index])
    var payload_checksum = nr_pucch_format2_bits_checksum(Span(payload_copy))
    var coded_checksum = nr_pucch_format2_bits_checksum(Span(coded_bits))
    var scrambled_checksum = nr_pucch_format2_bits_checksum(
        Span(scrambled_bits)
    )
    var grid_energy = _grid_energy(grid)
    var waveform_energy = _complex_energy(Span(waveform))
    var checkpoint_metadata = _nr_pucch_format2_tx_checkpoint_metadata(
        testcase_id,
        len(payload_copy),
        len(coded_bits),
        len(scrambled_bits),
        len(data_symbols),
        len(dmrs),
        grid.symbol_count,
        grid.subcarrier_count,
        len(waveform),
    )
    return NRPUCCHFormat2TransmitResult(
        payload_copy^,
        coded_bits^,
        scrambled_bits^,
        data_symbols^,
        dmrs^,
        grid^,
        waveform^,
        checkpoint_metadata^,
        encoded.scheme,
        encoded.code_blocks,
        payload_checksum,
        coded_checksum,
        scrambled_checksum,
        grid_energy,
        waveform_energy,
    )


def nr_pucch_format2_flat_channel(
    waveform: Span[Complex64, ...],
    gain: Complex64,
    *,
    noise_variance: Float64 = 0.0,
    seed: UInt64 = UInt64(1),
) raises -> List[Complex64]:
    """Apply a constant complex gain and optional seeded time-domain AWGN."""
    if (
        len(waveform) == 0
        or not isfinite(gain.re)
        or not isfinite(gain.im)
        or (gain.re == 0.0 and gain.im == 0.0)
    ):
        raise Error("PUCCH flat channel requires samples and non-zero gain")
    if not isfinite(noise_variance) or noise_variance < 0.0:
        raise Error(
            "PUCCH flat-channel noise variance must be finite and non-negative"
        )
    var faded = List[Complex64](capacity=len(waveform))
    for index in range(len(waveform)):
        var sample = Complex64(waveform[index].re, waveform[index].im)
        if not isfinite(sample.re) or not isfinite(sample.im):
            raise Error("PUCCH flat-channel samples must be finite")
        var output = sample * gain
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("PUCCH flat-channel output is not representable")
        faded.append(output)
    return add_awgn(Span(faded), noise_variance, seed=seed)


def _mean_complex_scaled(values: Span[Complex64, ...]) raises -> Complex64:
    if len(values) == 0:
        raise Error("complex mean requires at least one value")
    var scale = 0.0
    for index in range(len(values)):
        var value = values[index]
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("complex mean inputs must be finite")
        scale = max(scale, abs(value.re))
        scale = max(scale, abs(value.im))
    if scale == 0.0:
        return Complex64(0.0, 0.0)
    var real = 0.0
    var imag = 0.0
    for index in range(len(values)):
        var value = values[index]
        real += value.re / scale
        imag += value.im / scale
    var inverse_count = 1.0 / Float64(len(values))
    return Complex64(
        scale * real * inverse_count,
        scale * imag * inverse_count,
    )


def _equalized_noise_variance_scaled(
    sample_noise_variance: Float64,
    fft_size: Int,
    channel: Complex64,
) raises -> Float64:
    if sample_noise_variance == 0.0:
        return 1.0e-12
    var channel_scale = max(abs(channel.re), abs(channel.im))
    if channel_scale == 0.0:
        raise Error("PUCCH flat channel estimate is singular")
    var normalized_re = channel.re / channel_scale
    var normalized_im = channel.im / channel_scale
    var normalized_energy = (
        normalized_re * normalized_re + normalized_im * normalized_im
    )
    var noise_parts = _pucch_safe_frexp64(sample_noise_variance)
    var fft_parts = _pucch_safe_frexp64(Float64(fft_size))
    var channel_parts = _pucch_safe_frexp64(channel_scale)
    var energy_parts = _pucch_safe_frexp64(normalized_energy)
    var mantissa = (
        noise_parts[0] * fft_parts[0]
        / (
            channel_parts[0]
            * channel_parts[0]
            * energy_parts[0]
        )
    )
    var exponent = (
        noise_parts[1] + fft_parts[1]
        - 2 * channel_parts[1] - energy_parts[1]
    )
    var canonical = _pucch_safe_frexp64(mantissa)
    mantissa = canonical[0]
    exponent += canonical[1]
    if exponent <= -1022:
        return 1.0e-12
    if exponent > 1024:
        raise Error("PUCCH equalized noise variance is not representable")
    var result = (
        ldexp(mantissa, Int32(1023)) * 2.0
        if exponent == 1024
        else ldexp(mantissa, exponent)
    )
    if not isfinite(result) or result < 0.0:
        raise Error("PUCCH equalized noise variance is not representable")
    return max(result, 1.0e-12)


def nr_pucch_format2_descramble_llrs(
    llrs: Span[Float64, ...], rnti: Int, n_id: Int
) raises -> List[Float64]:
    """Undo format-2 Gold scrambling by changing soft-value signs."""
    var zeros = List[UInt8](length=len(llrs), fill=UInt8(0))
    var sequence = nr_pucch_scramble(Span(zeros), rnti, n_id)
    var result = List[Float64](capacity=len(llrs))
    for index in range(len(llrs)):
        if not isfinite(llrs[index]):
            raise Error("PUCCH descrambling LLRs must be finite")
        result.append(
            llrs[index] if sequence[index] == 0 else -llrs[index]
        )
    return result^


def _hard_bits(llrs: Span[Float64, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=len(llrs))
    for index in range(len(llrs)):
        result.append(UInt8(0) if llrs[index] >= 0.0 else UInt8(1))
    return result^


def nr_pucch_format2_decode(
    waveform: Span[Complex64, ...],
    config: NRPUCCHFormat2Config,
    payload_bits: Int,
    sample_noise_variance: Float64,
    *,
    testcase_id: StringSlice = "nr-pucch-format2-rx",
) raises -> NRPUCCHFormat2DecodeResult:
    """Execute FFT/flat-LS/ZF/soft demapping through UCI decoding.

    ``sample_noise_variance`` is E[|n|^2] before the FFT.  Since this package's
    forward FFT is unnormalised, the QPSK demapper uses
    ``fft_size*sample_noise_variance/|h_hat|^2``.  A tiny positive floor makes
    the exactly noiseless reference path legal for the soft demapper.
    """
    if (
        payload_bits < 3
        or not isfinite(sample_noise_variance)
        or sample_noise_variance < 0.0
    ):
        raise Error("invalid PUCCH payload length or sample-noise variance")
    var grid = nr_pucch_format2_waveform_to_grid(config, waveform)
    var received_data = nr_extract_pucch_format2_data(
        grid,
        config.start_symbol,
        config.first_subcarrier,
        1,
        config.symbol_count,
    )
    var received_dmrs = nr_extract_pucch_format2_dmrs(
        grid,
        config.start_symbol,
        config.first_subcarrier,
        1,
        config.symbol_count,
    )
    var known_dmrs = nr_pucch_format2_reference_dmrs(config)
    var ls_estimates = List[Complex64](capacity=len(known_dmrs))
    for index in range(len(known_dmrs)):
        var estimate = complex_divide(
            Complex64(received_dmrs[index].re, received_dmrs[index].im),
            Complex64(known_dmrs[index].re, known_dmrs[index].im),
        )
        ls_estimates.append(estimate)
    var channel_estimate = _mean_complex_scaled(Span(ls_estimates))
    if channel_estimate.re == 0.0 and channel_estimate.im == 0.0:
        raise Error("PUCCH flat channel estimate is singular")
    var equalized = List[Complex64](capacity=len(received_data))
    for value in received_data:
        equalized.append(complex_divide(value, channel_estimate))

    var equalized_noise_variance = _equalized_noise_variance_scaled(
        sample_noise_variance, config.fft_size, channel_estimate
    )
    var raw_llrs = qam_demapper_llr_piecewise(
        Span(equalized), 2, equalized_noise_variance
    )
    var descrambled_llrs = nr_pucch_format2_descramble_llrs(
        Span(raw_llrs), config.rnti, config.n_id
    )
    var hard_coded_bits = _hard_bits(Span(descrambled_llrs))
    var hard_scrambled_bits = _hard_bits(Span(raw_llrs))
    var decisions = qam_map(Span(hard_scrambled_bits), 2)
    var evm, maximum_error = _symbol_error(
        Span(equalized), Span(decisions)
    )
    var decoded = nr_uci_decode(Span(descrambled_llrs), payload_bits)
    var payload = decoded.bits.copy()
    var hard_checksum = nr_pucch_format2_bits_checksum(
        Span(hard_coded_bits)
    )
    var checkpoint_metadata = _nr_pucch_format2_rx_checkpoint_metadata(
        testcase_id,
        grid.symbol_count,
        grid.subcarrier_count,
        len(received_dmrs),
        len(ls_estimates),
        len(equalized),
        len(raw_llrs),
        len(descrambled_llrs),
        len(hard_coded_bits),
        len(payload),
    )
    return NRPUCCHFormat2DecodeResult(
        payload^,
        grid^,
        received_dmrs^,
        ls_estimates^,
        channel_estimate,
        equalized^,
        raw_llrs^,
        descrambled_llrs^,
        hard_coded_bits^,
        checkpoint_metadata^,
        decoded.scheme,
        decoded.code_blocks,
        decoded.crc_ok,
        decoded.parity_ok,
        hard_checksum,
        equalized_noise_variance,
        evm,
        maximum_error,
    )
