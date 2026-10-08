"""Shared reporting primitives for warning-clean project benchmarks.

This module deliberately contains reporting only: each benchmark owns its
inputs, warmups, timed regions, and retained result checksum.  Keeping the
statistics in one place prevents subtly different p95 definitions from
appearing across protocol families.
"""

from std.sys.defines import MOJO_VERSION
from std.sys.info import (
    CompilationTarget,
    align_of,
    num_logical_cores,
    num_physical_cores,
    simd_width_of,
)
from .core.complex import Complex32, Complex64


def sort_timing_samples(mut values: List[UInt64]):
    """Sort timing samples in ascending order in place."""
    for index in range(1, len(values)):
        var key = values[index]
        var position = index - 1
        while position >= 0 and values[position] > key:
            values[position + 1] = values[position]
            position -= 1
        values[position + 1] = key


def median_sample(values: List[UInt64]) raises -> UInt64:
    """Return the median of an already sorted, odd-sized sample set."""
    if len(values) == 0 or len(values) % 2 == 0:
        raise Error("benchmark median requires a non-empty odd sample count")
    return values[len(values) // 2]


def nearest_rank_p95_sample(values: List[UInt64]) raises -> UInt64:
    """Return nearest-rank p95 from an already sorted sample set."""
    if len(values) == 0:
        raise Error("benchmark p95 requires at least one sample")
    return values[(95 * len(values) + 99) // 100 - 1]


def report_timing_samples(
    family: StringSlice,
    mut values: List[UInt64],
    warmup_runs: Int,
    operations_per_sample: Int,
    denominator_unit: StringSlice = "api_call",
) raises:
    """Print the common latency contract for one independently sampled family."""
    if warmup_runs < 3:
        raise Error("benchmark requires at least three untimed warmups")
    if len(values) < 9:
        raise Error("benchmark requires at least nine independent samples")
    if operations_per_sample <= 0:
        raise Error("benchmark operation count must be positive")
    if denominator_unit.byte_length() == 0:
        raise Error("benchmark denominator unit must be named")
    sort_timing_samples(values)
    var median = median_sample(values)
    print("benchmark_family:", family)
    print("warmup_runs:", warmup_runs)
    print("independent_samples:", len(values))
    print("operations_per_sample:", operations_per_sample)
    print("denominator_unit:", denominator_unit)
    print("median_ns:", median)
    print("nearest_rank_p95_ns:", nearest_rank_p95_sample(values))
    print(
        "median_ns_per_operation:",
        Float64(median) / Float64(operations_per_sample),
    )


def print_runtime_buffer_alignment(
    name: StringSlice,
    address: Int,
    natural_alignment_bytes: Int,
):
    """Print an actual host-buffer address and its natural-alignment proof.

    The caller obtains ``address`` from ``Int(list.unsafe_ptr())``.  Reporting
    both the address and its modulus makes alignment independently verifiable;
    it does not claim allocator alignment beyond the observed buffer.
    """
    print("runtime_buffer_name:", name)
    print("runtime_buffer_address:", address)
    print("runtime_buffer_natural_alignment_bytes:", natural_alignment_bytes)
    print(
        "runtime_buffer_address_mod_natural_alignment:",
        address % natural_alignment_bytes,
    )


def print_benchmark_metadata():
    """Print compiler, SIMD, natural-alignment, and observed-host metadata.

    Every benchmark calls this before constructing its timed regions.  The
    small owned probe records one actual allocator result without implying
    that every later fixture has the same alignment; benchmarks with stronger
    buffer-specific claims additionally call ``print_runtime_buffer_alignment``.
    """
    print(
        "mojo_compiler_semver:",
        MOJO_VERSION.major,
        MOJO_VERSION.minor,
        MOJO_VERSION.patch,
    )
    print("compilation_target_arch:", CompilationTarget._arch())
    print("compilation_target_os:", CompilationTarget._os())
    print("host_logical_cores:", num_logical_cores())
    print("host_physical_cores:", num_physical_cores())
    print("target_has_sse4:", CompilationTarget.has_sse4())
    print("target_has_avx2:", CompilationTarget.has_avx2())
    print("target_has_avx512f:", CompilationTarget.has_avx512f())
    print("target_has_fma:", CompilationTarget.has_fma())
    print("target_has_neon:", CompilationTarget.has_neon())
    print("float32_simd_width_elements:", simd_width_of[DType.float32]())
    print("float64_simd_width_elements:", simd_width_of[DType.float64]())
    print("int64_simd_width_elements:", simd_width_of[DType.int64]())
    print("float32_natural_alignment_bytes:", align_of[Float32]())
    print("float64_natural_alignment_bytes:", align_of[Float64]())
    print("int64_natural_alignment_bytes:", align_of[Int64]())
    print("complex32_natural_alignment_bytes:", align_of[Complex32]())
    print("complex64_natural_alignment_bytes:", align_of[Complex64]())
    var observed_alignment_probe = List[Complex64](
        length=8, fill=Complex64(0.0, 0.0)
    )
    print_runtime_buffer_alignment(
        "benchmark_metadata_complex64_probe",
        Int(observed_alignment_probe.unsafe_ptr()),
        align_of[Complex64](),
    )
