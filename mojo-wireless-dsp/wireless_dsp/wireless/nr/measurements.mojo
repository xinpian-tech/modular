"""Linear-domain NR UE measurement kernels from TS 38.215 V18.5.0.

This bounded single-receive-branch profile covers the clause 5.1 SS/CSI
RSRP, RSRQ, SINR, and NR carrier RSSI arithmetic.  Filtering, L1/L3 reporting,
beam selection, antenna combining, and measurement scheduling remain caller
policy; none of those state machines are implied by these pure functions.
"""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.core import Complex64


struct NRLinearMeasurements(ImplicitlyCopyable):
    """One internally consistent linear-domain measurement result."""

    var rsrp: Float64
    var rsrq: Float64
    var sinr: Float64
    var rssi: Float64

    def __init__(
        out self, rsrp: Float64, rsrq: Float64, sinr: Float64, rssi: Float64
    ) raises:
        if (
            not isfinite(rsrp)
            or not isfinite(rsrq)
            or not isfinite(sinr)
            or not isfinite(rssi)
            or rsrp < 0.0
            or rsrq < 0.0
            or sinr < 0.0
            or rssi <= 0.0
        ):
            raise Error("NR linear measurement fields are invalid")
        self.rsrp = rsrp
        self.rsrq = rsrq
        self.sinr = sinr
        self.rssi = rssi


def _scaled_complex_energy(
    samples: Span[Complex64, ...], divisor: Int, field: StringSlice,
) raises -> Float64:
    if len(samples) < 1 or divisor < 1 or len(samples) % divisor != 0:
        raise Error(String(field) + " dimensions are invalid")
    var scale = 0.0
    for index in range(len(samples)):
        var sample = samples[index]
        if not isfinite(sample.re) or not isfinite(sample.im):
            raise Error(String(field) + " samples must be finite")
        scale = max(scale, max(abs(sample.re), abs(sample.im)))
    if scale == 0.0:
        return 0.0

    var normalized_sum = 0.0
    for index in range(len(samples)):
        var normalized_re = samples[index].re / scale
        var normalized_im = samples[index].im / scale
        normalized_sum += (
            normalized_re * normalized_re
            + normalized_im * normalized_im
        )
    var normalized_factor = normalized_sum / Float64(divisor)
    var rms_scale = scale * sqrt(normalized_factor)
    if not isfinite(rms_scale):
        raise Error(String(field) + " power is not representable")
    var maximum_root = sqrt(Float64.MAX_FINITE)
    if rms_scale > maximum_root:
        raise Error(String(field) + " power overflows Float64")
    return rms_scale * rms_scale


def nr_reference_signal_received_power(
    reference_signal_res: Span[Complex64, ...],
) raises -> Float64:
    """Return the linear average received power per reference-signal RE."""
    return _scaled_complex_energy(
        reference_signal_res, len(reference_signal_res), "NR RSRP"
    )


def nr_ss_rsrp(sss_res: Span[Complex64, ...]) raises -> Float64:
    """SS-RSRP over the supplied SSS resource elements (clause 5.1.1)."""
    return nr_reference_signal_received_power(sss_res)


def nr_csi_rsrp(csi_rs_res: Span[Complex64, ...]) raises -> Float64:
    """CSI-RSRP over the supplied CSI-RS resource elements (clause 5.1.2)."""
    return nr_reference_signal_received_power(csi_rs_res)


def nr_rssi(
    measured_bandwidth_res: Span[Complex64, ...],
    observation_count: Int,
) raises -> Float64:
    """Return linear NR carrier RSSI averaged over measurement observations.

    The input is flattened observation-major and contains every RE in the
    measured bandwidth for each selected OFDM symbol.  Powers are summed
    within an observation and averaged across ``observation_count``.
    """
    return _scaled_complex_energy(
        measured_bandwidth_res, observation_count, "NR RSSI"
    )


