"""Canonical deterministic text vectors for RTL/FPGA/ASIC co-verification."""

from std.collections import Span
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.quantization import (
    QFormat,
    require_raw_fits,
    validate_qformat,
)
from wireless_dsp.numerics.scale_schedule import ScaleTrace


def _fnv1a_byte(mut state: UInt64, value: UInt8):
    state ^= UInt64(value)
    state *= UInt64(1099511628211)


def _fnv1a_text(mut state: UInt64, value: StringSlice):
    var bytes = value.as_bytes()
    for index in range(len(bytes)):
        _fnv1a_byte(state, UInt8(bytes[index]))


def _fnv1a_word(mut state: UInt64, value: Int64):
    var word = UInt64(value)
    for byte_index in range(8):
        _fnv1a_byte(
            state,
            UInt8((word >> UInt64(8 * byte_index)) & UInt64(0xff)),
        )


def _header_and_words_checksum(
    header: StringSlice, values: Span[Int64, ...]
) -> UInt64:
    var state = UInt64(14695981039346656037)
    _fnv1a_text(state, header)
    for index in range(len(values)):
        _fnv1a_word(state, values[index])
    return state


def _header_and_complex_checksum(
    header: StringSlice, values: Span[ComplexRaw, ...]
) -> UInt64:
    var state = UInt64(14695981039346656037)
    _fnv1a_text(state, header)
    for index in range(len(values)):
        _fnv1a_word(state, values[index].re)
        _fnv1a_word(state, values[index].im)
    return state


def fixed_raw_checksum(values: Span[Int64, ...]) -> UInt64:
    """FNV-1a over canonical little-endian two's-complement Int64 words."""
    var result = UInt64(14695981039346656037)
    for i in range(len(values)):
        var word = UInt64(values[i])
        for byte_index in range(8):
            _fnv1a_byte(
                result,
                UInt8((word >> UInt64(8 * byte_index)) & UInt64(0xff)),
            )
    return result


def complex_raw_checksum(values: Span[ComplexRaw, ...]) -> UInt64:
    """FNV-1a over interleaved little-endian real/imag Int64 words."""
    var result = UInt64(14695981039346656037)
    for i in range(len(values)):
        var real_word = UInt64(values[i].re)
        var imag_word = UInt64(values[i].im)
        for byte_index in range(8):
            _fnv1a_byte(
                result,
                UInt8(
                    (real_word >> UInt64(8 * byte_index)) & UInt64(0xff)
                ),
            )
        for byte_index in range(8):
            _fnv1a_byte(
                result,
                UInt8(
                    (imag_word >> UInt64(8 * byte_index)) & UInt64(0xff)
                ),
            )
    return result


def serialize_fixed_vector(
    testcase_id: StringSlice,
    stage: StringSlice,
    values: Span[Int64, ...],
    qformat: QFormat,
    stride: Int = 1,
    version: Int = 1,
) raises -> String:
    """Serialize a contiguous scalar vector using the canonical V2 record.

    The V2 checksum binds the complete canonical UTF-8 header (including
    testcase identity and numeric semantics) followed by the raw data as
    little-endian Int64 words.  A ``Span`` is contiguous, so accepting any
    stride other than one would create false wire metadata and is rejected.
    """
    if testcase_id.byte_length() == 0 or stage.byte_length() == 0:
        raise Error("fixed vector testcase and stage must be non-empty")
    if stride != 1 or version < 1:
        raise Error("contiguous fixed vector requires stride=1 and positive version")
    if (
        "\n" in testcase_id or "\r" in testcase_id
        or "\n" in stage or "\r" in stage
    ):
        raise Error("fixed vector identifiers cannot contain line breaks")
    var validated_qformat = validate_qformat(qformat)
    for i in range(len(values)):
        require_raw_fits(values[i], validated_qformat)

    var header = String()
    header.write("MWDSP-FIXED-V2\n")
    header.write("testcase=", testcase_id, "\n")
    header.write("stage=", stage, "\n")
    header.write("version=", version, "\n")
    header.write("dtype=sint", validated_qformat.storage_bits, "\n")
    header.write("shape=", len(values), "\n")
    header.write("stride=1\n")
    header.write("layout=scalar-contiguous\n")
    header.write("storage_bits=", validated_qformat.storage_bits, "\n")
    header.write("fraction_bits=", validated_qformat.fraction_bits, "\n")
    header.write("scale_numerator=1\n")
    header.write("scale_denominator=", validated_qformat.scale(), "\n")
    header.write("rounding=", validated_qformat.rounding_mode, "\n")
    header.write("overflow=", validated_qformat.overflow_mode, "\n")
    header.write("checksum_algorithm=fnv1a64\n")
    header.write("checksum_scope=header-utf8+data-int64-le\n")
    var checksum = _header_and_words_checksum(StringSlice(header), values)
    var result = header^
    result.write("checksum=", checksum, "\n")
    result.write("data=")
    for i in range(len(values)):
        if i != 0:
            result.write(",")
        result.write(values[i])
    result.write("\n")
    return result^


