"""TS 38.211 V18.9.0 PRACH tables, equations and bounded composites."""

from std.collections import Span
from std.math import cos, sin
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.prach import (
    NRPRACHOccasion,
    PRACH_SET_UNRESTRICTED,
    PRACH_SET_RESTRICTED_A,
    PRACH_SET_RESTRICTED_B,
    PRACH_FORMAT_0,
    PRACH_FORMAT_1,
    PRACH_FORMAT_2,
    PRACH_FORMAT_3,
    PRACH_FORMAT_A1,
    PRACH_FORMAT_A2,
    PRACH_FORMAT_A3,
    PRACH_FORMAT_B1,
    PRACH_FORMAT_B2,
    PRACH_FORMAT_B3,
    PRACH_FORMAT_B4,
    PRACH_FORMAT_C0,
    PRACH_FORMAT_C2,
    PRACH_REGION_FR1,
    PRACH_REGION_FR2,
    PRACH_SPECTRUM_PAIRED,
    PRACH_SPECTRUM_UNPAIRED,
    nr_prach_format_parameters,
    nr_prach_logical_root_count,
    nr_prach_logical_root_u,
    nr_prach_root_sequence_standard,
    nr_prach_sequence_standard,
    nr_prach_n_cs,
    nr_prach_d_u,
    nr_prach_restricted_parameters,
    nr_prach_cyclic_shifts,
    nr_prach_allocate_preambles,
    nr_prach_preamble_sequence,
    nr_prach_frequency_sequence,
    nr_prach_normalized_cp_samples,
    nr_prach_normalized_waveform,
    nr_detect_prach_multi_root,
    nr_prach_normalized_composite,
    nr_prach_representative_occasion,
    nr_prach_occasion_is_active,
)


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _assert_occasion_row_and_activity(
    occasion: NRPRACHOccasion,
    region: Int,
    spectrum: Int,
    configuration_index: Int,
    format: Int,
    frame_period: Int,
    frame_offset_mask: UInt16,
    time_unit_mask: UInt64,
    starting_symbol: Int,
    prach_slots_per_unit: Int,
    occasions_per_slot: Int,
    duration_symbols: Int,
) raises:
    assert_equal(occasion.region, region)
    assert_equal(occasion.spectrum, spectrum)
    assert_equal(occasion.configuration_index, configuration_index)
    assert_equal(occasion.format, format)
    assert_equal(occasion.frame_period, frame_period)
    assert_equal(occasion.frame_offset_mask, frame_offset_mask)
    assert_equal(occasion.time_unit_mask, time_unit_mask)
    assert_equal(occasion.starting_symbol, starting_symbol)
    assert_equal(occasion.prach_slots_per_unit, prach_slots_per_unit)
    assert_equal(occasion.occasions_per_slot, occasions_per_slot)
    assert_equal(occasion.duration_symbols, duration_symbols)
    # Exhaust two full maximum periods and every admitted time-unit bit.
    for system_frame_number in range(32):
        for time_unit in range(64):
            var residue = system_frame_number % frame_period
            var expected = (
                (frame_offset_mask & (UInt16(1) << UInt16(residue)))
                != UInt16(0)
                and (time_unit_mask & (UInt64(1) << UInt64(time_unit)))
                != UInt64(0)
            )
            assert_equal(
                nr_prach_occasion_is_active(
                    occasion, system_frame_number, time_unit
                ),
                expected,
            )


