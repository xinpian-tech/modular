"""Independent exact evidence for TS 38.211 PDSCH layer mapping."""

from std.testing import assert_equal, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.layer_mapping import (
    NRPDSCHCodewordLayerAllocation,
    NRPDSCHLayerMapping,
    nr_pdsch_codeword_layer_allocation,
    nr_pdsch_layer_map,
    nr_pdsch_layer_demap,
)


def _symbols(count: Int, offset: Int) -> List[Complex64]:
    var result = List[Complex64](capacity=count)
    for index in range(count):
        result.append(
            Complex64(
                Float64(offset + index + 1),
                -Float64(2 * offset + index + 1),
            )
        )
    return result^


def _assert_complex_equal(actual: Complex64, expected: Complex64) raises:
    assert_equal(actual.re, expected.re)
    assert_equal(actual.im, expected.im)


def test_complete_normative_codeword_layer_partition_table() raises:
    var first_layers: List[Int] = [1, 2, 3, 4, 2, 3, 3, 4]
    var second_layers: List[Int] = [0, 0, 0, 0, 3, 3, 4, 4]
    for layer_count in range(1, 9):
        var allocation = nr_pdsch_codeword_layer_allocation(layer_count)
        assert_equal(allocation.layer_count, layer_count)
        assert_equal(
            allocation.codeword_count, 1 if layer_count <= 4 else 2
        )
        assert_equal(
            allocation.codeword0_layers, first_layers[layer_count - 1]
        )
        assert_equal(
            allocation.codeword1_layers, second_layers[layer_count - 1]
        )


def test_all_eight_layer_mapping_rows_match_independent_index_oracle() raises:
    var first_layers: List[Int] = [1, 2, 3, 4, 2, 3, 3, 4]
    var second_layers: List[Int] = [0, 0, 0, 0, 3, 3, 4, 4]
    for layer_count in range(1, 9):
        var first = first_layers[layer_count - 1]
        var second = second_layers[layer_count - 1]
        var codeword0 = _symbols(3 * first, 0)
        var codeword1 = _symbols(3 * second, 1000)
        var mapping = nr_pdsch_layer_map(
            Span(codeword0), Span(codeword1), layer_count
        )
        assert_equal(mapping.layer_count, layer_count)
        assert_equal(mapping.symbols_per_layer, 3)
        for symbol in range(3):
            for layer in range(first):
                _assert_complex_equal(
                    mapping[layer, symbol],
                    codeword0[first * symbol + layer],
                )
            for local_layer in range(second):
                _assert_complex_equal(
                    mapping[first + local_layer, symbol],
                    codeword1[second * symbol + local_layer],
                )


def test_seeded_map_demap_property_and_independent_formula() raises:
    var seed = UInt64(0x382117313C0DE)
    var first_layers: List[Int] = [1, 2, 3, 4, 2, 3, 3, 4]
    for _ in range(193):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var layer_count = 1 + Int(seed % UInt64(8))
        var symbols_per_layer = 1 + Int((seed >> 9) % UInt64(17))
        var first = first_layers[layer_count - 1]
        var second = layer_count - first
        var offset = Int((seed >> 17) % UInt64(10000))
        var codeword0 = _symbols(first * symbols_per_layer, offset)
        var codeword1 = _symbols(
            second * symbols_per_layer, offset + 20000
        )
        var mapping = nr_pdsch_layer_map(
            Span(codeword0), Span(codeword1), layer_count
        )
        for symbol in range(symbols_per_layer):
            for layer in range(first):
                _assert_complex_equal(
                    mapping[layer, symbol],
                    codeword0[first * symbol + layer],
                )
            for local_layer in range(second):
                _assert_complex_equal(
                    mapping[first + local_layer, symbol],
                    codeword1[second * symbol + local_layer],
                )
        var recovered = nr_pdsch_layer_demap(mapping)
        assert_equal(len(recovered.codeword0), len(codeword0))
        assert_equal(len(recovered.codeword1), len(codeword1))
        for index in range(len(codeword0)):
            _assert_complex_equal(recovered.codeword0[index], codeword0[index])
        for index in range(len(codeword1)):
            _assert_complex_equal(recovered.codeword1[index], codeword1[index])


def test_invalid_dimensions_nonfinite_values_and_mutation_edges() raises:
    with assert_raises():
        _ = nr_pdsch_codeword_layer_allocation(0)
    with assert_raises():
        _ = nr_pdsch_codeword_layer_allocation(9)

    var empty = List[Complex64]()
    var empty_other = List[Complex64]()
    var one = _symbols(1, 0)
    var one_other = _symbols(1, 100)
    var two = _symbols(2, 0)
    with assert_raises():
        _ = nr_pdsch_layer_map(Span(empty), Span(empty_other), 1)
    with assert_raises():
        _ = nr_pdsch_layer_map(Span(one), Span(one_other), 1)
    with assert_raises():
        _ = nr_pdsch_layer_map(Span(one), Span(empty), 2)
    with assert_raises():
        _ = nr_pdsch_layer_map(Span(two), Span(empty), 5)
    with assert_raises():
        _ = nr_pdsch_layer_map(Span(two), Span(one), 5)

    var nonfinite: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = nr_pdsch_layer_map(Span(nonfinite), Span(empty), 1)
    nonfinite[0] = Complex64(0.0, inf[DType.float64]())
    with assert_raises():
        _ = nr_pdsch_layer_map(Span(nonfinite), Span(empty), 1)

    var allocation = nr_pdsch_codeword_layer_allocation(5)
    allocation.codeword0_layers = 3
    with assert_raises():
        allocation.validate()

    var mapping = nr_pdsch_layer_map(Span(two), Span(empty), 2)
    with assert_raises():
        _ = mapping[-1, 0]
    mapping.symbols_per_layer = 2
    with assert_raises():
        _ = nr_pdsch_layer_demap(mapping)


def test_exact_zero_and_float64_extreme_values_are_preserved() raises:
    var codeword0: List[Complex64] = [
        Complex64(-0.0, 0.0),
        Complex64(Float64.MAX_FINITE, -Float64.MAX_FINITE),
        Complex64(5.0e-324, -5.0e-324),
        Complex64(-7.0, 9.0),
    ]
    var empty = List[Complex64]()
    var mapping = nr_pdsch_layer_map(
        Span(codeword0), Span(empty), 2
    )
    var recovered = nr_pdsch_layer_demap(mapping)
    for index in range(len(codeword0)):
        _assert_complex_equal(recovered.codeword0[index], codeword0[index])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
