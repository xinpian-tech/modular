"""SISO tapped-delay channel reference utilities.

The LTE profiles reproduce 3GPP TS 36.101 V18.13.0 Annex B Tables B.2.1-2
through B.2.1-4.  EPA, EVA, and ETU retain their absolute nanosecond tap
coordinates and tabulated relative powers; callers select the normative
maximum-Doppler combination explicitly when realizing paths.

The non-normative 3GPP reference profiles reproduce TR 38.901 Tables
7.7.2-1 through 7.7.2-5.
Their delay coordinates are dimensionless and are scaled by the requested RMS
delay spread in nanoseconds.  TDL-A/B/C are NLOS Rayleigh profiles.  TDL-D/E
keep the tabulated specular and diffuse first-path entries separate, including
their 13.3 dB and 22 dB Ricean K factors and the 0.7*f_D LOS Doppler tone.

The non-normative WLAN references reproduce the aggregate SISO PDP of IEEE
802.11-03/940r4,
Appendix C.  IEEE 802.11-09/0308r12 extends these profiles to wider TGac
bandwidths, and IEEE 802.11-14/0882r4 adopts the TGn/TGac indoor profiles for
TGax.  The arbitrary-rate fractional-delay application below therefore keeps
one source of truth for TGn, TGac, and TGax rather than rounding the 10 ns
profile coordinates prematurely.

This module intentionally implements a readable scalar reference.  Diffuse
TDL paths use a deterministic sum-of-sinusoids approximation to the classical
Jakes spectrum.  WLAN diffuse paths use samples of the TGn bell spectrum
S(f) proportional to 1/(1 + 9*(f/f_D)^2), truncated at +/-5*f_D.  Every random
choice is derived from the caller-provided seed.  TR 38.901 and the cited
IEEE working-group documents are reference provenance only: this module is
excluded from ratified protocol completion and does not turn those documents
into production-standard authority.
"""

from std.collections import Span
from std.math import (
    ceil,
    cos,
    exp,
    frexp,
    isfinite,
    ldexp,
    log,
    remainder,
    sin,
    sqrt,
)
from wireless_dsp.core import Complex64


comptime STANDARD_FAMILY_3GPP_TDL = 1
comptime STANDARD_FAMILY_WIFI_TGN = 2
comptime STANDARD_FAMILY_WIFI_TGAC = 3
comptime STANDARD_FAMILY_WIFI_TGAX = 4
comptime STANDARD_FAMILY_3GPP_LTE = 5

comptime STANDARD_PATH_RAYLEIGH = 0
comptime STANDARD_PATH_LOS = 1

comptime STANDARD_DOPPLER_JAKES = 0
comptime STANDARD_DOPPLER_WIFI_BELL = 1

comptime _TWO_PI = 6.283185307179586476925286766559
comptime _LN_10_OVER_10 = 0.230258509299404568401799145468
comptime _SOS_RAYS = 24
comptime _FLOAT64_MIN_NORMAL = 2.2250738585072014e-308
comptime _SUBNORMAL_SCALE = 18014398509481984.0


def _is_finite_complex(value: Complex64) -> Bool:
    return isfinite(value.re) and isfinite(value.im)


def _decompose_float64(value: Float64) -> Tuple[Float64, Int32]:
    """Return a stable binary mantissa/exponent pair for finite Float64."""
    if value == 0.0:
        return (0.0, Int32(0))
    var scaled = value
    var exponent_adjustment = Int32(0)
    if abs(value) < _FLOAT64_MIN_NORMAL:
        # The pinned stdlib frexp mishandles Float64 subnormals.  Scaling by
        # 2**54 is exact and makes every nonzero subnormal normal first.
        scaled *= _SUBNORMAL_SCALE
        exponent_adjustment = -54
    var parts = frexp(scaled)
    return (
        parts[0],
        parts[1].cast[DType.int32]() + exponent_adjustment,
    )


def _reduce_scaled_cycles(
    mantissa: Float64, exponent: Int32
) -> Float64:
    """Reduce ``mantissa * 2**exponent`` modulo one without overflow."""
    if mantissa == 0.0:
        return 0.0
    var canonical = frexp(mantissa)
    var reduced = canonical[0]
    var remaining = exponent + canonical[1].cast[DType.int32]()
    if remaining < -1074:
        return -0.0 if reduced < 0.0 else 0.0
    if remaining <= 0:
        return remainder(ldexp(reduced, remaining), 1.0)
    while remaining > 512:
        reduced = remainder(ldexp(reduced, Int32(512)), 1.0)
        remaining -= 512
        if reduced == 0.0:
            return reduced
    return remainder(ldexp(reduced, remaining), 1.0)


def _reduced_product_cycles(
    first: Float64, second: Float64, third: Float64
) -> Float64:
    """Return a three-factor product modulo one in cycle units."""
    if first == 0.0 or second == 0.0 or third == 0.0:
        return 0.0
    var first_parts = _decompose_float64(first)
    var second_parts = _decompose_float64(second)
    var third_parts = _decompose_float64(third)
    var mantissa = first_parts[0] * second_parts[0] * third_parts[0]
    var exponent = (
        first_parts[1] + second_parts[1] + third_parts[1]
    )
    return _reduce_scaled_cycles(mantissa, exponent)


