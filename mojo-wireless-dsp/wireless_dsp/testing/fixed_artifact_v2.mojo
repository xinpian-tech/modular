"""Strict parser and deterministic representative corpus for fixed artifacts V2."""

from std.collections import Span
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.fixed import (
    ROUND_NEAREST_AWAY,
    ROUND_TOWARD_ZERO,
    OVERFLOW_SATURATE,
    OVERFLOW_WRAP,
)
from wireless_dsp.numerics.quantization import QFormat, require_raw_fits
from wireless_dsp.numerics.scale_schedule import (
    ScaleStage,
    ScaleTrace,
    apply_scale_schedule,
)
from wireless_dsp.backend.fixed_fft_reference import (
    fixed_fft_radix2_trace_raw,
    serialize_fixed_fft_trace,
)
from .fixed_vectors import (
    fixed_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
    serialize_scale_trace,
)


comptime FIXED_ARTIFACT_V2_SCALAR = 1
comptime FIXED_ARTIFACT_V2_COMPLEX = 2
comptime FIXED_ARTIFACT_V2_SCALE_TRACE = 3

comptime FIXED_ARTIFACT_V2_SCALAR_SCHEMA = "MWDSP-FIXED-V2"
comptime FIXED_ARTIFACT_V2_COMPLEX_SCHEMA = "MWDSP-COMPLEX-FIXED-V2"
comptime FIXED_ARTIFACT_V2_SCALE_SCHEMA = "MWDSP-SCALE-TRACE-V2"
comptime FIXED_ARTIFACT_V2_FFT_BUNDLE_SCHEMA = "MWDSP-FIXED-FFT-TRACE-V2"
comptime FIXED_ARTIFACT_V2_MANIFEST_SCHEMA = "MWDSP-FIXED-V2-MANIFEST"

comptime FIXED_ARTIFACT_V2_SCALAR_FILE = "scalar.mwdsp"
comptime FIXED_ARTIFACT_V2_COMPLEX_FILE = "complex.mwdsp"
comptime FIXED_ARTIFACT_V2_SCALE_FILE = "scale-trace.mwdsp"
comptime FIXED_ARTIFACT_V2_FFT_FILE = "fft-trace.mwdsp"
comptime FIXED_ARTIFACT_V2_MANIFEST_FILE = "manifest.tsv"


struct FixedArtifactV2Record(Movable):
    """One validated V2 record with an owned, canonical flat Int64 payload."""

    var kind: Int
    var schema: String
    var testcase_id: String
    var stage: String
    var version: Int
    var logical_count: Int
    var storage_bits: Int
    var fraction_bits: Int
    var rounding_mode: Int
    var overflow_mode: Int
    var values: List[Int64]
    var checksum: UInt64
    var byte_count: Int

    def __init__(
        out self,
        kind: Int,
        schema: StringSlice,
        testcase_id: StringSlice,
        stage: StringSlice,
        version: Int,
        logical_count: Int,
        storage_bits: Int,
        fraction_bits: Int,
        rounding_mode: Int,
        overflow_mode: Int,
        var values: List[Int64],
        checksum: UInt64,
        byte_count: Int,
    ):
        self.kind = kind
        self.schema = String(schema)
        self.testcase_id = String(testcase_id)
        self.stage = String(stage)
        self.version = version
        self.logical_count = logical_count
        self.storage_bits = storage_bits
        self.fraction_bits = fraction_bits
        self.rounding_mode = rounding_mode
        self.overflow_mode = overflow_mode
        self.values = values^
        self.checksum = checksum
        self.byte_count = byte_count


struct FixedArtifactV2ManifestEntry(Movable):
    """One manifest binding from a safe relative filename to exact bytes."""

    var filename: String
    var schema: String
    var byte_count: Int
    var checksum: UInt64

    def __init__(
        out self,
        filename: StringSlice,
        schema: StringSlice,
        byte_count: Int,
        checksum: UInt64,
    ):
        self.filename = String(filename)
        self.schema = String(schema)
        self.byte_count = byte_count
        self.checksum = checksum


struct FixedArtifactV2Corpus(Movable):
    """The four small representative artifacts and their canonical manifest."""

    var scalar: String
    var complex: String
    var scale_trace: String
    var fft_trace: String
    var manifest: String

    def __init__(
        out self,
        var scalar: String,
        var complex: String,
        var scale_trace: String,
        var fft_trace: String,
        var manifest: String,
    ):
        self.scalar = scalar^
        self.complex = complex^
        self.scale_trace = scale_trace^
        self.fft_trace = fft_trace^
        self.manifest = manifest^


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


