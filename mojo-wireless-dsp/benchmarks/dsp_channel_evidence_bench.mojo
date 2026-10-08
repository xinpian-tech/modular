"""Strict attributable timings for DSP, modem, and channel kernels.

Every ledger-backed public API has one unique no-inline workload.  Each
workload prepares deterministic owned fixtures and Span views before starting
its timer, invokes exactly one target API inside the timed interval, retains
the complete owned result after stopping the timer, and computes only an O(1)
fingerprint.  The common driver verifies two consecutive fingerprints before
three warmups and nine independently reported samples.
"""

from std.benchmark import keep
from std.collections import Span
from std.math import cos, sin
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import (
    FFTPlan,
    apply_window_complex,
    argmax_real,
    autocorrelate_complex,
    autocorrelation_sequence,
    blackman_window,
    common_phase_error,
    convolve_real,
    correlation_peak,
    correlation_phase,
    cross_correlate_complex,
    dft_reference,
    dot_complex,
    dot_real,
    energy_complex,
    energy_real,
    estimate_pilot_noise_variance,
    fft_batch,
    fft_in_place_with_plan,
    fft_radix4,
    fir_complex,
    fir_complex_chunk,
    fir_real,
    fir_real_chunk,
    generate_nco,
    hamming_window,
    hann_window,
    ifft,
    ifft_radix4,
    linear_interpolate_complex,
    linear_resample_complex,
    linear_resample_real,
    ls_channel_estimate,
    make_fft_plan,
    max_real,
    min1_min2,
    min_real,
    mix_complex,
    mmse_equalize_siso,
    normalized_correlation_at,
    normalized_cross_correlate_complex,
    ofdm_demodulate,
    ofdm_modulate,
    rational_resample_complex,
    rational_resample_real,
    rectangular_window,
    sign_product,
    sliding_window_energy,
    sum_real,
    window_energy,
    zero_forcing_equalize_siso,
)
from wireless_dsp.modem import (
    crc_append,
    crc_bits,
    crc_check,
    hard_bits_from_llr,
    qam_demap_hard,
    qam_demapper_llr_exact,
    qam_demapper_llr_piecewise,
    quantize_llr,
)
from wireless_dsp.synchronization import detect_repetition_start
from wireless_dsp.channel import (
    CDLArray,
    CDLChannel,
    CDLProfile,
    StandardChannelProfile,
    add_awgn,
    apply_cdl_narrowband,
    apply_cfo,
    apply_doppler,
    apply_integer_timing_offset,
    apply_iq_imbalance,
    apply_multipath,
    apply_phase_noise,
    apply_rayleigh_fading,
    apply_rician_fading,
    apply_sample_clock_offset,
    apply_standard_channel,
    awgn_and_cfo,
    cdl_array_response,
    cdl_profile,
    cdl_ray_offsets,
    cdl_ray_angles,
    cdl_ray_polarization_matrix,
    cdl_ula,
    cdl_upa,
    realize_cdl_channel,
    realize_standard_channel_paths,
    standard_channel_impulse_response,
    tdl_profile,
    wifi_tgac_profile,
    wifi_tgax_profile,
    wifi_tgn_profile,
)


comptime _TWO_PI = 6.283185307179586476925286766559
comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _CHECKSUM_SEED = UInt64(1469598103934665603)


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _fingerprint_float(value: Float64) -> UInt64:
    var magnitude = UInt64(Int(abs(value) * 1_000_000.0))
    return _mix(magnitude, UInt64(1 if value < 0.0 else 0))


def _fingerprint_int(value: Int) -> UInt64:
    return _mix(UInt64(abs(value)), UInt64(1 if value < 0 else 0))


def _fingerprint_complex(value: Complex64) -> UInt64:
    return _mix(
        _fingerprint_float(value.re), _fingerprint_float(value.im)
    )


