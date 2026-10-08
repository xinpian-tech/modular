"""Rel-17 NR-NTN timing and frequency pre-compensation arithmetic.

This scalar CPU reference implements a bounded, decoded-configuration subset
of 3GPP TS 38.213 V17.13.0 clause 4.2 and TS 38.331 V17.17.0 ``NTN-Config``.
It evaluates service-link range, propagation delay, radial velocity, Doppler,
the ``ta-Common`` drift polynomial, Differential-Koffset composition, and the
validity interval for uplink synchronization assistance.

ECEF state vectors are caller-provided at the evaluation instant.  Orbital
element propagation, GNSS acquisition, feeder-link modelling, HARQ/RA state,
RF payload behaviour, and ASN.1 decoding are deliberately outside this
module.  Positive radial velocity means increasing UE-to-satellite range;
uplink frequency pre-compensation therefore has the opposite sign from the
received service-link Doppler shift.
"""

from std.math import isfinite, sqrt


comptime NR_NTN_SPEED_OF_LIGHT_MPS = 299792458.0
comptime NR_NTN_TA_COMMON_STEP_SECONDS = 4.072e-9
comptime NR_NTN_TA_COMMON_DRIFT_STEP_SECONDS_PER_SECOND = 2.0e-10
comptime NR_NTN_TA_COMMON_VARIANT_STEP_SECONDS_PER_SECOND2 = 2.0e-11
comptime NR_NTN_KOFFSET_15KHZ_SLOT_SECONDS = 1.0e-3
comptime NR_NTN_TA_COMMON_RAW_MAX = 66485757
comptime NR_NTN_TA_COMMON_DRIFT_RAW_MIN = -257303
comptime NR_NTN_TA_COMMON_DRIFT_RAW_MAX = 257303
comptime NR_NTN_TA_COMMON_VARIANT_RAW_MAX = 28949
comptime NR_NTN_CELL_SPECIFIC_KOFFSET_MAX = 1023
comptime NR_NTN_DIFFERENTIAL_KOFFSET_MAX = 63


struct NRNTNECEFStateVector(ImplicitlyCopyable, Equatable):
    """Caller-evaluated ECEF position in metres and velocity in metres/s."""

    var x_m: Float64
    var y_m: Float64
    var z_m: Float64
    var vx_mps: Float64
    var vy_mps: Float64
    var vz_mps: Float64

    def __init__(
        out self,
        x_m: Float64,
        y_m: Float64,
        z_m: Float64,
        vx_mps: Float64,
        vy_mps: Float64,
        vz_mps: Float64,
    ) raises:
        self.x_m = x_m
        self.y_m = y_m
        self.z_m = z_m
        self.vx_mps = vx_mps
        self.vy_mps = vy_mps
        self.vz_mps = vz_mps
        self.validate()

    def validate(self) raises:
        """Revalidate public mutable state-vector fields."""
        if (
            not isfinite(self.x_m)
            or not isfinite(self.y_m)
            or not isfinite(self.z_m)
            or not isfinite(self.vx_mps)
            or not isfinite(self.vy_mps)
            or not isfinite(self.vz_mps)
        ):
            raise Error("NR-NTN ECEF state-vector fields must be finite")


struct NRNTNRel17CommonTimingAssistance(ImplicitlyCopyable, Equatable):
    """Decoded Rel-17 ``TA-Info`` plus UL-sync validity duration."""

    var ta_common_raw: Int
    var ta_common_drift_raw: Int
    var ta_common_drift_variant_raw: Int
    var ul_sync_validity_seconds: Int

    def __init__(
        out self,
        ta_common_raw: Int,
        ta_common_drift_raw: Int,
        ta_common_drift_variant_raw: Int,
        ul_sync_validity_seconds: Int,
    ) raises:
        self.ta_common_raw = ta_common_raw
        self.ta_common_drift_raw = ta_common_drift_raw
        self.ta_common_drift_variant_raw = ta_common_drift_variant_raw
        self.ul_sync_validity_seconds = ul_sync_validity_seconds
        self.validate()

    def validate(self) raises:
        """Revalidate TS 38.331 field ranges after possible mutation."""
        if self.ta_common_raw < 0 or (
            self.ta_common_raw > NR_NTN_TA_COMMON_RAW_MAX
        ):
            raise Error("ta-Common-r17 is outside INTEGER(0..66485757)")
        if (
            self.ta_common_drift_raw < NR_NTN_TA_COMMON_DRIFT_RAW_MIN
            or self.ta_common_drift_raw > NR_NTN_TA_COMMON_DRIFT_RAW_MAX
        ):
            raise Error("ta-CommonDrift-r17 is outside its ASN.1 range")
        if self.ta_common_drift_variant_raw < 0 or (
            self.ta_common_drift_variant_raw
            > NR_NTN_TA_COMMON_VARIANT_RAW_MAX
        ):
            raise Error("ta-CommonDriftVariant-r17 is outside its range")
        if not _valid_ul_sync_duration(self.ul_sync_validity_seconds):
            raise Error("invalid ntn-UlSyncValidityDuration-r17 value")


