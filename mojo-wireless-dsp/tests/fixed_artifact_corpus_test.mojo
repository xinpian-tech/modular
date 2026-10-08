"""Strict parser, manifest, fault-injection, and regeneration tests for V2."""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.testing.fixed_artifact_v2 import (
    FIXED_ARTIFACT_V2_SCALAR,
    FIXED_ARTIFACT_V2_COMPLEX,
    FIXED_ARTIFACT_V2_SCALE_TRACE,
    FIXED_ARTIFACT_V2_SCALAR_SCHEMA,
    FIXED_ARTIFACT_V2_COMPLEX_SCHEMA,
    FIXED_ARTIFACT_V2_SCALE_SCHEMA,
    FIXED_ARTIFACT_V2_FFT_BUNDLE_SCHEMA,
    FIXED_ARTIFACT_V2_SCALAR_FILE,
    FIXED_ARTIFACT_V2_COMPLEX_FILE,
    FIXED_ARTIFACT_V2_SCALE_FILE,
    FIXED_ARTIFACT_V2_FFT_FILE,
    FIXED_ARTIFACT_V2_MANIFEST_FILE,
    FixedArtifactV2ManifestEntry,
    fixed_artifact_v2_bytes_checksum,
    parse_fixed_artifact_v2_record,
    parse_fixed_artifact_v2_records,
    parse_fixed_artifact_v2_manifest,
    representative_fixed_artifact_v2_corpus,
    validate_fixed_fft_trace_v2_bundle,
    verify_fixed_artifact_v2_manifest_entry,
)


def _read_checked_file(filename: StringSlice) raises -> String:
    var path = String("mojo-wireless-dsp/artifacts/fixed-v2/") + filename
    with open(path, "r") as file:
        return file.read()


def _oracle_fnv1a_text(text: StringSlice) -> UInt64:
    var state = UInt64(14695981039346656037)
    var bytes = text.as_bytes()
    for index in range(len(bytes)):
        state ^= UInt64(UInt8(bytes[index]))
        state *= UInt64(1099511628211)
    return state


def _verify_checked_entry(
    entry: FixedArtifactV2ManifestEntry,
    scalar: String,
    complex: String,
    scale: String,
    fft: String,
) raises:
    if entry.filename == FIXED_ARTIFACT_V2_SCALAR_FILE:
        verify_fixed_artifact_v2_manifest_entry(entry, StringSlice(scalar))
    elif entry.filename == FIXED_ARTIFACT_V2_COMPLEX_FILE:
        verify_fixed_artifact_v2_manifest_entry(entry, StringSlice(complex))
    elif entry.filename == FIXED_ARTIFACT_V2_SCALE_FILE:
        verify_fixed_artifact_v2_manifest_entry(entry, StringSlice(scale))
    elif entry.filename == FIXED_ARTIFACT_V2_FFT_FILE:
        verify_fixed_artifact_v2_manifest_entry(entry, StringSlice(fft))
    else:
        raise Error("unexpected checked-in fixed artifact filename")