def fixed_artifact_v2_bytes_checksum(value: StringSlice) -> UInt64:
    """FNV-1a-64 over the complete UTF-8 file bytes for manifest binding."""
    var state = UInt64(14695981039346656037)
    _fnv1a_text(state, value)
    return state


def _header_words_checksum(
    header: StringSlice, values: Span[Int64, ...]
) -> UInt64:
    var state = UInt64(14695981039346656037)
    _fnv1a_text(state, header)
    for index in range(len(values)):
        _fnv1a_word(state, values[index])
    return state


def _owned_field(line: StringSlice, prefix: StringSlice) raises -> String:
    if not line.startswith(prefix):
        raise Error("fixed artifact field order/name mismatch; expected ", prefix)
    return String(line[byte=prefix.byte_length():])


def _parse_u64(value: StringSlice) raises -> UInt64:
    var length = value.byte_length()
    if length == 0:
        raise Error("fixed artifact integer field is empty")
    var bytes = value.as_bytes()
    if length > 1 and UInt8(bytes[0]) == UInt8(ord("0")):
        raise Error("fixed artifact integers must use canonical decimal text")
    var result = UInt64(0)
    for index in range(length):
        var byte = UInt8(bytes[index])
        if byte < UInt8(ord("0")) or byte > UInt8(ord("9")):
            raise Error("fixed artifact integer contains a non-decimal byte")
        var digit = UInt64(byte - UInt8(ord("0")))
        if result > (UInt64.MAX - digit) // UInt64(10):
            raise Error("fixed artifact unsigned integer overflows UInt64")
        result = result * UInt64(10) + digit
    return result


def _parse_nonnegative_int(value: StringSlice) raises -> Int:
    var parsed = _parse_u64(value)
    if parsed > UInt64(Int.MAX):
        raise Error("fixed artifact integer overflows Int")
    return Int(parsed)


def _parse_i64(value: StringSlice) raises -> Int64:
    var length = value.byte_length()
    if length == 0:
        raise Error("fixed artifact signed integer field is empty")
    var bytes = value.as_bytes()
    var negative = UInt8(bytes[0]) == UInt8(ord("-"))
    var magnitude_text: String
    if negative:
        if length == 1:
            raise Error("fixed artifact signed integer has no digits")
        magnitude_text = String(value[byte=1:])
    else:
        magnitude_text = String(value)
    var magnitude = _parse_u64(StringSlice(magnitude_text))
    if negative:
        if magnitude == 0:
            raise Error("fixed artifact signed zero is not canonical")
        var minimum_magnitude = UInt64(1) << UInt64(63)
        if magnitude > minimum_magnitude:
            raise Error("fixed artifact signed integer underflows Int64")
        if magnitude == minimum_magnitude:
            return Int64.MIN_FINITE
        return -Int64(magnitude)
    if magnitude > UInt64(Int64.MAX_FINITE):
        raise Error("fixed artifact signed integer overflows Int64")
    return Int64(magnitude)


def _validate_text_envelope(text: StringSlice, label: StringSlice) raises:
    if text.byte_length() == 0 or not text.endswith("\n"):
        raise Error(label, " must be non-empty and end with one LF")
    if "\r" in text:
        raise Error(label, " must use LF rather than CR/CRLF")


def _shape_dimension(value: StringSlice, trailing: StringSlice) raises -> Int:
    var parts = value.split("x")
    if len(parts) != 2 or parts[1] != trailing:
        raise Error("fixed artifact shape has the wrong rank or trailing dimension")
    return _parse_nonnegative_int(parts[0])


def _build_header[O: ImmOrigin](
    lines: List[StringSlice[O]], count: Int
) -> String:
    var header = String()
    for index in range(count):
        header.write(lines[index], "\n")
    return header^