struct NRNTNRel17Precompensation(ImplicitlyCopyable):
    """One auditable Rel-17 service-link pre-compensation result."""

    var service_link_range_m: Float64
    var service_link_rtt_seconds: Float64
    var common_ta_seconds: Float64
    var ntn_propagation_ta_seconds: Float64
    var radial_velocity_mps: Float64
    var received_doppler_shift_hz: Float64
    var uplink_frequency_precompensation_hz: Float64
    var effective_koffset_15khz_slots: Int
    var effective_koffset_seconds: Float64

    def __init__(
        out self,
        service_link_range_m: Float64,
        service_link_rtt_seconds: Float64,
        common_ta_seconds: Float64,
        ntn_propagation_ta_seconds: Float64,
        radial_velocity_mps: Float64,
        received_doppler_shift_hz: Float64,
        uplink_frequency_precompensation_hz: Float64,
        effective_koffset_15khz_slots: Int,
        effective_koffset_seconds: Float64,
    ):
        self.service_link_range_m = service_link_range_m
        self.service_link_rtt_seconds = service_link_rtt_seconds
        self.common_ta_seconds = common_ta_seconds
        self.ntn_propagation_ta_seconds = ntn_propagation_ta_seconds
        self.radial_velocity_mps = radial_velocity_mps
        self.received_doppler_shift_hz = received_doppler_shift_hz
        self.uplink_frequency_precompensation_hz = (
            uplink_frequency_precompensation_hz
        )
        self.effective_koffset_15khz_slots = effective_koffset_15khz_slots
        self.effective_koffset_seconds = effective_koffset_seconds


def _valid_ul_sync_duration(value: Int) -> Bool:
    return (
        value == 5
        or value == 10
        or value == 15
        or value == 20
        or value == 25
        or value == 30
        or value == 35
        or value == 40
        or value == 45
        or value == 50
        or value == 55
        or value == 60
        or value == 120
        or value == 180
        or value == 240
        or value == 900
    )


def _checked_difference(lhs: Float64, rhs: Float64, field: String) raises -> Float64:
    var result = lhs - rhs
    if not isfinite(result):
        raise Error(field + " difference is not representable")
    return result


def _scaled_norm3(x: Float64, y: Float64, z: Float64, field: String) raises -> Float64:
    var scale = max(abs(x), max(abs(y), abs(z)))
    if scale == 0.0:
        return 0.0
    var nx = x / scale
    var ny = y / scale
    var nz = z / scale
    var normalized = sqrt(nx * nx + ny * ny + nz * nz)
    if not isfinite(normalized) or scale > Float64.MAX_FINITE / normalized:
        raise Error(field + " norm is not representable")
    return scale * normalized


def _relative_position(
    ue: NRNTNECEFStateVector, satellite: NRNTNECEFStateVector
) raises -> Tuple[Float64, Float64, Float64]:
    ue.validate()
    satellite.validate()
    return (
        _checked_difference(satellite.x_m, ue.x_m, "ECEF x"),
        _checked_difference(satellite.y_m, ue.y_m, "ECEF y"),
        _checked_difference(satellite.z_m, ue.z_m, "ECEF z"),
    )


def nr_ntn_rel17_service_link_range_m(
    ue: NRNTNECEFStateVector, satellite: NRNTNECEFStateVector
) raises -> Float64:
    """Return scale-safe UE-to-satellite ECEF distance in metres."""
    var relative = _relative_position(ue, satellite)
    var distance = _scaled_norm3(
        relative[0],
        relative[1],
        relative[2],
        "service-link range",
    )
    if distance <= 0.0:
        raise Error("UE and serving-satellite positions must differ")
    return distance


def nr_ntn_rel17_service_link_rtt_seconds(
    ue: NRNTNECEFStateVector, satellite: NRNTNECEFStateVector
) raises -> Float64:
    """Return the two-way UE-to-satellite propagation delay."""
    var one_way = nr_ntn_rel17_service_link_range_m(ue, satellite) / (
        NR_NTN_SPEED_OF_LIGHT_MPS
    )
    if one_way > Float64.MAX_FINITE / 2.0:
        raise Error("service-link round-trip delay is not representable")
    return 2.0 * one_way


