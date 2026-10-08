"""Strict evidence for the bounded fixed frequency-selective NR PDSCH chain."""

from std.collections import Span
from std.math import cos, sin
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.numerics.fixed import (
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
    ROUND_NEAREST_AWAY,
)
from wireless_dsp.numerics.quantization import QFormat, dequantize_raw
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.wireless.nr import nr_ldpc_encode
from wireless_dsp.backend.fixed_nr_pdsch_reference import (
    FIXED_NR_PDSCH_ALLOCATION_SIZE,
    FIXED_NR_PDSCH_CP_LENGTH,
    FIXED_NR_PDSCH_DATA_RE,
    FIXED_NR_PDSCH_DMRS_RE,
    FIXED_NR_PDSCH_FFT_SIZE,
    FIXED_NR_PDSCH_FIRST_SUBCARRIER,
    FIXED_NR_PDSCH_OUTPUT_BITS,
    FIXED_NR_PDSCH_PAYLOAD_BITS,
    FixedNRPDSCHConfig,
    FixedNRPDSCHFormats,
    FixedNRPDSCHResult,
    fixed_nr_pdsch_canonical_rtl_vectors,
    fixed_nr_pdsch_default_formats,
    fixed_nr_pdsch_reference,
    fixed_nr_pdsch_result_checksum,
    fixed_nr_pdsch_scale_trace_text,
)


def _oracle_fnv1a_text(text: StringSlice) -> UInt64:
    var state = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        state ^= UInt64(UInt8(bytes[index]))
        state *= UInt64(1099511628211)
    return state


comptime _TWO_PI = 6.283185307179586476925286766559
comptime _AMPLITUDE_RAW = 11585


def _payload(seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=FIXED_NR_PDSCH_PAYLOAD_BITS)
    for _ in range(FIXED_NR_PDSCH_PAYLOAD_BITS):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        result.append(UInt8((state >> UInt64(63)) & UInt64(1)))
    return result^


def _canonical_taps() -> List[ComplexRaw]:
    # Q18.14: 0.75+j0.0625, 0.1875-j0.125, 0.0625+j0.03125.
    return [
        ComplexRaw(12288, 1024),
        ComplexRaw(3072, -2048),
        ComplexRaw(1024, 512),
    ]


def _reference_crc16_append(
    bits: Span[UInt8, ...]
) raises -> List[UInt8]:
    """Independent MSB-first CRC16 shift-register implementation."""
    var state = UInt64(0)
    comptime polynomial = UInt64(0x1021)
    comptime top = UInt64(1) << UInt64(15)
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("independent CRC accepts binary inputs only")
        var feedback = (
            ((state & top) != 0) != (bits[index] != 0)
        )
        state = (state << UInt64(1)) & UInt64(0xFFFF)
        if feedback:
            state ^= polynomial
    var result = List[UInt8](capacity=len(bits) + 16)
    for index in range(len(bits)):
        result.append(bits[index])
    for index in range(16):
        result.append(
            UInt8((state >> UInt64(15 - index)) & UInt64(1))
        )
    return result^


def _reference_gold(c_init: UInt32, length: Int) -> List[UInt8]:
    """TS 38.211 5.2.1 rolling-register oracle, unlike production arrays."""
    var x1 = UInt32(1)
    var x2 = c_init & UInt32(0x7FFFFFFF)
    var result = List[UInt8](capacity=length)
    for index in range(1600 + length):
        var output = UInt8((x1 ^ x2) & UInt32(1))
        var feedback1 = ((x1 >> 3) ^ x1) & UInt32(1)
        var feedback2 = (
            (x2 >> 3) ^ (x2 >> 2) ^ (x2 >> 1) ^ x2
        ) & UInt32(1)
        x1 = (x1 >> 1) | (feedback1 << 30)
        x2 = (x2 >> 1) | (feedback2 << 30)
        if index >= 1600:
            result.append(output)
    return result^


def _reference_null_mask() -> List[UInt8]:
    # A=100 gives BG2, Zc=20, K=200 and 84 filler bits.  Puncturing the first
    # 2*Zc positions maps filler [116,200) to encoded indices [76,160).
    var result = List[UInt8](length=1000, fill=UInt8(0))
    for index in range(76, 160):
        result[index] = UInt8(1)
    return result^


