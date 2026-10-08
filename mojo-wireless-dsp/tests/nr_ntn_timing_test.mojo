"""Independent Rel-17 NR-NTN timing and Doppler evidence."""

from std.math import sqrt
from std.testing import (
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
    TestSuite,
)
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.ntn_timing import (
    NR_NTN_SPEED_OF_LIGHT_MPS,
    NR_NTN_TA_COMMON_DRIFT_RAW_MAX,
    NRNTNECEFStateVector,
    NRNTNRel17CommonTimingAssistance,
    nr_ntn_rel17_common_one_way_delay_seconds,
    nr_ntn_rel17_common_ta_seconds,
    nr_ntn_rel17_effective_koffset_15khz_slots,
    nr_ntn_rel17_koffset_covers_propagation,
    nr_ntn_rel17_koffset_seconds,
    nr_ntn_rel17_precompensation,
    nr_ntn_rel17_radial_velocity_mps,
    nr_ntn_rel17_service_link_doppler_shift_hz,
    nr_ntn_rel17_service_link_range_m,
    nr_ntn_rel17_service_link_rtt_seconds,
    nr_ntn_rel17_ul_sync_information_valid,
    nr_ntn_rel17_uplink_frequency_precompensation_hz,
)


def _zero_state() raises -> NRNTNECEFStateVector:
    return NRNTNECEFStateVector(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)


def test_static_ecef_range_rtt_radial_and_doppler_oracle() raises:
    var ue = _zero_state()
    var satellite = NRNTNECEFStateVector(
        3000000.0, 4000000.0, 0.0, 300.0, 400.0, 0.0
    )
    assert_almost_equal(
        nr_ntn_rel17_service_link_range_m(ue, satellite),
        5000000.0,
        atol=0.0,
    )
    var expected_rtt = 10000000.0 / 299792458.0
    assert_almost_equal(
        nr_ntn_rel17_service_link_rtt_seconds(ue, satellite),
        expected_rtt,
        rtol=1.0e-15,
    )
    assert_almost_equal(
        nr_ntn_rel17_radial_velocity_mps(ue, satellite), 500.0, atol=0.0
    )
    var expected_doppler = -(500.0 / 299792458.0) * 2000000000.0
    assert_almost_equal(
        nr_ntn_rel17_service_link_doppler_shift_hz(
            ue, satellite, 2000000000.0
        ),
        expected_doppler,
        rtol=1.0e-15,
    )
    assert_almost_equal(
        nr_ntn_rel17_uplink_frequency_precompensation_hz(
            ue, satellite, 2000000000.0
        ),
        -expected_doppler,
        rtol=1.0e-15,
    )


def test_common_ta_quantization_drift_koffset_and_validity_exact() raises:
    # Independent expansion of the TS 38.331 quantization steps:
    # 100000*4.072 ns - 1000*0.2 ns/s*4 s
    # + 100*0.02 ns/s^2*(4 s)^2 = 406.432 us.  Clause 4.2 divides
    # every two-way TA polynomial term by two only when forming Delay_common.
    var assistance = NRNTNRel17CommonTimingAssistance(
        100000, -1000, 100, 5
    )
    assert_almost_equal(
        nr_ntn_rel17_common_ta_seconds(assistance, 4.0),
        0.000406432,
        atol=1.0e-18,
    )
    assert_almost_equal(
        nr_ntn_rel17_common_one_way_delay_seconds(assistance, 4.0),
        0.000203216,
        atol=1.0e-18,
    )
    assert_equal(
        nr_ntn_rel17_effective_koffset_15khz_slots(73, 12), 61
    )
    assert_almost_equal(nr_ntn_rel17_koffset_seconds(73, 12), 0.061)
    assert_true(nr_ntn_rel17_ul_sync_information_valid(assistance, 0))
    assert_true(
        nr_ntn_rel17_ul_sync_information_valid(assistance, 4999999)
    )
    assert_false(
        nr_ntn_rel17_ul_sync_information_valid(assistance, 5000000)
    )


