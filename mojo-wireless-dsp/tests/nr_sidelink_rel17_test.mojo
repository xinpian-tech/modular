"""Independent/static/property/edge evidence for Rel-17 SCI-1A/PSCCH.

Static field vectors transcribe TS 38.212 V17.13.0 clause 8.3.1.1.  CRC and
packed-LFSR Gold oracles are independent scalar transcriptions of TS 38.212
clause 7.3.2 and TS 38.211 clause 5.2.1; they do not call production helpers.
Mapping expectations follow TS 38.211 clauses 8.3.2.3/8.4.1.3.2 and TS 38.213
clause 16.4.
"""

from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.sidelink_rel17 import (
    NRSLSCI1AConfig,
    NRSLSCI1AFields,
    nr_sl_sci1a_frequency_assignment_bits,
    nr_sl_sci1a_payload_bit_count,
    nr_sl_sci1a_pack,
    nr_sl_sci_crc24c,
    nr_sl_sci_crc24c_attach,
    nr_sl_sci_crc24c_check,
    nr_sl_pscch_rate_matched_bit_count,
    nr_sl_pscch_scramble,
    nr_sl_pscch_descramble_llrs,
    nr_sl_pscch_dmrs_c_init,
    nr_sl_pscch_dmrs,
    nr_sl_pscch_data_resource_elements,
    nr_sl_pscch_dmrs_resource_elements,
    nr_sl_pscch_encode,
    nr_sl_pscch_decode,
)


def _fixture_config() raises -> NRSLSCI1AConfig:
    return NRSLSCI1AConfig(10, 3, 16, 3, 2, 2, 4, True)


def _fixture_fields() -> NRSLSCI1AFields:
    return NRSLSCI1AFields(
        6,
        0x12B,
        0x101,
        9,
        2,
        2,
        3,
        True,
        21,
        2,
        True,
        True,
    )


def _fixture_payload() raises -> List[UInt8]:
    return nr_sl_sci1a_pack(_fixture_config(), _fixture_fields())


def _independent_crc24c(payload: List[UInt8]) -> UInt64:
    # Literal MSB-first long division, separate from modem.crc.
    var register = UInt64(0)
    comptime top = UInt64(1) << UInt64(23)
    comptime mask = (UInt64(1) << UInt64(24)) - UInt64(1)
    comptime polynomial = UInt64(0xB2B117)
    for index in range(24 + len(payload)):
        var bit = UInt64(1) if index < 24 else UInt64(payload[index - 24])
        var feedback = UInt64(1) if (register & top) != 0 else UInt64(0)
        feedback ^= bit
        register = (register << UInt64(1)) & mask
        if feedback != 0:
            register ^= polynomial
    return register


def _packed_x1_step(state: UInt32) -> UInt32:
    var feedback = (state ^ (state >> UInt32(3))) & UInt32(1)
    return (state >> UInt32(1)) | (feedback << UInt32(30))


def _packed_x2_step(state: UInt32) -> UInt32:
    var feedback = (
        state
        ^ (state >> UInt32(1))
        ^ (state >> UInt32(2))
        ^ (state >> UInt32(3))
    ) & UInt32(1)
    return (state >> UInt32(1)) | (feedback << UInt32(30))


def _independent_gold_with_c_init(
    c_init: UInt32, length: Int,
) -> List[UInt8]:
    # Packed 31-bit state is structurally distinct from production arrays.
    var x1 = UInt32(1)
    var x2 = c_init
    for _ in range(1600):
        x1 = _packed_x1_step(x1)
        x2 = _packed_x2_step(x2)
    var output = List[UInt8](capacity=length)
    for _ in range(length):
        output.append(UInt8((x1 ^ x2) & UInt32(1)))
        x1 = _packed_x1_step(x1)
        x2 = _packed_x2_step(x2)
    return output^


def _independent_pscch_gold(length: Int) -> List[UInt8]:
    return _independent_gold_with_c_init(UInt32(1010), length)


def _static_bit_checksum(bits: List[UInt8]) -> UInt64:
    var checksum = UInt64(1469598103934665603)
    for index in range(len(bits)):
        checksum = (
            checksum ^ (UInt64(bits[index]) + UInt64(index + 1))
        ) * UInt64(1099511628211)
    return checksum


