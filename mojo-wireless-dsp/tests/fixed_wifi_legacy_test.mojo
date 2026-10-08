"""Strict evidence for the bit-exact standard-allocation legacy mini-PHY."""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.numerics.fixed import OVERFLOW_WRAP, ROUND_NEAREST_AWAY
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYFormats,
    fixed_phy_default_formats,
)
from wireless_dsp.backend.fixed_wifi_legacy_reference import (
    FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
    FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL,
    FIXED_WIFI_LEGACY_MAX_AMPLITUDE_RAW,
    FIXED_WIFI_LEGACY_MIN_AMPLITUDE_RAW,
    fixed_wifi_legacy_canonical_rtl_vectors,
    fixed_wifi_legacy_reference,
    fixed_wifi_legacy_result_checksum,
)


def _oracle_fnv1a_text(text: StringSlice) -> UInt64:
    var state = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        state ^= UInt64(UInt8(bytes[index]))
        state *= UInt64(1099511628211)
    return state


def _payload_123456789() -> List[UInt8]:
    return [
        UInt8(0x31), UInt8(0x32), UInt8(0x33),
        UInt8(0x34), UInt8(0x35), UInt8(0x36),
        UInt8(0x37), UInt8(0x38), UInt8(0x39),
    ]


def _oracle_bits(values: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * len(values))
    for value_index in range(len(values)):
        var value = values[value_index]
        for bit_index in range(8):
            result.append(UInt8((value >> UInt8(bit_index)) & 1))
    return result^


def _oracle_crc32(values: Span[UInt8, ...]) -> UInt64:
    # Independent reflected byte-at-a-time IEEE CRC-32 oracle.  Unlike the
    # production path, this does not call wifi_fcs or crc_reflected_bits.
    var crc = UInt64(0xFFFFFFFF)
    for value_index in range(len(values)):
        var value = values[value_index]
        var octet = UInt64(value)
        for _ in range(8):
            var mix = (crc ^ octet) & UInt64(1)
            crc >>= 1
            if mix != 0:
                crc ^= UInt64(0xEDB88320)
            octet >>= 1
    return crc ^ UInt64(0xFFFFFFFF)


def _parity(value: Int) -> UInt8:
    var remaining = value
    var result = UInt8(0)
    while remaining != 0:
        result ^= UInt8(remaining & 1)
        remaining >>= 1
    return result


def _oracle_bcc(bits: Span[UInt8, ...]) -> List[UInt8]:
    # Independent integer shift-register implementation of octal 133/171.
    var state = 0
    var result = List[UInt8](capacity=2 * len(bits))
    for bit_index in range(len(bits)):
        var bit = bits[bit_index]
        state = ((state << 1) | Int(bit)) & 0x7F
        result.append(_parity(state & 0o133))
        result.append(_parity(state & 0o171))
    return result^