struct StandardChannelProfile(Movable):
    """One standardized SISO power-delay profile.

    ``delays`` contains normalized delay coordinates for TDL and nanoseconds
    for WLAN.  ``delay_scale_ns`` converts either representation to ns.
    ``powers_db`` are the unmodified standard-table powers.  Channel
    realization functions normalize their sum to unit mean power.
    """

    var name: String
    var family: Int
    var delays: List[Float64]
    var powers_db: List[Float64]
    var fading_kinds: List[Int]
    var delay_scale_ns: Float64
    var doppler_spectrum: Int
    var has_los: Bool
    var los_k_factor_db: Float64
    var los_doppler_ratio: Float64

    def __init__(
        out self,
        var name: String,
        family: Int,
        var delays: List[Float64],
        var powers_db: List[Float64],
        var fading_kinds: List[Int],
        delay_scale_ns: Float64,
        doppler_spectrum: Int,
        has_los: Bool,
        los_k_factor_db: Float64,
        los_doppler_ratio: Float64,
    ) raises:
        if len(delays) == 0 or len(delays) != len(powers_db):
            raise Error("standard profile arrays must be equal and non-empty")
        if (
            len(delays) != len(fading_kinds)
            or not isfinite(delay_scale_ns)
            or delay_scale_ns <= 0.0
        ):
            raise Error("invalid standard profile metadata")
        if (
            family != STANDARD_FAMILY_3GPP_TDL
            and family != STANDARD_FAMILY_WIFI_TGN
            and family != STANDARD_FAMILY_WIFI_TGAC
            and family != STANDARD_FAMILY_WIFI_TGAX
            and family != STANDARD_FAMILY_3GPP_LTE
        ):
            raise Error("unknown standard channel family")
        if (
            doppler_spectrum != STANDARD_DOPPLER_JAKES
            and doppler_spectrum != STANDARD_DOPPLER_WIFI_BELL
        ):
            raise Error("unknown standard Doppler spectrum")
        if not isfinite(los_k_factor_db) or los_k_factor_db < 0.0:
            raise Error("standard LOS K factor must be finite and non-negative")
        if (
            not isfinite(los_doppler_ratio)
            or abs(los_doppler_ratio) > 1.0
        ):
            raise Error("standard LOS Doppler ratio must be finite in [-1, 1]")
        for i in range(len(delays)):
            if not isfinite(delays[i]) or delays[i] < 0.0:
                raise Error(
                    "standard channel delays must be finite and non-negative"
                )
            if not isfinite(powers_db[i]):
                raise Error("standard channel powers must be finite")
            if (
                fading_kinds[i] != STANDARD_PATH_RAYLEIGH
                and fading_kinds[i] != STANDARD_PATH_LOS
            ):
                raise Error("unknown standard path fading kind")
        self.name = name^
        self.family = family
        self.delays = delays^
        self.powers_db = powers_db^
        self.fading_kinds = fading_kinds^
        self.delay_scale_ns = delay_scale_ns
        self.doppler_spectrum = doppler_spectrum
        self.has_los = has_los
        self.los_k_factor_db = los_k_factor_db
        self.los_doppler_ratio = los_doppler_ratio

    def validate(self) raises:
        """Revalidate all mutable metadata at a public profile boundary."""
        if len(self.delays) == 0 or len(self.delays) != len(self.powers_db):
            raise Error("standard profile arrays must be equal and non-empty")
        if (
            len(self.delays) != len(self.fading_kinds)
            or not isfinite(self.delay_scale_ns)
            or self.delay_scale_ns <= 0.0
        ):
            raise Error("invalid standard profile metadata")
        if (
            self.family != STANDARD_FAMILY_3GPP_TDL
            and self.family != STANDARD_FAMILY_WIFI_TGN
            and self.family != STANDARD_FAMILY_WIFI_TGAC
            and self.family != STANDARD_FAMILY_WIFI_TGAX
            and self.family != STANDARD_FAMILY_3GPP_LTE
        ):
            raise Error("unknown standard channel family")
        if (
            self.doppler_spectrum != STANDARD_DOPPLER_JAKES
            and self.doppler_spectrum != STANDARD_DOPPLER_WIFI_BELL
        ):
            raise Error("unknown standard Doppler spectrum")
        if not isfinite(self.los_k_factor_db) or self.los_k_factor_db < 0.0:
            raise Error("standard LOS K factor must be finite and non-negative")
        if (
            not isfinite(self.los_doppler_ratio)
            or abs(self.los_doppler_ratio) > 1.0
        ):
            raise Error("standard LOS Doppler ratio must be finite in [-1, 1]")
        for index in range(len(self.delays)):
            if not isfinite(self.delays[index]) or self.delays[index] < 0.0:
                raise Error(
                    "standard channel delays must be finite and non-negative"
                )
            if not isfinite(self.powers_db[index]):
                raise Error("standard channel powers must be finite")
            if (
                self.fading_kinds[index] != STANDARD_PATH_RAYLEIGH
                and self.fading_kinds[index] != STANDARD_PATH_LOS
            ):
                raise Error("unknown standard path fading kind")

    def path_count(self) raises -> Int:
        self.validate()
        return len(self.delays)

    def tap_count(self) raises -> Int:
        """Return standard taps, folding each LOS component into its tap.

        Distinct standardized taps can intentionally share the same delay
        (for example two TDL-E diffuse entries at 0.5440), so delay-value
        deduplication would be incorrect.
        """
        self.validate()
        var count = len(self.delays)
        for kind in self.fading_kinds:
            if kind == STANDARD_PATH_LOS:
                count -= 1
        return count

    def delay_ns(self, path: Int) raises -> Float64:
        self.validate()
        if path < 0 or path >= len(self.delays):
            raise Error("standard channel path index out of range")
        var result = self.delays[path] * self.delay_scale_ns
        if not isfinite(result):
            raise Error("standard scaled delay must remain finite")
        return result

    def maximum_delay_ns(self) raises -> Float64:
        self.validate()
        var maximum = 0.0
        for value in self.delays:
            var scaled = value * self.delay_scale_ns
            if not isfinite(scaled):
                raise Error("standard scaled delay must remain finite")
            maximum = max(maximum, scaled)
        return maximum

    def total_linear_power(self) raises -> Float64:
        self.validate()
        var total = 0.0
        for value in self.powers_db:
            var linear = _db_to_linear(value)
            if not isfinite(linear):
                raise Error("standard linear path power must remain finite")
            total += linear
            if not isfinite(total):
                raise Error("standard total linear power must remain finite")
        if total <= 0.0:
            raise Error("standard total linear power must be positive")
        return total

    def normalized_linear_powers(self) raises -> List[Float64]:
        self.validate()
        var maximum_db = self.powers_db[0]
        if not isfinite(maximum_db):
            raise Error("standard channel powers must be finite")
        for index in range(1, len(self.powers_db)):
            var value = self.powers_db[index]
            if not isfinite(value):
                raise Error("standard channel powers must be finite")
            maximum_db = max(maximum_db, value)

        var relative = List[Float64](capacity=len(self.powers_db))
        var total = 0.0
        for value in self.powers_db:
            var delta_db = value - maximum_db
            # With finite inputs and maximum_db >= value, a non-finite
            # difference can only represent a weight below the Float64 range.
            var linear = (
                _db_to_linear(delta_db) if isfinite(delta_db) else 0.0
            )
            relative.append(linear)
            total += linear
        if not isfinite(total) or total <= 0.0:
            raise Error("standard relative path power must be positive")

        var result = List[Float64](capacity=len(relative))
        for linear in relative:
            var normalized = linear / total
            if not isfinite(normalized):
                raise Error("standard normalized power must remain finite")
            result.append(normalized)
        return result^

    def rms_delay_spread_ns(self) raises -> Float64:
        self.validate()
        var powers = self.normalized_linear_powers()
        var mean = 0.0
        for i in range(len(powers)):
            mean += powers[i] * self.delays[i] * self.delay_scale_ns
            if not isfinite(mean):
                raise Error("standard mean delay must remain finite")
        var variance = 0.0
        for i in range(len(powers)):
            var delta = self.delays[i] * self.delay_scale_ns - mean
            variance += powers[i] * delta * delta
            if not isfinite(variance):
                raise Error("standard delay variance must remain finite")
        return sqrt(variance)


