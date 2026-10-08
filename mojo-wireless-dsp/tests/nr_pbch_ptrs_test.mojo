from std.collections import Span
from std.math import cos, sin, sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.fec.polar_5g import (
    polar_5g_reliability_sequence,
    polar_5g_mother_code_length,
    polar_5g_frozen_mask,
    polar_5g_input_interleave,
    polar_5g_input_deinterleave,
    polar_5g_encode,
    polar_5g_decode_sc,
)
from wireless_dsp.wireless.nr.pbch import (
    nr_pbch_build_payload,
    nr_pbch_payload_interleave,
    nr_pbch_payload_deinterleave,
    nr_pbch_payload_scramble,
    nr_pbch_payload_descramble,
    nr_pbch_crc24c,
    nr_pbch_crc24c_append,
    nr_pbch_crc24c_check,
    nr_pbch_physical_scramble,
    nr_pbch_physical_descramble_llrs,
    nr_pbch_encode,
    nr_pbch_decode,
)
from wireless_dsp.wireless.nr.ptrs import (
    nr_pdsch_ptrs_density_from_thresholds,
    nr_pdsch_ptrs_c_init,
    nr_pdsch_ptrs_time_positions,
    nr_pdsch_ptrs_k_ref_re,
    nr_pdsch_ptrs_frequency_positions,
    nr_pdsch_ptrs_sequence,
    nr_map_pdsch_ptrs,
    nr_extract_pdsch_ptrs,
    nr_ptrs_estimate_common_phase,
    nr_ptrs_correct_common_phase,
)
from wireless_dsp.wireless.nr.grid import NRResourceGrid


def _count_ones(bits: Span[UInt8, ...]) -> Int:
    var result = 0
    for index in range(len(bits)):
        result += Int(bits[index])
    return result


def _assert_bit_prefix(
    actual: Span[UInt8, ...], expected: Span[UInt8, ...],
) raises:
    assert_true(len(actual) >= len(expected))
    for index in range(len(expected)):
        assert_equal(actual[index], expected[index])


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64,
) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _pbch_mib_vector() -> List[UInt8]:
    # First six bits are the MSBs of SFN=713; remaining fields are deterministic.
    var result: List[UInt8] = [
        1, 0, 1, 1, 0, 0, 1, 0,
        1, 1, 0, 0, 1, 0, 1, 0,
        1, 1, 1, 0, 0, 1, 0, 1,
    ]
    return result^


def _length_text(length: Int) -> String:
    var result = String()
    result.write(length)
    return result^


def _assert_checkpoint_metadata(
    metadata: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stages: List[String],
    dtypes: List[String],
    shapes: List[String],
    q_formats: List[String],
    layouts: List[String],
) raises:
    assert_equal(len(metadata), len(stages))
    assert_equal(len(metadata), len(dtypes))
    assert_equal(len(metadata), len(shapes))
    assert_equal(len(metadata), len(q_formats))
    assert_equal(len(metadata), len(layouts))
    for index in range(len(metadata)):
        assert_equal(metadata[index].testcase_id, testcase_id)
        assert_equal(metadata[index].stage, stages[index])
        assert_equal(metadata[index].dtype, dtypes[index])
        assert_equal(metadata[index].shape, shapes[index])
        assert_equal(metadata[index].stride, "1")
        assert_equal(metadata[index].q_format, q_formats[index])
        assert_equal(metadata[index].layout, layouts[index])
        assert_equal(metadata[index].scale, 1.0)
        assert_equal(metadata[index].version, 1)


