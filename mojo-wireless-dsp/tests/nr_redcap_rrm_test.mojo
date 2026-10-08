"""Clause, edge, property, and differential evidence for RedCap RRM."""

from std.math import ceil
from std.testing import assert_equal, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.redcap_rrm import (
    NR_REDCAP_RRM_PROFILE_ORDINARY_NR,
    NR_REDCAP_RRM_PROFILE_REDCAP_REL17,
    NR_REDCAP_RRM_PROFILE_EREDCAP_REL18,
    NR_REDCAP_RRM_FR1,
    NR_REDCAP_RRM_FR2,
    NR_REDCAP_RRM_RS_SSB,
    NR_REDCAP_RRM_RS_CSI_RS,
    NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
    NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS,
    NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN,
    NR_REDCAP_RRM_L1_NO_INDICATION,
    NR_REDCAP_RRM_L1_OUT_OF_SYNC,
    NR_REDCAP_RRM_L1_IN_SYNC,
    NR_REDCAP_RRM_L1_BEAM_FAILURE_INSTANCE,
    nr_redcap_rel17_classify_link_quality,
    nr_redcap_rel17_rlm_evaluation_periods_us,
    nr_redcap_rel17_bfd_evaluation_period_us,
    nr_redcap_rel17_rlm_l1_indication,
    nr_redcap_rel17_bfd_l1_indication,
    nr_redcap_rel17_rlm_indication_interval_us,
    nr_redcap_rel17_bfd_indication_interval_us,
    nr_redcap_rel17_next_l1_indication_time_us,
)


def _independent_float_period_oracle(
    coefficient_numerator: Int,
    coefficient_denominator: Int,
    p_numerator: Int,
    p_denominator: Int,
    scaling: Int,
    base_period_us: Int,
    minimum_period_us: Int,
) -> Int:
    # Independent formulation used only on small exact test vectors.  The
    # implementation under test instead uses integer/rational Int128 math.
    var factor = Int(ceil(
        Float64(coefficient_numerator)
        * Float64(p_numerator)
        * Float64(scaling)
        / (
            Float64(coefficient_denominator)
            * Float64(p_denominator)
        )
    ))
    var value = factor * base_period_us
    return minimum_period_us if minimum_period_us > value else value


def _independent_max(lhs: Int, rhs: Int) -> Int:
    return lhs if lhs >= rhs else rhs


def test_rlm_static_clause_table_vectors() raises:
    var fr1_2rx_ssb = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        2,
        NR_REDCAP_RRM_RS_SSB,
        20000,
        False,
        0,
        1,
        1,
    )
    assert_equal(fr1_2rx_ssb[0], 200000)
    assert_equal(fr1_2rx_ssb[1], 100000)

    var fr1_1rx_ssb = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        1,
        NR_REDCAP_RRM_RS_SSB,
        20000,
        False,
        0,
        1,
        1,
    )
    assert_equal(fr1_1rx_ssb[0], 400000)
    assert_equal(fr1_1rx_ssb[1], 100000)

    var fr2_ssb = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR2,
        2,
        NR_REDCAP_RRM_RS_SSB,
        20000,
        False,
        0,
        1,
        1,
    )
    assert_equal(fr2_ssb[0], 1600000)
    assert_equal(fr2_ssb[1], 800000)

    var short_drx = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        2,
        NR_REDCAP_RRM_RS_SSB,
        20000,
        True,
        320000,
        1,
        1,
    )
    # Ceil(7.5) is performed before multiplication by Max(TDRX,TSSB).
    assert_equal(short_drx[0], 4800000)
    assert_equal(short_drx[1], 2560000)

    var long_drx = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        2,
        NR_REDCAP_RRM_RS_SSB,
        20000,
        True,
        512000,
        1,
        1,
    )
    assert_equal(long_drx[0], 5120000)
    assert_equal(long_drx[1], 2560000)

    var t310 = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        2,
        NR_REDCAP_RRM_RS_SSB,
        20000,
        True,
        512000,
        1,
        1,
        t310_running=True,
    )
    assert_equal(t310[0], 200000)
    assert_equal(t310[1], 100000)

    var rational_p = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        2,
        NR_REDCAP_RRM_RS_SSB,
        20000,
        False,
        0,
        4,
        3,
    )
    assert_equal(rational_p[0], 280000)
    assert_equal(rational_p[1], 140000)

    var csi_2rx = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        2,
        NR_REDCAP_RRM_RS_CSI_RS,
        10000,
        False,
        0,
        1,
        1,
        csi_rs_density=3,
        csi_rs_bandwidth_prbs=24,
    )
    assert_equal(csi_2rx[0], 200000)
    assert_equal(csi_2rx[1], 100000)

    var fr2_csi = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR2,
        2,
        NR_REDCAP_RRM_RS_CSI_RS,
        10000,
        False,
        0,
        1,
        1,
        csi_rs_density=3,
        csi_rs_bandwidth_prbs=132,
    )
    # CSI-RS uses N=1 in FR2, unlike the SSB N=8 branch above.
    assert_equal(fr2_csi[0], 200000)
    assert_equal(fr2_csi[1], 100000)

    var csi_1rx = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        1,
        NR_REDCAP_RRM_RS_CSI_RS,
        10000,
        False,
        0,
        1,
        1,
        csi_rs_density=3,
        csi_rs_bandwidth_prbs=106,
    )
    assert_equal(csi_1rx[0], 400000)
    assert_equal(csi_1rx[1], 100000)

    var csi_short = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        2,
        NR_REDCAP_RRM_RS_CSI_RS,
        10000,
        True,
        320000,
        4,
        3,
        csi_rs_density=3,
        csi_rs_bandwidth_prbs=48,
    )
    assert_equal(csi_short[0], 12800000)
    assert_equal(csi_short[1], 6400000)


