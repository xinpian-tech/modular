"""Pilot-aided residual phase tracking for Wi-Fi OFDM symbols.

Inputs are channel-equalized pilot tones.  The readable reference first removes
the known BPSK/QPSK pilot value, unwraps phase in increasing subcarrier order,
then fits ``phase(k) = common_phase + slope*k`` by least squares.  The common
term tracks residual CPE/CFO and the slope tracks residual timing/sample-clock
phase across frequency; the estimator is shared by HT/VHT/HE/EHT receivers.
"""

from std.collections import Span
from std.math import atan2, cos, isfinite, sin
from wireless_dsp.core import Complex64


comptime _PI = 3.1415926535897932384626433832795
comptime _TWO_PI = 6.283185307179586476925286766559


struct WifiPilotPhaseEstimate(Movable):
    var common_phase: Float64
    var phase_slope: Float64
    var residual_mean_square: Float64

    def __init__(
        out self,
        common_phase: Float64,
        phase_slope: Float64,
        residual_mean_square: Float64,
    ):
        self.common_phase = common_phase
        self.phase_slope = phase_slope
        self.residual_mean_square = residual_mean_square


def wifi_estimate_pilot_phase(
    received: Span[Complex64, ...],
    known: Span[Complex64, ...],
    subcarrier_indices: Span[Int, ...],
) raises -> WifiPilotPhaseEstimate:
    """Estimate common and linear phase from equalized pilots."""
    if (
        len(received) == 0
        or len(received) != len(known)
        or len(received) != len(subcarrier_indices)
    ):
        raise Error("pilot vectors must be nonempty and have equal length")
    var phases = List[Float64](capacity=len(received))
    var sum_x = 0.0
    var sum_y = 0.0
    var previous = 0.0
    for i in range(len(received)):
        if i > 0 and subcarrier_indices[i] <= subcarrier_indices[i - 1]:
            raise Error("pilot subcarrier indices must be strictly increasing")
        var known_pilot = Complex64(known[i].re, known[i].im)
        var received_pilot = Complex64(received[i].re, received[i].im)
        if (
            not isfinite(known_pilot.re)
            or not isfinite(known_pilot.im)
            or not isfinite(received_pilot.re)
            or not isfinite(received_pilot.im)
        ):
            raise Error("pilot phase inputs must be finite")
        if (
            (known_pilot.re == 0.0 and known_pilot.im == 0.0)
            or (
                received_pilot.re == 0.0
                and received_pilot.im == 0.0
            )
        ):
            raise Error("pilot phase cannot be estimated from a zero tone")
        # The phase of received*conj(known) is the difference of the two
        # arguments.  Computing that difference directly avoids overflow for
        # huge finite pilots and underflow for subnormal pilots.
        var phase = (
            atan2(received_pilot.im, received_pilot.re)
            - atan2(known_pilot.im, known_pilot.re)
        )
        if i > 0:
            while phase - previous > _PI:
                phase -= _TWO_PI
            while phase - previous < -_PI:
                phase += _TWO_PI
        phases.append(phase)
        previous = phase
        sum_x += Float64(subcarrier_indices[i])
        sum_y += phase

    var mean_x = sum_x / Float64(len(received))
    var mean_y = sum_y / Float64(len(received))
    var covariance = 0.0
    var variance = 0.0
    for i in range(len(received)):
        var dx = Float64(subcarrier_indices[i]) - mean_x
        covariance += dx * (phases[i] - mean_y)
        variance += dx * dx
    var slope = covariance / variance if variance > 0.0 else 0.0
    var common = mean_y - slope * mean_x
    while common > _PI:
        common -= _TWO_PI
    while common <= -_PI:
        common += _TWO_PI

    var residual = 0.0
    for i in range(len(received)):
        var error = phases[i] - (
            common + slope * Float64(subcarrier_indices[i])
        )
        while error > _PI:
            error -= _TWO_PI
        while error < -_PI:
            error += _TWO_PI
        residual += error * error
    return WifiPilotPhaseEstimate(common, slope, residual / Float64(len(received)))


def wifi_correct_pilot_phase(
    samples: Span[Complex64, ...],
    subcarrier_indices: Span[Int, ...],
    estimate: WifiPilotPhaseEstimate,
) raises -> List[Complex64]:
    """Remove an estimated common/linear pilot phase from arbitrary tones."""
    if len(samples) != len(subcarrier_indices):
        raise Error("sample and subcarrier-index vectors must have equal length")
    if (
        not isfinite(estimate.common_phase)
        or not isfinite(estimate.phase_slope)
        or not isfinite(estimate.residual_mean_square)
        or estimate.residual_mean_square < 0.0
    ):
        raise Error("pilot phase estimate must contain finite valid fields")
    var result = List[Complex64](capacity=len(samples))
    for i in range(len(samples)):
        var sample = Complex64(samples[i].re, samples[i].im)
        if not isfinite(sample.re) or not isfinite(sample.im):
            raise Error("pilot phase correction samples must be finite")
        var phase = -(
            estimate.common_phase
            + estimate.phase_slope * Float64(subcarrier_indices[i])
        )
        if not isfinite(phase):
            raise Error("pilot phase correction angle is not representable")
        var corrected = sample * Complex64(cos(phase), sin(phase))
        if not isfinite(corrected.re) or not isfinite(corrected.im):
            raise Error("pilot phase correction result is not representable")
        result.append(corrected)
    return result^