def test_5g_polar_normative_tables_and_construction() raises:
    var reliability = polar_5g_reliability_sequence()
    assert_equal(len(reliability), 1024)
    var seen = List[UInt8](length=1024, fill=UInt8(0))
    for value in reliability:
        assert_true(value >= 0 and value < 1024)
        assert_equal(seen[value], UInt8(0))
        seen[value] = 1
    var expected_first: List[Int] = [0, 1, 2, 4, 8, 16, 32, 3, 5, 64, 9, 6, 17, 10, 18, 128]
    var expected_last: List[Int] = [959, 1011, 1013, 895, 1006, 1014, 1017, 1018, 991, 1020, 1007, 1015, 1019, 1021, 1022, 1023]
    for index in range(16):
        assert_equal(reliability[index], expected_first[index])
        assert_equal(reliability[1008 + index], expected_last[index])
    assert_equal(polar_5g_mother_code_length(56, 864, n_max=9), 9)

    var frozen = polar_5g_frozen_mask(56, 864, n_max=9)
    assert_equal(len(frozen), 512)
    var information_positions = List[Int]()
    for index in range(512):
        if frozen[index] == 0:
            information_positions.append(index)
    # Independently transcribed Q_I for PBCH from Table 5.3.1.2-1.
    assert_equal(information_positions, [
        247, 253, 254, 255, 367, 375, 379, 381, 382, 383,
        415, 431, 439, 441, 443, 444, 445, 446, 447, 463,
        469, 470, 471, 473, 474, 475, 476, 477, 478, 479,
        483, 485, 486, 487, 489, 490, 491, 492, 493, 494,
        495, 497, 498, 499, 500, 501, 502, 503, 504, 505,
        506, 507, 508, 509, 510, 511,
    ])

    var input: List[UInt8] = [1, 0, 0, 1, 1, 0, 1, 0, 1]
    var interleaved = polar_5g_input_interleave(Span(input))
    assert_equal(polar_5g_input_deinterleave(Span(interleaved)), input)


def test_5g_polar_puncturing_shortening_and_bit_interleaving() raises:
    var punctured_input: List[UInt8] = [1, 0, 1, 1, 0, 0, 1, 0, 1, 1]
    var punctured = polar_5g_encode(Span(punctured_input), 40)
    var punctured_llrs = List[Float64](capacity=40)
    for bit in punctured:
        punctured_llrs.append(100.0 if bit == 0 else -100.0)
    assert_equal(
        polar_5g_decode_sc(Span(punctured_llrs), len(punctured_input)),
        punctured_input,
    )

    var shortened_input: List[UInt8] = [
        1, 1, 0, 1, 0, 0, 1, 1, 0, 0,
        0, 1, 1, 1, 0, 1, 0, 1, 1, 0,
    ]
    var shortened = polar_5g_encode(
        Span(shortened_input), 40, bit_interleave=True
    )
    var shortened_llrs = List[Float64](capacity=40)
    for bit in shortened:
        shortened_llrs.append(100.0 if bit == 0 else -100.0)
    assert_equal(
        polar_5g_decode_sc(
            Span(shortened_llrs),
            len(shortened_input),
            bit_interleave=True,
        ),
        shortened_input,
    )


def test_pbch_payload_scrambling_and_crc_independent_vector() raises:
    var mib = _pbch_mib_vector()
    var payload = nr_pbch_build_payload(
        Span(mib), 713, 1, 42, 64
    )
    var expected_payload: List[UInt8] = [
        1, 0, 1, 1, 0, 0, 1, 0,
        1, 1, 0, 0, 1, 0, 1, 0,
        1, 1, 1, 0, 0, 1, 0, 1,
        1, 0, 0, 1, 1, 1, 0, 1,
    ]
    assert_equal(payload, expected_payload)
    var interleaved = nr_pbch_payload_interleave(Span(payload))
    var expected_interleaved: List[UInt8] = [
        1, 1, 1, 0, 0, 1, 0, 1,
        0, 1, 1, 1, 0, 0, 1, 0,
        1, 1, 1, 1, 0, 1, 1, 0,
        0, 1, 0, 0, 1, 0, 0, 1,
    ]
    assert_equal(interleaved, expected_interleaved)
    assert_equal(nr_pbch_payload_deinterleave(Span(interleaved)), payload)
    var scrambled = nr_pbch_payload_scramble(Span(interleaved), 321, 713, 64)
    var expected_scrambled: List[UInt8] = [
        1, 0, 1, 0, 0, 1, 0, 1,
        1, 0, 1, 1, 1, 1, 1, 0,
        0, 0, 1, 1, 0, 1, 1, 0,
        0, 0, 1, 0, 0, 1, 0, 0,
    ]
    assert_equal(scrambled, expected_scrambled)
    assert_equal(nr_pbch_payload_descramble(Span(scrambled), 321, 64), interleaved)
    assert_equal(nr_pbch_crc24c(Span(scrambled)), UInt64(0x2C005D))
    var attached = nr_pbch_crc24c_append(Span(scrambled))
    assert_equal(len(attached), 56)
    assert_true(nr_pbch_crc24c_check(Span(attached)))


