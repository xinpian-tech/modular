"""Independent evidence for bounded IEEE 802.11 FTM range arithmetic."""

from std.testing import (
    assert_almost_equal,
    assert_equal,
    assert_raises,
    TestSuite,
)
from wireless_dsp.wireless.wifi.ftm_ranging import (
    WIFI_FTM_SPEED_OF_LIGHT_MPS,
    WIFI_FTM_PICOSECONDS_PER_SECOND,
    WifiFTMExchangeTimestamps,
    wifi_ftm_exchange_intervals_ps,
    wifi_ftm_corrected_round_trip_ps,
    wifi_ftm_link_delay_seconds,
    wifi_ftm_range_m,
    wifi_ftm_range_result,
)


def _oracle_corrected_ps(
    t1: Int, t2: Int, t3: Int, t4: Int, ratio: Float64
) -> Float64:
    # Independent direct transcription of the WG antenna-port equation.
    return Float64(t4 - t1) - ratio * Float64(t3 - t2)


def test_ftm_static_antenna_port_equation_and_distance() raises:
    # Responder RTT=18 us, initiator turnaround=16 us.  The resulting
    # one-way delay is 1 us and vacuum-equivalent distance is 299.792458 m.
    var exchange = WifiFTMExchangeTimestamps(
        1000000, 7000000, 23000000, 19000000
    )
    var intervals = wifi_ftm_exchange_intervals_ps(exchange)
    assert_equal(intervals.responder_round_trip_ps, 18000000)
    assert_equal(intervals.initiator_turnaround_ps, 16000000)
    assert_equal(intervals.equal_rate_corrected_round_trip_ps, 2000000)
    assert_equal(wifi_ftm_corrected_round_trip_ps(exchange), 2000000)
    assert_almost_equal(
        wifi_ftm_link_delay_seconds(exchange), 1.0e-6, atol=0.0
    )
    assert_almost_equal(
        wifi_ftm_range_m(exchange),
        1.0e-6 * WIFI_FTM_SPEED_OF_LIGHT_MPS,
        atol=0.0,
    )

    var result = wifi_ftm_range_result(exchange)
    assert_equal(result.responder_round_trip_ps, 18000000)
    assert_equal(result.initiator_turnaround_ps, 16000000)
    assert_almost_equal(result.initiator_to_responder_rate_ratio, 1.0)
    assert_almost_equal(result.corrected_round_trip_ps, 2000000.0)
    assert_almost_equal(result.one_way_delay_seconds, 1.0e-6, atol=0.0)
    assert_almost_equal(
        result.distance_m, 1.0e-6 * WIFI_FTM_SPEED_OF_LIGHT_MPS, atol=0.0
    )


def test_ftm_clock_rate_ratio_static_oracle() raises:
    # 15 us of initiator time converts to 16 us of responder time.
    var exchange = WifiFTMExchangeTimestamps(
        1000000, 7000000, 22000000, 19000000
    )
    var ratio = 16.0 / 15.0
    var expected_ps = _oracle_corrected_ps(
        1000000, 7000000, 22000000, 19000000, ratio
    )
    assert_almost_equal(expected_ps, 2000000.0, atol=1.0e-9)
    assert_almost_equal(
        wifi_ftm_link_delay_seconds(exchange, ratio),
        0.5 * expected_ps / WIFI_FTM_PICOSECONDS_PER_SECOND,
        atol=1.0e-18,
    )
    assert_almost_equal(
        wifi_ftm_range_m(exchange, ratio),
        0.5
        * expected_ps
        / WIFI_FTM_PICOSECONDS_PER_SECOND
        * WIFI_FTM_SPEED_OF_LIGHT_MPS,
        atol=1.0e-12,
    )


def test_ftm_seeded_independent_formula_properties() raises:
    var state = UInt64(0xD1B54A32D192ED03)
    for trial in range(257):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var t1 = Int((state >> 17) & UInt64(0x7FFFFFFF))
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var t2 = Int((state >> 17) & UInt64(0x7FFFFFFF))
        var turnaround = 1000 + Int(state & UInt64(0xFFFFF))
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var rtt = turnaround + Int(state & UInt64(0x3FFFFF))
        var t3 = t2 + turnaround
        var t4 = t1 + rtt
        var exchange = WifiFTMExchangeTimestamps(t1, t2, t3, t4)
        var expected = rtt - turnaround
        var intervals = wifi_ftm_exchange_intervals_ps(exchange)
        assert_equal(intervals.responder_round_trip_ps, rtt)
        assert_equal(intervals.initiator_turnaround_ps, turnaround)
        assert_equal(intervals.equal_rate_corrected_round_trip_ps, expected)
        assert_equal(wifi_ftm_corrected_round_trip_ps(exchange), expected)

        var ratio = 0.9995 + Float64(trial % 11) * 0.00005
        var expected_ratio = _oracle_corrected_ps(
            t1, t2, t3, t4, ratio
        )
        if expected_ratio >= 0.0:
            assert_almost_equal(
                wifi_ftm_link_delay_seconds(exchange, ratio),
                0.5
                * expected_ratio
                / WIFI_FTM_PICOSECONDS_PER_SECOND,
                atol=1.0e-18,
            )
            assert_almost_equal(
                wifi_ftm_range_result(exchange, ratio).distance_m,
                wifi_ftm_range_m(exchange, ratio),
                atol=1.0e-12,
            )


def test_ftm_public_boundaries_mutation_and_nonfinite_rates() raises:
    with assert_raises():
        _ = WifiFTMExchangeTimestamps(-1, 0, 0, 0)
    with assert_raises():
        _ = WifiFTMExchangeTimestamps(2, 0, 0, 1)
    with assert_raises():
        _ = WifiFTMExchangeTimestamps(0, 2, 1, 0)

    var mutable = WifiFTMExchangeTimestamps(1, 2, 4, 5)
    mutable.t4_responder_arrival_ps = 0
    with assert_raises():
        _ = wifi_ftm_exchange_intervals_ps(mutable)

    var negative = WifiFTMExchangeTimestamps(0, 0, 2, 1)
    with assert_raises():
        _ = wifi_ftm_corrected_round_trip_ps(negative)

    var valid = WifiFTMExchangeTimestamps(0, 0, 1, 2)
    with assert_raises():
        _ = wifi_ftm_link_delay_seconds(valid, 0.0)
    with assert_raises():
        _ = wifi_ftm_range_m(valid, -1.0)
    with assert_raises():
        _ = wifi_ftm_range_result(valid, FloatLiteral.nan)
    with assert_raises():
        _ = wifi_ftm_link_delay_seconds(valid, FloatLiteral.infinity)
    with assert_raises():
        _ = wifi_ftm_link_delay_seconds(
            valid, Float64.MAX_FINITE
        )

    var extreme = WifiFTMExchangeTimestamps(
        0, 0, Int.MAX - 1, Int.MAX
    )
    assert_equal(wifi_ftm_corrected_round_trip_ps(extreme), 1)
    assert_almost_equal(
        wifi_ftm_link_delay_seconds(extreme), 0.5e-12, atol=0.0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
