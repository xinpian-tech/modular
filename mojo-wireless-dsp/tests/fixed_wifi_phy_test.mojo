"""Acceptance tests for the connected fixed BCC/QPSK/OFDM mini-PHY."""

from std.collections import Span
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.backend.fixed_phy_reference import fixed_phy_default_formats
from wireless_dsp.backend.fixed_wifi_phy_reference import (
    fixed_wifi_bcc_ofdm_reference,
    fixed_wifi_phy_canonical_rtl_vectors,
    fixed_wifi_phy_result_checksum,
)


def _oracle_fnv1a_text(text: StringSlice) -> UInt64:
    var state = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        state ^= UInt64(UInt8(bytes[index]))
        state *= UInt64(1099511628211)
    return state


def _payload58() -> List[UInt8]:
    var result = List[UInt8](capacity=58)
    for index in range(58):
        result.append(UInt8((index * 13 + index // 5 + 1) & 1))
    return result^


def test_fixed_coded_phy_exposes_and_recovers_every_stage() raises:
    var formats = fixed_phy_default_formats()
    var payload = _payload58()
    var result = fixed_wifi_bcc_ofdm_reference(
        Span(payload),
        64,
        16,
        ComplexRaw(12288, -4096),
        formats,
        8192,
        pilot_symbols=4,
    )
    assert_equal(len(result.coded_bits), 128)
    assert_equal(len(result.phy.mapped_symbols), 64)
    assert_equal(len(result.phy.transmit_samples), 80)
    assert_equal(len(result.phy.equalized_symbols), 64)
    assert_equal(len(result.llrs_raw), 128)
    assert_equal(result.phy.decoded_bits, result.coded_bits)
    assert_equal(result.hard_viterbi.bits, payload)
    assert_equal(result.soft_viterbi.bits, payload)
    assert_equal(result.payload_bit_errors, 0)
    assert_equal(result.phy.audit.bit_errors, 0)
    assert_true(result.phy.audit.evm_rms < 0.001)
    assert_equal(result.hard_viterbi.final_state, 0)
    assert_equal(result.soft_viterbi.final_state, 0)
    for index in range(len(result.coded_bits)):
        assert_equal(result.llrs_raw[index] >= 0, result.coded_bits[index] == 0)


def test_fixed_coded_phy_is_bit_exact_and_serializable() raises:
    var formats = fixed_phy_default_formats()
    var payload = _payload58()
    var first = fixed_wifi_bcc_ofdm_reference(
        Span(payload), 64, 16, ComplexRaw(16384, 0), formats, 8192
    )
    var second = fixed_wifi_bcc_ofdm_reference(
        Span(payload), 64, 16, ComplexRaw(16384, 0), formats, 8192
    )
    var first_checksum = fixed_wifi_phy_result_checksum(
        first, formats.symbol
    )
    var second_checksum = fixed_wifi_phy_result_checksum(
        second, formats.symbol
    )
    assert_equal(first_checksum, second_checksum)
    assert_equal(first_checksum, UInt64(12301286675501406297))
    var vectors = fixed_wifi_phy_canonical_rtl_vectors(first, formats)
    # Independently computed FNV-1a pins every UTF-8 artifact byte.
    assert_equal(
        _oracle_fnv1a_text(StringSlice(vectors)),
        UInt64(4765869531272634902),
    )
    assert_true("stage=qpsk-grid\n" in vectors)
    assert_true("stage=soft-survivor-predecessors\n" in vectors)
    assert_true("MWDSP-FIXED-WIFI-PHY-CHECKSUM-V1\n" in vectors)


def test_fixed_coded_phy_rejects_shape_bits_and_metric_edges() raises:
    var formats = fixed_phy_default_formats()
    var short_payload: List[UInt8] = [0, 1]
    with assert_raises():
        _ = fixed_wifi_bcc_ofdm_reference(
            Span(short_payload),
            64,
            16,
            ComplexRaw(16384, 0),
            formats,
            8192,
        )
    var invalid = _payload58()
    invalid[7] = UInt8(2)
    with assert_raises():
        _ = fixed_wifi_bcc_ofdm_reference(
            Span(invalid),
            64,
            16,
            ComplexRaw(16384, 0),
            formats,
            8192,
        )
    var payload = _payload58()
    with assert_raises():
        _ = fixed_wifi_bcc_ofdm_reference(
            Span(payload),
            64,
            16,
            ComplexRaw(16384, 0),
            formats,
            8192,
            metric_storage_bits=14,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
