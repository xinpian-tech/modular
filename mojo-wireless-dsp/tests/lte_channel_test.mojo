from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.channel import (
    StandardChannelProfile,
    STANDARD_FAMILY_3GPP_LTE,
    STANDARD_DOPPLER_JAKES,
    lte_profile,
    realize_standard_channel_paths,
)


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _assert_exact_table(
    actual_delays: List[Float64],
    actual_powers: List[Float64],
    expected_delays: List[Float64],
    expected_powers: List[Float64],
) raises:
    assert_equal(actual_delays, expected_delays)
    assert_equal(actual_powers, expected_powers)


def _assert_normalized(profile: StandardChannelProfile) raises:
    var normalized = profile.normalized_linear_powers()
    var total = 0.0
    for power in normalized:
        assert_true(power > 0.0)
        total += power
    _assert_close(total, 1.0, 2.0e-15)


def test_lte_epa_eva_etu_normative_annex_b_tables() raises:
    var epa = lte_profile(String("EPA"))
    _assert_exact_table(
        epa.delays,
        epa.powers_db,
        [0.0, 30.0, 70.0, 90.0, 110.0, 190.0, 410.0],
        [0.0, -1.0, -2.0, -3.0, -8.0, -17.2, -20.8],
    )
    assert_equal(epa.name, "LTE-EPA")
    assert_equal(epa.family, STANDARD_FAMILY_3GPP_LTE)
    assert_equal(epa.doppler_spectrum, STANDARD_DOPPLER_JAKES)
    assert_equal(epa.path_count(), 7)
    _assert_close(epa.maximum_delay_ns(), 410.0, 0.0)
    _assert_normalized(epa)

    var eva = lte_profile(String("EVA"))
    _assert_exact_table(
        eva.delays,
        eva.powers_db,
        [
            0.0, 30.0, 150.0, 310.0, 370.0, 710.0, 1090.0,
            1730.0, 2510.0,
        ],
        [
            0.0, -1.5, -1.4, -3.6, -0.6, -9.1, -7.0, -12.0,
            -16.9,
        ],
    )
    assert_equal(eva.name, "LTE-EVA")
    assert_equal(eva.path_count(), 9)
    _assert_close(eva.maximum_delay_ns(), 2510.0, 0.0)
    _assert_normalized(eva)

    var etu = lte_profile(String("ETU"))
    _assert_exact_table(
        etu.delays,
        etu.powers_db,
        [
            0.0, 50.0, 120.0, 200.0, 230.0, 500.0, 1600.0,
            2300.0, 5000.0,
        ],
        [-1.0, -1.0, -1.0, 0.0, 0.0, 0.0, -3.0, -5.0, -7.0],
    )
    assert_equal(etu.name, "LTE-ETU")
    assert_equal(etu.path_count(), 9)
    _assert_close(etu.maximum_delay_ns(), 5000.0, 0.0)
    _assert_normalized(etu)


def test_lte_profile_replay_doppler_combinations_and_edges() raises:
    var epa = lte_profile(String("EPA"))
    var first = realize_standard_channel_paths(
        epa, time_seconds=0.125, maximum_doppler_hz=5.0,
        seed=UInt64(36101),
    )
    var replay = realize_standard_channel_paths(
        epa, time_seconds=0.125, maximum_doppler_hz=5.0,
        seed=UInt64(36101),
    )
    assert_equal(first, replay)
    assert_equal(len(first), 7)

    var eva = lte_profile(String("EVA"))
    var eva5 = realize_standard_channel_paths(
        eva, time_seconds=0.01, maximum_doppler_hz=5.0,
        seed=UInt64(36102),
    )
    var eva70 = realize_standard_channel_paths(
        eva, time_seconds=0.01, maximum_doppler_hz=70.0,
        seed=UInt64(36102),
    )
    assert_true(eva5 != eva70)

    var etu = lte_profile(String("ETU"))
    var etu70 = realize_standard_channel_paths(
        etu, time_seconds=0.01, maximum_doppler_hz=70.0,
        seed=UInt64(36103),
    )
    var etu300 = realize_standard_channel_paths(
        etu, time_seconds=0.01, maximum_doppler_hz=300.0,
        seed=UInt64(36103),
    )
    assert_true(etu70 != etu300)

    with assert_raises():
        _ = lte_profile(String("epa"))
    with assert_raises():
        _ = lte_profile(String("ETU300"))

    var mutated = lte_profile(String("EPA"))
    mutated.family = -1
    with assert_raises():
        mutated.validate()
    with assert_raises():
        _ = mutated.path_count()
    with assert_raises():
        _ = realize_standard_channel_paths(
            mutated, maximum_doppler_hz=5.0, seed=UInt64(36104)
        )

    var mutated_delay = lte_profile(String("EVA"))
    mutated_delay.delays[0] = -1.0
    with assert_raises():
        _ = realize_standard_channel_paths(
            mutated_delay, maximum_doppler_hz=70.0, seed=UInt64(36105)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
