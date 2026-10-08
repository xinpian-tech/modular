"""Independent evidence for Rel-17 RedCap SS measurement composition."""

from std.collections import Span
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from std.utils.numerics import nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.redcap import (
    NR_FREQUENCY_RANGE_FR1,
    NRRedCapRel17Capabilities,
)
from wireless_dsp.wireless.nr.measurements import (
    nr_ss_linear_measurements,
    nr_csi_linear_measurements,
)
from wireless_dsp.wireless.nr.redcap_measurements import (
    NR_REDCAP_SSB_CELL_DEFINING,
    NR_REDCAP_SSB_NON_CELL_DEFINING,
    nr_redcap_rel17_ssb_measurement_source,
    nr_redcap_rel17_ss_linear_measurements,
    nr_redcap_rel17_csi_linear_measurements,
)


def _capabilities() raises -> NRRedCapRel17Capabilities:
    return NRRedCapRel17Capabilities(
        NR_FREQUENCY_RANGE_FR1, 20.0, 1, 1
    )


def _average_power(values: Span[Complex64, ...], divisor: Int) -> Float64:
    var total = 0.0
    for index in range(len(values)):
        total += (
            values[index].re * values[index].re
            + values[index].im * values[index].im
        )
    return total / Float64(divisor)


def test_cd_and_ncd_ssb_static_measurement_oracle() raises:
    var capabilities = _capabilities()
    var sss: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(0.0, 2.0),
    ]
    var measured: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(0.0, 1.0),
        Complex64(-1.0, 0.0),
        Complex64(0.0, -1.0),
    ]
    var interference: List[Complex64] = [
        Complex64(0.5, 0.0),
        Complex64(0.0, -0.5),
    ]

    var expected_rsrp = _average_power(Span(sss), len(sss))
    var expected_rssi = _average_power(Span(measured), 2)
    var expected_interference = _average_power(
        Span(interference), len(interference)
    )
    for source in range(2):
        var has_cd = source == NR_REDCAP_SSB_CELL_DEFINING
        var result = nr_redcap_rel17_ss_linear_measurements(
            capabilities,
            Span(sss),
            Span(measured),
            Span(interference),
            20,
            2,
            has_cd_ssb=has_cd,
            has_ncd_ssb=not has_cd,
        )
        assert_almost_equal(result.rsrp, expected_rsrp, atol=1.0e-14)
        assert_almost_equal(result.rssi, expected_rssi, atol=1.0e-14)
        assert_almost_equal(
            result.rsrq, 20.0 * expected_rsrp / expected_rssi,
            atol=1.0e-14,
        )
        assert_almost_equal(
            result.sinr, expected_rsrp / expected_interference,
            atol=1.0e-14,
        )

    var csi = nr_redcap_rel17_csi_linear_measurements(
        capabilities,
        Span(sss),
        Span(measured),
        Span(interference),
        20,
        2,
    )
    var generic_csi = nr_csi_linear_measurements(
        Span(sss),
        Span(measured),
        Span(interference),
        20,
        2,
    )
    assert_almost_equal(csi.rsrp, expected_rsrp, atol=1.0e-14)
    assert_almost_equal(csi.rssi, expected_rssi, atol=1.0e-14)
    assert_almost_equal(csi.rsrq, generic_csi.rsrq, atol=0.0)
    assert_almost_equal(csi.sinr, generic_csi.sinr, atol=0.0)


def test_ssb_source_exact_presence_table_and_edges() raises:
    var capabilities = _capabilities()
    assert_equal(
        nr_redcap_rel17_ssb_measurement_source(
            capabilities, has_cd_ssb=True, has_ncd_ssb=False
        ),
        NR_REDCAP_SSB_CELL_DEFINING,
    )
    assert_equal(
        nr_redcap_rel17_ssb_measurement_source(
            capabilities, has_cd_ssb=False, has_ncd_ssb=True
        ),
        NR_REDCAP_SSB_NON_CELL_DEFINING,
    )
    with assert_raises():
        _ = nr_redcap_rel17_ssb_measurement_source(
            capabilities, has_cd_ssb=False, has_ncd_ssb=False
        )
    with assert_raises():
        _ = nr_redcap_rel17_ssb_measurement_source(
            capabilities, has_cd_ssb=True, has_ncd_ssb=True
        )

    capabilities.supports_ncd_ssb_measurements = False
    with assert_raises():
        _ = nr_redcap_rel17_ssb_measurement_source(
            capabilities, has_cd_ssb=False, has_ncd_ssb=True
        )