def test_release_18_19_preamble_format_tables() raises:
    var f0 = nr_prach_format_parameters(PRACH_FORMAT_0, sequence_length=839)
    assert_equal(f0.sequence_length, 839)
    assert_equal(f0.subcarrier_spacing_hz, 1250)
    assert_equal(f0.useful_samples_kappa, 24576.0)
    assert_equal(f0.cp_samples_kappa, 3168.0)
    assert_equal(f0.repetitions, 1)
    assert_true(f0.supports_restricted_sets)

    var f1 = nr_prach_format_parameters(PRACH_FORMAT_1, sequence_length=839)
    var f2 = nr_prach_format_parameters(PRACH_FORMAT_2, sequence_length=839)
    var f3 = nr_prach_format_parameters(PRACH_FORMAT_3, sequence_length=839)
    assert_equal(f1.useful_samples_kappa, 49152.0)
    assert_equal(f1.cp_samples_kappa, 21024.0)
    assert_equal(f2.useful_samples_kappa, 98304.0)
    assert_equal(f2.cp_samples_kappa, 4688.0)
    assert_equal(f3.subcarrier_spacing_hz, 5000)
    assert_equal(f3.repetitions, 4)

    var short_codes: List[Int] = [
        PRACH_FORMAT_A1, PRACH_FORMAT_A2, PRACH_FORMAT_A3,
        PRACH_FORMAT_B1, PRACH_FORMAT_B2, PRACH_FORMAT_B3,
        PRACH_FORMAT_B4, PRACH_FORMAT_C0, PRACH_FORMAT_C2,
    ]
    var expected_repetitions: List[Int] = [2,4,6,2,4,6,12,1,4]
    var expected_cp: List[Float64] = [288.0,576.0,864.0,216.0,360.0,504.0,936.0,1240.0,2048.0]
    for i in range(len(short_codes)):
        var parameters = nr_prach_format_parameters(short_codes[i])
        assert_equal(parameters.sequence_length, 139)
        assert_equal(parameters.repetitions, expected_repetitions[i])
        assert_equal(parameters.cp_samples_kappa, expected_cp[i])
        assert_true(not parameters.supports_restricted_sets)

    var rel18_571 = nr_prach_format_parameters(
        PRACH_FORMAT_A1, numerology=5, sequence_length=571
    )
    assert_equal(rel18_571.subcarrier_spacing_hz, 480000)
    assert_equal(rel18_571.useful_samples_kappa, 128.0)
    assert_equal(rel18_571.cp_samples_kappa, 9.0)
    var rel18_1151 = nr_prach_format_parameters(
        PRACH_FORMAT_C2, numerology=3, sequence_length=1151
    )
    assert_equal(rel18_1151.useful_samples_kappa, 1024.0)
    assert_equal(rel18_1151.cp_samples_kappa, 256.0)
    with assert_raises():
        _ = nr_prach_format_parameters(
            PRACH_FORMAT_A1, numerology=2, sequence_length=571
        )


def test_complete_logical_root_mapping_tables_and_checksum() raises:
    assert_equal(nr_prach_logical_root_count(839), 838)
    var seen = List[Bool](length=839, fill=False)
    var total = 0
    var weighted = 0
    for i in range(838):
        var root = nr_prach_logical_root_u(i, 839)
        assert_true(root >= 1 and root <= 838)
        assert_true(not seen[root])
        seen[root] = True
        total += root
        weighted += (i + 1) * root
    # Independent checksums over the literal values in Table 6.3.3.1-3.
    assert_equal(total, 351541)
    assert_equal(weighted, 147559230)
    assert_equal(nr_prach_logical_root_u(0, 839), 129)
    assert_equal(nr_prach_logical_root_u(21, 839), 837)
    assert_equal(nr_prach_logical_root_u(459, 839), 607)
    assert_equal(nr_prach_logical_root_u(837, 839), 610)

    assert_equal(nr_prach_logical_root_u(0, 139), 1)
    assert_equal(nr_prach_logical_root_u(1, 139), 138)
    assert_equal(nr_prach_logical_root_u(137, 139), 70)
    assert_equal(nr_prach_logical_root_u(569, 571), 286)
    assert_equal(nr_prach_logical_root_u(1149, 1151), 576)
    with assert_raises():
        _ = nr_prach_logical_root_u(838, 839)


