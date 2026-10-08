"""Independent boundary, analytic, and statistical evidence for testing APIs."""

from std.collections import Span
from std.math import erfc, isfinite, ldexp, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.numerics import ComplexRaw, QFormat, ScaleTrace
from wireless_dsp.testing import (
    checkpoint_bits_checksum,
    checkpoint_complex_error,
    checkpoint_metadata_1d,
    checkpoint_metadata_2d,
    complex_raw_checksum,
    fixed_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
    serialize_scale_trace,
    simulate_nr_pdsch_awgn,
    simulate_qam_awgn,
    simulate_qam_awgn_sweep,
    simulate_wifi_legacy_bpsk_awgn,
)


def _oracle_fnv1a_bit_bytes(bits: Span[UInt8, ...]) -> UInt64:
    var state = UInt64(14695981039346656037)
    for index in range(len(bits)):
        state ^= UInt64(bits[index])
        state *= UInt64(1099511628211)
    return state


def _read_external_oracle_fixture(filename: StringSlice) raises -> String:
    var path = String("mojo-wireless-dsp/tests/fixtures/") + filename
    with open(path, "r") as file:
        return file.read()


def _lower_hex_digit(value: StringSlice, index: Int) raises -> Int:
    var code = ord(value[byte=index])
    if ord("0") <= code <= ord("9"):
        return code - ord("0")
    if ord("a") <= code <= ord("f"):
        return 10 + code - ord("a")
    raise Error("oracle value contains a non-canonical hex digit")


def _parse_hex_u64_exact(value: StringSlice) raises -> UInt64:
    if (
        value.byte_length() != 18
        or ord(value[byte=0]) != ord("0")
        or ord(value[byte=1]) != ord("x")
    ):
        raise Error("oracle UInt64 must be canonical 0x plus 16 lowercase hex digits")
    var result = UInt64(0)
    for index in range(2, 18):
        result = (result << 4) | UInt64(_lower_hex_digit(value, index))
    return result


def _parse_positive_hex_float_exact(value: StringSlice) raises -> Float64:
    if (
        value.byte_length() < 8
        or ord(value[byte=0]) != ord("0")
        or ord(value[byte=1]) != ord("x")
    ):
        raise Error("oracle Float64 must use canonical positive hexadecimal form")
    var mantissa = 0.0
    var fraction_scale = 1.0 / 16.0
    var seen_dot = False
    var exponent_marker = -1
    for index in range(2, value.byte_length()):
        var code = ord(value[byte=index])
        if code == ord("p"):
            exponent_marker = index
            break
        if code == ord("."):
            if seen_dot:
                raise Error("oracle Float64 contains multiple radix points")
            seen_dot = True
            continue
        var digit = _lower_hex_digit(value, index)
        if seen_dot:
            mantissa += Float64(digit) * fraction_scale
            fraction_scale /= 16.0
        else:
            mantissa = 16.0 * mantissa + Float64(digit)
    if not seen_dot or exponent_marker < 0 or exponent_marker + 2 >= value.byte_length():
        raise Error("oracle Float64 is missing a radix point or exponent")
    var exponent_sign = 1
    var exponent_index = exponent_marker + 1
    if ord(value[byte=exponent_index]) == ord("-"):
        exponent_sign = -1
        exponent_index += 1
    elif ord(value[byte=exponent_index]) == ord("+"):
        exponent_index += 1
    else:
        raise Error("oracle Float64 exponent must include an explicit sign")
    if exponent_index >= value.byte_length():
        raise Error("oracle Float64 exponent is empty")
    var exponent = 0
    for index in range(exponent_index, value.byte_length()):
        var code = ord(value[byte=index])
        if not (ord("0") <= code <= ord("9")):
            raise Error("oracle Float64 exponent is not canonical decimal")
        exponent = 10 * exponent + code - ord("0")
    return ldexp(mantissa, Int32(exponent_sign * exponent))


def _require_lower_hex_digest(value: StringSlice) raises:
    if value.byte_length() != 64:
        raise Error("oracle digest must contain exactly 64 lowercase hex digits")
    for index in range(64):
        var code = ord(value[byte=index])
        if not (
            ord("0") <= code <= ord("9")
            or ord("a") <= code <= ord("f")
        ):
            raise Error("oracle digest contains a non-canonical hex digit")


def _require_lf_only_unique_trailing_newline(text: StringSlice) raises:
    if text.byte_length() == 0 or text.as_bytes()[text.byte_length() - 1] != 10:
        raise Error("oracle fixture must have one trailing LF")
    if text.byte_length() >= 2 and text.as_bytes()[text.byte_length() - 2] == 10:
        raise Error("oracle fixture must not contain a trailing blank line")
    for index in range(text.byte_length()):
        var byte = UInt8(text.as_bytes()[index])
        if byte == 13 or byte > 0x7F:
            raise Error("oracle fixture must be LF-only ASCII")


def _oracle_fnv1a_int64_words(values: Span[Int64, ...]) -> UInt64:
    var state = UInt64(14695981039346656037)
    for index in range(len(values)):
        var word = UInt64(values[index])
        for byte_index in range(8):
            state ^= UInt64(
                UInt8((word >> UInt64(8 * byte_index)) & UInt64(0xff))
            )
            state *= UInt64(1099511628211)
    return state


def _oracle_fnv1a_complex_words(values: Span[ComplexRaw, ...]) -> UInt64:
    var state = UInt64(14695981039346656037)
    for index in range(len(values)):
        for word in [UInt64(values[index].re), UInt64(values[index].im)]:
            for byte_index in range(8):
                state ^= UInt64(
                    UInt8(
                        (word >> UInt64(8 * byte_index)) & UInt64(0xff)
                    )
                )
                state *= UInt64(1099511628211)
    return state


