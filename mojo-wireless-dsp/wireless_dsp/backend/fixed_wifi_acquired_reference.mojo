"""Bounded, connected fixed-point legacy Wi-Fi acquisition reference.

This module closes the timing boundary intentionally left open by
``fixed_wifi_legacy_reference``.  It builds the standard twelve-tone legacy
L-STF as an integer QPSK-like spectrum, runs the fixed radix-2 IFFT once, and
repeats its exact 16-sample short symbol ten times.  An integer timing prefix
is inserted before the complete ``L-STF | L-LTF | DATA`` waveform and the
whole packet traverses one fixed flat channel operation.

The receiver scans a fixed 96-sample search aperture with the integer
16-sample repetition correlator.  The selected boundary, rather than the
transmit timing control, determines the L-LTF and DATA slices used by the
fixed LS, ZF, QPSK-LLR, deinterleaver, soft Viterbi, descrambler, and FCS
pipeline.  Exact equality with the older known-timing reference is retained
only as a composition oracle after the acquired decode has completed.

Scope is deliberately narrow and honest: 20 MHz legacy QPSK, K=7 rate-1/2
BCC, a flat complex channel, integer timing in [0, 64], and zero CFO/noise.
It is not a complete IEEE 802.11 PPDU (there is no L-SIG) and it does not
claim a frequency-selective estimator or a fixed-point phase rotator.
"""

from std.collections import Span
from wireless_dsp.numerics.fixed import (
    OVERFLOW_SATURATE,
    ROUND_NEAREST_AWAY,
)
from wireless_dsp.numerics.quantization import (
    QFormat,
    narrow_raw,
    rounded_shift_right,
)
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.scale_schedule import (
    ScaleStage,
    ScaleTrace,
    apply_scale_schedule,
)
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYFormats,
    fixed_equalize_flat_raw,
    fixed_flat_channel_raw,
    fixed_ls_flat_channel_raw,
    fixed_ofdm_demodulate_raw,
    fixed_ofdm_modulate_raw,
    fixed_qpsk_llrs_raw,
)
from wireless_dsp.backend.fixed_sync_reference import (
    FixedRepetitionScanResult,
    fixed_repetition_scan_checksum,
    fixed_repetition_scan_raw,
)
from wireless_dsp.backend.fixed_wifi_bcc_reference import (
    FixedWifiBCCDecodeResult,
    FixedWifiBCCViterbiConfig,
    fixed_wifi_bcc_viterbi_decode_soft,
)
from wireless_dsp.backend.fixed_wifi_legacy_reference import (
    FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
    FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL,
    FIXED_WIFI_LEGACY_FCS_BITS,
    FIXED_WIFI_LEGACY_MAX_PSDU_OCTETS,
    FIXED_WIFI_LEGACY_SERVICE_BITS,
    FIXED_WIFI_LEGACY_TAIL_BITS,
    FixedWifiLegacyResult,
    fixed_wifi_legacy_canonical_rtl_vectors,
    fixed_wifi_legacy_reference,
    fixed_wifi_legacy_result_checksum,
)
from wireless_dsp.testing.fixed_vectors import (
    complex_raw_checksum,
    fixed_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
    serialize_scale_trace,
)
from wireless_dsp.wireless.wifi.legacy import (
    wifi_data_subcarriers,
    wifi_fcs,
    wifi_scramble,
)


comptime FIXED_WIFI_ACQUIRED_STF_PERIOD = 16
comptime FIXED_WIFI_ACQUIRED_STF_SAMPLES = 160
comptime FIXED_WIFI_ACQUIRED_LTF_SAMPLES = 160
comptime FIXED_WIFI_ACQUIRED_MAX_TIMING_OFFSET = 64
comptime FIXED_WIFI_ACQUIRED_SYNC_SEARCH_SAMPLES = 96
comptime _STF_SCALE_Q16_RAW = 96466  # round(sqrt(13/6) * 2^16)


