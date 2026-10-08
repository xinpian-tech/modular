"""Strict evidence for the connected fixed legacy Wi-Fi acquired chain."""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.numerics.fixed import OVERFLOW_WRAP, ROUND_NEAREST_AWAY
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYFormats,
    fixed_phy_default_formats,
)
from wireless_dsp.backend.fixed_wifi_acquired_reference import (
    FIXED_WIFI_ACQUIRED_LTF_SAMPLES,
    FIXED_WIFI_ACQUIRED_MAX_TIMING_OFFSET,
    FIXED_WIFI_ACQUIRED_STF_PERIOD,
    FIXED_WIFI_ACQUIRED_STF_SAMPLES,
    fixed_wifi_acquired_canonical_rtl_vectors,
    fixed_wifi_acquired_receive,
    fixed_wifi_acquired_reference,
    fixed_wifi_acquired_result_checksum,
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


def _bin(subcarrier: Int) -> Int:
    return subcarrier if subcarrier >= 0 else 64 + subcarrier


def _slice_complex(
    values: Span[ComplexRaw, ...], offset: Int, count: Int
) -> List[ComplexRaw]:
    var result = List[ComplexRaw](capacity=count)
    for index in range(count):
        result.append(values[offset + index])
    return result^


def test_static_standard_stf_indices_periodicity_and_acquired_boundary() raises:
    var payload = _payload_123456789()
    var formats = fixed_phy_default_formats()
    var timing = 13
    var result = fixed_wifi_acquired_reference(
        Span(payload), ComplexRaw(12288, -4096), formats, 8192, timing
    )
    var direct_rx = fixed_wifi_acquired_receive(
        Span(result.observation),
        Span(payload),
        Span(result.known_timing_audit.ltf_grid),
        formats,
        result.known_timing_audit.data_symbol_count,
        result.known_timing_audit.scrambler_seed,
    )

    assert_equal(len(result.stf_grid), 64)
    assert_equal(len(result.stf_ifft_samples), 64)
    assert_equal(len(result.stf_short_symbol), FIXED_WIFI_ACQUIRED_STF_PERIOD)
    assert_equal(len(result.stf_transmit_samples), FIXED_WIFI_ACQUIRED_STF_SAMPLES)
    var positive = result.stf_grid[_bin(-24)].re
    assert_equal(positive, Int64(17053))
    var positive_tones: List[Int] = [-24, -16, -4, 12, 16, 20, 24]
    var negative_tones: List[Int] = [-20, -12, -8, 4, 8]
    for tone in positive_tones:
        assert_equal(result.stf_grid[_bin(tone)], ComplexRaw(positive, positive))
    for tone in negative_tones:
        assert_equal(result.stf_grid[_bin(tone)], ComplexRaw(-positive, -positive))
    var occupied = 0
    for index in range(64):
        var value = result.stf_grid[index]
        if value.re != 0 or value.im != 0:
            occupied += 1
        assert_equal(
            result.stf_ifft_samples[index],
            result.stf_short_symbol[index % 16],
        )
    assert_equal(occupied, 12)
    for repetition in range(10):
        for index in range(16):
            assert_equal(
                result.stf_transmit_samples[16 * repetition + index],
                result.stf_short_symbol[index],
            )
    # Static raw output of the independent standard-tone integer index above.
    # This locks the fixed radix-2 order, six IFFT shifts, and twiddle ROM.
    var expected_short: List[ComplexRaw] = [
        ComplexRaw(533, 533), ComplexRaw(-1535, 28),
        ComplexRaw(-157, -910), ComplexRaw(1654, -147),
        ComplexRaw(1066, 0), ComplexRaw(1654, -147),
        ComplexRaw(-157, -910), ComplexRaw(-1535, 28),
        ComplexRaw(533, 533), ComplexRaw(28, -1535),
        ComplexRaw(-910, -157), ComplexRaw(-147, 1654),
        ComplexRaw(0, 1066), ComplexRaw(-147, 1654),
        ComplexRaw(-910, -157), ComplexRaw(28, -1535),
    ]
    assert_equal(result.stf_short_symbol, expected_short)

    # These indices are computed independently from the standard field
    # lengths.  The receiver does not receive ``timing`` as an argument.
    assert_equal(result.rx.packet_start, timing)
    assert_equal(result.rx.ltf_start, timing + 160)
    assert_equal(result.rx.data_start, timing + 160 + 160)
    assert_equal(len(result.rx.ltf_observation), FIXED_WIFI_ACQUIRED_LTF_SAMPLES)
    assert_equal(
        len(result.rx.data_observation),
        result.known_timing_audit.data_symbol_count * 80,
    )
    assert_equal(result.rx.recovered_payload_bytes, payload)
    assert_equal(result.rx.fcs_expected, UInt64(0xCBF43926))
    assert_equal(result.rx.fcs_recovered, UInt64(0xCBF43926))
    assert_true(result.rx.service_ok and result.rx.tail_ok and result.rx.fcs_ok)
    assert_equal(result.rx.payload_byte_errors, 0)
    assert_equal(direct_rx.packet_start, result.rx.packet_start)
    assert_equal(direct_rx.recovered_payload_bytes, payload)
    assert_true(direct_rx.fcs_ok)


def test_detected_slices_drive_every_receive_checkpoint() raises:
    var payload: List[UInt8] = [
        UInt8(0x00), UInt8(0xFF), UInt8(0x55), UInt8(0xAA),
        UInt8(0x80), UInt8(0x01), UInt8(0x7E), UInt8(0x42),
    ]
    var formats = fixed_phy_default_formats()
    var result = fixed_wifi_acquired_reference(
        Span(payload), ComplexRaw(12288, -4096), formats, 8192, 47,
        scrambler_seed=UInt8(0x35),
    )
    var direct_rx = fixed_wifi_acquired_receive(
        Span(result.observation),
        Span(payload),
        Span(result.known_timing_audit.ltf_grid),
        formats,
        result.known_timing_audit.data_symbol_count,
        result.known_timing_audit.scrambler_seed,
    )
    var independent_ltf = _slice_complex(
        Span(result.observation), result.rx.packet_start + 160, 160
    )
    var independent_data = _slice_complex(
        Span(result.observation),
        result.rx.packet_start + 320,
        result.known_timing_audit.data_symbol_count * 80,
    )
    assert_equal(result.rx.ltf_observation, independent_ltf)
    assert_equal(result.rx.data_observation, independent_data)
    assert_equal(result.rx.ltf_observation, result.known_timing_audit.ltf_channel_samples)
    assert_equal(result.rx.data_observation, result.known_timing_audit.data_channel_samples)
    assert_equal(result.rx.ltf_received_bins, result.known_timing_audit.ltf_received_bins)
    assert_equal(result.rx.channel_estimate, result.known_timing_audit.channel_estimate)
    assert_equal(result.rx.data_received_bins, result.known_timing_audit.data_received_bins)
    assert_equal(
        result.rx.equalized_data_symbols,
        result.known_timing_audit.equalized_data_symbols,
    )
    assert_equal(result.rx.interleaved_llrs_raw, result.known_timing_audit.interleaved_llrs_raw)
    assert_equal(
        result.rx.deinterleaved_llrs_raw,
        result.known_timing_audit.deinterleaved_llrs_raw,
    )
    assert_equal(result.rx.soft_viterbi.bits, result.known_timing_audit.soft_viterbi.bits)
    assert_true(result.composition_matches_known_timing)
    assert_true(result.rx.fcs_ok)
    assert_equal(direct_rx.ltf_observation, result.rx.ltf_observation)
    assert_equal(direct_rx.data_observation, result.rx.data_observation)
    assert_equal(direct_rx.channel_estimate, result.rx.channel_estimate)
    assert_equal(
        direct_rx.deinterleaved_llrs_raw,
        result.rx.deinterleaved_llrs_raw,
    )
    assert_equal(direct_rx.recovered_payload_bytes, payload)
    assert_true(direct_rx.fcs_ok)


def test_seeded_payload_channel_timing_property() raises:
    var formats = fixed_phy_default_formats()
    var state = UInt64(0xA5A5802115EED64)
    var timings: List[Int] = [0, 1, 15, 16, 47, 64]
    for case_index in range(len(timings)):
        var length = (case_index * case_index + 5 * case_index) % 25
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
        var result = fixed_wifi_acquired_reference(
            Span(payload),
            channel,
            formats,
            Int64(4096 + 1024 * case_index),
            timings[case_index],
            scrambler_seed=UInt8(1 + 17 * case_index),
        )
        var direct_rx = fixed_wifi_acquired_receive(
            Span(result.observation),
            Span(payload),
            Span(result.known_timing_audit.ltf_grid),
            formats,
            result.known_timing_audit.data_symbol_count,
            result.known_timing_audit.scrambler_seed,
        )
        assert_equal(result.rx.packet_start, timings[case_index])
        assert_equal(result.rx.recovered_payload_bytes, payload)
        assert_equal(result.rx.payload_byte_errors, 0)
        assert_true(result.rx.service_ok and result.rx.tail_ok and result.rx.fcs_ok)
        assert_true(result.composition_matches_known_timing)
        assert_equal(direct_rx.packet_start, timings[case_index])
        assert_equal(direct_rx.recovered_payload_bytes, payload)
        assert_true(direct_rx.fcs_ok)
        assert_equal(len(result.ifft_scale_trace.values), 6)
        assert_equal(len(result.fft_scale_trace.values), 6)
        for stage in range(6):
            assert_equal(result.ifft_scale_trace.right_shifts[stage], 1)
            assert_equal(result.fft_scale_trace.right_shifts[stage], 0)
            assert_equal(
                result.ifft_scale_trace.rounding_modes[stage],
                ROUND_NEAREST_AWAY,
            )


def test_wrong_boundary_fault_and_int_max_edges() raises:
    var formats = fixed_phy_default_formats()
    var payload = _payload_123456789()
    var valid = fixed_wifi_acquired_reference(
        Span(payload), ComplexRaw(12288, -4096), formats, 8192, 7
    )
    var different_expected = payload.copy()
    different_expected[0] ^= UInt8(0xFF)
    var audit_mismatch = fixed_wifi_acquired_receive(
        Span(valid.observation),
        Span(different_expected),
        Span(valid.known_timing_audit.ltf_grid),
        formats,
        valid.known_timing_audit.data_symbol_count,
        valid.known_timing_audit.scrambler_seed,
    )
    # Expected payload is an error-count oracle only.  The receiver's FCS
    # decision must depend solely on the recovered payload and received FCS.
    assert_equal(audit_mismatch.recovered_payload_bytes, payload)
    assert_equal(audit_mismatch.payload_byte_errors, 1)
    assert_true(audit_mismatch.fcs_ok)
    assert_true(audit_mismatch.fcs_expected != audit_mismatch.fcs_recovered)
    # Delete the last STF sample, then retain the original total length with a
    # trailing zero.  The first repeated windows still detect packet start 7,
    # but the derived L-LTF/DATA boundary is now one sample wrong.  A receiver
    # that silently reused the known TX timing slices would incorrectly pass.
    var wrong = List[ComplexRaw](capacity=len(valid.observation))
    var deleted = valid.rx.packet_start + 159
    for index in range(len(valid.observation)):
        if index != deleted:
            wrong.append(valid.observation[index])
    wrong.append(ComplexRaw())
    var wrong_rx = fixed_wifi_acquired_receive(
        Span(wrong),
        Span(payload),
        Span(valid.known_timing_audit.ltf_grid),
        formats,
        valid.known_timing_audit.data_symbol_count,
        valid.known_timing_audit.scrambler_seed,
    )
    assert_equal(wrong_rx.packet_start, 7)
    assert_true(not wrong_rx.fcs_ok)
    assert_true(wrong_rx.payload_byte_errors != 0 or not wrong_rx.service_ok)

    with assert_raises():
        _ = fixed_wifi_acquired_reference(
            Span(payload), ComplexRaw(16384, 0), formats, 8192, -1
        )
    with assert_raises():
        _ = fixed_wifi_acquired_reference(
            Span(payload), ComplexRaw(16384, 0), formats, 8192, Int.MAX
        )
    with assert_raises():
        _ = fixed_wifi_acquired_reference(
            Span(payload), ComplexRaw(16384, 0), formats, 8192,
            FIXED_WIFI_ACQUIRED_MAX_TIMING_OFFSET + 1,
        )
    var truncated = _slice_complex(Span(valid.observation), 0, 95)
    with assert_raises():
        _ = fixed_wifi_acquired_receive(
            Span(truncated),
            Span(payload),
            Span(valid.known_timing_audit.ltf_grid),
            formats,
            valid.known_timing_audit.data_symbol_count,
            valid.known_timing_audit.scrambler_seed,
        )
    with assert_raises():
        _ = fixed_wifi_acquired_receive(
            Span(valid.observation),
            Span(payload),
            Span(valid.known_timing_audit.ltf_grid),
            formats,
            Int.MAX,
            valid.known_timing_audit.scrambler_seed,
        )
    var all_zero = List[ComplexRaw](length=len(valid.observation), fill=ComplexRaw())
    with assert_raises():
        _ = fixed_wifi_acquired_receive(
            Span(all_zero),
            Span(payload),
            Span(valid.known_timing_audit.ltf_grid),
            formats,
            valid.known_timing_audit.data_symbol_count,
            valid.known_timing_audit.scrambler_seed,
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
        _ = fixed_wifi_acquired_reference(
            Span(payload), ComplexRaw(16384, 0), wrap_formats, 8192, 0
        )


def test_bit_exact_checksum_v2_serializer_and_scale_trace() raises:
    var payload: List[UInt8] = [
        UInt8(0x00), UInt8(0xFF), UInt8(0x55), UInt8(0xAA),
        UInt8(0x80), UInt8(0x01), UInt8(0x7E), UInt8(0x42),
    ]
    var formats = fixed_phy_default_formats()
    var first = fixed_wifi_acquired_reference(
        Span(payload), ComplexRaw(12288, -4096), formats, 8192, 23
    )
    var second = fixed_wifi_acquired_reference(
        Span(payload), ComplexRaw(12288, -4096), formats, 8192, 23
    )
    var checksum = fixed_wifi_acquired_result_checksum(first)
    assert_equal(checksum, fixed_wifi_acquired_result_checksum(second))
    assert_equal(checksum, UInt64(14475604976949752913))
    var first_text = fixed_wifi_acquired_canonical_rtl_vectors(first, formats)
    # Independently computed FNV-1a pins every UTF-8 artifact byte.
    assert_equal(
        _oracle_fnv1a_text(StringSlice(first_text)),
        UInt64(3826299094601560237),
    )
    var second_text = fixed_wifi_acquired_canonical_rtl_vectors(second, formats)
    assert_equal(first_text, second_text)
    assert_true("MWDSP-FIXED-WIFI-ACQUIRED-V2\n" in first_text)
    assert_true("version=2\n" in first_text)
    assert_true("boundary_source=detected-packet-start\n" in first_text)
    assert_true("known_timing_role=post-decode-composition-audit-only\n" in first_text)
    assert_true("stage=acquired-ltf-slice\n" in first_text)
    assert_true("stage=acquired-data-slice\n" in first_text)
    assert_true("stage=stf-ifft-registers\n" in first_text)
    assert_true("rounding=nearest-away\n" in first_text)
    assert_true("overflow=saturate\n" in first_text)
    assert_true("stride=1\n" in first_text)
    assert_true("MWDSP-FIXED-WIFI-ACQUIRED-CHECKSUM-V2\n" in first_text)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