def _reference_ceil_log2(value: Int) -> Int:
    var threshold = 1
    var result = 0
    while threshold < value:
        threshold *= 2
        result += 1
    return result


def test_sci1a_exact_widths_and_rel17_static_pack() raises:
    var n_values: List[Int] = [1, 2, 3, 4, 5, 10, 27]
    var expected_two: List[Int] = [0, 2, 3, 4, 4, 6, 9]
    var expected_three: List[Int] = [0, 3, 4, 5, 6, 9, 13]
    for index in range(len(n_values)):
        assert_equal(
            nr_sl_sci1a_frequency_assignment_bits(n_values[index], 2),
            expected_two[index],
        )
        assert_equal(
            nr_sl_sci1a_frequency_assignment_bits(n_values[index], 3),
            expected_three[index],
        )

    var config = _fixture_config()
    assert_equal(nr_sl_sci1a_payload_bit_count(config), 44)
    var actual = nr_sl_sci1a_pack(config, _fixture_fields())
    # 101 | 100101011 | 100000001 | 1001 | 10 | 10 | 11 | 1 |
    # 10101 | 10 | 1 | 000 | 1.  The last bit is the Rel-17 flag.
    var expected: List[UInt8] = [
        1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1,
        1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1,
        0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1,
        0, 1, 0, 1, 1, 0, 1, 0, 0, 0, 1,
    ]
    assert_equal(actual, expected)


def test_sidelink_table_configs_against_integer_domain_oracles() raises:
    for number_subchannels in range(1, 28):
        var combinations_two = (
            number_subchannels * (number_subchannels + 1) // 2
        )
        var combinations_three = (
            number_subchannels
            * (number_subchannels + 1)
            * (2 * number_subchannels + 1)
            // 6
        )
        assert_equal(
            nr_sl_sci1a_frequency_assignment_bits(
                number_subchannels, 2
            ),
            _reference_ceil_log2(combinations_two),
        )
        assert_equal(
            nr_sl_sci1a_frequency_assignment_bits(
                number_subchannels, 3
            ),
            _reference_ceil_log2(combinations_three),
        )

    # Independent field-width sum over a broad configuration product.
    for max_num_per_reserve in [2, 3]:
        for reserve_period_entries in [0, 1, 3, 16]:
            for dmrs_pattern_count in [1, 2, 3]:
                for additional_mcs_tables in [0, 1, 2]:
                    for psfch_period in [0, 1, 2, 4]:
                        var config = NRSLSCI1AConfig(
                            10,
                            max_num_per_reserve,
                            reserve_period_entries,
                            dmrs_pattern_count,
                            additional_mcs_tables,
                            psfch_period,
                            4,
                        )
                        var frequency_combinations = (
                            10 * 11 // 2
                            if max_num_per_reserve == 2
                            else 10 * 11 * 21 // 6
                        )
                        var expected = (
                            3
                            + _reference_ceil_log2(
                                frequency_combinations
                            )
                            + (5 if max_num_per_reserve == 2 else 9)
                            + (
                                0
                                if reserve_period_entries == 0
                                else _reference_ceil_log2(
                                    reserve_period_entries
                                )
                            )
                            + _reference_ceil_log2(dmrs_pattern_count)
                            + 2
                            + 2
                            + 1
                            + 5
                            + additional_mcs_tables
                            + (
                                1
                                if psfch_period == 2 or psfch_period == 4
                                else 0
                            )
                            + 4
                        )
                        assert_equal(
                            nr_sl_sci1a_payload_bit_count(config), expected
                        )

    for resource_blocks in [10, 12, 15, 20, 25]:
        for duration_symbols in [2, 3]:
            assert_equal(
                nr_sl_pscch_rate_matched_bit_count(
                    resource_blocks, duration_symbols
                ),
                18 * resource_blocks * duration_symbols,
            )

    for numerology in range(4):
        for slot_number in [0, 10 * (1 << numerology) - 1]:
            for symbol in [0, 13]:
                for scrambling_id in [0, 321, 65535]:
                    var modulus = UInt64(1) << UInt64(31)
                    var time_term = UInt64(
                        14 * slot_number + symbol + 1
                    )
                    var expected = (
                        (((UInt64(1) << UInt64(17)) * time_term)
                            % modulus)
                        * UInt64(2 * scrambling_id + 1)
                        + UInt64(2 * scrambling_id)
                    ) % modulus
                    assert_equal(
                        nr_sl_pscch_dmrs_c_init(
                            slot_number,
                            symbol,
                            scrambling_id,
                            numerology=numerology,
                        ),
                        UInt32(expected),
                    )