def test_composed_precompensation_has_independent_component_wiring() raises:
    var ue = _zero_state()
    var satellite = NRNTNECEFStateVector(
        3000000.0, 4000000.0, 0.0, 300.0, 400.0, 0.0
    )
    var assistance = NRNTNRel17CommonTimingAssistance(
        100000, -1000, 100, 5
    )
    var result = nr_ntn_rel17_precompensation(
        ue, satellite, assistance, 4.0, 2000000000.0, 73, 12
    )
    var expected_rtt = 10000000.0 / 299792458.0
    var expected_doppler = -(500.0 / 299792458.0) * 2000000000.0
    assert_almost_equal(result.service_link_range_m, 5000000.0, atol=0.0)
    assert_almost_equal(result.service_link_rtt_seconds, expected_rtt)
    assert_almost_equal(result.common_ta_seconds, 0.000406432)
    assert_almost_equal(
        result.ntn_propagation_ta_seconds,
        expected_rtt + 0.000406432,
        rtol=1.0e-15,
    )
    assert_almost_equal(result.radial_velocity_mps, 500.0, atol=0.0)
    assert_almost_equal(result.received_doppler_shift_hz, expected_doppler)
    assert_almost_equal(
        result.uplink_frequency_precompensation_hz, -expected_doppler
    )
    assert_equal(result.effective_koffset_15khz_slots, 61)
    assert_almost_equal(result.effective_koffset_seconds, 0.061, atol=0.0)


def test_seeded_geometry_matches_independent_float64_oracle() raises:
    var seed = UInt64(0x243F6A8885A308D3)
    for _ in range(257):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var ux = Float64(Int(seed & UInt64(0xFFFF)) - 32768) * 100.0
        var uy = Float64(Int((seed >> 16) & UInt64(0xFFFF)) - 32768) * 100.0
        var uz = Float64(Int((seed >> 32) & UInt64(0xFFFF)) - 32768) * 100.0
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var dx = Float64(1000000 + Int(seed & UInt64(0xFFFF)))
        var dy = Float64(2000000 + Int((seed >> 16) & UInt64(0xFFFF)))
        var dz = Float64(3000000 + Int((seed >> 32) & UInt64(0xFFFF)))
        var dvx = Float64(Int((seed >> 8) & UInt64(0xFF)) - 128)
        var dvy = Float64(Int((seed >> 24) & UInt64(0xFF)) - 128)
        var dvz = Float64(Int((seed >> 40) & UInt64(0xFF)) - 128)
        var ue = NRNTNECEFStateVector(ux, uy, uz, 10.0, -20.0, 30.0)
        var satellite = NRNTNECEFStateVector(
            ux + dx,
            uy + dy,
            uz + dz,
            10.0 + dvx,
            -20.0 + dvy,
            30.0 + dvz,
        )
        var expected_range = sqrt(dx * dx + dy * dy + dz * dz)
        var expected_radial = (dx * dvx + dy * dvy + dz * dvz) / (
            expected_range
        )
        var carrier = 1900000000.0 + Float64(seed & UInt64(0xFFFF))
        var expected_rtt = 2.0 * expected_range / NR_NTN_SPEED_OF_LIGHT_MPS
        var expected_doppler = (
            -expected_radial * carrier / NR_NTN_SPEED_OF_LIGHT_MPS
        )
        assert_almost_equal(
            nr_ntn_rel17_service_link_range_m(ue, satellite),
            expected_range,
            rtol=1.0e-14,
        )
        assert_almost_equal(
            nr_ntn_rel17_service_link_rtt_seconds(ue, satellite),
            expected_rtt,
            rtol=1.0e-14,
        )
        assert_almost_equal(
            nr_ntn_rel17_radial_velocity_mps(ue, satellite),
            expected_radial,
            atol=1.0e-12,
        )
        assert_almost_equal(
            nr_ntn_rel17_service_link_doppler_shift_hz(
                ue, satellite, carrier
            ),
            expected_doppler,
            atol=1.0e-9,
        )
        assert_almost_equal(
            nr_ntn_rel17_uplink_frequency_precompensation_hz(
                ue, satellite, carrier
            ),
            -expected_doppler,
            atol=1.0e-9,
        )


