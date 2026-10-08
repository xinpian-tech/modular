from std.testing import assert_equal, TestSuite
from wireless_dsp.numerics import (
    Fixed,
    ROUND_NEAREST_AWAY,
    ROUND_TOWARD_ZERO,
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
)

comptime Q4_4 = Fixed[4, 8]


def test_add_mul_and_rescale() raises:
    var one_and_half = Q4_4(raw=24)
    var half = Q4_4(raw=8)
    assert_equal((one_and_half + half).raw, 32)
    assert_equal((one_and_half * half).raw, 12)
    assert_equal(one_and_half.rescale[2]().raw, 6)
    assert_equal(Q4_4.from_int(2).to_float64(), 2.0)


def test_saturation() raises:
    assert_equal(Q4_4(raw=1000).raw, 127)
    assert_equal(Q4_4(raw=-1000).raw, -128)
    assert_equal((Q4_4(raw=120) + Q4_4(raw=20)).raw, 127)
    assert_equal(Q4_4.from_int(Int64.MAX_FINITE).raw, Int64(127))
    assert_equal(Q4_4.from_int(Int64.MIN_FINITE).raw, Int64(-128))


def test_wrap() raises:
    comptime Wrap8 = Fixed[0, 8, ROUND_TOWARD_ZERO, OVERFLOW_WRAP]
    assert_equal(Wrap8(raw=128).raw, -128)
    assert_equal(Wrap8(raw=-129).raw, 127)
    comptime WrapQ4 = Fixed[4, 8, ROUND_TOWARD_ZERO, OVERFLOW_WRAP]
    assert_equal(WrapQ4.from_int(Int64.MAX_FINITE).raw, Int64(-16))
    assert_equal(WrapQ4.from_int(Int64.MIN_FINITE).raw, Int64(0))


def test_negative_rounding_is_symmetric() raises:
    comptime QNearest = Fixed[2, 8, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE]
    # (-1.25 * 0.5) = -0.625, tie rounds away from zero to -0.75.
    assert_equal((QNearest(raw=-5) * QNearest(raw=2)).raw, -3)
    comptime QTrunc = Fixed[2, 8, ROUND_TOWARD_ZERO, OVERFLOW_SATURATE]
    assert_equal((QTrunc(raw=-5) * QTrunc(raw=2)).raw, -2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
