"""Strictly attributable practical Float32 CPU PHY benchmarks.

Each ledger API owns a unique no-inline workload, timer, and report.  All
plans, workspaces, Lists, Spans, and derived fixtures precede the timer.  A
timed region contains exactly one target call; the complete result is retained
and fingerprinted in O(1) after timing.  Fixed inputs run twice before three
warmups and nine samples.
"""

from std.benchmark import keep
from std.collections import Span
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.core import Complex32
from wireless_dsp.backend.cpu.practical import (
    FFTPlanF32,
    make_fft_plan_f32,
)
from wireless_dsp.backend.cpu.phy_practical import (
    OFDMWorkspaceF32,
    common_phase_error_f32,
    complex_divide_f32,
    correct_common_phase_error_f32,
    correct_common_phase_error_f32_into,
    estimate_pilot_noise_variance_f32,
    ls_channel_estimate_f32,
    ls_channel_estimate_f32_into,
    make_ofdm_workspace_f32,
    mmse_equalize_siso_f32,
    mmse_equalize_siso_f32_into,
    ofdm_demodulate_f32,
    ofdm_demodulate_f32_into,
    ofdm_modulate_f32,
    ofdm_modulate_f32_into,
    zero_forcing_equalize_siso_f32,
    zero_forcing_equalize_siso_f32_into,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _FIXED_RUNS = 2
comptime _FFT_SIZE = 256
comptime _CYCLIC_PREFIX = 32
comptime _PILOTS = 128


struct _SISOFixture(Movable):
    var known: List[Complex32]
    var channel: List[Complex32]
    var received: List[Complex32]

    def __init__(
        out self,
        var known: List[Complex32],
        var channel: List[Complex32],
        var received: List[Complex32],
    ):
        self.known = known^
        self.channel = channel^
        self.received = received^


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _fingerprint_float(value: Float32) -> UInt64:
    return _mix(
        UInt64(Int(abs(Float64(value)) * 1_000_000.0)),
        UInt64(1 if value < 0.0 else 0),
    )


def _fingerprint_complex(value: Complex32) -> UInt64:
    return _mix(_fingerprint_float(value.re), _fingerprint_float(value.im))


def _fingerprint_complex_list(values: List[Complex32]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_complex(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_complex(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_workspace(workspace: OFDMWorkspaceF32) -> UInt64:
    var fingerprint = _mix(
        UInt64(workspace.size), UInt64(len(workspace.scratch))
    )
    if len(workspace.scratch) > 0:
        fingerprint = _mix(
            fingerprint, _fingerprint_complex(workspace.scratch[0])
        )
    return fingerprint


def _record(
    invocation: Int,
    elapsed: UInt64,
    fingerprint: UInt64,
    mut first: UInt64,
    mut samples: List[UInt64],
    mut checksum: UInt64,
) raises:
    if invocation == 0:
        first = fingerprint
    elif invocation == 1:
        if fingerprint != first:
            raise Error("fixed Float32 PHY result is nondeterministic")
        keep(first)
        keep(fingerprint)
    elif invocation >= _FIXED_RUNS + _WARMUPS:
        samples.append(elapsed)
        checksum = _mix(checksum, fingerprint)


def _finish(
    name: StringSlice,
    mut samples: List[UInt64],
    checksum: UInt64,
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


@no_inline
def _workload_make_ofdm_workspace_f32(size: Int) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = make_ofdm_workspace_f32(size)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_workspace(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("make_ofdm_workspace_f32", samples, checksum)


@no_inline
def _workload_ofdm_modulate_f32_into(
    spectrum: Span[Complex32, ...],
    cyclic_prefix: Int,
    plan: FFTPlanF32,
    mut workspace: OFDMWorkspaceF32,
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        ofdm_modulate_f32_into(
            spectrum, cyclic_prefix, plan, workspace, output
        )
        var elapsed = global_perf_counter_ns() - start
        keep(workspace)
        keep(output)
        var fingerprint = _mix(
            _fingerprint_complex_list(output),
            _fingerprint_workspace(workspace),
        )
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("ofdm_modulate_f32_into", samples, checksum)


@no_inline
def _workload_ofdm_modulate_f32(
    spectrum: Span[Complex32, ...], cyclic_prefix: Int
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = ofdm_modulate_f32(spectrum, cyclic_prefix)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("ofdm_modulate_f32", samples, checksum)


@no_inline
def _workload_ofdm_demodulate_f32_into(
    input_samples: Span[Complex32, ...],
    transform_size: Int,
    cyclic_prefix: Int,
    plan: FFTPlanF32,
    mut workspace: OFDMWorkspaceF32,
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        ofdm_demodulate_f32_into(
            input_samples,
            transform_size,
            cyclic_prefix,
            plan,
            workspace,
            output,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(workspace)
        keep(output)
        var fingerprint = _mix(
            _fingerprint_complex_list(output),
            _fingerprint_workspace(workspace),
        )
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("ofdm_demodulate_f32_into", samples, checksum)


@no_inline
def _workload_ofdm_demodulate_f32(
    input_samples: Span[Complex32, ...],
    transform_size: Int,
    cyclic_prefix: Int,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = ofdm_demodulate_f32(
            input_samples, transform_size, cyclic_prefix
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("ofdm_demodulate_f32", samples, checksum)


@no_inline
def _workload_complex_divide_f32(
    lhs: Complex32, rhs: Complex32
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = complex_divide_f32(lhs, rhs)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("complex_divide_f32", samples, checksum)


@no_inline
def _workload_ls_channel_estimate_f32_into(
    received: Span[Complex32, ...],
    known: Span[Complex32, ...],
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        ls_channel_estimate_f32_into(received, known, output)
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_complex_list(output)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("ls_channel_estimate_f32_into", samples, checksum)


@no_inline
def _workload_ls_channel_estimate_f32(
    received: Span[Complex32, ...], known: Span[Complex32, ...]
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = ls_channel_estimate_f32(received, known)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("ls_channel_estimate_f32", samples, checksum)


@no_inline
def _workload_zero_forcing_equalize_siso_f32_into(
    received: Span[Complex32, ...],
    channel: Span[Complex32, ...],
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        zero_forcing_equalize_siso_f32_into(received, channel, output)
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_complex_list(output)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish(
        "zero_forcing_equalize_siso_f32_into", samples, checksum
    )


@no_inline
def _workload_zero_forcing_equalize_siso_f32(
    received: Span[Complex32, ...], channel: Span[Complex32, ...]
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = zero_forcing_equalize_siso_f32(received, channel)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("zero_forcing_equalize_siso_f32", samples, checksum)


@no_inline
def _workload_mmse_equalize_siso_f32_into(
    received: Span[Complex32, ...],
    channel: Span[Complex32, ...],
    noise_variance: Float32,
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        mmse_equalize_siso_f32_into(
            received, channel, noise_variance, output
        )
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_complex_list(output)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("mmse_equalize_siso_f32_into", samples, checksum)


@no_inline
def _workload_mmse_equalize_siso_f32(
    received: Span[Complex32, ...],
    channel: Span[Complex32, ...],
    noise_variance: Float32,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = mmse_equalize_siso_f32(
            received, channel, noise_variance
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("mmse_equalize_siso_f32", samples, checksum)


@no_inline
def _workload_estimate_pilot_noise_variance_f32(
    received: Span[Complex32, ...],
    known: Span[Complex32, ...],
    channel: Span[Complex32, ...],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = estimate_pilot_noise_variance_f32(
            received, known, channel
        )
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_float(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("estimate_pilot_noise_variance_f32", samples, checksum)


@no_inline
def _workload_common_phase_error_f32(
    received: Span[Complex32, ...], known: Span[Complex32, ...]
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = common_phase_error_f32(received, known)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_float(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("common_phase_error_f32", samples, checksum)


@no_inline
def _workload_correct_common_phase_error_f32_into(
    input_samples: Span[Complex32, ...],
    phase: Float32,
    mut output: List[Complex32],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        correct_common_phase_error_f32_into(input_samples, phase, output)
        var elapsed = global_perf_counter_ns() - start
        keep(output)
        var fingerprint = _fingerprint_complex_list(output)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish(
        "correct_common_phase_error_f32_into", samples, checksum
    )


@no_inline
def _workload_correct_common_phase_error_f32(
    input_samples: Span[Complex32, ...], phase: Float32
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = correct_common_phase_error_f32(input_samples, phase)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_complex_list(result)
        _record(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish("correct_common_phase_error_f32", samples, checksum)


def _next_uniform_f32(mut state: UInt64) -> Float32:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return Float32(state >> UInt64(40)) / Float32(1 << 24)


def _seeded_complex32(length: Int, mut state: UInt64) -> List[Complex32]:
    var result = List[Complex32](capacity=length)
    for _ in range(length):
        result.append(Complex32(
            Float32(2.0) * _next_uniform_f32(state) - Float32(1.0),
            Float32(2.0) * _next_uniform_f32(state) - Float32(1.0),
        ))
    return result^


def _make_siso_fixture() -> _SISOFixture:
    var seed = UInt64(0x5150_E571_2026)
    var known = _seeded_complex32(_PILOTS, seed)
    var channel = _seeded_complex32(_PILOTS, seed)
    var received = List[Complex32](capacity=_PILOTS)
    for index in range(_PILOTS):
        known[index] = Complex32(
            known[index].re
            + (Float32(1.5) if known[index].re >= 0.0 else Float32(-1.5)),
            known[index].im + Float32(0.25),
        )
        channel[index] = Complex32(
            channel[index].re
            + (Float32(1.25) if channel[index].re >= 0.0 else Float32(-1.25)),
            channel[index].im - Float32(0.125),
        )
        var h = channel[index]
        var x = known[index]
        received.append(Complex32(
            h.re * x.re - h.im * x.im + Float32(0.001),
            h.re * x.im + h.im * x.re - Float32(0.0005),
        ))
    return _SISOFixture(known^, channel^, received^)


def _ofdm_spectrum(seed_value: UInt64) -> List[Complex32]:
    var seed = seed_value
    return _seeded_complex32(_FFT_SIZE, seed)


def benchmark_ofdm_modulate_into() raises -> UInt64:
    var spectrum = _ofdm_spectrum(UInt64(0x0FD0_4D0D_2026))
    var spectrum_span = Span(spectrum)
    var plan = make_fft_plan_f32(_FFT_SIZE, inverse=True)
    var workspace = make_ofdm_workspace_f32(_FFT_SIZE)
    var output = List[Complex32](
        length=_FFT_SIZE + _CYCLIC_PREFIX,
        fill=Complex32(0.0, 0.0),
    )
    var checksum = _workload_make_ofdm_workspace_f32(_FFT_SIZE)
    checksum ^= _workload_ofdm_modulate_f32_into(
        spectrum_span, _CYCLIC_PREFIX, plan, workspace, output
    )
    keep(plan)
    keep(workspace)
    keep(output)
    return checksum


def benchmark_ofdm_modulate_owning() raises -> UInt64:
    var spectrum = _ofdm_spectrum(UInt64(0x0FD0_0A11_2026))
    var spectrum_span = Span(spectrum)
    return _workload_ofdm_modulate_f32(spectrum_span, _CYCLIC_PREFIX)


def benchmark_ofdm_demodulate_into() raises -> UInt64:
    var spectrum = _ofdm_spectrum(UInt64(0x0FD0_DED0_2026))
    var spectrum_span = Span(spectrum)
    var input_samples = ofdm_modulate_f32(
        spectrum_span, _CYCLIC_PREFIX
    )
    var input_span = Span(input_samples)
    var plan = make_fft_plan_f32(_FFT_SIZE)
    var workspace = make_ofdm_workspace_f32(_FFT_SIZE)
    var output = List[Complex32](
        length=_FFT_SIZE, fill=Complex32(0.0, 0.0)
    )
    var checksum = _workload_ofdm_demodulate_f32_into(
        input_span,
        _FFT_SIZE,
        _CYCLIC_PREFIX,
        plan,
        workspace,
        output,
    )
    keep(input_samples)
    keep(plan)
    keep(workspace)
    keep(output)
    return checksum


def benchmark_ofdm_demodulate_owning() raises -> UInt64:
    var spectrum = _ofdm_spectrum(UInt64(0x0FD0_DA11_2026))
    var spectrum_span = Span(spectrum)
    var input_samples = ofdm_modulate_f32(
        spectrum_span, _CYCLIC_PREFIX
    )
    var input_span = Span(input_samples)
    var checksum = _workload_ofdm_demodulate_f32(
        input_span, _FFT_SIZE, _CYCLIC_PREFIX
    )
    keep(input_samples)
    return checksum


def benchmark_complex_divide_direct() raises -> UInt64:
    var lhs = Complex32(3.25, -0.75)
    var rhs = Complex32(1.25, -0.5)
    return _workload_complex_divide_f32(lhs, rhs)


def benchmark_siso_ls_into() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var known = Span(fixture.known)
    var output = List[Complex32](
        length=_PILOTS, fill=Complex32(0.0, 0.0)
    )
    return _workload_ls_channel_estimate_f32_into(
        received, known, output
    )


def benchmark_siso_ls_owning() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var known = Span(fixture.known)
    return _workload_ls_channel_estimate_f32(received, known)


def benchmark_siso_zf_into() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var channel = Span(fixture.channel)
    var output = List[Complex32](
        length=_PILOTS, fill=Complex32(0.0, 0.0)
    )
    return _workload_zero_forcing_equalize_siso_f32_into(
        received, channel, output
    )


def benchmark_siso_zf_owning() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var channel = Span(fixture.channel)
    return _workload_zero_forcing_equalize_siso_f32(received, channel)


def benchmark_siso_mmse_into() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var channel = Span(fixture.channel)
    var output = List[Complex32](
        length=_PILOTS, fill=Complex32(0.0, 0.0)
    )
    return _workload_mmse_equalize_siso_f32_into(
        received, channel, Float32(0.03125), output
    )


def benchmark_siso_mmse_owning() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var channel = Span(fixture.channel)
    return _workload_mmse_equalize_siso_f32(
        received, channel, Float32(0.03125)
    )


def benchmark_pilot_noise_variance() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var known = Span(fixture.known)
    var channel = Span(fixture.channel)
    return _workload_estimate_pilot_noise_variance_f32(
        received, known, channel
    )


def benchmark_common_phase_error() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var known = Span(fixture.known)
    return _workload_common_phase_error_f32(received, known)


def benchmark_common_phase_correction_into() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var known = Span(fixture.known)
    var phase = common_phase_error_f32(received, known)
    var output = List[Complex32](
        length=_PILOTS, fill=Complex32(0.0, 0.0)
    )
    return _workload_correct_common_phase_error_f32_into(
        received, phase, output
    )


def benchmark_common_phase_correction_owning() raises -> UInt64:
    var fixture = _make_siso_fixture()
    var received = Span(fixture.received)
    var known = Span(fixture.known)
    var phase = common_phase_error_f32(received, known)
    return _workload_correct_common_phase_error_f32(received, phase)


def benchmark_siso_estimation_bundle() raises -> UInt64:
    var checksum = benchmark_siso_ls_into()
    checksum ^= benchmark_siso_ls_owning()
    checksum ^= benchmark_siso_zf_into()
    checksum ^= benchmark_siso_zf_owning()
    checksum ^= benchmark_siso_mmse_into()
    checksum ^= benchmark_siso_mmse_owning()
    checksum ^= benchmark_pilot_noise_variance()
    checksum ^= benchmark_common_phase_error()
    checksum ^= benchmark_common_phase_correction_into()
    checksum ^= benchmark_common_phase_correction_owning()
    keep(checksum)
    return checksum


def main() raises:
    var alignment_probe = List[Complex32](
        length=64, fill=Complex32(0.0, 0.0)
    )
    print_benchmark_metadata()
    print_runtime_buffer_alignment(
        "cpu_phy_f32_complex32_probe",
        Int(alignment_probe.unsafe_ptr()),
        align_of[Complex32](),
    )
    var checksum = benchmark_ofdm_modulate_into()
    checksum ^= benchmark_ofdm_modulate_owning()
    checksum ^= benchmark_ofdm_demodulate_into()
    checksum ^= benchmark_ofdm_demodulate_owning()
    checksum ^= benchmark_complex_divide_direct()
    checksum ^= benchmark_siso_estimation_bundle()
    keep(checksum)
    print("cpu_phy_f32_combined_retained_checksum:", checksum)