def test_pbch_full_encoder_independent_checkpoints_and_decode() raises:
    var mib = _pbch_mib_vector()
    var transmit = nr_pbch_encode(Span(mib), 321, 713, 1, 42, 64)
    assert_equal(len(transmit.crc_attached), 56)
    assert_equal(len(transmit.polar_codeword), 512)
    assert_equal(len(transmit.rate_matched), 864)
    assert_equal(len(transmit.physical_channel_bits), 864)
    assert_true(nr_pbch_crc24c_check(Span(transmit.crc_attached)))
    assert_equal(_count_ones(Span(transmit.polar_codeword)), 256)
    assert_equal(_count_ones(Span(transmit.rate_matched)), 428)
    assert_equal(_count_ones(Span(transmit.physical_channel_bits)), 421)
    var tx_stages: List[String] = [
        "mib-input",
        "payload",
        "interleaved-payload",
        "payload-scrambled",
        "crc-attached-information",
        "polar-codeword",
        "rate-matched-bits",
        "physical-channel-bits",
    ]
    var tx_dtypes: List[String] = [
        "uint8", "uint8", "uint8", "uint8", "uint8", "uint8", "uint8",
        "uint8",
    ]
    var tx_shapes: List[String] = [
        _length_text(len(mib)),
        _length_text(len(transmit.payload)),
        _length_text(len(transmit.interleaved_payload)),
        _length_text(len(transmit.payload_scrambled)),
        _length_text(len(transmit.crc_attached)),
        _length_text(len(transmit.polar_codeword)),
        _length_text(len(transmit.rate_matched)),
        _length_text(len(transmit.physical_channel_bits)),
    ]
    var tx_q_formats: List[String] = [
        "binary-u1", "binary-u1", "binary-u1", "binary-u1", "binary-u1",
        "binary-u1", "binary-u1", "binary-u1",
    ]
    var tx_layouts: List[String] = [
        "bit-per-byte", "bit-per-byte", "bit-per-byte", "bit-per-byte",
        "bit-per-byte", "bit-per-byte", "bit-per-byte", "bit-per-byte",
    ]
    _assert_checkpoint_metadata(
        transmit.checkpoint_metadata,
        "nr-pbch-tx",
        tx_stages,
        tx_dtypes,
        tx_shapes,
        tx_q_formats,
        tx_layouts,
    )
    var expected_mother_prefix: List[UInt8] = [
        0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1,
        0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 0, 0, 0, 1,
        0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0,
        0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 0,
    ]
    _assert_bit_prefix(Span(transmit.polar_codeword), Span(expected_mother_prefix))
    var expected_rate_prefix: List[UInt8] = [
        0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1,
        0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 0, 0, 0, 1,
        0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0,
        0, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1,
    ]
    _assert_bit_prefix(Span(transmit.rate_matched), Span(expected_rate_prefix))
    var expected_physical_prefix: List[UInt8] = [
        0, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0, 1, 1, 0,
        1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1,
        0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1,
        1, 0, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0,
    ]
    _assert_bit_prefix(
        Span(transmit.physical_channel_bits), Span(expected_physical_prefix)
    )
    assert_equal(
        nr_pbch_physical_scramble(
            Span(transmit.rate_matched), 321, 42, 64
        ),
        transmit.physical_channel_bits,
    )

    var llrs = List[Float64](capacity=864)
    for bit in transmit.physical_channel_bits:
        llrs.append(80.0 if bit == 0 else -80.0)
    var descrambled = nr_pbch_physical_descramble_llrs(
        Span(llrs), 321, 42, 64
    )
    for index in range(len(descrambled)):
        assert_equal(descrambled[index] > 0.0, transmit.rate_matched[index] == 0)
    var invalid_llrs: List[Float64] = [nan[DType.float64](), 1.0]
    with assert_raises():
        _ = nr_pbch_physical_descramble_llrs(
            Span(invalid_llrs), 321, 42, 64
        )
    invalid_llrs[0] = inf[DType.float64]()
    with assert_raises():
        _ = nr_pbch_physical_descramble_llrs(
            Span(invalid_llrs), 321, 42, 64
        )
    var decoded = nr_pbch_decode(Span(llrs), 321, 42, 64)
    assert_true(decoded.crc_ok)
    assert_equal(decoded.mib_bits, mib)
    assert_equal(decoded.system_frame_number, 713)
    assert_equal(decoded.half_frame, 1)
    assert_equal(decoded.ssb_index, 42)
    assert_equal(decoded.k_ssb_msb, -1)
    var rx_stages: List[String] = [
        "physical-channel-llrs",
        "physical-descrambled-llrs",
        "decoded-information-with-crc",
        "payload",
        "mib-bits",
        "decoded-fields",
        "crc-ok",
    ]
    var rx_dtypes: List[String] = [
        "float64", "float64", "uint8", "uint8", "uint8", "int", "bool",
    ]
    var rx_shapes: List[String] = [
        _length_text(len(llrs)),
        _length_text(len(llrs)),
        _length_text(len(decoded.decoded_information)),
        _length_text(len(decoded.payload)),
        _length_text(len(decoded.mib_bits)),
        "4",
        "1",
    ]
    var rx_q_formats: List[String] = [
        "floating", "floating", "binary-u1", "binary-u1", "binary-u1",
        "integer", "boolean",
    ]
    var rx_layouts: List[String] = [
        "linear", "linear", "bit-per-byte", "bit-per-byte", "bit-per-byte",
        "sfn-half-frame-ssb-index-k-ssb-msb", "scalar",
    ]
    _assert_checkpoint_metadata(
        decoded.checkpoint_metadata,
        "nr-pbch-rx",
        rx_stages,
        rx_dtypes,
        rx_shapes,
        rx_q_formats,
        rx_layouts,
    )

    transmit.crc_attached[5] ^= 1
    assert_true(not nr_pbch_crc24c_check(Span(transmit.crc_attached)))


