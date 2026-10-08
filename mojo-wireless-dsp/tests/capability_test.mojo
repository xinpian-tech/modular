"""Phase-0 compile/run spikes for value parameters and native CPU SIMD."""

from std.testing import assert_equal, TestSuite


def simd_energy[dtype: DType, width: SIMDLength](
    values: SIMD[dtype, width],
) -> Scalar[dtype]:
    var squares = values * values
    var total = Scalar[dtype](0)
    comptime for lane in range(Int(width)):
        total += squares[lane]
    return total


def test_value_parameter_specialization() raises:
    var values = SIMD[DType.float32, 4](1.0, 2.0, 3.0, 4.0)
    assert_equal(simd_energy(values), 30.0)


def test_integral_simd_specialization() raises:
    var values = SIMD[DType.int16, 8](1, -1, 2, -2, 3, -3, 4, -4)
    assert_equal(simd_energy(values), Int16(60))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