def _reference_rate_match_rv0_qpsk(
    encoded: Span[UInt8, ...], null_mask: Span[UInt8, ...]
) -> List[UInt8]:
    # RV0 starts at k0=0 for BG2.  Selection and Qm=2 interleaving are
    # independently restated; only the separately evidenced QC encoder feeds
    # this oracle.
    var selected = List[UInt8](capacity=FIXED_NR_PDSCH_OUTPUT_BITS)
    var cursor = 0
    while len(selected) < FIXED_NR_PDSCH_OUTPUT_BITS:
        if null_mask[cursor] == 0:
            selected.append(encoded[cursor])
        cursor = (cursor + 1) % len(encoded)
    var symbols = FIXED_NR_PDSCH_OUTPUT_BITS // 2
    var result = List[UInt8](capacity=FIXED_NR_PDSCH_OUTPUT_BITS)
    for symbol in range(symbols):
        result.append(selected[symbol])
        result.append(selected[symbols + symbol])
    return result^


def _reference_dmrs_c_init(config: FixedNRPDSCHConfig) -> UInt32:
    var modulus = UInt64(1) << UInt64(31)
    var value = (
        (UInt64(1) << UInt64(17))
        * UInt64(14 * config.slot + config.dmrs_symbol + 1)
        * UInt64(2 * config.n_id + 1)
        + UInt64(2 * config.n_id + config.n_scid)
    ) % modulus
    return UInt32(value)


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _dequantize(
    value: ComplexRaw, qformat: QFormat
) raises -> Complex64:
    return Complex64(
        dequantize_raw(value.re, qformat),
        dequantize_raw(value.im, qformat),
    )


def _direct_dft_bin(
    samples: Span[ComplexRaw, ...],
    bin: Int,
    formats: FixedNRPDSCHFormats,
) raises -> Complex64:
    var result_re = 0.0
    var result_im = 0.0
    for n in range(FIXED_NR_PDSCH_FFT_SIZE):
        var value = _dequantize(
            ComplexRaw(
                samples[FIXED_NR_PDSCH_CP_LENGTH + n].re,
                samples[FIXED_NR_PDSCH_CP_LENGTH + n].im,
            ),
            formats.time,
        )
        var angle = (
            -_TWO_PI * Float64(bin * n)
            / Float64(FIXED_NR_PDSCH_FFT_SIZE)
        )
        var twiddle_re = cos(angle)
        var twiddle_im = sin(angle)
        result_re += value.re * twiddle_re - value.im * twiddle_im
        result_im += value.re * twiddle_im + value.im * twiddle_re
    return Complex64(result_re, result_im)