def test_all_zero_correlation_zone_tables() raises:
    var long_1250_u: List[Int] = [0,13,15,18,22,26,32,38,46,59,76,93,119,167,279,419]
    var long_1250_a: List[Int] = [15,18,22,26,32,38,46,55,68,82,100,128,158,202,237]
    var long_1250_b: List[Int] = [15,18,22,26,32,38,46,55,68,82,100,118,137]
    var long_5000_u: List[Int] = [0,13,26,33,38,41,49,55,64,76,93,119,139,209,279,419]
    var long_5000_a: List[Int] = [36,57,72,81,89,94,103,112,121,132,137,152,173,195,216,237]
    var long_5000_b: List[Int] = [36,57,60,63,65,68,71,77,81,85,97,109,122,137]
    for i in range(16):
        assert_equal(nr_prach_n_cs(i, 839, 1250), long_1250_u[i])
        assert_equal(nr_prach_n_cs(i, 839, 5000), long_5000_u[i])
        assert_equal(nr_prach_n_cs(i, 839, 5000, PRACH_SET_RESTRICTED_A), long_5000_a[i])
    for i in range(15):
        assert_equal(nr_prach_n_cs(i, 839, 1250, PRACH_SET_RESTRICTED_A), long_1250_a[i])
    for i in range(13):
        assert_equal(nr_prach_n_cs(i, 839, 1250, PRACH_SET_RESTRICTED_B), long_1250_b[i])
    for i in range(14):
        assert_equal(nr_prach_n_cs(i, 839, 5000, PRACH_SET_RESTRICTED_B), long_5000_b[i])

    var short139: List[Int] = [0,2,4,6,8,10,12,13,15,17,19,23,27,34,46,69]
    var short571: List[Int] = [0,8,10,12,15,17,21,25,31,40,51,63,81,114,190,285]
    var short1151: List[Int] = [0,17,21,25,30,35,44,52,63,82,104,127,164,230,383,575]
    for i in range(16):
        assert_equal(nr_prach_n_cs(i, 139, 120000), short139[i])
        assert_equal(nr_prach_n_cs(i, 571, 480000), short571[i])
        assert_equal(nr_prach_n_cs(i, 1151, 15000), short1151[i])
    with assert_raises():
        _ = nr_prach_n_cs(15, 839, 1250, PRACH_SET_RESTRICTED_A)
    with assert_raises():
        _ = nr_prach_n_cs(14, 839, 5000, PRACH_SET_RESTRICTED_B)
    with assert_raises():
        _ = nr_prach_n_cs(1, 571, 15000)


def test_zadoff_chu_static_vector_unit_modulus_and_correlations() raises:
    var root1 = nr_prach_root_sequence_standard(1, 139)
    _assert_complex_close(root1[0], Complex64(1.0, 0.0), 1.0e-14)
    _assert_complex_close(
        root1[1], Complex64(0.9989785286500293, -0.04518737983356034), 1.0e-13
    )
    _assert_complex_close(
        root1[10], Complex64(-0.792779703083777, -0.609508279171332), 1.0e-13
    )
    for value in root1:
        assert_true(abs(value.magnitude_squared() - 1.0) < 1.0e-11)

    var shifted = nr_prach_cyclic_shifts(1, 139, 13, PRACH_SET_UNRESTRICTED)
    assert_equal(len(shifted), 10)
    var shifted_sequence = nr_prach_root_sequence_standard(1, 139)
    for i in range(139):
        shifted_sequence[i] = root1[(i + shifted[1]) % 139]
    var auto = Complex64(0.0, 0.0)
    for i in range(139):
        auto = auto + root1[i] * shifted_sequence[i].conjugate()
    assert_true(auto.magnitude_squared() / Float64(139 * 139) < 1.0e-20)

    var root2 = nr_prach_root_sequence_standard(2, 139)
    var cross = Complex64(0.0, 0.0)
    for i in range(139):
        cross = cross + root1[i] * root2[i].conjugate()
    assert_true(abs(cross.magnitude_squared() / Float64(139 * 139) - 1.0 / 139.0) < 1.0e-10)

    # Rel-18/19 additions are real sequence paths, not parameter-only stubs.
    var root571 = nr_prach_root_sequence_standard(1, 571)
    var shifted571 = nr_prach_sequence_standard(1, 571, 285)
    assert_equal(len(root571), 571)
    assert_equal(len(shifted571), 571)
    _assert_complex_close(shifted571[0], root571[285], 0.0)
    var root1151 = nr_prach_root_sequence_standard(1150, 1151)
    assert_equal(len(root1151), 1151)
    for i in range(0, 1151, 97):
        assert_true(abs(root1151[i].magnitude_squared() - 1.0) < 1.0e-10)