def _parse_scalar_or_complex_record[O: ImmOrigin](
    lines: List[StringSlice[O]], is_complex: Bool
) raises -> FixedArtifactV2Record:
    if len(lines) != 19 or lines[18].byte_length() != 0:
        raise Error("fixed scalar/complex artifact has a truncated or extra field")
    var expected_schema = (
        StringSlice(FIXED_ARTIFACT_V2_COMPLEX_SCHEMA)
        if is_complex
        else StringSlice(FIXED_ARTIFACT_V2_SCALAR_SCHEMA)
    )
    if lines[0] != expected_schema:
        raise Error("fixed artifact magic/schema mismatch")
    var original = String()
    for line_index in range(len(lines) - 1):
        original.write(lines[line_index], "\n")
    var testcase = _owned_field(lines[1], "testcase=")
    var stage = _owned_field(lines[2], "stage=")
    if testcase.byte_length() == 0 or stage.byte_length() == 0:
        raise Error("fixed artifact testcase and stage must be non-empty")
    var version_text = _owned_field(lines[3], "version=")
    var version = _parse_nonnegative_int(StringSlice(version_text))
    if version < 1:
        raise Error("fixed artifact vector revision must be positive")
    var dtype = _owned_field(lines[4], "dtype=")
    if not dtype.startswith("sint"):
        raise Error("fixed artifact dtype must be a signed integer")
    var dtype_width_text = StringSlice(dtype)[byte=4:]
    var dtype_width = _parse_nonnegative_int(dtype_width_text)
    var shape_text = _owned_field(lines[5], "shape=")
    var logical_count = (
        _shape_dimension(StringSlice(shape_text), "2")
        if is_complex
        else _parse_nonnegative_int(StringSlice(shape_text))
    )
    var stride_text = _owned_field(lines[6], "stride=")
    if _parse_nonnegative_int(StringSlice(stride_text)) != 1:
        raise Error("fixed artifact contiguous Span stride must equal one")
    var layout = _owned_field(lines[7], "layout=")
    var expected_layout = (
        "iq-interleaved-contiguous" if is_complex else "scalar-contiguous"
    )
    if layout != expected_layout:
        raise Error("fixed artifact layout does not match its schema")
    var storage_text = _owned_field(lines[8], "storage_bits=")
    var fraction_text = _owned_field(lines[9], "fraction_bits=")
    var storage_bits = _parse_nonnegative_int(StringSlice(storage_text))
    var fraction_bits = _parse_nonnegative_int(StringSlice(fraction_text))
    if dtype_width != storage_bits:
        raise Error("fixed artifact dtype width differs from Q-format storage")
    var numerator_text = _owned_field(lines[10], "scale_numerator=")
    if _parse_nonnegative_int(StringSlice(numerator_text)) != 1:
        raise Error("fixed artifact scale numerator must equal one")
    var denominator_text = _owned_field(lines[11], "scale_denominator=")
    var denominator = _parse_u64(StringSlice(denominator_text))
    var rounding_text = _owned_field(lines[12], "rounding=")
    var overflow_text = _owned_field(lines[13], "overflow=")
    var rounding = _parse_nonnegative_int(StringSlice(rounding_text))
    var overflow = _parse_nonnegative_int(StringSlice(overflow_text))
    var qformat = QFormat(storage_bits, fraction_bits, rounding, overflow)
    if denominator != UInt64(qformat.scale()):
        raise Error("fixed artifact scale denominator differs from Q-format")
    var algorithm = _owned_field(lines[14], "checksum_algorithm=")
    if algorithm != "fnv1a64":
        raise Error("fixed artifact checksum algorithm is unsupported")
    var scope = _owned_field(lines[15], "checksum_scope=")
    var expected_scope = (
        "header-utf8+data-iq-int64-le"
        if is_complex
        else "header-utf8+data-int64-le"
    )
    if scope != expected_scope:
        raise Error("fixed artifact checksum scope does not match its schema")
    var checksum_text = _owned_field(lines[16], "checksum=")
    var declared_checksum = _parse_u64(StringSlice(checksum_text))
    var data_prefix = "data_iq=" if is_complex else "data="
    var data = _owned_field(lines[17], data_prefix)
    if logical_count > data.byte_length() + 1:
        raise Error("fixed artifact shape exceeds its textual payload bound")
    var flat_values = List[Int64](
        capacity=logical_count * (2 if is_complex else 1)
    )
    if logical_count == 0:
        if data.byte_length() != 0:
            raise Error("fixed artifact empty shape has non-empty data")
    else:
        var elements = data.split(",")
        if len(elements) != logical_count:
            raise Error("fixed artifact shape and data length differ")
        for element in elements:
            if is_complex:
                var iq = element.split(":")
                if len(iq) != 2:
                    raise Error("complex fixed artifact element is not one I:Q pair")
                var real = _parse_i64(iq[0])
                var imag = _parse_i64(iq[1])
                require_raw_fits(real, qformat)
                require_raw_fits(imag, qformat)
                flat_values.append(real)
                flat_values.append(imag)
            else:
                var raw = _parse_i64(element)
                require_raw_fits(raw, qformat)
                flat_values.append(raw)

    var header = _build_header(lines, 16)
    var actual_checksum = _header_words_checksum(
        StringSlice(header), Span(flat_values)
    )
    if actual_checksum != declared_checksum:
        raise Error("fixed artifact header/data checksum mismatch")

    var reencoded: String
    if is_complex:
        var complex_values = List[ComplexRaw](capacity=logical_count)
        for index in range(logical_count):
            complex_values.append(ComplexRaw(
                flat_values[2 * index], flat_values[2 * index + 1]
            ))
        reencoded = serialize_complex_fixed_vector(
            StringSlice(testcase),
            StringSlice(stage),
            Span(complex_values),
            qformat,
            version=version,
        )
    else:
        reencoded = serialize_fixed_vector(
            StringSlice(testcase),
            StringSlice(stage),
            Span(flat_values),
            qformat,
            version=version,
        )
    if reencoded != original:
        raise Error("fixed artifact text is not the canonical V2 encoding")
    return FixedArtifactV2Record(
        FIXED_ARTIFACT_V2_COMPLEX if is_complex else FIXED_ARTIFACT_V2_SCALAR,
        expected_schema,
        StringSlice(testcase),
        StringSlice(stage),
        version,
        logical_count,
        storage_bits,
        fraction_bits,
        rounding,
        overflow,
        flat_values^,
        declared_checksum,
        original.byte_length(),
    )