def test_pbch_payload_rules_for_every_standard_lmax() raises:
    var mib = _pbch_mib_vector()
    var lmax_values: List[Int] = [4, 8, 10, 20, 64]
    var ssb_values: List[Int] = [3, 7, 9, 19, 63]
    for case_index in range(len(lmax_values)):
        var payload = nr_pbch_build_payload(
            Span(mib),
            713,
            case_index & 1,
            ssb_values[case_index],
            lmax_values[case_index],
            k_ssb_msb=1,
        )
        var interleaved = nr_pbch_payload_interleave(Span(payload))
        var scrambled = nr_pbch_payload_scramble(
            Span(interleaved), 777, 713, lmax_values[case_index]
        )
        var recovered = nr_pbch_payload_descramble(
            Span(scrambled), 777, lmax_values[case_index]
        )
        assert_equal(
            nr_pbch_payload_deinterleave(Span(recovered)), payload
        )
    # Lmax=20 exercises two protected SSB-index MSBs and a separate k_SSB bit.
    var transmit = nr_pbch_encode(
        Span(mib), 777, 713, 1, 19, 20, k_ssb_msb=1
    )
    var llrs = List[Float64](capacity=864)
    for bit in transmit.physical_channel_bits:
        llrs.append(80.0 if bit == 0 else -80.0)
    var decoded = nr_pbch_decode(Span(llrs), 777, 19, 20)
    assert_true(decoded.crc_ok)
    assert_equal(decoded.ssb_index, 19)
    assert_equal(decoded.k_ssb_msb, 1)