def _assert_independent_physical_differential(
    result: FixedNRPDSCHResult,
    formats: FixedNRPDSCHFormats,
) raises:
    # Independent Float64 causal convolution of the exact raw IFFT samples and
    # taps checks the registered channel to within its final Q18.14 boundary.
    for output_index in range(len(result.physical.channel_samples)):
        if output_index % 37 != 0 and output_index + 1 != len(
            result.physical.channel_samples
        ):
            continue
        var expected_re = 0.0
        var expected_im = 0.0
        var used_taps = min(
            output_index + 1, len(result.physical.channel_taps)
        )
        for tap_index in range(used_taps):
            var sample = _dequantize(
                result.physical.transmit_samples[output_index - tap_index],
                formats.time,
            )
            var tap = _dequantize(
                result.physical.channel_taps[tap_index], formats.tap
            )
            expected_re += sample.re * tap.re - sample.im * tap.im
            expected_im += sample.re * tap.im + sample.im * tap.re
        var actual = _dequantize(
            result.physical.channel_samples[output_index], formats.time
        )
        _assert_close(actual.re, expected_re, 2.5e-4)
        _assert_close(actual.im, expected_im, 2.5e-4)

    # Direct O(N) DFTs do not call either production FFT implementation.
    for local in [0, 1, 118, 239, 478, 479]:
        var bin = FIXED_NR_PDSCH_FIRST_SUBCARRIER + local
        var expected = _direct_dft_bin(
            Span(result.physical.channel_samples), bin, formats
        )
        var actual = _dequantize(
            result.physical.received_bins[bin], formats.frequency
        )
        _assert_close(actual.re, expected.re, 0.018)
        _assert_close(actual.im, expected.im, 0.018)

    # Independent complex division checks every 29th pilot LS result.
    for pilot in range(0, FIXED_NR_PDSCH_DMRS_RE, 29):
        var y = _dequantize(
            result.physical.received_dmrs[pilot], formats.frequency
        )
        var x = _dequantize(
            result.physical.dmrs_symbols[pilot], formats.symbol
        )
        var denominator = x.re * x.re + x.im * x.im
        var expected_re = (y.re * x.re + y.im * x.im) / denominator
        var expected_im = (y.im * x.re - y.re * x.im) / denominator
        var actual = _dequantize(
            result.physical.pilot_channel_estimates[pilot],
            formats.channel_estimate,
        )
        _assert_close(actual.re, expected_re, 4.0e-4)
        _assert_close(actual.im, expected_im, 4.0e-4)

    # Comb-2 interpolation has a small exact integer oracle.  Edge data REs
    # hold the nearest pilot; interior data REs use nearest-away half sums.
    for local in range(FIXED_NR_PDSCH_ALLOCATION_SIZE):
        if local % 2 == result.config.dmrs_offset:
            var pilot = (local - result.config.dmrs_offset) // 2
            assert_equal(
                result.physical.interpolated_channel[local],
                result.physical.pilot_channel_estimates[pilot],
            )
        elif local < result.config.dmrs_offset:
            assert_equal(
                result.physical.interpolated_channel[local],
                result.physical.pilot_channel_estimates[0],
            )
        else:
            var left = (local - result.config.dmrs_offset) // 2
            var right = left + 1
            if right >= FIXED_NR_PDSCH_DMRS_RE:
                assert_equal(
                    result.physical.interpolated_channel[local],
                    result.physical.pilot_channel_estimates[left],
                )
            else:
                var sum_re = (
                    result.physical.pilot_channel_estimates[left].re
                    + result.physical.pilot_channel_estimates[right].re
                )
                var sum_im = (
                    result.physical.pilot_channel_estimates[left].im
                    + result.physical.pilot_channel_estimates[right].im
                )
                var expected_re = (
                    (sum_re + 1) >> 1 if sum_re >= 0 else sum_re >> 1
                )
                var expected_im = (
                    (sum_im + 1) >> 1 if sum_im >= 0 else sum_im >> 1
                )
                assert_equal(
                    result.physical.interpolated_channel[local],
                    ComplexRaw(expected_re, expected_im),
                )

    # Independent Float64 ZF of exact fixed FFT/channel words.
    var data_index = 0
    for local in range(FIXED_NR_PDSCH_ALLOCATION_SIZE):
        if local % 2 == result.config.dmrs_offset:
            continue
        if data_index % 31 == 0 or data_index + 1 == FIXED_NR_PDSCH_DATA_RE:
            var y = _dequantize(
                result.physical.received_data[data_index], formats.frequency
            )
            var h = _dequantize(
                result.physical.interpolated_channel[local],
                formats.channel_estimate,
            )
            var denominator = h.re * h.re + h.im * h.im
            var expected_re = (y.re * h.re + y.im * h.im) / denominator
            var expected_im = (y.im * h.re - y.re * h.im) / denominator
            var actual = _dequantize(
                result.physical.equalized_data_symbols[data_index],
                formats.equalized,
            )
            _assert_close(actual.re, expected_re, 5.0e-4)
            _assert_close(actual.im, expected_im, 5.0e-4)
        data_index += 1