def nr_ntn_rel17_radial_velocity_mps(
    ue: NRNTNECEFStateVector, satellite: NRNTNECEFStateVector
) raises -> Float64:
    """Return range rate; positive means the service-link range increases."""
    var relative = _relative_position(ue, satellite)
    var dx = relative[0]
    var dy = relative[1]
    var dz = relative[2]
    var distance = _scaled_norm3(dx, dy, dz, "service-link range")
    if distance <= 0.0:
        raise Error("UE and serving-satellite positions must differ")
    var dvx = _checked_difference(
        satellite.vx_mps, ue.vx_mps, "ECEF x velocity"
    )
    var dvy = _checked_difference(
        satellite.vy_mps, ue.vy_mps, "ECEF y velocity"
    )
    var dvz = _checked_difference(
        satellite.vz_mps, ue.vz_mps, "ECEF z velocity"
    )
    var velocity_scale = max(abs(dvx), max(abs(dvy), abs(dvz)))
    if velocity_scale == 0.0:
        return 0.0
    var normalized_dot = (
        (dx / distance) * (dvx / velocity_scale)
        + (dy / distance) * (dvy / velocity_scale)
        + (dz / distance) * (dvz / velocity_scale)
    )
    if (
        not isfinite(normalized_dot)
        or abs(normalized_dot) > Float64.MAX_FINITE / velocity_scale
    ):
        raise Error("service-link radial velocity is not representable")
    return normalized_dot * velocity_scale


def nr_ntn_rel17_service_link_doppler_shift_hz(
    ue: NRNTNECEFStateVector,
    satellite: NRNTNECEFStateVector,
    uplink_carrier_frequency_hz: Float64,
) raises -> Float64:
    """Return first-order received Doppler, negative for increasing range."""
    if (
        not isfinite(uplink_carrier_frequency_hz)
        or uplink_carrier_frequency_hz <= 0.0
    ):
        raise Error("NR-NTN uplink carrier frequency must be positive and finite")
    var radial = nr_ntn_rel17_radial_velocity_mps(ue, satellite)
    if abs(radial) >= NR_NTN_SPEED_OF_LIGHT_MPS:
        raise Error("NR-NTN relative radial velocity must be subluminal")
    var ratio = radial / NR_NTN_SPEED_OF_LIGHT_MPS
    if abs(ratio) > Float64.MAX_FINITE / uplink_carrier_frequency_hz:
        raise Error("NR-NTN Doppler shift is not representable")
    return -ratio * uplink_carrier_frequency_hz


def nr_ntn_rel17_uplink_frequency_precompensation_hz(
    ue: NRNTNECEFStateVector,
    satellite: NRNTNECEFStateVector,
    uplink_carrier_frequency_hz: Float64,
) raises -> Float64:
    """Return the frequency offset that cancels first-order service Doppler."""
    return -nr_ntn_rel17_service_link_doppler_shift_hz(
        ue, satellite, uplink_carrier_frequency_hz
    )


def nr_ntn_rel17_ul_sync_information_valid(
    assistance: NRNTNRel17CommonTimingAssistance, elapsed_since_epoch_us: Int
) raises -> Bool:
    """Return whether decoded assistance remains inside its half-open window."""
    assistance.validate()
    if elapsed_since_epoch_us < 0:
        raise Error("NR-NTN elapsed time cannot be negative")
    var limit = Int128(assistance.ul_sync_validity_seconds) * Int128(1000000)
    return Int128(elapsed_since_epoch_us) < limit


def nr_ntn_rel17_common_ta_seconds(
    assistance: NRNTNRel17CommonTimingAssistance,
    elapsed_since_epoch_seconds: Float64,
) raises -> Float64:
    """Evaluate the TS 38.213 common-TA drift polynomial.

    The return value is the two-way common timing-advance adjustment.  The
    corresponding one-way ``Delay_common(t)`` is half this value.
    """
    assistance.validate()
    if (
        not isfinite(elapsed_since_epoch_seconds)
        or elapsed_since_epoch_seconds < 0.0
        or elapsed_since_epoch_seconds
        >= Float64(assistance.ul_sync_validity_seconds)
    ):
        raise Error("NR-NTN common TA evaluation is outside its validity")
    var elapsed = elapsed_since_epoch_seconds
    var value = (
        Float64(assistance.ta_common_raw) * NR_NTN_TA_COMMON_STEP_SECONDS
        + Float64(assistance.ta_common_drift_raw)
        * NR_NTN_TA_COMMON_DRIFT_STEP_SECONDS_PER_SECOND
        * elapsed
        + Float64(assistance.ta_common_drift_variant_raw)
        * NR_NTN_TA_COMMON_VARIANT_STEP_SECONDS_PER_SECOND2
        * elapsed
        * elapsed
    )
    if not isfinite(value) or value < 0.0:
        raise Error("evaluated NR-NTN common TA is invalid")
    return value


