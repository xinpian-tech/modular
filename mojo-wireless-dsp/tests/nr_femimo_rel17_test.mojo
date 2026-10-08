"""Independent clause evidence for bounded Rel-17 NR feMIMO algorithms."""

from std.testing import (
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
    TestSuite,
)
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.femimo_rel17 import (
    NRFeMIMORel17PortSelectionConfig,
    nr_femimo_rel17_port_selection_config,
    nr_femimo_rel17_ri_allowed,
    nr_femimo_rel17_i12_state_count,
    nr_femimo_rel17_i12_to_vector_indices,
    nr_femimo_rel17_vector_indices_to_i12,
    nr_femimo_rel17_strongest_coefficient_index,
    nr_femimo_rel17_strongest_coefficient_coordinates,
    nr_femimo_rel17_csi_coefficient_priority,
    nr_femimo_rel17_nonzero_coefficient_total,
)


def _oracle_parameter_values(
    param_combination: Int,
) -> Tuple[Int, Int, Int, Int, Int]:
    # Independent static transcription of TS 38.214 V17.16.0
    # Table 5.2.2.2.7-1: M, alpha numerator/denominator, beta numerator/
    # denominator.  This test deliberately does not call a production helper.
    var m: List[Int] = [1, 1, 1, 1, 2, 2, 2, 2]
    var alpha_num: List[Int] = [3, 1, 1, 1, 1, 3, 1, 1]
    var alpha_den: List[Int] = [4, 1, 1, 1, 2, 4, 1, 1]
    var beta_num: List[Int] = [1, 1, 3, 1, 1, 1, 1, 3]
    var beta_den: List[Int] = [2, 2, 4, 1, 2, 2, 2, 4]
    var index = param_combination - 1
    return (
        m[index],
        alpha_num[index],
        alpha_den[index],
        beta_num[index],
        beta_den[index],
    )


def _oracle_profile_legal(
    ports: Int, param_combination: Int, ri_bitmap: Int
) -> Bool:
    if (
        (param_combination == 1 or param_combination == 6)
        and (ports == 4 or ports == 12)
    ):
        return False
    if (
        (param_combination == 7 or param_combination == 8)
        and ports == 32
    ):
        return False
    return not (
        param_combination == 5
        and ports == 4
        and (ri_bitmap & 0xC) != 0
    )