def _rsrq(rsrp: Float64, rssi: Float64, resource_blocks: Int) raises -> Float64:
    if (
        not isfinite(rsrp)
        or not isfinite(rssi)
        or rsrp < 0.0
        or rssi <= 0.0
        or resource_blocks < 1
        or resource_blocks > 275
    ):
        raise Error("NR RSRQ inputs must be finite, positive, and in range")
    if rsrp == 0.0:
        return 0.0
    var ratio = rsrp / rssi
    if not isfinite(ratio) or ratio > Float64.MAX_FINITE / Float64(resource_blocks):
        raise Error("NR RSRQ is not representable")
    return Float64(resource_blocks) * ratio


def nr_ss_rsrq(ss_rsrp: Float64, rssi: Float64, resource_blocks: Int) raises -> Float64:
    """Return linear SS-RSRQ = N_RB * SS-RSRP / NR carrier RSSI."""
    return _rsrq(ss_rsrp, rssi, resource_blocks)


def nr_csi_rsrq(csi_rsrp: Float64, rssi: Float64, resource_blocks: Int) raises -> Float64:
    """Return linear CSI-RSRQ = N_RB * CSI-RSRP / NR carrier RSSI."""
    return _rsrq(csi_rsrp, rssi, resource_blocks)


def _sinr(signal_power: Float64, interference_noise_power: Float64) raises -> Float64:
    if (
        not isfinite(signal_power)
        or not isfinite(interference_noise_power)
        or signal_power < 0.0
        or interference_noise_power <= 0.0
    ):
        raise Error("NR SINR powers must be finite with a positive denominator")
    var result = signal_power / interference_noise_power
    if not isfinite(result):
        raise Error("NR SINR is not representable")
    return result


def nr_ss_sinr(
    ss_signal_power: Float64, interference_noise_power: Float64,
) raises -> Float64:
    """Return linear SS-SINR for same-RE signal and interference/noise powers."""
    return _sinr(ss_signal_power, interference_noise_power)


def nr_csi_sinr(
    csi_signal_power: Float64, interference_noise_power: Float64,
) raises -> Float64:
    """Return linear CSI-SINR for same-RE signal and interference/noise powers."""
    return _sinr(csi_signal_power, interference_noise_power)


def nr_ss_linear_measurements(
    sss_res: Span[Complex64, ...],
    measured_bandwidth_res: Span[Complex64, ...],
    interference_noise_res: Span[Complex64, ...],
    resource_blocks: Int,
    observation_count: Int,
) raises -> NRLinearMeasurements:
    """Evaluate a consistent SS-RSRP/RSRQ/SINR/RSSI checkpoint bundle."""
    if len(interference_noise_res) != len(sss_res):
        raise Error("SS-SINR signal and interference/noise RE counts must match")
    var rsrp = nr_ss_rsrp(sss_res)
    var rssi = nr_rssi(measured_bandwidth_res, observation_count)
    var interference_noise = nr_reference_signal_received_power(
        interference_noise_res
    )
    return NRLinearMeasurements(
        rsrp,
        nr_ss_rsrq(rsrp, rssi, resource_blocks),
        nr_ss_sinr(rsrp, interference_noise),
        rssi,
    )


def nr_csi_linear_measurements(
    csi_rs_res: Span[Complex64, ...],
    measured_bandwidth_res: Span[Complex64, ...],
    interference_noise_res: Span[Complex64, ...],
    resource_blocks: Int,
    observation_count: Int,
) raises -> NRLinearMeasurements:
    """Evaluate a consistent CSI-RSRP/RSRQ/SINR/RSSI checkpoint bundle."""
    if len(interference_noise_res) != len(csi_rs_res):
        raise Error("CSI-SINR signal and interference/noise RE counts must match")
    var rsrp = nr_csi_rsrp(csi_rs_res)
    var rssi = nr_rssi(measured_bandwidth_res, observation_count)
    var interference_noise = nr_reference_signal_received_power(
        interference_noise_res
    )
    return NRLinearMeasurements(
        rsrp,
        nr_csi_rsrq(rsrp, rssi, resource_blocks),
        nr_csi_sinr(rsrp, interference_noise),
        rssi,
    )
