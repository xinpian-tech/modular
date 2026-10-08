"""Regenerate the checked-in fixed-artifact V2 corpus into one directory."""

from std.sys import argv
from wireless_dsp.testing.fixed_artifact_v2 import (
    FIXED_ARTIFACT_V2_SCALAR_FILE,
    FIXED_ARTIFACT_V2_COMPLEX_FILE,
    FIXED_ARTIFACT_V2_SCALE_FILE,
    FIXED_ARTIFACT_V2_FFT_FILE,
    FIXED_ARTIFACT_V2_MANIFEST_FILE,
    parse_fixed_artifact_v2_manifest,
    parse_fixed_artifact_v2_record,
    parse_fixed_artifact_v2_records,
    representative_fixed_artifact_v2_corpus,
    validate_fixed_fft_trace_v2_bundle,
    verify_fixed_artifact_v2_manifest_entry,
)


def _write_text(path: String, text: StringSlice) raises:
    with open(path, "w") as file:
        file.write_string(text)


def main() raises:
    var args = argv()
    if len(args) != 2:
        raise Error("usage: fixed_artifact_corpus <output-directory>")
    var output_directory = String(args[1])
    if output_directory.byte_length() == 0:
        raise Error("fixed artifact corpus output directory must be non-empty")
    var corpus = representative_fixed_artifact_v2_corpus()

    _ = parse_fixed_artifact_v2_record(StringSlice(corpus.scalar))
    _ = parse_fixed_artifact_v2_record(StringSlice(corpus.complex))
    _ = parse_fixed_artifact_v2_record(StringSlice(corpus.scale_trace))
    var fft_records = parse_fixed_artifact_v2_records(
        StringSlice(corpus.fft_trace)
    )
    validate_fixed_fft_trace_v2_bundle(fft_records)
    var manifest_entries = parse_fixed_artifact_v2_manifest(
        StringSlice(corpus.manifest)
    )
    for entry_index in range(len(manifest_entries)):
        ref entry = manifest_entries[entry_index]
        if entry.filename == FIXED_ARTIFACT_V2_SCALAR_FILE:
            verify_fixed_artifact_v2_manifest_entry(
                entry, StringSlice(corpus.scalar)
            )
        elif entry.filename == FIXED_ARTIFACT_V2_COMPLEX_FILE:
            verify_fixed_artifact_v2_manifest_entry(
                entry, StringSlice(corpus.complex)
            )
        elif entry.filename == FIXED_ARTIFACT_V2_SCALE_FILE:
            verify_fixed_artifact_v2_manifest_entry(
                entry, StringSlice(corpus.scale_trace)
            )
        elif entry.filename == FIXED_ARTIFACT_V2_FFT_FILE:
            verify_fixed_artifact_v2_manifest_entry(
                entry, StringSlice(corpus.fft_trace)
            )
        else:
            raise Error("representative corpus manifest contains an unknown file")

    _write_text(
        output_directory + "/" + FIXED_ARTIFACT_V2_SCALAR_FILE,
        StringSlice(corpus.scalar),
    )
    _write_text(
        output_directory + "/" + FIXED_ARTIFACT_V2_COMPLEX_FILE,
        StringSlice(corpus.complex),
    )
    _write_text(
        output_directory + "/" + FIXED_ARTIFACT_V2_SCALE_FILE,
        StringSlice(corpus.scale_trace),
    )
    _write_text(
        output_directory + "/" + FIXED_ARTIFACT_V2_FFT_FILE,
        StringSlice(corpus.fft_trace),
    )
    _write_text(
        output_directory + "/" + FIXED_ARTIFACT_V2_MANIFEST_FILE,
        StringSlice(corpus.manifest),
    )