def _oracle_choose(n: Int, k: Int) -> Int:
    # Independent factorial-ratio oracle.  The bounded domain has n <= 16,
    # so the unreduced numerator is exactly representable in Int128.  This
    # differs from the production implementation's stepwise reduced product.
    if k < 0 or k > n:
        return 0
    if k == 0 or k == n:
        return 1
    var numerator = Int128(1)
    var denominator = Int128(1)
    for index in range(k):
        numerator *= Int128(n - index)
        denominator *= Int128(index + 1)
    return Int(numerator // denominator)


def _oracle_i12(
    half_ports: Int, selected_vectors: Span[Int, ...]
) -> Int:
    var result = 0
    for index in range(len(selected_vectors)):
        result += _oracle_choose(
            half_ports - 1 - selected_vectors[index],
            len(selected_vectors) - index,
        )
    return result


def _small_expected_i12(index: Int) -> List[Int]:
    # Complete C(4,2)=6 ordering from the normative combinadic equation.
    if index == 0:
        return [2, 3]
    if index == 1:
        return [1, 3]
    if index == 2:
        return [1, 2]
    if index == 3:
        return [0, 3]
    if index == 4:
        return [0, 2]
    return [0, 1]


def test_table_5_2_2_2_7_1_and_restrictions_exhaustive() raises:
    var ports: List[Int] = [4, 8, 12, 16, 24, 32]
    # Bits 0/1 allow the 4-port paramCombination=5 profile while preserving
    # the exact special restriction on ranks above two.
    var ri_bitmap = 0x3
    for param_combination in range(1, 9):
        var expected = _oracle_parameter_values(param_combination)
        for port_index in range(len(ports)):
            var port_count = ports[port_index]
            var value_of_n = 0 if expected[0] == 1 else 2
            if _oracle_profile_legal(
                port_count, param_combination, ri_bitmap
            ):
                var config = nr_femimo_rel17_port_selection_config(
                    port_count,
                    param_combination,
                    ri_bitmap,
                    value_of_n,
                    1,
                )
                var expected_k1 = (
                    port_count * expected[1] // expected[2]
                )
                var expected_k0 = (
                    expected_k1 * expected[0] * expected[3]
                    // expected[4]
                )
                assert_equal(config.csi_rs_ports, port_count)
                assert_equal(config.param_combination, param_combination)
                assert_equal(config.ri_restriction_bitmap, ri_bitmap)
                assert_equal(config.frequency_vectors, expected[0])
                assert_equal(
                    config.alpha,
                    Float64(expected[1]) / Float64(expected[2]),
                )
                assert_equal(
                    config.beta,
                    Float64(expected[3]) / Float64(expected[4]),
                )
                assert_equal(config.selected_ports, expected_k1)
                assert_equal(config.selected_vectors, expected_k1 // 2)
                assert_equal(config.per_layer_nonzero_limit, expected_k0)
                config.validate()
            else:
                with assert_raises():
                    _ = nr_femimo_rel17_port_selection_config(
                        port_count,
                        param_combination,
                        ri_bitmap,
                        value_of_n,
                        1,
                    )

    # The third adjacent restriction is conditional on an enabled RI > 2.
    _ = nr_femimo_rel17_port_selection_config(4, 5, 0x3, 2, 1)
    with assert_raises():
        _ = nr_femimo_rel17_port_selection_config(4, 5, 0x4, 2, 1)
    with assert_raises():
        _ = nr_femimo_rel17_port_selection_config(4, 5, 0x8, 2, 1)


def test_ri_bitmap_and_m_n_r_semantics_exact() raises:
    var config = nr_femimo_rel17_port_selection_config(16, 6, 0xA, 4, 2)
    assert_false(nr_femimo_rel17_ri_allowed(config, 1))
    assert_true(nr_femimo_rel17_ri_allowed(config, 2))
    assert_false(nr_femimo_rel17_ri_allowed(config, 3))
    assert_true(nr_femimo_rel17_ri_allowed(config, 4))
    assert_equal(config.frequency_vectors, 2)
    assert_equal(config.value_of_n, 4)
    assert_equal(config.pmi_subbands_per_cqi_subband, 2)

    var m_one = nr_femimo_rel17_port_selection_config(16, 3, 0xF)
    assert_equal(m_one.frequency_vectors, 1)
    assert_equal(m_one.value_of_n, 0)
    assert_equal(m_one.pmi_subbands_per_cqi_subband, 1)


def test_i12_complete_six_state_external_static_vector() raises:
    var config = nr_femimo_rel17_port_selection_config(8, 5, 0xF, 2, 1)
    assert_equal(nr_femimo_rel17_i12_state_count(config), 6)
    for i12 in range(6):
        var actual = nr_femimo_rel17_i12_to_vector_indices(config, i12)
        var expected = _small_expected_i12(i12)
        assert_equal(actual, expected)
        assert_equal(
            nr_femimo_rel17_vector_indices_to_i12(
                config, Span(actual)
            ),
            i12,
        )


def test_i12_all_legal_profiles_exhaustive_analytic_oracle() raises:
    var ports: List[Int] = [4, 8, 12, 16, 24, 32]
    for param_combination in range(1, 9):
        var row = _oracle_parameter_values(param_combination)
        for port_index in range(len(ports)):
            var port_count = ports[port_index]
            if not _oracle_profile_legal(
                port_count, param_combination, 0x3
            ):
                continue
            var value_of_n = 0 if row[0] == 1 else 2
            var config = nr_femimo_rel17_port_selection_config(
                port_count,
                param_combination,
                0x3,
                value_of_n,
                1,
            )
            var expected_states = _oracle_choose(
                port_count // 2, config.selected_vectors
            )
            assert_equal(
                nr_femimo_rel17_i12_state_count(config), expected_states
            )
            for i12 in range(expected_states):
                var decoded = nr_femimo_rel17_i12_to_vector_indices(
                    config, i12
                )
                assert_equal(len(decoded), config.selected_vectors)
                for index in range(len(decoded)):
                    assert_true(decoded[index] >= 0)
                    assert_true(decoded[index] < port_count // 2)
                    if index > 0:
                        assert_true(decoded[index] > decoded[index - 1])
                assert_equal(
                    _oracle_i12(port_count // 2, Span(decoded)), i12
                )
                assert_equal(
                    nr_femimo_rel17_vector_indices_to_i12(
                        config, Span(decoded)
                    ),
                    i12,
                )


def test_coefficient_indices_priorities_and_nonzero_caps_exact() raises:
    var config = nr_femimo_rel17_port_selection_config(16, 6, 0xF, 4, 2)
    assert_equal(config.selected_ports, 12)
    assert_equal(config.frequency_vectors, 2)
    assert_equal(config.per_layer_nonzero_limit, 12)
    for frequency_index in range(config.frequency_vectors):
        for vector_index in range(config.selected_ports):
            var expected_i18 = (
                config.selected_ports * frequency_index + vector_index
            )
            var actual_i18 = nr_femimo_rel17_strongest_coefficient_index(
                config, vector_index, frequency_index
            )
            assert_equal(actual_i18, expected_i18)
            var coordinates = (
                nr_femimo_rel17_strongest_coefficient_coordinates(
                    config, actual_i18
                )
            )
            assert_equal(coordinates[0], vector_index)
            assert_equal(coordinates[1], frequency_index)

    for layers in range(1, 5):
        for frequency_index in range(config.frequency_vectors):
            for vector_index in range(config.selected_ports):
                for layer_index in range(layers):
                    var expected_priority = (
                        config.selected_ports
                        * layers
                        * frequency_index
                        + layers * vector_index
                        + layer_index
                        + 1
                    )
                    assert_equal(
                        nr_femimo_rel17_csi_coefficient_priority(
                            config,
                            layers,
                            layer_index,
                            vector_index,
                            frequency_index,
                        ),
                        expected_priority,
                    )

    var rank_one: List[Int] = [12]
    var rank_two: List[Int] = [7, 12]
    var rank_four: List[Int] = [3, 4, 5, 6]
    assert_equal(
        nr_femimo_rel17_nonzero_coefficient_total(
            config, Span(rank_one)
        ),
        12,
    )
    assert_equal(
        nr_femimo_rel17_nonzero_coefficient_total(
            config, Span(rank_two)
        ),
        19,
    )
    assert_equal(
        nr_femimo_rel17_nonzero_coefficient_total(
            config, Span(rank_four)
        ),
        18,
    )


def test_seeded_property_and_differential_oracles() raises:
    var config = nr_femimo_rel17_port_selection_config(32, 5, 0xF, 4, 2)
    var state_count = nr_femimo_rel17_i12_state_count(config)
    assert_equal(state_count, 12870)
    var seed = UInt64(0x243F6A8885A308D3)
    for _ in range(1025):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var i12 = Int(seed % UInt64(state_count))
        var decoded = nr_femimo_rel17_i12_to_vector_indices(config, i12)
        assert_equal(
            _oracle_i12(config.csi_rs_ports // 2, Span(decoded)), i12
        )
        assert_equal(
            nr_femimo_rel17_vector_indices_to_i12(
                config, Span(decoded)
            ),
            i12,
        )

        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var layers = 1 + Int(seed & UInt64(3))
        var layer = Int((seed >> 8) % UInt64(layers))
        var vector = Int((seed >> 16) % UInt64(config.selected_ports))
        var frequency = Int(
            (seed >> 32) % UInt64(config.frequency_vectors)
        )
        var expected = (
            config.selected_ports * layers * frequency
            + layers * vector
            + layer
            + 1
        )
        assert_equal(
            nr_femimo_rel17_csi_coefficient_priority(
                config, layers, layer, vector, frequency
            ),
            expected,
        )
        var i18 = nr_femimo_rel17_strongest_coefficient_index(
            config, vector, frequency
        )
        var inverse = nr_femimo_rel17_strongest_coefficient_coordinates(
            config, i18
        )
        assert_equal(inverse[0], vector)
        assert_equal(inverse[1], frequency)

        var counts = List[Int](capacity=layers)
        var expected_total = 0
        for count_layer in range(layers):
            var count = 1 + Int(
                (seed >> UInt64(count_layer * 8)) % UInt64(4)
            )
            counts.append(count)
            expected_total += count
        assert_equal(
            nr_femimo_rel17_nonzero_coefficient_total(
                config, Span(counts)
            ),
            expected_total,
        )


def test_invalid_extreme_and_mutable_state_boundaries() raises:
    for invalid_ports in [Int.MIN, -1, 0, 6, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_port_selection_config(
                invalid_ports, 2, 0xF
            )
    for invalid_parameter in [Int.MIN, 0, 9, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_port_selection_config(
                8, invalid_parameter, 0xF
            )
    for invalid_bitmap in [Int.MIN, -1, 16, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_port_selection_config(
                8, 2, invalid_bitmap
            )
    with assert_raises():
        _ = nr_femimo_rel17_port_selection_config(8, 2, 0xF, 2, 1)
    with assert_raises():
        _ = nr_femimo_rel17_port_selection_config(8, 2, 0xF, 0, 2)
    for invalid_n in [Int.MIN, 0, 1, 3, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_port_selection_config(
                8, 5, 0xF, invalid_n, 1
            )
    for invalid_r in [Int.MIN, 0, 3, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_port_selection_config(
                8, 5, 0xF, 2, invalid_r
            )

    var config = nr_femimo_rel17_port_selection_config(8, 5, 0xF, 2, 1)
    for invalid_layers in [Int.MIN, 0, 5, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_ri_allowed(config, invalid_layers)
    for invalid_i12 in [Int.MIN, -1, 6, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_i12_to_vector_indices(config, invalid_i12)

    var empty: List[Int] = []
    var short: List[Int] = [0]
    var duplicate: List[Int] = [1, 1]
    var descending: List[Int] = [2, 1]
    var negative: List[Int] = [-1, 2]
    var extreme: List[Int] = [0, Int.MAX]
    with assert_raises():
        _ = nr_femimo_rel17_vector_indices_to_i12(config, Span(empty))
    with assert_raises():
        _ = nr_femimo_rel17_vector_indices_to_i12(config, Span(short))
    with assert_raises():
        _ = nr_femimo_rel17_vector_indices_to_i12(
            config, Span(duplicate)
        )
    with assert_raises():
        _ = nr_femimo_rel17_vector_indices_to_i12(
            config, Span(descending)
        )
    with assert_raises():
        _ = nr_femimo_rel17_vector_indices_to_i12(config, Span(negative))
    with assert_raises():
        _ = nr_femimo_rel17_vector_indices_to_i12(config, Span(extreme))

    for invalid_vector in [Int.MIN, -1, 4, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_strongest_coefficient_index(
                config, invalid_vector, 0
            )
    for invalid_frequency in [Int.MIN, -1, 2, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_strongest_coefficient_index(
                config, 0, invalid_frequency
            )
    for invalid_i18 in [Int.MIN, -1, 8, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_strongest_coefficient_coordinates(
                config, invalid_i18
            )

    var rank_two_only = nr_femimo_rel17_port_selection_config(
        8, 5, 0x2, 2, 1
    )
    for invalid_layers in [Int.MIN, 0, 5, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_csi_coefficient_priority(
                rank_two_only, invalid_layers, 0, 0, 0
            )
    with assert_raises():
        _ = nr_femimo_rel17_csi_coefficient_priority(
            rank_two_only, 1, 0, 0, 0
        )
    for invalid_layer_index in [Int.MIN, -1, 2, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_csi_coefficient_priority(
                rank_two_only, 2, invalid_layer_index, 0, 0
            )
    with assert_raises():
        _ = nr_femimo_rel17_csi_coefficient_priority(
            rank_two_only, 2, 2, 0, 0
        )
    for invalid_vector in [Int.MIN, -1, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_csi_coefficient_priority(
                rank_two_only, 2, 0, invalid_vector, 0
            )
    for invalid_frequency in [Int.MIN, -1, Int.MAX]:
        with assert_raises():
            _ = nr_femimo_rel17_csi_coefficient_priority(
                rank_two_only, 2, 0, 0, invalid_frequency
            )

    var zero: List[Int] = [0]
    var negative_count: List[Int] = [Int.MIN]
    var too_large: List[Int] = [5]
    var total_too_large: List[Int] = [3, 3, 3, 3]
    var too_many_layers: List[Int] = [1, 1, 1, 1, 1]
    with assert_raises():
        _ = nr_femimo_rel17_nonzero_coefficient_total(
            config, Span(empty)
        )
    with assert_raises():
        _ = nr_femimo_rel17_nonzero_coefficient_total(config, Span(zero))
    with assert_raises():
        _ = nr_femimo_rel17_nonzero_coefficient_total(
            config, Span(negative_count)
        )
    with assert_raises():
        _ = nr_femimo_rel17_nonzero_coefficient_total(
            config, Span(too_large)
        )
    with assert_raises():
        _ = nr_femimo_rel17_nonzero_coefficient_total(
            config, Span(total_too_large)
        )
    with assert_raises():
        _ = nr_femimo_rel17_nonzero_coefficient_total(
            config, Span(too_many_layers)
        )
    var one_count: List[Int] = [1]
    with assert_raises():
        _ = nr_femimo_rel17_nonzero_coefficient_total(
            rank_two_only, Span(one_count)
        )

    # Every public consumer must reject mutable-state corruption.  NaN and
    # infinities are applicable to the exact binary alpha/beta fields even
    # though all external algorithm indices are integral.
    var valid_vectors: List[Int] = [2, 3]
    var valid_counts: List[Int] = [1]
    config.alpha = nan[DType.float64]()
    with assert_raises():
        _ = nr_femimo_rel17_ri_allowed(config, 1)
    with assert_raises():
        _ = nr_femimo_rel17_i12_state_count(config)
    with assert_raises():
        _ = nr_femimo_rel17_i12_to_vector_indices(config, 0)
    with assert_raises():
        _ = nr_femimo_rel17_vector_indices_to_i12(
            config, Span(valid_vectors)
        )
    with assert_raises():
        _ = nr_femimo_rel17_strongest_coefficient_index(config, 0, 0)
    with assert_raises():
        _ = nr_femimo_rel17_strongest_coefficient_coordinates(config, 0)
    with assert_raises():
        _ = nr_femimo_rel17_csi_coefficient_priority(
            config, 1, 0, 0, 0
        )
    with assert_raises():
        _ = nr_femimo_rel17_nonzero_coefficient_total(
            config, Span(valid_counts)
        )

    config = nr_femimo_rel17_port_selection_config(8, 5, 0xF, 2, 1)
    config.alpha = inf[DType.float64]()
    with assert_raises():
        _ = nr_femimo_rel17_i12_state_count(config)
    config = nr_femimo_rel17_port_selection_config(8, 5, 0xF, 2, 1)
    config.beta = -inf[DType.float64]()
    with assert_raises():
        _ = nr_femimo_rel17_i12_state_count(config)
    config = nr_femimo_rel17_port_selection_config(8, 5, 0xF, 2, 1)
    config.selected_ports = Int.MAX
    with assert_raises():
        _ = nr_femimo_rel17_i12_state_count(config)
    config = nr_femimo_rel17_port_selection_config(8, 5, 0xF, 2, 1)
    config.ri_restriction_bitmap = Int.MIN
    with assert_raises():
        _ = nr_femimo_rel17_i12_state_count(config)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