def test_restricted_set_a_b_all_du_branches_and_shifts() raises:
    assert_equal(nr_prach_d_u(129, 839), 13)
    var type_a = nr_prach_restricted_parameters(
        129, 839, 13, PRACH_SET_RESTRICTED_A
    )
    assert_true(type_a.valid)
    assert_equal(type_a.n_shift, 1)
    assert_equal(type_a.d_start, 39)
    assert_equal(type_a.n_group, 21)
    assert_equal(type_a.count(), 21)

    # Roots below hit, in order, all six type-B d_u regions in 6.3.3.1.
    var roots: List[Int] = [6,5,18,19,11,9]
    var expected_du: List[Int] = [140,168,233,265,305,373]
    var expected_count: List[Int] = [10,12,10,10,10,7]
    for i in range(6):
        var parameters = nr_prach_restricted_parameters(
            roots[i], 839, 13, PRACH_SET_RESTRICTED_B
        )
        assert_true(parameters.valid)
        assert_equal(parameters.d_u, expected_du[i])
        assert_equal(parameters.count(), expected_count[i])

    var branch3 = nr_prach_restricted_parameters(
        18, 839, 13, PRACH_SET_RESTRICTED_B
    )
    assert_equal(branch3.n_shift, 7)
    assert_equal(branch3.d_start, 184)
    assert_equal(branch3.d_start_double_bar, 324)
    assert_equal(branch3.d_start_triple_bar, 557)
    assert_equal(branch3.n_shift_double_bar, 3)
    var shifts = nr_prach_cyclic_shifts(18, 839, 13, PRACH_SET_RESTRICTED_B)
    var expected: List[Int] = [0,13,26,39,52,65,78,324,337,350]
    assert_equal(shifts, expected)
    var seen = List[Bool](length=839, fill=False)
    for shift in shifts:
        assert_true(shift >= 0 and shift < 839)
        assert_true(not seen[shift])
        seen[shift] = True

    var unavailable = nr_prach_restricted_parameters(
        140, 839, 13, PRACH_SET_RESTRICTED_A
    )
    assert_true(not unavailable.valid)
    assert_equal(len(nr_prach_cyclic_shifts(140, 839, 13, PRACH_SET_RESTRICTED_A)), 0)


def test_64_preamble_allocation_crosses_and_wraps_logical_roots() raises:
    var allocations = nr_prach_allocate_preambles(
        837, 839, 419, PRACH_SET_UNRESTRICTED
    )
    assert_equal(len(allocations), 64)
    assert_equal(allocations[0].logical_root_index, 837)
    assert_equal(allocations[0].root_u, 610)
    assert_equal(allocations[0].cyclic_shift, 0)
    assert_equal(allocations[1].logical_root_index, 837)
    assert_equal(allocations[1].cyclic_shift, 419)
    assert_equal(allocations[2].logical_root_index, 0)
    assert_equal(allocations[2].root_u, 129)
    assert_equal(allocations[63].logical_root_index, 30)

    var restricted = nr_prach_allocate_preambles(
        0, 839, 13, PRACH_SET_RESTRICTED_A
    )
    assert_equal(len(restricted), 64)
    assert_equal(restricted[0].logical_root_index, 0)
    assert_equal(restricted[20].cyclic_shift, 780)
    assert_equal(restricted[21].logical_root_index, 1)
    # Logical roots 2..17 have d_u<N_CS and therefore contribute no shifts.
    assert_equal(restricted[42].logical_root_index, 18)
    assert_equal(restricted[63].logical_root_index, 19)