def test_seeded_scale_property_and_generic_kernel_differential() raises:
    var capabilities = _capabilities()
    var base_sss: List[Complex64] = [
        Complex64(0.25, -0.5),
        Complex64(-1.25, 0.75),
        Complex64(0.625, 1.5),
    ]
    var base_measured: List[Complex64] = [
        Complex64(0.5, 0.25),
        Complex64(-0.75, 1.0),
        Complex64(1.25, -0.5),
        Complex64(-1.5, -0.25),
        Complex64(0.875, 0.125),
        Complex64(-0.375, 0.625),
    ]
    var base_interference: List[Complex64] = [
        Complex64(0.125, -0.25),
        Complex64(-0.5, 0.125),
        Complex64(0.25, 0.375),
    ]
    var reference = nr_redcap_rel17_ss_linear_measurements(
        capabilities,
        Span(base_sss),
        Span(base_measured),
        Span(base_interference),
        24,
        2,
        has_cd_ssb=False,
        has_ncd_ssb=True,
    )
    var generic = nr_ss_linear_measurements(
        Span(base_sss),
        Span(base_measured),
        Span(base_interference),
        24,
        2,
    )
    assert_almost_equal(reference.rsrp, generic.rsrp, atol=0.0)
    assert_almost_equal(reference.rssi, generic.rssi, atol=0.0)
    assert_almost_equal(reference.rsrq, generic.rsrq, atol=0.0)
    assert_almost_equal(reference.sinr, generic.sinr, atol=0.0)
    var scales: List[Float64] = [0.25, 0.5, 2.0, 4.0]
    for scale_index in range(len(scales)):
        var scale = scales[scale_index]
        var multiplier = Complex64(scale, 0.0)
        var sss = base_sss.copy()
        var measured = base_measured.copy()
        var interference = base_interference.copy()
        for index in range(len(sss)):
            sss[index] = base_sss[index] * multiplier
            interference[index] = base_interference[index] * multiplier
        for index in range(len(measured)):
            measured[index] = base_measured[index] * multiplier
        var result = nr_redcap_rel17_ss_linear_measurements(
            capabilities,
            Span(sss),
            Span(measured),
            Span(interference),
            24,
            2,
            has_cd_ssb=True,
            has_ncd_ssb=False,
        )
        var csi_result = nr_redcap_rel17_csi_linear_measurements(
            capabilities,
            Span(sss),
            Span(measured),
            Span(interference),
            24,
            2,
        )
        var energy_scale = scale * scale
        assert_almost_equal(
            result.rsrp, reference.rsrp * energy_scale, rtol=1.0e-13
        )
        assert_almost_equal(
            result.rssi, reference.rssi * energy_scale, rtol=1.0e-13
        )
        assert_almost_equal(result.rsrq, reference.rsrq, rtol=1.0e-13)
        assert_almost_equal(result.sinr, reference.sinr, rtol=1.0e-13)
        assert_almost_equal(csi_result.rsrp, result.rsrp, atol=0.0)
        assert_almost_equal(csi_result.rssi, result.rssi, atol=0.0)
        assert_almost_equal(csi_result.rsrq, result.rsrq, atol=0.0)
        assert_almost_equal(csi_result.sinr, result.sinr, atol=0.0)


def test_measurement_geometry_nonfinite_and_mutation_edges() raises:
    var capabilities = _capabilities()
    var sss: List[Complex64] = [Complex64(1.0, 0.0)]
    var measured: List[Complex64] = [Complex64(1.0, 0.0)]
    var interference: List[Complex64] = [Complex64(0.5, 0.0)]
    with assert_raises():
        _ = nr_redcap_rel17_ss_linear_measurements(
            capabilities,
            Span(sss),
            Span(measured),
            Span(interference),
            0,
            1,
            has_cd_ssb=True,
            has_ncd_ssb=False,
        )
    measured[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_redcap_rel17_ss_linear_measurements(
            capabilities,
            Span(sss),
            Span(measured),
            Span(interference),
            1,
            1,
            has_cd_ssb=True,
            has_ncd_ssb=False,
        )
    capabilities.ue_specific_dl_bwps_per_carrier = 2
    with assert_raises():
        _ = nr_redcap_rel17_ssb_measurement_source(
            capabilities, has_cd_ssb=True, has_ncd_ssb=False
        )
    with assert_raises():
        _ = nr_redcap_rel17_csi_linear_measurements(
            capabilities,
            Span(sss),
            Span(measured),
            Span(interference),
            1,
            1,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