struct FixedWifiAcquiredRxResult(Movable):
    """Detection, acquired slices, and every integer receive checkpoint."""

    var sync_search_samples: List[ComplexRaw]
    var sync: FixedRepetitionScanResult
    var packet_start: Int
    var ltf_start: Int
    var data_start: Int
    var ltf_observation: List[ComplexRaw]
    var data_observation: List[ComplexRaw]
    var ltf_received_bins: List[ComplexRaw]
    var channel_estimate: ComplexRaw
    var data_received_bins: List[ComplexRaw]
    var equalized_data_symbols: List[ComplexRaw]
    var interleaved_llrs_raw: List[Int64]
    var deinterleaved_llrs_raw: List[Int64]
    var soft_viterbi: FixedWifiBCCDecodeResult
    var descrambled_data_bits: List[UInt8]
    var recovered_payload_bytes: List[UInt8]
    var recovered_fcs_bits: List[UInt8]
    var fcs_expected: UInt64
    var fcs_recovered: UInt64
    var fcs_ok: Bool
    var service_ok: Bool
    var tail_ok: Bool
    var payload_byte_errors: Int

    def __init__(
        out self,
        var sync_search_samples: List[ComplexRaw],
        var sync: FixedRepetitionScanResult,
        packet_start: Int,
        ltf_start: Int,
        data_start: Int,
        var ltf_observation: List[ComplexRaw],
        var data_observation: List[ComplexRaw],
        var ltf_received_bins: List[ComplexRaw],
        channel_estimate: ComplexRaw,
        var data_received_bins: List[ComplexRaw],
        var equalized_data_symbols: List[ComplexRaw],
        var interleaved_llrs_raw: List[Int64],
        var deinterleaved_llrs_raw: List[Int64],
        var soft_viterbi: FixedWifiBCCDecodeResult,
        var descrambled_data_bits: List[UInt8],
        var recovered_payload_bytes: List[UInt8],
        var recovered_fcs_bits: List[UInt8],
        fcs_expected: UInt64,
        fcs_recovered: UInt64,
        fcs_ok: Bool,
        service_ok: Bool,
        tail_ok: Bool,
        payload_byte_errors: Int,
    ):
        self.sync_search_samples = sync_search_samples^
        self.sync = sync^
        self.packet_start = packet_start
        self.ltf_start = ltf_start
        self.data_start = data_start
        self.ltf_observation = ltf_observation^
        self.data_observation = data_observation^
        self.ltf_received_bins = ltf_received_bins^
        self.channel_estimate = channel_estimate
        self.data_received_bins = data_received_bins^
        self.equalized_data_symbols = equalized_data_symbols^
        self.interleaved_llrs_raw = interleaved_llrs_raw^
        self.deinterleaved_llrs_raw = deinterleaved_llrs_raw^
        self.soft_viterbi = soft_viterbi^
        self.descrambled_data_bits = descrambled_data_bits^
        self.recovered_payload_bytes = recovered_payload_bytes^
        self.recovered_fcs_bits = recovered_fcs_bits^
        self.fcs_expected = fcs_expected
        self.fcs_recovered = fcs_recovered
        self.fcs_ok = fcs_ok
        self.service_ok = service_ok
        self.tail_ok = tail_ok
        self.payload_byte_errors = payload_byte_errors


struct FixedWifiAcquiredResult(Movable):
    """Transmit, channel, synchronization, acquired RX, and scale evidence."""

    var known_timing_audit: FixedWifiLegacyResult
    var stf_grid: List[ComplexRaw]
    var stf_ifft_samples: List[ComplexRaw]
    var stf_short_symbol: List[ComplexRaw]
    var stf_transmit_samples: List[ComplexRaw]
    var packet_transmit_samples: List[ComplexRaw]
    var packet_channel_samples: List[ComplexRaw]
    var observation: List[ComplexRaw]
    var timing_offset: Int
    var rx: FixedWifiAcquiredRxResult
    var ifft_scale_trace: ScaleTrace
    var fft_scale_trace: ScaleTrace
    var composition_matches_known_timing: Bool

    def __init__(
        out self,
        var known_timing_audit: FixedWifiLegacyResult,
        var stf_grid: List[ComplexRaw],
        var stf_ifft_samples: List[ComplexRaw],
        var stf_short_symbol: List[ComplexRaw],
        var stf_transmit_samples: List[ComplexRaw],
        var packet_transmit_samples: List[ComplexRaw],
        var packet_channel_samples: List[ComplexRaw],
        var observation: List[ComplexRaw],
        timing_offset: Int,
        var rx: FixedWifiAcquiredRxResult,
        var ifft_scale_trace: ScaleTrace,
        var fft_scale_trace: ScaleTrace,
        composition_matches_known_timing: Bool,
    ):
        self.known_timing_audit = known_timing_audit^
        self.stf_grid = stf_grid^
        self.stf_ifft_samples = stf_ifft_samples^
        self.stf_short_symbol = stf_short_symbol^
        self.stf_transmit_samples = stf_transmit_samples^
        self.packet_transmit_samples = packet_transmit_samples^
        self.packet_channel_samples = packet_channel_samples^
        self.observation = observation^
        self.timing_offset = timing_offset
        self.rx = rx^
        self.ifft_scale_trace = ifft_scale_trace^
        self.fft_scale_trace = fft_scale_trace^
        self.composition_matches_known_timing = composition_matches_known_timing


def _bin(subcarrier: Int) -> Int:
    return subcarrier if subcarrier >= 0 else 64 + subcarrier


def _validate_formats(formats: FixedPHYFormats) raises:
    for qformat in [
        formats.symbol,
        formats.time,
        formats.channel,
        formats.frequency,
        formats.accumulator,
        formats.reciprocal,
        formats.twiddle,
    ]:
        if qformat.rounding_mode != ROUND_NEAREST_AWAY:
            raise Error("fixed acquired Wi-Fi requires nearest-away rounding")
        if qformat.overflow_mode != OVERFLOW_SATURATE:
            raise Error("fixed acquired Wi-Fi rejects wrap arithmetic")
    if (
        formats.symbol.storage_bits != 18
        or formats.symbol.fraction_bits != 14
        or formats.time.storage_bits != 18
        or formats.time.fraction_bits != 14
        or formats.channel.storage_bits != 18
        or formats.channel.fraction_bits != 14
        or formats.frequency.storage_bits != 24
        or formats.frequency.fraction_bits != 14
        or formats.accumulator.storage_bits != 30
        or formats.accumulator.fraction_bits != 20
        or formats.reciprocal.storage_bits != 24
        or formats.reciprocal.fraction_bits != 18
        or formats.twiddle.storage_bits != 18
        or formats.twiddle.fraction_bits != 16
    ):
        raise Error("fixed acquired Wi-Fi requires the audited default Q contract")