def test_checkpoint_metadata_1d_owned_fields_and_total_boundaries() raises:
    var metadata = checkpoint_metadata_1d(
        "case-1d",
        "equalized",
        "complex64",
        0,
        scale=0.25,
        element_stride=Int.MAX,
        q_format="floating",
        version=Int.MAX,
        layout="strided",
    )
    assert_equal(metadata.testcase_id, "case-1d")
    assert_equal(metadata.stage, "equalized")
    assert_equal(metadata.dtype, "complex64")
    assert_equal(metadata.shape, "0")
    var maximum_stride = String()
    maximum_stride.write(Int.MAX)
    assert_equal(metadata.stride, maximum_stride)
    assert_equal(metadata.scale, 0.25)
    assert_equal(metadata.version, Int.MAX)
    assert_equal(metadata.q_format, "floating")
    assert_equal(metadata.layout, "strided")

    with assert_raises():
        _ = checkpoint_metadata_1d("id", "stage", "u1", -1)
    with assert_raises():
        _ = checkpoint_metadata_1d(
            "id", "stage", "u1", 1, element_stride=0
        )
    for invalid_scale in [
        -1.0,
        0.0,
        nan[DType.float64](),
        inf[DType.float64](),
    ]:
        with assert_raises():
            _ = checkpoint_metadata_1d(
                "id", "stage", "u1", 1, scale=invalid_scale
            )
    with assert_raises():
        _ = checkpoint_metadata_1d(
            "id", "stage", "u1", 1, version=0
        )
    with assert_raises():
        _ = checkpoint_metadata_1d("", "stage", "u1", 1)
    with assert_raises():
        _ = checkpoint_metadata_1d("id", "", "u1", 1)
    with assert_raises():
        _ = checkpoint_metadata_1d("id", "stage", "", 1)
    with assert_raises():
        _ = checkpoint_metadata_1d(
            "id", "stage", "u1", 1, q_format=""
        )
    with assert_raises():
        _ = checkpoint_metadata_1d(
            "id", "stage", "u1", 1, layout=""
        )
    with assert_raises():
        _ = checkpoint_metadata_1d("bad\nid", "stage", "u1", 1)
    with assert_raises():
        _ = checkpoint_metadata_1d("id", "bad\rstage", "u1", 1)


def test_checkpoint_metadata_2d_shape_stride_and_total_boundaries() raises:
    var metadata = checkpoint_metadata_2d(
        "case-2d",
        "grid",
        "complex-int16",
        0,
        Int.MAX,
        row_stride=Int.MAX,
        column_stride=2,
        scale=32768.0,
        q_format="Q1.15",
        version=9,
        layout="row-major-padded",
    )
    var maximum = String()
    maximum.write(Int.MAX)
    assert_equal(metadata.shape, "0x" + maximum)
    assert_equal(metadata.stride, maximum + ",2")
    assert_equal(metadata.scale, 32768.0)
    assert_equal(metadata.q_format, "Q1.15")
    assert_equal(metadata.layout, "row-major-padded")

    with assert_raises():
        _ = checkpoint_metadata_2d(
            "id", "stage", "u1", -1, 1, row_stride=1
        )
    with assert_raises():
        _ = checkpoint_metadata_2d(
            "id", "stage", "u1", 1, -1, row_stride=1
        )
    with assert_raises():
        _ = checkpoint_metadata_2d(
            "id", "stage", "u1", 1, 1, row_stride=0
        )
    with assert_raises():
        _ = checkpoint_metadata_2d(
            "id", "stage", "u1", 1, 1,
            row_stride=1, column_stride=0,
        )
    with assert_raises():
        _ = checkpoint_metadata_2d(
            "id", "stage", "u1", 1, 1,
            row_stride=1, scale=nan[DType.float64](),
        )
    with assert_raises():
        _ = checkpoint_metadata_2d(
            "id", "stage", "u1", 1, 1,
            row_stride=1, version=0,
        )
    with assert_raises():
        _ = checkpoint_metadata_2d(
            "id", "stage", "u1", 1, 1,
            row_stride=1, layout="bad\nlayout",
        )


def test_checkpoint_bits_checksum_static_fnv_and_edges() raises:
    var bits: List[UInt8] = [0, 1, 1, 0, 1]
    assert_equal(
        checkpoint_bits_checksum(Span(bits)),
        UInt64(5578585346173446582),
    )
    var empty = List[UInt8]()
    assert_equal(
        checkpoint_bits_checksum(Span(empty)),
        UInt64(14695981039346656037),
    )
    var invalid: List[UInt8] = [0, 2]
    with assert_raises():
        _ = checkpoint_bits_checksum(Span(invalid))


def test_checkpoint_complex_error_scale_safe_analytic_oracle_and_edges() raises:
    var expected: List[Complex64] = [
        Complex64(3.0, 4.0), Complex64(0.0, 0.0)
    ]
    var actual: List[Complex64] = [
        Complex64(0.0, 0.0), Complex64(6.0, 8.0)
    ]
    var evm, maximum = checkpoint_complex_error(
        Span(actual), Span(expected)
    )
    assert_almost_equal(evm, sqrt(5.0), atol=1.0e-15, rtol=1.0e-15)
    assert_equal(maximum, 10.0)

    # The mathematical squares overflow at the large scale and underflow at
    # the small scale; EVM remains scale invariant and the maximum error stays
    # representable in both cases.
    var huge_expected: List[Complex64] = [
        Complex64(1.0e200, -1.0e200)
    ]
    var huge_actual: List[Complex64] = [
        Complex64(1.0000000001e200, -1.0000000001e200)
    ]
    var huge_evm, huge_maximum = checkpoint_complex_error(
        Span(huge_actual), Span(huge_expected)
    )
    assert_true(isfinite(huge_evm))
    assert_almost_equal(
        huge_evm, 1.0e-10, atol=2.0e-16, rtol=2.0e-6
    )
    assert_true(isfinite(huge_maximum))
    assert_almost_equal(
        huge_maximum,
        sqrt(2.0) * 1.0e190,
        atol=0.0,
        rtol=2.0e-6,
    )

    var tiny_expected: List[Complex64] = [
        Complex64(1.0e-200, -1.0e-200)
    ]
    var tiny_actual: List[Complex64] = [
        Complex64(1.0000000001e-200, -1.0000000001e-200)
    ]
    var tiny_evm, tiny_maximum = checkpoint_complex_error(
        Span(tiny_actual), Span(tiny_expected)
    )
    assert_almost_equal(
        tiny_evm, huge_evm, atol=2.0e-16, rtol=2.0e-6
    )
    assert_true(tiny_maximum > 0.0)
    assert_almost_equal(
        tiny_maximum,
        sqrt(2.0) * 1.0e-210,
        atol=0.0,
        rtol=2.0e-6,
    )

    # An unchanged huge component must not erase a unit-scale error.
    var mixed_expected: List[Complex64] = [
        Complex64(1.0e200, 0.0), Complex64(0.0, 1.0)
    ]
    var mixed_actual: List[Complex64] = [
        Complex64(1.0e200, 0.0), Complex64(0.0, 0.0)
    ]
    var mixed_evm, mixed_maximum = checkpoint_complex_error(
        Span(mixed_actual), Span(mixed_expected)
    )
    assert_almost_equal(
        mixed_evm, 1.0e-200, atol=0.0, rtol=1.0e-15
    )
    assert_equal(mixed_maximum, 1.0)

    # Opposite near-limit finite values have a finite EVM, but their maximum
    # absolute error is not representable as Float64 and must therefore raise.
    var opposite_expected: List[Complex64] = [Complex64(1.0e308, 0.0)]
    var opposite_actual: List[Complex64] = [Complex64(-1.0e308, 0.0)]
    with assert_raises():
        _ = checkpoint_complex_error(
            Span(opposite_actual), Span(opposite_expected)
        )

    var zeros: List[Complex64] = [Complex64(0.0)]
    var zero_expected: List[Complex64] = [Complex64(0.0)]
    var zero_evm, zero_maximum = checkpoint_complex_error(
        Span(zeros), Span(zero_expected)
    )
    assert_equal(zero_evm, 0.0)
    assert_equal(zero_maximum, 0.0)
    var one: List[Complex64] = [Complex64(1.0, 0.0)]
    with assert_raises():
        _ = checkpoint_complex_error(Span(one), Span(zeros))
    var subnormal_reference: List[Complex64] = [Complex64(1.0e-320)]
    with assert_raises():
        _ = checkpoint_complex_error(Span(one), Span(subnormal_reference))

    var empty = List[Complex64]()
    var empty_expected = List[Complex64]()
    with assert_raises():
        _ = checkpoint_complex_error(Span(empty), Span(empty_expected))
    with assert_raises():
        _ = checkpoint_complex_error(Span(one), Span(empty))
    var bad_actual: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = checkpoint_complex_error(Span(bad_actual), Span(zeros))
    var bad_expected: List[Complex64] = [
        Complex64(0.0, inf[DType.float64]())
    ]
    with assert_raises():
        _ = checkpoint_complex_error(Span(zeros), Span(bad_expected))


