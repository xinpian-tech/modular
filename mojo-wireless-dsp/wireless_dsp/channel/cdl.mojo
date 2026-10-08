"""Non-normative 3GPP TR 38.901 clustered-delay-line MIMO reference.

The CDL-A through CDL-E tables are from 3GPP TR 38.901 V18.1.0,
Tables 7.7.1-1 through 7.7.1-5.  Clause 7.7.1 supplies the twenty fixed ray
offsets, random angle coupling, per-ray cross-polarization ratio (XPR), and
the initial-phase procedure.  Clause 7.5 supplies far-field array steering
and Doppler evolution.

This is deliberately a scalar, inspectable reference.  Array coordinates are
expressed in wavelengths and may describe independent Tx/Rx ULA or UPA
geometries.  The polarization model is an isotropic theta/phi element with a
configurable linear slant.  Arbitrary calibrated element patterns and the
optional near-field model of clause 7.6.13 are outside this reference's
boundary; the standard far-field phase, four seeded polarization phases, and
tabulated XPR remain explicit.

TR 38.901 is reference provenance, not a frozen normative TS.  This module is
therefore excluded from ratified protocol completion and makes no conformance
or production-standard claim.
"""

from std.math import cos, exp, frexp, isfinite, ldexp, remainder, sin, sqrt
from wireless_dsp.core import Complex64


comptime CDL_PATH_DIFFUSE = 0
comptime CDL_PATH_LOS = 1
comptime CDL_RAYS_PER_CLUSTER = 20

# This scalar CPU reference allocates three Float64 coordinate arrays.  Keep
# the public builders total on adversarial dimensions without presenting this
# implementation capacity as a 3GPP model limit.  65,536 elements is far above
# the largest arrays exercised by the documented reference examples and
# benchmarks while bounding one coordinate object to roughly 1.5 MiB.
comptime _CDL_CPU_REFERENCE_MAX_ARRAY_ELEMENTS = 65_536

comptime _TWO_PI = 6.283185307179586476925286766559
comptime _PI = 3.1415926535897932384626433832795
comptime _DEG_TO_RAD = _PI / 180.0
comptime _LN_10_OVER_10 = 0.230258509299404568401799145468
comptime _LIGHT_SPEED_MPS = 299792458.0
comptime _FLOAT64_MIN_NORMAL = 2.2250738585072014e-308
comptime _SUBNORMAL_SCALE = 18014398509481984.0


def _is_finite_complex(value: Complex64) -> Bool:
    return isfinite(value.re) and isfinite(value.im)


def _compensated_add(
    accumulator: Float64, correction: Float64, value: Float64
) -> Tuple[Float64, Float64]:
    """Return a Neumaier-compensated update for a finite scalar sum."""
    var updated = accumulator + value
    var rounding_error = (
        (accumulator - updated) + value
        if abs(accumulator) >= abs(value)
        else (value - updated) + accumulator
    )
    return (updated, correction + rounding_error)


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
    first: Float64, second: Float64
) -> Float64:
    """Return a two-factor product modulo one in cycle units."""
    if first == 0.0 or second == 0.0:
        return 0.0
    var first_parts = _decompose_float64(first)
    var second_parts = _decompose_float64(second)
    return _reduce_scaled_cycles(
        first_parts[0] * second_parts[0],
        first_parts[1] + second_parts[1],
    )


def _reduced_product_cycles(
    first: Float64, second: Float64, third: Float64
) -> Float64:
    """Return a three-factor product modulo one in cycle units."""
    if first == 0.0 or second == 0.0 or third == 0.0:
        return 0.0
    var first_parts = _decompose_float64(first)
    var second_parts = _decompose_float64(second)
    var third_parts = _decompose_float64(third)
    return _reduce_scaled_cycles(
        first_parts[0] * second_parts[0] * third_parts[0],
        first_parts[1] + second_parts[1] + third_parts[1],
    )


def _reduced_product_cycles(
    first: Float64,
    second: Float64,
    third: Float64,
    fourth: Float64,
    fifth: Float64,
) -> Float64:
    """Return a five-factor product modulo one in cycle units."""
    if (
        first == 0.0
        or second == 0.0
        or third == 0.0
        or fourth == 0.0
        or fifth == 0.0
    ):
        return 0.0
    var first_parts = _decompose_float64(first)
    var second_parts = _decompose_float64(second)
    var third_parts = _decompose_float64(third)
    var fourth_parts = _decompose_float64(fourth)
    var fifth_parts = _decompose_float64(fifth)
    return _reduce_scaled_cycles(
        first_parts[0]
        * second_parts[0]
        * third_parts[0]
        * fourth_parts[0]
        * fifth_parts[0],
        first_parts[1]
        + second_parts[1]
        + third_parts[1]
        + fourth_parts[1]
        + fifth_parts[1],
    )


def _checked_positive_product(
    lhs: Int, rhs: Int, label: StringSlice
) raises -> Int:
    if lhs <= 0 or rhs <= 0:
        raise Error(String(label) + " dimensions must be positive")
    if lhs > Int.MAX // rhs:
        raise Error(String(label) + " dimensions overflow Int")
    return lhs * rhs