def _parse_scale_record[O: ImmOrigin](
    lines: List[StringSlice[O]]
) raises -> FixedArtifactV2Record:
    if len(lines) != 11 or lines[10].byte_length() != 0:
        raise Error("fixed scale artifact has a truncated or extra field")
    if String(lines[0]) != FIXED_ARTIFACT_V2_SCALE_SCHEMA:
        raise Error("fixed scale artifact magic/schema mismatch")
    var original = String()
    for line_index in range(len(lines) - 1):
        original.write(lines[line_index], "\n")
    var testcase = _owned_field(lines[1], "testcase=")
    var stage = _owned_field(lines[2], "stage=")
    if testcase.byte_length() == 0 or stage.byte_length() == 0:
        raise Error("fixed scale artifact testcase and stage must be non-empty")
    var version_text = _owned_field(lines[3], "version=")
    var version = _parse_nonnegative_int(StringSlice(version_text))
    if version < 1:
        raise Error("fixed scale artifact vector revision must be positive")
    var shape_text = _owned_field(lines[4], "shape=")
    var logical_count = _shape_dimension(StringSlice(shape_text), "6")
    var columns = _owned_field(lines[5], "columns=")
    if columns != (
        "raw:storage_bits:fraction_bits:right_shift:rounding:overflow"
    ):
        raise Error("fixed scale artifact columns do not match V2")
    var algorithm = _owned_field(lines[6], "checksum_algorithm=")
    if algorithm != "fnv1a64":
        raise Error("fixed scale artifact checksum algorithm is unsupported")
    var scope = _owned_field(lines[7], "checksum_scope=")
    if scope != "header-utf8+rows-int64-le":
        raise Error("fixed scale artifact checksum scope does not match V2")
    var checksum_text = _owned_field(lines[8], "checksum=")
    var declared_checksum = _parse_u64(StringSlice(checksum_text))
    var data = _owned_field(lines[9], "data=")
    if (
        logical_count > data.byte_length() + 1
        or logical_count > Int.MAX // 6
    ):
        raise Error("fixed scale shape exceeds its textual payload bound")
    var flat_values = List[Int64](capacity=logical_count * 6)
    var trace_values = List[Int64](capacity=logical_count)
    var fractions = List[Int](capacity=logical_count)
    var widths = List[Int](capacity=logical_count)
    var shifts = List[Int](capacity=logical_count)
    var roundings = List[Int](capacity=logical_count)
    var overflows = List[Int](capacity=logical_count)
    if logical_count == 0:
        if data.byte_length() != 0:
            raise Error("empty fixed scale shape has non-empty data")
    else:
        var rows = data.split(",")
        if len(rows) != logical_count:
            raise Error("fixed scale shape and row count differ")
        for row in rows:
            var fields = row.split(":")
            if len(fields) != 6:
                raise Error("fixed scale row must have exactly six fields")
            var raw = _parse_i64(fields[0])
            var width = _parse_nonnegative_int(fields[1])
            var fraction = _parse_nonnegative_int(fields[2])
            var shift = _parse_nonnegative_int(fields[3])
            var rounding = _parse_nonnegative_int(fields[4])
            var overflow = _parse_nonnegative_int(fields[5])
            if shift > 61:
                raise Error("fixed scale row right shift exceeds 61")
            var qformat = QFormat(width, fraction, rounding, overflow)
            require_raw_fits(raw, qformat)
            trace_values.append(raw)
            widths.append(width)
            fractions.append(fraction)
            shifts.append(shift)
            roundings.append(rounding)
            overflows.append(overflow)
            flat_values.append(raw)
            flat_values.append(Int64(width))
            flat_values.append(Int64(fraction))
            flat_values.append(Int64(shift))
            flat_values.append(Int64(rounding))
            flat_values.append(Int64(overflow))

    var header = _build_header(lines, 8)
    var actual_checksum = _header_words_checksum(
        StringSlice(header), Span(flat_values)
    )
    if actual_checksum != declared_checksum:
        raise Error("fixed scale artifact header/row checksum mismatch")
    var trace = ScaleTrace(
        trace_values^,
        fractions^,
        widths^,
        shifts^,
        roundings^,
        overflows^,
    )
    var reencoded = serialize_scale_trace(
        StringSlice(testcase),
        StringSlice(stage),
        trace,
        version=version,
    )
    if reencoded != original:
        raise Error("fixed scale artifact text is not canonical V2")
    return FixedArtifactV2Record(
        FIXED_ARTIFACT_V2_SCALE_TRACE,
        FIXED_ARTIFACT_V2_SCALE_SCHEMA,
        StringSlice(testcase),
        StringSlice(stage),
        version,
        logical_count,
        -1,
        -1,
        -1,
        -1,
        flat_values^,
        declared_checksum,
        original.byte_length(),
    )