def test_fixed_and_complex_raw_checksums_static_fnv_edges() raises:
    var words: List[Int64] = [
        0,
        1,
        -1,
        Int64.MIN_FINITE,
        Int64.MAX_FINITE,
    ]
    assert_equal(
        fixed_raw_checksum(Span(words)),
        UInt64(3107239636911500980),
    )
    assert_equal(
        fixed_raw_checksum(Span(words)), fixed_raw_checksum(Span(words))
    )
    var empty_words = List[Int64]()
    assert_equal(
        fixed_raw_checksum(Span(empty_words)),
        UInt64(14695981039346656037),
    )

    var complex_words: List[ComplexRaw] = [
        ComplexRaw(-8, 7), ComplexRaw(0, -1)
    ]
    assert_equal(
        complex_raw_checksum(Span(complex_words)),
        UInt64(2401200982308944693),
    )
    var empty_complex = List[ComplexRaw]()
    assert_equal(
        complex_raw_checksum(Span(empty_complex)),
        UInt64(14695981039346656037),
    )


def test_seeded_metadata_checksums_and_serializer_properties() raises:
    """Exercise mutable-size invariants against independent byte oracles."""
    var state = UInt64(0x5445_5354_494E_475F)
    for _ in range(257):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        var length = Int((state >> 57) & UInt64(15))
        var stride = Int((state >> 49) & UInt64(31)) + 1

        var one = checkpoint_metadata_1d(
            "seeded", "one", "sint8", length,
            element_stride=stride,
            scale=0.5,
            q_format="Q3.4",
            version=2,
            layout="linear",
        )
        var expected_shape = String()
        expected_shape.write(length)
        var expected_stride = String()
        expected_stride.write(stride)
        assert_equal(one.shape, expected_shape)
        assert_equal(one.stride, expected_stride)
        assert_equal(one.scale, 0.5)
        assert_equal(one.version, 2)

        var rows = length
        var columns = Int((state >> 45) & UInt64(7))
        var two = checkpoint_metadata_2d(
            "seeded", "two", "complex-int8", rows, columns,
            row_stride=stride,
            column_stride=2,
            scale=0.25,
            q_format="Q3.4",
            version=3,
            layout="row-major",
        )
        var expected_matrix_shape = String()
        expected_matrix_shape.write(rows, "x", columns)
        var expected_matrix_stride = String()
        expected_matrix_stride.write(stride, ",2")
        assert_equal(two.shape, expected_matrix_shape)
        assert_equal(two.stride, expected_matrix_stride)

        var bits = List[UInt8](capacity=length)
        var words = List[Int64](capacity=length)
        var complex_words = List[ComplexRaw](capacity=length)
        var data = String("data=")
        var complex_data = String("data_iq=")
        for index in range(length):
            state = state * UInt64(6364136223846793005) + UInt64(1)
            var bit = UInt8((state >> 63) & UInt64(1))
            var word = Int64(Int(state & UInt64(15)) - 8)
            var imaginary = Int64(Int((state >> 8) & UInt64(15)) - 8)
            bits.append(bit)
            words.append(word)
            complex_words.append(ComplexRaw(word, imaginary))
            if index != 0:
                data.write(",")
                complex_data.write(",")
            data.write(word)
            complex_data.write(word, ":", imaginary)
        data.write("\n")
        complex_data.write("\n")

        assert_equal(
            checkpoint_bits_checksum(Span(bits)),
            _oracle_fnv1a_bit_bytes(Span(bits)),
        )
        assert_equal(
            fixed_raw_checksum(Span(words)),
            _oracle_fnv1a_int64_words(Span(words)),
        )
        assert_equal(
            complex_raw_checksum(Span(complex_words)),
            _oracle_fnv1a_complex_words(Span(complex_words)),
        )

        var qformat = QFormat(4, 2)
        var scalar = serialize_fixed_vector(
            "seeded", "scalar", Span(words), qformat
        )
        var scalar_again = serialize_fixed_vector(
            "seeded", "scalar", Span(words), qformat
        )
        assert_equal(scalar, scalar_again)
        assert_true(scalar.endswith(StringSlice(data)))
        var scalar_shape = String("shape=")
        scalar_shape.write(length, "\n")
        assert_true(StringSlice(scalar_shape) in scalar)

        var complex = serialize_complex_fixed_vector(
            "seeded", "complex", Span(complex_words), qformat
        )
        var complex_again = serialize_complex_fixed_vector(
            "seeded", "complex", Span(complex_words), qformat
        )
        assert_equal(complex, complex_again)
        assert_true(complex.endswith(StringSlice(complex_data)))
        var complex_shape = String("shape=")
        complex_shape.write(length, "x2\n")
        assert_true(StringSlice(complex_shape) in complex)

        var trace_values = List[Int64](capacity=length)
        var fractions = List[Int](capacity=length)
        var widths = List[Int](capacity=length)
        var shifts = List[Int](capacity=length)
        var trace_data = String("data=")
        for index in range(length):
            var value = words[index]
            trace_values.append(value)
            fractions.append(2)
            widths.append(4)
            shifts.append(index % 3)
            if index != 0:
                trace_data.write(",")
            trace_data.write(value, ":4:2:", index % 3, ":1:1")
        trace_data.write("\n")
        var trace = ScaleTrace(
            trace_values^, fractions^, widths^, shifts^
        )
        var trace_text = serialize_scale_trace("seeded", "trace", trace)
        assert_true(trace_text.endswith(StringSlice(trace_data)))
        var trace_shape = String("shape=")
        trace_shape.write(length, "x6\n")
        assert_true(StringSlice(trace_shape) in trace_text)