def test_sci_crc_static_independent_and_unmasked() raises:
    var payload = _fixture_payload()
    var oracle = _independent_crc24c(payload)
    assert_equal(oracle, UInt64(0x1B4A25))
    assert_equal(nr_sl_sci_crc24c(Span(payload)), oracle)
    var attached = nr_sl_sci_crc24c_attach(Span(payload))
    assert_equal(len(attached), 68)
    var expected_crc: List[UInt8] = [
        0, 0, 0, 1, 1, 0, 1, 1,
        0, 1, 0, 0, 1, 0, 1, 0,
        0, 0, 1, 0, 0, 1, 0, 1,
    ]
    for index in range(24):
        assert_equal(attached[44 + index], expected_crc[index])
    assert_true(nr_sl_sci_crc24c_check(Span(attached)))
    attached[67] ^= 1
    assert_true(not nr_sl_sci_crc24c_check(Span(attached)))


def test_pscch_gold_static_independent_qpsk_and_involution() raises:
    var zeros = List[UInt8](length=64, fill=UInt8(0))
    var actual = nr_sl_pscch_scramble(Span(zeros))
    var expected: List[UInt8] = [
        0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1,
        0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        0, 1, 1, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 1, 0, 1, 1, 0,
    ]
    assert_equal(actual, expected)
    assert_equal(actual, _independent_pscch_gold(64))
    var physical_llrs = List[Float64](capacity=64)
    for bit in expected:
        physical_llrs.append(8.0 if bit == 0 else -8.0)
    var descrambled = nr_sl_pscch_descramble_llrs(Span(physical_llrs))
    for llr in descrambled:
        assert_equal(llr, 8.0)

    var bits = List[UInt8](capacity=257)
    for index in range(257):
        bits.append(UInt8((index * 17 + index // 3 + 1) & 1))
    var once = nr_sl_pscch_scramble(Span(bits))
    var twice = nr_sl_pscch_scramble(Span(once))
    assert_equal(twice, bits)

    var payload = _fixture_payload()
    var encoded = nr_sl_pscch_encode(Span(payload), 10, 2)
    comptime inverse_sqrt_two = 0.7071067811865475
    for index in range(len(encoded.qpsk_symbols)):
        var symbol = encoded.qpsk_symbols[index]
        assert_true(abs(abs(symbol.re) - inverse_sqrt_two) < 1.0e-15)
        assert_true(abs(abs(symbol.im) - inverse_sqrt_two) < 1.0e-15)
        assert_equal(
            symbol.re,
            inverse_sqrt_two
            if encoded.scrambled[2 * index] == 0
            else -inverse_sqrt_two,
        )
        assert_equal(
            symbol.im,
            inverse_sqrt_two
            if encoded.scrambled[2 * index + 1] == 0
            else -inverse_sqrt_two,
        )


def test_pscch_exact_resource_mapping_and_first_symbol_copy() raises:
    assert_equal(nr_sl_pscch_rate_matched_bit_count(10, 2), 360)
    assert_equal(nr_sl_pscch_rate_matched_bit_count(25, 3), 1350)
    var data = nr_sl_pscch_data_resource_elements(
        10, 2, first_available_symbol=3, first_resource_block=40
    )
    # 180 primary data RE plus the 90 copied first-symbol data RE.
    assert_equal(len(data), 270)
    assert_equal(data[0].symbol, 4)
    assert_equal(data[0].resource_block, 40)
    assert_equal(data[0].subcarrier, 0)
    assert_equal(data[0].sequence_index, 0)
    assert_true(not data[0].is_duplicate)
    assert_equal(data[1].subcarrier, 2)
    assert_equal(data[8].subcarrier, 11)
    assert_equal(data[9].resource_block, 41)
    assert_equal(data[90].symbol, 5)
    assert_equal(data[180].symbol, 3)
    assert_equal(data[180].sequence_index, 0)
    assert_true(data[180].is_duplicate)
    assert_equal(data[269].sequence_index, 89)

    var dmrs = nr_sl_pscch_dmrs_resource_elements(
        10, 2, first_available_symbol=3, first_resource_block=40
    )
    # 60 primary DM-RS RE plus the 30 copied first-symbol DM-RS RE.
    assert_equal(len(dmrs), 90)
    assert_equal(dmrs[0].subcarrier, 1)
    assert_equal(dmrs[0].sequence_index, 120)
    assert_equal(dmrs[1].subcarrier, 5)
    assert_equal(dmrs[2].subcarrier, 9)
    assert_equal(dmrs[30].symbol, 5)
    assert_equal(dmrs[30].sequence_index, 120)
    assert_equal(dmrs[60].symbol, 3)
    assert_equal(dmrs[60].sequence_index, 120)
    assert_true(dmrs[60].is_duplicate)
    for data_re in data:
        assert_true(
            data_re.subcarrier != 1
            and data_re.subcarrier != 5
            and data_re.subcarrier != 9
        )


def test_pscch_dmrs_static_c_init_and_independent_sequence() raises:
    assert_equal(nr_sl_pscch_dmrs_c_init(0, 1, 0), UInt32(0x40000))
    assert_equal(
        nr_sl_pscch_dmrs_c_init(19, 13, 65535, numerology=1),
        UInt32(0x7DD1FFFE),
    )
    assert_equal(
        nr_sl_pscch_dmrs_c_init(7, 4, 321), UInt32(0x056A0282)
    )
    var actual = nr_sl_pscch_dmrs(
        7, 4, 321, 10, first_resource_block=4
    )
    var bits = _independent_gold_with_c_init(UInt32(0x056A0282), 84)
    comptime scale = 0.7071067811865475
    assert_equal(len(actual), 30)
    for index in range(30):
        var source = 24 + 2 * index
        assert_equal(
            actual[index].re,
            scale if bits[source] == 0 else -scale,
        )
        assert_equal(
            actual[index].im,
            scale if bits[source + 1] == 0 else -scale,
        )


def test_full_pscch_chain_lengths_roundtrip_and_crc_verdict() raises:
    var payload = _fixture_payload()
    var encoded = nr_sl_pscch_encode(
        Span(payload),
        10,
        3,
        first_available_symbol=2,
        first_resource_block=17,
    )
    assert_equal(encoded.payload, payload)
    assert_equal(len(encoded.crc_attached), 68)
    assert_equal(len(encoded.input_interleaved), 68)
    assert_equal(len(encoded.polar_codeword), 512)
    assert_equal(len(encoded.rate_matched), 540)
    assert_equal(len(encoded.scrambled), 540)
    assert_equal(len(encoded.qpsk_symbols), 270)
    assert_equal(len(encoded.data_resource_elements), 360)
    assert_true(nr_sl_sci_crc24c_check(Span(encoded.crc_attached)))
    # Static digests from an independent Python transcription of clauses
    # 5.3.1, 5.4.1, 7.3.2--4, and 8.3.  The script used packed Gold state,
    # direct frozen-set selection, and an in-place Arikan transform.
    assert_equal(
        _static_bit_checksum(encoded.crc_attached),
        UInt64(11441014768396553611),
    )
    assert_equal(
        _static_bit_checksum(encoded.input_interleaved),
        UInt64(15702971395747559075),
    )
    assert_equal(
        _static_bit_checksum(encoded.polar_codeword),
        UInt64(13126936695110201379),
    )
    assert_equal(
        _static_bit_checksum(encoded.rate_matched),
        UInt64(13655966641939598184),
    )
    assert_equal(
        _static_bit_checksum(encoded.scrambled),
        UInt64(12108953134518977252),
    )

    var llrs = List[Float64](capacity=len(encoded.scrambled))
    for bit in encoded.scrambled:
        llrs.append(24.0 if bit == 0 else -24.0)
    var decoded = nr_sl_pscch_decode(Span(llrs), len(payload), 10, 3)
    assert_true(decoded.crc_ok)
    assert_equal(decoded.payload, payload)

    var descrambled = nr_sl_pscch_descramble_llrs(Span(llrs))
    for index in range(len(descrambled)):
        assert_equal(
            descrambled[index],
            24.0 if encoded.rate_matched[index] == 0 else -24.0,
        )


def test_sidelink_rel17_edge_validation() raises:
    with assert_raises():
        _ = nr_sl_sci1a_frequency_assignment_bits(0, 2)
    with assert_raises():
        _ = nr_sl_sci1a_frequency_assignment_bits(10, 4)
    with assert_raises():
        _ = NRSLSCI1AConfig(0, 2, 0, 1, 0, 0, 2)
    with assert_raises():
        _ = NRSLSCI1AConfig(28, 2, 0, 1, 0, 0, 2)
    with assert_raises():
        _ = NRSLSCI1AConfig(10, 1, 0, 1, 0, 0, 2)
    with assert_raises():
        _ = NRSLSCI1AConfig(10, 3, 17, 1, 0, 0, 2)
    with assert_raises():
        _ = NRSLSCI1AConfig(10, 3, 0, 4, 0, 0, 2)
    with assert_raises():
        _ = NRSLSCI1AConfig(10, 3, 0, 1, 3, 0, 2)
    with assert_raises():
        _ = NRSLSCI1AConfig(10, 3, 0, 1, 0, 3, 2)
    with assert_raises():
        _ = NRSLSCI1AConfig(10, 3, 0, 1, 0, 0, 1)

    var config = _fixture_config()
    var fields = _fixture_fields()
    fields.frequency_resource_assignment = 512
    with assert_raises():
        _ = nr_sl_sci1a_pack(config, fields)
    fields = _fixture_fields()
    fields.second_stage_sci_format = 3
    with assert_raises():
        _ = nr_sl_sci1a_pack(config, fields)
    fields = _fixture_fields()
    fields.mcs_index = 32
    with assert_raises():
        _ = nr_sl_sci1a_pack(config, fields)
    var no_conflict = NRSLSCI1AConfig(10, 3, 0, 1, 0, 0, 2)
    fields = NRSLSCI1AFields(1, 0, 0, 0, 0, 0, 0, False, 0)
    fields.conflict_information_receiver = True
    with assert_raises():
        _ = nr_sl_sci1a_pack(no_conflict, fields)

    var invalid_bits: List[UInt8] = [0, 2]
    with assert_raises():
        _ = nr_sl_sci_crc24c(Span(invalid_bits))
    with assert_raises():
        _ = nr_sl_sci_crc24c_attach(Span(invalid_bits))
    var short_crc = List[UInt8](length=24, fill=UInt8(0))
    with assert_raises():
        _ = nr_sl_sci_crc24c_check(Span(short_crc))
    with assert_raises():
        _ = nr_sl_pscch_scramble(Span(invalid_bits))
    with assert_raises():
        _ = nr_sl_pscch_rate_matched_bit_count(11, 2)
    with assert_raises():
        _ = nr_sl_pscch_rate_matched_bit_count(10, 4)
    with assert_raises():
        _ = nr_sl_pscch_data_resource_elements(
            25, 3, first_available_symbol=11
        )
    with assert_raises():
        _ = nr_sl_pscch_data_resource_elements(
            25, 2, first_resource_block=251
        )
    with assert_raises():
        _ = nr_sl_pscch_dmrs_c_init(10, 1, 0)
    with assert_raises():
        _ = nr_sl_pscch_dmrs_c_init(0, 14, 0)
    with assert_raises():
        _ = nr_sl_pscch_dmrs_c_init(0, 1, 65536)
    with assert_raises():
        _ = nr_sl_pscch_dmrs(0, 1, 0, 11)
    with assert_raises():
        _ = nr_sl_pscch_dmrs_resource_elements(11, 2)
    with assert_raises():
        _ = nr_sl_pscch_encode(Span(invalid_bits), 10, 2)
    var short_llrs = List[Float64](length=359, fill=0.0)
    with assert_raises():
        _ = nr_sl_pscch_decode(Span(short_llrs), 44, 10, 2)
    var bad_llrs = List[Float64](length=360, fill=0.0)
    bad_llrs[0] = nan[DType.float64]()
    with assert_raises():
        _ = nr_sl_pscch_descramble_llrs(Span(bad_llrs))
    bad_llrs[0] = inf[DType.float64]()
    with assert_raises():
        _ = nr_sl_pscch_descramble_llrs(Span(bad_llrs))

    var mutated = _fixture_config()
    mutated.number_subchannels = 0
    with assert_raises():
        _ = nr_sl_sci1a_payload_bit_count(mutated)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