def parse_fixed_artifact_v2_record(
    text: StringSlice
) raises -> FixedArtifactV2Record:
    """Parse, semantically validate, re-checksum, and canonicalize one record."""
    _validate_text_envelope(text, "fixed artifact record")
    var lines = text.split("\n")
    if len(lines) == 0:
        raise Error("fixed artifact record has no magic")
    if lines[0] == FIXED_ARTIFACT_V2_SCALAR_SCHEMA:
        return _parse_scalar_or_complex_record(lines, False)
    if lines[0] == FIXED_ARTIFACT_V2_COMPLEX_SCHEMA:
        return _parse_scalar_or_complex_record(lines, True)
    if lines[0] == FIXED_ARTIFACT_V2_SCALE_SCHEMA:
        return _parse_scale_record(lines)
    raise Error("unknown fixed artifact magic/schema")


def parse_fixed_artifact_v2_records(
    text: StringSlice
) raises -> List[FixedArtifactV2Record]:
    """Parse a non-empty concatenation of canonical V2 records."""
    _validate_text_envelope(text, "fixed artifact record stream")
    var lines = text.split("\n")
    var line_count = len(lines) - 1
    var records = List[FixedArtifactV2Record]()
    var index = 0
    while index < line_count:
        var record_line_count: Int
        if (
            lines[index] == FIXED_ARTIFACT_V2_SCALAR_SCHEMA
            or lines[index] == FIXED_ARTIFACT_V2_COMPLEX_SCHEMA
        ):
            record_line_count = 18
        elif lines[index] == FIXED_ARTIFACT_V2_SCALE_SCHEMA:
            record_line_count = 10
        else:
            raise Error("unknown fixed artifact magic inside record stream")
        if index + record_line_count > line_count:
            raise Error("truncated fixed artifact record stream")
        var record_text = String()
        for line_index in range(record_line_count):
            record_text.write(lines[index + line_index], "\n")
        records.append(parse_fixed_artifact_v2_record(
            StringSlice(record_text)
        ))
        index += record_line_count
    if len(records) == 0 or index != line_count:
        raise Error("fixed artifact record stream has trailing bytes")
    return records^


def _same_record_identity(
    lhs: FixedArtifactV2Record, rhs: FixedArtifactV2Record
) -> Bool:
    return (
        lhs.testcase_id == rhs.testcase_id
        and lhs.version == rhs.version
    )