def test_ptrs_density_time_frequency_and_sequence_vectors() raises:
    var absent = nr_pdsch_ptrs_density_from_thresholds(4, 20, 5, 10, 15, 29, 4, 12)
    assert_true(not absent.enabled)
    absent = nr_pdsch_ptrs_density_from_thresholds(15, 3, 5, 10, 15, 29, 4, 12)
    assert_true(not absent.enabled)
    var sparse = nr_pdsch_ptrs_density_from_thresholds(7, 4, 5, 10, 15, 29, 4, 12)
    assert_true(sparse.enabled)
    assert_equal(sparse.time_density, 4)
    assert_equal(sparse.frequency_density, 2)
    var medium = nr_pdsch_ptrs_density_from_thresholds(12, 12, 5, 10, 15, 29, 4, 12)
    assert_equal(medium.time_density, 2)
    assert_equal(medium.frequency_density, 4)
    var dense = nr_pdsch_ptrs_density_from_thresholds(20, 12, 5, 10, 15, 29, 4, 12)
    assert_equal(dense.time_density, 1)

    var dmrs: List[Int] = [2, 11]
    assert_equal(
        nr_pdsch_ptrs_time_positions(14, 2, Span(dmrs)),
        [0, 4, 6, 8, 10, 13],
    )
    var double_dmrs: List[Int] = [0, 1]
    assert_equal(
        nr_pdsch_ptrs_time_positions(8, 2, Span(double_dmrs)),
        [3, 5, 7],
    )
    var no_dmrs = List[Int]()
    assert_equal(
        nr_pdsch_ptrs_time_positions(2, 2, Span(no_dmrs)), List[Int]()
    )
    assert_equal(
        nr_pdsch_ptrs_time_positions(4, 4, Span(no_dmrs)), List[Int]()
    )
    assert_equal(nr_pdsch_ptrs_k_ref_re(1000, 1, 2), 6)
    assert_equal(
        nr_pdsch_ptrs_k_ref_re(1017, 2, 3, enhanced_dmrs=True), 10
    )
    var frequencies = nr_pdsch_ptrs_frequency_positions(
        10, 0x1234, 4, 1000, 1, 2
    )
    assert_equal(frequencies, [6, 54, 102])
    assert_equal(
        nr_pdsch_ptrs_c_init(3, 2, 42, 0), UInt32(0x1DE20054)
    )
    assert_equal(
        nr_pdsch_ptrs_c_init(
            3, 2, 42, 0, symbols_per_slot=12
        ),
        UInt32(0x19E60054),
    )
    var sequence = nr_pdsch_ptrs_sequence(
        Span(frequencies), 0, 3, 2, 42, 0, 1000, 1
    )
    var scale = 1.0 / sqrt(2.0)
    _assert_complex_close(sequence[0], Complex64(-scale, -scale), 1.0e-12)
    _assert_complex_close(sequence[1], Complex64(scale, -scale), 1.0e-12)
    _assert_complex_close(sequence[2], Complex64(-scale, -scale), 1.0e-12)

    # Enhanced type-2 uses k=12n+k'+Delta(+4 for k'=2,3) and r(4n+k').
    var enhanced_frequencies = nr_pdsch_ptrs_frequency_positions(
        10, 0x1234, 4, 1017, 2, 3, enhanced_dmrs=True
    )
    assert_equal(enhanced_frequencies, [10, 58, 106])
    var enhanced_sequence = nr_pdsch_ptrs_sequence(
        Span(enhanced_frequencies),
        0,
        3,
        2,
        42,
        0,
        1017,
        2,
        enhanced_dmrs=True,
    )
    # Independent Gold indices are r(2), r(18), and r(34).
    _assert_complex_close(enhanced_sequence[0], Complex64(scale, -scale), 1.0e-12)
    _assert_complex_close(enhanced_sequence[1], Complex64(scale, -scale), 1.0e-12)
    _assert_complex_close(enhanced_sequence[2], Complex64(-scale, -scale), 1.0e-12)


