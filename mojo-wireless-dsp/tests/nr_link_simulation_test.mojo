from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.testing import simulate_nr_pdsch_awgn


def test_nr_pdsch_link_is_reproducible_and_error_free_at_low_noise() raises:
    var first = simulate_nr_pdsch_awgn(
        3, 1.0e-12, seed=UInt64(20260821)
    )
    var second = simulate_nr_pdsch_awgn(
        3, 1.0e-12, seed=UInt64(20260821)
    )
    assert_equal(first.bit_count, 300)
    assert_equal(first.bit_errors, 0)
    assert_equal(first.packet_errors, 0)
    assert_equal(first.bler, 0.0)
    assert_equal(first.bit_errors, second.bit_errors)
    assert_equal(first.packet_errors, second.packet_errors)


def test_nr_pdsch_bler_degrades_at_high_noise() raises:
    var low = simulate_nr_pdsch_awgn(
        4, 0.001, seed=UInt64(9191)
    )
    var high = simulate_nr_pdsch_awgn(
        4, 4.0, seed=UInt64(9191)
    )
    assert_equal(low.packet_errors, 0)
    assert_true(high.packet_errors > low.packet_errors)
    assert_true(high.bit_errors > low.bit_errors)
    assert_true(high.bler > low.bler)


def test_nr_pdsch_link_rejects_nonfinite_noise() raises:
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, nan[DType.float64](), seed=UInt64(1)
        )
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, inf[DType.float64](), seed=UInt64(1)
        )
    for modulation_order in [0, 1, 3, 12]:
        with assert_raises():
            _ = simulate_nr_pdsch_awgn(
                1,
                0.0,
                seed=UInt64(1),
                modulation_order=modulation_order,
            )
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            Int.MAX, 0.0, seed=UInt64(1)
        )
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, 0.0, seed=UInt64(1), output_bits=Int.MAX
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