def _db_to_linear(value_db: Float64) -> Float64:
    return exp(_LN_10_OVER_10 * value_db)


def _rayleigh_kinds(count: Int) -> List[Int]:
    return List[Int](length=count, fill=STANDARD_PATH_RAYLEIGH)


def lte_profile(model: String) raises -> StandardChannelProfile:
    """Return an LTE EPA, EVA, or ETU profile from TS 36.101 Annex B.

    Delays are absolute nanoseconds.  ``realize_standard_channel_paths`` takes
    the selected maximum Doppler separately, covering the standard EPA5,
    EVA5/EVA70 and ETU70/ETU300 combinations without duplicating the PDP.
    """
    if model == "EPA":
        var delays: List[Float64] = [
            0.0, 30.0, 70.0, 90.0, 110.0, 190.0, 410.0,
        ]
        var powers: List[Float64] = [
            0.0, -1.0, -2.0, -3.0, -8.0, -17.2, -20.8,
        ]
        var kinds = _rayleigh_kinds(len(delays))
        return StandardChannelProfile(
            String("LTE-EPA"), STANDARD_FAMILY_3GPP_LTE, delays^, powers^,
            kinds^, 1.0, STANDARD_DOPPLER_JAKES, False, 0.0, 0.0,
        )
    if model == "EVA":
        var delays: List[Float64] = [
            0.0, 30.0, 150.0, 310.0, 370.0, 710.0, 1090.0,
            1730.0, 2510.0,
        ]
        var powers: List[Float64] = [
            0.0, -1.5, -1.4, -3.6, -0.6, -9.1, -7.0, -12.0,
            -16.9,
        ]
        var kinds = _rayleigh_kinds(len(delays))
        return StandardChannelProfile(
            String("LTE-EVA"), STANDARD_FAMILY_3GPP_LTE, delays^, powers^,
            kinds^, 1.0, STANDARD_DOPPLER_JAKES, False, 0.0, 0.0,
        )
    if model == "ETU":
        var delays: List[Float64] = [
            0.0, 50.0, 120.0, 200.0, 230.0, 500.0, 1600.0,
            2300.0, 5000.0,
        ]
        var powers: List[Float64] = [
            -1.0, -1.0, -1.0, 0.0, 0.0, 0.0, -3.0, -5.0, -7.0,
        ]
        var kinds = _rayleigh_kinds(len(delays))
        return StandardChannelProfile(
            String("LTE-ETU"), STANDARD_FAMILY_3GPP_LTE, delays^, powers^,
            kinds^, 1.0, STANDARD_DOPPLER_JAKES, False, 0.0, 0.0,
        )
    raise Error("LTE channel model must be EPA, EVA, or ETU")


