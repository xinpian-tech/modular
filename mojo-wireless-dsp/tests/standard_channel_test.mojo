from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.core import Complex64, Span
from wireless_dsp.channel.standard_profiles import (
    StandardChannelProfile,
    STANDARD_FAMILY_3GPP_TDL,
    STANDARD_FAMILY_WIFI_TGAC,
    STANDARD_FAMILY_WIFI_TGAX,
    STANDARD_DOPPLER_JAKES,
    STANDARD_PATH_LOS,
    STANDARD_PATH_RAYLEIGH,
    apply_standard_channel,
    realize_standard_channel_paths,
    standard_channel_impulse_response,
    tdl_profile,
    wifi_tgn_profile,
    wifi_tgac_profile,
    wifi_tgax_profile,
)


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _assert_normalized(profile: StandardChannelProfile) raises:
    var powers = profile.normalized_linear_powers()
    var total = 0.0
    for value in powers:
        total += value
    _assert_close(total, 1.0, 2.0e-15)


def _extreme_standard_profile(
    strongest_db: Float64, weaker_db: Float64
) raises -> StandardChannelProfile:
    var delays: List[Float64] = [0.0, 1.0]
    var powers: List[Float64] = [strongest_db, weaker_db]
    var kinds: List[Int] = [STANDARD_PATH_RAYLEIGH, STANDARD_PATH_RAYLEIGH]
    return StandardChannelProfile(
        String("extreme-dB"), STANDARD_FAMILY_3GPP_TDL, delays^, powers^,
        kinds^, 1.0, STANDARD_DOPPLER_JAKES, False, 0.0, 0.0,
    )


def test_normalized_powers_are_invariant_to_extreme_common_db_shift() raises:
    var positive = _extreme_standard_profile(4000.0, 3990.0)
    var negative = _extreme_standard_profile(-4000.0, -4010.0)
    var positive_powers = positive.normalized_linear_powers()
    var negative_powers = negative.normalized_linear_powers()
    _assert_close(positive_powers[0], 10.0 / 11.0, 1.0e-12)
    _assert_close(positive_powers[1], 1.0 / 11.0, 1.0e-12)
    assert_equal(positive_powers, negative_powers)


def test_3gpp_tdl_tables_and_los_semantics() raises:
    var a = tdl_profile(String("A"), desired_delay_spread_ns=100.0)
    assert_equal(a.path_count(), 23)
    _assert_close(a.delays[1], 0.3819, 1.0e-15)
    _assert_close(a.powers_db[0], -13.4, 1.0e-15)
    _assert_close(a.delay_ns(22), 965.86, 1.0e-12)
    _assert_normalized(a)

    var b = tdl_profile(String("B"))
    assert_equal(b.path_count(), 23)
    _assert_close(b.delays[15], 1.7842, 1.0e-15)
    _assert_close(b.powers_db[15], -1.9, 1.0e-15)
    _assert_normalized(b)

    var c = tdl_profile(String("C"))
    assert_equal(c.path_count(), 24)
    _assert_close(c.delays[23], 8.6523, 1.0e-15)
    _assert_close(c.powers_db[5], 0.0, 1.0e-15)
    _assert_normalized(c)

    var d = tdl_profile(String("D"))
    assert_equal(d.path_count(), 14)
    assert_equal(d.tap_count(), 13)
    assert_true(d.has_los)
    assert_equal(d.fading_kinds[0], STANDARD_PATH_LOS)
    _assert_close(d.delays[0], 0.0, 0.0)
    _assert_close(d.delays[1], 0.0, 0.0)
    _assert_close(d.powers_db[0] - d.powers_db[1], 13.3, 1.0e-14)
    _assert_close(d.los_k_factor_db, 13.3, 1.0e-15)
    _assert_close(d.los_doppler_ratio, 0.7, 1.0e-15)
    _assert_normalized(d)

    var e = tdl_profile(String("E"))
    assert_equal(e.path_count(), 15)
    assert_equal(e.tap_count(), 14)
    assert_true(e.has_los)
    _assert_close(e.powers_db[0] - e.powers_db[1], 22.0, 1.0e-14)
    _assert_close(e.delays[14], 20.6519, 1.0e-15)
    _assert_normalized(e)