def _copy_complex(
    values: Span[ComplexRaw, ...], offset: Int, count: Int
) raises -> List[ComplexRaw]:
    if (
        offset < 0
        or count < 0
        or count > len(values)
        or offset > len(values) - count
    ):
        raise Error("fixed acquired Wi-Fi complex slice is out of range")
    var result = List[ComplexRaw](capacity=count)
    for index in range(count):
        result.append(
            ComplexRaw(values[offset + index].re, values[offset + index].im)
        )
    return result^


def _copy_i64(
    values: Span[Int64, ...], offset: Int, count: Int
) raises -> List[Int64]:
    if (
        offset < 0
        or count < 0
        or count > len(values)
        or offset > len(values) - count
    ):
        raise Error("fixed acquired Wi-Fi LLR slice is out of range")
    var result = List[Int64](capacity=count)
    for index in range(count):
        result.append(values[offset + index])
    return result^


def _copy_bits(
    values: Span[UInt8, ...], offset: Int, count: Int
) raises -> List[UInt8]:
    if (
        offset < 0
        or count < 0
        or count > len(values)
        or offset > len(values) - count
    ):
        raise Error("fixed acquired Wi-Fi bit slice is out of range")
    var result = List[UInt8](capacity=count)
    for index in range(count):
        result.append(values[offset + index])
    return result^


def _octets_to_bits(values: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * len(values))
    for value_index in range(len(values)):
        for bit_index in range(8):
            result.append(
                UInt8((values[value_index] >> UInt8(bit_index)) & 1)
            )
    return result^