def test_readable_cp_repetition_waveform_and_frequency_sequence() raises:
    var parameters = nr_prach_format_parameters(
        PRACH_FORMAT_A2, numerology=1, sequence_length=139
    )
    var allocation = nr_prach_allocate_preambles(
        0, 139, 13, PRACH_SET_UNRESTRICTED, 1
    )[0]
    var sequence = nr_prach_preamble_sequence(allocation, 139)
    assert_equal(nr_prach_normalized_cp_samples(parameters), 39)
    var waveform = nr_prach_normalized_waveform(Span(sequence), parameters)
    assert_equal(len(waveform), 39 + 4 * 139)
    for i in range(39):
        _assert_complex_close(waveform[i], sequence[100 + i], 0.0)
    for repetition in range(4):
        for i in range(139):
            _assert_complex_close(waveform[39 + repetition * 139 + i], sequence[i], 0.0)

    var spectrum = nr_prach_frequency_sequence(Span(sequence))
    var spectrum_energy = 0.0
    for value in spectrum:
        spectrum_energy += value.magnitude_squared()
    assert_true(abs(spectrum_energy - Float64(139 * 139)) < 1.0e-7)


def test_multi_root_detector_with_root_rollover_gain_and_noise() raises:
    var allocations = nr_prach_allocate_preambles(
        137, 139, 0, PRACH_SET_UNRESTRICTED, 4
    )
    assert_equal(allocations[0].logical_root_index, 137)
    assert_equal(allocations[1].logical_root_index, 0)
    assert_equal(allocations[2].logical_root_index, 1)
    var transmitted = nr_prach_preamble_sequence(allocations[2], 139)
    var gain = Complex64(0.73, -0.29)
    for i in range(139):
        var noise = Complex64(
            1.0e-4 * Float64(i % 5 - 2),
            1.0e-4 * Float64((3 * i) % 7 - 3),
        )
        transmitted[i] = transmitted[i] * gain + noise
    var detection = nr_detect_prach_multi_root(
        Span(transmitted), 137, 0, PRACH_SET_UNRESTRICTED, 4
    )
    assert_equal(detection.preamble_index, 2)
    assert_equal(detection.logical_root_index, 1)
    assert_equal(detection.root_u, 138)
    assert_equal(detection.cyclic_shift, 0)
    assert_true(detection.metric > 0.999999)


def test_representative_normalized_composite_owned_checkpoints_and_zc_oracle(
) raises:
    """Cross generation/waveform/detection without claiming occasion tables."""
    var parameters = nr_prach_format_parameters(
        PRACH_FORMAT_A2, numerology=1, sequence_length=139
    )
    var testcase = String("nr-prach-composite-independent-zc")
    var result = nr_prach_normalized_composite(
        parameters,
        0,
        13,
        PRACH_SET_UNRESTRICTED,
        7,
        preamble_count=12,
        testcase_id=testcase,
    )
    # Mutating the call-site String proves every metadata record owns its ID.
    testcase.write("-mutated")

    assert_equal(result.parameters.format, PRACH_FORMAT_A2)
    assert_equal(result.allocation.preamble_index, 7)
    assert_equal(result.allocation.logical_root_index, 0)
    assert_equal(result.allocation.root_u, 1)
    assert_equal(result.allocation.cyclic_shift, 91)
    assert_equal(result.normalized_cp_samples, 39)

    # Independent TS 38.211 Zadoff-Chu equation and cyclic-shift oracle.
    var expected_root = List[Complex64](capacity=139)
    for n in range(139):
        var angle = (
            -3.1415926535897932384626433832795
            * Float64(n * (n + 1)) / 139.0
        )
        expected_root.append(Complex64(cos(angle), sin(angle)))
    var expected_preamble = List[Complex64](capacity=139)
    for n in range(139):
        expected_preamble.append(expected_root[(n + 91) % 139])
    for n in range(139):
        _assert_complex_close(result.root_sequence[n], expected_root[n], 1.0e-13)
        _assert_complex_close(
            result.preamble_sequence[n], expected_preamble[n], 1.0e-13
        )
        _assert_complex_close(
            result.detector_input[n], expected_preamble[n], 1.0e-13
        )

    assert_equal(len(result.frequency_sequence), 139)
    var frequency_energy = 0.0
    for value in result.frequency_sequence:
        frequency_energy += value.magnitude_squared()
    assert_true(abs(frequency_energy - Float64(139 * 139)) < 1.0e-7)
    assert_equal(len(result.normalized_waveform), 39 + 4 * 139)
    for n in range(39):
        _assert_complex_close(
            result.normalized_waveform[n], expected_preamble[100 + n], 1.0e-13
        )
    for repetition in range(4):
        for n in range(139):
            _assert_complex_close(
                result.normalized_waveform[39 + repetition * 139 + n],
                expected_preamble[n],
                1.0e-13,
            )

    assert_equal(result.detection.preamble_index, 7)
    assert_equal(result.detection.logical_root_index, 0)
    assert_equal(result.detection.root_u, 1)
    assert_equal(result.detection.cyclic_shift, 91)
    assert_true(result.detection.metric >= 1.0 - 1.0e-12)

    var stages: List[String] = [
        "allocated-preamble",
        "root-sequence",
        "preamble-sequence",
        "frequency-sequence",
        "normalized-waveform",
        "detector-input",
        "normalized-cp-samples",
        "detected-preamble-index",
        "detection-metric",
    ]
    var dtypes: List[String] = [
        "int", "complex64", "complex64", "complex64", "complex64",
        "complex64", "int", "int", "float64",
    ]
    var shapes: List[String] = [
        "4", "139", "139", "139", "595", "139", "1", "1", "1"
    ]
    var layouts: List[String] = [
        "preamble-index-logical-root-index-root-u-cyclic-shift",
        "iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
        "cp-then-repeated-iq",
        "first-useful-repetition-iq",
        "scalar",
        "scalar",
        "scalar",
    ]
    assert_equal(len(result.checkpoint_metadata), len(stages))
    for index in range(len(stages)):
        ref metadata = result.checkpoint_metadata[index]
        assert_equal(metadata.testcase_id, "nr-prach-composite-independent-zc")
        assert_equal(metadata.stage, stages[index])
        assert_equal(metadata.dtype, dtypes[index])
        assert_equal(metadata.shape, shapes[index])
        assert_equal(metadata.stride, "1")
        assert_equal(metadata.scale, 1.0)
        assert_equal(metadata.version, 1)
        assert_equal(metadata.layout, layouts[index])
        assert_equal(
            metadata.q_format,
            "integer" if index == 0 or index == 6 or index == 7 else "floating",
        )

    with assert_raises():
        _ = nr_prach_normalized_composite(
            parameters,
            0,
            13,
            PRACH_SET_UNRESTRICTED,
            12,
            preamble_count=12,
        )