def test_quantization_koffset_and_validity_exhaustive_properties() raises:
    var durations: List[Int] = [
        5, 10, 15, 20, 25, 30, 35, 40,
        45, 50, 55, 60, 120, 180, 240, 900,
    ]
    for duration in durations:
        var assistance = NRNTNRel17CommonTimingAssistance(
            1000000, 0, 0, duration
        )
        assert_true(
            nr_ntn_rel17_ul_sync_information_valid(
                assistance, duration * 1000000 - 1
            )
        )
        assert_false(
            nr_ntn_rel17_ul_sync_information_valid(
                assistance, duration * 1000000
            )
        )

    for cell in range(1024):
        for differential in range(64):
            var expected = cell - differential
            assert_equal(
                nr_ntn_rel17_effective_koffset_15khz_slots(
                    cell, differential
                ),
                expected,
            )
            assert_almost_equal(
                nr_ntn_rel17_koffset_seconds(cell, differential),
                Float64(expected) * 0.001,
                atol=0.0,
            )

    assert_true(
        nr_ntn_rel17_koffset_covers_propagation(31, 0, 0.030, 0.001)
    )
    assert_false(
        nr_ntn_rel17_koffset_covers_propagation(
            31, 0, 0.030000000000001, 0.001
        )
    )

    var seed = UInt64(0x13198A2E03707344)
    for _ in range(257):
        seed = seed * UInt64(2862933555777941757) + UInt64(3037000493)
        var ta_raw = 1000000 + Int(seed % UInt64(1000000))
        var drift_raw = Int((seed >> 20) % UInt64(200001)) - 100000
        var variant_raw = Int((seed >> 40) % UInt64(10001))
        var elapsed = Float64(Int((seed >> 8) % UInt64(4999))) / 1000.0
        var assistance = NRNTNRel17CommonTimingAssistance(
            ta_raw, drift_raw, variant_raw, 5
        )
        var expected = (
            Float64(ta_raw) * 4.072e-9
            + Float64(drift_raw) * 2.0e-10 * elapsed
            + Float64(variant_raw) * 2.0e-11 * elapsed * elapsed
        )
        assert_almost_equal(
            nr_ntn_rel17_common_ta_seconds(assistance, elapsed),
            expected,
            rtol=1.0e-15,
        )
        assert_almost_equal(
            nr_ntn_rel17_common_one_way_delay_seconds(assistance, elapsed),
            0.5 * expected,
            rtol=1.0e-15,
        )


def test_seeded_composite_matches_independent_rel17_formula() raises:
    var seed = UInt64(0xA4093822299F31D0)
    for _ in range(129):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var dx = 1000000.0 + Float64(seed & UInt64(0xFFFF))
        var dy = 2000000.0 + Float64((seed >> 16) & UInt64(0xFFFF))
        var dz = 3000000.0 + Float64((seed >> 32) & UInt64(0xFFFF))
        var dvx = Float64(Int((seed >> 8) & UInt64(0xFF)) - 128)
        var dvy = Float64(Int((seed >> 24) & UInt64(0xFF)) - 128)
        var dvz = Float64(Int((seed >> 40) & UInt64(0xFF)) - 128)
        var ue = NRNTNECEFStateVector(
            6371000.0, 100.0, -200.0, 10.0, 20.0, 30.0
        )
        var satellite = NRNTNECEFStateVector(
            ue.x_m + dx,
            ue.y_m + dy,
            ue.z_m + dz,
            ue.vx_mps + dvx,
            ue.vy_mps + dvy,
            ue.vz_mps + dvz,
        )
        var ta_raw = 100000 + Int((seed >> 4) % UInt64(100000))
        var drift_raw = Int((seed >> 28) % UInt64(2001)) - 1000
        var variant_raw = Int((seed >> 48) % UInt64(101))
        var elapsed = Float64(Int(seed % UInt64(4999))) / 1000.0
        var carrier = 1900000000.0 + Float64(seed & UInt64(0xFFFF))
        var assistance = NRNTNRel17CommonTimingAssistance(
            ta_raw, drift_raw, variant_raw, 5
        )
        var result = nr_ntn_rel17_precompensation(
            ue, satellite, assistance, elapsed, carrier, 200, 7
        )
        var expected_range = sqrt(dx * dx + dy * dy + dz * dz)
        var expected_rtt = 2.0 * expected_range / 299792458.0
        var expected_radial = (dx * dvx + dy * dvy + dz * dvz) / (
            expected_range
        )
        var expected_doppler = -expected_radial * carrier / 299792458.0
        var expected_common = (
            Float64(ta_raw) * 4.072e-9
            + Float64(drift_raw) * 2.0e-10 * elapsed
            + Float64(variant_raw) * 2.0e-11 * elapsed * elapsed
        )
        assert_almost_equal(
            result.service_link_range_m, expected_range, rtol=1.0e-14
        )
        assert_almost_equal(
            result.service_link_rtt_seconds, expected_rtt, rtol=1.0e-14
        )
        assert_almost_equal(
            result.radial_velocity_mps, expected_radial, atol=1.0e-12
        )
        assert_almost_equal(
            result.received_doppler_shift_hz,
            expected_doppler,
            atol=1.0e-9,
        )
        assert_almost_equal(
            result.uplink_frequency_precompensation_hz,
            -expected_doppler,
            atol=1.0e-9,
        )
        assert_almost_equal(
            result.common_ta_seconds, expected_common, rtol=1.0e-15
        )
        assert_almost_equal(
            result.ntn_propagation_ta_seconds,
            expected_rtt + expected_common,
            rtol=1.0e-14,
        )
        assert_equal(result.effective_koffset_15khz_slots, 193)
        assert_almost_equal(
            result.effective_koffset_seconds, 0.193, atol=0.0
        )