def test_static_coded_gold_grid_and_raw_checkpoint_vector() raises:
    """Static profile/CRC/rate-match plus independent Gold/grid oracle."""
    var payload = _payload(UInt64(0x9E3779B97F4A7C15))
    var formats = fixed_nr_pdsch_default_formats()
    var config = FixedNRPDSCHConfig()
    var taps = _canonical_taps()
    var result = fixed_nr_pdsch_reference(
        Span(payload), Span(taps), formats, Int64(_AMPLITUDE_RAW), config
    )

    assert_equal(result.base_graph, 2)
    assert_equal(result.lifting_size, 20)
    assert_equal(result.encoded_bits_per_block, 1000)
    assert_equal(result.transport_block, _reference_crc16_append(Span(payload)))
    var null_mask = _reference_null_mask()
    assert_equal(result.encoded_null_mask, null_mask)
    var information = List[UInt8](length=200, fill=UInt8(0))
    for index in range(len(result.transport_block)):
        information[index] = result.transport_block[index]
    var encoded = nr_ldpc_encode(Span(information), 2, 20)
    assert_equal(
        result.physical.rate_matched_bits,
        _reference_rate_match_rv0_qpsk(Span(encoded), Span(null_mask)),
    )

    var scramble_init = UInt32((config.rnti << 15) + config.n_id)
    var expected_scrambling = _reference_gold(
        scramble_init, FIXED_NR_PDSCH_OUTPUT_BITS
    )
    assert_equal(result.physical.scrambling_gold_bits, expected_scrambling)
    var expected_dmrs = _reference_gold(
        _reference_dmrs_c_init(config), 2 * FIXED_NR_PDSCH_DMRS_RE
    )
    assert_equal(result.physical.dmrs_gold_bits, expected_dmrs)
    for symbol in range(FIXED_NR_PDSCH_DATA_RE):
        assert_equal(
            result.physical.mapped_data_symbols[symbol],
            ComplexRaw(
                -Int64(_AMPLITUDE_RAW)
                if result.physical.scrambled_bits[2 * symbol] == 1
                else Int64(_AMPLITUDE_RAW),
                -Int64(_AMPLITUDE_RAW)
                if result.physical.scrambled_bits[2 * symbol + 1] == 1
                else Int64(_AMPLITUDE_RAW),
            ),
        )
    var data_index = 0
    var pilot_index = 0
    for local in range(FIXED_NR_PDSCH_ALLOCATION_SIZE):
        var actual = result.physical.transmit_grid[
            FIXED_NR_PDSCH_FIRST_SUBCARRIER + local
        ]
        if local % 2 == config.dmrs_offset:
            assert_equal(actual, result.physical.dmrs_symbols[pilot_index])
            pilot_index += 1
        else:
            assert_equal(
                actual, result.physical.mapped_data_symbols[data_index]
            )
            data_index += 1

    assert_equal(len(result.physical.transmit_grid), 512)
    assert_equal(len(result.physical.transmit_samples), 548)
    assert_equal(len(result.physical.channel_samples), 548)
    assert_equal(len(result.physical.received_bins), 512)
    assert_equal(len(result.physical.received_dmrs), 240)
    assert_equal(len(result.physical.pilot_channel_estimates), 240)
    assert_equal(len(result.physical.interpolated_channel), 480)
    assert_equal(len(result.physical.received_data), 240)
    assert_equal(len(result.physical.equalized_data_symbols), 240)
    assert_equal(len(result.physical.llrs_raw), 480)
    assert_equal(result.audit.scrambled_bit_errors, 0)
    assert_equal(result.audit.rate_matched_bit_errors, 0)
    assert_equal(result.audit.payload_bit_errors, 0)
    assert_equal(result.decoded_payload_bits, payload)
    assert_true(result.ldpc_converged)
    assert_true(result.code_block_crc_ok)
    assert_true(result.transport_crc_ok)
    assert_true(result.float64_decoder_agrees)
    assert_equal(len(result.decoder_input_llrs_raw), 480)
    assert_equal(len(result.decoder_descrambled_llrs_raw), 480)
    assert_equal(len(result.decoder_rate_recovered_llrs_raw), 1000)
    assert_equal(len(result.decoder_posterior_llrs_raw), 1040)
    assert_equal(result.decoder_syndrome_weight, 0)
    for index in range(len(result.decoder_input_llrs_raw)):
        var expected = result.decoder_input_llrs_raw[index]
        if result.physical.scrambling_gold_bits[index] != 0:
            expected = -expected
        assert_equal(result.decoder_descrambled_llrs_raw[index], expected)
    assert_true(result.audit.equalized_evm_rms < 0.006)
    assert_true(result.audit.channel_evm_rms < 0.006)

    # These raw values and the joint checksum pin every registered stage.
    assert_equal(
        fixed_nr_pdsch_result_checksum(result),
        UInt64(4597413783685323838),
    )
    assert_equal(
        result.physical.mapped_data_symbols[0], ComplexRaw(-11585, 11585)
    )
    assert_equal(
        result.physical.transmit_samples[36], ComplexRaw(-226, 46)
    )
    assert_equal(
        result.physical.channel_samples[36], ComplexRaw(-136, -22)
    )
    assert_equal(
        result.physical.received_bins[16], ComplexRaw(10306, -12418)
    )
    assert_equal(
        result.physical.pilot_channel_estimates[0],
        ComplexRaw(16069, -1493),
    )
    assert_equal(
        result.physical.interpolated_channel[1],
        ComplexRaw(16021, -1554),
    )
    assert_equal(
        result.physical.equalized_data_symbols[0],
        ComplexRaw(-11586, 11591),
    )
    assert_equal(result.physical.llrs_raw[0], Int64(-11586))
    assert_equal(result.physical.llrs_raw[1], Int64(11591))
    assert_equal(result.decoder_iterations, [1])
    _assert_independent_physical_differential(result, formats)