def test_parse_scalar_complex_and_scale_records() raises:
    var corpus = representative_fixed_artifact_v2_corpus()
    var scalar = parse_fixed_artifact_v2_record(StringSlice(corpus.scalar))
    assert_equal(scalar.kind, FIXED_ARTIFACT_V2_SCALAR)
    assert_equal(scalar.schema, FIXED_ARTIFACT_V2_SCALAR_SCHEMA)
    assert_equal(scalar.testcase_id, "phase7-corpus")
    assert_equal(scalar.stage, "scalar")
    assert_equal(scalar.version, 2)
    assert_equal(scalar.logical_count, 3)
    assert_equal(scalar.storage_bits, 8)
    assert_equal(scalar.fraction_bits, 4)
    assert_equal(scalar.rounding_mode, 1)
    assert_equal(scalar.overflow_mode, 1)
    assert_equal(scalar.values, [Int64(8), Int64(-24), Int64(40)])
    assert_equal(scalar.byte_count, corpus.scalar.byte_length())

    var complex = parse_fixed_artifact_v2_record(StringSlice(corpus.complex))
    assert_equal(complex.kind, FIXED_ARTIFACT_V2_COMPLEX)
    assert_equal(complex.schema, FIXED_ARTIFACT_V2_COMPLEX_SCHEMA)
    assert_equal(complex.logical_count, 2)
    assert_equal(complex.values, [
        Int64(-16), Int64(16), Int64(0), Int64(32)
    ])

    var scale = parse_fixed_artifact_v2_record(
        StringSlice(corpus.scale_trace)
    )
    assert_equal(scale.kind, FIXED_ARTIFACT_V2_SCALE_TRACE)
    assert_equal(scale.schema, FIXED_ARTIFACT_V2_SCALE_SCHEMA)
    assert_equal(scale.logical_count, 2)
    assert_equal(scale.values, [
        Int64(3), Int64(8), Int64(2), Int64(1), Int64(0), Int64(0),
        Int64(2), Int64(8), Int64(2), Int64(1), Int64(1), Int64(1),
    ])
    assert_true(
        fixed_artifact_v2_bytes_checksum(StringSlice(corpus.scalar))
        != scalar.checksum
    )


def test_seeded_bytes_checksum_matches_independent_fnv1a_oracle() raises:
    var corpus = representative_fixed_artifact_v2_corpus()
    assert_equal(
        fixed_artifact_v2_bytes_checksum(StringSlice(corpus.scalar)),
        _oracle_fnv1a_text(StringSlice(corpus.scalar)),
    )
    assert_equal(
        fixed_artifact_v2_bytes_checksum(StringSlice(corpus.complex)),
        _oracle_fnv1a_text(StringSlice(corpus.complex)),
    )
    assert_equal(
        fixed_artifact_v2_bytes_checksum(StringSlice(corpus.scale_trace)),
        _oracle_fnv1a_text(StringSlice(corpus.scale_trace)),
    )
    assert_equal(
        fixed_artifact_v2_bytes_checksum(StringSlice(corpus.fft_trace)),
        _oracle_fnv1a_text(StringSlice(corpus.fft_trace)),
    )
    assert_equal(
        fixed_artifact_v2_bytes_checksum(StringSlice(corpus.manifest)),
        _oracle_fnv1a_text(StringSlice(corpus.manifest)),
    )
    var empty = String()
    assert_equal(
        fixed_artifact_v2_bytes_checksum(StringSlice(empty)),
        _oracle_fnv1a_text(StringSlice(empty)),
    )
    var control = String("MWDSP\nseeded\tbytes\r\n")
    assert_equal(
        fixed_artifact_v2_bytes_checksum(StringSlice(control)),
        _oracle_fnv1a_text(StringSlice(control)),
    )

    var state = UInt64(0x4152_5449_4641_4354)
    for trial in range(257):
        var text = String()
        for _ in range(trial % 37):
            state = state * UInt64(6364136223846793005) + UInt64(1)
            text.write(UInt8((state >> 56) & UInt64(0x7f)))
        assert_equal(
            fixed_artifact_v2_bytes_checksum(StringSlice(text)),
            _oracle_fnv1a_text(StringSlice(text)),
        )


