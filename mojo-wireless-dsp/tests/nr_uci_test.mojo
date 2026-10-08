from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.nr import (
    NR_UCI_SCHEME_SMALL_BLOCK,
    NR_UCI_SCHEME_POLAR,
    nr_uci_crc_length,
    nr_uci_code_block_count,
    nr_pucch_uci_capacity,
    nr_uci_encode,
    nr_uci_decode,
)


def _payload(length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(UInt8((index * 3 + index // 2 + 1) & 1))
    return result^


def _llrs(bits: Span[UInt8, ...]) -> List[Float64]:
    var result = List[Float64](capacity=len(bits))
    for index in range(len(bits)):
        result.append(24.0 if bits[index] == 0 else -24.0)
    return result^


def _pack_first_64(bits: Span[UInt8, ...]) -> UInt64:
    var result = UInt64(0)
    for index in range(64):
        result = (result << UInt64(1)) | UInt64(bits[index])
    return result


def _pack_last_32(bits: Span[UInt8, ...]) -> UInt32:
    var result = UInt32(0)
    for index in range(len(bits) - 32, len(bits)):
        result = (result << UInt32(1)) | UInt32(bits[index])
    return result


def test_uci_small_block_full_rate_match_roundtrip() raises:
    var payload = _payload(7)
    var encoded = nr_uci_encode(Span(payload), 72)
    assert_equal(encoded.scheme, NR_UCI_SCHEME_SMALL_BLOCK)
    assert_equal(encoded.code_blocks, 1)
    assert_equal(encoded.crc_bits, 0)
    assert_equal(len(encoded.bits), 72)
    var decoded = nr_uci_decode(Span(_llrs(Span(encoded.bits))), 7)
    assert_equal(decoded.bits, payload)
    assert_true(decoded.crc_ok and decoded.parity_ok)


def test_uci_crc6_pc_polar_static_vector_and_roundtrip() raises:
    var payload = _payload(12)
    var encoded = nr_uci_encode(Span(payload), 96)
    assert_equal(encoded.scheme, NR_UCI_SCHEME_POLAR)
    assert_equal(encoded.crc_bits, 6)
    assert_equal(encoded.parity_check_bits, 3)
    assert_equal(_pack_first_64(Span(encoded.bits)), UInt64(0x44E04FC1BBB60D87))
    assert_equal(_pack_last_32(Span(encoded.bits)), UInt32(0x9607D8F3))
    var decoded = nr_uci_decode(Span(_llrs(Span(encoded.bits))), 12)
    assert_equal(decoded.bits, payload)
    assert_true(decoded.crc_ok and decoded.parity_ok)


def test_uci_crc11_polar_static_vector_and_roundtrip() raises:
    var payload = _payload(20)
    var encoded = nr_uci_encode(Span(payload), 128)
    assert_equal(encoded.crc_bits, 11)
    assert_equal(encoded.parity_check_bits, 0)
    assert_equal(_pack_first_64(Span(encoded.bits)), UInt64(0x3B3934B751B99C08))
    assert_equal(_pack_last_32(Span(encoded.bits)), UInt32(0xBBD2DDAB))
    var decoded = nr_uci_decode(Span(_llrs(Span(encoded.bits))), 20)
    assert_equal(decoded.bits, payload)
    assert_true(decoded.crc_ok and decoded.parity_ok)


def test_uci_two_block_segmentation_roundtrip() raises:
    var payload = _payload(400)
    var encoded = nr_uci_encode(Span(payload), 1152)
    assert_equal(encoded.code_blocks, 2)
    assert_equal(encoded.crc_bits, 11)
    assert_equal(encoded.padded_payload_bits, 0)
    var decoded = nr_uci_decode(Span(_llrs(Span(encoded.bits))), 400)
    assert_equal(decoded.code_blocks, 2)
    assert_equal(decoded.bits, payload)
    assert_true(decoded.crc_ok and decoded.parity_ok)


def test_pucch_capacity_and_segmentation_thresholds() raises:
    assert_equal(nr_pucch_uci_capacity(2, 3, 2), 96)
    assert_equal(nr_pucch_uci_capacity(3, 2, 8), 384)
    assert_equal(
        nr_pucch_uci_capacity(
            3, 2, 8, spreading_factor=2, pi_over_2_bpsk=True
        ),
        96,
    )
    assert_equal(nr_pucch_uci_capacity(4, 1, 10, spreading_factor=4), 60)
    assert_equal(nr_uci_crc_length(12), 6)
    assert_equal(nr_uci_crc_length(20), 11)
    assert_equal(nr_uci_code_block_count(359, 1088), 1)
    assert_equal(nr_uci_code_block_count(360, 1088), 2)
    assert_equal(nr_uci_code_block_count(1013, 1024), 2)


def test_uci_table_config_integer_domain_oracles() raises:
    # Exhaust the bounded payload domain for CRC and code-block selection.
    for payload_length in range(3, 1707):
        var expected_crc = (
            0
            if payload_length <= 11
            else 6 if payload_length <= 19 else 11
        )
        assert_equal(nr_uci_crc_length(payload_length), expected_crc)
        var expected_blocks = (
            2
            if payload_length >= 360 or payload_length >= 1013
            else 1
        )
        assert_equal(
            nr_uci_code_block_count(payload_length, 1088),
            expected_blocks,
        )

    # Independent products for every supported PUCCH format and spreading
    # choice.  No encoder/decoder round trip supplies an expected value.
    for resource_blocks in [1, 3, 17]:
        for uci_symbols in [1, 2, 10]:
            for spreading_factor in [1, 2, 4]:
                assert_equal(
                    nr_pucch_uci_capacity(
                        2,
                        resource_blocks,
                        uci_symbols,
                        spreading_factor=spreading_factor,
                    ),
                    (16 // spreading_factor)
                    * resource_blocks
                    * uci_symbols,
                )
                for pi_over_2_bpsk in [False, True]:
                    var bits_per_re = 1 if pi_over_2_bpsk else 2
                    assert_equal(
                        nr_pucch_uci_capacity(
                            3,
                            resource_blocks,
                            uci_symbols,
                            spreading_factor=spreading_factor,
                            pi_over_2_bpsk=pi_over_2_bpsk,
                        ),
                        (12 * bits_per_re // spreading_factor)
                        * resource_blocks
                        * uci_symbols,
                    )
    for uci_symbols in [1, 2, 10]:
        for spreading_factor in [2, 4]:
            for pi_over_2_bpsk in [False, True]:
                var bits_per_re = 1 if pi_over_2_bpsk else 2
                assert_equal(
                    nr_pucch_uci_capacity(
                        4,
                        1,
                        uci_symbols,
                        spreading_factor=spreading_factor,
                        pi_over_2_bpsk=pi_over_2_bpsk,
                    ),
                    (12 * bits_per_re // spreading_factor) * uci_symbols,
                )


def test_uci_validation() raises:
    var too_short: List[UInt8] = [0, 1]
    with assert_raises():
        _ = nr_uci_encode(Span(too_short), 32)
    var invalid: List[UInt8] = [0, 1, 2]
    with assert_raises():
        _ = nr_uci_encode(Span(invalid), 32)
    with assert_raises():
        _ = nr_pucch_uci_capacity(4, 2, 4, spreading_factor=2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
