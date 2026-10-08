from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.testing import (
    simulate_qam_awgn,
    simulate_qam_awgn_sweep,
    simulate_wifi_legacy_bpsk_awgn,
)


def test_seeded_link_simulation_reproducibility() raises:
    var first = simulate_qam_awgn(4, 2000, 0.05, seed=UInt64(12345))
    var second = simulate_qam_awgn(4, 2000, 0.05, seed=UInt64(12345))
    assert_equal(first.bit_count, 8000)
    assert_equal(first.bit_errors, second.bit_errors)
    assert_equal(first.ber, second.ber)


def test_qam_link_low_noise_is_error_free() raises:
    for bits_per_symbol in [1, 2, 4, 6, 8]:
        var result = simulate_qam_awgn(
            bits_per_symbol, 200, 1.0e-12, seed=UInt64(77 + bits_per_symbol)
        )
        assert_equal(result.bit_errors, 0)
        assert_equal(result.ber, 0.0)


def test_ber_degrades_with_noise_on_fixed_vector() raises:
    var low = simulate_qam_awgn(2, 10000, 0.02, seed=UInt64(9001))
    var high = simulate_qam_awgn(2, 10000, 2.0, seed=UInt64(9001))
    assert_true(high.bit_errors > low.bit_errors)
    assert_true(high.ber > 0.1)


def test_wifi_coded_packet_link_metrics() raises:
    var first = simulate_wifi_legacy_bpsk_awgn(20, 1.0e-12, seed=UInt64(55))
    var second = simulate_wifi_legacy_bpsk_awgn(20, 1.0e-12, seed=UInt64(55))
    assert_equal(first.bit_count, 360)
    assert_equal(first.bit_errors, 0)
    assert_equal(first.packet_errors, 0)
    assert_equal(first.bit_errors, second.bit_errors)
    assert_equal(first.packet_errors, second.packet_errors)


def test_qam_cartesian_sweep_order_reproducibility_and_boundaries() raises:
    var orders: List[Int] = [2, 4]
    var noises: List[Float64] = [1.0e-12, 1.0]
    var seeds: List[UInt64] = [UInt64(7), UInt64(19)]
    var first = simulate_qam_awgn_sweep(
        Span(orders), Span(noises), Span(seeds), 1024
    )
    var second = simulate_qam_awgn_sweep(
        Span(orders), Span(noises), Span(seeds), 1024
    )
    assert_equal(len(first), 8)
    for index in range(len(first)):
        assert_equal(first[index].bits_per_symbol, second[index].bits_per_symbol)
        assert_equal(first[index].noise_variance, second[index].noise_variance)
        assert_equal(first[index].seed, second[index].seed)
        assert_equal(first[index].result.bit_errors, second[index].result.bit_errors)
    assert_equal(first[0].bits_per_symbol, 2)
    assert_equal(first[0].noise_variance, 1.0e-12)
    assert_equal(first[0].seed, UInt64(7))
    assert_equal(first[4].bits_per_symbol, 4)
    assert_equal(first[4].noise_variance, 1.0e-12)
    assert_equal(first[0].result.bit_errors, 0)
    assert_true(first[2].result.bit_errors > first[0].result.bit_errors)
    assert_true(first[6].result.bit_errors > first[4].result.bit_errors)

    var invalid_noises: List[Float64] = [nan[DType.float64]()]
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(orders), Span(invalid_noises), Span(seeds), 1
        )


def test_link_simulation_rejects_before_allocation_and_product_overflow() raises:
    for order in [-1, 0, 3, 11, 13]:
        with assert_raises():
            _ = simulate_qam_awgn(order, 1, 0.0, seed=UInt64(1))
    for noise in [
        -1.0, nan[DType.float64](), inf[DType.float64](),
    ]:
        with assert_raises():
            _ = simulate_qam_awgn(2, 1, noise, seed=UInt64(1))
        with assert_raises():
            _ = simulate_wifi_legacy_bpsk_awgn(1, noise, seed=UInt64(1))
    with assert_raises():
        _ = simulate_qam_awgn(12, Int.MAX, 0.0, seed=UInt64(1))
    with assert_raises():
        _ = simulate_wifi_legacy_bpsk_awgn(
            Int.MAX, 0.0, seed=UInt64(1)
        )

    var invalid_orders: List[Int] = [2, 3]
    var valid_noises: List[Float64] = [0.0]
    var valid_seeds: List[UInt64] = [UInt64(1)]
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(invalid_orders), Span(valid_noises), Span(valid_seeds), 1
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