def tdl_profile(
    model: String, *, desired_delay_spread_ns: Float64 = 100.0
) raises -> StandardChannelProfile:
    """Return a 3GPP TR 38.901 TDL-A/B/C/D/E profile.

    The requested delay spread is the scale in equation 7.7-1.  Raw
    ``profile.delays`` retain the tabulated reference coordinates.
    """
    if (
        not isfinite(desired_delay_spread_ns)
        or desired_delay_spread_ns <= 0.0
    ):
        raise Error("TDL delay spread must be finite and positive")
    if model == "A":
        var delays: List[Float64] = [
            0.0000, 0.3819, 0.4025, 0.5868, 0.4610, 0.5375,
            0.6708, 0.5750, 0.7618, 1.5375, 1.8978, 2.2242,
            2.1718, 2.4942, 2.5119, 3.0582, 4.0810, 4.4579,
            4.5695, 4.7966, 5.0066, 5.3043, 9.6586,
        ]
        var powers: List[Float64] = [
            -13.4, 0.0, -2.2, -4.0, -6.0, -8.2, -9.9, -10.5,
            -7.5, -15.9, -6.6, -16.7, -12.4, -15.2, -10.8,
            -11.3, -12.7, -16.2, -18.3, -18.9, -16.6, -19.9,
            -29.7,
        ]
        var kinds = _rayleigh_kinds(len(delays))
        return StandardChannelProfile(
            String("TDL-A"), STANDARD_FAMILY_3GPP_TDL, delays^, powers^,
            kinds^, desired_delay_spread_ns, STANDARD_DOPPLER_JAKES,
            False, 0.0, 0.0,
        )
    if model == "B":
        var delays: List[Float64] = [
            0.0000, 0.1072, 0.2155, 0.2095, 0.2870, 0.2986,
            0.3752, 0.5055, 0.3681, 0.3697, 0.5700, 0.5283,
            1.1021, 1.2756, 1.5474, 1.7842, 2.0169, 2.8294,
            3.0219, 3.6187, 4.1067, 4.2790, 4.7834,
        ]
        var powers: List[Float64] = [
            0.0, -2.2, -4.0, -3.2, -9.8, -1.2, -3.4, -5.2,
            -7.6, -3.0, -8.9, -9.0, -4.8, -5.7, -7.5, -1.9,
            -7.6, -12.2, -9.8, -11.4, -14.9, -9.2, -11.3,
        ]
        var kinds = _rayleigh_kinds(len(delays))
        return StandardChannelProfile(
            String("TDL-B"), STANDARD_FAMILY_3GPP_TDL, delays^, powers^,
            kinds^, desired_delay_spread_ns, STANDARD_DOPPLER_JAKES,
            False, 0.0, 0.0,
        )
    if model == "C":
        var delays: List[Float64] = [
            0.0000, 0.2099, 0.2219, 0.2329, 0.2176, 0.6366,
            0.6448, 0.6560, 0.6584, 0.7935, 0.8213, 0.9336,
            1.2285, 1.3083, 2.1704, 2.7105, 4.2589, 4.6003,
            5.4902, 5.6077, 6.3065, 6.6374, 7.0427, 8.6523,
        ]
        var powers: List[Float64] = [
            -4.4, -1.2, -3.5, -5.2, -2.5, 0.0, -2.2, -3.9,
            -7.4, -7.1, -10.7, -11.1, -5.1, -6.8, -8.7, -13.2,
            -13.9, -13.9, -15.8, -17.1, -16.0, -15.7, -21.6,
            -22.8,
        ]
        var kinds = _rayleigh_kinds(len(delays))
        return StandardChannelProfile(
            String("TDL-C"), STANDARD_FAMILY_3GPP_TDL, delays^, powers^,
            kinds^, desired_delay_spread_ns, STANDARD_DOPPLER_JAKES,
            False, 0.0, 0.0,
        )
    if model == "D":
        # Tap 1 has distinct specular and diffuse entries at zero delay.
        var delays: List[Float64] = [
            0.000, 0.000, 0.035, 0.612, 1.363, 1.405, 1.804,
            2.596, 1.775, 4.042, 7.937, 9.424, 9.708, 12.525,
        ]
        var powers: List[Float64] = [
            -0.2, -13.5, -18.8, -21.0, -22.8, -17.9, -20.1,
            -21.9, -22.9, -27.8, -23.6, -24.8, -30.0, -27.7,
        ]
        var kinds = _rayleigh_kinds(len(delays))
        kinds[0] = STANDARD_PATH_LOS
        return StandardChannelProfile(
            String("TDL-D"), STANDARD_FAMILY_3GPP_TDL, delays^, powers^,
            kinds^, desired_delay_spread_ns, STANDARD_DOPPLER_JAKES,
            True, 13.3, 0.7,
        )
    if model == "E":
        var delays: List[Float64] = [
            0.0000, 0.0000, 0.5133, 0.5440, 0.5630, 0.5440,
            0.7112, 1.9092, 1.9293, 1.9589, 2.6426, 3.7136,
            5.4524, 12.0034, 20.6519,
        ]
        var powers: List[Float64] = [
            -0.03, -22.03, -15.8, -18.1, -19.8, -22.9, -22.4,
            -18.6, -20.8, -22.6, -22.3, -25.6, -20.2, -29.8,
            -29.2,
        ]
        var kinds = _rayleigh_kinds(len(delays))
        kinds[0] = STANDARD_PATH_LOS
        return StandardChannelProfile(
            String("TDL-E"), STANDARD_FAMILY_3GPP_TDL, delays^, powers^,
            kinds^, desired_delay_spread_ns, STANDARD_DOPPLER_JAKES,
            True, 22.0, 0.7,
        )
    raise Error("TDL model must be A, B, C, D, or E")


def _wifi_profile_name(family: Int, model: String) raises -> String:
    if family == STANDARD_FAMILY_WIFI_TGN:
        if model == "A": return String("TGn-A")
        if model == "B": return String("TGn-B")
        if model == "C": return String("TGn-C")
        if model == "D": return String("TGn-D")
        if model == "E": return String("TGn-E")
        if model == "F": return String("TGn-F")
    elif family == STANDARD_FAMILY_WIFI_TGAC:
        if model == "A": return String("TGac-A")
        if model == "B": return String("TGac-B")
        if model == "C": return String("TGac-C")
        if model == "D": return String("TGac-D")
        if model == "E": return String("TGac-E")
        if model == "F": return String("TGac-F")
    elif family == STANDARD_FAMILY_WIFI_TGAX:
        if model == "A": return String("TGax-A")
        if model == "B": return String("TGax-B")
        if model == "C": return String("TGax-C")
        if model == "D": return String("TGax-D")
        if model == "E": return String("TGax-E")
        if model == "F": return String("TGax-F")
    raise Error("invalid WLAN profile family or model")


