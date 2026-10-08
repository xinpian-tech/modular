"""NR PSS/SSS cell search and SS/PBCH synchronization primitives."""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.core import Complex64
from .sequences import nr_pss, nr_sss


struct NRPSSDetection(ImplicitlyCopyable):
    var offset: Int
    var n_id_2: Int
    var metric: Float64
    var phase_re: Float64
    var phase_im: Float64

    def __init__(
        out self, offset: Int, n_id_2: Int, metric: Float64,
        phase_re: Float64, phase_im: Float64,
    ):
        self.offset = offset
        self.n_id_2 = n_id_2
        self.metric = metric
        self.phase_re = phase_re
        self.phase_im = phase_im


struct NRCellDetection(ImplicitlyCopyable):
    var n_id_1: Int
    var n_id_2: Int
    var physical_cell_id: Int
    var metric: Float64

    def __init__(out self, n_id_1: Int, n_id_2: Int, metric: Float64):
        self.n_id_1 = n_id_1
        self.n_id_2 = n_id_2
        self.physical_cell_id = 3 * n_id_1 + n_id_2
        self.metric = metric


def nr_search_pss(samples: Span[Complex64, ...]) raises -> NRPSSDetection:
    """Exhaustive time-domain search over the three standardized PSS values."""
    if len(samples) < 127:
        raise Error("PSS search requires at least 127 samples")
    for index in range(len(samples)):
        if not isfinite(samples[index].re) or not isfinite(samples[index].im):
            raise Error("PSS search samples must be finite")
    var best_offset = 0
    var best_id = 0
    var best_power = -1.0
    var best_re = 0.0
    var best_im = 0.0
    for n_id_2 in range(3):
        var reference = nr_pss(n_id_2)
        for offset in range(len(samples) - 126):
            var sample_scale = 0.0
            for i in range(127):
                if abs(samples[offset + i].re) > sample_scale:
                    sample_scale = abs(samples[offset + i].re)
                if abs(samples[offset + i].im) > sample_scale:
                    sample_scale = abs(samples[offset + i].im)
            var correlation_re = 0.0
            var correlation_im = 0.0
            var received_energy = 0.0
            if sample_scale > 0.0:
                for i in range(127):
                    var scaled_re = samples[offset + i].re / sample_scale
                    var scaled_im = samples[offset + i].im / sample_scale
                    correlation_re += scaled_re * reference[i]
                    correlation_im += scaled_im * reference[i]
                    received_energy += (
                        scaled_re * scaled_re + scaled_im * scaled_im
                    )
            var power = correlation_re * correlation_re + correlation_im * correlation_im
            var metric = power / (127.0 * received_energy) if received_energy > 0.0 else 0.0
            if not isfinite(metric):
                raise Error("PSS search metric must remain finite")
            if metric > 1.0:
                metric = 1.0
            if metric > best_power:
                best_power = metric
                best_offset = offset
                best_id = n_id_2
                best_re = correlation_re
                best_im = correlation_im
    var magnitude = sqrt(best_re * best_re + best_im * best_im)
    return NRPSSDetection(
        best_offset, best_id, best_power,
        best_re / magnitude if magnitude > 0.0 else 1.0,
        best_im / magnitude if magnitude > 0.0 else 0.0,
    )


def nr_detect_sss(
    samples: Span[Complex64, ...], n_id_2: Int
) raises -> NRCellDetection:
    """Exhaustive SSS search with a scale-invariant normalized metric."""
    if len(samples) != 127 or n_id_2 < 0 or n_id_2 > 2:
        raise Error("SSS detection requires exactly 127 resource elements")
    for index in range(len(samples)):
        if not isfinite(samples[index].re) or not isfinite(samples[index].im):
            raise Error("SSS detection samples must be finite")
    var sample_scale = 0.0
    for index in range(len(samples)):
        if abs(samples[index].re) > sample_scale:
            sample_scale = abs(samples[index].re)
        if abs(samples[index].im) > sample_scale:
            sample_scale = abs(samples[index].im)
    var received_energy = 0.0
    if sample_scale > 0.0:
        for index in range(len(samples)):
            var scaled_re = samples[index].re / sample_scale
            var scaled_im = samples[index].im / sample_scale
            received_energy += scaled_re * scaled_re + scaled_im * scaled_im
    var best_id = 0
    var best_metric = -1.0
    for n_id_1 in range(336):
        var reference = nr_sss(n_id_1, n_id_2)
        var correlation_re = 0.0
        var correlation_im = 0.0
        if sample_scale > 0.0:
            for i in range(127):
                correlation_re += samples[i].re / sample_scale * reference[i]
                correlation_im += samples[i].im / sample_scale * reference[i]
        var power = correlation_re * correlation_re + correlation_im * correlation_im
        var metric = power / (127.0 * received_energy) if received_energy > 0.0 else 0.0
        if metric > 1.0:
            metric = 1.0
        if metric > best_metric:
            best_metric = metric
            best_id = n_id_1
    return NRCellDetection(best_id, n_id_2, best_metric)
