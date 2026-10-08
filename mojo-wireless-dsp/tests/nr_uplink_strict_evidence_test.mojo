"""Strict boundary evidence for NR uplink, UCI, and PRACH primitives."""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr import (
    NRResourceGrid,
    NRPRACHFormat,
    NRPRACHOccasion,
    NRPUSCHConfig,
    NRPUCCHFormat2Config,
    PRACH_SET_UNRESTRICTED,
    nr_pusch_descramble_llrs,
    nr_pusch_transform_precoding,
    nr_pusch_transform_deprecoding,
    nr_pusch_dmrs_c_init,
    nr_map_pusch_single_layer,
    nr_pusch_grid_to_waveform,
    nr_prach_sequence,
    nr_detect_prach_unrestricted,
    nr_pucch_cyclic_shift_index,
    nr_pucch_block_spread,
    nr_pucch_block_despread,
    nr_pucch_format1_apply_occ,
    nr_pucch_format2_dmrs_c_init,
    nr_pucch_format2_data_re_count,
    nr_pucch_format2_dmrs_re_count,
    nr_map_pucch_format2,
    nr_pucch_format2_descramble_llrs,
    nr_pucch_uci_capacity,
    nr_uci_code_block_count,
    nr_uci_decode,
    nr_prach_sequence_standard,
    nr_prach_frequency_sequence,
    nr_prach_normalized_cp_samples,
    nr_prach_normalized_waveform,
    nr_detect_prach_multi_root,
    nr_prach_occasion_is_active,
)


def test_pusch_descrambler_rejects_nonfinite_soft_values() raises:
    var invalid: List[Float64] = [1.0, nan[DType.float64](), -2.0]
    with assert_raises():
        _ = nr_pusch_descramble_llrs(Span(invalid), 0x1234, 0, 17)
    invalid[1] = inf[DType.float64]()
    with assert_raises():
        _ = nr_pusch_descramble_llrs(Span(invalid), 0x1234, 0, 17)

    var finite: List[Float64] = [1.0, -2.0, 3.0]
    var result = nr_pusch_descramble_llrs(Span(finite), 0, 0, 0)
    assert_equal(len(result), len(finite))
    for value in result:
        assert_true(value in (-3.0, -2.0, -1.0, 1.0, 2.0, 3.0))


def test_pusch_transforms_reject_nonfinite_and_unrepresentable_outputs() raises:
    var values = List[Complex64](length=12, fill=Complex64(0.0, 0.0))
    values[3] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_pusch_transform_precoding(Span(values))
    values[3] = Complex64(0.0, inf[DType.float64]())
    with assert_raises():
        _ = nr_pusch_transform_deprecoding(Span(values))

    # Every input is finite, but the DC bin of a unitary 12-point DFT is
    # sqrt(12)*1e308 and therefore cannot be represented as Float64.
    for index in range(12):
        values[index] = Complex64(1.0e308, 0.0)
    with assert_raises():
        _ = nr_pusch_transform_precoding(Span(values))


def test_pusch_dmrs_c_init_extreme_slot_uses_exact_modular_arithmetic() raises:
    # For slot=2^63-1 and symbol=12, (14*slot+13) mod 2^31 is 2^31-1.
    # Reducing the remaining factors gives the independently derived 0x3ffff.
    assert_equal(
        nr_pusch_dmrs_c_init(Int.MAX, 12, 65535, 1),
        UInt32(0x0003FFFF),
    )
    # At symbol=13 the time factor is exactly zero modulo 2^31.
    assert_equal(
        nr_pusch_dmrs_c_init(Int.MAX, 13, 65535, 1),
        UInt32(0x0001FFFF),
    )
    for slot in [0, 1, 17, 100000]:
        for symbol in [0, 6, 13]:
            for n_id in [0, 321, 65535]:
                for n_scid in [0, 1]:
                    var modulus = UInt64(1) << UInt64(31)
                    var time_term = (
                        UInt64(14) * (UInt64(slot) % modulus)
                        + UInt64(symbol + 1)
                    ) % modulus
                    var expected = (
                        (((UInt64(1) << UInt64(17)) * time_term)
                            % modulus)
                        * UInt64(2 * n_id + 1)
                        + UInt64(2 * n_id + n_scid)
                    ) % modulus
                    assert_equal(
                        nr_pusch_dmrs_c_init(
                            slot, symbol, n_id, n_scid
                        ),
                        UInt32(expected),
                    )