def test_seeded_two_and_three_tap_property_evm_ber_and_determinism() raises:
    var formats = fixed_nr_pdsch_default_formats()
    var seed = UInt64(0x5EED5EED20260821)
    for case_index in range(3):
        var payload = _payload(seed + UInt64(case_index))
        var taps = List[ComplexRaw](capacity=3)
        taps.append(
            ComplexRaw(
                11264 + Int64(173 * case_index),
                768 - Int64(91 * case_index),
            )
        )
        taps.append(
            ComplexRaw(
                2560 - Int64(113 * case_index),
                -1536 + Int64(67 * case_index),
            )
        )
        if case_index != 0:
            taps.append(
                ComplexRaw(
                    768 + Int64(59 * case_index),
                    384 - Int64(37 * case_index),
                )
            )
        var config = FixedNRPDSCHConfig(
            slot=case_index,
            dmrs_symbol=2 + case_index,
            dmrs_offset=case_index & 1,
            n_id=71 + case_index,
            n_scid=case_index & 1,
            rnti=0x3400 + case_index,
            redundancy_version=case_index,
        )
        var first = fixed_nr_pdsch_reference(
            Span(payload), Span(taps), formats, Int64(_AMPLITUDE_RAW), config
        )
        var second = fixed_nr_pdsch_reference(
            Span(payload), Span(taps), formats, Int64(_AMPLITUDE_RAW), config
        )
        assert_equal(
            fixed_nr_pdsch_result_checksum(first),
            fixed_nr_pdsch_result_checksum(second),
        )
        assert_equal(
            first.physical.hard_rate_matched_bits,
            first.physical.rate_matched_bits,
        )
        assert_equal(first.decoded_payload_bits, payload)
        assert_equal(first.audit.scrambled_bit_errors, 0)
        assert_equal(first.audit.rate_matched_bit_errors, 0)
        assert_equal(first.audit.payload_bit_errors, 0)
        assert_true(first.ldpc_converged)
        assert_true(first.code_block_crc_ok)
        assert_true(first.transport_crc_ok)
        assert_true(first.audit.equalized_evm_rms < 0.007)
        assert_true(first.audit.channel_evm_rms < 0.007)
        _assert_independent_physical_differential(first, formats)


def _with_tap_format(
    formats: FixedNRPDSCHFormats, tap: QFormat
) -> FixedNRPDSCHFormats:
    return FixedNRPDSCHFormats(
        formats.symbol,
        formats.time,
        tap,
        formats.channel_accumulator,
        formats.frequency,
        formats.channel_estimate,
        formats.reciprocal,
        formats.equalized,
        formats.llr,
        formats.twiddle,
    )