def test_ptrs_table_configs_against_exhaustive_integer_oracles() raises:
    # Exhaust every branch of both density threshold tables on a bounded MCS
    # domain and on each side of the two RB thresholds.
    for scheduled_mcs in range(31):
        for scheduled_resource_blocks in [1, 3, 4, 11, 12, 275]:
            var actual = nr_pdsch_ptrs_density_from_thresholds(
                scheduled_mcs,
                scheduled_resource_blocks,
                5,
                10,
                15,
                29,
                4,
                12,
            )
            var enabled = (
                scheduled_mcs >= 5
                and scheduled_mcs < 29
                and scheduled_resource_blocks >= 4
            )
            assert_equal(actual.enabled, enabled)
            if enabled:
                var expected_time = (
                    4
                    if scheduled_mcs < 10
                    else 2 if scheduled_mcs < 15 else 1
                )
                var expected_frequency = (
                    2 if scheduled_resource_blocks < 12 else 4
                )
                assert_equal(actual.time_density, expected_time)
                assert_equal(actual.frequency_density, expected_frequency)

    for symbols_per_slot in [12, 14]:
        for slot in [0, 1, 3, 100000]:
            for symbol in [0, symbols_per_slot - 1]:
                for n_id in [0, 42, 65535]:
                    for n_scid in [0, 1]:
                        var modulus = UInt64(1) << UInt64(31)
                        var time_term = (
                            UInt64(symbols_per_slot)
                            * (UInt64(slot) % modulus)
                            + UInt64(symbol + 1)
                        ) % modulus
                        var expected = (
                            (((UInt64(1) << UInt64(17)) * time_term)
                                % modulus)
                            * UInt64(2 * n_id + 1)
                            + UInt64(2 * n_id + n_scid)
                        ) % modulus
                        assert_equal(
                            nr_pdsch_ptrs_c_init(
                                slot,
                                symbol,
                                n_id,
                                n_scid,
                                symbols_per_slot=symbols_per_slot,
                            ),
                            UInt32(expected),
                        )

    var no_dmrs = List[Int]()
    for allocation_symbols in range(1, 15):
        for time_density in [1, 2, 4]:
            var actual_positions = nr_pdsch_ptrs_time_positions(
                allocation_symbols, time_density, Span(no_dmrs)
            )
            var expected_positions = List[Int]()
            if not (
                (allocation_symbols == 2 and time_density != 1)
                or (allocation_symbols == 4 and time_density == 4)
            ):
                var position = 0
                while position < allocation_symbols:
                    expected_positions.append(position)
                    position += time_density
            assert_equal(actual_positions, expected_positions)

    # Complete literal transcription of Table 7.4.1.2.2-1 for every port the
    # bounded API supports, including enhanced-DMRS rows.
    var type1_ports: List[Int] = [1000, 1001, 1002, 1003]
    var type1_values: List[Int] = [
        0, 2, 6, 8,  2, 4, 8, 10,
        1, 3, 7, 9,  3, 5, 9, 11,
    ]
    for port_index in range(len(type1_ports)):
        for offset in range(4):
            assert_equal(
                nr_pdsch_ptrs_k_ref_re(
                    type1_ports[port_index], 1, offset
                ),
                type1_values[4 * port_index + offset],
            )
    var type1_enhanced_ports: List[Int] = [1008, 1009, 1010, 1011]
    var type1_enhanced_values: List[Int] = [
        4, 6, 10, 0,  6, 8, 0, 2,
        5, 7, 11, 1,  7, 9, 1, 3,
    ]
    for port_index in range(len(type1_enhanced_ports)):
        for offset in range(4):
            assert_equal(
                nr_pdsch_ptrs_k_ref_re(
                    type1_enhanced_ports[port_index],
                    1,
                    offset,
                    enhanced_dmrs=True,
                ),
                type1_enhanced_values[4 * port_index + offset],
            )
    var type2_ports: List[Int] = [1000, 1001, 1002, 1003, 1004, 1005]
    var type2_values: List[Int] = [
        0, 1, 6, 7,  1, 6, 7, 0,
        2, 3, 8, 9,  3, 8, 9, 2,
        4, 5, 10, 11,  5, 10, 11, 4,
    ]
    for port_index in range(len(type2_ports)):
        for offset in range(4):
            assert_equal(
                nr_pdsch_ptrs_k_ref_re(
                    type2_ports[port_index], 2, offset
                ),
                type2_values[4 * port_index + offset],
            )
    var type2_enhanced_ports: List[Int] = [
        1012, 1013, 1014, 1015, 1016, 1017
    ]
    var type2_enhanced_values: List[Int] = [
        6, 7, 0, 1,  7, 0, 1, 6,
        8, 9, 2, 3,  9, 2, 3, 8,
        10, 11, 4, 5,  11, 4, 5, 10,
    ]
    for port_index in range(len(type2_enhanced_ports)):
        for offset in range(4):
            assert_equal(
                nr_pdsch_ptrs_k_ref_re(
                    type2_enhanced_ports[port_index],
                    2,
                    offset,
                    enhanced_dmrs=True,
                ),
                type2_enhanced_values[4 * port_index + offset],
            )

    # Independent RB arithmetic for the frequency-placement API.  k'=6 is
    # the literal type-1/port-1000/offset10 row verified above.
    for scheduled_resource_blocks in [1, 2, 3, 4, 10, 17]:
        for rnti in [0, 1, 0x1234, 0xFFFF]:
            for frequency_density in [2, 4]:
                var remainder = (
                    scheduled_resource_blocks % frequency_density
                )
                var divisor = (
                    frequency_density if remainder == 0 else remainder
                )
                var rb = rnti % divisor
                var expected = List[Int]()
                while rb < scheduled_resource_blocks:
                    expected.append(12 * rb + 6)
                    rb += frequency_density
                assert_equal(
                    nr_pdsch_ptrs_frequency_positions(
                        scheduled_resource_blocks,
                        rnti,
                        frequency_density,
                        1000,
                        1,
                        2,
                    ),
                    expected,
                )