def test_normalized_cp_matches_independent_rational_rounding() raises:
    var format_codes: List[Int] = [
        PRACH_FORMAT_0,
        PRACH_FORMAT_1,
        PRACH_FORMAT_2,
        PRACH_FORMAT_3,
        PRACH_FORMAT_A1,
        PRACH_FORMAT_A2,
        PRACH_FORMAT_A3,
        PRACH_FORMAT_B1,
        PRACH_FORMAT_B2,
        PRACH_FORMAT_B3,
        PRACH_FORMAT_B4,
        PRACH_FORMAT_C0,
        PRACH_FORMAT_C2,
    ]
    for format_code in format_codes:
        var sequence_length = (
            839 if format_code <= PRACH_FORMAT_3 else 139
        )
        var parameters = nr_prach_format_parameters(
            format_code, sequence_length=sequence_length
        )
        var one_repetition = (
            parameters.useful_samples_kappa
            / Float64(parameters.repetitions)
        )
        var expected = Int(
            parameters.cp_samples_kappa
            / one_repetition
            * Float64(parameters.sequence_length)
            + 0.5
        )
        assert_equal(
            nr_prach_normalized_cp_samples(parameters), expected
        )


def test_complete_representative_occasion_table_and_mask_property() raises:
    comptime units_0_to_9 = UInt64(0x00000000000003FF)
    comptime units_4_9 = UInt64(0x0000000000000210)
    comptime unit_9 = UInt64(0x0000000000000200)
    comptime fr2_units = UInt64(0x0000008421084210)

    var row = nr_prach_representative_occasion(
        PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 0
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 0,
        PRACH_FORMAT_0, 16, UInt16(0x0002), UInt64(0x2), 0, 0, 0, 0,
    )
    row = nr_prach_representative_occasion(
        PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 27
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 27,
        PRACH_FORMAT_0, 1, UInt16(0x0001), units_0_to_9, 0, 0, 0, 0,
    )
    row = nr_prach_representative_occasion(
        PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 87
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 87,
        PRACH_FORMAT_A1, 16, UInt16(0x0001), units_4_9, 0, 1, 6, 2,
    )

    row = nr_prach_representative_occasion(
        PRACH_REGION_FR1, PRACH_SPECTRUM_UNPAIRED, 0
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR1, PRACH_SPECTRUM_UNPAIRED, 0,
        PRACH_FORMAT_0, 16, UInt16(0x0002), unit_9, 0, 0, 0, 0,
    )
    row = nr_prach_representative_occasion(
        PRACH_REGION_FR1, PRACH_SPECTRUM_UNPAIRED, 67
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR1, PRACH_SPECTRUM_UNPAIRED, 67,
        PRACH_FORMAT_A1, 16, UInt16(0x0002), unit_9, 0, 2, 6, 2,
    )
    row = nr_prach_representative_occasion(
        PRACH_REGION_FR1, PRACH_SPECTRUM_UNPAIRED, 133
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR1, PRACH_SPECTRUM_UNPAIRED, 133,
        PRACH_FORMAT_B1, 4, UInt16(0x0002), unit_9, 2, 1, 6, 2,
    )

    row = nr_prach_representative_occasion(
        PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 0
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 0,
        PRACH_FORMAT_A1, 16, UInt16(0x0002), fr2_units, 0, 2, 6, 2,
    )
    row = nr_prach_representative_occasion(
        PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 29
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 29,
        PRACH_FORMAT_A2, 16, UInt16(0x0002), fr2_units, 0, 2, 3, 4,
    )
    row = nr_prach_representative_occasion(
        PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 89
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 89,
        PRACH_FORMAT_B1, 16, UInt16(0x0002), fr2_units, 2, 2, 6, 2,
    )
    row = nr_prach_representative_occasion(
        PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 112
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 112,
        PRACH_FORMAT_B4, 16, UInt16(0x0006), fr2_units, 0, 2, 1, 12,
    )
    row = nr_prach_representative_occasion(
        PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 144
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 144,
        PRACH_FORMAT_C0, 16, UInt16(0x0002), fr2_units, 0, 2, 7, 2,
    )
    row = nr_prach_representative_occasion(
        PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 173
    )
    _assert_occasion_row_and_activity(
        row, PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 173,
        PRACH_FORMAT_C2, 16, UInt16(0x0002), fr2_units, 0, 2, 2, 6,
    )