def _wifi_profile(
    family: Int, model: String, *, los: Bool
) raises -> StandardChannelProfile:
    var delays: List[Float64]
    var powers: List[Float64]
    var k_factor_db = 0.0
    if model == "A":
        delays = [0.0]
        powers = [0.0]
    elif model == "B":
        delays = [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0]
        powers = [0.0, -5.4, -2.5, -5.9, -9.2, -12.5, -15.6, -18.7, -21.8]
    elif model == "C":
        delays = [
            0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0,
            80.0, 90.0, 110.0, 140.0, 170.0, 200.0,
        ]
        powers = [
            0.0, -2.1, -4.3, -6.5, -8.6, -10.8, -4.4, -6.6,
            -8.7, -10.9, -13.7, -15.8, -18.0, -20.2,
        ]
    elif model == "D":
        delays = [
            0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0,
            80.0, 90.0, 110.0, 140.0, 170.0, 200.0, 240.0,
            290.0, 340.0, 390.0,
        ]
        powers = [
            0.0, -0.9, -1.7, -2.6, -3.5, -4.3, -5.2, -6.1,
            -6.9, -7.8, -4.7, -7.3, -9.9, -12.5, -13.7, -18.0,
            -22.4, -26.7,
        ]
        k_factor_db = 3.0
    elif model == "E":
        delays = [
            0.0, 10.0, 20.0, 30.0, 50.0, 80.0, 110.0, 140.0,
            180.0, 230.0, 280.0, 330.0, 380.0, 430.0, 490.0,
            560.0, 640.0, 730.0,
        ]
        powers = [
            -2.6, -3.0, -3.5, -3.9, 0.0, -1.3, -2.6, -3.9,
            -3.4, -5.6, -7.7, -9.9, -12.1, -14.3, -15.4, -18.4,
            -20.7, -24.6,
        ]
        k_factor_db = 6.0
    elif model == "F":
        delays = [
            0.0, 10.0, 20.0, 30.0, 50.0, 80.0, 110.0, 140.0,
            180.0, 230.0, 280.0, 330.0, 400.0, 490.0, 600.0,
            730.0, 880.0, 1050.0,
        ]
        powers = [
            -3.3, -3.6, -3.9, -4.2, 0.0, -0.9, -1.7, -2.6,
            -1.5, -3.0, -4.4, -5.9, -5.3, -7.9, -9.4, -13.2,
            -16.3, -21.2,
        ]
        k_factor_db = 6.0
    else:
        raise Error("WLAN channel model must be A through F")

    var kinds = _rayleigh_kinds(len(delays))
    if los:
        # 03/940r4 adds, rather than substitutes, the specular first-path
        # component.  Its power is K times the first diffuse-path power.
        delays.append(0.0)
        powers.append(powers[0] + k_factor_db)
        kinds.append(STANDARD_PATH_LOS)
    var name = _wifi_profile_name(family, model)
    return StandardChannelProfile(
        name^, family, delays^, powers^, kinds^, 1.0,
        STANDARD_DOPPLER_WIFI_BELL, los, k_factor_db, 0.0,
    )


def wifi_tgn_profile(
    model: String, *, los: Bool = False
) raises -> StandardChannelProfile:
    """Return an IEEE 802.11-03/940r4 indoor A--F profile."""
    return _wifi_profile(STANDARD_FAMILY_WIFI_TGN, model, los=los)


def _append_unique_time(mut times: List[Float64], value: Float64):
    for existing in times:
        if existing == value:
            return
    times.append(value)


def _append_tgac_cluster_times(
    mut times: List[Float64],
    delays: Span[Float64, ...],
    expansion_factor: Int,
):
    var spacing_ns = 10.0 / Float64(expansion_factor)
    for tap in range(len(delays) - 1):
        for offset in range(expansion_factor):
            _append_unique_time(
                times, delays[tap] + spacing_ns * Float64(offset)
            )
    _append_unique_time(times, delays[len(delays) - 1])


def _sort_times(mut times: List[Float64]):
    # The profile arrays are tiny; insertion sort keeps this reference free
    # from an algorithm-backend dependency.
    for i in range(1, len(times)):
        var value = times[i]
        var j = i
        while j > 0 and times[j - 1] > value:
            times[j] = times[j - 1]
            j -= 1
        times[j] = value


def _cluster_linear_power_at(
    time_ns: Float64,
    delays: Span[Float64, ...],
    powers_db: Span[Float64, ...],
) -> Float64:
    if time_ns < delays[0] or time_ns > delays[len(delays) - 1]:
        return 0.0
    if time_ns == delays[len(delays) - 1]:
        return _db_to_linear(powers_db[len(powers_db) - 1])
    for tap in range(len(delays) - 1):
        if time_ns >= delays[tap] and time_ns <= delays[tap + 1]:
            var fraction = (
                (time_ns - delays[tap])
                / (delays[tap + 1] - delays[tap])
            )
            var interpolated_db = (
                powers_db[tap]
                + fraction * (powers_db[tap + 1] - powers_db[tap])
            )
            return _db_to_linear(interpolated_db)
    return 0.0


def _accumulate_tgac_cluster(
    mut total_powers: List[Float64],
    times: Span[Float64, ...],
    delays: Span[Float64, ...],
    powers_db: Span[Float64, ...],
):
    for i in range(len(times)):
        total_powers[i] += _cluster_linear_power_at(
            times[i], delays, powers_db
        )


def _wifi_k_factor_db(model: String) raises -> Float64:
    if model == "A" or model == "B" or model == "C":
        return 0.0
    if model == "D":
        return 3.0
    if model == "E" or model == "F":
        return 6.0
    raise Error("WLAN channel model must be A through F")


def _finish_tgac_profile(
    family: Int,
    model: String,
    los: Bool,
    var times: List[Float64],
    var total_powers: List[Float64],
) raises -> StandardChannelProfile:
    var powers_db = List[Float64](capacity=len(total_powers))
    for power in total_powers:
        powers_db.append(log(power) / _LN_10_OVER_10)
    var kinds = _rayleigh_kinds(len(times))
    var k_factor_db = _wifi_k_factor_db(model)
    if los:
        times.append(0.0)
        powers_db.append(powers_db[0] + k_factor_db)
        kinds.append(STANDARD_PATH_LOS)
    var name = _wifi_profile_name(family, model)
    return StandardChannelProfile(
        name^, family, times^, powers_db^, kinds^, 1.0,
        STANDARD_DOPPLER_WIFI_BELL, los, k_factor_db, 0.0,
    )


