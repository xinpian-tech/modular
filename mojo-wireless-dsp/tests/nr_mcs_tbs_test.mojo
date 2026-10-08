"""TS 38.214 V18.10.0 MCS and exact-integer TBS conformance tests."""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.nr.mcs_tbs import (
    NR_MCS_TABLE_QAM64,
    NR_MCS_TABLE_QAM256,
    NR_MCS_TABLE_QAM64_LOW_SE,
    NR_MCS_TABLE_QAM1024,
    NRMCSProfile,
    nr_mcs_profile,
    nr_mcs_target_code_rate,
    nr_mcs_spectral_efficiency,
    nr_pdsch_resource_elements_per_prb,
    nr_transport_block_size,
    nr_transport_block_allocation,
    _small_tbs_values,
    _transport_block_size_from_ratio,
)


def _expected_small_tbs() -> List[Int]:
    # TS 38.214 V18.10.0 Table 5.1.3.2-1, transcribed by table index.
    return [
        24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 120,
        128, 136, 144, 152, 160, 168, 176, 184, 192, 208, 224, 240,
        256, 272, 288, 304, 320, 336, 352, 368, 384, 408, 432, 456,
        480, 504, 528, 552, 576, 608, 640, 672, 704, 736, 768, 808,
        848, 888, 928, 984, 1032, 1064, 1128, 1160, 1192, 1224,
        1256, 1288, 1320, 1352, 1416, 1480, 1544, 1608, 1672, 1736,
        1800, 1864, 1928, 2024, 2088, 2152, 2216, 2280, 2408, 2472,
        2536, 2600, 2664, 2728, 2792, 2856, 2976, 3104, 3240, 3368,
        3496, 3624, 3752, 3824,
    ]


def _assert_mcs_table(
    table: Int, modulation_orders: List[Int], rates_x2048: List[Int]
) raises:
    assert_equal(len(modulation_orders), len(rates_x2048))
    for index in range(len(modulation_orders)):
        var profile = nr_mcs_profile(table, index)
        assert_equal(profile.table, table)
        assert_equal(profile.index, index)
        assert_equal(profile.modulation_order, modulation_orders[index])
        assert_equal(profile.target_code_rate_x2048, rates_x2048[index])
        assert_equal(
            nr_mcs_target_code_rate(profile),
            Float64(rates_x2048[index]) / 2048.0,
        )
        assert_equal(
            nr_mcs_spectral_efficiency(profile),
            (
                Float64(modulation_orders[index])
                * Float64(rates_x2048[index])
                / 2048.0
            ),
        )
    for reserved_index in range(len(modulation_orders), 32):
        with assert_raises():
            _ = nr_mcs_profile(table, reserved_index)


def _oracle_floor_log2_ratio(numerator: Int, denominator: Int) -> Int:
    # Test-local positive-rational oracle: scale the smaller side until the
    # half-open power-of-two interval containing the ratio is known.
    if numerator >= denominator:
        var result = 0
        var lower = denominator
        while lower * 2 <= numerator:
            lower *= 2
            result += 1
        return result
    var result = -1
    var upper = numerator * 2
    while upper < denominator:
        upper *= 2
        result -= 1
    return result


def _oracle_ceil_div(numerator: Int, denominator: Int) -> Int:
    return numerator // denominator + (1 if numerator % denominator else 0)


def _oracle_round_ties_up(numerator: Int, denominator: Int) -> Int:
    var whole = numerator // denominator
    var remainder = numerator % denominator
    return whole + (1 if 2 * remainder >= denominator else 0)