def test_bfd_static_clause_table_vectors() raises:
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            1,
            1,
        ),
        100000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR2,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            5000,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=132,
        ),
        50000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            1,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            1,
            1,
        ),
        200000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR2,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            1,
            1,
        ),
        800000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            True,
            320000,
            1,
            1,
        ),
        2560000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            True,
            512000,
            1,
            1,
        ),
        2560000,
    )

    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            5000,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=24,
        ),
        50000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            1,
            NR_REDCAP_RRM_RS_CSI_RS,
            5000,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=48,
        ),
        100000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            10000,
            True,
            320000,
            4,
            3,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=48,
        ),
        6400000,
    )
    # Unlike CSI-RS RLM, clause 8.5B does not restrict CSI-RS BFD to
    # 5/10/20/40 ms.  These are slots4 at 15 kHz and 30 kHz respectively.
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            4000,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=24,
        ),
        50000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            2000,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=24,
        ),
        50000,
    )


def test_l1_aggregation_and_reporting_intervals() raises:
    assert_equal(
        nr_redcap_rel17_classify_link_quality(-6.0, -5.0, 5.0),
        NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
    )
    assert_equal(
        nr_redcap_rel17_classify_link_quality(-5.0, -5.0, 5.0),
        NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS,
    )
    assert_equal(
        nr_redcap_rel17_classify_link_quality(5.0, -5.0, 5.0),
        NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS,
    )
    assert_equal(
        nr_redcap_rel17_classify_link_quality(6.0, -5.0, 5.0),
        NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN,
    )

    var all_worse: List[Int] = [
        NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
        NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
    ]
    var mixed: List[Int] = [
        NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
        NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS,
    ]
    var recovered: List[Int] = [
        NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
        NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN,
    ]
    assert_equal(
        nr_redcap_rel17_rlm_l1_indication(Span(all_worse)),
        NR_REDCAP_RRM_L1_OUT_OF_SYNC,
    )
    assert_equal(
        nr_redcap_rel17_rlm_l1_indication(Span(mixed)),
        NR_REDCAP_RRM_L1_NO_INDICATION,
    )
    assert_equal(
        nr_redcap_rel17_rlm_l1_indication(Span(recovered)),
        NR_REDCAP_RRM_L1_IN_SYNC,
    )

    var all_bfd_worse: List[UInt8] = [1, 1, 1]
    var one_bfd_good: List[UInt8] = [1, 0, 1]
    assert_equal(
        nr_redcap_rel17_bfd_l1_indication(Span(all_bfd_worse)),
        NR_REDCAP_RRM_L1_BEAM_FAILURE_INSTANCE,
    )
    assert_equal(
        nr_redcap_rel17_bfd_l1_indication(Span(one_bfd_good)),
        NR_REDCAP_RRM_L1_NO_INDICATION,
    )

    var rs_types: List[Int] = [
        NR_REDCAP_RRM_RS_SSB, NR_REDCAP_RRM_RS_CSI_RS
    ]
    var rs_periods: List[Int] = [20000, 5000]
    assert_equal(
        nr_redcap_rel17_rlm_indication_interval_us(
            Span(rs_types), Span(rs_periods), False, 0
        ),
        10000,
    )
    assert_equal(
        nr_redcap_rel17_rlm_indication_interval_us(
            Span(rs_types), Span(rs_periods), True, 320000
        ),
        480000,
    )
    assert_equal(
        nr_redcap_rel17_rlm_indication_interval_us(
            Span(rs_types), Span(rs_periods), True, 512000
        ),
        512000,
    )
    assert_equal(
        nr_redcap_rel17_rlm_indication_interval_us(
            Span(rs_types),
            Span(rs_periods),
            True,
            512000,
            t310_running=True,
        ),
        10000,
    )

    assert_equal(
        nr_redcap_rel17_bfd_indication_interval_us(
            NR_REDCAP_RRM_RS_SSB, 20000, False, 0
        ),
        20000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_indication_interval_us(
            NR_REDCAP_RRM_RS_CSI_RS, 5000, False, 0
        ),
        5000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_indication_interval_us(
            NR_REDCAP_RRM_RS_CSI_RS, 4000, False, 0
        ),
        4000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_indication_interval_us(
            NR_REDCAP_RRM_RS_CSI_RS, 2000, False, 0
        ),
        2000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_indication_interval_us(
            NR_REDCAP_RRM_RS_CSI_RS, 5000, True, 320000
        ),
        480000,
    )
    assert_equal(
        nr_redcap_rel17_bfd_indication_interval_us(
            NR_REDCAP_RRM_RS_SSB, 20000, True, 512000
        ),
        512000,
    )

    assert_equal(nr_redcap_rel17_next_l1_indication_time_us(3000, 10000), 3000)
    assert_equal(
        nr_redcap_rel17_next_l1_indication_time_us(
            110000, 20000, previous_time_us=100000
        ),
        120000,
    )
    assert_equal(
        nr_redcap_rel17_next_l1_indication_time_us(
            150000, 20000, previous_time_us=100000
        ),
        150000,
    )