def test_prach_detector_is_scale_invariant_and_rejects_nonfinite() raises:
    var transmitted = nr_prach_sequence(1, 139, 26)
    var large = List[Complex64](capacity=139)
    for sample in transmitted:
        large.append(Complex64(sample.re * 1.0e308, sample.im * 1.0e308))
    var detection = nr_detect_prach_unrestricted(Span(large), 1, 13, 8)
    assert_equal(detection.preamble_index, 2)
    assert_equal(detection.cyclic_shift, 26)
    assert_true(abs(detection.metric - 1.0) < 1.0e-12)

    large[17] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_detect_prach_unrestricted(Span(large), 1, 13, 8)
    large[17] = Complex64(0.0, inf[DType.float64]())
    with assert_raises():
        _ = nr_detect_prach_unrestricted(Span(large), 1, 13, 8)


def test_pucch_uci_capacity_checks_integer_products() raises:
    assert_equal(nr_pucch_uci_capacity(2, 3, 2), 96)
    assert_equal(
        nr_pucch_uci_capacity(
            3, 2, 8, spreading_factor=2, pi_over_2_bpsk=True
        ),
        96,
    )
    with assert_raises():
        _ = nr_pucch_uci_capacity(2, Int.MAX, Int.MAX)
    with assert_raises():
        _ = nr_pucch_uci_capacity(3, Int.MAX, 1)
    with assert_raises():
        _ = nr_pucch_uci_capacity(4, 1, Int.MAX, spreading_factor=2)


def test_uci_code_block_range_and_downstream_finite_validation() raises:
    assert_equal(nr_uci_code_block_count(11, 8192), 1)
    assert_equal(nr_uci_code_block_count(400, 16384), 2)
    with assert_raises():
        _ = nr_uci_code_block_count(11, 8193)
    with assert_raises():
        _ = nr_uci_code_block_count(400, 16385)
    with assert_raises():
        _ = nr_uci_code_block_count(3, Int.MAX)

    # These are deliberately asserted at the UCI facade.  Its small-block
    # and Polar callees own the finite checks, avoiding duplicate scans.
    var small_llrs = List[Float64](length=32, fill=1.0)
    small_llrs[5] = nan[DType.float64]()
    with assert_raises():
        _ = nr_uci_decode(Span(small_llrs), 7)
    var polar_llrs = List[Float64](length=96, fill=1.0)
    polar_llrs[5] = inf[DType.float64]()
    with assert_raises():
        _ = nr_uci_decode(Span(polar_llrs), 12)