def _bits_to_octets(values: Span[UInt8, ...]) raises -> List[UInt8]:
    if len(values) % 8 != 0:
        raise Error("fixed acquired Wi-Fi octet conversion needs full bytes")
    var result = List[UInt8](capacity=len(values) // 8)
    for offset in range(0, len(values), 8):
        var octet = UInt8(0)
        for bit_index in range(8):
            if values[offset + bit_index] > 1:
                raise Error("fixed acquired Wi-Fi bits must be binary")
            octet |= values[offset + bit_index] << UInt8(bit_index)
        result.append(octet)
    return result^


def _bits_to_u32(values: Span[UInt8, ...]) raises -> UInt64:
    if len(values) != FIXED_WIFI_LEGACY_FCS_BITS:
        raise Error("fixed acquired Wi-Fi FCS must contain 32 bits")
    var result = UInt64(0)
    for bit_index in range(FIXED_WIFI_LEGACY_FCS_BITS):
        if values[bit_index] > 1:
            raise Error("fixed acquired Wi-Fi FCS bits must be binary")
        result |= UInt64(values[bit_index]) << UInt64(bit_index)
    return result


def _deinterleave_llrs(block: Span[Int64, ...]) raises -> List[Int64]:
    if len(block) != FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL:
        raise Error("fixed acquired Wi-Fi LLR block must contain 96 values")
    comptime n_cbps = FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL
    var result = List[Int64](length=n_cbps, fill=Int64(0))
    for k in range(n_cbps):
        # QPSK has s=1, so the standard second permutation is the identity.
        var first = (n_cbps // 16) * (k % 16) + k // 16
        result[k] = block[first]
    return result^


def _stf_tone_amplitude_raw(
    reference_amplitude_raw: Int64, formats: FixedPHYFormats
) raises -> Int64:
    if reference_amplitude_raw < 1:
        raise Error("fixed acquired Wi-Fi STF reference amplitude must be positive")
    var value = rounded_shift_right(
        reference_amplitude_raw * Int64(_STF_SCALE_Q16_RAW),
        16,
        ROUND_NEAREST_AWAY,
    )
    if value > formats.symbol.max_raw():
        raise Error("fixed acquired Wi-Fi STF tone exceeds the symbol format")
    return value


def _build_stf(
    reference_amplitude_raw: Int64, formats: FixedPHYFormats
) raises -> Tuple[
    List[ComplexRaw], List[ComplexRaw], List[ComplexRaw], List[ComplexRaw]
]:
    var amplitude = _stf_tone_amplitude_raw(
        reference_amplitude_raw, formats
    )
    var grid = List[ComplexRaw](length=64, fill=ComplexRaw())
    # IEEE legacy STF signs in unshifted FFT-bin order.  All occupied tones
    # are multiples of four, so the 64-point IFFT is 16-sample periodic.
    for tone in [-24, -16, -4, 12, 16, 20, 24]:
        grid[_bin(tone)] = ComplexRaw(amplitude, amplitude)
    for tone in [-20, -12, -8, 4, 8]:
        grid[_bin(tone)] = ComplexRaw(-amplitude, -amplitude)
    var ifft = fixed_ofdm_modulate_raw(
        Span(grid),
        formats.symbol,
        formats.time,
        formats.twiddle,
        0,
    )
    if len(ifft) != 64:
        raise Error("fixed acquired Wi-Fi STF IFFT length is invalid")
    var short = _copy_complex(Span(ifft), 0, FIXED_WIFI_ACQUIRED_STF_PERIOD)
    for index in range(64):
        var expected = short[index % FIXED_WIFI_ACQUIRED_STF_PERIOD]
        if ifft[index] != expected:
            raise Error("fixed acquired Wi-Fi STF IFFT lost exact 16-sample periodicity")
    var waveform = List[ComplexRaw](capacity=FIXED_WIFI_ACQUIRED_STF_SAMPLES)
    for _ in range(10):
        for sample in short:
            waveform.append(sample)
    return (grid^, ifft^, short^, waveform^)


def _estimate_ltf_channel(
    received_samples: Span[ComplexRaw, ...],
    ltf_grid: Span[ComplexRaw, ...],
    formats: FixedPHYFormats,
) raises -> Tuple[List[ComplexRaw], ComplexRaw]:
    if (
        len(received_samples) != FIXED_WIFI_ACQUIRED_LTF_SAMPLES
        or len(ltf_grid) != 64
    ):
        raise Error("fixed acquired Wi-Fi L-LTF dimensions are invalid")
    var first_time = _copy_complex(received_samples, 32, 64)
    var second_time = _copy_complex(received_samples, 96, 64)
    var first_bins = fixed_ofdm_demodulate_raw(
        Span(first_time), 64, 0, formats.time, formats.frequency, formats.twiddle
    )
    var second_bins = fixed_ofdm_demodulate_raw(
        Span(second_time), 64, 0, formats.time, formats.frequency, formats.twiddle
    )
    var averaged = List[ComplexRaw](capacity=64)
    for index in range(64):
        averaged.append(
            ComplexRaw(
                narrow_raw(
                    rounded_shift_right(
                        first_bins[index].re + second_bins[index].re,
                        1,
                        formats.frequency.rounding_mode,
                    ),
                    formats.frequency,
                ),
                narrow_raw(
                    rounded_shift_right(
                        first_bins[index].im + second_bins[index].im,
                        1,
                        formats.frequency.rounding_mode,
                    ),
                    formats.frequency,
                ),
            )
        )
    var known_active = List[ComplexRaw](capacity=52)
    var received_active = List[ComplexRaw](capacity=52)
    for index in range(64):
        if ltf_grid[index].re != 0 or ltf_grid[index].im != 0:
            known_active.append(ltf_grid[index])
            received_active.append(averaged[index])
    if len(known_active) != 52:
        raise Error("fixed acquired Wi-Fi L-LTF must contain 52 active tones")
    var estimate = fixed_ls_flat_channel_raw(
        Span(received_active),
        Span(known_active),
        formats.frequency,
        formats.symbol,
        formats.accumulator,
        formats.reciprocal,
        formats.channel,
    )
    return (averaged^, estimate)


def _six_stage_trace(
    probe_raw: Int64,
    input_format: QFormat,
    output_format: QFormat,
    right_shift: Int,
) raises -> ScaleTrace:
    var stages = List[ScaleStage](capacity=6)
    for _ in range(6):
        stages.append(ScaleStage(output_format, right_shift))
    return apply_scale_schedule(probe_raw, input_format, Span(stages))


def fixed_wifi_acquired_receive(
    observation: Span[ComplexRaw, ...],
    expected_payload_bytes: Span[UInt8, ...],
    ltf_grid: Span[ComplexRaw, ...],
    formats: FixedPHYFormats,
    data_symbol_count: Int,
    scrambler_seed: UInt8,
    *,
    metric_storage_bits: Int = 30,
) raises -> FixedWifiAcquiredRxResult:
    """Detect and decode only from acquired L-LTF/DATA observation slices.

    ``expected_payload_bytes`` supplies the bounded frame length and enables a
    composition/error-count oracle; it never selects the packet boundary or
    any decoded bit.  The fixed 96-sample search aperture supports timing
    offsets through 64 samples without using that transmit-side value.
    """
    _validate_formats(formats)
    if len(expected_payload_bytes) > FIXED_WIFI_LEGACY_MAX_PSDU_OCTETS - 4:
        raise Error("fixed acquired Wi-Fi payload exceeds the legacy PSDU bound")
    if scrambler_seed == 0 or scrambler_seed > UInt8(0x7F):
        raise Error("fixed acquired Wi-Fi scrambler seed must be nonzero 7-bit")
    var payload_bits = _octets_to_bits(expected_payload_bytes)
    var required = (
        FIXED_WIFI_LEGACY_SERVICE_BITS
        + len(payload_bits)
        + FIXED_WIFI_LEGACY_FCS_BITS
        + FIXED_WIFI_LEGACY_TAIL_BITS
    )
    var expected_symbols = (
        required + FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL - 1
    ) // FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL
    if data_symbol_count != expected_symbols:
        raise Error("fixed acquired Wi-Fi DATA symbol count is inconsistent")
    if len(ltf_grid) != 64:
        raise Error("fixed acquired Wi-Fi L-LTF grid must contain 64 bins")
    if len(observation) < FIXED_WIFI_ACQUIRED_SYNC_SEARCH_SAMPLES:
        raise Error("fixed acquired Wi-Fi observation is shorter than the search aperture")

    var search = _copy_complex(
        observation, 0, FIXED_WIFI_ACQUIRED_SYNC_SEARCH_SAMPLES
    )
    var sync = fixed_repetition_scan_raw(
        Span(search),
        FIXED_WIFI_ACQUIRED_STF_PERIOD,
        FIXED_WIFI_ACQUIRED_STF_PERIOD,
        formats.time,
        formats.accumulator,
        formats.accumulator,
    )
    var packet_start = sync.peak_offset
    var peak_first = sync.first_energies[packet_start]
    var peak_second = sync.second_energies[packet_start]
    # This zero-noise bounded detector requires an exact repeated window.  It
    # prevents an all-zero prefix or an arbitrary non-periodic peak from being
    # accepted without introducing a Float64 normalized-metric decision.
    if (
        sync.peak_correlation.re <= 0
        or sync.peak_correlation.im != 0
        or sync.peak_correlation.re != peak_first
        or sync.peak_correlation.re != peak_second
    ):
        raise Error("fixed acquired Wi-Fi exact STF repetition was not detected")
    if packet_start > FIXED_WIFI_ACQUIRED_MAX_TIMING_OFFSET:
        raise Error("fixed acquired Wi-Fi packet start exceeds the bounded aperture")

    var ltf_start = packet_start + FIXED_WIFI_ACQUIRED_STF_SAMPLES
    var data_start = ltf_start + FIXED_WIFI_ACQUIRED_LTF_SAMPLES
    var data_samples = data_symbol_count * 80
    if (
        ltf_start < packet_start
        or data_start < ltf_start
        or data_samples < 0
        or data_start > len(observation)
        or data_samples > len(observation) - data_start
    ):
        raise Error("fixed acquired Wi-Fi detected frame is truncated")
    var ltf_observation = _copy_complex(
        observation, ltf_start, FIXED_WIFI_ACQUIRED_LTF_SAMPLES
    )
    var data_observation = _copy_complex(
        observation, data_start, data_samples
    )
    var ltf_estimate = _estimate_ltf_channel(
        Span(ltf_observation), ltf_grid, formats
    )
    var ltf_bins = ltf_estimate[0].copy()
    var channel_estimate = ltf_estimate[1]

    var carriers = wifi_data_subcarriers()
    if len(carriers) != 48:
        raise Error("fixed acquired Wi-Fi data-tone table must contain 48 tones")
    var received_bins = List[ComplexRaw](capacity=data_symbol_count * 64)
    var equalized_data = List[ComplexRaw](capacity=data_symbol_count * 48)
    for symbol_index in range(data_symbol_count):
        var samples = _copy_complex(
            Span(data_observation), symbol_index * 80, 80
        )
        var bins = fixed_ofdm_demodulate_raw(
            Span(samples),
            64,
            16,
            formats.time,
            formats.frequency,
            formats.twiddle,
        )
        for value in bins:
            received_bins.append(value)
        var equalized = fixed_equalize_flat_raw(
            Span(bins),
            formats.frequency,
            channel_estimate,
            formats.channel,
            formats.accumulator,
            formats.reciprocal,
            formats.symbol,
        )
        for tone_index in range(48):
            equalized_data.append(equalized[_bin(carriers[tone_index])])

    var interleaved_llrs = fixed_qpsk_llrs_raw(
        Span(equalized_data), formats.symbol, formats.symbol
    )
    var deinterleaved_llrs = List[Int64](capacity=len(interleaved_llrs))
    for symbol_index in range(data_symbol_count):
        var block = _copy_i64(
            Span(interleaved_llrs),
            symbol_index * FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
            FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
        )
        var restored = _deinterleave_llrs(Span(block))
        for value in restored:
            deinterleaved_llrs.append(value)
    var soft = fixed_wifi_bcc_viterbi_decode_soft(
        Span(deinterleaved_llrs),
        FixedWifiBCCViterbiConfig(formats.symbol, metric_storage_bits),
        terminate=False,
    )
    var data_bit_count = data_symbol_count * FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL
    if len(soft.bits) != data_bit_count:
        raise Error("fixed acquired Wi-Fi Viterbi output length is inconsistent")
    var decoded_scrambled = soft.bits.copy()
    var descrambled = wifi_scramble(Span(decoded_scrambled), scrambler_seed)
    var tail_offset = (
        FIXED_WIFI_LEGACY_SERVICE_BITS
        + len(payload_bits)
        + FIXED_WIFI_LEGACY_FCS_BITS
    )
    var service_ok = True
    for index in range(FIXED_WIFI_LEGACY_SERVICE_BITS):
        service_ok = service_ok and descrambled[index] == 0
    var tail_ok = True
    for index in range(FIXED_WIFI_LEGACY_TAIL_BITS):
        tail_ok = tail_ok and decoded_scrambled[tail_offset + index] == 0
    var recovered_payload_bits = _copy_bits(
        Span(descrambled), FIXED_WIFI_LEGACY_SERVICE_BITS, len(payload_bits)
    )
    var recovered_payload = _bits_to_octets(Span(recovered_payload_bits))
    var recovered_fcs = _copy_bits(
        Span(descrambled),
        FIXED_WIFI_LEGACY_SERVICE_BITS + len(payload_bits),
        FIXED_WIFI_LEGACY_FCS_BITS,
    )
    var fcs_recovered = _bits_to_u32(Span(recovered_fcs))
    var fcs_expected = wifi_fcs(Span(payload_bits))
    var recalculated_fcs = wifi_fcs(Span(recovered_payload_bits))
    var errors = 0
    for index in range(len(expected_payload_bytes)):
        if recovered_payload[index] != expected_payload_bytes[index]:
            errors += 1
    return FixedWifiAcquiredRxResult(
        search^,
        sync^,
        packet_start,
        ltf_start,
        data_start,
        ltf_observation^,
        data_observation^,
        ltf_bins^,
        channel_estimate,
        received_bins^,
        equalized_data^,
        interleaved_llrs^,
        deinterleaved_llrs^,
        soft^,
        descrambled^,
        recovered_payload^,
        recovered_fcs^,
        fcs_expected,
        fcs_recovered,
        fcs_recovered == recalculated_fcs,
        service_ok,
        tail_ok,
        errors,
    )


def fixed_wifi_acquired_reference(
    payload_bytes: Span[UInt8, ...],
    flat_channel: ComplexRaw,
    formats: FixedPHYFormats,
    amplitude_raw: Int64,
    timing_offset: Int,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    metric_storage_bits: Int = 30,
) raises -> FixedWifiAcquiredResult:
    """Run the bounded integer-timing L-STF/L-LTF/DATA acquired chain."""
    _validate_formats(formats)
    if (
        timing_offset < 0
        or timing_offset > FIXED_WIFI_ACQUIRED_MAX_TIMING_OFFSET
    ):
        raise Error("fixed acquired Wi-Fi timing offset must lie in [0, 64]")
    var known = fixed_wifi_legacy_reference(
        payload_bytes,
        flat_channel,
        formats,
        amplitude_raw,
        scrambler_seed=scrambler_seed,
        metric_storage_bits=metric_storage_bits,
    )
    var stf = _build_stf(
        known.reference_amplitude_raw, formats
    )
    var stf_grid = stf[0].copy()
    var stf_ifft = stf[1].copy()
    var stf_short = stf[2].copy()
    var stf_waveform = stf[3].copy()
    var packet_tx = List[ComplexRaw](
        capacity=(
            len(stf_waveform)
            + len(known.ltf_transmit_samples)
            + len(known.data_transmit_samples)
        )
    )
    for value in stf_waveform:
        packet_tx.append(value)
    for value in known.ltf_transmit_samples:
        packet_tx.append(value)
    for value in known.data_transmit_samples:
        packet_tx.append(value)
    var packet_channel = fixed_flat_channel_raw(
        Span(packet_tx),
        formats.time,
        flat_channel,
        formats.channel,
        formats.time,
    )
    var observation = List[ComplexRaw](
        capacity=timing_offset + len(packet_channel)
    )
    for _ in range(timing_offset):
        observation.append(ComplexRaw())
    for value in packet_channel:
        observation.append(value)
    var rx = fixed_wifi_acquired_receive(
        Span(observation),
        payload_bytes,
        Span(known.ltf_grid),
        formats,
        known.data_symbol_count,
        scrambler_seed,
        metric_storage_bits=metric_storage_bits,
    )

    var composition_matches = (
        rx.packet_start == timing_offset
        and rx.ltf_observation == known.ltf_channel_samples
        and rx.data_observation == known.data_channel_samples
        and rx.ltf_received_bins == known.ltf_received_bins
        and rx.channel_estimate == known.channel_estimate
        and rx.data_received_bins == known.data_received_bins
        and rx.equalized_data_symbols == known.equalized_data_symbols
        and rx.interleaved_llrs_raw == known.interleaved_llrs_raw
        and rx.deinterleaved_llrs_raw == known.deinterleaved_llrs_raw
        and rx.soft_viterbi.bits == known.soft_viterbi.bits
        and rx.recovered_payload_bytes == known.recovered_payload_bytes
        and rx.recovered_fcs_bits == known.recovered_fcs_bits
        and rx.fcs_ok == known.fcs_ok
    )
    if not composition_matches:
        raise Error("fixed acquired Wi-Fi slice composition disagrees with known timing")
    var ifft_trace = _six_stage_trace(
        stf_grid[_bin(-24)].re, formats.symbol, formats.time, 1
    )
    var fft_trace = _six_stage_trace(
        rx.ltf_observation[32].re,
        formats.time,
        formats.frequency,
        0,
    )
    return FixedWifiAcquiredResult(
        known^,
        stf_grid^,
        stf_ifft^,
        stf_short^,
        stf_waveform^,
        packet_tx^,
        packet_channel^,
        observation^,
        timing_offset,
        rx^,
        ifft_trace^,
        fft_trace^,
        composition_matches,
    )


def _u8_raw(values: Span[UInt8, ...]) -> List[Int64]:
    var result = List[Int64](capacity=len(values))
    for index in range(len(values)):
        result.append(Int64(values[index]))
    return result^


def _int_raw(values: Span[Int, ...]) -> List[Int64]:
    var result = List[Int64](capacity=len(values))
    for index in range(len(values)):
        result.append(Int64(values[index]))
    return result^


def _mix_word(mut state: UInt64, value: UInt64):
    for byte_index in range(8):
        state ^= UInt64(
            UInt8((value >> UInt64(8 * byte_index)) & UInt64(0xFF))
        )
        state *= UInt64(1099511628211)


def _mix_trace(mut state: UInt64, trace: ScaleTrace):
    var fraction = _int_raw(Span(trace.fraction_bits))
    var storage = _int_raw(Span(trace.storage_bits))
    var shifts = _int_raw(Span(trace.right_shifts))
    var rounding = _int_raw(Span(trace.rounding_modes))
    var overflow = _int_raw(Span(trace.overflow_modes))
    for checksum in [
        fixed_raw_checksum(Span(trace.values)),
        fixed_raw_checksum(Span(fraction)),
        fixed_raw_checksum(Span(storage)),
        fixed_raw_checksum(Span(shifts)),
        fixed_raw_checksum(Span(rounding)),
        fixed_raw_checksum(Span(overflow)),
    ]:
        _mix_word(state, checksum)


def fixed_wifi_acquired_result_checksum(
    result: FixedWifiAcquiredResult
) -> UInt64:
    """FNV-compose transmit, acquired slices, decoder, and scale checkpoints."""
    var decoded = _u8_raw(Span(result.rx.soft_viterbi.bits))
    var descrambled = _u8_raw(Span(result.rx.descrambled_data_bits))
    var recovered = _u8_raw(Span(result.rx.recovered_payload_bytes))
    var recovered_fcs = _u8_raw(Span(result.rx.recovered_fcs_bits))
    var predecessors = _int_raw(
        Span(result.rx.soft_viterbi.survivor_predecessors)
    )
    var decisions = _u8_raw(Span(result.rx.soft_viterbi.survivor_decisions))
    var reachable = _u8_raw(Span(result.rx.soft_viterbi.final_reachable))
    var state = UInt64(14695981039346656037)
    for scalar in [
        UInt64(2),
        UInt64(result.timing_offset),
        UInt64(result.rx.packet_start),
        UInt64(result.rx.ltf_start),
        UInt64(result.rx.data_start),
        UInt64(result.rx.fcs_expected),
        UInt64(result.rx.fcs_recovered),
        UInt64(result.rx.fcs_ok),
        UInt64(result.rx.service_ok),
        UInt64(result.rx.tail_ok),
        UInt64(result.rx.payload_byte_errors),
        UInt64(result.composition_matches_known_timing),
        UInt64(result.rx.soft_viterbi.final_state),
        UInt64(result.rx.soft_viterbi.final_normalized_metric_raw),
        UInt64(result.rx.soft_viterbi.saturation_count),
    ]:
        _mix_word(state, scalar)
    for checksum in [
        fixed_wifi_legacy_result_checksum(result.known_timing_audit),
        complex_raw_checksum(Span(result.stf_grid)),
        complex_raw_checksum(Span(result.stf_ifft_samples)),
        complex_raw_checksum(Span(result.stf_short_symbol)),
        complex_raw_checksum(Span(result.stf_transmit_samples)),
        complex_raw_checksum(Span(result.packet_transmit_samples)),
        complex_raw_checksum(Span(result.packet_channel_samples)),
        complex_raw_checksum(Span(result.observation)),
        complex_raw_checksum(Span(result.rx.sync_search_samples)),
        fixed_repetition_scan_checksum(result.rx.sync),
        complex_raw_checksum(Span(result.rx.ltf_observation)),
        complex_raw_checksum(Span(result.rx.data_observation)),
        complex_raw_checksum(Span(result.rx.ltf_received_bins)),
        complex_raw_checksum(Span([result.rx.channel_estimate])),
        complex_raw_checksum(Span(result.rx.data_received_bins)),
        complex_raw_checksum(Span(result.rx.equalized_data_symbols)),
        fixed_raw_checksum(Span(result.rx.interleaved_llrs_raw)),
        fixed_raw_checksum(Span(result.rx.deinterleaved_llrs_raw)),
        fixed_raw_checksum(Span(predecessors)),
        fixed_raw_checksum(Span(decisions)),
        fixed_raw_checksum(Span(result.rx.soft_viterbi.final_metrics_raw)),
        fixed_raw_checksum(Span(reachable)),
        fixed_raw_checksum(Span(result.rx.soft_viterbi.normalization_offsets_raw)),
        fixed_raw_checksum(Span(decoded)),
        fixed_raw_checksum(Span(descrambled)),
        fixed_raw_checksum(Span(recovered)),
        fixed_raw_checksum(Span(recovered_fcs)),
    ]:
        _mix_word(state, checksum)
    _mix_trace(state, result.ifft_scale_trace)
    _mix_trace(state, result.fft_scale_trace)
    return state


def fixed_wifi_acquired_canonical_rtl_vectors(
    result: FixedWifiAcquiredResult, formats: FixedPHYFormats
) raises -> String:
    """Serialize the connected acquired chain as canonical V2 raw records."""
    _validate_formats(formats)
    var bit_q = QFormat(2, 0, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var byte_q = QFormat(9, 0, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var index_q = QFormat(34, 0, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var metric_q = QFormat(
        result.rx.soft_viterbi.metric_storage_bits,
        result.rx.soft_viterbi.metric_fraction_bits,
        ROUND_NEAREST_AWAY,
        OVERFLOW_SATURATE,
    )
    var control: List[Int64] = [
        Int64(2),
        Int64(FIXED_WIFI_ACQUIRED_STF_PERIOD),
        Int64(FIXED_WIFI_ACQUIRED_STF_SAMPLES),
        Int64(FIXED_WIFI_ACQUIRED_LTF_SAMPLES),
        Int64(FIXED_WIFI_ACQUIRED_MAX_TIMING_OFFSET),
        Int64(FIXED_WIFI_ACQUIRED_SYNC_SEARCH_SAMPLES),
        Int64(result.timing_offset),
        Int64(result.rx.packet_start),
        Int64(result.rx.ltf_start),
        Int64(result.rx.data_start),
        Int64(result.rx.fcs_expected),
        Int64(result.rx.fcs_recovered),
        Int64(result.rx.fcs_ok),
        Int64(result.rx.service_ok),
        Int64(result.rx.tail_ok),
        Int64(result.rx.payload_byte_errors),
        Int64(result.composition_matches_known_timing),
    ]
    var correlations = result.rx.sync.correlations.copy()
    var first_energies = result.rx.sync.first_energies.copy()
    var second_energies = result.rx.sync.second_energies.copy()
    var decoded = _u8_raw(Span(result.rx.soft_viterbi.bits))
    var descrambled = _u8_raw(Span(result.rx.descrambled_data_bits))
    var recovered = _u8_raw(Span(result.rx.recovered_payload_bytes))
    var recovered_fcs = _u8_raw(Span(result.rx.recovered_fcs_bits))
    var predecessors = _int_raw(
        Span(result.rx.soft_viterbi.survivor_predecessors)
    )
    var decisions = _u8_raw(Span(result.rx.soft_viterbi.survivor_decisions))
    var reachable = _u8_raw(Span(result.rx.soft_viterbi.final_reachable))
    var estimate: List[ComplexRaw] = [result.rx.channel_estimate]
    var text = String()
    # The nested legacy V2 records bind framing/BCC/QPSK/OFDM transmit stages;
    # their known-timing receive side is explicitly labelled as an audit.
    text.write(
        fixed_wifi_legacy_canonical_rtl_vectors(
            result.known_timing_audit, formats
        )
    )
    text.write(
        "MWDSP-FIXED-WIFI-ACQUIRED-V2\n",
        "testcase=fixed-wifi-acquired-qpsk-r12\n",
        "version=2\n",
        "scope=20mhz-legacy-qpsk-flat-channel-integer-timing-zero-cfo\n",
        "not_a_complete_ppdu=no-l-sig\n",
        "stf=standard-12-tone-16-sample-period-10-repetitions\n",
        "detection=fixed-exact-repetition-peak\n",
        "search_samples=96\n",
        "max_timing_offset=64\n",
        "boundary_source=detected-packet-start\n",
        "ltf_slice=packet-start+160:length-160\n",
        "data_slice=packet-start+320:remaining-data-symbols\n",
        "known_timing_role=post-decode-composition-audit-only\n",
        "rounding=nearest-away\n",
        "overflow=saturate\n",
        "wrap=disabled\n",
        "checksum_algorithm=fnv1a64-int64-little-endian\n",
    )
    text.write(serialize_fixed_vector(
        "fixed-wifi-acquired-qpsk-r12", "frame-control", Span(control), index_q,
        version=2,
    ))
    for record in [
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "stf-grid", Span(result.stf_grid),
            formats.symbol, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "stf-ifft-64", Span(result.stf_ifft_samples),
            formats.time, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "stf-short-16", Span(result.stf_short_symbol),
            formats.time, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "stf-waveform-160", Span(result.stf_transmit_samples),
            formats.time, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "packet-transmit", Span(result.packet_transmit_samples),
            formats.time, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "packet-flat-channel", Span(result.packet_channel_samples),
            formats.time, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "timing-prefixed-observation", Span(result.observation),
            formats.time, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "sync-search-aperture", Span(result.rx.sync_search_samples),
            formats.time, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "sync-correlations", Span(correlations),
            formats.accumulator, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "sync-first-energies", Span(first_energies),
            formats.accumulator, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "sync-second-energies", Span(second_energies),
            formats.accumulator, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-ltf-slice", Span(result.rx.ltf_observation),
            formats.time, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-data-slice", Span(result.rx.data_observation),
            formats.time, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-ltf-fft", Span(result.rx.ltf_received_bins),
            formats.frequency, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-ltf-flat-ls", Span(estimate),
            formats.channel, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-data-fft", Span(result.rx.data_received_bins),
            formats.frequency, version=2,
        ),
        serialize_complex_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-data-flat-zf", Span(result.rx.equalized_data_symbols),
            formats.symbol, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-interleaved-llrs", Span(result.rx.interleaved_llrs_raw),
            formats.symbol, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-deinterleaved-llrs", Span(result.rx.deinterleaved_llrs_raw),
            formats.symbol, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-viterbi-predecessors", Span(predecessors),
            QFormat(8, 0), version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-viterbi-decisions", Span(decisions),
            bit_q, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-viterbi-final-metrics", Span(result.rx.soft_viterbi.final_metrics_raw),
            metric_q, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-viterbi-final-reachable", Span(reachable),
            bit_q, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-viterbi-metric-normalization", Span(result.rx.soft_viterbi.normalization_offsets_raw),
            metric_q, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-decoded-scrambled", Span(decoded),
            bit_q, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-descrambled", Span(descrambled),
            bit_q, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-payload-octets", Span(recovered),
            byte_q, version=2,
        ),
        serialize_fixed_vector(
            "fixed-wifi-acquired-qpsk-r12", "acquired-fcs-bits", Span(recovered_fcs),
            bit_q, version=2,
        ),
    ]:
        text.write(record)
    text.write(serialize_scale_trace(
        "fixed-wifi-acquired-qpsk-r12", "stf-ifft-registers",
        result.ifft_scale_trace, version=2,
    ))
    text.write(serialize_scale_trace(
        "fixed-wifi-acquired-qpsk-r12", "ltf-data-fft-registers",
        result.fft_scale_trace, version=2,
    ))
    text.write(
        "MWDSP-FIXED-WIFI-ACQUIRED-CHECKSUM-V2\nchecksum=",
        fixed_wifi_acquired_result_checksum(result),
        "\n",
    )
    return text^