def test_parse_and_validate_complete_fft_trace_bundle() raises:
    var corpus = representative_fixed_artifact_v2_corpus()
    var records = parse_fixed_artifact_v2_records(
        StringSlice(corpus.fft_trace)
    )
    assert_equal(len(records), 8)
    assert_equal(records[0].stage, "fft-config")
    assert_equal(records[1].stage, "fft-input")
    assert_equal(records[2].stage, "fft-twiddle-rom")
    assert_equal(records[3].stage, "fft-schedule")
    assert_equal(records[4].stage, "fft-stage-0")
    assert_equal(records[5].stage, "fft-stage-1")
    assert_equal(records[6].stage, "fft-output")
    assert_equal(records[7].stage, "fft-trace-checksum-lohi32")
    assert_equal(records[2].values, [
        Int64(256), Int64(0), Int64(0), Int64(-256)
    ])
    assert_equal(records[3].values, [
        Int64(262144), Int64(24), Int64(16), Int64(0), Int64(1), Int64(1),
        Int64(655360), Int64(24), Int64(16), Int64(0), Int64(0), Int64(0),
    ])
    assert_equal(records[6].values, records[5].values)
    validate_fixed_fft_trace_v2_bundle(records)

    var duplicated = String()
    duplicated.write(corpus.fft_trace, corpus.fft_trace)
    var duplicate_records = parse_fixed_artifact_v2_records(
        StringSlice(duplicated)
    )
    with assert_raises():
        validate_fixed_fft_trace_v2_bundle(duplicate_records)

    var corrupt_output_records = parse_fixed_artifact_v2_records(
        StringSlice(corpus.fft_trace)
    )
    corrupt_output_records[6].values[0] += 1
    with assert_raises():
        validate_fixed_fft_trace_v2_bundle(corrupt_output_records)

    var corrupt_schedule_records = parse_fixed_artifact_v2_records(
        StringSlice(corpus.fft_trace)
    )
    corrupt_schedule_records[3].values[10] = Int64(1)
    with assert_raises():
        validate_fixed_fft_trace_v2_bundle(corrupt_schedule_records)


def test_checked_corpus_manifest_and_regeneration_are_exact() raises:
    var regenerated = representative_fixed_artifact_v2_corpus()
    var scalar = _read_checked_file(FIXED_ARTIFACT_V2_SCALAR_FILE)
    var complex = _read_checked_file(FIXED_ARTIFACT_V2_COMPLEX_FILE)
    var scale = _read_checked_file(FIXED_ARTIFACT_V2_SCALE_FILE)
    var fft = _read_checked_file(FIXED_ARTIFACT_V2_FFT_FILE)
    var manifest = _read_checked_file(FIXED_ARTIFACT_V2_MANIFEST_FILE)
    assert_equal(scalar, regenerated.scalar)
    assert_equal(complex, regenerated.complex)
    assert_equal(scale, regenerated.scale_trace)
    assert_equal(fft, regenerated.fft_trace)
    assert_equal(manifest, regenerated.manifest)

    var entries = parse_fixed_artifact_v2_manifest(StringSlice(manifest))
    assert_equal(len(entries), 4)
    assert_equal(entries[0].filename, FIXED_ARTIFACT_V2_COMPLEX_FILE)
    assert_equal(entries[0].schema, FIXED_ARTIFACT_V2_COMPLEX_SCHEMA)
    assert_equal(entries[1].filename, FIXED_ARTIFACT_V2_FFT_FILE)
    assert_equal(entries[1].schema, FIXED_ARTIFACT_V2_FFT_BUNDLE_SCHEMA)
    assert_equal(entries[2].filename, FIXED_ARTIFACT_V2_SCALAR_FILE)
    assert_equal(entries[2].schema, FIXED_ARTIFACT_V2_SCALAR_SCHEMA)
    assert_equal(entries[3].filename, FIXED_ARTIFACT_V2_SCALE_FILE)
    assert_equal(entries[3].schema, FIXED_ARTIFACT_V2_SCALE_SCHEMA)
    for index in range(len(entries)):
        _verify_checked_entry(entries[index], scalar, complex, scale, fft)