struct CDLProfile(Movable):
    """One normative CDL table with component and cluster identities.

    CDL-D/E list a specular LOS component and a diffuse component for cluster
    one.  Consequently ``component_count()`` is one greater than
    ``cluster_count`` for those profiles.  Raw delays are normalized and are
    scaled by ``delay_scale_ns`` when a channel is realized.
    """

    var name: String
    var delays: List[Float64]
    var powers_db: List[Float64]
    var aod_deg: List[Float64]
    var aoa_deg: List[Float64]
    var zod_deg: List[Float64]
    var zoa_deg: List[Float64]
    var cluster_indices: List[Int]
    var path_kinds: List[Int]
    var cluster_count: Int
    var delay_scale_ns: Float64
    var azimuth_departure_spread_deg: Float64
    var azimuth_arrival_spread_deg: Float64
    var zenith_departure_spread_deg: Float64
    var zenith_arrival_spread_deg: Float64
    var xpr_db: Float64
    var has_los: Bool
    var los_k_factor_db: Float64

    def __init__(
        out self,
        var name: String,
        var delays: List[Float64],
        var powers_db: List[Float64],
        var aod_deg: List[Float64],
        var aoa_deg: List[Float64],
        var zod_deg: List[Float64],
        var zoa_deg: List[Float64],
        var cluster_indices: List[Int],
        var path_kinds: List[Int],
        cluster_count: Int,
        delay_scale_ns: Float64,
        azimuth_departure_spread_deg: Float64,
        azimuth_arrival_spread_deg: Float64,
        zenith_departure_spread_deg: Float64,
        zenith_arrival_spread_deg: Float64,
        xpr_db: Float64,
        has_los: Bool,
        los_k_factor_db: Float64,
    ) raises:
        var count = len(delays)
        if count == 0 or len(powers_db) != count:
            raise Error("CDL table arrays must be equal and non-empty")
        if (
            len(aod_deg) != count
            or len(aoa_deg) != count
            or len(zod_deg) != count
            or len(zoa_deg) != count
            or len(cluster_indices) != count
            or len(path_kinds) != count
        ):
            raise Error("CDL angle and metadata arrays must match")
        if (
            cluster_count <= 0
            or not isfinite(delay_scale_ns)
            or delay_scale_ns <= 0.0
        ):
            raise Error("CDL cluster count and delay spread must be positive")
        if (
            not isfinite(azimuth_departure_spread_deg)
            or azimuth_departure_spread_deg < 0.0
            or not isfinite(azimuth_arrival_spread_deg)
            or azimuth_arrival_spread_deg < 0.0
            or not isfinite(zenith_departure_spread_deg)
            or zenith_departure_spread_deg < 0.0
            or not isfinite(zenith_arrival_spread_deg)
            or zenith_arrival_spread_deg < 0.0
        ):
            raise Error("CDL angular spreads must be finite and non-negative")
        if not isfinite(xpr_db) or xpr_db < 0.0:
            raise Error("CDL XPR must be finite and non-negative")
        if not isfinite(los_k_factor_db) or los_k_factor_db < 0.0:
            raise Error("CDL LOS K factor must be finite and non-negative")
        for component in range(count):
            if not isfinite(delays[component]) or delays[component] < 0.0:
                raise Error("CDL delays must be finite and non-negative")
            if (
                not isfinite(powers_db[component])
                or not isfinite(aod_deg[component])
                or not isfinite(aoa_deg[component])
                or not isfinite(zod_deg[component])
                or not isfinite(zoa_deg[component])
            ):
                raise Error("CDL powers and angles must be finite")
            if (
                cluster_indices[component] < 0
                or cluster_indices[component] >= cluster_count
            ):
                raise Error("CDL component has an invalid cluster index")
            if (
                path_kinds[component] != CDL_PATH_DIFFUSE
                and path_kinds[component] != CDL_PATH_LOS
            ):
                raise Error("CDL component has an invalid path kind")
        self.name = name^
        self.delays = delays^
        self.powers_db = powers_db^
        self.aod_deg = aod_deg^
        self.aoa_deg = aoa_deg^
        self.zod_deg = zod_deg^
        self.zoa_deg = zoa_deg^
        self.cluster_indices = cluster_indices^
        self.path_kinds = path_kinds^
        self.cluster_count = cluster_count
        self.delay_scale_ns = delay_scale_ns
        self.azimuth_departure_spread_deg = azimuth_departure_spread_deg
        self.azimuth_arrival_spread_deg = azimuth_arrival_spread_deg
        self.zenith_departure_spread_deg = zenith_departure_spread_deg
        self.zenith_arrival_spread_deg = zenith_arrival_spread_deg
        self.xpr_db = xpr_db
        self.has_los = has_los
        self.los_k_factor_db = los_k_factor_db

    def component_count(self) -> Int:
        return len(self.delays)

    def delay_ns(self, component: Int) raises -> Float64:
        if component < 0 or component >= self.component_count():
            raise Error("CDL component index out of range")
        var result = self.delays[component] * self.delay_scale_ns
        if not isfinite(result):
            raise Error("CDL scaled delay must remain finite")
        return result

    def maximum_delay_ns(self) raises -> Float64:
        var result = 0.0
        for delay in self.delays:
            var scaled = delay * self.delay_scale_ns
            if not isfinite(scaled):
                raise Error("CDL scaled delay must remain finite")
            result = max(result, scaled)
        return result

    def total_linear_power(self) raises -> Float64:
        var result = 0.0
        for power_db in self.powers_db:
            var linear = _db_to_linear(power_db)
            if not isfinite(linear):
                raise Error("CDL linear path power must remain finite")
            result += linear
            if not isfinite(result):
                raise Error("CDL total linear power must remain finite")
        if result <= 0.0:
            raise Error("CDL total linear power must be positive")
        return result

    def normalized_linear_powers(self) raises -> List[Float64]:
        if self.component_count() == 0:
            raise Error("CDL profile requires at least one component power")
        var maximum_db = self.powers_db[0]
        if not isfinite(maximum_db):
            raise Error("CDL component powers must be finite")
        for component in range(1, self.component_count()):
            var power_db = self.powers_db[component]
            if not isfinite(power_db):
                raise Error("CDL component powers must be finite")
            maximum_db = max(maximum_db, power_db)

        var relative = List[Float64](capacity=self.component_count())
        var total = 0.0
        for power_db in self.powers_db:
            var delta_db = power_db - maximum_db
            # With finite inputs and maximum_db >= power_db, a non-finite
            # difference can only represent a weight below the Float64 range.
            var linear = (
                _db_to_linear(delta_db) if isfinite(delta_db) else 0.0
            )
            relative.append(linear)
            total += linear
        if not isfinite(total) or total <= 0.0:
            raise Error("CDL relative component power must be positive")

        var result = List[Float64](capacity=len(relative))
        for linear in relative:
            var normalized = linear / total
            if not isfinite(normalized):
                raise Error("CDL normalized path power must remain finite")
            result.append(normalized)
        return result^

    def xpr_linear(self) raises -> Float64:
        var result = _db_to_linear(self.xpr_db)
        if not isfinite(result) or result <= 0.0:
            raise Error("CDL linear XPR must remain finite and positive")
        return result


struct CDLArray(Movable):
    """Far-field element positions measured in carrier wavelengths."""

    var x_wavelengths: List[Float64]
    var y_wavelengths: List[Float64]
    var z_wavelengths: List[Float64]

    def __init__(
        out self,
        var x_wavelengths: List[Float64],
        var y_wavelengths: List[Float64],
        var z_wavelengths: List[Float64],
    ) raises:
        if len(x_wavelengths) == 0:
            raise Error("CDL array must contain at least one element")
        if (
            len(y_wavelengths) != len(x_wavelengths)
            or len(z_wavelengths) != len(x_wavelengths)
        ):
            raise Error("CDL array coordinate vectors must match")
        for element in range(len(x_wavelengths)):
            if (
                not isfinite(x_wavelengths[element])
                or not isfinite(y_wavelengths[element])
                or not isfinite(z_wavelengths[element])
            ):
                raise Error("CDL array coordinates must be finite")
        self.x_wavelengths = x_wavelengths^
        self.y_wavelengths = y_wavelengths^
        self.z_wavelengths = z_wavelengths^

    def element_count(self) -> Int:
        return len(self.x_wavelengths)