def test_fixed_vector_serializers_exact_wire_format_and_edges() raises:
    var q2 = QFormat(4, 2)
    var values: List[Int64] = [-8, 7]
    var scalar = serialize_fixed_vector(
        "case", "scalar", Span(values), q2, stride=1, version=2
    )
    assert_equal(
        scalar,
        "MWDSP-FIXED-V2\n"
        "testcase=case\n"
        "stage=scalar\n"
        "version=2\n"
        "dtype=sint4\n"
        "shape=2\n"
        "stride=1\n"
        "layout=scalar-contiguous\n"
        "storage_bits=4\n"
        "fraction_bits=2\n"
        "scale_numerator=1\n"
        "scale_denominator=4\n"
        "rounding=1\n"
        "overflow=1\n"
        "checksum_algorithm=fnv1a64\n"
        "checksum_scope=header-utf8+data-int64-le\n"
        "checksum=5018718757992377813\n"
        "data=-8,7\n",
    )

    # The payload is identical, but changing header identity must change the
    # checksum rather than merely changing unprotected descriptive text.
    var renamed = serialize_fixed_vector(
        "case", "scalar-alt", Span(values), q2, version=2
    )
    assert_true("checksum=501103247962221995\n" in renamed)
    assert_true("checksum=5018718757992377813\n" not in renamed)

    var complex_values: List[ComplexRaw] = [
        ComplexRaw(-8, 7), ComplexRaw(0, -1)
    ]
    var complex = serialize_complex_fixed_vector(
        "case", "complex", Span(complex_values), q2
    )
    assert_equal(
        complex,
        "MWDSP-COMPLEX-FIXED-V2\n"
        "testcase=case\n"
        "stage=complex\n"
        "version=1\n"
        "dtype=sint4\n"
        "shape=2x2\n"
        "stride=1\n"
        "layout=iq-interleaved-contiguous\n"
        "storage_bits=4\n"
        "fraction_bits=2\n"
        "scale_numerator=1\n"
        "scale_denominator=4\n"
        "rounding=1\n"
        "overflow=1\n"
        "checksum_algorithm=fnv1a64\n"
        "checksum_scope=header-utf8+data-iq-int64-le\n"
        "checksum=5334673058524614298\n"
        "data_iq=-8:7,0:-1\n",
    )

    var empty_values = List[Int64]()
    var empty_text = serialize_fixed_vector(
        "empty", "scalar", Span(empty_values), q2
    )
    assert_true("shape=0\n" in empty_text)
    assert_true("checksum=4743998529226288703\n" in empty_text)
    assert_true(empty_text.endswith("data=\n"))

    with assert_raises():
        _ = serialize_fixed_vector("", "stage", Span(values), q2)
    with assert_raises():
        _ = serialize_fixed_vector("id", "", Span(values), q2)
    with assert_raises():
        _ = serialize_fixed_vector("bad\nid", "stage", Span(values), q2)
    with assert_raises():
        _ = serialize_fixed_vector(
            "id", "stage", Span(values), q2, stride=0
        )
    with assert_raises():
        _ = serialize_fixed_vector(
            "id", "stage", Span(values), q2, stride=3
        )
    with assert_raises():
        _ = serialize_fixed_vector(
            "id", "stage", Span(values), q2, version=0
        )
    var outside: List[Int64] = [8]
    with assert_raises():
        _ = serialize_fixed_vector("id", "stage", Span(outside), q2)
    var outside_complex: List[ComplexRaw] = [ComplexRaw(0, -9)]
    with assert_raises():
        _ = serialize_complex_fixed_vector(
            "id", "stage", Span(outside_complex), q2
        )
    with assert_raises():
        _ = serialize_complex_fixed_vector(
            "", "stage", Span(complex_values), q2
        )
    with assert_raises():
        _ = serialize_complex_fixed_vector(
            "id", "bad\rstage", Span(complex_values), q2
        )
    with assert_raises():
        _ = serialize_complex_fixed_vector(
            "id", "stage", Span(complex_values), q2, stride=0
        )
    with assert_raises():
        _ = serialize_complex_fixed_vector(
            "id", "stage", Span(complex_values), q2, stride=3
        )
    with assert_raises():
        _ = serialize_complex_fixed_vector(
            "id", "stage", Span(complex_values), q2, version=0
        )

    # QFormat fields are mutable, so serializers must revalidate the complete
    # descriptor before shifts, range checks, or wire emission.
    var malformed = QFormat(8, 4)
    malformed.storage_bits = 1
    with assert_raises():
        _ = serialize_fixed_vector(
            "id", "stage", Span(empty_values), malformed
        )
    malformed = QFormat(8, 4)
    malformed.fraction_bits = 8
    with assert_raises():
        _ = serialize_complex_fixed_vector(
            "id", "stage", Span(complex_values), malformed
        )
    malformed = QFormat(8, 4)
    malformed.rounding_mode = 99
    with assert_raises():
        _ = serialize_fixed_vector(
            "id", "stage", Span(empty_values), malformed
        )
    malformed = QFormat(8, 4)
    malformed.overflow_mode = 99
    with assert_raises():
        _ = serialize_complex_fixed_vector(
            "id", "stage", Span(complex_values), malformed
        )