def test_record_fault_injection_rejects_every_contract_class() raises:
    var corpus = representative_fixed_artifact_v2_corpus()
    var scalar = corpus.scalar
    var truncated = String(scalar.removesuffix("\n"))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(truncated))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("MWDSP-FIXED-V2\n", "MWDSP-FIXED-V3\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("stage=scalar\n", "stage=scalar\nunknown=x\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("stage=scalar\n", "stage=scalar\nstage=again\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("dtype=sint8\n", "dtype=sint7\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("shape=3\n", "shape=2\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("stride=1\n", "stride=2\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("layout=scalar-contiguous\n", "layout=scalar\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("fraction_bits=4\n", "fraction_bits=3\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("scale_denominator=16\n", "scale_denominator=8\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("rounding=1\n", "rounding=9\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("overflow=1\n", "overflow=9\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("data=8,-24,40\n", "data=9,-24,40\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("data=8,-24,40\n", "data=8,-24\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace(
                "checksum=2193276742025766337\n",
                "checksum=18446744073709551616\n",
            )
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            scalar.replace("\n", "\r\n")
        ))

    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            corpus.complex.replace("shape=2x2\n", "shape=2x3\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            corpus.complex.replace("data_iq=-16:16,0:32\n", "data_iq=-16,0:32\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            corpus.scale_trace.replace("shape=2x6\n", "shape=2x5\n")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_record(StringSlice(
            corpus.scale_trace.replace(":1:0:0,", ":62:0:0,")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_records(StringSlice(
            String(corpus.fft_trace.removesuffix("data=3785851695,2346072667\n"))
        ))


def test_manifest_fault_injection_rejects_aliases_and_tampering() raises:
    var corpus = representative_fixed_artifact_v2_corpus()
    var manifest = corpus.manifest
    with assert_raises():
        _ = parse_fixed_artifact_v2_manifest(StringSlice(
            String(manifest.removesuffix("\n"))
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_manifest(StringSlice(
            manifest.replace(
                "MWDSP-FIXED-V2-MANIFEST\t1",
                "MWDSP-FIXED-V2-MANIFEST\t2",
            )
        ))
    var scalar_row = (
        "scalar.mwdsp\tMWDSP-FIXED-V2\t318\t4183685440716469852\n"
    )
    var duplicate_scalar_rows = String()
    duplicate_scalar_rows.write(scalar_row, scalar_row)
    with assert_raises():
        _ = parse_fixed_artifact_v2_manifest(StringSlice(
            manifest.replace(scalar_row, duplicate_scalar_rows)
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_manifest(StringSlice(
            manifest.replace("scalar.mwdsp\t", "../scalar.mwdsp\t")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_manifest(StringSlice(
            manifest.replace("MWDSP-FIXED-V2\t318", "MWDSP-UNKNOWN-V2\t318")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_manifest(StringSlice(
            manifest.replace("\t318\t", "\t0318\t")
        ))
    with assert_raises():
        _ = parse_fixed_artifact_v2_manifest(StringSlice(
            manifest.replace("\t318\t", "\t318\textra\t")
        ))

    var entries = parse_fixed_artifact_v2_manifest(StringSlice(manifest))
    var tampered_scalar = corpus.scalar.replace(
        "data=8,-24,40", "data=9,-24,40"
    )
    with assert_raises():
        verify_fixed_artifact_v2_manifest_entry(
            entries[2], StringSlice(tampered_scalar)
        )
    var wrong_length = corpus.scalar + "\n"
    with assert_raises():
        verify_fixed_artifact_v2_manifest_entry(
            entries[2], StringSlice(wrong_length)
        )
    var duplicate_scalar = String()
    duplicate_scalar.write(corpus.scalar, corpus.scalar)
    var duplicate_entry = FixedArtifactV2ManifestEntry(
        FIXED_ARTIFACT_V2_SCALAR_FILE,
        FIXED_ARTIFACT_V2_SCALAR_SCHEMA,
        duplicate_scalar.byte_length(),
        fixed_artifact_v2_bytes_checksum(StringSlice(duplicate_scalar)),
    )
    with assert_raises():
        verify_fixed_artifact_v2_manifest_entry(
            duplicate_entry, StringSlice(duplicate_scalar)
        )

    var bad_count_manifest = manifest.replace(
        "MWDSP-FIXED-V2\t318\t", "MWDSP-FIXED-V2\t319\t"
    )
    var bad_count_entries = parse_fixed_artifact_v2_manifest(
        StringSlice(bad_count_manifest)
    )
    with assert_raises():
        verify_fixed_artifact_v2_manifest_entry(
            bad_count_entries[2], StringSlice(corpus.scalar)
        )
    var bad_checksum_manifest = manifest.replace(
        "4183685440716469852", "4183685440716469853"
    )
    var bad_checksum_entries = parse_fixed_artifact_v2_manifest(
        StringSlice(bad_checksum_manifest)
    )
    with assert_raises():
        verify_fixed_artifact_v2_manifest_entry(
            bad_checksum_entries[2], StringSlice(corpus.scalar)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