def test_exact_rational_property_and_independent_differential_oracle() raises:
    var p_numerators: List[Int] = [1, 4, 7, 9]
    var p_denominators: List[Int] = [1, 3, 5, 4]
    var previous_out = 0
    for index in range(len(p_numerators)):
        var p_num = p_numerators[index]
        var p_den = p_denominators[index]
        var rlm = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            p_num,
            p_den,
        )
        assert_equal(
            rlm[0],
            _independent_float_period_oracle(
                10, 1, p_num, p_den, 1, 20000, 200000
            ),
        )
        assert_equal(
            rlm[1],
            _independent_float_period_oracle(
                5, 1, p_num, p_den, 1, 20000, 100000
            ),
        )
        assert_equal(rlm[0] >= previous_out, True)
        previous_out = rlm[0]

        var fr2_bfd = nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR2,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            True,
            320000,
            p_num,
            p_den,
        )
        assert_equal(
            fr2_bfd,
            _independent_float_period_oracle(
                15, 2, p_num, p_den, 8, 320000, 50000
            ),
        )

    var csi_1rx = nr_redcap_rel17_rlm_evaluation_periods_us(
        NR_REDCAP_RRM_FR1,
        1,
        NR_REDCAP_RRM_RS_CSI_RS,
        40000,
        True,
        320000,
        7,
        5,
        csi_rs_density=3,
        csi_rs_bandwidth_prbs=24,
    )
    assert_equal(
        csi_1rx[0],
        _independent_float_period_oracle(
            120, 2, 7, 5, 1, 320000, 400000
        ),
    )
    assert_equal(
        csi_1rx[1],
        _independent_float_period_oracle(
            30, 2, 7, 5, 1, 320000, 100000
        ),
    )

    # Threshold classification is monotonic, with equality assigned to the
    # hysteresis region by the clause's strict worse/better comparisons.
    var qualities: List[Float64] = [-10.0, -5.0, 0.0, 5.0, 10.0]
    var expected_quality_states: List[Int] = [
        NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT,
        NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS,
        NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS,
        NR_REDCAP_RRM_QUALITY_BETWEEN_THRESHOLDS,
        NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN,
    ]
    for index in range(len(qualities)):
        assert_equal(
            nr_redcap_rel17_classify_link_quality(
                qualities[index], -5.0, 5.0
            ),
            expected_quality_states[index],
        )

    # Exhaustive two-resource aggregation is checked against independent
    # Boolean quantifiers and must be invariant under resource ordering.
    for first in range(3):
        for second in range(3):
            var states: List[Int] = [first, second]
            var reversed_states: List[Int] = [second, first]
            var expected = NR_REDCAP_RRM_L1_NO_INDICATION
            if (
                first == NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN
                or second == NR_REDCAP_RRM_QUALITY_BETTER_THAN_QIN
            ):
                expected = NR_REDCAP_RRM_L1_IN_SYNC
            elif (
                first == NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT
                and second == NR_REDCAP_RRM_QUALITY_WORSE_THAN_QOUT
            ):
                expected = NR_REDCAP_RRM_L1_OUT_OF_SYNC
            assert_equal(
                nr_redcap_rel17_rlm_l1_indication(Span(states)), expected
            )
            assert_equal(
                nr_redcap_rel17_rlm_l1_indication(Span(reversed_states)),
                expected,
            )

    for first in range(2):
        for second in range(2):
            var bfd_flags: List[UInt8] = [UInt8(first), UInt8(second)]
            var expected = (
                NR_REDCAP_RRM_L1_BEAM_FAILURE_INSTANCE
                if first == 1 and second == 1
                else NR_REDCAP_RRM_L1_NO_INDICATION
            )
            assert_equal(
                nr_redcap_rel17_bfd_l1_indication(Span(bfd_flags)), expected
            )

    var rs_types: List[Int] = [
        NR_REDCAP_RRM_RS_SSB, NR_REDCAP_RRM_RS_CSI_RS
    ]
    var rs_periods: List[Int] = [20000, 5000]
    var drx_cycles: List[Int] = [10000, 320000, 512000]
    for cycle in drx_cycles:
        var expected_rlm = cycle
        var expected_bfd = cycle
        if cycle <= 320000:
            expected_rlm = _independent_max(
                10000,
                _independent_max(3 * cycle // 2, 3 * 5000 // 2),
            )
            expected_bfd = _independent_max(
                3 * cycle // 2, 3 * 5000 // 2
            )
        assert_equal(
            nr_redcap_rel17_rlm_indication_interval_us(
                Span(rs_types), Span(rs_periods), True, cycle
            ),
            expected_rlm,
        )
        assert_equal(
            nr_redcap_rel17_bfd_indication_interval_us(
                NR_REDCAP_RRM_RS_CSI_RS, 5000, True, cycle
            ),
            expected_bfd,
        )

    var candidates: List[Int] = [90000, 120000, 150000]
    for candidate in candidates:
        assert_equal(
            nr_redcap_rel17_next_l1_indication_time_us(
                candidate, 20000, previous_time_us=100000
            ),
            _independent_max(candidate, 120000),
        )


def test_public_domain_nan_and_overflow_edges() raises:
    with assert_raises():
        _ = nr_redcap_rel17_classify_link_quality(
            nan[DType.float64](), -5.0, 5.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_classify_link_quality(
            inf[DType.float64](), -5.0, 5.0
        )
    with assert_raises():
        _ = nr_redcap_rel17_classify_link_quality(0.0, 5.0, 5.0)
    with assert_raises():
        _ = nr_redcap_rel17_classify_link_quality(
            0.0,
            -5.0,
            5.0,
            profile=NR_REDCAP_RRM_PROFILE_ORDINARY_NR,
        )
    with assert_raises():
        _ = nr_redcap_rel17_classify_link_quality(
            0.0,
            -5.0,
            5.0,
            profile=NR_REDCAP_RRM_PROFILE_EREDCAP_REL18,
        )

    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            3, 2, NR_REDCAP_RRM_RS_SSB, 20000, False, 0, 1, 1
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            3,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            1,
            1,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR2,
            1,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            1,
            1,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1, 2, 9, 20000, False, 0, 1, 1
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            30000,
            False,
            0,
            1,
            1,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            10000,
            1,
            1,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            True,
            321000,
            1,
            1,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            1,
            0,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            1,
            2,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            10000,
            False,
            0,
            1,
            1,
            csi_rs_density=1,
            csi_rs_bandwidth_prbs=24,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            10000,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=23,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            10000,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=107,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR2,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            10000,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=133,
        )
    with assert_raises():
        _ = nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            10000,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=24,
            csi_rs_repetition_on=True,
        )
    with assert_raises():
        _ = nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_CSI_RS,
            0,
            False,
            0,
            1,
            1,
            csi_rs_density=3,
            csi_rs_bandwidth_prbs=24,
        )
    with assert_raises():
        _ = nr_redcap_rel17_bfd_indication_interval_us(
            NR_REDCAP_RRM_RS_CSI_RS, -1, False, 0
        )
    with assert_raises():
        _ = nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            1,
            1,
            profile=NR_REDCAP_RRM_PROFILE_ORDINARY_NR,
        )
    with assert_raises():
        _ = nr_redcap_rel17_rlm_evaluation_periods_us(
            NR_REDCAP_RRM_FR1,
            2,
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            1,
            1,
            profile=NR_REDCAP_RRM_PROFILE_EREDCAP_REL18,
        )
    with assert_raises():
        _ = nr_redcap_rel17_bfd_evaluation_period_us(
            NR_REDCAP_RRM_FR2,
            2,
            NR_REDCAP_RRM_RS_SSB,
            160000,
            True,
            10240000,
            Int.MAX,
            1,
        )

    var empty_states: List[Int] = []
    with assert_raises():
        _ = nr_redcap_rel17_rlm_l1_indication(Span(empty_states))
    var invalid_states: List[Int] = [9]
    with assert_raises():
        _ = nr_redcap_rel17_rlm_l1_indication(Span(invalid_states))
    var invalid_flags: List[UInt8] = [2]
    with assert_raises():
        _ = nr_redcap_rel17_bfd_l1_indication(Span(invalid_flags))
    var late_invalid_flags: List[UInt8] = [0, 2]
    with assert_raises():
        _ = nr_redcap_rel17_bfd_l1_indication(Span(late_invalid_flags))

    var rs_types: List[Int] = [NR_REDCAP_RRM_RS_SSB]
    var no_periods: List[Int] = []
    with assert_raises():
        _ = nr_redcap_rel17_rlm_indication_interval_us(
            Span(rs_types), Span(no_periods), False, 0
        )
    var rs_periods: List[Int] = [20000]
    with assert_raises():
        _ = nr_redcap_rel17_rlm_indication_interval_us(
            Span(rs_types),
            Span(rs_periods),
            False,
            0,
            hd_fdd=True,
            hd_fdd_dl_sample_condition_met=False,
        )
    with assert_raises():
        _ = nr_redcap_rel17_bfd_indication_interval_us(
            NR_REDCAP_RRM_RS_SSB,
            20000,
            False,
            0,
            hd_fdd=True,
            hd_fdd_dl_sample_condition_met=False,
        )
    with assert_raises():
        _ = nr_redcap_rel17_next_l1_indication_time_us(
            0, 1, previous_time_us=Int.MAX
        )
    with assert_raises():
        _ = nr_redcap_rel17_next_l1_indication_time_us(-1, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