def test_ptrs_grid_mapping_phase_estimation_and_correction() raises:
    var times: List[Int] = [0, 4, 6]
    var frequencies: List[Int] = [6, 30]
    var known: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(0.0, 1.0)
    ]
    var grid = NRResourceGrid(14, 64)
    nr_map_pdsch_ptrs(
        grid, 1, 2, Span(times), Span(frequencies), Span(known)
    )
    var phases: List[Float64] = [0.2, -0.4, 0.7]
    for time_index in range(len(times)):
        var rotation = Complex64(cos(phases[time_index]), sin(phases[time_index]))
        for frequency_index in range(len(frequencies)):
            grid[1 + times[time_index], 2 + frequencies[frequency_index]] = (
                known[frequency_index] * rotation
            )
    var received = nr_extract_pdsch_ptrs(
        grid, 1, 2, Span(times), Span(frequencies)
    )
    var estimate = nr_ptrs_estimate_common_phase(
        Span(received), Span(known), Span(times)
    )
    for index in range(len(phases)):
        assert_true(abs(estimate.phase_radians[index] - phases[index]) < 1.0e-12)
        assert_true(abs(estimate.coherent_magnitudes[index] - 2.0) < 1.0e-12)

    var original: List[Complex64] = [Complex64(0.3, -0.8), Complex64(-1.0, 0.25)]
    var rotation = Complex64(cos(phases[2]), sin(phases[2]))
    var impaired = List[Complex64](capacity=len(original))
    for value in original:
        impaired.append(value * rotation)
    var corrected = nr_ptrs_correct_common_phase(Span(impaired), phases[2])
    for index in range(len(original)):
        _assert_complex_close(corrected[index], original[index], 1.0e-12)

    # Scale-safe coherent accumulation preserves cancellation and phase at
    # both ends of the finite Float64 range.
    var cancellation_known: List[Complex64] = [
        Complex64(1.0e200, 0.0), Complex64(1.0e200, 0.0)
    ]
    var cancellation_received: List[Complex64] = [
        Complex64(1.0e200, 0.0), Complex64(-1.0e200, 0.0)
    ]
    var one_symbol: List[Int] = [0]
    var cancellation = nr_ptrs_estimate_common_phase(
        Span(cancellation_received), Span(cancellation_known), Span(one_symbol)
    )
    assert_equal(cancellation.phase_radians[0], 0.0)
    assert_equal(cancellation.coherent_magnitudes[0], 0.0)

    var tiny_known: List[Complex64] = [Complex64(1.0e-300, 0.0)]
    var tiny_received: List[Complex64] = [Complex64(0.0, 1.0e-300)]
    var tiny = nr_ptrs_estimate_common_phase(
        Span(tiny_received), Span(tiny_known), Span(one_symbol)
    )
    assert_true(abs(tiny.phase_radians[0] - 1.5707963267948966) < 1.0e-12)
    assert_equal(tiny.coherent_magnitudes[0], 0.0)

    var minimum_received: List[Complex64] = [Complex64(0.0, 5.0e-324)]
    var unit_known: List[Complex64] = [Complex64(1.0, 0.0)]
    var minimum = nr_ptrs_estimate_common_phase(
        Span(minimum_received), Span(unit_known), Span(one_symbol)
    )
    assert_true(abs(minimum.phase_radians[0] - 1.5707963267948966) < 1.0e-12)
    assert_equal(minimum.coherent_magnitudes[0], 5.0e-324)

    var maximum_received: List[Complex64] = [
        Complex64(1.7976931348623157e308, 0.0)
    ]
    var maximum = nr_ptrs_estimate_common_phase(
        Span(maximum_received), Span(unit_known), Span(one_symbol)
    )
    assert_equal(maximum.phase_radians[0], 0.0)
    assert_equal(
        maximum.coherent_magnitudes[0], 1.7976931348623157e308
    )

    var zero_known: List[Complex64] = [Complex64(0.0, 0.0)]
    with assert_raises():
        _ = nr_ptrs_estimate_common_phase(
            Span(tiny_received), Span(zero_known), Span(one_symbol)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