def _fingerprint_float_list(values: List[Float64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_float(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_float(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_complex_list(values: List[Complex64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_complex(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_complex(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_uint8_list(values: List[UInt8]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, UInt64(values[0]))
        fingerprint = _mix(
            fingerprint, UInt64(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_int_list(values: List[Int]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        fingerprint = _mix(fingerprint, _fingerprint_int(values[0]))
        fingerprint = _mix(
            fingerprint, _fingerprint_int(values[len(values) - 1])
        )
    return fingerprint


def _fingerprint_cdl_profile(value: CDLProfile) -> UInt64:
    var fingerprint = UInt64(value.component_count())
    fingerprint = _mix(fingerprint, UInt64(value.cluster_count))
    fingerprint = _mix(
        fingerprint, _fingerprint_float_list(value.delays)
    )
    return _mix(fingerprint, _fingerprint_float_list(value.powers_db))


def _fingerprint_standard_profile(
    value: StandardChannelProfile
) -> UInt64:
    var fingerprint = UInt64(len(value.delays))
    fingerprint = _mix(fingerprint, UInt64(value.family))
    fingerprint = _mix(
        fingerprint, _fingerprint_float_list(value.delays)
    )
    return _mix(fingerprint, _fingerprint_float_list(value.powers_db))


def _fingerprint_cdl_array(value: CDLArray) -> UInt64:
    var fingerprint = _fingerprint_float_list(value.x_wavelengths)
    fingerprint = _mix(
        fingerprint, _fingerprint_float_list(value.y_wavelengths)
    )
    return _mix(
        fingerprint, _fingerprint_float_list(value.z_wavelengths)
    )


def _run[
    workload: def() thin raises -> Tuple[UInt64, UInt64]
](name: StringSlice) raises -> UInt64:
    var first = workload()
    var second = workload()
    if first[1] != second[1]:
        raise Error("fixed DSP/channel benchmark result is nondeterministic")
    keep(first)
    keep(second)
    for _ in range(_WARMUPS):
        keep(workload())
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = _CHECKSUM_SEED
    for _ in range(_SAMPLES):
        var sample = workload()
        samples.append(sample[0])
        checksum = _mix(checksum, sample[1])
        keep(sample)
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


def _real_values(length: Int, salt: Int = 3) -> List[Float64]:
    var result = List[Float64](capacity=length)
    for index in range(length):
        result.append(
            Float64((17 * index + salt) % 101) / 50.0 - 1.0
        )
    return result^


def _complex_values(length: Int, salt: Int = 5) -> List[Complex64]:
    var result = List[Complex64](capacity=length)
    for index in range(length):
        result.append(Complex64(
            Float64((17 * index + salt) % 101) / 50.0 - 1.0,
            Float64((29 * index + 2 * salt + 1) % 103) / 51.0 - 1.0,
        ))
    return result^


def _window_values(length: Int) -> List[Float64]:
    var result = List[Float64](capacity=length)
    for index in range(length):
        result.append(0.25 + 0.75 * Float64((index % 17) + 1) / 17.0)
    return result^


def _real_taps() -> List[Float64]:
    var result = List[Float64](capacity=15)
    for index in range(15):
        result.append(Float64(index + 1) / 120.0)
    return result^


def _complex_taps() -> List[Complex64]:
    var result = List[Complex64](capacity=15)
    for index in range(15):
        result.append(Complex64(
            Float64(index + 1) / 120.0,
            -Float64(index % 5) / 240.0,
        ))
    return result^


@no_inline
def _bench_rectangular_window() raises -> Tuple[UInt64, UInt64]:
    var length = 128
    var start = global_perf_counter_ns()
    var result = rectangular_window(length)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_hann_window() raises -> Tuple[UInt64, UInt64]:
    var length = 128
    var start = global_perf_counter_ns()
    var result = hann_window(length)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_hamming_window() raises -> Tuple[UInt64, UInt64]:
    var length = 128
    var start = global_perf_counter_ns()
    var result = hamming_window(length)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_blackman_window() raises -> Tuple[UInt64, UInt64]:
    var length = 128
    var start = global_perf_counter_ns()
    var result = blackman_window(length)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_apply_window_complex() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(128)
    var window = _window_values(128)
    var values_span = Span(values)
    var window_span = Span(window)
    var start = global_perf_counter_ns()
    var result = apply_window_complex(values_span, window_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_sum_real() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = sum_real(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


@no_inline
def _bench_dot_real() raises -> Tuple[UInt64, UInt64]:
    var lhs = _real_values(128, 3)
    var rhs = _real_values(128, 11)
    var lhs_span = Span(lhs)
    var rhs_span = Span(rhs)
    var start = global_perf_counter_ns()
    var result = dot_real(lhs_span, rhs_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


@no_inline
def _bench_energy_real() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = energy_real(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


@no_inline
def _bench_argmax_real() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = argmax_real(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_int(result))


@no_inline
def _bench_min_real() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = min_real(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


@no_inline
def _bench_max_real() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = max_real(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


@no_inline
def _bench_min1_min2() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = min1_min2(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(
        _fingerprint_float(result[0]), _fingerprint_float(result[1])
    )
    fingerprint = _mix(fingerprint, _fingerprint_int(result[2]))
    return (elapsed, fingerprint)


@no_inline
def _bench_sign_product() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = sign_product(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_int(result))


@no_inline
def _bench_dot_complex() raises -> Tuple[UInt64, UInt64]:
    var lhs = _complex_values(128, 5)
    var rhs = _complex_values(128, 13)
    var lhs_span = Span(lhs)
    var rhs_span = Span(rhs)
    var start = global_perf_counter_ns()
    var result = dot_complex(lhs_span, rhs_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex(result))


@no_inline
def _bench_energy_complex() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(128)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = energy_complex(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


@no_inline
def _bench_convolve_real() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var taps = _real_taps()
    var values_span = Span(values)
    var taps_span = Span(taps)
    var start = global_perf_counter_ns()
    var result = convolve_real(values_span, taps_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_fir_real() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var taps = _real_taps()
    var values_span = Span(values)
    var taps_span = Span(taps)
    var start = global_perf_counter_ns()
    var result = fir_real(values_span, taps_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_fir_real_chunk() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var taps = _real_taps()
    var history = List[Float64](length=14, fill=0.0)
    var values_span = Span(values)
    var taps_span = Span(taps)
    var start = global_perf_counter_ns()
    var result = fir_real_chunk(values_span, taps_span, history)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    keep(history)
    var fingerprint = _fingerprint_float_list(result)
    fingerprint = _mix(fingerprint, _fingerprint_float_list(history))
    return (elapsed, fingerprint)


@no_inline
def _bench_fir_complex() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(128)
    var taps = _complex_taps()
    var values_span = Span(values)
    var taps_span = Span(taps)
    var start = global_perf_counter_ns()
    var result = fir_complex(values_span, taps_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_fir_complex_chunk() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(128)
    var taps = _complex_taps()
    var history = List[Complex64](
        length=14, fill=Complex64(0.0, 0.0)
    )
    var values_span = Span(values)
    var taps_span = Span(taps)
    var start = global_perf_counter_ns()
    var result = fir_complex_chunk(values_span, taps_span, history)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    keep(history)
    var fingerprint = _fingerprint_complex_list(result)
    fingerprint = _mix(fingerprint, _fingerprint_complex_list(history))
    return (elapsed, fingerprint)


def _benchmark_reductions_windows_fir() raises -> Float64:
    var checksum = _CHECKSUM_SEED
    checksum = _mix(
        checksum, _run[_bench_rectangular_window]("rectangular_window")
    )
    checksum = _mix(checksum, _run[_bench_hann_window]("hann_window"))
    checksum = _mix(checksum, _run[_bench_hamming_window]("hamming_window"))
    checksum = _mix(checksum, _run[_bench_blackman_window]("blackman_window"))
    checksum = _mix(
        checksum,
        _run[_bench_apply_window_complex]("apply_window_complex"),
    )
    checksum = _mix(checksum, _run[_bench_sum_real]("sum_real"))
    checksum = _mix(checksum, _run[_bench_dot_real]("dot_real"))
    checksum = _mix(checksum, _run[_bench_energy_real]("energy_real"))
    checksum = _mix(checksum, _run[_bench_argmax_real]("argmax_real"))
    checksum = _mix(checksum, _run[_bench_min_real]("min_real"))
    checksum = _mix(checksum, _run[_bench_max_real]("max_real"))
    checksum = _mix(checksum, _run[_bench_min1_min2]("min1_min2"))
    checksum = _mix(checksum, _run[_bench_sign_product]("sign_product"))
    checksum = _mix(checksum, _run[_bench_dot_complex]("dot_complex"))
    checksum = _mix(
        checksum, _run[_bench_energy_complex]("energy_complex")
    )
    checksum = _mix(checksum, _run[_bench_convolve_real]("convolve_real"))
    checksum = _mix(checksum, _run[_bench_fir_real]("fir_real"))
    checksum = _mix(
        checksum, _run[_bench_fir_real_chunk]("fir_real_chunk")
    )
    checksum = _mix(checksum, _run[_bench_fir_complex]("fir_complex"))
    checksum = _mix(
        checksum, _run[_bench_fir_complex_chunk]("fir_complex_chunk")
    )
    keep(checksum)
    print("dsp_reductions_windows_fir_retained_checksum:", checksum)
    return Float64(checksum)


@no_inline
def _bench_cross_correlate_complex() raises -> Tuple[UInt64, UInt64]:
    var signal = _complex_values(256, 5)
    var reference = _complex_values(32, 19)
    var signal_span = Span(signal)
    var reference_span = Span(reference)
    var start = global_perf_counter_ns()
    var result = cross_correlate_complex(signal_span, reference_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_normalized_cross_correlate_complex(
) raises -> Tuple[UInt64, UInt64]:
    var signal = _complex_values(256, 5)
    var reference = _complex_values(32, 19)
    var signal_span = Span(signal)
    var reference_span = Span(reference)
    var start = global_perf_counter_ns()
    var result = normalized_cross_correlate_complex(
        signal_span, reference_span
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_normalized_correlation_at() raises -> Tuple[UInt64, UInt64]:
    var signal = _complex_values(256, 5)
    var reference = _complex_values(32, 19)
    var signal_span = Span(signal)
    var reference_span = Span(reference)
    var offset = 73
    var start = global_perf_counter_ns()
    var result = normalized_correlation_at(
        signal_span, reference_span, offset
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex(result))


@no_inline
def _bench_correlation_peak() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(225, 23)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = correlation_peak(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_int(result))


@no_inline
def _bench_autocorrelate_complex() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(256, 5)
    var values_span = Span(values)
    var lag = 17
    var start = global_perf_counter_ns()
    var result = autocorrelate_complex(values_span, lag)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex(result))


@no_inline
def _bench_autocorrelation_sequence() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(256, 5)
    var values_span = Span(values)
    var max_lag = 63
    var normalized = True
    var start = global_perf_counter_ns()
    var result = autocorrelation_sequence(
        values_span, max_lag, normalized=normalized
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_window_energy() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(256, 5)
    var values_span = Span(values)
    var offset = 41
    var length = 64
    var start = global_perf_counter_ns()
    var result = window_energy(values_span, offset, length)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


@no_inline
def _bench_sliding_window_energy() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(256, 5)
    var values_span = Span(values)
    var length = 64
    var start = global_perf_counter_ns()
    var result = sliding_window_energy(values_span, length)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_correlation_phase() raises -> Tuple[UInt64, UInt64]:
    var value = Complex64(-0.75, 1.25)
    var start = global_perf_counter_ns()
    var result = correlation_phase(value)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


def _benchmark_correlation() raises -> Float64:
    var checksum = _CHECKSUM_SEED
    checksum = _mix(
        checksum,
        _run[_bench_cross_correlate_complex]("cross_correlate_complex"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_normalized_cross_correlate_complex](
            "normalized_cross_correlate_complex"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_bench_normalized_correlation_at](
            "normalized_correlation_at"
        ),
    )
    checksum = _mix(
        checksum, _run[_bench_correlation_peak]("correlation_peak")
    )
    checksum = _mix(
        checksum,
        _run[_bench_autocorrelate_complex]("autocorrelate_complex"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_autocorrelation_sequence](
            "autocorrelation_sequence"
        ),
    )
    checksum = _mix(
        checksum, _run[_bench_window_energy]("window_energy")
    )
    checksum = _mix(
        checksum,
        _run[_bench_sliding_window_energy]("sliding_window_energy"),
    )
    checksum = _mix(
        checksum, _run[_bench_correlation_phase]("correlation_phase")
    )
    keep(checksum)
    print("dsp_correlation_retained_checksum:", checksum)
    return Float64(checksum)


def _ofdm_waveform() raises -> List[Complex64]:
    var spectrum = _complex_values(64, 7)
    return ofdm_modulate(Span(spectrum), 16)


def _fft_plan_fixture() raises -> FFTPlan:
    return make_fft_plan(64)


@no_inline
def _bench_make_fft_plan() raises -> Tuple[UInt64, UInt64]:
    var size = 1024
    var start = global_perf_counter_ns()
    var result = make_fft_plan(size)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(UInt64(result.size), UInt64(len(result.twiddles)))
    if len(result.twiddles) > 0:
        fingerprint = _mix(
            fingerprint, _fingerprint_complex(result.twiddles[0])
        )
        fingerprint = _mix(
            fingerprint,
            _fingerprint_complex(result.twiddles[len(result.twiddles) - 1]),
        )
    return (elapsed, fingerprint)


@no_inline
def _bench_dft_reference() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(64, 7)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = dft_reference(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_fft_batch() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(256, 7)
    var values_span = Span(values)
    var transform_size = 64
    var inverse = False
    var start = global_perf_counter_ns()
    var result = fft_batch(
        values_span, transform_size, inverse=inverse
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_fft_in_place_with_plan() raises -> Tuple[UInt64, UInt64]:
    var data = _complex_values(64, 7)
    var plan = _fft_plan_fixture()
    var start = global_perf_counter_ns()
    fft_in_place_with_plan(data, plan)
    var elapsed = global_perf_counter_ns() - start
    keep(data)
    return (elapsed, _fingerprint_complex_list(data))


@no_inline
def _bench_fft_radix4() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(64, 7)
    var values_span = Span(values)
    var inverse = False
    var start = global_perf_counter_ns()
    var result = fft_radix4(values_span, inverse=inverse)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_ifft() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(64, 7)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = ifft(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_ifft_radix4() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(64, 7)
    var values_span = Span(values)
    var start = global_perf_counter_ns()
    var result = ifft_radix4(values_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_ofdm_modulate() raises -> Tuple[UInt64, UInt64]:
    var spectrum = _complex_values(64, 7)
    var spectrum_span = Span(spectrum)
    var cyclic_prefix = 16
    var start = global_perf_counter_ns()
    var result = ofdm_modulate(spectrum_span, cyclic_prefix)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_ofdm_demodulate() raises -> Tuple[UInt64, UInt64]:
    var samples = _ofdm_waveform()
    var samples_span = Span(samples)
    var transform_size = 64
    var cyclic_prefix = 16
    var start = global_perf_counter_ns()
    var result = ofdm_demodulate(
        samples_span, transform_size, cyclic_prefix
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_generate_nco() raises -> Tuple[UInt64, UInt64]:
    var sample_count = 128
    var cycles_per_sample = 0.0075
    var initial_phase = 0.125
    var start = global_perf_counter_ns()
    var result = generate_nco(
        sample_count,
        cycles_per_sample,
        initial_phase=initial_phase,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_mix_complex() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(128, 7)
    var values_span = Span(values)
    var cycles_per_sample = -0.0125
    var initial_phase = -0.25
    var start = global_perf_counter_ns()
    var result = mix_complex(
        values_span,
        cycles_per_sample,
        initial_phase=initial_phase,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


def _benchmark_fft_ofdm_nco() raises -> Float64:
    var checksum = _CHECKSUM_SEED
    checksum = _mix(
        checksum, _run[_bench_make_fft_plan]("make_fft_plan")
    )
    checksum = _mix(
        checksum, _run[_bench_dft_reference]("dft_reference")
    )
    checksum = _mix(checksum, _run[_bench_fft_batch]("fft_batch"))
    checksum = _mix(
        checksum,
        _run[_bench_fft_in_place_with_plan]("fft_in_place_with_plan"),
    )
    checksum = _mix(checksum, _run[_bench_fft_radix4]("fft_radix4"))
    checksum = _mix(checksum, _run[_bench_ifft]("ifft"))
    checksum = _mix(
        checksum, _run[_bench_ifft_radix4]("ifft_radix4")
    )
    checksum = _mix(
        checksum, _run[_bench_ofdm_modulate]("ofdm_modulate")
    )
    checksum = _mix(
        checksum, _run[_bench_ofdm_demodulate]("ofdm_demodulate")
    )
    checksum = _mix(
        checksum, _run[_bench_generate_nco]("generate_nco")
    )
    checksum = _mix(checksum, _run[_bench_mix_complex]("mix_complex"))
    keep(checksum)
    print("dsp_fft_ofdm_nco_retained_checksum:", checksum)
    return Float64(checksum)


def _pilot_known_values() -> List[Complex64]:
    var result = List[Complex64](capacity=128)
    for index in range(128):
        result.append(Complex64(
            1.0 if index % 2 == 0 else -1.0, 0.5
        ))
    return result^


def _pilot_channel_values() -> List[Complex64]:
    var result = List[Complex64](capacity=128)
    for index in range(128):
        result.append(Complex64(
            0.75 + Float64(index % 7) / 32.0, -0.25
        ))
    return result^


def _pilot_received_values() -> List[Complex64]:
    var result = List[Complex64](capacity=128)
    for index in range(128):
        var re = Float64((17 * index + 3) % 101) / 50.0 - 1.0
        var im = Float64((29 * index + 7) % 103) / 51.0 - 1.0
        var pilot = Complex64(
            1.0 if index % 2 == 0 else -1.0, 0.5
        )
        var h = Complex64(
            0.75 + Float64(index % 7) / 32.0, -0.25
        )
        result.append(
            h * pilot + Complex64(0.001 * re, -0.001 * im)
        )
    return result^


def _interpolation_pilots() -> List[Complex64]:
    var result = List[Complex64](capacity=8)
    for index in range(8):
        result.append(Complex64(
            0.75 + Float64(index % 7) / 32.0, -0.25
        ))
    return result^


def _interpolation_positions() -> List[Int]:
    var result = List[Int](capacity=8)
    for index in range(8):
        result.append(16 * index)
    return result^


def _resample_taps() -> List[Float64]:
    return [0.125, 0.25, 0.5, 0.25, 0.125]


@no_inline
def _bench_linear_resample_real() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var values_span = Span(values)
    var output_length = 191
    var start = global_perf_counter_ns()
    var result = linear_resample_real(values_span, output_length)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_linear_resample_complex() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(128)
    var values_span = Span(values)
    var output_length = 191
    var start = global_perf_counter_ns()
    var result = linear_resample_complex(values_span, output_length)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_rational_resample_real() raises -> Tuple[UInt64, UInt64]:
    var values = _real_values(128)
    var taps = _resample_taps()
    var values_span = Span(values)
    var taps_span = Span(taps)
    var up = 3
    var down = 2
    var start = global_perf_counter_ns()
    var result = rational_resample_real(values_span, taps_span, up, down)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_rational_resample_complex() raises -> Tuple[UInt64, UInt64]:
    var values = _complex_values(128)
    var taps = _resample_taps()
    var values_span = Span(values)
    var taps_span = Span(taps)
    var up = 3
    var down = 2
    var start = global_perf_counter_ns()
    var result = rational_resample_complex(
        values_span, taps_span, up, down
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_ls_channel_estimate() raises -> Tuple[UInt64, UInt64]:
    var received = _pilot_received_values()
    var known = _pilot_known_values()
    var received_span = Span(received)
    var known_span = Span(known)
    var start = global_perf_counter_ns()
    var result = ls_channel_estimate(received_span, known_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_linear_interpolate_complex() raises -> Tuple[UInt64, UInt64]:
    var pilots = _interpolation_pilots()
    var positions = _interpolation_positions()
    var pilots_span = Span(pilots)
    var positions_span = Span(positions)
    var output_length = 128
    var start = global_perf_counter_ns()
    var result = linear_interpolate_complex(
        pilots_span, positions_span, output_length
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_estimate_pilot_noise_variance(
) raises -> Tuple[UInt64, UInt64]:
    var received = _pilot_received_values()
    var known = _pilot_known_values()
    var channel = _pilot_channel_values()
    var received_span = Span(received)
    var known_span = Span(known)
    var channel_span = Span(channel)
    var start = global_perf_counter_ns()
    var result = estimate_pilot_noise_variance(
        received_span, known_span, channel_span
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


@no_inline
def _bench_zero_forcing_equalize_siso() raises -> Tuple[UInt64, UInt64]:
    var received = _pilot_received_values()
    var channel = _pilot_channel_values()
    var received_span = Span(received)
    var channel_span = Span(channel)
    var start = global_perf_counter_ns()
    var result = zero_forcing_equalize_siso(received_span, channel_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_mmse_equalize_siso() raises -> Tuple[UInt64, UInt64]:
    var received = _pilot_received_values()
    var channel = _pilot_channel_values()
    var received_span = Span(received)
    var channel_span = Span(channel)
    var noise_variance = 0.05
    var start = global_perf_counter_ns()
    var result = mmse_equalize_siso(
        received_span, channel_span, noise_variance
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_common_phase_error() raises -> Tuple[UInt64, UInt64]:
    var received = _pilot_received_values()
    var known = _pilot_known_values()
    var received_span = Span(received)
    var known_span = Span(known)
    var start = global_perf_counter_ns()
    var result = common_phase_error(received_span, known_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float(result))


def _benchmark_resample_estimation() raises -> Float64:
    var checksum = _CHECKSUM_SEED
    checksum = _mix(
        checksum,
        _run[_bench_linear_resample_real]("linear_resample_real"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_linear_resample_complex]("linear_resample_complex"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_rational_resample_real]("rational_resample_real"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_rational_resample_complex](
            "rational_resample_complex"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_bench_ls_channel_estimate]("ls_channel_estimate"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_linear_interpolate_complex](
            "linear_interpolate_complex"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_bench_estimate_pilot_noise_variance](
            "estimate_pilot_noise_variance"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_bench_zero_forcing_equalize_siso](
            "zero_forcing_equalize_siso"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_bench_mmse_equalize_siso]("mmse_equalize_siso"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_common_phase_error]("common_phase_error"),
    )
    keep(checksum)
    print("dsp_resample_estimation_retained_checksum:", checksum)
    return Float64(checksum)


def _bit_values(length: Int = 1024) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(UInt8(((17 * index + 5) >> (index % 5)) & 1))
    return result^


def _qam_symbols() -> List[Complex64]:
    var result = List[Complex64](capacity=256)
    for index in range(256):
        result.append(Complex64(
            Float64((index % 7) - 3) / 3.1622776601683795,
            Float64(((3 * index + 1) % 7) - 3) / 3.1622776601683795,
        ))
    return result^


def _llr_values() -> List[Float64]:
    var result = List[Float64](capacity=1024)
    for index in range(1024):
        result.append(
            Float64((19 * index + 7) % 127) / 8.0 - 7.5
        )
    return result^


def _crc_codeword() raises -> List[UInt8]:
    var bits = _bit_values()
    return crc_append(
        Span(bits), width=16, polynomial=UInt64(0x1021)
    )


@no_inline
def _bench_crc_bits() raises -> Tuple[UInt64, UInt64]:
    var bits = _bit_values()
    var bits_span = Span(bits)
    var width = 16
    var polynomial = UInt64(0x1021)
    var initial = UInt64(0x1D0F)
    var start = global_perf_counter_ns()
    var result = crc_bits(
        bits_span,
        width=width,
        polynomial=polynomial,
        initial=initial,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, result)


@no_inline
def _bench_crc_append() raises -> Tuple[UInt64, UInt64]:
    var bits = _bit_values()
    var bits_span = Span(bits)
    var width = 16
    var polynomial = UInt64(0x1021)
    var start = global_perf_counter_ns()
    var result = crc_append(
        bits_span, width=width, polynomial=polynomial
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_uint8_list(result))


@no_inline
def _bench_crc_check() raises -> Tuple[UInt64, UInt64]:
    var codeword = _crc_codeword()
    var codeword_span = Span(codeword)
    var width = 16
    var polynomial = UInt64(0x1021)
    var start = global_perf_counter_ns()
    var result = crc_check(
        codeword_span, width=width, polynomial=polynomial
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, UInt64(1 if result else 0))


@no_inline
def _bench_qam_demap_hard() raises -> Tuple[UInt64, UInt64]:
    var samples = _qam_symbols()
    var samples_span = Span(samples)
    var bits_per_symbol = 4
    var start = global_perf_counter_ns()
    var result = qam_demap_hard(samples_span, bits_per_symbol)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_uint8_list(result))


@no_inline
def _bench_qam_demapper_llr_exact() raises -> Tuple[UInt64, UInt64]:
    var samples = _qam_symbols()
    var samples_span = Span(samples)
    var bits_per_symbol = 4
    var noise_variance = 0.25
    var start = global_perf_counter_ns()
    var result = qam_demapper_llr_exact(
        samples_span, bits_per_symbol, noise_variance
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_qam_demapper_llr_piecewise(
) raises -> Tuple[UInt64, UInt64]:
    var samples = _qam_symbols()
    var samples_span = Span(samples)
    var bits_per_symbol = 4
    var noise_variance = 0.25
    var start = global_perf_counter_ns()
    var result = qam_demapper_llr_piecewise(
        samples_span, bits_per_symbol, noise_variance
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_quantize_llr() raises -> Tuple[UInt64, UInt64]:
    var llrs = _llr_values()
    var llrs_span = Span(llrs)
    var scale = 2.0
    var clip = 31
    var start = global_perf_counter_ns()
    var result = quantize_llr(llrs_span, scale=scale, clip=clip)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_int_list(result))


@no_inline
def _bench_hard_bits_from_llr() raises -> Tuple[UInt64, UInt64]:
    var llrs = _llr_values()
    var llrs_span = Span(llrs)
    var start = global_perf_counter_ns()
    var result = hard_bits_from_llr(llrs_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_uint8_list(result))


def _benchmark_modem() raises -> Float64:
    var checksum = _CHECKSUM_SEED
    checksum = _mix(checksum, _run[_bench_crc_bits]("crc_bits"))
    checksum = _mix(checksum, _run[_bench_crc_append]("crc_append"))
    checksum = _mix(checksum, _run[_bench_crc_check]("crc_check"))
    checksum = _mix(
        checksum, _run[_bench_qam_demap_hard]("qam_demap_hard")
    )
    checksum = _mix(
        checksum,
        _run[_bench_qam_demapper_llr_exact]("qam_demapper_llr_exact"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_qam_demapper_llr_piecewise](
            "qam_demapper_llr_piecewise"
        ),
    )
    checksum = _mix(
        checksum, _run[_bench_quantize_llr]("quantize_llr")
    )
    checksum = _mix(
        checksum, _run[_bench_hard_bits_from_llr]("hard_bits_from_llr")
    )
    keep(checksum)
    print("modem_crc_qam_retained_checksum:", checksum)
    return Float64(checksum)


def _channel_taps() -> List[Complex64]:
    var result = List[Complex64](capacity=8)
    for index in range(8):
        result.append(Complex64(
            Float64(index + 1) / 64.0,
            -Float64(index % 3) / 128.0,
        ))
    return result^


@no_inline
def _bench_apply_cfo() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var normalized_frequency = 0.0075
    var initial_phase = 0.125
    var start = global_perf_counter_ns()
    var result = apply_cfo(
        samples_span,
        normalized_frequency,
        initial_phase=initial_phase,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_apply_doppler() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var normalized_doppler = -0.0025
    var initial_phase = -0.25
    var start = global_perf_counter_ns()
    var result = apply_doppler(
        samples_span,
        normalized_doppler,
        initial_phase=initial_phase,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_apply_integer_timing_offset() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var offset = 7
    var start = global_perf_counter_ns()
    var result = apply_integer_timing_offset(samples_span, offset)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_apply_multipath() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var taps = _channel_taps()
    var samples_span = Span(samples)
    var taps_span = Span(taps)
    var start = global_perf_counter_ns()
    var result = apply_multipath(samples_span, taps_span)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_apply_iq_imbalance() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var gain_imbalance = 0.05
    var phase_imbalance = 0.1
    var start = global_perf_counter_ns()
    var result = apply_iq_imbalance(
        samples_span, gain_imbalance, phase_imbalance
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_apply_sample_clock_offset() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var offset_ppm = 50.0
    var start = global_perf_counter_ns()
    var result = apply_sample_clock_offset(samples_span, offset_ppm)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_add_awgn() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var noise_variance = 0.05
    var seed = UInt64(0x600D0000)
    var start = global_perf_counter_ns()
    var result = add_awgn(
        samples_span, noise_variance, seed=seed
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_apply_phase_noise() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var innovation_stddev = 0.001
    var seed = UInt64(0x600D0000)
    var initial_phase = 0.1
    var start = global_perf_counter_ns()
    var result = apply_phase_noise(
        samples_span,
        innovation_stddev,
        seed=seed,
        initial_phase=initial_phase,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_apply_rayleigh_fading() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var seed = UInt64(0x600D0000)
    var block_fading = False
    var start = global_perf_counter_ns()
    var result = apply_rayleigh_fading(
        samples_span, seed=seed, block_fading=block_fading
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_apply_rician_fading() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var k_factor = 4.0
    var seed = UInt64(0x600D0000)
    var los_phase = 0.3
    var block_fading = False
    var start = global_perf_counter_ns()
    var result = apply_rician_fading(
        samples_span,
        k_factor,
        seed=seed,
        los_phase=los_phase,
        block_fading=block_fading,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_awgn_and_cfo() raises -> Tuple[UInt64, UInt64]:
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var noise_variance = 0.05
    var normalized_frequency = 0.004
    var seed = UInt64(0x600D0000)
    var initial_phase = -0.1
    var start = global_perf_counter_ns()
    var result = awgn_and_cfo(
        samples_span,
        noise_variance,
        normalized_frequency,
        seed=seed,
        initial_phase=initial_phase,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


def _benchmark_basic_channel() raises -> Float64:
    var checksum = _CHECKSUM_SEED
    checksum = _mix(checksum, _run[_bench_apply_cfo]("apply_cfo"))
    checksum = _mix(
        checksum, _run[_bench_apply_doppler]("apply_doppler")
    )
    checksum = _mix(
        checksum,
        _run[_bench_apply_integer_timing_offset](
            "apply_integer_timing_offset"
        ),
    )
    checksum = _mix(
        checksum, _run[_bench_apply_multipath]("apply_multipath")
    )
    checksum = _mix(
        checksum,
        _run[_bench_apply_iq_imbalance]("apply_iq_imbalance"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_apply_sample_clock_offset](
            "apply_sample_clock_offset"
        ),
    )
    checksum = _mix(checksum, _run[_bench_add_awgn]("add_awgn"))
    checksum = _mix(
        checksum, _run[_bench_apply_phase_noise]("apply_phase_noise")
    )
    checksum = _mix(
        checksum,
        _run[_bench_apply_rayleigh_fading]("apply_rayleigh_fading"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_apply_rician_fading]("apply_rician_fading"),
    )
    checksum = _mix(
        checksum, _run[_bench_awgn_and_cfo]("awgn_and_cfo")
    )
    keep(checksum)
    print("channel_basic_impairment_retained_checksum:", checksum)
    return Float64(checksum)


def _wifi_profile_fixture() raises -> StandardChannelProfile:
    return wifi_tgn_profile(String("A"))


@no_inline
def _bench_tdl_profile() raises -> Tuple[UInt64, UInt64]:
    var model = String("C")
    var delay_spread = 100.0
    var start = global_perf_counter_ns()
    var result = tdl_profile(model, desired_delay_spread_ns=delay_spread)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_standard_profile(result))


@no_inline
def _bench_wifi_tgn_profile() raises -> Tuple[UInt64, UInt64]:
    var model = String("D")
    var start = global_perf_counter_ns()
    var result = wifi_tgn_profile(model, los=True)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_standard_profile(result))


@no_inline
def _bench_wifi_tgac_profile() raises -> Tuple[UInt64, UInt64]:
    var model = String("D")
    var bandwidth_mhz = 160
    var start = global_perf_counter_ns()
    var result = wifi_tgac_profile(
        model, bandwidth_mhz=bandwidth_mhz, los=True
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_standard_profile(result))


@no_inline
def _bench_wifi_tgax_profile() raises -> Tuple[UInt64, UInt64]:
    var model = String("D")
    var bandwidth_mhz = 320
    var start = global_perf_counter_ns()
    var result = wifi_tgax_profile(
        model, bandwidth_mhz=bandwidth_mhz, los=True
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_standard_profile(result))


def _cdl_profile_fixture() raises -> CDLProfile:
    return cdl_profile(String("D"))


@no_inline
def _bench_cdl_profile() raises -> Tuple[UInt64, UInt64]:
    var model = String("C")
    var delay_spread = 100.0
    var start = global_perf_counter_ns()
    var result = cdl_profile(model, desired_delay_spread_ns=delay_spread)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_cdl_profile(result))


@no_inline
def _bench_cdl_ray_offsets() raises -> Tuple[UInt64, UInt64]:
    var start = global_perf_counter_ns()
    var result = cdl_ray_offsets()
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_float_list(result))


@no_inline
def _bench_cdl_ula() raises -> Tuple[UInt64, UInt64]:
    var element_count = 64
    var spacing = 0.5
    var axis = 1
    var start = global_perf_counter_ns()
    var result = cdl_ula(
        element_count, spacing_wavelengths=spacing, axis=axis
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_cdl_array(result))


@no_inline
def _bench_cdl_upa() raises -> Tuple[UInt64, UInt64]:
    var rows = 8
    var columns = 8
    var start = global_perf_counter_ns()
    var result = cdl_upa(rows, columns)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_cdl_array(result))


def _cdl_array_fixture() raises -> CDLArray:
    return cdl_ula(2, spacing_wavelengths=0.5, axis=1)


@no_inline
def _bench_realize_standard_channel_paths() raises -> Tuple[
    UInt64, UInt64
]:
    var profile = _wifi_profile_fixture()
    var seed = UInt64(0x13579000)
    var start = global_perf_counter_ns()
    var result = realize_standard_channel_paths(profile, seed=seed)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_standard_channel_impulse_response() raises -> Tuple[
    UInt64, UInt64
]:
    var profile = _wifi_profile_fixture()
    var sample_rate_hz = 20.0e6
    var seed = UInt64(0x13579000)
    var start = global_perf_counter_ns()
    var result = standard_channel_impulse_response(
        profile, sample_rate_hz, seed=seed
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_apply_standard_channel() raises -> Tuple[UInt64, UInt64]:
    var profile = _wifi_profile_fixture()
    var samples = _complex_values(256, 3)
    var samples_span = Span(samples)
    var sample_rate_hz = 20.0e6
    var seed = UInt64(0x13579000)
    var start = global_perf_counter_ns()
    var result = apply_standard_channel(
        samples_span, profile, sample_rate_hz, seed=seed
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


def _benchmark_standard_channel() raises -> Float64:
    var checksum = _CHECKSUM_SEED
    checksum = _mix(
        checksum, _run[_bench_tdl_profile]("tdl_profile")
    )
    checksum = _mix(
        checksum, _run[_bench_wifi_tgn_profile]("wifi_tgn_profile")
    )
    checksum = _mix(
        checksum, _run[_bench_wifi_tgac_profile]("wifi_tgac_profile")
    )
    checksum = _mix(
        checksum, _run[_bench_wifi_tgax_profile]("wifi_tgax_profile")
    )
    checksum = _mix(
        checksum,
        _run[_bench_realize_standard_channel_paths](
            "realize_standard_channel_paths"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_bench_standard_channel_impulse_response](
            "standard_channel_impulse_response"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_bench_apply_standard_channel]("apply_standard_channel"),
    )
    keep(checksum)
    print("channel_standard_model_retained_checksum:", checksum)
    return Float64(checksum)


def _cdl_channel_fixture() raises -> CDLChannel:
    var profile = _cdl_profile_fixture()
    var transmit_array = _cdl_array_fixture()
    var receive_array = _cdl_array_fixture()
    return realize_cdl_channel(
        profile,
        transmit_array,
        receive_array,
        seed=UInt64(0xC0DE0000),
        carrier_frequency_hz=3.5e9,
        link_distance_m=20.0,
    )


@no_inline
def _bench_cdl_array_response() raises -> Tuple[UInt64, UInt64]:
    var array = _cdl_array_fixture()
    var azimuth_deg = 92.0
    var zenith_deg = 87.0
    var start = global_perf_counter_ns()
    var result = cdl_array_response(array, azimuth_deg, zenith_deg)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


@no_inline
def _bench_cdl_ray_angles() raises -> Tuple[UInt64, UInt64]:
    var profile = _cdl_profile_fixture()
    var component = 1
    var seed = UInt64(0xCAFE0000)
    var start = global_perf_counter_ns()
    var result = cdl_ray_angles(profile, component, seed=seed)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_float_list(result.aod_deg)
    fingerprint = _mix(
        fingerprint, _fingerprint_float_list(result.aoa_deg)
    )
    fingerprint = _mix(
        fingerprint, _fingerprint_float_list(result.zod_deg)
    )
    fingerprint = _mix(
        fingerprint, _fingerprint_float_list(result.zoa_deg)
    )
    return (elapsed, fingerprint)


@no_inline
def _bench_cdl_ray_polarization_matrix() raises -> Tuple[
    UInt64, UInt64
]:
    var profile = _cdl_profile_fixture()
    var component = 1
    var ray = 7
    var seed = UInt64(0xBEEF0000)
    var start = global_perf_counter_ns()
    var result = cdl_ray_polarization_matrix(
        profile, component, ray, seed=seed
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _fingerprint_complex(result.theta_theta)
    fingerprint = _mix(
        fingerprint, _fingerprint_complex(result.theta_phi)
    )
    fingerprint = _mix(
        fingerprint, _fingerprint_complex(result.phi_theta)
    )
    fingerprint = _mix(
        fingerprint, _fingerprint_complex(result.phi_phi)
    )
    return (elapsed, fingerprint)


@no_inline
def _bench_realize_cdl_channel() raises -> Tuple[UInt64, UInt64]:
    var profile = _cdl_profile_fixture()
    var transmit_array = _cdl_array_fixture()
    var receive_array = _cdl_array_fixture()
    var seed = UInt64(0xC0DE0000)
    var carrier_frequency_hz = 3.5e9
    var link_distance_m = 20.0
    var start = global_perf_counter_ns()
    var result = realize_cdl_channel(
        profile,
        transmit_array,
        receive_array,
        seed=seed,
        carrier_frequency_hz=carrier_frequency_hz,
        link_distance_m=link_distance_m,
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    var fingerprint = _mix(
        UInt64(result.receive_count), UInt64(result.transmit_count)
    )
    fingerprint = _mix(
        fingerprint, _fingerprint_float_list(result.delays_ns)
    )
    fingerprint = _mix(
        fingerprint, _fingerprint_complex_list(result.coefficients)
    )
    return (elapsed, fingerprint)


@no_inline
def _bench_apply_cdl_narrowband() raises -> Tuple[UInt64, UInt64]:
    var channel = _cdl_channel_fixture()
    var transmit: List[Complex64] = [
        Complex64(0.75, -0.25), Complex64(-0.5, 1.0)
    ]
    var start = global_perf_counter_ns()
    var result = apply_cdl_narrowband(channel, transmit)
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_complex_list(result))


def _benchmark_cdl() raises -> Float64:
    var checksum = _CHECKSUM_SEED
    checksum = _mix(
        checksum, _run[_bench_cdl_profile]("cdl_profile")
    )
    checksum = _mix(
        checksum, _run[_bench_cdl_ray_offsets]("cdl_ray_offsets")
    )
    checksum = _mix(checksum, _run[_bench_cdl_ula]("cdl_ula"))
    checksum = _mix(checksum, _run[_bench_cdl_upa]("cdl_upa"))
    checksum = _mix(
        checksum,
        _run[_bench_cdl_array_response]("cdl_array_response"),
    )
    checksum = _mix(
        checksum, _run[_bench_cdl_ray_angles]("cdl_ray_angles")
    )
    checksum = _mix(
        checksum,
        _run[_bench_cdl_ray_polarization_matrix](
            "cdl_ray_polarization_matrix"
        ),
    )
    checksum = _mix(
        checksum,
        _run[_bench_realize_cdl_channel]("realize_cdl_channel"),
    )
    checksum = _mix(
        checksum,
        _run[_bench_apply_cdl_narrowband]("apply_cdl_narrowband"),
    )
    keep(checksum)
    print("channel_cdl_retained_checksum:", checksum)
    return Float64(checksum)


def _repetition_samples() -> List[Complex64]:
    var pattern = List[Complex64](capacity=32)
    var samples = List[Complex64](capacity=320)
    for index in range(32):
        pattern.append(Complex64(
            Float64((17 * index + 3) % 31) / 15.0 - 1.0,
            Float64((11 * index + 5) % 29) / 14.0 - 1.0,
        ))
    for _ in range(17):
        samples.append(Complex64(0.0, 0.0))
    for _ in range(9):
        for value in pattern:
            samples.append(value)
    return samples^


@no_inline
def _bench_detect_repetition_start() raises -> Tuple[UInt64, UInt64]:
    var samples = _repetition_samples()
    var samples_span = Span(samples)
    var period = 32
    var window = 128
    var threshold = 0.8
    var start = global_perf_counter_ns()
    var result = detect_repetition_start(
        samples_span, period, window, threshold
    )
    var elapsed = global_perf_counter_ns() - start
    keep(result)
    return (elapsed, _fingerprint_int(result))


def _benchmark_synchronization() raises -> Float64:
    var checksum = _run[_bench_detect_repetition_start](
        "detect_repetition_start"
    )
    keep(checksum)
    print("synchronization_retained_checksum:", checksum)
    return Float64(checksum)


def main() raises:
    print_benchmark_metadata()
    var alignment_probe = List[Complex64](
        length=64, fill=Complex64(0.0, 0.0)
    )
    print_runtime_buffer_alignment(
        "dsp_channel_complex64_probe",
        Int(alignment_probe.unsafe_ptr()),
        align_of[Complex64](),
    )
    var checksum = _benchmark_reductions_windows_fir()
    checksum += _benchmark_correlation()
    checksum += _benchmark_fft_ofdm_nco()
    checksum += _benchmark_resample_estimation()
    checksum += _benchmark_modem()
    checksum += _benchmark_basic_channel()
    checksum += _benchmark_standard_channel()
    checksum += _benchmark_cdl()
    checksum += _benchmark_synchronization()
    keep(checksum)
    print("dsp_channel_combined_retained_checksum:", checksum)
