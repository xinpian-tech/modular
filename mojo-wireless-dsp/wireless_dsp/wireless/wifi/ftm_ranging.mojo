"""Bounded IEEE 802.11 Fine Timing Measurement range arithmetic.

This scalar CPU reference implements the deterministic timestamp calculation
used by the Fine Timing Measurement (FTM) procedure incorporated into IEEE
Std 802.11-2024.  For one exchange, the responder measures ``t4 - t1`` and
the initiator measures ``t3 - t2``.  The corrected round-trip delay is their
difference, and the one-way propagation delay is half that result.  An
optional positive clock-rate ratio converts initiator ticks into responder
ticks before subtraction.

All timestamps are caller-unwrapped, calibrated integer picoseconds.  This
module does not parse FTM frames, unwrap finite-width timestamp fields,
estimate RF arrival/departure instants, calibrate antenna/front-end delay,
protect measurements, schedule an FTM session, or estimate a position from
multiple ranges.  HE/EDMG secure ranging waveforms and IEEE 802.11bk 320-MHz
ranging remain outside this bounded arithmetic profile.

The normative publication is IEEE Std 802.11-2024, DOI
10.1109/IEEESTD.2025.10979691.  IEEE 802.11 WG document 11-14/1464r1 records
the independent equation ``RTD = (t4-t1) - (t3-t2)`` at the antenna ports.
"""

from std.math import isfinite


comptime WIFI_FTM_SPEED_OF_LIGHT_MPS = 299792458.0
comptime WIFI_FTM_PICOSECONDS_PER_SECOND = 1000000000000.0


struct WifiFTMExchangeTimestamps(ImplicitlyCopyable, Equatable):
    """Caller-unwrapped and calibrated FTM timestamps in picoseconds.

    ``t1`` and ``t4`` belong to the responder clock.  ``t2`` and ``t3``
    belong to the initiator clock.  Cross-clock numerical ordering is not
    meaningful; only each local departure/arrival pair is ordered.
    """

    var t1_responder_departure_ps: Int
    var t2_initiator_arrival_ps: Int
    var t3_initiator_departure_ps: Int
    var t4_responder_arrival_ps: Int

    def __init__(
        out self,
        t1_responder_departure_ps: Int,
        t2_initiator_arrival_ps: Int,
        t3_initiator_departure_ps: Int,
        t4_responder_arrival_ps: Int,
    ) raises:
        self.t1_responder_departure_ps = t1_responder_departure_ps
        self.t2_initiator_arrival_ps = t2_initiator_arrival_ps
        self.t3_initiator_departure_ps = t3_initiator_departure_ps
        self.t4_responder_arrival_ps = t4_responder_arrival_ps
        self.validate()

    def validate(self) raises:
        """Revalidate public mutable timestamp fields."""
        if (
            self.t1_responder_departure_ps < 0
            or self.t2_initiator_arrival_ps < 0
            or self.t3_initiator_departure_ps < 0
            or self.t4_responder_arrival_ps < 0
        ):
            raise Error("FTM caller-unwrapped timestamps must be non-negative")
        if (
            self.t4_responder_arrival_ps
            < self.t1_responder_departure_ps
        ):
            raise Error("FTM responder arrival precedes responder departure")
        if (
            self.t3_initiator_departure_ps
            < self.t2_initiator_arrival_ps
        ):
            raise Error("FTM initiator departure precedes initiator arrival")


struct WifiFTMExchangeIntervals(ImplicitlyCopyable, Equatable):
    """Exact local-clock intervals for one validated FTM exchange."""

    var responder_round_trip_ps: Int
    var initiator_turnaround_ps: Int
    var equal_rate_corrected_round_trip_ps: Int

    def __init__(
        out self,
        responder_round_trip_ps: Int,
        initiator_turnaround_ps: Int,
        equal_rate_corrected_round_trip_ps: Int,
    ):
        self.responder_round_trip_ps = responder_round_trip_ps
        self.initiator_turnaround_ps = initiator_turnaround_ps
        self.equal_rate_corrected_round_trip_ps = (
            equal_rate_corrected_round_trip_ps
        )


struct WifiFTMRangeResult(ImplicitlyCopyable):
    """Auditable clock-corrected delay and one-way range result."""

    var responder_round_trip_ps: Int
    var initiator_turnaround_ps: Int
    var initiator_to_responder_rate_ratio: Float64
    var corrected_round_trip_ps: Float64
    var one_way_delay_seconds: Float64
    var distance_m: Float64

    def __init__(
        out self,
        responder_round_trip_ps: Int,
        initiator_turnaround_ps: Int,
        initiator_to_responder_rate_ratio: Float64,
        corrected_round_trip_ps: Float64,
        one_way_delay_seconds: Float64,
        distance_m: Float64,
    ):
        self.responder_round_trip_ps = responder_round_trip_ps
        self.initiator_turnaround_ps = initiator_turnaround_ps
        self.initiator_to_responder_rate_ratio = (
            initiator_to_responder_rate_ratio
        )
        self.corrected_round_trip_ps = corrected_round_trip_ps
        self.one_way_delay_seconds = one_way_delay_seconds
        self.distance_m = distance_m