def serialize_complex_fixed_vector(
    testcase_id: StringSlice,
    stage: StringSlice,
    values: Span[ComplexRaw, ...],
    qformat: QFormat,
    stride: Int = 1,
    version: Int = 1,
) raises -> String:
    """Serialize a contiguous complex vector using the canonical V2 record."""
    if testcase_id.byte_length() == 0 or stage.byte_length() == 0:
        raise Error("complex vector testcase and stage must be non-empty")
    if stride != 1 or version < 1:
        raise Error("contiguous complex vector requires stride=1 and positive version")
    if (
        "\n" in testcase_id or "\r" in testcase_id
        or "\n" in stage or "\r" in stage
    ):
        raise Error("complex vector identifiers cannot contain line breaks")
    var validated_qformat = validate_qformat(qformat)
    for i in range(len(values)):
        require_raw_fits(values[i].re, validated_qformat)
        require_raw_fits(values[i].im, validated_qformat)

    var header = String()
    header.write("MWDSP-COMPLEX-FIXED-V2\n")
    header.write("testcase=", testcase_id, "\n")
    header.write("stage=", stage, "\n")
    header.write("version=", version, "\n")
    header.write("dtype=sint", validated_qformat.storage_bits, "\n")
    header.write("shape=", len(values), "x2\n")
    header.write("stride=1\n")
    header.write("layout=iq-interleaved-contiguous\n")
    header.write("storage_bits=", validated_qformat.storage_bits, "\n")
    header.write("fraction_bits=", validated_qformat.fraction_bits, "\n")
    header.write("scale_numerator=1\n")
    header.write("scale_denominator=", validated_qformat.scale(), "\n")
    header.write("rounding=", validated_qformat.rounding_mode, "\n")
    header.write("overflow=", validated_qformat.overflow_mode, "\n")
    header.write("checksum_algorithm=fnv1a64\n")
    header.write("checksum_scope=header-utf8+data-iq-int64-le\n")
    var checksum = _header_and_complex_checksum(
        StringSlice(header), values
    )
    var result = header^
    result.write("checksum=", checksum, "\n")
    result.write("data_iq=")
    for i in range(len(values)):
        if i != 0:
            result.write(",")
        result.write(values[i].re, ":", values[i].im)
    result.write("\n")
    return result^


def serialize_scale_trace(
    testcase_id: StringSlice,
    stage: StringSlice,
    trace: ScaleTrace,
    version: Int = 1,
) raises -> String:
    """Serialize every registered scale boundary using the V2 contract."""
    if testcase_id.byte_length() == 0 or stage.byte_length() == 0:
        raise Error("scale trace testcase and stage must be non-empty")
    if (
        "\n" in testcase_id or "\r" in testcase_id
        or "\n" in stage or "\r" in stage
    ):
        raise Error("scale trace identifiers cannot contain line breaks")
    if version < 1:
        raise Error("scale trace version must be positive")
    var count = len(trace.values)
    if count > Int.MAX // 6:
        raise Error("scale trace checksum row count is unrepresentable")
    if (
        len(trace.fraction_bits) != count
        or len(trace.storage_bits) != count
        or len(trace.right_shifts) != count
        or len(trace.rounding_modes) != count
        or len(trace.overflow_modes) != count
    ):
        raise Error("scale trace metadata lengths are inconsistent")
    for i in range(count):
        var qformat = validate_qformat(QFormat(
            trace.storage_bits[i],
            trace.fraction_bits[i],
            trace.rounding_modes[i],
            trace.overflow_modes[i],
        ))
        require_raw_fits(trace.values[i], qformat)
        if trace.right_shifts[i] < 0 or trace.right_shifts[i] > 61:
            raise Error("scale trace right shift must be in [0, 61]")

    var header = String()
    header.write("MWDSP-SCALE-TRACE-V2\n")
    header.write("testcase=", testcase_id, "\n")
    header.write("stage=", stage, "\n")
    header.write("version=", version, "\n")
    header.write("shape=", count, "x6\n")
    header.write(
        "columns=raw:storage_bits:fraction_bits:right_shift:rounding:overflow\n"
    )
    header.write("checksum_algorithm=fnv1a64\n")
    header.write("checksum_scope=header-utf8+rows-int64-le\n")
    var checksum_values = List[Int64](capacity=count * 6)
    for i in range(count):
        checksum_values.append(trace.values[i])
        checksum_values.append(Int64(trace.storage_bits[i]))
        checksum_values.append(Int64(trace.fraction_bits[i]))
        checksum_values.append(Int64(trace.right_shifts[i]))
        checksum_values.append(Int64(trace.rounding_modes[i]))
        checksum_values.append(Int64(trace.overflow_modes[i]))
    var checksum = _header_and_words_checksum(
        StringSlice(header), Span(checksum_values)
    )
    var result = header^
    result.write("checksum=", checksum, "\n")
    result.write("data=")
    for i in range(count):
        if i != 0:
            result.write(",")
        result.write(
            trace.values[i],
            ":",
            trace.storage_bits[i],
            ":",
            trace.fraction_bits[i],
            ":",
            trace.right_shifts[i],
            ":",
            trace.rounding_modes[i],
            ":",
            trace.overflow_modes[i],
        )
    result.write("\n")
    return result^