def validate_fixed_fft_trace_v2_bundle(
    records: List[FixedArtifactV2Record]
) raises:
    """Validate the record graph and aggregate checksum of one FFT trace."""
    if len(records) < 6:
        raise Error("fixed FFT trace bundle has too few records")
    ref config = records[0]
    if (
        config.kind != FIXED_ARTIFACT_V2_SCALAR
        or config.storage_bits != 32
        or config.fraction_bits != 0
        or config.rounding_mode != ROUND_NEAREST_AWAY
        or config.overflow_mode != OVERFLOW_SATURATE
        or config.logical_count != 2
        or not config.stage.endswith("-config")
    ):
        raise Error("fixed FFT trace config record is invalid")
    var size = Int(config.values[0])
    var stage_count = Int(config.values[1])
    if size < 1 or stage_count < 0 or len(records) != stage_count + 6:
        raise Error("fixed FFT trace config dimensions are inconsistent")
    var expected_stages = 0
    var power = size
    while power > 1 and (power & 1) == 0:
        expected_stages += 1
        power >>= 1
    if power != 1 or expected_stages != stage_count:
        raise Error("fixed FFT trace size/stage count is not radix-2")
    var prefix = String(config.stage.removesuffix("-config"))
    ref input = records[1]
    ref twiddles = records[2]
    ref schedule = records[3]
    var input_stage = prefix + "-input"
    var twiddle_stage = prefix + "-twiddle-rom"
    var schedule_stage = prefix + "-schedule"
    if (
        not _same_record_identity(config, input)
        or not _same_record_identity(config, twiddles)
        or not _same_record_identity(config, schedule)
        or input.kind != FIXED_ARTIFACT_V2_COMPLEX
        or input.stage != input_stage
        or input.logical_count != size
        or twiddles.kind != FIXED_ARTIFACT_V2_COMPLEX
        or twiddles.stage != twiddle_stage
        or twiddles.logical_count != size // 2
        or schedule.kind != FIXED_ARTIFACT_V2_SCALE_TRACE
        or schedule.stage != schedule_stage
        or schedule.logical_count != stage_count
    ):
        raise Error("fixed FFT trace input/ROM/schedule records are inconsistent")

    var aggregate_words: List[Int64] = [
        Int64(2),
        Int64(size),
        Int64(stage_count),
        Int64(input.storage_bits),
        Int64(input.fraction_bits),
        Int64(input.rounding_mode),
        Int64(input.overflow_mode),
        Int64(twiddles.storage_bits),
        Int64(twiddles.fraction_bits),
        Int64(twiddles.rounding_mode),
        Int64(twiddles.overflow_mode),
    ]
    for stage_index in range(stage_count):
        var row = 6 * stage_index
        aggregate_words.append(schedule.values[row + 1])
        aggregate_words.append(schedule.values[row + 2])
        aggregate_words.append(schedule.values[row + 3])
        aggregate_words.append(schedule.values[row + 4])
        aggregate_words.append(schedule.values[row + 5])
    for value in input.values:
        aggregate_words.append(value)
    for value in twiddles.values:
        aggregate_words.append(value)

    for stage_index in range(stage_count):
        ref record = records[4 + stage_index]
        var stage_name = String()
        stage_name.write(prefix, "-stage-", stage_index)
        var row = 6 * stage_index
        if (
            not _same_record_identity(config, record)
            or record.kind != FIXED_ARTIFACT_V2_COMPLEX
            or record.stage != stage_name
            or record.logical_count != size
            or record.storage_bits != Int(schedule.values[row + 1])
            or record.fraction_bits != Int(schedule.values[row + 2])
            or record.rounding_mode != Int(schedule.values[row + 4])
            or record.overflow_mode != Int(schedule.values[row + 5])
            or schedule.values[row] != record.values[0]
        ):
            raise Error("fixed FFT trace stage record/metadata mismatch")
        for value in record.values:
            aggregate_words.append(value)

    ref output = records[4 + stage_count]
    var output_stage = prefix + "-output"
    if (
        not _same_record_identity(config, output)
        or output.kind != FIXED_ARTIFACT_V2_COMPLEX
        or output.stage != output_stage
        or output.logical_count != size
    ):
        raise Error("fixed FFT trace output record identity is invalid")
    if stage_count == 0:
        if (
            output.storage_bits != input.storage_bits
            or output.fraction_bits != input.fraction_bits
            or output.rounding_mode != input.rounding_mode
            or output.overflow_mode != input.overflow_mode
            or output.values != input.values
        ):
            raise Error("fixed FFT trace output differs from its input")
    else:
        ref final_stage = records[3 + stage_count]
        if (
            output.storage_bits != final_stage.storage_bits
            or output.fraction_bits != final_stage.fraction_bits
            or output.rounding_mode != final_stage.rounding_mode
            or output.overflow_mode != final_stage.overflow_mode
            or output.values != final_stage.values
        ):
            raise Error("fixed FFT trace output differs from its final stage")
    for value in output.values:
        aggregate_words.append(value)

    ref checksum_record = records[5 + stage_count]
    var checksum_stage = prefix + "-trace-checksum-lohi32"
    if (
        not _same_record_identity(config, checksum_record)
        or checksum_record.kind != FIXED_ARTIFACT_V2_SCALAR
        or checksum_record.stage != checksum_stage
        or checksum_record.storage_bits != 33
        or checksum_record.fraction_bits != 0
        or checksum_record.rounding_mode != ROUND_NEAREST_AWAY
        or checksum_record.overflow_mode != OVERFLOW_SATURATE
        or checksum_record.logical_count != 2
    ):
        raise Error("fixed FFT trace aggregate checksum record is invalid")
    var aggregate_checksum = fixed_raw_checksum(Span(aggregate_words))
    if (
        checksum_record.values[0]
        != Int64(aggregate_checksum & UInt64(0xffffffff))
        or checksum_record.values[1]
        != Int64(aggregate_checksum >> UInt64(32))
    ):
        raise Error("fixed FFT trace aggregate checksum mismatch")