def test_pucch_sequence_and_spreading_numeric_boundaries() raises:
    with assert_raises():
        _ = nr_pucch_cyclic_shift_index(Int.MAX, 0, 0, 0, 0)
    with assert_raises():
        _ = nr_pucch_cyclic_shift_index(0, 0, 0, 0, 0, symbols_per_slot=13)

    var symbols = List[Complex64](length=4, fill=Complex64(1.0, 0.0))
    symbols[2] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_pucch_block_spread(Span(symbols), 4, 0)
    symbols[2] = Complex64(1.0, inf[DType.float64]())
    with assert_raises():
        _ = nr_pucch_block_despread(Span(symbols), 4, 0)
    for index in range(4):
        symbols[index] = Complex64(1.0e308, 0.0)
    with assert_raises():
        _ = nr_pucch_block_despread(Span(symbols), 4, 0)

    var occ: List[Complex64] = [Complex64(1.0, 0.0)]
    symbols[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_pucch_format1_apply_occ(Span(symbols), Span(occ))


def test_pucch_resource_products_c_init_and_atomic_finite_rejection() raises:
    assert_equal(
        nr_pucch_format2_dmrs_c_init(Int.MAX, 12, 65535),
        UInt32(0x0003FFFE),
    )
    with assert_raises():
        _ = nr_pucch_format2_data_re_count(Int.MAX, Int.MAX)
    with assert_raises():
        _ = nr_pucch_format2_dmrs_re_count(Int.MAX, 1)

    var grid = NRResourceGrid(14, 24)
    var data = List[Complex64](length=8, fill=Complex64(1.0, 0.0))
    var dmrs = List[Complex64](length=4, fill=Complex64(0.0, 1.0))
    data[7] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        nr_map_pucch_format2(grid, 0, 0, 1, 1, Span(data), Span(dmrs))
    # Validation is performed before the first grid write.
    for value in grid.values:
        assert_equal(value, Complex64(0.0, 0.0))


def test_standard_prach_numeric_and_format_boundaries() raises:
    var time = nr_prach_sequence_standard(1, 139, 0)
    time[5] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_prach_frequency_sequence(Span(time))
    for index in range(139):
        time[index] = Complex64(1.0e308, 0.0)
    with assert_raises():
        _ = nr_prach_frequency_sequence(Span(time))

    var invalid = NRPRACHFormat(
        4, 139, 0, 15000, 4096.0, 288.0, 0, False
    )
    with assert_raises():
        _ = nr_prach_normalized_cp_samples(invalid)
    invalid.repetitions = Int.MAX
    invalid.cp_samples_kappa = 0.0
    var finite_sequence = nr_prach_sequence_standard(1, 139, 0)
    with assert_raises():
        _ = nr_prach_normalized_waveform(Span(finite_sequence), invalid)


def test_standard_prach_detector_scaling_and_occasion_validation() raises:
    var transmitted = nr_prach_sequence_standard(1, 139, 26)
    var large = List[Complex64](capacity=139)
    for sample in transmitted:
        large.append(Complex64(sample.re * 1.0e308, sample.im * 1.0e308))
    var detection = nr_detect_prach_multi_root(
        Span(large), 0, 13, PRACH_SET_UNRESTRICTED, 4
    )
    assert_equal(detection.preamble_index, 2)
    assert_equal(detection.root_u, 1)
    assert_equal(detection.cyclic_shift, 26)
    assert_true(abs(detection.metric - 1.0) < 1.0e-12)

    large[0] = Complex64(0.0, inf[DType.float64]())
    with assert_raises():
        _ = nr_detect_prach_multi_root(
            Span(large), 0, 13, PRACH_SET_UNRESTRICTED, 4
        )

    var invalid_occasion = NRPRACHOccasion(
        1, 0, 0, 0, 0, UInt16(1), UInt64(1), 0, 0, 0, 0
    )
    with assert_raises():
        _ = nr_prach_occasion_is_active(invalid_occasion, 0, 0)


def test_pusch_chain_rejects_overflowed_config_and_nonfinite_symbols() raises:
    with assert_raises():
        _ = NRPUSCHConfig(
            64, 8, 2, 0, 0, Int.MAX, 0, 0, 0, 1
        )
    with assert_raises():
        _ = NRPUSCHConfig(
            64, 8, 2, 0, Int.MAX, 1, 0, 0, 0, 1
        )

    var config = NRPUSCHConfig(64, 8, 2, 0, 0, 1, 0, 0, 0, 1)
    var data = List[Complex64](length=12, fill=Complex64(1.0, 0.0))
    var dmrs = List[Complex64](length=6, fill=Complex64(0.0, 1.0))
    data[11] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_map_pusch_single_layer(config, Span(data), Span(dmrs))

    var grid = NRResourceGrid(2, 64)
    for symbol in range(2):
        for subcarrier in range(64):
            grid[symbol, subcarrier] = Complex64(1.0e308, 0.0)
    with assert_raises():
        _ = nr_pusch_grid_to_waveform(config, grid)


def test_pucch_chain_rejects_overflowed_config_and_nonfinite_llrs() raises:
    with assert_raises():
        _ = NRPUCCHFormat2Config(
            128, 0, 0, Int.MAX, 1, 0, 0, 0, 1
        )
    with assert_raises():
        _ = NRPUCCHFormat2Config(
            128, 0, 0, 0, 1, Int.MAX, 0, 0, 1
        )
    var llrs: List[Float64] = [1.0, nan[DType.float64](), -1.0]
    with assert_raises():
        _ = nr_pucch_format2_descramble_llrs(Span(llrs), 1, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