def test_wifi_a_through_f_known_profiles_and_families() raises:
    var a = wifi_tgn_profile(String("A"))
    assert_equal(a.path_count(), 1)
    _assert_close(a.rms_delay_spread_ns(), 0.0, 0.0)

    var b = wifi_tgn_profile(String("B"))
    assert_equal(b.path_count(), 9)
    _assert_close(b.delays[8], 80.0, 0.0)
    _assert_close(b.powers_db[2], -2.5, 0.0)
    _assert_close(b.rms_delay_spread_ns(), 15.0, 1.0)
    _assert_normalized(b)

    var c = wifi_tgn_profile(String("C"))
    assert_equal(c.path_count(), 14)
    _assert_close(c.delays[13], 200.0, 0.0)
    _assert_close(c.rms_delay_spread_ns(), 30.0, 4.0)

    var d = wifi_tgn_profile(String("D"))
    assert_equal(d.path_count(), 18)
    _assert_close(d.delays[17], 390.0, 0.0)
    _assert_close(d.rms_delay_spread_ns(), 50.0, 1.0)

    var e = wifi_tgac_profile(String("E"))
    assert_equal(e.family, STANDARD_FAMILY_WIFI_TGAC)
    assert_equal(e.path_count(), 18)
    _assert_close(e.delays[17], 730.0, 0.0)
    _assert_close(e.rms_delay_spread_ns(), 100.0, 2.0)

    var f = wifi_tgax_profile(String("F"))
    assert_equal(f.family, STANDARD_FAMILY_WIFI_TGAX)
    assert_equal(f.path_count(), 18)
    _assert_close(f.delays[17], 1050.0, 0.0)
    _assert_close(f.powers_db[4], 0.0, 0.0)
    _assert_close(f.rms_delay_spread_ns(), 150.0, 2.0)

    var los_d = wifi_tgn_profile(String("D"), los=True)
    assert_equal(los_d.path_count(), 19)
    assert_equal(los_d.tap_count(), 18)
    assert_true(los_d.has_los)
    assert_equal(los_d.fading_kinds[18], STANDARD_PATH_LOS)
    _assert_close(los_d.delays[18], 0.0, 0.0)
    _assert_close(los_d.powers_db[18] - los_d.powers_db[0], 3.0, 0.0)
    _assert_normalized(los_d)


def test_seed_reproducibility_and_ensemble_power() raises:
    var profile = tdl_profile(String("B"))
    var first = realize_standard_channel_paths(
        profile, seed=UInt64(0x12345678)
    )
    var second = realize_standard_channel_paths(
        profile, seed=UInt64(0x12345678)
    )
    assert_equal(first, second)
    var different = realize_standard_channel_paths(
        profile, seed=UInt64(0x12345679)
    )
    assert_true(first[0] != different[0])

    var mean_power = 0.0
    var realization_count = 2000
    for realization in range(realization_count):
        var paths = realize_standard_channel_paths(
            profile, seed=UInt64(1000 + realization)
        )
        for path in paths:
            mean_power += path.magnitude_squared()
    mean_power /= Float64(realization_count)
    _assert_close(mean_power, 1.0, 0.025)

    # Repeat the normalization check with the deterministic LOS component and
    # diffuse paths of TDL-D.
    var los_profile = tdl_profile(String("D"))
    var los_mean_power = 0.0
    for realization in range(realization_count):
        var paths = realize_standard_channel_paths(
            los_profile, seed=UInt64(9000 + realization)
        )
        for path in paths:
            los_mean_power += path.magnitude_squared()
    los_mean_power /= Float64(realization_count)
    _assert_close(los_mean_power, 1.0, 0.025)


def test_tgac_tgax_wideband_cluster_interpolation() raises:
    # 09/0308r12 Table 1 selects k=2 and 5 ns PDP spacing at 80 MHz.
    var b80 = wifi_tgac_profile(String("B"), bandwidth_mhz=80)
    assert_equal(b80.path_count(), 17)
    _assert_close(b80.delays[0], 0.0, 0.0)
    _assert_close(b80.delays[1], 5.0, 0.0)
    _assert_close(b80.delays[16], 80.0, 0.0)
    # Cluster 1 interpolates linearly in dB from 0 to -5.4 dB.
    _assert_close(b80.powers_db[1], -2.7, 1.0e-9)
    # At 20 ns the two standard clusters combine in linear power.
    _assert_close(b80.powers_db[4], -2.504132640257994, 1.0e-9)
    _assert_normalized(b80)

    # TGax adopts the indoor TGn/TGac profile and 160 MHz selects k=4.
    var f160 = wifi_tgax_profile(String("F"), bandwidth_mhz=160)
    assert_true(f160.path_count() > 18)
    _assert_close(f160.delays[1], 2.5, 0.0)
    _assert_close(f160.delays[f160.path_count() - 1], 1050.0, 0.0)
    _assert_normalized(f160)

    var d160_los = wifi_tgac_profile(
        String("D"), bandwidth_mhz=160, los=True
    )
    var los_path = d160_los.path_count() - 1
    assert_equal(d160_los.fading_kinds[los_path], STANDARD_PATH_LOS)
    _assert_close(d160_los.delays[los_path], 0.0, 0.0)
    _assert_close(
        d160_los.powers_db[los_path] - d160_los.powers_db[0],
        3.0,
        1.0e-14,
    )