def test_scale_trace_serializer_exact_wire_format_and_malformed_fields() raises:
    var values: List[Int64] = [1, -2, 3]
    var fractions: List[Int] = [2, 3, 4]
    var widths: List[Int] = [8, 8, 16]
    var shifts: List[Int] = [0, 1, 2]
    var trace = ScaleTrace(values^, fractions^, widths^, shifts^)
    var text = serialize_scale_trace("case", "scales", trace, version=3)
    assert_equal(
        text,
        "MWDSP-SCALE-TRACE-V2\n"
        "testcase=case\n"
        "stage=scales\n"
        "version=3\n"
        "shape=3x6\n"
        "columns=raw:storage_bits:fraction_bits:right_shift:rounding:overflow\n"
        "checksum_algorithm=fnv1a64\n"
        "checksum_scope=header-utf8+rows-int64-le\n"
        "checksum=16455425978113418481\n"
        "data=1:8:2:0:1:1,-2:8:3:1:1:1,3:16:4:2:1:1\n",
    )

    var empty_trace = ScaleTrace(
        List[Int64](), List[Int](), List[Int](), List[Int]()
    )
    var empty_text = serialize_scale_trace("empty", "trace", empty_trace)
    assert_true("shape=0x6\n" in empty_text)
    assert_true("checksum=10323120131842585426\n" in empty_text)
    assert_true(empty_text.endswith("data=\n"))

    with assert_raises():
        _ = serialize_scale_trace("", "trace", empty_trace)
    with assert_raises():
        _ = serialize_scale_trace("id", "bad\nstage", empty_trace)
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", empty_trace, version=0)

    var mismatched = ScaleTrace(
        [Int64(1)], List[Int](), [8], [0]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", mismatched)
    var bad_width = ScaleTrace(
        [Int64(0)], [0], [1], [0]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", bad_width)
    var bad_fraction = ScaleTrace(
        [Int64(0)], [8], [8], [0]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", bad_fraction)
    var negative_fraction = ScaleTrace(
        [Int64(0)], [-1], [8], [0]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", negative_fraction)
    var bad_shift = ScaleTrace(
        [Int64(0)], [0], [8], [62]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", bad_shift)
    var negative_shift = ScaleTrace(
        [Int64(0)], [0], [8], [-1]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", negative_shift)
    var bad_raw = ScaleTrace(
        [Int64(128)], [0], [8], [0]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", bad_raw)
    var mismatched_modes = ScaleTrace(
        [Int64(0)], [0], [8], [0], List[Int](), [1]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", mismatched_modes)
    var bad_rounding = ScaleTrace(
        [Int64(0)], [0], [8], [0], [99], [1]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", bad_rounding)
    var bad_overflow = ScaleTrace(
        [Int64(0)], [0], [8], [0], [1], [99]
    )
    with assert_raises():
        _ = serialize_scale_trace("id", "trace", bad_overflow)


def test_simulate_qam_awgn_against_bpsk_theory_and_total_edges() raises:
    comptime symbols = 50000
    comptime noise_variance = 1.0
    var first = simulate_qam_awgn(
        1, symbols, noise_variance, seed=UInt64(0x51A71C)
    )
    var second = simulate_qam_awgn(
        1, symbols, noise_variance, seed=UInt64(0x51A71C)
    )
    assert_equal(first.bit_count, symbols)
    assert_equal(first.bit_errors, second.bit_errors)
    assert_equal(first.ber, second.ber)
    assert_equal(first.ber, Float64(first.bit_errors) / Float64(symbols))

    # Unit-energy BPSK in circular complex AWGN with E[|n|^2] = N0 has
    # Pb = Q(sqrt(2/N0)) = 0.5*erfc(sqrt(1/N0)).
    var theoretical = 0.5 * erfc(sqrt(1.0 / noise_variance))
    var standard_error = sqrt(
        theoretical * (1.0 - theoretical) / Float64(symbols)
    )
    assert_true(abs(first.ber - theoretical) <= 6.0 * standard_error)

    for order in [1, 2, 4, 6, 8, 10, 12]:
        var noiseless = simulate_qam_awgn(
            order, 32, 0.0, seed=UInt64(100 + order)
        )
        assert_equal(noiseless.bit_errors, 0)
        assert_equal(noiseless.ber, 0.0)
    for order in [-1, 0, 3, 11, 13]:
        with assert_raises():
            _ = simulate_qam_awgn(order, 1, 0.0, seed=UInt64(1))
    with assert_raises():
        _ = simulate_qam_awgn(2, 0, 0.0, seed=UInt64(1))
    var capacity_result = simulate_qam_awgn(
        1, 131072, 0.0, seed=UInt64(0xC0FFEE)
    )
    assert_equal(capacity_result.bit_count, 131072)
    assert_equal(capacity_result.bit_errors, 0)
    with assert_raises():
        _ = simulate_qam_awgn(
            1, 131073, 0.0, seed=UInt64(1)
        )
    with assert_raises():
        _ = simulate_qam_awgn(1, Int.MIN, 0.0, seed=UInt64(1))
    with assert_raises():
        _ = simulate_qam_awgn(1, Int.MAX, 0.0, seed=UInt64(1))
    with assert_raises():
        _ = simulate_qam_awgn(12, Int.MAX, 0.0, seed=UInt64(1))
    for invalid_noise in [
        -1.0,
        nan[DType.float64](),
        inf[DType.float64](),
    ]:
        with assert_raises():
            _ = simulate_qam_awgn(
                2, 1, invalid_noise, seed=UInt64(1)
            )


def test_simulate_qam_awgn_sweep_order_theory_and_axis_edges() raises:
    var orders: List[Int] = [1]
    var noises: List[Float64] = [0.0, 1.0]
    var seeds: List[UInt64] = [
        UInt64(7), UInt64(19), UInt64(41), UInt64(73)
    ]
    comptime symbols_per_point = 12000
    var points = simulate_qam_awgn_sweep(
        Span(orders), Span(noises), Span(seeds), symbols_per_point
    )
    assert_equal(len(points), 8)
    var noisy_errors = 0
    for index in range(len(points)):
        assert_equal(points[index].bits_per_symbol, 1)
        assert_equal(points[index].noise_variance, noises[index // 4])
        assert_equal(points[index].seed, seeds[index % 4])
        assert_equal(points[index].result.bit_count, symbols_per_point)
        if index < 4:
            assert_equal(points[index].result.bit_errors, 0)
        else:
            noisy_errors += points[index].result.bit_errors

    var noisy_bits = 4 * symbols_per_point
    var observed = Float64(noisy_errors) / Float64(noisy_bits)
    var theoretical = 0.5 * erfc(1.0)
    var standard_error = sqrt(
        theoretical * (1.0 - theoretical) / Float64(noisy_bits)
    )
    assert_true(abs(observed - theoretical) <= 6.0 * standard_error)

    var repeated = simulate_qam_awgn_sweep(
        Span(orders), Span(noises), Span(seeds), symbols_per_point
    )
    for index in range(len(points)):
        assert_equal(
            points[index].result.bit_errors,
            repeated[index].result.bit_errors,
        )

    var empty_orders = List[Int]()
    var empty_noises = List[Float64]()
    var empty_seeds = List[UInt64]()
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(empty_orders), Span(noises), Span(seeds), 1
        )
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(orders), Span(empty_noises), Span(seeds), 1
        )
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(orders), Span(noises), Span(empty_seeds), 1
        )
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(orders), Span(noises), Span(seeds), 0
        )
    var bad_orders: List[Int] = [3]
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(bad_orders), Span(noises), Span(seeds), 1
        )
    var bad_noises: List[Float64] = [nan[DType.float64]()]
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(orders), Span(bad_noises), Span(seeds), 1
        )

    var capacity_noises: List[Float64] = [0.0]
    var capacity_seeds: List[UInt64] = [UInt64(11)]
    var capacity_points = simulate_qam_awgn_sweep(
        Span(orders), Span(capacity_noises), Span(capacity_seeds), 131072
    )
    assert_equal(len(capacity_points), 1)
    assert_equal(capacity_points[0].result.bit_count, 131072)
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(orders), Span(capacity_noises), Span(capacity_seeds), 131073
        )
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(orders), Span(capacity_noises), Span(capacity_seeds), Int.MIN
        )
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(orders), Span(capacity_noises), Span(capacity_seeds), Int.MAX
        )
    var many_seeds = List[UInt64](capacity=1024)
    for index in range(1024):
        many_seeds.append(UInt64(index))
    var point_capacity = simulate_qam_awgn_sweep(
        Span(orders), Span(capacity_noises), Span(many_seeds), 1
    )
    assert_equal(len(point_capacity), 1024)
    many_seeds.append(UInt64(1024))
    with assert_raises():
        _ = simulate_qam_awgn_sweep(
            Span(orders), Span(capacity_noises), Span(many_seeds), 1
        )


def test_simulate_wifi_legacy_bpsk_awgn_analytic_limits_and_edges() raises:
    var first = simulate_wifi_legacy_bpsk_awgn(
        8, 0.0, seed=UInt64(0x80211)
    )
    var second = simulate_wifi_legacy_bpsk_awgn(
        8, 0.0, seed=UInt64(0x80211)
    )
    assert_equal(first.bit_count, 144)
    assert_equal(first.bit_errors, 0)
    assert_equal(first.packet_count, 8)
    assert_equal(first.packet_errors, 0)
    assert_equal(first.ber, 0.0)
    assert_equal(first.per, 0.0)
    assert_equal(first.bler, first.per)
    assert_equal(first.bit_errors, second.bit_errors)

    # At overwhelming symmetric AWGN the received hard decisions are
    # independent of the payload, so BER tends to 1/2 and PER tends to one.
    var noisy = simulate_wifi_legacy_bpsk_awgn(
        256, 1.0e6, seed=UInt64(0xBADC0DE)
    )
    assert_true(abs(noisy.ber - 0.5) <= 0.08)
    assert_true(noisy.per >= 0.95)
    assert_equal(noisy.bler, noisy.per)
    assert_equal(
        noisy.ber,
        Float64(noisy.bit_errors) / Float64(noisy.bit_count),
    )

    with assert_raises():
        _ = simulate_wifi_legacy_bpsk_awgn(
            0, 0.0, seed=UInt64(1)
        )
    var packet_capacity = simulate_wifi_legacy_bpsk_awgn(
        512, 0.0, seed=UInt64(0x51A7)
    )
    assert_equal(packet_capacity.packet_count, 512)
    assert_equal(packet_capacity.packet_errors, 0)
    with assert_raises():
        _ = simulate_wifi_legacy_bpsk_awgn(
            513, 0.0, seed=UInt64(1)
        )
    with assert_raises():
        _ = simulate_wifi_legacy_bpsk_awgn(
            Int.MIN, 0.0, seed=UInt64(1)
        )
    with assert_raises():
        _ = simulate_wifi_legacy_bpsk_awgn(
            Int.MAX, 0.0, seed=UInt64(1)
        )
    for invalid_noise in [
        -1.0,
        nan[DType.float64](),
        inf[DType.float64](),
    ]:
        with assert_raises():
            _ = simulate_wifi_legacy_bpsk_awgn(
                1, invalid_noise, seed=UInt64(1)
            )


def test_simulate_wifi_legacy_bpsk_awgn_external_static_whole_chain_oracle() raises:
    """Check complete link results against a production-independent fixture.

    ``tests/fixtures/generate_wifi_legacy_bpsk_awgn_oracle.py`` V1 uses only
    the CPython 3.13.7 standard library.  It independently evaluates scalar
    integer scrambler/BCC/Viterbi recurrences, the BPSK/interleaver equations,
    direct O(N^2) DFT sums, and circular Box--Muller AWGN.  It imports neither
    this package nor Mojo and does not execute a production TX/RX round trip.

    The checked-in ``wifi_legacy_bpsk_awgn_oracle_v1.tsv`` records every input,
    binary64 big-endian noise-stream SHA-256, discrete-checkpoint SHA-256, and
    the minimum final BPSK decision margin.  Generator SHA-256 is
    90edb514f011b9b722b25c283d1cec184c224dca9145899272f3ed420a977d94;
    fixture SHA-256 is
    626d843b0d016d1338894c640e6568206527651960b071c86ec9b0ef6ec39705;
    canonical fixture-row SHA-256 is
    05c42137c99b7e606f624140f9dde8323c0aad3b122aa2832d06277579a5de05.
    The smallest diagnostic decision margin is 0x1.59daa87d0e600p-12,
    while all asserted API results are discrete counts or exact ratios, so
    the result tolerance is exact.
    """
    var fixture = _read_external_oracle_fixture(
        "wifi_legacy_bpsk_awgn_oracle_v1.tsv"
    )
    _require_lf_only_unique_trailing_newline(StringSlice(fixture))
    var lines = fixture.split("\n")
    assert_equal(len(lines), 14)
    assert_equal(lines[0], "# MWDSP-WIFI-LEGACY-BPSK-AWGN-ORACLE-V1")
    assert_equal(
        lines[1],
        "# generator_sha256=90edb514f011b9b722b25c283d1cec184c224dca9145899272f3ed420a977d94",
    )
    assert_equal(lines[2], "# generator_runtime=CPython_3.13.7")
    assert_equal(lines[3], "# dependencies=python_standard_library_only")
    assert_equal(
        lines[4],
        "# float_format=IEEE-754_binary64;noise_packing=big-endian_real_then_imag",
    )
    assert_equal(
        lines[5],
        "# result_tolerance=exact;minimum_bpsk_margin_is_diagnostic_only",
    )
    assert_equal(
        lines[6],
        "# canonical_rows_sha256=05c42137c99b7e606f624140f9dde8323c0aad3b122aa2832d06277579a5de05",
    )
    assert_equal(
        lines[7],
        "packets\tnoise_variance_hex\tseed_hex\tbit_count\tbit_errors\tpacket_errors\tminimum_bpsk_margin\tnoise_f64be_sha256\tcheckpoints_sha256\tnoise_q12be_fnv1a64\tcheckpoints_fnv1a64",
    )
    assert_equal(lines[13], "")
    for row_index in range(8, 13):
        var fields = lines[row_index].split("\t")
        assert_equal(len(fields), 11)
        var packets = atol(fields[0])
        var noise_variance = _parse_positive_hex_float_exact(fields[1])
        var seed = _parse_hex_u64_exact(fields[2])
        var expected_bits = atol(fields[3])
        var expected_bit_errors = atol(fields[4])
        var expected_packet_errors = atol(fields[5])
        assert_true(_parse_positive_hex_float_exact(fields[6]) > 0.0)
        _require_lower_hex_digest(fields[7])
        _require_lower_hex_digest(fields[8])
        var expected_noise_fingerprint = _parse_hex_u64_exact(fields[9])
        var expected_discrete_fingerprint = _parse_hex_u64_exact(fields[10])
        assert_equal(expected_bits, packets * 18)
        var actual = simulate_wifi_legacy_bpsk_awgn(
            packets, noise_variance, seed=seed
        )
        assert_equal(actual.bit_count, expected_bits)
        assert_equal(actual.bit_errors, expected_bit_errors)
        assert_equal(actual.packet_count, packets)
        assert_equal(actual.packet_errors, expected_packet_errors)
        assert_equal(
            actual.ber,
            Float64(expected_bit_errors) / Float64(expected_bits),
        )
        assert_equal(
            actual.per,
            Float64(expected_packet_errors) / Float64(packets),
        )
        assert_equal(actual.bler, actual.per)
        assert_equal(actual.noise_fingerprint, expected_noise_fingerprint)
        assert_equal(
            actual.discrete_fingerprint, expected_discrete_fingerprint
        )


def test_simulate_nr_pdsch_awgn_analytic_limits_and_edges() raises:
    var first = simulate_nr_pdsch_awgn(
        2, 0.0, seed=UInt64(0x5A5A), payload_bits=100
    )
    var second = simulate_nr_pdsch_awgn(
        2, 0.0, seed=UInt64(0x5A5A), payload_bits=100
    )
    assert_equal(first.bit_count, 200)
    assert_equal(first.bit_errors, 0)
    assert_equal(first.packet_count, 2)
    assert_equal(first.packet_errors, 0)
    assert_equal(first.ber, 0.0)
    assert_equal(first.bler, 0.0)
    assert_equal(first.bit_errors, second.bit_errors)
    assert_equal(first.packet_errors, second.packet_errors)

    # The same independent high-noise limit applies to the decoded payload;
    # block failures approach one while payload BER approaches one half.
    var noisy = simulate_nr_pdsch_awgn(
        12, 1.0e6, seed=UInt64(0x38_212), payload_bits=100
    )
    assert_true(abs(noisy.ber - 0.5) <= 0.15)
    assert_true(noisy.bler >= 0.75)
    assert_equal(noisy.bler, noisy.per)
    assert_equal(
        noisy.ber,
        Float64(noisy.bit_errors) / Float64(noisy.bit_count),
    )

    with assert_raises():
        _ = simulate_nr_pdsch_awgn(0, 0.0, seed=UInt64(1))
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, 0.0, seed=UInt64(1), payload_bits=0
        )
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, 0.0, seed=UInt64(1), output_bits=0
        )
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, 0.0, seed=UInt64(1), output_bits=481
        )
    for order in [0, 1, 3, 12]:
        with assert_raises():
            _ = simulate_nr_pdsch_awgn(
                1, 0.0, seed=UInt64(1), modulation_order=order
            )
    for invalid_noise in [
        -1.0,
        nan[DType.float64](),
        inf[DType.float64](),
    ]:
        with assert_raises():
            _ = simulate_nr_pdsch_awgn(
                1, invalid_noise, seed=UInt64(1)
            )
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(Int.MAX, 0.0, seed=UInt64(1))
    var packet_capacity = simulate_nr_pdsch_awgn(
        16, 0.0, seed=UInt64(0xCAFE)
    )
    assert_equal(packet_capacity.packet_count, 16)
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(17, 0.0, seed=UInt64(1))
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(Int.MIN, 0.0, seed=UInt64(1))
    var payload_capacity = simulate_nr_pdsch_awgn(
        1,
        0.0,
        seed=UInt64(0xB17),
        payload_bits=512,
        output_bits=2048,
    )
    assert_equal(payload_capacity.bit_count, 512)
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, 0.0, seed=UInt64(1), payload_bits=513, output_bits=2048
        )
    var output_capacity = simulate_nr_pdsch_awgn(
        1, 0.0, seed=UInt64(0xB17), output_bits=4096
    )
    assert_equal(output_capacity.packet_count, 1)
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, 0.0, seed=UInt64(1), output_bits=4098
        )
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, 0.0, seed=UInt64(1), output_bits=Int.MAX - 1
        )
    with assert_raises():
        _ = simulate_nr_pdsch_awgn(
            1, 0.0, seed=UInt64(1), output_bits=Int.MAX
        )