def _tgac_refined_profile(
    family: Int,
    model: String,
    expansion_factor: Int,
    *,
    los: Bool,
) raises -> StandardChannelProfile:
    """Apply 09/0308r12 cluster-by-cluster PDP interpolation."""
    if expansion_factor <= 1 or model == "A":
        return _wifi_profile(family, model, los=los)
    var times = List[Float64]()

    if model == "B":
        var c1d: List[Float64] = [0.0, 10.0, 20.0, 30.0, 40.0]
        var c1p: List[Float64] = [0.0, -5.4, -10.8, -16.2, -21.7]
        var c2d: List[Float64] = [20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0]
        var c2p: List[Float64] = [-3.2, -6.3, -9.4, -12.5, -15.6, -18.7, -21.8]
        _append_tgac_cluster_times(times, Span(c1d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c2d), expansion_factor)
        _sort_times(times)
        var totals = List[Float64](length=len(times), fill=0.0)
        _accumulate_tgac_cluster(totals, Span(times), Span(c1d), Span(c1p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c2d), Span(c2p))
        return _finish_tgac_profile(family, model, los, times^, totals^)

    if model == "C":
        var c1d: List[Float64] = [
            0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0,
            80.0, 90.0,
        ]
        var c1p: List[Float64] = [
            0.0, -2.1, -4.3, -6.5, -8.6, -10.8, -13.0, -15.2,
            -17.3, -19.5,
        ]
        var c2d: List[Float64] = [60.0, 70.0, 80.0, 90.0, 110.0, 140.0, 170.0, 200.0]
        var c2p: List[Float64] = [-5.0, -7.2, -9.3, -11.5, -13.7, -15.8, -18.0, -20.2]
        _append_tgac_cluster_times(times, Span(c1d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c2d), expansion_factor)
        _sort_times(times)
        var totals = List[Float64](length=len(times), fill=0.0)
        _accumulate_tgac_cluster(totals, Span(times), Span(c1d), Span(c1p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c2d), Span(c2p))
        return _finish_tgac_profile(family, model, los, times^, totals^)

    if model == "D":
        var c1d: List[Float64] = [
            0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0,
            80.0, 90.0, 110.0, 140.0, 170.0, 200.0, 240.0, 290.0,
        ]
        var c1p: List[Float64] = [
            0.0, -0.9, -1.7, -2.6, -3.5, -4.3, -5.2, -6.1,
            -6.9, -7.8, -9.0, -11.1, -13.7, -16.3, -19.3, -23.2,
        ]
        var c2d: List[Float64] = [110.0, 140.0, 170.0, 200.0, 240.0, 290.0, 340.0]
        var c2p: List[Float64] = [-6.6, -9.5, -12.1, -14.7, -17.4, -21.9, -25.5]
        var c3d: List[Float64] = [240.0, 290.0, 340.0, 390.0]
        var c3p: List[Float64] = [-18.8, -23.2, -25.2, -26.7]
        _append_tgac_cluster_times(times, Span(c1d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c2d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c3d), expansion_factor)
        _sort_times(times)
        var totals = List[Float64](length=len(times), fill=0.0)
        _accumulate_tgac_cluster(totals, Span(times), Span(c1d), Span(c1p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c2d), Span(c2p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c3d), Span(c3p))
        return _finish_tgac_profile(family, model, los, times^, totals^)

    if model == "E":
        var c1d: List[Float64] = [
            0.0, 10.0, 20.0, 30.0, 50.0, 80.0, 110.0, 140.0,
            180.0, 230.0, 280.0, 330.0, 380.0, 430.0, 490.0,
        ]
        var c1p: List[Float64] = [
            -2.6, -3.0, -3.5, -3.9, -4.5, -5.6, -6.9, -8.2,
            -9.8, -11.7, -13.9, -16.1, -18.3, -20.5, -22.9,
        ]
        var c2d: List[Float64] = [
            50.0, 80.0, 110.0, 140.0, 180.0, 230.0, 280.0, 330.0,
            380.0, 430.0, 490.0, 560.0,
        ]
        var c2p: List[Float64] = [
            -1.8, -3.2, -4.5, -5.8, -7.1, -9.9, -10.3, -14.3,
            -14.7, -18.7, -19.9, -22.4,
        ]
        var c3d: List[Float64] = [180.0, 230.0, 280.0, 330.0, 380.0, 430.0, 490.0]
        var c3p: List[Float64] = [-7.9, -9.6, -14.2, -13.8, -18.6, -18.1, -22.8]
        var c4d: List[Float64] = [490.0, 560.0, 640.0, 730.0]
        var c4p: List[Float64] = [-20.6, -20.5, -20.7, -24.6]
        _append_tgac_cluster_times(times, Span(c1d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c2d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c3d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c4d), expansion_factor)
        _sort_times(times)
        var totals = List[Float64](length=len(times), fill=0.0)
        _accumulate_tgac_cluster(totals, Span(times), Span(c1d), Span(c1p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c2d), Span(c2p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c3d), Span(c3p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c4d), Span(c4p))
        return _finish_tgac_profile(family, model, los, times^, totals^)

    if model == "F":
        var c1d: List[Float64] = [
            0.0, 10.0, 20.0, 30.0, 50.0, 80.0, 110.0, 140.0,
            180.0, 230.0, 280.0, 330.0, 400.0, 490.0, 600.0,
        ]
        var c1p: List[Float64] = [
            -3.3, -3.6, -3.9, -4.2, -4.6, -5.3, -6.2, -7.1,
            -8.2, -9.5, -11.0, -12.5, -14.3, -16.7, -19.9,
        ]
        var c2d: List[Float64] = [
            50.0, 80.0, 110.0, 140.0, 180.0, 230.0, 280.0, 330.0,
            400.0, 490.0, 600.0, 730.0,
        ]
        var c2p: List[Float64] = [
            -1.8, -2.8, -3.5, -4.4, -5.3, -7.4, -7.0, -10.3,
            -10.4, -13.8, -15.7, -19.9,
        ]
        var c3d: List[Float64] = [180.0, 230.0, 280.0, 330.0, 400.0, 490.0, 600.0]
        var c3p: List[Float64] = [-5.7, -6.7, -10.4, -9.6, -14.1, -12.7, -18.5]
        var c4d: List[Float64] = [400.0, 490.0, 600.0]
        var c4p: List[Float64] = [-8.8, -13.3, -18.7]
        var c5d: List[Float64] = [600.0, 730.0]
        var c5p: List[Float64] = [-12.9, -14.2]
        var c6d: List[Float64] = [880.0, 1050.0]
        var c6p: List[Float64] = [-16.3, -21.2]
        _append_tgac_cluster_times(times, Span(c1d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c2d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c3d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c4d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c5d), expansion_factor)
        _append_tgac_cluster_times(times, Span(c6d), expansion_factor)
        _sort_times(times)
        var totals = List[Float64](length=len(times), fill=0.0)
        _accumulate_tgac_cluster(totals, Span(times), Span(c1d), Span(c1p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c2d), Span(c2p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c3d), Span(c3p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c4d), Span(c4p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c5d), Span(c5p))
        _accumulate_tgac_cluster(totals, Span(times), Span(c6d), Span(c6p))
        return _finish_tgac_profile(family, model, los, times^, totals^)

    raise Error("WLAN channel model must be A through F")