def test_representative_fr1_fr2_occasion_rows_and_boundaries() raises:
    var paired = nr_prach_representative_occasion(
        PRACH_REGION_FR1, PRACH_SPECTRUM_PAIRED, 87
    )
    assert_equal(paired.format, PRACH_FORMAT_A1)
    assert_equal(paired.frame_period, 16)
    assert_equal(paired.prach_slots_per_unit, 1)
    assert_equal(paired.occasions_per_slot, 6)
    assert_equal(paired.duration_symbols, 2)
    assert_true(nr_prach_occasion_is_active(paired, 0, 4))
    assert_true(nr_prach_occasion_is_active(paired, 0, 9))
    assert_true(not nr_prach_occasion_is_active(paired, 1, 4))

    var unpaired = nr_prach_representative_occasion(
        PRACH_REGION_FR1, PRACH_SPECTRUM_UNPAIRED, 133
    )
    assert_equal(unpaired.format, PRACH_FORMAT_B1)
    assert_equal(unpaired.starting_symbol, 2)
    assert_true(nr_prach_occasion_is_active(unpaired, 1, 9))

    var fr2 = nr_prach_representative_occasion(
        PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 112
    )
    assert_equal(fr2.format, PRACH_FORMAT_B4)
    assert_equal(fr2.duration_symbols, 12)
    assert_true(nr_prach_occasion_is_active(fr2, 1, 4))
    assert_true(nr_prach_occasion_is_active(fr2, 2, 39))
    assert_true(not nr_prach_occasion_is_active(fr2, 3, 39))
    with assert_raises():
        _ = nr_prach_representative_occasion(
            PRACH_REGION_FR2, PRACH_SPECTRUM_UNPAIRED, 28
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