def test_simulate_nr_pdsch_awgn_external_static_nonzero_noise_oracle() raises:
    """Compare the whole-link result with a production-independent fixture.

    ``tests/fixtures/generate_nr_pdsch_awgn_oracle.py`` does not import this
    package or execute Mojo.  Its external TX reference uses catkira/py3gpp
    commit 17b432b30c965ffd350257ee4b1fc4de642c8e37 and the TS-derived BG2 table;
    independent scalar Python implements the LCG, Box--Muller AWGN, comb-2
    LS/interpolation/ZF receiver, QPSK LLRs, and flooding normalized min-sum.

    The frozen authorities are TS 38.211 V18.9.0 (official ZIP SHA-256
    6b44878ccf4b651441608ec810b6639a6e4939160ca64b4980738a58692ee140)
    and TS 38.212 V18.8.0 (official ZIP SHA-256
    1762858b2f09a5a48f5a4730ccbc72c43ff90bebb96c14833841e36a235c8e4c).
    The checked-in V1 TSV pins all inputs, per-packet errors, noise and stage
    hashes.  Generator SHA-256 is
    0be701507a6f879528b0bcb822fc0369e6c934ac6b9be3940d5053ffa5508f17;
    fixture SHA-256 is
    d733ae4855913293213f5d6427f51ee8f956c19d05e1d8902873e41a9c08738c;
    canonical-row SHA-256 is
    91f8e74415eb5ee187036fdb6a46a6855d56c37c6a998b19089360ec1b3ff143.
    The minimum payload posterior margin is 0x1.d42fa72faf270p-6.  All API
    outputs asserted below are discrete counts or exact derived ratios, so
    the result tolerance is exact.
    """
    var fixture = _read_external_oracle_fixture(
        "nr_pdsch_awgn_external_oracle_v1.tsv"
    )
    _require_lf_only_unique_trailing_newline(StringSlice(fixture))
    var lines = fixture.split("\n")
    assert_equal(len(lines), 15)
    assert_equal(lines[0], "# MWDSP-NR-PDSCH-AWGN-EXTERNAL-ORACLE-V1")
    assert_equal(
        lines[1],
        "# generator_sha256=0be701507a6f879528b0bcb822fc0369e6c934ac6b9be3940d5053ffa5508f17",
    )
    assert_equal(lines[2], "# generator_runtime=CPython_3.13.7")
    assert_equal(lines[3], "# numpy_version=2.3.2;scipy_version=1.16.1")
    assert_equal(
        lines[4], "# py3gpp_repository=https://github.com/catkira/py3gpp"
    )
    assert_equal(
        lines[5],
        "# py3gpp_commit=17b432b30c965ffd350257ee4b1fc4de642c8e37",
    )
    assert_equal(
        lines[6],
        "# normative_sources=3GPP_TS_38.211_V18.9.0_sha256_6b44878ccf4b651441608ec810b6639a6e4939160ca64b4980738a58692ee140;3GPP_TS_38.212_V18.8.0_sha256_1762858b2f09a5a48f5a4730ccbc72c43ff90bebb96c14833841e36a235c8e4c",
    )
    assert_equal(
        lines[7],
        "# profile=single_codeword_single_layer_QPSK_BG2_Zc20_C1_RV0_then_RV1_comb2_flat_gain_0.9_plus_0.2j",
    )
    assert_equal(
        lines[8],
        "# receiver=comb2_LS_linear_interpolation_ZF_piecewise_QPSK_LLR_flooding_normalized_min_sum_alpha_0.8_clip_50_iterations_30",
    )
    assert_equal(
        lines[9],
        "# bit_order=one_bit_per_int_MSB_first_CRC;packing=big_endian",
    )
    assert_equal(
        lines[10],
        "# result_tolerance=exact;posterior_margin_is_diagnostic_only",
    )
    assert_equal(
        lines[11],
        "# canonical_rows_sha256=91f8e74415eb5ee187036fdb6a46a6855d56c37c6a998b19089360ec1b3ff143",
    )
    assert_equal(
        lines[12],
        "packets\tnoise_variance_hex\tseed_hex\tpayload_bits\toutput_bits\tmodulation_order\tbit_count\tbit_errors\tpacket_errors\tper_packet_bit_errors\tper_packet_failures\tminimum_payload_posterior_margin\tnoise_f64be_sha256\tdiscrete_checkpoints_sha256\treceiver_f64be_sha256\tnoise_q12be_fnv1a64\tobservable_discrete_fnv1a64",
    )
    assert_equal(lines[14], "")
    var fields = lines[13].split("\t")
    assert_equal(len(fields), 17)
    var packets = atol(fields[0])
    var noise_variance = _parse_positive_hex_float_exact(fields[1])
    var seed = _parse_hex_u64_exact(fields[2])
    var payload_bits = atol(fields[3])
    var output_bits = atol(fields[4])
    var modulation_order = atol(fields[5])
    var expected_bits = atol(fields[6])
    var expected_bit_errors = atol(fields[7])
    var expected_packet_errors = atol(fields[8])
    assert_equal(fields[9], "11,31")
    assert_equal(fields[10], "1,1")
    assert_true(_parse_positive_hex_float_exact(fields[11]) > 0.0)
    _require_lower_hex_digest(fields[12])
    _require_lower_hex_digest(fields[13])
    _require_lower_hex_digest(fields[14])
    var expected_noise_fingerprint = _parse_hex_u64_exact(fields[15])
    var expected_discrete_fingerprint = _parse_hex_u64_exact(fields[16])
    assert_equal(expected_bits, packets * payload_bits)
    var actual = simulate_nr_pdsch_awgn(
        packets,
        noise_variance,
        seed=seed,
        payload_bits=payload_bits,
        output_bits=output_bits,
        modulation_order=modulation_order,
    )
    assert_equal(actual.bit_count, packets * payload_bits)
    assert_equal(actual.bit_errors, expected_bit_errors)
    assert_equal(actual.packet_count, packets)
    assert_equal(actual.packet_errors, expected_packet_errors)
    assert_equal(
        actual.ber,
        Float64(expected_bit_errors) / Float64(packets * payload_bits),
    )
    assert_equal(
        actual.per,
        Float64(expected_packet_errors) / Float64(packets),
    )
    assert_equal(actual.bler, actual.per)
    assert_equal(actual.noise_fingerprint, expected_noise_fingerprint)
    assert_equal(
        actual.discrete_fingerprint, expected_discrete_fingerprint
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