def _safe_manifest_filename(value: StringSlice) -> Bool:
    if value.byte_length() == 0 or value.startswith(".") or ".." in value:
        return False
    var bytes = value.as_bytes()
    for byte_value in bytes:
        var byte = UInt8(byte_value)
        var valid = (
            (byte >= UInt8(ord("a")) and byte <= UInt8(ord("z")))
            or (byte >= UInt8(ord("0")) and byte <= UInt8(ord("9")))
            or byte == UInt8(ord("-"))
            or byte == UInt8(ord("_"))
            or byte == UInt8(ord("."))
        )
        if not valid:
            return False
    return True


def _known_manifest_schema(value: StringSlice) -> Bool:
    return (
        value == FIXED_ARTIFACT_V2_SCALAR_SCHEMA
        or value == FIXED_ARTIFACT_V2_COMPLEX_SCHEMA
        or value == FIXED_ARTIFACT_V2_SCALE_SCHEMA
        or value == FIXED_ARTIFACT_V2_FFT_BUNDLE_SCHEMA
    )


def parse_fixed_artifact_v2_manifest(
    text: StringSlice
) raises -> List[FixedArtifactV2ManifestEntry]:
    """Parse the canonical tab-separated corpus manifest and reject aliases."""
    _validate_text_envelope(text, "fixed artifact manifest")
    var lines = text.split("\n")
    if (
        len(lines) < 4
        or String(lines[0]) != "MWDSP-FIXED-V2-MANIFEST\t1"
        or String(lines[1]) != "filename\tschema\tbytes\tchecksum"
        or lines[len(lines) - 1].byte_length() != 0
    ):
        raise Error("fixed artifact manifest header/schema is invalid")
    var result = List[FixedArtifactV2ManifestEntry](capacity=len(lines) - 3)
    for line_index in range(2, len(lines) - 1):
        var fields = lines[line_index].split("\t")
        if len(fields) != 4:
            raise Error("fixed artifact manifest row must have four fields")
        if not _safe_manifest_filename(fields[0]):
            raise Error("fixed artifact manifest filename is unsafe/noncanonical")
        if not _known_manifest_schema(fields[1]):
            raise Error("fixed artifact manifest contains an unknown schema")
        var byte_count = _parse_nonnegative_int(fields[2])
        if byte_count <= 0:
            raise Error("fixed artifact manifest byte count must be positive")
        var checksum = _parse_u64(fields[3])
        for prior_index in range(len(result)):
            if result[prior_index].filename == fields[0]:
                raise Error("fixed artifact manifest contains a duplicate filename")
        result.append(FixedArtifactV2ManifestEntry(
            fields[0], fields[1], byte_count, checksum
        ))
    if len(result) == 0:
        raise Error("fixed artifact manifest must bind at least one file")
    return result^


