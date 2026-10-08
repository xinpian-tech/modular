"""Strictly isolated CPU evidence for every fixed-artifact V2 public API.

Each no-inline workload times exactly one target call.  Corpus strings,
records, manifests, entries, and views are prepared before entry; complete
owned results are retained after timing and fingerprinted in O(1).
"""

from std.benchmark import keep
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.testing.fixed_artifact_v2 import (
    FixedArtifactV2Record,
    FixedArtifactV2ManifestEntry,
    fixed_artifact_v2_bytes_checksum,
    parse_fixed_artifact_v2_manifest,
    parse_fixed_artifact_v2_record,
    parse_fixed_artifact_v2_records,
    representative_fixed_artifact_v2_corpus,
    validate_fixed_fft_trace_v2_bundle,
    verify_fixed_artifact_v2_manifest_entry,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("fixed artifact benchmark result is nondeterministic")
    keep(first)
    keep(second)


def _fingerprint_record(value: FixedArtifactV2Record) -> UInt64:
    var fingerprint = _mix(value.checksum, UInt64(value.byte_count))
    fingerprint = _mix(fingerprint, UInt64(len(value.values)))
    if len(value.values) > 0:
        fingerprint = _mix(fingerprint, UInt64(value.values[0]))
        fingerprint = _mix(
            fingerprint, UInt64(value.values[len(value.values) - 1])
        )
    return fingerprint


def _fingerprint_records(values: List[FixedArtifactV2Record]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, values[0].checksum)
        fingerprint = _mix(
            fingerprint, values[len(values) - 1].checksum
        )
    return fingerprint


def _fingerprint_entries(
    values: List[FixedArtifactV2ManifestEntry]
) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, values[0].checksum)
        fingerprint = _mix(
            fingerprint, values[len(values) - 1].checksum
        )
    return fingerprint


def _fingerprint_entry(value: FixedArtifactV2ManifestEntry) -> UInt64:
    return _mix(value.checksum, UInt64(value.byte_count))


def _finish_sample(
    name: StringSlice, mut samples: List[UInt64], checksum: UInt64
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


@no_inline
def _work_fixed_artifact_v2_bytes_checksum(
    text: StringSlice
) -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = fixed_artifact_v2_bytes_checksum(text)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, result)


def _run_fixed_artifact_v2_bytes_checksum() raises -> UInt64:
    var corpus = representative_fixed_artifact_v2_corpus()
    var text = StringSlice(corpus.fft_trace)
    var first = _work_fixed_artifact_v2_bytes_checksum(text)
    var second = _work_fixed_artifact_v2_bytes_checksum(text)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_fixed_artifact_v2_bytes_checksum(text))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_fixed_artifact_v2_bytes_checksum(text)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(corpus)
    return _finish_sample(
        "fixed_artifact_v2_bytes_checksum", samples, checksum
    )


@no_inline
def _work_parse_fixed_artifact_v2_record(
    text: StringSlice
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = parse_fixed_artifact_v2_record(text)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_record(result))


def _run_parse_fixed_artifact_v2_record() raises -> UInt64:
    var corpus = representative_fixed_artifact_v2_corpus()
    var text = StringSlice(corpus.scalar)
    var first = _work_parse_fixed_artifact_v2_record(text)
    var second = _work_parse_fixed_artifact_v2_record(text)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_parse_fixed_artifact_v2_record(text))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_parse_fixed_artifact_v2_record(text)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(corpus)
    return _finish_sample("parse_fixed_artifact_v2_record", samples, checksum)


@no_inline
def _work_parse_fixed_artifact_v2_records(
    text: StringSlice
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = parse_fixed_artifact_v2_records(text)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_records(result))


def _run_parse_fixed_artifact_v2_records() raises -> UInt64:
    var corpus = representative_fixed_artifact_v2_corpus()
    var text = StringSlice(corpus.fft_trace)
    var first = _work_parse_fixed_artifact_v2_records(text)
    var second = _work_parse_fixed_artifact_v2_records(text)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_parse_fixed_artifact_v2_records(text))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_parse_fixed_artifact_v2_records(text)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(corpus)
    return _finish_sample("parse_fixed_artifact_v2_records", samples, checksum)