def _tgac_expansion_factor(bandwidth_mhz: Int) raises -> Int:
    if bandwidth_mhz <= 0 or bandwidth_mhz > 1280:
        raise Error("TGac/TGax model bandwidth must be in 1..1280 MHz")
    if bandwidth_mhz <= 40: return 1
    if bandwidth_mhz <= 80: return 2
    if bandwidth_mhz <= 160: return 4
    if bandwidth_mhz <= 320: return 8
    if bandwidth_mhz <= 640: return 16
    return 32


def wifi_tgac_profile(
    model: String, *, bandwidth_mhz: Int = 20, los: Bool = False
) raises -> StandardChannelProfile:
    """Return the TGac A--F reference profile at its tabulated tap spacing."""
    return _tgac_refined_profile(
        STANDARD_FAMILY_WIFI_TGAC, model,
        _tgac_expansion_factor(bandwidth_mhz), los=los,
    )


def wifi_tgax_profile(
    model: String, *, bandwidth_mhz: Int = 20, los: Bool = False
) raises -> StandardChannelProfile:
    """Return the A--F indoor profile adopted by 802.11-14/0882r4."""
    return _tgac_refined_profile(
        STANDARD_FAMILY_WIFI_TGAX, model,
        _tgac_expansion_factor(bandwidth_mhz), los=los,
    )


def _uniform(mut state: UInt64) -> Float64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return (Float64(state >> 11) + 0.5) / 9007199254740992.0


def _complex_gaussian(mut state: UInt64) -> Complex64:
    # Box-Muller scaling gives E[re^2 + im^2] = 1.
    var radius = sqrt(-log(_uniform(state)))
    var phase = _TWO_PI * _uniform(state)
    return Complex64(radius * cos(phase), radius * sin(phase))


def _path_seed(seed: UInt64, path: Int) -> UInt64:
    var value = seed ^ (UInt64(path + 1) * UInt64(0x9E3779B97F4A7C15))
    value = (value ^ (value >> 30)) * UInt64(0xBF58476D1CE4E5B9)
    value = (value ^ (value >> 27)) * UInt64(0x94D049BB133111EB)
    return value ^ (value >> 31)


def _diffuse_sos(
    seed: UInt64,
    path: Int,
    time_seconds: Float64,
    maximum_doppler_hz: Float64,
    spectrum: Int,
) -> Complex64:
    var state = _path_seed(seed, path)
    var result = Complex64(0.0, 0.0)
    var weight_energy = 0.0
    for _ in range(_SOS_RAYS):
        var frequency_ratio: Float64
        var weight = 1.0
        if spectrum == STANDARD_DOPPLER_JAKES:
            frequency_ratio = cos(_TWO_PI * _uniform(state))
        else:
            var ratio = 10.0 * (_uniform(state) - 0.5)
            frequency_ratio = ratio
            weight = sqrt(1.0 / (1.0 + 9.0 * ratio * ratio))
        var phase = _TWO_PI * _uniform(state)
        var cycles = _reduced_product_cycles(
            maximum_doppler_hz, frequency_ratio, time_seconds
        )
        var angle = remainder(phase + _TWO_PI * cycles, _TWO_PI)
        result = result + Complex64(weight * cos(angle), weight * sin(angle))
        weight_energy += weight * weight
    var scale = 1.0 / sqrt(weight_energy)
    return Complex64(scale * result.re, scale * result.im)


def _path_coefficient(
    profile: StandardChannelProfile,
    path: Int,
    normalized_power: Float64,
    time_seconds: Float64,
    maximum_doppler_hz: Float64,
    seed: UInt64,
) -> Complex64:
    var amplitude = sqrt(normalized_power)
    if profile.fading_kinds[path] == STANDARD_PATH_LOS:
        var state = _path_seed(seed, path)
        var initial_phase = _TWO_PI * _uniform(state)
        var cycles = _reduced_product_cycles(
            profile.los_doppler_ratio,
            maximum_doppler_hz,
            time_seconds,
        )
        var phase = remainder(initial_phase + _TWO_PI * cycles, _TWO_PI)
        return Complex64(amplitude * cos(phase), amplitude * sin(phase))
    var diffuse: Complex64
    if maximum_doppler_hz == 0.0:
        var state = _path_seed(seed, path)
        diffuse = _complex_gaussian(state)
    else:
        diffuse = _diffuse_sos(
            seed, path, time_seconds, maximum_doppler_hz,
            profile.doppler_spectrum,
        )
    return Complex64(amplitude * diffuse.re, amplitude * diffuse.im)


def realize_standard_channel_paths(
    profile: StandardChannelProfile,
    *,
    time_seconds: Float64 = 0.0,
    maximum_doppler_hz: Float64 = 0.0,
    seed: UInt64,
) raises -> List[Complex64]:
    """Realize one coefficient per profile path at an absolute time."""
    profile.validate()
    if not isfinite(time_seconds):
        raise Error("channel realization time must be finite")
    if not isfinite(maximum_doppler_hz) or maximum_doppler_hz < 0.0:
        raise Error("maximum Doppler frequency must be finite and non-negative")
    var powers = profile.normalized_linear_powers()
    var result = List[Complex64](capacity=profile.path_count())
    for path in range(profile.path_count()):
        var coefficient = _path_coefficient(
            profile, path, powers[path], time_seconds,
            maximum_doppler_hz, seed,
        )
        if not _is_finite_complex(coefficient):
            raise Error("standard channel coefficient must remain finite")
        result.append(coefficient)
    return result^


