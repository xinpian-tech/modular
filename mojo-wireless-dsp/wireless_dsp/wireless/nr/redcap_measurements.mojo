"""Rel-17 RedCap SS measurement profile composition.

TS 38.215 V17.5.0 does not define a different RedCap measurement equation.
This module therefore composes the existing linear SS-RSRP, SS-RSRQ,
SS-SINR, and RSSI kernels with the RedCap CD-SSB/NCD-SSB capability boundary
from TS 38.306 V17.16.0 clause 4.2.21.2.  Inputs are already selected
resource elements from one decoded RedCap DL BWP.

RF acquisition, SSB discovery, SMTC/gap scheduling, L1/L3 filtering, beam
selection, and RRC reporting are intentionally outside this pure CPU kernel.
"""

from std.collections import Span
from wireless_dsp.core import Complex64
from .measurements import (
    NRLinearMeasurements,
    nr_ss_linear_measurements,
    nr_csi_linear_measurements,
)
from .redcap import NRRedCapRel17Capabilities


comptime NR_REDCAP_SSB_CELL_DEFINING = 0
comptime NR_REDCAP_SSB_NON_CELL_DEFINING = 1


def nr_redcap_rel17_ssb_measurement_source(
    capabilities: NRRedCapRel17Capabilities,
    *,
    has_cd_ssb: Bool,
    has_ncd_ssb: Bool,
) raises -> Int:
    """Return the unique RedCap SSB source selected in one DL BWP.

    A RedCap BWP can contain at most one CD-SSB or NCD-SSB.  A measurement
    checkpoint needs exactly one of them; an SSB-free connected BWP is legal
    only for other procedures and cannot produce an SS measurement here.
    """
    capabilities.validate()
    if has_cd_ssb == has_ncd_ssb:
        raise Error("a RedCap SS measurement requires exactly one CD/NCD-SSB")
    if has_ncd_ssb and not capabilities.supports_ncd_ssb_measurements:
        raise Error("this RedCap capability does not support NCD-SSB measurement")
    if has_ncd_ssb:
        return NR_REDCAP_SSB_NON_CELL_DEFINING
    return NR_REDCAP_SSB_CELL_DEFINING


def nr_redcap_rel17_ss_linear_measurements(
    capabilities: NRRedCapRel17Capabilities,
    sss_res: Span[Complex64, ...],
    measured_bandwidth_res: Span[Complex64, ...],
    interference_noise_res: Span[Complex64, ...],
    resource_blocks: Int,
    observation_count: Int,
    *,
    has_cd_ssb: Bool,
    has_ncd_ssb: Bool,
) raises -> NRLinearMeasurements:
    """Evaluate inherited SS metrics for one explicit RedCap SSB source."""
    _ = nr_redcap_rel17_ssb_measurement_source(
        capabilities,
        has_cd_ssb=has_cd_ssb,
        has_ncd_ssb=has_ncd_ssb,
    )
    return nr_ss_linear_measurements(
        sss_res,
        measured_bandwidth_res,
        interference_noise_res,
        resource_blocks,
        observation_count,
    )


def nr_redcap_rel17_csi_linear_measurements(
    capabilities: NRRedCapRel17Capabilities,
    csi_rs_res: Span[Complex64, ...],
    measured_bandwidth_res: Span[Complex64, ...],
    interference_noise_res: Span[Complex64, ...],
    resource_blocks: Int,
    observation_count: Int,
) raises -> NRLinearMeasurements:
    """Evaluate inherited CSI metrics under an explicit Rel-17 profile."""
    capabilities.validate()
    return nr_csi_linear_measurements(
        csi_rs_res,
        measured_bandwidth_res,
        interference_noise_res,
        resource_blocks,
        observation_count,
    )
