from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from wireless_dsp.wireless.lte import (
    LTE_RRM_NON_EDRX_DRX_ROW_COUNT,
    LTE_RRM_DRX_320_MS,
    LTE_RRM_DRX_640_MS,
    LTE_RRM_DRX_1280_MS,
    LTE_RRM_DRX_2560_MS,
    LTERRMServingCellConfig,
    lte_rrm_serving_cell_nserv,
    lte_rrm_minimum_filter_spacing_ms,
    lte_rrm_all_neighbour_measurements_required,
)


def _cycles() -> List[Int]:
    # Literal external-domain transcription; do not derive the oracle input
    # set from production constants.
    return [320, 640, 1280, 2560]


def _external_static_nserv(cycle_ms: Int) raises -> Int:
    # Independent literal transcription of TS 36.133 V18.14.0
    # Table 4.2.2.1-1.  This test oracle does not call production code.
    if cycle_ms == 320:
        return 4
    if cycle_ms == 640:
        return 4
    if cycle_ms == 1280:
        return 2
    if cycle_ms == 2560:
        return 2
    raise Error("test oracle received a non-table DRX cycle")


def _next(mut state: UInt64) -> UInt64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return state


def test_lte_rrm_table_4_2_2_1_1_all_rows_external_static_exact() raises:
    var cycles = _cycles()
    assert_equal(len(cycles), 4)
    assert_equal(LTE_RRM_NON_EDRX_DRX_ROW_COUNT, 4)
    for cycle_ms in cycles:
        var config = LTERRMServingCellConfig(cycle_ms)
        assert_equal(
            lte_rrm_serving_cell_nserv(config),
            _external_static_nserv(cycle_ms),
        )


def test_lte_rrm_filter_spacing_and_trigger_exhaustive() raises:
    var cycles = _cycles()
    for cycle_ms in cycles:
        var config = LTERRMServingCellConfig(cycle_ms)
        var nserv = _external_static_nserv(cycle_ms)
        assert_equal(lte_rrm_minimum_filter_spacing_ms(config), cycle_ms // 2)
        for failed_cycles in range(0, 7):
            assert_equal(
                lte_rrm_all_neighbour_measurements_required(
                    config, failed_cycles
                ),
                failed_cycles >= nserv,
            )


def test_lte_rrm_mutable_int_extremes_and_boundaries() raises:
    for invalid_cycle in [
        Int.MIN,
        -1,
        0,
        319,
        321,
        639,
        641,
        1279,
        1281,
        2559,
        2561,
        Int.MAX,
    ]:
        with assert_raises():
            _ = LTERRMServingCellConfig(invalid_cycle)

    var mutated = LTERRMServingCellConfig(320)
    mutated.drx_cycle_ms = 321
    with assert_raises():
        _ = lte_rrm_serving_cell_nserv(mutated)
    with assert_raises():
        _ = lte_rrm_minimum_filter_spacing_ms(mutated)
    with assert_raises():
        _ = lte_rrm_all_neighbour_measurements_required(mutated, 4)

    var valid = LTERRMServingCellConfig(2560)
    with assert_raises():
        _ = lte_rrm_all_neighbour_measurements_required(valid, Int.MIN)
    with assert_raises():
        _ = lte_rrm_all_neighbour_measurements_required(valid, -1)
    assert_true(lte_rrm_all_neighbour_measurements_required(valid, Int.MAX))


def test_lte_rrm_seeded_threshold_differential() raises:
    var cycles = _cycles()
    var state = UInt64(0x36133E0004220011)
    for _ in range(1024):
        var selector = _next(state)
        var cycle_ms = cycles[Int((selector >> 8) & 3)]
        var failed_cycles = Int((selector >> 16) & 15)
        var expected_nserv = _external_static_nserv(cycle_ms)
        var config = LTERRMServingCellConfig(cycle_ms)
        assert_equal(lte_rrm_serving_cell_nserv(config), expected_nserv)
        assert_equal(
            lte_rrm_minimum_filter_spacing_ms(config), cycle_ms // 2
        )
        assert_equal(
            lte_rrm_all_neighbour_measurements_required(
                config, failed_cycles
            ),
            failed_cycles >= expected_nserv,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