def test_scale_safe_finite_extremes_and_public_mutation_edges() raises:
    var ue = _zero_state()
    var huge = NRNTNECEFStateVector(
        8.0e307, 6.0e307, 0.0, 1.0, 2.0, 3.0
    )
    assert_almost_equal(
        nr_ntn_rel17_service_link_range_m(ue, huge), 1.0e308, rtol=1.0e-15
    )

    var same = _zero_state()
    with assert_raises():
        _ = nr_ntn_rel17_service_link_range_m(ue, same)
    with assert_raises():
        _ = nr_ntn_rel17_service_link_rtt_seconds(ue, same)
    var invalid = _zero_state()
    invalid.x_m = nan[DType.float64]()
    with assert_raises():
        _ = nr_ntn_rel17_service_link_range_m(invalid, huge)
    invalid = _zero_state()
    invalid.vx_mps = inf[DType.float64]()
    with assert_raises():
        _ = nr_ntn_rel17_radial_velocity_mps(invalid, huge)
    var left = NRNTNECEFStateVector(
        -1.0e308, 0.0, 0.0, 0.0, 0.0, 0.0
    )
    var right = NRNTNECEFStateVector(
        1.0e308, 0.0, 0.0, 0.0, 0.0, 0.0
    )
    with assert_raises():
        _ = nr_ntn_rel17_service_link_range_m(left, right)

    var assistance = NRNTNRel17CommonTimingAssistance(0, 0, 0, 5)
    assistance.ta_common_drift_raw = NR_NTN_TA_COMMON_DRIFT_RAW_MAX + 1
    with assert_raises():
        _ = nr_ntn_rel17_common_ta_seconds(assistance, 0.0)
    assistance = NRNTNRel17CommonTimingAssistance(0, 0, 0, 5)
    with assert_raises():
        _ = nr_ntn_rel17_common_ta_seconds(assistance, 5.0)
    with assert_raises():
        _ = nr_ntn_rel17_common_one_way_delay_seconds(assistance, 5.0)
    with assert_raises():
        _ = nr_ntn_rel17_ul_sync_information_valid(assistance, -1)
    with assert_raises():
        _ = nr_ntn_rel17_effective_koffset_15khz_slots(-1, 0)
    with assert_raises():
        _ = nr_ntn_rel17_effective_koffset_15khz_slots(1024, 0)
    with assert_raises():
        _ = nr_ntn_rel17_effective_koffset_15khz_slots(1, 64)
    with assert_raises():
        _ = nr_ntn_rel17_koffset_seconds(1, 64)
    with assert_raises():
        _ = nr_ntn_rel17_service_link_doppler_shift_hz(ue, huge, 0.0)
    with assert_raises():
        _ = nr_ntn_rel17_uplink_frequency_precompensation_hz(ue, huge, 0.0)
    with assert_raises():
        _ = nr_ntn_rel17_koffset_covers_propagation(1, 0, -1.0, 0.0)
    with assert_raises():
        _ = nr_ntn_rel17_precompensation(
            ue,
            NRNTNECEFStateVector(
                3000000.0, 4000000.0, 0.0, 0.0, 0.0, 0.0
            ),
            assistance,
            0.0,
            2000000000.0,
            1,
            0,
        )

    var superluminal = NRNTNECEFStateVector(
        1.0, 0.0, 0.0, 2.0 * NR_NTN_SPEED_OF_LIGHT_MPS, 0.0, 0.0
    )
    with assert_raises():
        _ = nr_ntn_rel17_service_link_doppler_shift_hz(
            ue, superluminal, 2000000000.0
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