def verify_fixed_artifact_v2_manifest_entry(
    entry: FixedArtifactV2ManifestEntry, text: StringSlice
) raises:
    """Verify byte binding, record checksums, and the declared file schema."""
    if text.byte_length() != entry.byte_count:
        raise Error("fixed artifact manifest byte count mismatch")
    if fixed_artifact_v2_bytes_checksum(text) != entry.checksum:
        raise Error("fixed artifact manifest whole-file checksum mismatch")
    var records = parse_fixed_artifact_v2_records(text)
    if entry.schema == FIXED_ARTIFACT_V2_FFT_BUNDLE_SCHEMA:
        validate_fixed_fft_trace_v2_bundle(records)
        return
    if len(records) != 1 or records[0].schema != entry.schema:
        raise Error("fixed artifact manifest schema differs from file records")


def _manifest_row(
    mut manifest: String,
    filename: StringSlice,
    schema: StringSlice,
    text: StringSlice,
):
    manifest.write(
        filename,
        "\t",
        schema,
        "\t",
        text.byte_length(),
        "\t",
        fixed_artifact_v2_bytes_checksum(text),
        "\n",
    )


def representative_fixed_artifact_v2_corpus() raises -> FixedArtifactV2Corpus:
    """Regenerate the bounded, static Phase-7 V2 corpus entirely in Mojo."""
    var q4 = QFormat(8, 4)
    var scalar_values: List[Int64] = [8, -24, 40]
    var scalar = serialize_fixed_vector(
        "phase7-corpus", "scalar", Span(scalar_values), q4, version=2
    )
    var complex_values: List[ComplexRaw] = [
        ComplexRaw(-16, 16), ComplexRaw(0, 32)
    ]
    var complex = serialize_complex_fixed_vector(
        "phase7-corpus", "complex", Span(complex_values), q4, version=2
    )

    var mixed_stages: List[ScaleStage] = [
        ScaleStage(QFormat(8, 2, ROUND_TOWARD_ZERO, OVERFLOW_WRAP), 1),
        ScaleStage(QFormat(8, 2, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE), 1),
    ]
    var scale = apply_scale_schedule(
        Int64(7), QFormat(8, 2), Span(mixed_stages)
    )
    var scale_trace = serialize_scale_trace(
        "phase7-corpus", "scale", scale, version=2
    )

    var q8 = QFormat(16, 8)
    var q16 = QFormat(24, 16)
    var q16_wrap = QFormat(24, 16, ROUND_TOWARD_ZERO, OVERFLOW_WRAP)
    var fft_values: List[ComplexRaw] = [
        ComplexRaw(256),
        ComplexRaw(512),
        ComplexRaw(768),
        ComplexRaw(1024),
    ]
    var twiddles: List[ComplexRaw] = [
        ComplexRaw(256, 0), ComplexRaw(0, -256)
    ]
    var fft_stages: List[ScaleStage] = [
        ScaleStage(q16), ScaleStage(q16_wrap)
    ]
    var fft = fixed_fft_radix2_trace_raw(
        Span(fft_values), q8, Span(twiddles), q8, Span(fft_stages)
    )
    var fft_trace = serialize_fixed_fft_trace(
        "phase7-corpus", "fft", fft, version=2
    )

    var manifest = String()
    manifest.write(
        FIXED_ARTIFACT_V2_MANIFEST_SCHEMA,
        "\t1\nfilename\tschema\tbytes\tchecksum\n",
    )
    _manifest_row(
        manifest,
        FIXED_ARTIFACT_V2_COMPLEX_FILE,
        FIXED_ARTIFACT_V2_COMPLEX_SCHEMA,
        StringSlice(complex),
    )
    _manifest_row(
        manifest,
        FIXED_ARTIFACT_V2_FFT_FILE,
        FIXED_ARTIFACT_V2_FFT_BUNDLE_SCHEMA,
        StringSlice(fft_trace),
    )
    _manifest_row(
        manifest,
        FIXED_ARTIFACT_V2_SCALAR_FILE,
        FIXED_ARTIFACT_V2_SCALAR_SCHEMA,
        StringSlice(scalar),
    )
    _manifest_row(
        manifest,
        FIXED_ARTIFACT_V2_SCALE_FILE,
        FIXED_ARTIFACT_V2_SCALE_SCHEMA,
        StringSlice(scale_trace),
    )
    return FixedArtifactV2Corpus(
        scalar^,
        complex^,
        scale_trace^,
        fft_trace^,
        manifest^,
    )