def wifi_ftm_exchange_intervals_ps(
    timestamps: WifiFTMExchangeTimestamps,
) raises -> WifiFTMExchangeIntervals:
    """Return exact local intervals and the equal-clock corrected RTT."""
    timestamps.validate()
    var responder = (
        timestamps.t4_responder_arrival_ps
        - timestamps.t1_responder_departure_ps
    )
    var turnaround = (
        timestamps.t3_initiator_departure_ps
        - timestamps.t2_initiator_arrival_ps
    )
    var corrected = responder - turnaround
    if corrected < 0:
        raise Error("FTM corrected round-trip delay cannot be negative")
    return WifiFTMExchangeIntervals(responder, turnaround, corrected)


def wifi_ftm_corrected_round_trip_ps(
    timestamps: WifiFTMExchangeTimestamps,
) raises -> Int:
    """Return ``(t4-t1)-(t3-t2)`` for equal-rate clocks, exactly."""
    return wifi_ftm_exchange_intervals_ps(
        timestamps
    ).equal_rate_corrected_round_trip_ps


def _clock_corrected_round_trip_ps(
    timestamps: WifiFTMExchangeTimestamps,
    initiator_to_responder_rate_ratio: Float64,
) raises -> Tuple[WifiFTMExchangeIntervals, Float64]:
    if (
        not isfinite(initiator_to_responder_rate_ratio)
        or initiator_to_responder_rate_ratio <= 0.0
    ):
        raise Error("FTM clock-rate ratio must be positive and finite")
    timestamps.validate()
    var responder_ps = (
        timestamps.t4_responder_arrival_ps
        - timestamps.t1_responder_departure_ps
    )
    var turnaround_ps = (
        timestamps.t3_initiator_departure_ps
        - timestamps.t2_initiator_arrival_ps
    )
    var exact_equal_rate = responder_ps - turnaround_ps
    var intervals = WifiFTMExchangeIntervals(
        responder_ps, turnaround_ps, exact_equal_rate
    )
    var turnaround = Float64(turnaround_ps)
    var rate_delta = 1.0 - initiator_to_responder_rate_ratio
    if (
        turnaround > 0.0
        and abs(rate_delta)
        > Float64.MAX_FINITE / turnaround
    ):
        raise Error("FTM rate-corrected turnaround is not representable")
    # Subtract the local integer intervals before conversion.  This preserves
    # a one-picosecond difference even when both timestamps are near Int.MAX.
    var corrected = Float64(exact_equal_rate) + rate_delta * turnaround
    if not isfinite(corrected) or corrected < 0.0:
        raise Error("FTM clock-corrected round-trip delay is invalid")
    return (intervals, corrected)


def wifi_ftm_link_delay_seconds(
    timestamps: WifiFTMExchangeTimestamps,
    initiator_to_responder_rate_ratio: Float64 = 1.0,
) raises -> Float64:
    """Return one-way propagation time from one FTM exchange.

    The rate ratio converts one initiator-clock picosecond to responder-clock
    picoseconds.  A value of one is the ordinary equal-rate FTM equation.
    """
    var corrected = _clock_corrected_round_trip_ps(
        timestamps, initiator_to_responder_rate_ratio
    )[1]
    var result = 0.5 * corrected / WIFI_FTM_PICOSECONDS_PER_SECOND
    if not isfinite(result):
        raise Error("FTM one-way propagation delay is not representable")
    return result


def wifi_ftm_range_m(
    timestamps: WifiFTMExchangeTimestamps,
    initiator_to_responder_rate_ratio: Float64 = 1.0,
) raises -> Float64:
    """Return one-way vacuum-equivalent range in metres."""
    var delay = wifi_ftm_link_delay_seconds(
        timestamps, initiator_to_responder_rate_ratio
    )
    var distance = delay * WIFI_FTM_SPEED_OF_LIGHT_MPS
    if not isfinite(distance):
        raise Error("FTM range is not representable")
    return distance


def wifi_ftm_range_result(
    timestamps: WifiFTMExchangeTimestamps,
    initiator_to_responder_rate_ratio: Float64 = 1.0,
) raises -> WifiFTMRangeResult:
    """Return exact intervals together with corrected delay and range."""
    var corrected = _clock_corrected_round_trip_ps(
        timestamps, initiator_to_responder_rate_ratio
    )
    var intervals = corrected[0]
    var corrected_ps = corrected[1]
    var delay = 0.5 * corrected_ps / WIFI_FTM_PICOSECONDS_PER_SECOND
    var distance = delay * WIFI_FTM_SPEED_OF_LIGHT_MPS
    if not isfinite(delay) or not isfinite(distance):
        raise Error("FTM range result is not representable")
    return WifiFTMRangeResult(
        intervals.responder_round_trip_ps,
        intervals.initiator_turnaround_ps,
        initiator_to_responder_rate_ratio,
        corrected_ps,
        delay,
        distance,
    )