def nr_ntn_rel17_common_one_way_delay_seconds(
    assistance: NRNTNRel17CommonTimingAssistance,
    elapsed_since_epoch_seconds: Float64,
) raises -> Float64:
    """Return ``Delay_common(t)`` from TS 38.213 clause 4.2."""
    return 0.5 * nr_ntn_rel17_common_ta_seconds(
        assistance, elapsed_since_epoch_seconds
    )


def nr_ntn_rel17_effective_koffset_15khz_slots(
    cell_specific_koffset: Int, differential_koffset: Int
) raises -> Int:
    """Return ``K_cell,offset - K_UE,offset`` in 15-kHz slots.

    A resolved ``cell_specific_koffset`` of zero is the sentinel for an
    absent ASN.1 field; a present field has the TS 38.331 range 1..1023.
    """
    if cell_specific_koffset < 0 or (
        cell_specific_koffset > NR_NTN_CELL_SPECIFIC_KOFFSET_MAX
    ):
        raise Error("cellSpecificKoffset-r17 is outside [0,1023]")
    if differential_koffset < 0 or (
        differential_koffset > NR_NTN_DIFFERENTIAL_KOFFSET_MAX
    ):
        raise Error("Differential Koffset MAC CE is outside 6 bits")
    return cell_specific_koffset - differential_koffset


def nr_ntn_rel17_koffset_seconds(
    cell_specific_koffset: Int, differential_koffset: Int
) raises -> Float64:
    """Return the effective Koffset duration from its 15-kHz slot unit."""
    return Float64(
        nr_ntn_rel17_effective_koffset_15khz_slots(
            cell_specific_koffset, differential_koffset
        )
    ) * NR_NTN_KOFFSET_15KHZ_SLOT_SECONDS


def nr_ntn_rel17_koffset_covers_propagation(
    cell_specific_koffset: Int,
    differential_koffset: Int,
    service_link_rtt_seconds: Float64,
    common_ta_seconds: Float64,
) raises -> Bool:
    """Check the TS 38.300 Koffset lower bound against RTT plus Common TA."""
    if (
        not isfinite(service_link_rtt_seconds)
        or not isfinite(common_ta_seconds)
        or service_link_rtt_seconds < 0.0
        or common_ta_seconds < 0.0
        or service_link_rtt_seconds > Float64.MAX_FINITE - common_ta_seconds
    ):
        raise Error("NR-NTN propagation-delay inputs are invalid")
    var koffset = nr_ntn_rel17_koffset_seconds(
        cell_specific_koffset, differential_koffset
    )
    return koffset >= service_link_rtt_seconds + common_ta_seconds


def nr_ntn_rel17_precompensation(
    ue: NRNTNECEFStateVector,
    satellite: NRNTNECEFStateVector,
    assistance: NRNTNRel17CommonTimingAssistance,
    elapsed_since_epoch_seconds: Float64,
    uplink_carrier_frequency_hz: Float64,
    cell_specific_koffset: Int,
    differential_koffset: Int,
) raises -> NRNTNRel17Precompensation:
    """Compose the bounded Rel-17 timing/frequency pre-compensation result."""
    var distance = nr_ntn_rel17_service_link_range_m(ue, satellite)
    var rtt = nr_ntn_rel17_service_link_rtt_seconds(ue, satellite)
    var common_ta = nr_ntn_rel17_common_ta_seconds(
        assistance, elapsed_since_epoch_seconds
    )
    if rtt > Float64.MAX_FINITE - common_ta:
        raise Error("total NR-NTN timing adjustment is not representable")
    var radial = nr_ntn_rel17_radial_velocity_mps(ue, satellite)
    var doppler = nr_ntn_rel17_service_link_doppler_shift_hz(
        ue, satellite, uplink_carrier_frequency_hz
    )
    var effective_koffset = nr_ntn_rel17_effective_koffset_15khz_slots(
        cell_specific_koffset, differential_koffset
    )
    var effective_koffset_seconds = nr_ntn_rel17_koffset_seconds(
        cell_specific_koffset, differential_koffset
    )
    if not nr_ntn_rel17_koffset_covers_propagation(
        cell_specific_koffset, differential_koffset, rtt, common_ta
    ):
        raise Error("effective NR-NTN Koffset is shorter than RTT plus Common TA")
    return NRNTNRel17Precompensation(
        distance,
        rtt,
        common_ta,
        rtt + common_ta,
        radial,
        doppler,
        -doppler,
        effective_koffset,
        effective_koffset_seconds,
    )