def standard_channel_impulse_response(
    profile: StandardChannelProfile,
    sample_rate_hz: Float64,
    *,
    time_seconds: Float64 = 0.0,
    maximum_doppler_hz: Float64 = 0.0,
    seed: UInt64,
) raises -> List[Complex64]:
    """Sample a unit-mean-power channel impulse response.

    Non-integer path delays are deposited into the two adjacent samples using
    linear interpolation.  This is deliberately transparent and is suitable
    as a differential oracle for a higher-order fractional-delay backend.
    """
    profile.validate()
    if not isfinite(sample_rate_hz) or sample_rate_hz <= 0.0:
        raise Error("sample rate must be finite and positive")
    if not isfinite(time_seconds):
        raise Error("channel impulse-response time must be finite")
    if not isfinite(maximum_doppler_hz) or maximum_doppler_hz < 0.0:
        raise Error("maximum Doppler frequency must be finite and non-negative")
    var maximum_samples = profile.maximum_delay_ns() * sample_rate_hz * 1.0e-9
    if (
        not isfinite(maximum_samples)
        or maximum_samples > Float64(Int.MAX - 1)
    ):
        raise Error("standard impulse-response length overflows Int")
    var result = List[Complex64](
        length=Int(ceil(maximum_samples)) + 1, fill=Complex64(0.0, 0.0)
    )
    var coefficients = realize_standard_channel_paths(
        profile, time_seconds=time_seconds,
        maximum_doppler_hz=maximum_doppler_hz, seed=seed,
    )
    for path in range(profile.path_count()):
        var position = profile.delay_ns(path) * sample_rate_hz * 1.0e-9
        var left = Int(position)
        var fraction = position - Float64(left)
        var first_weight = 1.0 - fraction
        result[left] = result[left] + Complex64(
            first_weight * coefficients[path].re,
            first_weight * coefficients[path].im,
        )
        if not _is_finite_complex(result[left]):
            raise Error("standard impulse-response accumulation overflowed")
        if fraction > 0.0:
            result[left + 1] = result[left + 1] + Complex64(
                fraction * coefficients[path].re,
                fraction * coefficients[path].im,
            )
            if not _is_finite_complex(result[left + 1]):
                raise Error("standard impulse-response accumulation overflowed")
    return result^


def _fractional_input_sample(
    samples: Span[Complex64, ...], position: Float64
) raises -> Complex64:
    if not isfinite(position):
        raise Error("fractional input position must be finite")
    # Int truncates toward zero; adjust it to mathematical floor below zero.
    var left = Int(position)
    if position < Float64(left):
        left -= 1
    var fraction = position - Float64(left)
    var result = Complex64(0.0, 0.0)
    if left >= 0 and left < len(samples):
        result = result + Complex64(
            (1.0 - fraction) * samples[left].re,
            (1.0 - fraction) * samples[left].im,
        )
    var right = left + 1
    if right >= 0 and right < len(samples):
        result = result + Complex64(
            fraction * samples[right].re,
            fraction * samples[right].im,
        )
    if not _is_finite_complex(result):
        raise Error("fractional-delay interpolation must remain finite")
    return result


def apply_standard_channel(
    samples: Span[Complex64, ...],
    profile: StandardChannelProfile,
    sample_rate_hz: Float64,
    *,
    maximum_doppler_hz: Float64 = 0.0,
    start_time_seconds: Float64 = 0.0,
    seed: UInt64,
) raises -> List[Complex64]:
    """Apply a standardized full-length, possibly time-varying SISO channel.

    Each output sample evaluates ``x(n-delay)`` with linear fractional-delay
    interpolation.  A zero Doppler value gives block fading.  A positive
    value evaluates the deterministic seeded Doppler process at every output
    sample, so consecutive calls can continue time through
    ``start_time_seconds``.
    """
    profile.validate()
    if not isfinite(sample_rate_hz) or sample_rate_hz <= 0.0:
        raise Error("sample rate must be finite and positive")
    if not isfinite(maximum_doppler_hz) or maximum_doppler_hz < 0.0:
        raise Error("maximum Doppler frequency must be finite and non-negative")
    if not isfinite(start_time_seconds):
        raise Error("standard channel start time must be finite")
    for sample_index in range(len(samples)):
        if (
            not isfinite(samples[sample_index].re)
            or not isfinite(samples[sample_index].im)
        ):
            raise Error("standard channel input samples must be finite")
    if len(samples) == 0:
        return List[Complex64]()
    var maximum_samples = profile.maximum_delay_ns() * sample_rate_hz * 1.0e-9
    if (
        not isfinite(maximum_samples)
        or maximum_samples > Float64(Int.MAX)
    ):
        raise Error("standard channel delay length overflows Int")
    var delay_samples = Int(ceil(maximum_samples))
    if len(samples) > Int.MAX - delay_samples:
        raise Error("standard channel output length overflows Int")
    var output_length = len(samples) + delay_samples
    var result = List[Complex64](
        length=output_length, fill=Complex64(0.0, 0.0)
    )
    var powers = profile.normalized_linear_powers()
    for n in range(output_length):
        var time_seconds = start_time_seconds + Float64(n) / sample_rate_hz
        if not isfinite(time_seconds):
            raise Error("standard channel sample time must remain finite")
        var output = Complex64(0.0, 0.0)
        for path in range(profile.path_count()):
            var delay_samples = profile.delay_ns(path) * sample_rate_hz * 1.0e-9
            var input = _fractional_input_sample(
                samples, Float64(n) - delay_samples
            )
            var coefficient = _path_coefficient(
                profile, path, powers[path], time_seconds,
                maximum_doppler_hz, seed,
            )
            output = output + coefficient * input
            if not _is_finite_complex(output):
                raise Error("standard channel accumulation must remain finite")
        result[n] = output
    return result^