struct CDLRayAngles(Movable):
    """Coupled departure/arrival angles for one CDL component."""

    var aod_deg: List[Float64]
    var aoa_deg: List[Float64]
    var zod_deg: List[Float64]
    var zoa_deg: List[Float64]

    def __init__(
        out self,
        var aod_deg: List[Float64],
        var aoa_deg: List[Float64],
        var zod_deg: List[Float64],
        var zoa_deg: List[Float64],
    ) raises:
        var count = len(aod_deg)
        if (
            count == 0
            or len(aoa_deg) != count
            or len(zod_deg) != count
            or len(zoa_deg) != count
        ):
            raise Error("CDL ray angle vectors must be equal and non-empty")
        for ray in range(count):
            if (
                not isfinite(aod_deg[ray])
                or not isfinite(aoa_deg[ray])
                or not isfinite(zod_deg[ray])
                or not isfinite(zoa_deg[ray])
            ):
                raise Error("CDL ray angles must be finite")
        self.aod_deg = aod_deg^
        self.aoa_deg = aoa_deg^
        self.zod_deg = zod_deg^
        self.zoa_deg = zoa_deg^

    def ray_count(self) -> Int:
        return len(self.aod_deg)


struct CDLPolarizationMatrix(Movable):
    """Per-ray matrix ordered as Rx(theta,phi) by Tx(theta,phi)."""

    var theta_theta: Complex64
    var theta_phi: Complex64
    var phi_theta: Complex64
    var phi_phi: Complex64

    def __init__(
        out self,
        theta_theta: Complex64,
        theta_phi: Complex64,
        phi_theta: Complex64,
        phi_phi: Complex64,
    ) raises:
        if (
            not _is_finite_complex(theta_theta)
            or not _is_finite_complex(theta_phi)
            or not _is_finite_complex(phi_theta)
            or not _is_finite_complex(phi_phi)
        ):
            raise Error("CDL polarization coefficients must be finite")
        self.theta_theta = theta_theta
        self.theta_phi = theta_phi
        self.phi_theta = phi_theta
        self.phi_phi = phi_phi


struct CDLChannel(Movable):
    """Component-major tapped MIMO realization.

    ``coefficients`` is flattened as component, receive element, transmit
    element.  Table powers are normalized to one before ray expansion, so a
    unit-gain co-polarized element pair has unit ensemble-average tap power.
    """

    var receive_count: Int
    var transmit_count: Int
    var delays_ns: List[Float64]
    var coefficients: List[Complex64]

    def __init__(
        out self,
        receive_count: Int,
        transmit_count: Int,
        var delays_ns: List[Float64],
        var coefficients: List[Complex64],
    ) raises:
        var matrix_size = _checked_positive_product(
            receive_count, transmit_count, "CDL channel"
        )
        if len(delays_ns) == 0:
            raise Error("CDL channel must contain at least one component")
        if len(delays_ns) > Int.MAX // matrix_size:
            raise Error("CDL channel coefficient dimensions overflow Int")
        if len(coefficients) != len(delays_ns) * matrix_size:
            raise Error("CDL channel coefficient dimensions do not match")
        for component in range(len(delays_ns)):
            if not isfinite(delays_ns[component]) or delays_ns[component] < 0.0:
                raise Error("CDL channel delays must be finite and non-negative")
        for coefficient in coefficients:
            if not _is_finite_complex(coefficient):
                raise Error("CDL channel coefficients must be finite")
        self.receive_count = receive_count
        self.transmit_count = transmit_count
        self.delays_ns = delays_ns^
        self.coefficients = coefficients^

    def component_count(self) -> Int:
        return len(self.delays_ns)

    def coefficient(
        self, component: Int, receive: Int, transmit: Int
    ) raises -> Complex64:
        if component < 0 or component >= self.component_count():
            raise Error("CDL component index out of range")
        if receive < 0 or receive >= self.receive_count:
            raise Error("CDL receive element index out of range")
        if transmit < 0 or transmit >= self.transmit_count:
            raise Error("CDL transmit element index out of range")
        return self.coefficients[
            (component * self.receive_count + receive)
            * self.transmit_count
            + transmit
        ]

    def narrowband(self) raises -> List[Complex64]:
        """Sum all delay components at zero baseband frequency offset."""
        var count = _checked_positive_product(
            self.receive_count, self.transmit_count, "CDL narrowband matrix"
        )
        var result = List[Complex64](
            length=count, fill=Complex64(0.0, 0.0)
        )
        for index in range(count):
            var scale = 0.0
            for component in range(self.component_count()):
                var value = self.coefficients[component * count + index]
                scale = max(scale, max(abs(value.re), abs(value.im)))
            if scale == 0.0:
                continue

            var real_sum = 0.0
            var real_correction = 0.0
            var imag_sum = 0.0
            var imag_correction = 0.0
            for component in range(self.component_count()):
                var value = self.coefficients[component * count + index]
                var real_update = _compensated_add(
                    real_sum, real_correction, value.re / scale
                )
                real_sum = real_update[0]
                real_correction = real_update[1]
                var imag_update = _compensated_add(
                    imag_sum, imag_correction, value.im / scale
                )
                imag_sum = imag_update[0]
                imag_correction = imag_update[1]

            result[index] = Complex64(
                scale * (real_sum + real_correction),
                scale * (imag_sum + imag_correction),
            )
            if not _is_finite_complex(result[index]):
                raise Error("CDL narrowband accumulation must remain finite")
        return result^

    def frequency_response(
        self, offset_hz: Float64
    ) raises -> List[Complex64]:
        """Return H(f) at a baseband offset from the carrier."""
        if not isfinite(offset_hz):
            raise Error("CDL frequency offset must be finite")
        if offset_hz == 0.0:
            return self.narrowband()
        var count = _checked_positive_product(
            self.receive_count, self.transmit_count,
            "CDL frequency-response matrix",
        )
        var result = List[Complex64](
            length=count, fill=Complex64(0.0, 0.0)
        )
        var rotations = List[Complex64](capacity=self.component_count())
        for component in range(self.component_count()):
            var cycles = _reduced_product_cycles(
                -offset_hz, self.delays_ns[component], 1.0e-9
            )
            var phase = _TWO_PI * cycles
            rotations.append(Complex64(cos(phase), sin(phase)))

        for index in range(count):
            var scale = 0.0
            for component in range(self.component_count()):
                var value = (
                    self.coefficients[component * count + index]
                    * rotations[component]
                )
                scale = max(scale, max(abs(value.re), abs(value.im)))
            if scale == 0.0:
                continue

            var real_sum = 0.0
            var real_correction = 0.0
            var imag_sum = 0.0
            var imag_correction = 0.0
            for component in range(self.component_count()):
                var value = (
                    self.coefficients[component * count + index]
                    * rotations[component]
                )
                var real_update = _compensated_add(
                    real_sum, real_correction, value.re / scale
                )
                real_sum = real_update[0]
                real_correction = real_update[1]
                var imag_update = _compensated_add(
                    imag_sum, imag_correction, value.im / scale
                )
                imag_sum = imag_update[0]
                imag_correction = imag_update[1]

            result[index] = Complex64(
                scale * (real_sum + real_correction),
                scale * (imag_sum + imag_correction),
            )
            if not _is_finite_complex(result[index]):
                raise Error(
                    "CDL frequency-response accumulation must remain finite"
                )
        return result^

    def total_tapped_energy(self) raises -> Float64:
        var result = 0.0
        for value in self.coefficients:
            result += value.magnitude_squared()
            if not isfinite(result):
                raise Error("CDL tapped energy must remain finite")
        return result