def test_bounds_formats_overflow_and_zero_channel_edges() raises:
    var formats = fixed_nr_pdsch_default_formats()
    var config = FixedNRPDSCHConfig()
    var payload = _payload(UInt64(3))
    var taps = _canonical_taps()
    var one_tap: List[ComplexRaw] = [ComplexRaw(16384, 0)]
    var four_taps: List[ComplexRaw] = [
        ComplexRaw(8192, 0),
        ComplexRaw(2048, 0),
        ComplexRaw(1024, 0),
        ComplexRaw(512, 0),
    ]
    var zero_taps: List[ComplexRaw] = [ComplexRaw(), ComplexRaw()]
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            Span(payload), Span(one_tap), formats, Int64(_AMPLITUDE_RAW), config
        )
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            Span(payload), Span(four_taps), formats, Int64(_AMPLITUDE_RAW), config
        )
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            Span(payload), Span(zero_taps), formats, Int64(_AMPLITUDE_RAW), config
        )
    var invalid_taps = taps.copy()
    invalid_taps[0] = ComplexRaw(131072, 0)
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            Span(payload), Span(invalid_taps), formats, Int64(_AMPLITUDE_RAW), config
        )

    # In-range high-gain taps exercise the declared saturation boundary.  The
    # function still returns all checkpoints even when the optional Float64
    # decoder reports errors; saturation is observable rather than hidden.
    var high_gain_taps: List[ComplexRaw] = [
        ComplexRaw(131071, 0),
        ComplexRaw(131071, 0),
        ComplexRaw(131071, 0),
    ]
    var saturated = fixed_nr_pdsch_reference(
        Span(payload),
        Span(high_gain_taps),
        formats,
        Int64(_AMPLITUDE_RAW),
        config,
    )
    var saw_saturation = False
    for value in saturated.physical.interpolated_channel:
        saw_saturation = (
            saw_saturation
            or value.re == formats.channel_estimate.max_raw()
            or value.re == formats.channel_estimate.min_raw()
            or value.im == formats.channel_estimate.max_raw()
            or value.im == formats.channel_estimate.min_raw()
        )
    assert_true(saw_saturation)
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            Span(payload), Span(taps), formats, Int64(4095), config
        )
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            Span(payload), Span(taps), formats, Int64(16385), config
        )
    var short_payload = payload[:99]
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            short_payload, Span(taps), formats, Int64(_AMPLITUDE_RAW), config
        )
    var invalid_payload = payload.copy()
    invalid_payload[17] = UInt8(2)
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            Span(invalid_payload), Span(taps), formats, Int64(_AMPLITUDE_RAW), config
        )

    var wrap_tap = QFormat(
        18, 14, ROUND_NEAREST_AWAY, OVERFLOW_WRAP
    )
    var wrap_formats = _with_tap_format(formats, wrap_tap)
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            Span(payload), Span(taps), wrap_formats, Int64(_AMPLITUDE_RAW), config
        )
    var wrong_tap = QFormat(
        18, 13, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var wrong_formats = _with_tap_format(formats, wrong_tap)
    with assert_raises():
        _ = fixed_nr_pdsch_reference(
            Span(payload), Span(taps), wrong_formats, Int64(_AMPLITUDE_RAW), config
        )
    with assert_raises():
        _ = FixedNRPDSCHConfig(slot=10)
    with assert_raises():
        _ = FixedNRPDSCHConfig(dmrs_offset=2)
    with assert_raises():
        _ = FixedNRPDSCHConfig(n_id=1008)
    with assert_raises():
        _ = FixedNRPDSCHConfig(redundancy_version=4)
    with assert_raises():
        _ = FixedNRPDSCHConfig(decoder_llr_scale=1000001.0)


def test_canonical_vectors_scale_trace_and_explicit_decoder_boundary() raises:
    var formats = fixed_nr_pdsch_default_formats()
    var config = FixedNRPDSCHConfig()
    var payload = _payload(UInt64(0xC001D00D))
    var taps = _canonical_taps()
    var first = fixed_nr_pdsch_reference(
        Span(payload), Span(taps), formats, Int64(_AMPLITUDE_RAW), config
    )
    var second = fixed_nr_pdsch_reference(
        Span(payload), Span(taps), formats, Int64(_AMPLITUDE_RAW), config
    )
    var first_text = fixed_nr_pdsch_canonical_rtl_vectors(first, formats)
    # Independently computed FNV-1a pins every UTF-8 artifact byte.
    assert_equal(
        _oracle_fnv1a_text(StringSlice(first_text)),
        UInt64(16052237385349147282),
    )
    var second_text = fixed_nr_pdsch_canonical_rtl_vectors(second, formats)
    assert_equal(first_text, second_text)
    assert_true("fft_size=512\n" in first_text)
    assert_true("cyclic_prefix=36\n" in first_text)
    assert_true("allocation_re=480\n" in first_text)
    assert_true("dmrs_pattern=configuration-type-1-comb2\n" in first_text)
    assert_true("stage=frequency-selective-channel\n" in first_text)
    assert_true("stage=comb2-interpolated-channel\n" in first_text)
    assert_true("stage=raw-coordinate-llrs\n" in first_text)
    assert_true("stage=fixed-decoder-input-llrs\n" in first_text)
    assert_true("stage=fixed-rate-recovered-llrs\n" in first_text)
    assert_true("stage=fixed-ldpc-posterior-llrs\n" in first_text)
    assert_true("fixed_terminal_stage=transport-crc\n" in first_text)
    assert_true("decoder_schedule=layered-min-sum\n" in first_text)
    assert_true(
        "decoder_stages=fixed-rescale,descramble,rate-recover,ldpc,crc\n"
        in first_text
    )
    assert_true("float64_role=differential-audit-only\n" in first_text)
    assert_true("float64_decoder_agrees=1\n" in first_text)
    assert_true("MWDSP-FIXED-NR-PDSCH-CHECKSUM-V1\n" in first_text)
    var trace = fixed_nr_pdsch_scale_trace_text(first, formats)
    assert_equal(
        _oracle_fnv1a_text(StringSlice(trace)),
        UInt64(17893196541486513868),
    )
    assert_true("stage=ifft-registers\n" in trace)
    assert_true("stage=fft-registers\n" in trace)
    assert_true("stage=physical-boundaries\n" in trace)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