def _oracle_interleave(block: Span[UInt8, ...]) -> List[UInt8]:
    # IEEE legacy QPSK N_CBPS=96, N_BPSC=2, s=1 permutation calculated
    # locally rather than through either public interleaver implementation.
    var result = List[UInt8](length=96, fill=UInt8(0))
    for k in range(96):
        var first = 6 * (k % 16) + k // 16
        var second = first + (first + 96 - (16 * first) // 96) % 1
        result[second] = block[k]
    return result^


def _slice_bits(
    values: Span[UInt8, ...], offset: Int, count: Int
) -> List[UInt8]:
    var result = List[UInt8](capacity=count)
    for index in range(count):
        result.append(values[offset + index])
    return result^


def test_static_ieee_frame_tones_interleaver_crc_and_roundtrip() raises:
    var payload = _payload_123456789()
    var formats = fixed_phy_default_formats()
    var result = fixed_wifi_legacy_reference(
        Span(payload), ComplexRaw(12288, -4096), formats, 8192
    )

    assert_equal(result.fcs_expected, UInt64(0xCBF43926))
    assert_equal(result.fcs_expected, _oracle_crc32(Span(payload)))
    assert_equal(result.fcs_recovered, UInt64(0xCBF43926))
    assert_equal(result.data_symbol_count, 3)
    assert_equal(result.pad_bit_count, 18)
    assert_equal(result.amplitude_raw, Int64(8192))
    assert_equal(result.reference_amplitude_raw, Int64(11585))
    assert_equal(len(result.psdu_bits), 13 * 8)
    assert_equal(len(result.uncoded_data_bits), 3 * 48)
    assert_equal(len(result.coded_bits), 3 * 96)
    assert_equal(len(result.interleaved_bits), 3 * 96)
    assert_equal(len(result.mapped_data_symbols), 3 * 48)
    assert_equal(len(result.data_frequency_grids), 3 * 64)
    assert_equal(len(result.data_transmit_samples), 3 * 80)
    assert_equal(len(result.ltf_transmit_samples), 160)
    assert_equal(result.recovered_payload_bytes, payload)
    assert_equal(result.payload_byte_errors, 0)
    assert_true(result.service_ok)
    assert_true(result.tail_ok)
    assert_true(result.fcs_ok)
    assert_equal(result.audit.bit_errors, 0)
    assert_true(result.audit.evm_rms < 0.01)

    var payload_bits = _oracle_bits(Span(payload))
    for index in range(len(payload_bits)):
        assert_equal(result.psdu_bits[index], payload_bits[index])
    for index in range(32):
        assert_equal(
            result.fcs_bits[index],
            UInt8((UInt64(0xCBF43926) >> UInt64(index)) & 1),
        )
    for index in range(16):
        assert_equal(result.uncoded_data_bits[index], UInt8(0))
    for index in range(6):
        assert_equal(
            result.scrambled_data_bits[result.tail_offset + index], UInt8(0)
        )
    var oracle_coded = _oracle_bcc(Span(result.scrambled_data_bits))
    assert_equal(result.coded_bits, oracle_coded)
    for symbol_index in range(result.data_symbol_count):
        var coded_block = _slice_bits(
            Span(result.coded_bits), symbol_index * 96, 96
        )
        var expected = _oracle_interleave(Span(coded_block))
        var actual = _slice_bits(
            Span(result.interleaved_bits), symbol_index * 96, 96
        )
        assert_equal(actual, expected)

    # Independent allocation set: only k=-26..-1,+1..+26 is occupied;
    # -21,-7,+7,+21 are pilots and the remaining 48 are DATA.
    for symbol_index in range(result.data_symbol_count):
        var active = 0
        var data = 0
        for k in range(-32, 32):
            var bin_index = k if k >= 0 else 64 + k
            var value = result.data_frequency_grids[64 * symbol_index + bin_index]
            var occupied = value.re != 0 or value.im != 0
            var should_be_active = k >= -26 and k <= 26 and k != 0
            assert_equal(occupied, should_be_active)
            if occupied:
                active += 1
                if k != -21 and k != -7 and k != 7 and k != 21:
                    data += 1
        assert_equal(active, 52)
        assert_equal(data, 48)


def test_seeded_payload_channel_property_and_float_audit() raises:
    var formats = fixed_phy_default_formats()
    var state = UInt64(0x80211A20260821)
    for case_index in range(6):
        var length = (case_index * case_index + 3 * case_index) % 24
        var payload = List[UInt8](capacity=length)
        for _ in range(length):
            state = (
                state * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            payload.append(UInt8(state >> 56))
        var channel = (
            ComplexRaw(16384, 0)
            if case_index % 2 == 0
            else ComplexRaw(12288, -4096)
        )
        var result = fixed_wifi_legacy_reference(
            Span(payload),
            channel,
            formats,
            Int64(4096 + 1024 * case_index),
            scrambler_seed=UInt8(1 + 19 * case_index),
        )
        assert_equal(result.recovered_payload_bytes, payload)
        assert_equal(result.payload_byte_errors, 0)
        assert_true(result.service_ok and result.tail_ok and result.fcs_ok)
        assert_equal(result.audit.bit_errors, 0)
        assert_true(result.audit.evm_rms < 0.02)
        assert_equal(
            len(result.coded_bits),
            result.data_symbol_count * FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
        )
        assert_equal(
            len(result.uncoded_data_bits),
            result.data_symbol_count * FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL,
        )


def test_min_max_numeric_and_capacity_edges() raises:
    var formats = fixed_phy_default_formats()
    var empty = List[UInt8]()
    var minimum = fixed_wifi_legacy_reference(
        Span(empty),
        ComplexRaw(16384, 0),
        formats,
        Int64(FIXED_WIFI_LEGACY_MIN_AMPLITUDE_RAW),
        scrambler_seed=UInt8(1),
    )
    assert_equal(minimum.data_symbol_count, 2)
    assert_equal(minimum.reference_amplitude_raw, Int64(1448))
    assert_equal(minimum.recovered_payload_bytes, empty)
    assert_true(minimum.fcs_ok)
    assert_equal(minimum.audit.bit_errors, 0)
    assert_true(fixed_wifi_legacy_result_checksum(minimum) != UInt64(0))
    var minimum_vectors = fixed_wifi_legacy_canonical_rtl_vectors(
        minimum, formats
    )
    assert_true("testcase=fixed-wifi-legacy-qpsk-r12\n" in minimum_vectors)
    assert_true("shape=" in minimum_vectors)

    var maximum = fixed_wifi_legacy_reference(
        Span(empty),
        ComplexRaw(16384, 0),
        formats,
        Int64(FIXED_WIFI_LEGACY_MAX_AMPLITUDE_RAW),
        scrambler_seed=UInt8(0x7F),
    )
    assert_equal(maximum.recovered_payload_bytes, empty)
    assert_equal(maximum.reference_amplitude_raw, Int64(46340))
    assert_true(maximum.fcs_ok)
    assert_equal(maximum.audit.bit_errors, 0)
    assert_true(fixed_wifi_legacy_result_checksum(maximum) != UInt64(0))
    assert_true(
        "overflow=saturate\n"
        in fixed_wifi_legacy_canonical_rtl_vectors(maximum, formats)
    )

    # The largest legal payload plus its four-octet FCS exactly reaches the
    # legacy 4095-octet PSDU ceiling.  It occupies 683 QPSK rate-1/2 symbols
    # with two pad bits and must remain an exact end-to-end recovery.
    var largest = List[UInt8](capacity=4091)
    for index in range(4091):
        largest.append(UInt8((index * 73 + index // 11) & 0xFF))
    var maximum_capacity = fixed_wifi_legacy_reference(
        Span(largest), ComplexRaw(16384, 0), formats, 8192
    )
    assert_equal(maximum_capacity.data_symbol_count, 683)
    assert_equal(maximum_capacity.pad_bit_count, 2)
    assert_equal(maximum_capacity.recovered_payload_bytes, largest)
    assert_equal(maximum_capacity.payload_byte_errors, 0)
    assert_true(maximum_capacity.fcs_ok)

    with assert_raises():
        _ = fixed_wifi_legacy_reference(
            Span(empty), ComplexRaw(16384, 0), formats, 1023
        )
    with assert_raises():
        _ = fixed_wifi_legacy_reference(
            Span(empty), ComplexRaw(16384, 0), formats, 32768
        )
    with assert_raises():
        _ = fixed_wifi_legacy_reference(
            Span(empty), ComplexRaw(16384, 0), formats, 8192,
            scrambler_seed=UInt8(0),
        )

    var too_large = List[UInt8](length=4092, fill=UInt8(0))
    with assert_raises():
        _ = fixed_wifi_legacy_reference(
            Span(too_large), ComplexRaw(16384, 0), formats, 8192
        )

    var wrap_formats = FixedPHYFormats(
        QFormat(18, 14, ROUND_NEAREST_AWAY, OVERFLOW_WRAP),
        formats.time,
        formats.channel,
        formats.frequency,
        formats.accumulator,
        formats.reciprocal,
        formats.twiddle,
    )
    with assert_raises():
        _ = fixed_wifi_legacy_reference(
            Span(empty), ComplexRaw(16384, 0), wrap_formats, 8192
        )


def test_bit_exact_checksum_and_canonical_checkpoint_metadata() raises:
    var payload: List[UInt8] = [
        UInt8(0x00), UInt8(0xFF), UInt8(0x55), UInt8(0xAA),
        UInt8(0x80), UInt8(0x01), UInt8(0x7E), UInt8(0x42),
    ]
    var formats = fixed_phy_default_formats()
    var first = fixed_wifi_legacy_reference(
        Span(payload), ComplexRaw(12288, -4096), formats, 8192
    )
    var second = fixed_wifi_legacy_reference(
        Span(payload), ComplexRaw(12288, -4096), formats, 8192
    )
    var checksum = fixed_wifi_legacy_result_checksum(first)
    assert_equal(checksum, fixed_wifi_legacy_result_checksum(second))
    assert_equal(checksum, UInt64(17908611358574504484))
    var first_text = fixed_wifi_legacy_canonical_rtl_vectors(first, formats)
    # Independently computed FNV-1a pins every UTF-8 artifact byte.
    assert_equal(
        _oracle_fnv1a_text(StringSlice(first_text)),
        UInt64(4455245236901763262),
    )
    var second_text = fixed_wifi_legacy_canonical_rtl_vectors(second, formats)
    assert_equal(first_text, second_text)
    assert_true("testcase=fixed-wifi-legacy-qpsk-r12\n" in first_text)
    assert_true("version=2\n" in first_text)
    assert_true("dtype=sint18\n" in first_text)
    assert_true("shape=192x2\n" in first_text)
    assert_true("stride=1\n" in first_text)
    assert_true("fraction_bits=14\n" in first_text)
    assert_true("scale_numerator=1\n" in first_text)
    assert_true("scale_denominator=16384\n" in first_text)
    assert_true("rounding=nearest-away\n" in first_text)
    assert_true("overflow=saturate\n" in first_text)
    assert_true("wrap=disabled\n" in first_text)
    assert_true("stage=frame-control\n" in first_text)
    assert_true("stage=soft-survivor-predecessors\n" in first_text)
    assert_true("MWDSP-FIXED-WIFI-LEGACY-CHECKSUM-V2\n" in first_text)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
