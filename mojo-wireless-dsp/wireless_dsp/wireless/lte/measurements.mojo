"""Finite, scale-stable linear LTE measurements from TS 36.214 V18.1.0.

Inputs are already-selected useful-symbol observations at the UE antenna
connector.  Selection of measurement subframes, receiver-diversity combining,
unit calibration, and conversion to dB are deliberately left to the caller.
"""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.core import Complex64


def _lte_linear_average_power(
    observations: Span[Complex64, ...], measurement_name: StringSlice
) raises -> Float64:
    if len(observations) < 1:
        raise Error(String(measurement_name) + " requires at least one observation")
    var scale = 0.0
    for index in range(len(observations)):
        var value = observations[index]
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error(String(measurement_name) + " observations must be finite")
        scale = max(scale, max(abs(value.re), abs(value.im)))
    if scale == 0.0:
        return 0.0

    # Neumaier-style compensation is applied after scaling all components to
    # [-1,1].  It avoids both direct-square overflow and loss of small terms.
    var total = 0.0
    var compensation = 0.0
    for index in range(len(observations)):
        var value = observations[index]
        var real = value.re / scale
        var imaginary = value.im / scale
        var term = real * real + imaginary * imaginary
        var candidate = total + term
        if abs(total) >= abs(term):
            compensation += (total - candidate) + term
        else:
            compensation += (term - candidate) + total
        total = candidate
    var normalized_mean = (total + compensation) / Float64(len(observations))
    if normalized_mean <= 0.0 or not isfinite(normalized_mean):
        raise Error(String(measurement_name) + " normalized power is not representable")
    var rms = scale * sqrt(normalized_mean)
    if not isfinite(rms) or rms > sqrt(Float64.MAX_FINITE):
        raise Error(String(measurement_name) + " linear power exceeds Float64 range")
    return rms * rms


def _lte_positive_finite_ratio(
    numerator: Float64,
    denominator: Float64,
    measurement_name: StringSlice,
    *, allow_zero_numerator: Bool = True,
) raises -> Float64:
    if (
        not isfinite(numerator)
        or not isfinite(denominator)
        or numerator < 0.0
        or (not allow_zero_numerator and numerator == 0.0)
        or denominator <= 0.0
    ):
        raise Error(String(measurement_name) + " powers must be finite and valid")
    if numerator == 0.0:
        return 0.0
    var scale = max(numerator, denominator)
    var ratio = (numerator / scale) / (denominator / scale)
    if not isfinite(ratio):
        raise Error(String(measurement_name) + " ratio exceeds Float64 range")
    return ratio


def lte_rsrp(crs_observations: Span[Complex64, ...]) raises -> Float64:
    """Clause 5.1.1 linear average power per selected CRS resource element."""
    return _lte_linear_average_power(crs_observations, "LTE RSRP")


def lte_rssi(
    received_resource_elements: Span[Complex64, ...],
    resource_elements_per_symbol: Int,
) raises -> Float64:
    """Clauses 5.1.3/5.1.24 average total received power per OFDM symbol.

    The flattened input must contain complete configured measurement symbols;
    summing the per-RE powers within each symbol and averaging over symbols is
    equivalent to multiplying the all-RE average by the RE count per symbol.
    """
    if (
        resource_elements_per_symbol < 1
        or len(received_resource_elements) < resource_elements_per_symbol
        or len(received_resource_elements) % resource_elements_per_symbol != 0
    ):
        raise Error("LTE RSSI input must contain complete non-empty OFDM symbols")
    var average_re_power = _lte_linear_average_power(
        received_resource_elements, "LTE RSSI"
    )
    if (
        average_re_power > 0.0
        and average_re_power
        > Float64.MAX_FINITE / Float64(resource_elements_per_symbol)
    ):
        raise Error("LTE RSSI linear power exceeds Float64 range")
    return average_re_power * Float64(resource_elements_per_symbol)


def lte_rsrq(
    rsrp_linear: Float64,
    rssi_linear: Float64,
    measurement_resource_blocks: Int,
) raises -> Float64:
    """Clause 5.1.3 ``N * RSRP / E-UTRA carrier RSSI`` in linear units."""
    if measurement_resource_blocks < 1 or measurement_resource_blocks > 110:
        raise Error("LTE RSRQ measurement bandwidth must contain 1 to 110 RBs")
    var ratio = _lte_positive_finite_ratio(
        rsrp_linear, rssi_linear, "LTE RSRQ"
    )
    if (
        ratio > 0.0
        and ratio > Float64.MAX_FINITE / Float64(measurement_resource_blocks)
    ):
        raise Error("LTE RSRQ linear ratio exceeds Float64 range")
    return Float64(measurement_resource_blocks) * ratio


def lte_rs_sinr_from_powers(
    reference_signal_power: Float64,
    interference_noise_power: Float64,
) raises -> Float64:
    """Clause 5.1.23 linear CRS power divided by interference/noise power."""
    return _lte_positive_finite_ratio(
        reference_signal_power,
        interference_noise_power,
        "LTE RS-SINR",
    )


def lte_rs_sinr(
    reference_signal_observations: Span[Complex64, ...],
    interference_noise_observations: Span[Complex64, ...],
) raises -> Float64:
    """Measure RS-SINR from paired selected-CRS signal and noise samples."""
    if len(reference_signal_observations) != len(interference_noise_observations):
        raise Error("LTE RS-SINR signal and interference observations must match")
    var reference_signal_power = _lte_linear_average_power(
        reference_signal_observations, "LTE RS-SINR reference signal"
    )
    var interference_noise_power = _lte_linear_average_power(
        interference_noise_observations, "LTE RS-SINR interference and noise"
    )
    return lte_rs_sinr_from_powers(
        reference_signal_power, interference_noise_power
    )
