from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import (
    Complex32, Complex64, Span, MatrixView, ComplexSpan, SplitComplexSpan,
    IQBuffer, BitSpan, LLRBuffer,
)
from wireless_dsp.testing import (
    CheckpointMetadata, checkpoint_bits_checksum, checkpoint_complex_error,
)


def test_matrix_and_split_iq_views_are_zero_copy() raises:
    var matrix_values: List[Int] = [1, 2, 99, 3, 4, 99]
    var matrix = MatrixView(
        unsafe_ptr=matrix_values.unsafe_ptr(), rows=2, columns=2, row_stride=3
    )
    assert_equal(matrix[1, 1], 4)
    matrix[0, 1] = 7
    assert_equal(matrix_values[1], 7)

    var real: List[Float64] = [1.0, 2.0]
    var imag: List[Float64] = [-1.0, -2.0]
    var split = SplitComplexSpan(
        real_ptr=real.unsafe_ptr(), imag_ptr=imag.unsafe_ptr(), length=2
    )
    assert_equal(split.load(1), Complex64(2.0, -2.0))
    split.store(0, Complex64(3.0, 4.0))
    assert_equal(real[0], 3.0)
    assert_equal(imag[0], 4.0)

    var owned_samples: List[Complex32] = [
        Complex32(1.0, -1.0),
        Complex32(2.0, -2.0),
    ]
    var owned = IQBuffer[DType.float32](owned_samples^, alignment_bytes=32)
    assert_equal(len(owned), 2)
    assert_equal(owned.alignment_bytes, 32)
    var interleaved = ComplexSpan(
        unsafe_ptr=owned.samples.unsafe_ptr(), length=len(owned)
    )
    assert_equal(interleaved.load(1), Complex32(2.0, -2.0))
    interleaved.store(0, Complex32(3.0, 4.0))
    assert_equal(owned.load(0), Complex32(3.0, 4.0))

    with assert_raises():
        _ = MatrixView(
            unsafe_ptr=matrix_values.unsafe_ptr(),
            rows=-1,
            columns=1,
            row_stride=1,
        )
    with assert_raises():
        _ = MatrixView(
            unsafe_ptr=matrix_values.unsafe_ptr(),
            rows=Int.MAX,
            columns=2,
            row_stride=1,
        )
    with assert_raises():
        _ = MatrixView(
            unsafe_ptr=matrix_values.unsafe_ptr(),
            rows=2,
            columns=2,
            row_stride=Int.MAX,
        )
    with assert_raises():
        _ = SplitComplexSpan(
            real_ptr=real.unsafe_ptr(),
            imag_ptr=imag.unsafe_ptr(),
            length=-1,
        )
    with assert_raises():
        _ = SplitComplexSpan(
            real_ptr=real.unsafe_ptr(),
            imag_ptr=imag.unsafe_ptr(),
            length=1,
            stride=0,
        )
    with assert_raises():
        _ = SplitComplexSpan(
            real_ptr=real.unsafe_ptr(),
            imag_ptr=imag.unsafe_ptr(),
            length=3,
            stride=Int.MAX,
        )
    with assert_raises():
        _ = ComplexSpan(
            unsafe_ptr=owned.samples.unsafe_ptr(), length=-1
        )
    with assert_raises():
        _ = ComplexSpan(
            unsafe_ptr=owned.samples.unsafe_ptr(), length=1, stride=0
        )
    with assert_raises():
        _ = ComplexSpan(
            unsafe_ptr=owned.samples.unsafe_ptr(),
            length=3,
            stride=Int.MAX,
        )

    var invalid_alignment_samples: List[Complex32] = []
    with assert_raises():
        _ = IQBuffer[DType.float32](
            invalid_alignment_samples^, alignment_bytes=3
        )


def test_bitspan_order_offset_and_mutation() raises:
    var bytes: List[UInt8] = [UInt8(0b10110010), UInt8(0)]
    var lsb = BitSpan(
        unsafe_ptr=bytes.unsafe_ptr(), bit_length=8, lsb_first=True
    )
    assert_equal(lsb[0], UInt8(0))
    assert_equal(lsb[1], UInt8(1))
    var msb = BitSpan(
        unsafe_ptr=bytes.unsafe_ptr(), bit_length=8, lsb_first=False
    )
    assert_equal(msb[0], UInt8(1))
    assert_equal(msb[1], UInt8(0))
    lsb.set(0, UInt8(1))
    assert_equal(bytes[0], UInt8(0b10110011))
    with assert_raises():
        lsb.set(0, UInt8(2))
    with assert_raises():
        _ = BitSpan(
            unsafe_ptr=bytes.unsafe_ptr(), bit_length=-1, lsb_first=True
        )
    with assert_raises():
        _ = BitSpan(
            unsafe_ptr=bytes.unsafe_ptr(), bit_length=1, bit_offset=-1
        )
    with assert_raises():
        _ = BitSpan(
            unsafe_ptr=bytes.unsafe_ptr(),
            bit_length=2,
            bit_offset=Int.MAX,
        )


def test_llr_metadata_and_checkpoint_metrics() raises:
    var quantized: List[Int] = [7, -4, 0]
    var buffer = LLRBuffer(quantized^, 2.0, 7)
    assert_equal(buffer.dequantize(), [3.5, -2.0, 0.0])
    var clipped: List[Int] = [8]
    with assert_raises():
        _ = LLRBuffer(clipped^, 1.0, 7)
    var invalid_clip: List[Int] = [0]
    with assert_raises():
        _ = LLRBuffer(invalid_clip^, 1.0, 0)
    var bits: List[UInt8] = [1, 0, 1]
    assert_equal(checkpoint_bits_checksum(Span(bits)), UInt64(15034027211670106815))
    var expected: List[Complex64] = [Complex64(1.0), Complex64(0.0, 1.0)]
    var actual: List[Complex64] = [Complex64(1.0), Complex64(0.0, 1.0)]
    var evm, maximum = checkpoint_complex_error(Span(actual), Span(expected))
    assert_equal(evm, 0.0)
    assert_equal(maximum, 0.0)

    var metadata = CheckpointMetadata(
        testcase_id="phase7-metadata",
        stage="equalized-symbols",
        dtype="complex-int16",
        shape="2",
        scale=32768.0,
        version=1,
        stride="2",
        q_format="Q1.15",
        layout="iq-interleaved",
    )
    assert_equal(metadata.stride, "2")
    assert_equal(metadata.q_format, "Q1.15")
    assert_equal(metadata.layout, "iq-interleaved")

    var zero_reference: List[Complex64] = [
        Complex64(0.0), Complex64(0.0),
    ]
    var zero_actual: List[Complex64] = [
        Complex64(0.0), Complex64(0.0),
    ]
    var zero_evm, zero_maximum = checkpoint_complex_error(
        Span(zero_actual), Span(zero_reference)
    )
    assert_equal(zero_evm, 0.0)
    assert_equal(zero_maximum, 0.0)
    var nonzero_actual: List[Complex64] = [
        Complex64(1.0), Complex64(0.0),
    ]
    with assert_raises():
        _ = checkpoint_complex_error(
            Span(nonzero_actual), Span(zero_reference)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