@no_inline
def _work_validate_fixed_fft_trace_v2_bundle(
    records: List[FixedArtifactV2Record]
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    validate_fixed_fft_trace_v2_bundle(records)
    var elapsed = global_perf_counter_ns() - start
    keep(records)
    return (elapsed, _fingerprint_records(records))


def _run_validate_fixed_fft_trace_v2_bundle() raises -> UInt64:
    var corpus = representative_fixed_artifact_v2_corpus()
    var text = StringSlice(corpus.fft_trace)
    var records = parse_fixed_artifact_v2_records(text)
    var first = _work_validate_fixed_fft_trace_v2_bundle(records)
    var second = _work_validate_fixed_fft_trace_v2_bundle(records)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_validate_fixed_fft_trace_v2_bundle(records))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_validate_fixed_fft_trace_v2_bundle(records)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(corpus)
    keep(records)
    return _finish_sample(
        "validate_fixed_fft_trace_v2_bundle", samples, checksum
    )


@no_inline
def _work_parse_fixed_artifact_v2_manifest(
    text: StringSlice
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = parse_fixed_artifact_v2_manifest(text)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_entries(result))


def _run_parse_fixed_artifact_v2_manifest() raises -> UInt64:
    var corpus = representative_fixed_artifact_v2_corpus()
    var text = StringSlice(corpus.manifest)
    var first = _work_parse_fixed_artifact_v2_manifest(text)
    var second = _work_parse_fixed_artifact_v2_manifest(text)
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_parse_fixed_artifact_v2_manifest(text))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_parse_fixed_artifact_v2_manifest(text)
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(corpus)
    return _finish_sample("parse_fixed_artifact_v2_manifest", samples, checksum)


@no_inline
def _work_verify_fixed_artifact_v2_manifest_entry(
    entry: FixedArtifactV2ManifestEntry, text: StringSlice
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    verify_fixed_artifact_v2_manifest_entry(entry, text)
    var elapsed = global_perf_counter_ns() - start
    keep(entry)
    keep(text)
    return (elapsed, _fingerprint_entry(entry))


def _run_verify_fixed_artifact_v2_manifest_entry() raises -> UInt64:
    var corpus = representative_fixed_artifact_v2_corpus()
    var manifest_text = StringSlice(corpus.manifest)
    var artifact_text = StringSlice(corpus.complex)
    var entries = parse_fixed_artifact_v2_manifest(manifest_text)
    ref entry = entries[0]
    var first = _work_verify_fixed_artifact_v2_manifest_entry(
        entry, artifact_text
    )
    var second = _work_verify_fixed_artifact_v2_manifest_entry(
        entry, artifact_text
    )
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_verify_fixed_artifact_v2_manifest_entry(
            entry, artifact_text
        ))
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_verify_fixed_artifact_v2_manifest_entry(
            entry, artifact_text
        )
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    keep(corpus)
    keep(entries)
    return _finish_sample(
        "verify_fixed_artifact_v2_manifest_entry", samples, checksum
    )


@no_inline
def _work_representative_fixed_artifact_v2_corpus(
) raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = representative_fixed_artifact_v2_corpus()
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = UInt64(result.scalar.byte_length())
    fingerprint = _mix(fingerprint, UInt64(result.complex.byte_length()))
    fingerprint = _mix(fingerprint, UInt64(result.scale_trace.byte_length()))
    fingerprint = _mix(fingerprint, UInt64(result.fft_trace.byte_length()))
    fingerprint = _mix(fingerprint, UInt64(result.manifest.byte_length()))
    return (elapsed, fingerprint)


def _run_representative_fixed_artifact_v2_corpus() raises -> UInt64:
    var first = _work_representative_fixed_artifact_v2_corpus()
    var second = _work_representative_fixed_artifact_v2_corpus()
    _require_repeat(first[1], second[1])
    for _ in range(_WARMUPS):
        keep(_work_representative_fixed_artifact_v2_corpus())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var sample = _work_representative_fixed_artifact_v2_corpus()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    return _finish_sample(
        "representative_fixed_artifact_v2_corpus", samples, checksum
    )


def main() raises:
    print_benchmark_metadata()
    var checksum = _run_fixed_artifact_v2_bytes_checksum()
    checksum = _mix(checksum, _run_parse_fixed_artifact_v2_record())
    checksum = _mix(checksum, _run_parse_fixed_artifact_v2_records())
    checksum = _mix(checksum, _run_validate_fixed_fft_trace_v2_bundle())
    checksum = _mix(checksum, _run_parse_fixed_artifact_v2_manifest())
    checksum = _mix(
        checksum, _run_verify_fixed_artifact_v2_manifest_entry()
    )
    checksum = _mix(
        checksum, _run_representative_fixed_artifact_v2_corpus()
    )
    keep(checksum)
    print("fixed_artifact_v2_strict_retained_checksum:", checksum)