def _integer_spec_oracle_tbs(
    information_numerator: Int,
    information_denominator: Int,
    target_code_rate_x2048: Int,
) -> Int:
    # Independent integer transcription of TS 38.214 5.1.3.2 steps 3/4.
    if information_numerator <= 3824 * information_denominator:
        var n = max(
            3,
            _oracle_floor_log2_ratio(
                information_numerator, information_denominator
            ) - 6,
        )
        var quantum = Int(1) << n
        var quantized = max(
            24,
            quantum
            * (information_numerator // (information_denominator * quantum)),
        )
        for candidate in _expected_small_tbs():
            if candidate >= quantized:
                return candidate

    var shifted = information_numerator - 24 * information_denominator
    var n = _oracle_floor_log2_ratio(
        shifted, information_denominator
    ) - 5
    var quantum = Int(1) << n
    var quantized = max(
        3840,
        quantum
        * _oracle_round_ties_up(
            shifted, information_denominator * quantum
        ),
    )
    if target_code_rate_x2048 <= 512:
        var blocks = _oracle_ceil_div(quantized + 24, 3816)
        return (
            8 * blocks
            * _oracle_ceil_div(quantized + 24, 8 * blocks)
            - 24
        )
    if quantized > 8424:
        var blocks = _oracle_ceil_div(quantized + 24, 8424)
        return (
            8 * blocks
            * _oracle_ceil_div(quantized + 24, 8 * blocks)
            - 24
        )
    return 8 * _oracle_ceil_div(quantized + 24, 8) - 24


def test_all_four_normative_mcs_tables_and_reserved_rows() raises:
    _assert_mcs_table(
        NR_MCS_TABLE_QAM64,
        [
            2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
            4, 4, 4, 4, 4, 4, 4,
            6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
        ],
        [
            240, 314, 386, 502, 616, 758, 898, 1052, 1204, 1358,
            680, 756, 868, 980, 1106, 1232, 1316,
            876, 932, 1034, 1134, 1232, 1332, 1438, 1544, 1644,
            1746, 1820, 1896,
        ],
    )
    _assert_mcs_table(
        NR_MCS_TABLE_QAM256,
        [
            2, 2, 2, 2, 2,
            4, 4, 4, 4, 4, 4,
            6, 6, 6, 6, 6, 6, 6, 6, 6,
            8, 8, 8, 8, 8, 8, 8, 8,
        ],
        [
            240, 386, 616, 898, 1204,
            756, 868, 980, 1106, 1232, 1316,
            932, 1034, 1134, 1232, 1332, 1438, 1544, 1644, 1746,
            1365, 1422, 1508, 1594, 1682, 1770, 1833, 1896,
        ],
    )
    _assert_mcs_table(
        NR_MCS_TABLE_QAM64_LOW_SE,
        [
            2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
            4, 4, 4, 4, 4, 4,
            6, 6, 6, 6, 6, 6, 6, 6,
        ],
        [
            60, 80, 100, 128, 156, 198, 240, 314, 386, 502, 616,
            758, 898, 1052, 1204,
            680, 756, 868, 980, 1106, 1232,
            876, 932, 1034, 1134, 1232, 1332, 1438, 1544,
        ],
    )
    _assert_mcs_table(
        NR_MCS_TABLE_QAM1024,
        [
            2, 2, 2,
            4, 4, 4,
            6, 6, 6, 6, 6, 6, 6, 6, 6,
            8, 8, 8, 8, 8, 8, 8, 8,
            10, 10, 10, 10,
        ],
        [
            240, 386, 898,
            756, 980, 1232,
            932, 1034, 1134, 1232, 1332, 1438, 1544, 1644, 1746,
            1365, 1422, 1508, 1594, 1682, 1770, 1833, 1896,
            1611, 1706, 1801, 1896,
        ],
    )

    # The odd x2048 values are the exact representation of half-integer
    # R*1024 entries: 682.5, 916.5, 805.5, and 900.5.
    assert_equal(nr_mcs_profile(NR_MCS_TABLE_QAM256, 20).target_code_rate_x2048, 1365)
    assert_equal(nr_mcs_profile(NR_MCS_TABLE_QAM256, 26).target_code_rate_x2048, 1833)
    assert_equal(nr_mcs_profile(NR_MCS_TABLE_QAM1024, 23).target_code_rate_x2048, 1611)
    assert_equal(nr_mcs_profile(NR_MCS_TABLE_QAM1024, 25).target_code_rate_x2048, 1801)

    with assert_raises():
        _ = nr_mcs_profile(0, 0)
    with assert_raises():
        _ = nr_mcs_profile(NR_MCS_TABLE_QAM64, -1)
    with assert_raises():
        _ = nr_mcs_profile(NR_MCS_TABLE_QAM64, 32)
    with assert_raises():
        _ = NRMCSProfile(NR_MCS_TABLE_QAM64, 29, 2, 240)
    with assert_raises():
        _ = NRMCSProfile(NR_MCS_TABLE_QAM64, 0, 4, 240)
    var corrupted = nr_mcs_profile(NR_MCS_TABLE_QAM64, 0)
    corrupted.target_code_rate_x2048 = 314
    with assert_raises():
        corrupted.validate()


def test_complete_93_entry_small_tbs_table_and_selection() raises:
    var expected = _expected_small_tbs()
    var actual = _small_tbs_values()
    assert_equal(len(actual), 93)
    assert_equal(actual, expected)
    for index in range(93):
        assert_equal(
            _transport_block_size_from_ratio(expected[index], 1, 1232),
            expected[index],
        )


def test_integer_branch_boundaries_low_rate_8424_and_ties_up() raises:
    assert_equal(_transport_block_size_from_ratio(3824, 1, 1232), 3824)
    assert_equal(_transport_block_size_from_ratio(3825, 1, 1232), 3840)

    # At N_info=8344, n=8 and (N_info-24)/256=32.5.  V18.10.0 says
    # ties go to the next largest integer, yielding N_info'=8448.  A
    # ties-to-even implementation would incorrectly remain at 8192.
    assert_equal(_transport_block_size_from_ratio(8343, 1, 1232), 8192)
    assert_equal(_transport_block_size_from_ratio(8344, 1, 1232), 8456)

    # The R <= 1/4 branch is inclusive and uses the 3816-bit divisor.
    assert_equal(_transport_block_size_from_ratio(4040, 1, 512), 4040)
    assert_equal(_transport_block_size_from_ratio(4040, 1, 514), 4032)

    # Independent integer-oracle agreement on non-integer N_info values.
    for numerator in [38241, 45879, 66751, 83439, 83440, 130005]:
        for denominator in [2, 5, 10]:
            if numerator <= 3824 * denominator:
                continue
            for rate in [60, 512, 514, 1232, 1896]:
                assert_equal(
                    _transport_block_size_from_ratio(
                        numerator, denominator, rate
                    ),
                    _integer_spec_oracle_tbs(numerator, denominator, rate),
                )


def test_py3gpp_17b432_static_vectors_and_integer_property_grid() raises:
    # These vectors were generated independently with py3gpp nrTBS at
    # 17b432b30c965ffd350257ee4b1fc4de642c8e37.  Its Float inputs are exact
    # here (rates have denominator 2048; scaling is 1, 1/2, or 1/4).
    var tables: List[Int] = [3, 1, 2, 1, 4, 3, 1, 4, 4]
    var indices: List[Int] = [0, 9, 20, 16, 25, 4, 15, 26, 26]
    var prbs: List[Int] = [1, 5, 2, 20, 10, 275, 15, 50, 275]
    var re_per_prb: List[Int] = [12, 120, 100, 132, 144, 156, 120, 144, 156]
    var layers: List[Int] = [1, 1, 1, 2, 1, 8, 2, 4, 8]
    var scaling_denominators: List[Int] = [1, 1, 1, 2, 4, 1, 1, 1, 1]
    var expected: List[Int] = [
        24, 808, 1064, 6784, 3240, 52280, 8712, 270576, 3147560,
    ]
    for case_index in range(len(expected)):
        var profile = nr_mcs_profile(
            tables[case_index], indices[case_index]
        )
        assert_equal(
            nr_transport_block_size(
                prbs[case_index] * re_per_prb[case_index],
                profile,
                layers[case_index],
                tb_scaling_denominator=scaling_denominators[case_index],
            ),
            expected[case_index],
        )

    # Broad differential property test against a separately structured exact
    # integer oracle, spanning all 113 non-reserved rows and every scaling.
    var row_counts: List[Int] = [29, 28, 29, 27]
    var resource_counts: List[Int] = [1, 12, 156, 2640, 10000, 42900]
    var layer_counts: List[Int] = [1, 3, 8]
    for table_offset in range(4):
        var table = table_offset + 1
        for index in range(row_counts[table_offset]):
            var profile = nr_mcs_profile(table, index)
            for total_re in resource_counts:
                for layer_count in layer_counts:
                    for scale_denominator in [1, 2, 4]:
                        var numerator = (
                            total_re
                            * profile.modulation_order
                            * layer_count
                            * profile.target_code_rate_x2048
                        )
                        var denominator = 2048 * scale_denominator
                        var actual = nr_transport_block_size(
                            total_re,
                            profile,
                            layer_count,
                            tb_scaling_denominator=scale_denominator,
                        )
                        assert_equal(
                            actual,
                            _integer_spec_oracle_tbs(
                                numerator,
                                denominator,
                                profile.target_code_rate_x2048,
                            ),
                        )
                        assert_true(actual >= 24 and actual % 8 == 0)


def test_resource_accounting_scaling_canonicalization_and_edges() raises:
    assert_equal(nr_pdsch_resource_elements_per_prb(14, 0), 156)
    assert_equal(nr_pdsch_resource_elements_per_prb(14, 12), 156)
    assert_equal(nr_pdsch_resource_elements_per_prb(12, 12, 6), 126)

    var profile = nr_mcs_profile(NR_MCS_TABLE_QAM64, 16)
    var allocation = nr_transport_block_allocation(
        20,
        12,
        12,
        0,
        profile,
        2,
        tb_scaling_numerator=2,
        tb_scaling_denominator=4,
    )
    assert_equal(allocation.resource_elements_per_prb, 132)
    assert_equal(allocation.total_resource_elements, 2640)
    assert_equal(allocation.information_numerator, 27793920)
    assert_equal(allocation.information_denominator, 4096)
    assert_equal(allocation.transport_block_size, 6784)
    assert_equal(
        nr_transport_block_size(
            2640, profile, 2, tb_scaling_numerator=1,
            tb_scaling_denominator=2,
        ),
        allocation.transport_block_size,
    )

    var full = nr_transport_block_size(2640, profile, 2)
    var half = nr_transport_block_size(
        2640, profile, 2, tb_scaling_denominator=2
    )
    var quarter = nr_transport_block_size(
        2640, profile, 2, tb_scaling_denominator=4
    )
    assert_true(quarter <= half and half <= full)

    for invalid_scale_numerator in [0, -1]:
        with assert_raises():
            _ = nr_transport_block_size(
                100, profile, 1,
                tb_scaling_numerator=invalid_scale_numerator,
                tb_scaling_denominator=1,
            )
    with assert_raises():
        _ = nr_transport_block_size(
            100, profile, 1,
            tb_scaling_numerator=3, tb_scaling_denominator=4,
        )
    with assert_raises():
        _ = nr_transport_block_size(
            100, profile, 1,
            tb_scaling_numerator=1, tb_scaling_denominator=3,
        )
    with assert_raises():
        _ = nr_transport_block_size(
            100, profile, 1, tb_scaling_denominator=0
        )

    for invalid_symbols in [0, 15]:
        with assert_raises():
            _ = nr_pdsch_resource_elements_per_prb(invalid_symbols, 0)
    with assert_raises():
        _ = nr_pdsch_resource_elements_per_prb(12, -1)
    with assert_raises():
        _ = nr_pdsch_resource_elements_per_prb(12, 0, 1)
    with assert_raises():
        _ = nr_pdsch_resource_elements_per_prb(1, 12)
    with assert_raises():
        _ = nr_transport_block_size(0, profile, 1)
    with assert_raises():
        _ = nr_transport_block_size(275 * 156 + 1, profile, 1)
    with assert_raises():
        _ = nr_transport_block_size(100, profile, 0)
    with assert_raises():
        _ = nr_transport_block_size(100, profile, 9)
    with assert_raises():
        _ = nr_transport_block_allocation(0, 12, 12, 0, profile, 1)
    with assert_raises():
        _ = nr_transport_block_allocation(276, 12, 12, 0, profile, 1)


def test_resource_allocation_independent_integer_property_grid() raises:
    var tables: List[Int] = [
        NR_MCS_TABLE_QAM64,
        NR_MCS_TABLE_QAM256,
        NR_MCS_TABLE_QAM64_LOW_SE,
        NR_MCS_TABLE_QAM1024,
    ]
    var indices: List[Int] = [0, 20, 14, 26]
    for profile_index in range(len(tables)):
        var profile = nr_mcs_profile(
            tables[profile_index], indices[profile_index]
        )
        for symbol_count in [2, 7, 14]:
            for dmrs_re_per_prb in [0, 12, 24]:
                for overhead_re_per_prb in [0, 6, 12, 18]:
                    var available = (
                        12 * symbol_count
                        - dmrs_re_per_prb
                        - overhead_re_per_prb
                    )
                    if available < 1:
                        continue
                    var expected_per_prb = min(156, available)
                    assert_equal(
                        nr_pdsch_resource_elements_per_prb(
                            symbol_count,
                            dmrs_re_per_prb,
                            overhead_re_per_prb,
                        ),
                        expected_per_prb,
                    )
                    for scheduled_prbs in [1, 10, 275]:
                        for layers in [1, 4, 8]:
                            for scale_denominator in [1, 2, 4]:
                                var allocation = nr_transport_block_allocation(
                                    scheduled_prbs,
                                    symbol_count,
                                    dmrs_re_per_prb,
                                    overhead_re_per_prb,
                                    profile,
                                    layers,
                                    tb_scaling_denominator=scale_denominator,
                                )
                                var total = (
                                    scheduled_prbs * expected_per_prb
                                )
                                var numerator = (
                                    total
                                    * profile.modulation_order
                                    * layers
                                    * profile.target_code_rate_x2048
                                )
                                var denominator = 2048 * scale_denominator
                                assert_equal(
                                    allocation.resource_elements_per_prb,
                                    expected_per_prb,
                                )
                                assert_equal(
                                    allocation.total_resource_elements,
                                    total,
                                )
                                assert_equal(
                                    allocation.information_numerator,
                                    numerator,
                                )
                                assert_equal(
                                    allocation.information_denominator,
                                    denominator,
                                )
                                assert_equal(
                                    allocation.transport_block_size,
                                    _integer_spec_oracle_tbs(
                                        numerator,
                                        denominator,
                                        profile.target_code_rate_x2048,
                                    ),
                                )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