def test_fractional_impulse_response_matches_direct_application() raises:
    var profile = tdl_profile(
        String("A"), desired_delay_spread_ns=100.0
    )
    var sample_rate_hz = 10.0e6
    var impulse: List[Complex64] = [Complex64(1.0, 0.0)]
    var response = standard_channel_impulse_response(
        profile, sample_rate_hz, seed=UInt64(77)
    )
    var applied = apply_standard_channel(
        Span(impulse), profile, sample_rate_hz, seed=UInt64(77)
    )
    assert_equal(len(response), 11)
    assert_equal(len(applied), len(response))
    for i in range(len(response)):
        _assert_close(applied[i].re, response[i].re, 2.0e-15)
        _assert_close(applied[i].im, response[i].im, 2.0e-15)

    var again = standard_channel_impulse_response(
        profile, sample_rate_hz, seed=UInt64(77)
    )
    assert_equal(response, again)


def test_static_and_time_varying_doppler_behavior() raises:
    var profile = tdl_profile(String("D"))
    var static_a = realize_standard_channel_paths(
        profile, time_seconds=0.0, maximum_doppler_hz=0.0,
        seed=UInt64(456),
    )
    var static_b = realize_standard_channel_paths(
        profile, time_seconds=4.0, maximum_doppler_hz=0.0,
        seed=UInt64(456),
    )
    assert_equal(static_a, static_b)

    var varying_a = realize_standard_channel_paths(
        profile, time_seconds=0.0, maximum_doppler_hz=100.0,
        seed=UInt64(456),
    )
    var varying_b = realize_standard_channel_paths(
        profile, time_seconds=0.001, maximum_doppler_hz=100.0,
        seed=UInt64(456),
    )
    assert_true(varying_a[0] != varying_b[0])
    assert_true(varying_a[2] != varying_b[2])
    _assert_close(
        varying_a[0].magnitude_squared(),
        varying_b[0].magnitude_squared(),
        2.0e-15,
    )

    var wifi = wifi_tgax_profile(String("B"))
    var wifi_a = realize_standard_channel_paths(
        wifi, time_seconds=0.0, maximum_doppler_hz=6.0,
        seed=UInt64(88),
    )
    var wifi_b = realize_standard_channel_paths(
        wifi, time_seconds=0.01, maximum_doppler_hz=6.0,
        seed=UInt64(88),
    )
    assert_true(wifi_a[0] != wifi_b[0])


def test_doppler_phase_products_reduce_in_cycle_domain() raises:
    # A one-second step at this Float64 Doppler is an integer number of cycles,
    # even though multiplying by 2*pi first would overflow.
    var los_profile = tdl_profile(String("D"))
    var at_zero = realize_standard_channel_paths(
        los_profile, time_seconds=0.0, maximum_doppler_hz=1.0e308,
        seed=UInt64(90210),
    )
    var after_integer_cycles = realize_standard_channel_paths(
        los_profile, time_seconds=1.0, maximum_doppler_hz=1.0e308,
        seed=UInt64(90210),
    )
    assert_equal(after_integer_cycles, at_zero)

    # Wi-Fi's bell-spectrum ratios can exceed one.  The first product may
    # overflow even though the reciprocal time scale keeps the phase finite.
    var wifi_profile = wifi_tgn_profile(String("B"))
    var ordinary = realize_standard_channel_paths(
        wifi_profile, time_seconds=1.0, maximum_doppler_hz=1.0,
        seed=UInt64(123456),
    )
    var balanced_extremes = realize_standard_channel_paths(
        wifi_profile, time_seconds=1.0e-308,
        maximum_doppler_hz=1.0e308, seed=UInt64(123456),
    )
    for index in range(len(ordinary)):
        _assert_close(
            balanced_extremes[index].re, ordinary[index].re, 2.0e-12
        )
        _assert_close(
            balanced_extremes[index].im, ordinary[index].im, 2.0e-12
        )


def test_mutable_profile_is_revalidated_at_every_public_boundary() raises:
    var profile = tdl_profile(String("A"))
    profile.family = -1
    with assert_raises():
        profile.validate()
    with assert_raises():
        _ = profile.path_count()
    with assert_raises():
        _ = profile.tap_count()
    with assert_raises():
        _ = profile.delay_ns(0)
    with assert_raises():
        _ = profile.maximum_delay_ns()
    with assert_raises():
        _ = profile.total_linear_power()
    with assert_raises():
        _ = profile.normalized_linear_powers()
    with assert_raises():
        _ = profile.rms_delay_spread_ns()
    with assert_raises():
        _ = realize_standard_channel_paths(profile, seed=UInt64(1))
    with assert_raises():
        _ = standard_channel_impulse_response(
            profile, 1.0e6, seed=UInt64(1)
        )
    var empty = List[Complex64]()
    with assert_raises():
        _ = apply_standard_channel(
            Span(empty), profile, 1.0e6, seed=UInt64(1)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