def _db_to_linear(value_db: Float64) -> Float64:
    return exp(_LN_10_OVER_10 * value_db)


def _cluster_indices(count: Int, *, los_first: Bool = False) -> List[Int]:
    var cluster_indices = List[Int](capacity=count)
    for component in range(count):
        cluster_indices.append(component)
    if los_first:
        cluster_indices[0] = 0
        cluster_indices[1] = 0
        for component in range(2, count):
            cluster_indices[component] = component - 1
    return cluster_indices^


def _path_kinds(count: Int, *, los_first: Bool = False) -> List[Int]:
    var result = List[Int](length=count, fill=CDL_PATH_DIFFUSE)
    if los_first:
        result[0] = CDL_PATH_LOS
    return result^


def cdl_profile(
    model: String, *, desired_delay_spread_ns: Float64 = 100.0
) raises -> CDLProfile:
    """Return CDL-A/B/C/D/E with unmodified Release 18.1 reference values."""
    if (
        not isfinite(desired_delay_spread_ns)
        or desired_delay_spread_ns <= 0.0
    ):
        raise Error("CDL delay spread must be finite and positive")
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
        var aod: List[Float64] = [
            -178.1, -4.2, -4.2, -4.2, 90.2, 90.2, 90.2, 121.5,
            -81.7, 158.4, -83.0, 134.8, -153.0, -172.0, -129.9,
            -136.0, 165.4, 148.4, 132.7, -118.6, -154.1, 126.5,
            -56.2,
        ]
        var aoa: List[Float64] = [
            51.3, -152.7, -152.7, -152.7, 76.6, 76.6, 76.6, -1.8,
            -41.9, 94.2, 51.9, -115.9, 26.6, 76.6, -7.0, -23.0,
            -47.2, 110.4, 144.5, 155.3, 102.0, -151.8, 55.2,
        ]
        var zod: List[Float64] = [
            50.2, 93.2, 93.2, 93.2, 122.0, 122.0, 122.0, 150.2,
            55.2, 26.4, 126.4, 171.6, 151.4, 157.2, 47.2, 40.4,
            43.3, 161.8, 10.8, 16.7, 171.7, 22.7, 144.9,
        ]
        var zoa: List[Float64] = [
            125.4, 91.3, 91.3, 91.3, 94.0, 94.0, 94.0, 47.1,
            56.0, 30.1, 58.8, 26.0, 49.2, 143.1, 117.4, 122.7,
            123.2, 32.6, 27.2, 15.2, 146.0, 150.7, 156.1,
        ]
        var cluster_indices = _cluster_indices(len(delays))
        var path_kinds = _path_kinds(len(delays))
        return CDLProfile(
            String("CDL-A"), delays^, powers^, aod^, aoa^, zod^, zoa^,
            cluster_indices^, path_kinds^, 23, desired_delay_spread_ns,
            5.0, 11.0, 3.0, 3.0, 10.0, False, 0.0,
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
        var aod: List[Float64] = [
            9.3, 9.3, 9.3, -34.1, -65.4, -11.4, -11.4, -11.4,
            -67.2, 52.5, -72.0, 74.3, -52.2, -50.5, 61.4, 30.6,
            -72.5, -90.6, -77.6, -82.6, -103.6, 75.6, -77.6,
        ]
        var aoa: List[Float64] = [
            -173.3, -173.3, -173.3, 125.5, -88.0, 155.1, 155.1,
            155.1, -89.8, 132.1, -83.6, 95.3, 103.7, -87.8,
            -92.5, -139.1, -90.6, 58.6, -79.0, 65.8, 52.7, 88.7,
            -60.4,
        ]
        var zod: List[Float64] = [
            105.8, 105.8, 105.8, 115.3, 119.3, 103.2, 103.2,
            103.2, 118.2, 102.0, 100.4, 98.3, 103.4, 102.5, 101.4,
            103.0, 100.0, 115.2, 100.5, 119.6, 118.7, 117.8, 115.7,
        ]
        var zoa: List[Float64] = [
            78.9, 78.9, 78.9, 63.3, 59.9, 67.5, 67.5, 67.5, 82.6,
            66.3, 61.6, 58.0, 78.2, 82.0, 62.4, 78.0, 60.9, 82.9,
            60.8, 57.3, 59.9, 60.1, 62.3,
        ]
        var cluster_indices = _cluster_indices(len(delays))
        var path_kinds = _path_kinds(len(delays))
        return CDLProfile(
            String("CDL-B"), delays^, powers^, aod^, aoa^, zod^, zoa^,
            cluster_indices^, path_kinds^, 23, desired_delay_spread_ns,
            10.0, 22.0, 3.0, 7.0, 8.0, False, 0.0,
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
        var aod: List[Float64] = [
            -46.6, -22.8, -22.8, -22.8, -40.7, 0.3, 0.3, 0.3,
            73.1, -64.5, 80.2, -97.1, -55.3, -64.3, -78.5,
            102.7, 99.2, 88.8, -101.9, 92.2, 93.3, 106.6, 119.5,
            -123.8,
        ]
        var aoa: List[Float64] = [
            -101.0, 120.0, 120.0, 120.0, -127.5, 170.4, 170.4,
            170.4, 55.4, 66.5, -48.1, 46.9, 68.1, -68.7, 81.5,
            30.7, -16.4, 3.8, -13.7, 9.7, 5.6, 0.7, -21.9, 33.6,
        ]
        var zod: List[Float64] = [
            97.2, 98.6, 98.6, 98.6, 100.6, 99.2, 99.2, 99.2,
            105.2, 95.3, 106.1, 93.5, 103.7, 104.2, 93.0, 104.2,
            94.9, 93.1, 92.2, 106.7, 93.0, 92.9, 105.2, 107.8,
        ]
        var zoa: List[Float64] = [
            87.6, 72.1, 72.1, 72.1, 70.1, 75.3, 75.3, 75.3, 67.4,
            63.8, 71.4, 60.5, 90.6, 60.1, 61.0, 100.7, 62.3, 66.7,
            52.9, 61.8, 51.9, 61.7, 58.0, 57.0,
        ]
        var cluster_indices = _cluster_indices(len(delays))
        var path_kinds = _path_kinds(len(delays))
        return CDLProfile(
            String("CDL-C"), delays^, powers^, aod^, aoa^, zod^, zoa^,
            cluster_indices^, path_kinds^, 24, desired_delay_spread_ns,
            2.0, 15.0, 3.0, 7.0, 7.0, False, 0.0,
        )
    if model == "D":
        var delays: List[Float64] = [
            0.000, 0.000, 0.035, 0.612, 1.363, 1.405, 1.804,
            2.596, 1.775, 4.042, 7.937, 9.424, 9.708, 12.525,
        ]
        var powers: List[Float64] = [
            -0.2, -13.5, -18.8, -21.0, -22.8, -17.9, -20.1,
            -21.9, -22.9, -27.8, -23.6, -24.8, -30.0, -27.7,
        ]
        var aod: List[Float64] = [
            0.0, 0.0, 89.2, 89.2, 89.2, 13.0, 13.0, 13.0, 34.6,
            -64.5, -32.9, 52.6, -132.1, 77.2,
        ]
        var aoa: List[Float64] = [
            -180.0, -180.0, 89.2, 89.2, 89.2, 163.0, 163.0,
            163.0, -137.0, 74.5, 127.7, -119.6, -9.1, -83.8,
        ]
        var zod: List[Float64] = [
            98.5, 98.5, 85.5, 85.5, 85.5, 97.5, 97.5, 97.5, 98.5,
            88.4, 91.3, 103.8, 80.3, 86.5,
        ]
        var zoa: List[Float64] = [
            81.5, 81.5, 86.9, 86.9, 86.9, 79.4, 79.4, 79.4, 78.2,
            73.6, 78.3, 87.0, 70.6, 72.9,
        ]
        var cluster_indices = _cluster_indices(len(delays), los_first=True)
        var path_kinds = _path_kinds(len(delays), los_first=True)
        return CDLProfile(
            String("CDL-D"), delays^, powers^, aod^, aoa^, zod^, zoa^,
            cluster_indices^, path_kinds^, 13, desired_delay_spread_ns,
            5.0, 8.0, 3.0, 3.0, 11.0, True, 13.3,
        )
    if model == "E":
        var delays: List[Float64] = [
            0.0000, 0.0000, 0.5133, 0.5440, 0.5630, 0.5440,
            0.7112, 1.9092, 1.9293, 1.9589, 2.6426, 3.7136,
            5.4524, 12.0034, 20.6419,
        ]
        var powers: List[Float64] = [
            -0.03, -22.03, -15.8, -18.1, -19.8, -22.9, -22.4,
            -18.6, -20.8, -22.6, -22.3, -25.6, -20.2, -29.8,
            -29.2,
        ]
        var aod: List[Float64] = [
            0.0, 0.0, 57.5, 57.5, 57.5, -20.1, 16.2, 9.3, 9.3,
            9.3, 19.0, 32.7, 0.5, 55.9, 57.6,
        ]
        var aoa: List[Float64] = [
            -180.0, -180.0, 18.2, 18.2, 18.2, 101.8, 112.9,
            -155.5, -155.5, -155.5, -143.3, -94.7, 147.0, -36.2,
            -26.0,
        ]
        var zod: List[Float64] = [
            99.6, 99.6, 104.2, 104.2, 104.2, 99.4, 100.8, 98.8,
            98.8, 98.8, 100.8, 96.4, 98.9, 95.6, 104.6,
        ]
        var zoa: List[Float64] = [
            80.4, 80.4, 80.4, 80.4, 80.4, 80.8, 86.3, 82.7, 82.7,
            82.7, 82.9, 88.0, 81.0, 88.6, 78.3,
        ]
        var cluster_indices = _cluster_indices(len(delays), los_first=True)
        var path_kinds = _path_kinds(len(delays), los_first=True)
        return CDLProfile(
            String("CDL-E"), delays^, powers^, aod^, aoa^, zod^, zoa^,
            cluster_indices^, path_kinds^, 14, desired_delay_spread_ns,
            5.0, 11.0, 3.0, 7.0, 8.0, True, 22.0,
        )
    raise Error("CDL model must be A through E")


def cdl_ray_offsets() -> List[Float64]:
    """Return Table 7.5-3's twenty dimensionless ray offsets."""
    return [
        0.0447, -0.0447, 0.1413, -0.1413, 0.2492, -0.2492,
        0.3715, -0.3715, 0.5129, -0.5129, 0.6797, -0.6797,
        0.8844, -0.8844, 1.1481, -1.1481, 1.5195, -1.5195,
        2.1551, -2.1551,
    ]


def _uniform(mut state: UInt64) -> Float64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return (Float64(state >> 11) + 0.5) / 9007199254740992.0


def _mixed_seed(seed: UInt64, cluster: Int, ray: Int, stream: Int) -> UInt64:
    var value = seed ^ (UInt64(cluster + 1) * UInt64(0x9E3779B97F4A7C15))
    value ^= UInt64(ray + 1) * UInt64(0xD1B54A32D192ED03)
    value ^= UInt64(stream + 1) * UInt64(0x94D049BB133111EB)
    value = (value ^ (value >> 30)) * UInt64(0xBF58476D1CE4E5B9)
    value = (value ^ (value >> 27)) * UInt64(0x94D049BB133111EB)
    return value ^ (value >> 31)


def _permutation(seed: UInt64, cluster: Int, stream: Int) -> List[Int]:
    var result = List[Int](capacity=CDL_RAYS_PER_CLUSTER)
    for ray in range(CDL_RAYS_PER_CLUSTER):
        result.append(ray)
    var state = _mixed_seed(seed, cluster, 0, stream)
    var remaining = CDL_RAYS_PER_CLUSTER
    while remaining > 1:
        var selected = Int(_uniform(state) * Float64(remaining))
        var tail = remaining - 1
        var temporary = result[tail]
        result[tail] = result[selected]
        result[selected] = temporary
        remaining -= 1
    return result^


def cdl_ray_angles(
    profile: CDLProfile, component: Int, *, seed: UInt64
) raises -> CDLRayAngles:
    """Generate angles and the three independent clause-7.7.1 couplings."""
    if component < 0 or component >= profile.component_count():
        raise Error("CDL component index out of range")
    if profile.path_kinds[component] == CDL_PATH_LOS:
        var aod: List[Float64] = [profile.aod_deg[component]]
        var aoa: List[Float64] = [profile.aoa_deg[component]]
        var zod: List[Float64] = [profile.zod_deg[component]]
        var zoa: List[Float64] = [profile.zoa_deg[component]]
        return CDLRayAngles(aod^, aoa^, zod^, zoa^)
    var cluster = profile.cluster_indices[component]
    var offsets = cdl_ray_offsets()
    # Pair AOD randomly with AOA, ZOD randomly with ZOA, and then couple the
    # two pairs randomly.  This is the three-stage procedure in clause 7.7.1.
    var aod_order = _permutation(seed, cluster, 0)
    var zod_order = _permutation(seed, cluster, 1)
    var pair_order = _permutation(seed, cluster, 2)
    var aod = List[Float64](capacity=CDL_RAYS_PER_CLUSTER)
    var aoa = List[Float64](capacity=CDL_RAYS_PER_CLUSTER)
    var zod = List[Float64](capacity=CDL_RAYS_PER_CLUSTER)
    var zoa = List[Float64](capacity=CDL_RAYS_PER_CLUSTER)
    for ray in range(CDL_RAYS_PER_CLUSTER):
        var zenith_pair = pair_order[ray]
        aod.append(
            profile.aod_deg[component]
            + profile.azimuth_departure_spread_deg * offsets[aod_order[ray]]
        )
        aoa.append(
            profile.aoa_deg[component]
            + profile.azimuth_arrival_spread_deg * offsets[ray]
        )
        zod.append(
            profile.zod_deg[component]
            + profile.zenith_departure_spread_deg
            * offsets[zod_order[zenith_pair]]
        )
        zoa.append(
            profile.zoa_deg[component]
            + profile.zenith_arrival_spread_deg * offsets[zenith_pair]
        )
    return CDLRayAngles(aod^, aoa^, zod^, zoa^)


def _unit_phase(phase: Float64) -> Complex64:
    return Complex64(cos(phase), sin(phase))


def _scale(value: Complex64, scale: Float64) -> Complex64:
    return Complex64(scale * value.re, scale * value.im)


def cdl_ray_polarization_matrix(
    profile: CDLProfile, component: Int, ray: Int, *, seed: UInt64
) raises -> CDLPolarizationMatrix:
    """Return the seeded phase/XPR matrix for one diffuse ray.

    The LOS component uses the deterministic diag(1,-1) matrix from
    equation 7.5-29.  Diffuse co-polar magnitudes are one and cross-polar
    squared magnitudes are exactly ``1 / profile.xpr_linear()``.
    """
    if component < 0 or component >= profile.component_count():
        raise Error("CDL component index out of range")
    if profile.path_kinds[component] == CDL_PATH_LOS:
        if ray != 0:
            raise Error("CDL LOS component contains exactly one ray")
        return CDLPolarizationMatrix(
            Complex64(1.0, 0.0), Complex64(0.0, 0.0),
            Complex64(0.0, 0.0), Complex64(-1.0, 0.0),
        )
    if ray < 0 or ray >= CDL_RAYS_PER_CLUSTER:
        raise Error("CDL diffuse ray index out of range")
    var cluster = profile.cluster_indices[component]
    var state = _mixed_seed(seed, cluster, ray, 3)
    var theta_theta = _unit_phase(_TWO_PI * _uniform(state) - _PI)
    var theta_phi = _unit_phase(_TWO_PI * _uniform(state) - _PI)
    var phi_theta = _unit_phase(_TWO_PI * _uniform(state) - _PI)
    var phi_phi = _unit_phase(_TWO_PI * _uniform(state) - _PI)
    # Evaluate the half exponent directly.  The full linear XPR can overflow
    # even when its reciprocal square root remains representable.
    var cross_scale = exp(-0.5 * _LN_10_OVER_10 * profile.xpr_db)
    return CDLPolarizationMatrix(
        theta_theta,
        _scale(theta_phi, cross_scale),
        _scale(phi_theta, cross_scale),
        phi_phi,
    )


def cdl_ula(
    element_count: Int,
    *,
    spacing_wavelengths: Float64 = 0.5,
    axis: Int = 1,
) raises -> CDLArray:
    """Create a centered ULA; axis 0/1/2 denotes x/y/z.

    This scalar CPU reference accepts at most 65,536 elements.  That bound is
    an implementation capacity guard, not a 3GPP array-size restriction.
    """
    if (
        element_count <= 0
        or not isfinite(spacing_wavelengths)
        or spacing_wavelengths <= 0.0
    ):
        raise Error("CDL ULA size and spacing must be finite and positive")
    if axis < 0 or axis > 2:
        raise Error("CDL ULA axis must be x=0, y=1, or z=2")
    if element_count > _CDL_CPU_REFERENCE_MAX_ARRAY_ELEMENTS:
        raise Error("CDL ULA exceeds the CPU reference capacity")
    var maximum_position = (
        0.5 * Float64(element_count - 1) * spacing_wavelengths
    )
    if not isfinite(maximum_position):
        raise Error("CDL ULA coordinates must remain finite")
    var x = List[Float64](length=element_count, fill=0.0)
    var y = List[Float64](length=element_count, fill=0.0)
    var z = List[Float64](length=element_count, fill=0.0)
    for element in range(element_count):
        var position = (
            Float64(element) - 0.5 * Float64(element_count - 1)
        ) * spacing_wavelengths
        if axis == 0:
            x[element] = position
        elif axis == 1:
            y[element] = position
        else:
            z[element] = position
    return CDLArray(x^, y^, z^)


def cdl_upa(
    rows: Int,
    columns: Int,
    *,
    horizontal_spacing_wavelengths: Float64 = 0.5,
    vertical_spacing_wavelengths: Float64 = 0.5,
    horizontal_axis: Int = 1,
    vertical_axis: Int = 2,
) raises -> CDLArray:
    """Create a centered row-major UPA on two selectable Cartesian axes.

    This scalar CPU reference accepts at most 65,536 total elements.  That
    bound is an implementation capacity guard, not a 3GPP model restriction.
    """
    if rows <= 0 or columns <= 0:
        raise Error("CDL UPA dimensions must be positive")
    if (
        not isfinite(horizontal_spacing_wavelengths)
        or horizontal_spacing_wavelengths <= 0.0
        or not isfinite(vertical_spacing_wavelengths)
        or vertical_spacing_wavelengths <= 0.0
    ):
        raise Error("CDL UPA spacings must be finite and positive")
    if (
        horizontal_axis < 0
        or horizontal_axis > 2
        or vertical_axis < 0
        or vertical_axis > 2
        or horizontal_axis == vertical_axis
    ):
        raise Error("CDL UPA axes must be distinct x=0, y=1, or z=2")
    var count = _checked_positive_product(rows, columns, "CDL UPA")
    if count > _CDL_CPU_REFERENCE_MAX_ARRAY_ELEMENTS:
        raise Error("CDL UPA exceeds the CPU reference capacity")
    var maximum_horizontal = (
        0.5 * Float64(columns - 1) * horizontal_spacing_wavelengths
    )
    var maximum_vertical = (
        0.5 * Float64(rows - 1) * vertical_spacing_wavelengths
    )
    if not isfinite(maximum_horizontal) or not isfinite(maximum_vertical):
        raise Error("CDL UPA coordinates must remain finite")
    var x = List[Float64](length=count, fill=0.0)
    var y = List[Float64](length=count, fill=0.0)
    var z = List[Float64](length=count, fill=0.0)
    for row in range(rows):
        var vertical = (
            Float64(row) - 0.5 * Float64(rows - 1)
        ) * vertical_spacing_wavelengths
        for column in range(columns):
            var horizontal = (
                Float64(column) - 0.5 * Float64(columns - 1)
            ) * horizontal_spacing_wavelengths
            var element = row * columns + column
            if horizontal_axis == 0:
                x[element] += horizontal
            elif horizontal_axis == 1:
                y[element] += horizontal
            else:
                z[element] += horizontal
            if vertical_axis == 0:
                x[element] += vertical
            elif vertical_axis == 1:
                y[element] += vertical
            else:
                z[element] += vertical
    return CDLArray(x^, y^, z^)


def _direction_x(azimuth_deg: Float64, zenith_deg: Float64) -> Float64:
    return sin(zenith_deg * _DEG_TO_RAD) * cos(azimuth_deg * _DEG_TO_RAD)


def _direction_y(azimuth_deg: Float64, zenith_deg: Float64) -> Float64:
    return sin(zenith_deg * _DEG_TO_RAD) * sin(azimuth_deg * _DEG_TO_RAD)


def _direction_z(zenith_deg: Float64) -> Float64:
    return cos(zenith_deg * _DEG_TO_RAD)


def _steering_value(
    array: CDLArray, element: Int, azimuth_deg: Float64, zenith_deg: Float64
) -> Complex64:
    var x_projection = (
        array.x_wavelengths[element]
        * _direction_x(azimuth_deg, zenith_deg)
    )
    var y_projection = (
        array.y_wavelengths[element]
        * _direction_y(azimuth_deg, zenith_deg)
    )
    var z_projection = (
        array.z_wavelengths[element] * _direction_z(zenith_deg)
    )
    # Steering is periodic in every coordinate.  Reduce in wavelength units
    # before multiplying by 2*pi, both to avoid overflow and to keep the
    # trigonometric argument accurate for very large finite coordinates.
    var reduced_projection = remainder(x_projection, 1.0)
    reduced_projection += remainder(y_projection, 1.0)
    reduced_projection += remainder(z_projection, 1.0)
    reduced_projection = remainder(reduced_projection, 1.0)
    return _unit_phase(_TWO_PI * reduced_projection)


def _validate_cdl_array(array: CDLArray) raises -> Int:
    var count = array.element_count()
    if count <= 0 or len(array.y_wavelengths) != count:
        raise Error("CDL array coordinate vectors must be equal and non-empty")
    if len(array.z_wavelengths) != count:
        raise Error("CDL array coordinate vectors must be equal and non-empty")
    for element in range(count):
        if (
            not isfinite(array.x_wavelengths[element])
            or not isfinite(array.y_wavelengths[element])
            or not isfinite(array.z_wavelengths[element])
        ):
            raise Error("CDL array coordinates must be finite")
    return count


def cdl_array_response(
    array: CDLArray, azimuth_deg: Float64, zenith_deg: Float64
) raises -> List[Complex64]:
    """Return exp(j*2*pi*r dot direction) for every array element."""
    if not isfinite(azimuth_deg) or not isfinite(zenith_deg):
        raise Error("CDL steering angles must be finite")
    var count = _validate_cdl_array(array)
    var result = List[Complex64](capacity=count)
    for element in range(count):
        var value = _steering_value(
            array, element, azimuth_deg, zenith_deg
        )
        if not _is_finite_complex(value):
            raise Error("CDL array response must remain finite")
        result.append(value)
    return result^


def _polarization_gain(
    matrix: CDLPolarizationMatrix,
    transmit_slant_deg: Float64,
    receive_slant_deg: Float64,
) -> Complex64:
    var transmit_theta = cos(transmit_slant_deg * _DEG_TO_RAD)
    var transmit_phi = sin(transmit_slant_deg * _DEG_TO_RAD)
    var receive_theta = cos(receive_slant_deg * _DEG_TO_RAD)
    var receive_phi = sin(receive_slant_deg * _DEG_TO_RAD)
    var result = _scale(
        matrix.theta_theta, receive_theta * transmit_theta
    )
    result = result + _scale(
        matrix.theta_phi, receive_theta * transmit_phi
    )
    result = result + _scale(
        matrix.phi_theta, receive_phi * transmit_theta
    )
    return result + _scale(
        matrix.phi_phi, receive_phi * transmit_phi
    )


def _doppler_cycles(
    arrival_azimuth_deg: Float64,
    arrival_zenith_deg: Float64,
    carrier_frequency_hz: Float64,
    speed_mps: Float64,
    travel_azimuth_deg: Float64,
    travel_zenith_deg: Float64,
    time_seconds: Float64,
) -> Float64:
    var dot = (
        _direction_x(arrival_azimuth_deg, arrival_zenith_deg)
        * _direction_x(travel_azimuth_deg, travel_zenith_deg)
        + _direction_y(arrival_azimuth_deg, arrival_zenith_deg)
        * _direction_y(travel_azimuth_deg, travel_zenith_deg)
        + _direction_z(arrival_zenith_deg)
        * _direction_z(travel_zenith_deg)
    )
    return _reduced_product_cycles(
        speed_mps,
        carrier_frequency_hz,
        dot,
        time_seconds,
        1.0 / _LIGHT_SPEED_MPS,
    )


def realize_cdl_channel(
    profile: CDLProfile,
    transmit_array: CDLArray,
    receive_array: CDLArray,
    *,
    seed: UInt64,
    time_seconds: Float64 = 0.0,
    carrier_frequency_hz: Float64 = 3.5e9,
    speed_mps: Float64 = 0.0,
    travel_azimuth_deg: Float64 = 0.0,
    travel_zenith_deg: Float64 = 90.0,
    link_distance_m: Float64 = 0.0,
    transmit_slant_deg: Float64 = 0.0,
    receive_slant_deg: Float64 = 0.0,
) raises -> CDLChannel:
    """Realize normalized tapped MIMO coefficients at an absolute time.

    Diffuse components sum twenty rays with independent seeded phases.  The
    CDL-D/E specular row is already power-separated from its diffuse row in
    the normative table, so it is not mixed by K a second time.  Its phase is
    the deterministic ``-2*pi*distance/lambda`` term from equation 7.5-29.
    """
    if (
        not isfinite(carrier_frequency_hz)
        or carrier_frequency_hz <= 0.0
    ):
        raise Error("CDL carrier frequency must be finite and positive")
    if (
        not isfinite(time_seconds)
        or not isfinite(speed_mps)
        or speed_mps < 0.0
        or not isfinite(travel_azimuth_deg)
        or not isfinite(travel_zenith_deg)
        or not isfinite(link_distance_m)
        or link_distance_m < 0.0
        or not isfinite(transmit_slant_deg)
        or not isfinite(receive_slant_deg)
    ):
        raise Error("CDL realization parameters must be finite and valid")
    var receive_count = _validate_cdl_array(receive_array)
    var transmit_count = _validate_cdl_array(transmit_array)
    var matrix_size = _checked_positive_product(
        receive_count, transmit_count, "CDL realization matrix"
    )
    var component_count = profile.component_count()
    if component_count <= 0:
        raise Error("CDL profile must contain at least one component")
    var coefficient_count = _checked_positive_product(
        component_count, matrix_size, "CDL realization coefficient"
    )
    var delays = List[Float64](capacity=profile.component_count())
    for component in range(profile.component_count()):
        delays.append(profile.delay_ns(component))
    var coefficients = List[Complex64](
        length=coefficient_count,
        fill=Complex64(0.0, 0.0),
    )
    var powers = profile.normalized_linear_powers()
    for component in range(profile.component_count()):
        if profile.path_kinds[component] == CDL_PATH_LOS:
            var polarization = cdl_ray_polarization_matrix(
                profile, component, 0, seed=seed
            )
            var gain = _polarization_gain(
                polarization, transmit_slant_deg, receive_slant_deg
            )
            if not _is_finite_complex(gain):
                raise Error("CDL polarization gain must remain finite")
            var doppler_cycles = _doppler_cycles(
                profile.aoa_deg[component], profile.zoa_deg[component],
                carrier_frequency_hz, speed_mps,
                travel_azimuth_deg, travel_zenith_deg,
                time_seconds,
            )
            var path_cycles = remainder(
                -_reduced_product_cycles(
                    link_distance_m,
                    carrier_frequency_hz,
                    1.0 / _LIGHT_SPEED_MPS,
                )
                + doppler_cycles,
                1.0,
            )
            var path_phase = _TWO_PI * path_cycles
            var scalar = _scale(
                gain * _unit_phase(path_phase), sqrt(powers[component])
            )
            if not _is_finite_complex(scalar):
                raise Error("CDL LOS coefficient must remain finite")
            for receive in range(receive_count):
                var receive_steering = _steering_value(
                    receive_array, receive,
                    profile.aoa_deg[component], profile.zoa_deg[component],
                )
                for transmit in range(transmit_count):
                    var transmit_steering = _steering_value(
                        transmit_array, transmit,
                        profile.aod_deg[component], profile.zod_deg[component],
                    )
                    var index = (
                        (component * receive_count + receive)
                        * transmit_count + transmit
                    )
                    coefficients[index] = scalar * (
                        receive_steering * transmit_steering
                    )
                    if not _is_finite_complex(coefficients[index]):
                        raise Error("CDL LOS coefficient must remain finite")
        else:
            var angles = cdl_ray_angles(profile, component, seed=seed)
            var ray_amplitude = sqrt(
                powers[component] / Float64(CDL_RAYS_PER_CLUSTER)
            )
            for ray in range(CDL_RAYS_PER_CLUSTER):
                var polarization = cdl_ray_polarization_matrix(
                    profile, component, ray, seed=seed
                )
                var gain = _polarization_gain(
                    polarization, transmit_slant_deg, receive_slant_deg
                )
                if not _is_finite_complex(gain):
                    raise Error("CDL polarization gain must remain finite")
                var doppler_cycles = _doppler_cycles(
                    angles.aoa_deg[ray], angles.zoa_deg[ray],
                    carrier_frequency_hz, speed_mps,
                    travel_azimuth_deg, travel_zenith_deg,
                    time_seconds,
                )
                var ray_phase = _TWO_PI * doppler_cycles
                var scalar = _scale(
                    gain * _unit_phase(ray_phase),
                    ray_amplitude,
                )
                if not _is_finite_complex(scalar):
                    raise Error("CDL diffuse coefficient must remain finite")
                for receive in range(receive_count):
                    var receive_steering = _steering_value(
                        receive_array, receive,
                        angles.aoa_deg[ray], angles.zoa_deg[ray],
                    )
                    for transmit in range(transmit_count):
                        var transmit_steering = _steering_value(
                            transmit_array, transmit,
                            angles.aod_deg[ray], angles.zod_deg[ray],
                        )
                        var index = (
                            (component * receive_count + receive)
                            * transmit_count + transmit
                        )
                        coefficients[index] = coefficients[index] + (
                            scalar * receive_steering * transmit_steering
                        )
                        if not _is_finite_complex(coefficients[index]):
                            raise Error(
                                "CDL diffuse accumulation must remain finite"
                            )
    return CDLChannel(
        receive_count, transmit_count, delays^, coefficients^
    )


def apply_cdl_narrowband(
    channel: CDLChannel, transmit_symbols: List[Complex64]
) raises -> List[Complex64]:
    """Apply a realized zero-offset narrowband matrix to one Tx vector."""
    if len(transmit_symbols) != channel.transmit_count:
        raise Error("CDL narrowband input dimension does not match Tx array")
    for symbol in transmit_symbols:
        if not _is_finite_complex(symbol):
            raise Error("CDL narrowband input symbols must be finite")
    var matrix = channel.narrowband()
    var result = List[Complex64](
        length=channel.receive_count, fill=Complex64(0.0, 0.0)
    )
    for receive in range(channel.receive_count):
        for transmit in range(channel.transmit_count):
            result[receive] = result[receive] + (
                matrix[receive * channel.transmit_count + transmit]
                * transmit_symbols[transmit]
            )
            if not _is_finite_complex(result[receive]):
                raise Error("CDL narrowband output must remain finite")
    return result^
