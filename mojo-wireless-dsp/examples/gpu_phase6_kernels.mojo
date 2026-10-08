"""Compile/runtime-gated Phase 6 GPU DSP kernel coverage smoke."""

from std.gpu import block_dim, block_idx, thread_idx
from std.math import ceildiv, cos, sin
from std.sys import has_accelerator
from max.gpu.host import DeviceContext
from layout import TileTensor, row_major

comptime block_size = 128
comptime fft_size = 64
comptime fft_batches = 4
comptime fft_complex_count = fft_size * fft_batches
comptime fft_layout = row_major[2 * fft_complex_count]()
comptime channel_layout = row_major[2 * fft_complex_count]()
comptime mimo_input_layout = row_major[2 * fft_batches * 2]()
comptime mimo_weight_layout = row_major[2 * 2 * 2]()
comptime ldpc_checks = 64
comptime ldpc_degree = 4
comptime ldpc_layout = row_major[ldpc_checks * ldpc_degree]()
comptime correlation_offsets = 64
comptime correlation_reference = 16
comptime correlation_signal_layout = row_major[2 * (correlation_offsets + correlation_reference - 1)]()
comptime correlation_reference_layout = row_major[2 * correlation_reference]()
comptime correlation_output_layout = row_major[2 * correlation_offsets]()
comptime two_pi = 6.2831853071795864769


def batched_dft64_kernel(
    input: TileTensor[DType.float32, type_of(fft_layout), MutAnyOrigin],
    output: TileTensor[DType.float32, type_of(fft_layout), MutAnyOrigin],
):
    var index = block_idx.x * block_dim.x + thread_idx.x
    if index < fft_complex_count:
        var batch = index // fft_size
        var k = index % fft_size
        var acc_re = Float32(0.0)
        var acc_im = Float32(0.0)
        for n in range(fft_size):
            var angle = -two_pi * Float64(k * n) / Float64(fft_size)
            var tw_re = Float32(cos(angle))
            var tw_im = Float32(sin(angle))
            var source = 2 * (batch * fft_size + n)
            var re = input[source]
            var im = input[source + 1]
            acc_re += re * tw_re - im * tw_im
            acc_im += re * tw_im + im * tw_re
        output[2 * index] = acc_re
        output[2 * index + 1] = acc_im


def complex_channel_kernel(
    input: TileTensor[DType.float32, type_of(channel_layout), MutAnyOrigin],
    coefficients: TileTensor[DType.float32, type_of(channel_layout), MutAnyOrigin],
    noise: TileTensor[DType.float32, type_of(channel_layout), MutAnyOrigin],
    output: TileTensor[DType.float32, type_of(channel_layout), MutAnyOrigin],
):
    var index = block_idx.x * block_dim.x + thread_idx.x
    if index < fft_complex_count:
        var re = input[2 * index]
        var im = input[2 * index + 1]
        var hr = coefficients[2 * index]
        var hi = coefficients[2 * index + 1]
        output[2 * index] = re * hr - im * hi + noise[2 * index]
        output[2 * index + 1] = re * hi + im * hr + noise[2 * index + 1]


def mimo_2x2_matvec_kernel(
    input: TileTensor[DType.float32, type_of(mimo_input_layout), MutAnyOrigin],
    weights: TileTensor[DType.float32, type_of(mimo_weight_layout), MutAnyOrigin],
    output: TileTensor[DType.float32, type_of(mimo_input_layout), MutAnyOrigin],
):
    var index = block_idx.x * block_dim.x + thread_idx.x
    if index < fft_batches * 2:
        var batch = index // 2
        var row = index % 2
        var acc_re = Float32(0.0)
        var acc_im = Float32(0.0)
        for column in range(2):
            var w = 2 * (row * 2 + column)
            var x = 2 * (batch * 2 + column)
            acc_re += weights[w] * input[x] - weights[w + 1] * input[x + 1]
            acc_im += weights[w] * input[x + 1] + weights[w + 1] * input[x]
        output[2 * index] = acc_re
        output[2 * index + 1] = acc_im


def ldpc_check_node_kernel(
    input: TileTensor[DType.float32, type_of(ldpc_layout), MutAnyOrigin],
    output: TileTensor[DType.float32, type_of(ldpc_layout), MutAnyOrigin],
):
    var edge = block_idx.x * block_dim.x + thread_idx.x
    if edge < ldpc_checks * ldpc_degree:
        var check = edge // ldpc_degree
        var excluded = edge % ldpc_degree
        var minimum = Float32(3.4028235e38)
        var sign = Int32(1)
        for local in range(ldpc_degree):
            if local != excluded:
                var value = input[check * ldpc_degree + local]
                minimum = min(minimum, abs(value))
                if value < 0.0:
                    sign = -sign
        output[edge] = minimum if sign > 0 else -minimum


def complex_correlation_kernel(
    signal: TileTensor[DType.float32, type_of(correlation_signal_layout), MutAnyOrigin],
    reference: TileTensor[DType.float32, type_of(correlation_reference_layout), MutAnyOrigin],
    output: TileTensor[DType.float32, type_of(correlation_output_layout), MutAnyOrigin],
):
    var offset = block_idx.x * block_dim.x + thread_idx.x
    if offset < correlation_offsets:
        var acc_re = Float32(0.0)
        var acc_im = Float32(0.0)
        for k in range(correlation_reference):
            var sample_index = 2 * (offset + k)
            var reference_index = 2 * k
            var sr = signal[sample_index]
            var si = signal[sample_index + 1]
            var rr = reference[reference_index]
            var ri = reference[reference_index + 1]
            acc_re += sr * rr + si * ri
            acc_im += si * rr - sr * ri
        output[2 * offset] = acc_re
        output[2 * offset + 1] = acc_im


def main() raises:
    comptime if not has_accelerator():
        print("Phase 6 GPU FFT/channel/MIMO/LDPC/correlation kernels compiled; runtime skipped")
    else:
        var context = DeviceContext()
        # Batched DFT oracle: a batch-specific impulse transforms to a
        # constant real spectrum of the same amplitude.
        var fft_input_host = context.enqueue_create_host_buffer[DType.float32](2 * fft_complex_count)
        for i in range(2 * fft_complex_count):
            fft_input_host[i] = 0.0
        for batch in range(fft_batches):
            fft_input_host[2 * batch * fft_size] = Float32(batch + 1)
        var fft_a = context.enqueue_create_buffer[DType.float32](2 * fft_complex_count)
        var fft_b = context.enqueue_create_buffer[DType.float32](2 * fft_complex_count)
        var fft_c = context.enqueue_create_buffer[DType.float32](2 * fft_complex_count)
        var fft_d = context.enqueue_create_buffer[DType.float32](2 * fft_complex_count)
        context.enqueue_copy(dst_buf=fft_a, src_buf=fft_input_host)
        var fft_a_tensor = TileTensor(fft_a, fft_layout)
        var fft_b_tensor = TileTensor(fft_b, fft_layout)
        var fft_c_tensor = TileTensor(fft_c, fft_layout)
        var fft_d_tensor = TileTensor(fft_d, fft_layout)
        context.enqueue_function[batched_dft64_kernel](
            fft_a_tensor, fft_d_tensor,
            grid_dim=ceildiv(fft_complex_count, block_size), block_dim=block_size,
        )
        var fft_output_host = context.enqueue_create_host_buffer[DType.float32](2 * fft_complex_count)
        context.enqueue_copy(dst_buf=fft_output_host, src_buf=fft_d)
        context.synchronize()
        for batch in range(fft_batches):
            for k in range(fft_size):
                var index = 2 * (batch * fft_size + k)
                if abs(fft_output_host[index] - Float32(batch + 1)) > 1.0e-4:
                    raise Error("GPU batched DFT real output mismatch")
                if abs(fft_output_host[index + 1]) > 1.0e-4:
                    raise Error("GPU batched DFT imaginary output mismatch")

        # Pointwise complex channel with explicit coefficient/noise vectors.
        var coefficient_host = context.enqueue_create_host_buffer[DType.float32](2 * fft_complex_count)
        var noise_host = context.enqueue_create_host_buffer[DType.float32](2 * fft_complex_count)
        for i in range(fft_complex_count):
            fft_input_host[2 * i] = Float32(i % 7) - 3.0
            fft_input_host[2 * i + 1] = Float32(i % 5) - 2.0
            coefficient_host[2 * i] = 0.5
            coefficient_host[2 * i + 1] = -0.25
            noise_host[2 * i] = 0.125
            noise_host[2 * i + 1] = -0.0625
        context.enqueue_copy(dst_buf=fft_a, src_buf=fft_input_host)
        context.enqueue_copy(dst_buf=fft_b, src_buf=coefficient_host)
        context.enqueue_copy(dst_buf=fft_c, src_buf=noise_host)
        context.enqueue_function[complex_channel_kernel](
            fft_a_tensor, fft_b_tensor, fft_c_tensor, fft_d_tensor,
            grid_dim=ceildiv(fft_complex_count, block_size), block_dim=block_size,
        )
        var channel_output_host = context.enqueue_create_host_buffer[DType.float32](2 * fft_complex_count)
        context.enqueue_copy(dst_buf=channel_output_host, src_buf=fft_d)
        context.synchronize()
        for i in range(fft_complex_count):
            var re = fft_input_host[2 * i]
            var im = fft_input_host[2 * i + 1]
            var expected_re = re * 0.5 + im * 0.25 + 0.125
            var expected_im = -re * 0.25 + im * 0.5 - 0.0625
            if abs(channel_output_host[2 * i] - expected_re) > 1.0e-6:
                raise Error("GPU complex-channel real output mismatch")
            if abs(channel_output_host[2 * i + 1] - expected_im) > 1.0e-6:
                raise Error("GPU complex-channel imaginary output mismatch")

        var mimo_a = context.enqueue_create_buffer[DType.float32](2 * fft_batches * 2)
        var mimo_b = context.enqueue_create_buffer[DType.float32](2 * fft_batches * 2)
        var weights = context.enqueue_create_buffer[DType.float32](2 * 2 * 2)
        var mimo_input_host = context.enqueue_create_host_buffer[DType.float32](2 * fft_batches * 2)
        var mimo_output_host = context.enqueue_create_host_buffer[DType.float32](2 * fft_batches * 2)
        var weights_host = context.enqueue_create_host_buffer[DType.float32](2 * 2 * 2)
        for i in range(2 * fft_batches * 2):
            mimo_input_host[i] = Float32(i) * 0.125 - 0.5
        for i in range(2 * 2 * 2):
            weights_host[i] = 0.0
        weights_host[0] = 1.0
        weights_host[6] = 1.0
        context.enqueue_copy(dst_buf=mimo_a, src_buf=mimo_input_host)
        context.enqueue_copy(dst_buf=weights, src_buf=weights_host)
        context.enqueue_function[mimo_2x2_matvec_kernel](
            TileTensor(mimo_a, mimo_input_layout),
            TileTensor(weights, mimo_weight_layout),
            TileTensor(mimo_b, mimo_input_layout),
            grid_dim=1, block_dim=block_size,
        )
        context.enqueue_copy(dst_buf=mimo_output_host, src_buf=mimo_b)

        var ldpc_a = context.enqueue_create_buffer[DType.float32](ldpc_checks * ldpc_degree)
        var ldpc_b = context.enqueue_create_buffer[DType.float32](ldpc_checks * ldpc_degree)
        var ldpc_input_host = context.enqueue_create_host_buffer[DType.float32](ldpc_checks * ldpc_degree)
        var ldpc_output_host = context.enqueue_create_host_buffer[DType.float32](ldpc_checks * ldpc_degree)
        for check in range(ldpc_checks):
            ldpc_input_host[check * ldpc_degree] = 1.0
            ldpc_input_host[check * ldpc_degree + 1] = -2.0
            ldpc_input_host[check * ldpc_degree + 2] = 3.0
            ldpc_input_host[check * ldpc_degree + 3] = -4.0
        context.enqueue_copy(dst_buf=ldpc_a, src_buf=ldpc_input_host)
        context.enqueue_function[ldpc_check_node_kernel](
            TileTensor(ldpc_a, ldpc_layout), TileTensor(ldpc_b, ldpc_layout),
            grid_dim=ceildiv(ldpc_checks * ldpc_degree, block_size), block_dim=block_size,
        )
        context.enqueue_copy(dst_buf=ldpc_output_host, src_buf=ldpc_b)

        var corr_a = context.enqueue_create_buffer[DType.float32](2 * (correlation_offsets + correlation_reference - 1))
        var corr_b = context.enqueue_create_buffer[DType.float32](2 * correlation_reference)
        var corr_c = context.enqueue_create_buffer[DType.float32](2 * correlation_offsets)
        var corr_signal_host = context.enqueue_create_host_buffer[DType.float32](2 * (correlation_offsets + correlation_reference - 1))
        var corr_reference_host = context.enqueue_create_host_buffer[DType.float32](2 * correlation_reference)
        var corr_output_host = context.enqueue_create_host_buffer[DType.float32](2 * correlation_offsets)
        for i in range(correlation_offsets + correlation_reference - 1):
            corr_signal_host[2 * i] = Float32(i) * 0.03125
            corr_signal_host[2 * i + 1] = Float32(i % 3) - 1.0
        for i in range(2 * correlation_reference):
            corr_reference_host[i] = 0.0
        corr_reference_host[0] = 1.0
        context.enqueue_copy(dst_buf=corr_a, src_buf=corr_signal_host)
        context.enqueue_copy(dst_buf=corr_b, src_buf=corr_reference_host)
        context.enqueue_function[complex_correlation_kernel](
            TileTensor(corr_a, correlation_signal_layout),
            TileTensor(corr_b, correlation_reference_layout),
            TileTensor(corr_c, correlation_output_layout),
            grid_dim=1, block_dim=block_size,
        )
        context.enqueue_copy(dst_buf=corr_output_host, src_buf=corr_c)
        context.synchronize()
        for i in range(2 * fft_batches * 2):
            if abs(mimo_output_host[i] - mimo_input_host[i]) > 1.0e-6:
                raise Error("GPU 2x2 MIMO identity mismatch")
        var expected_ldpc: List[Float32] = [2.0, -1.0, 1.0, -1.0]
        for check in range(ldpc_checks):
            for edge in range(ldpc_degree):
                if abs(ldpc_output_host[check * ldpc_degree + edge] - expected_ldpc[edge]) > 1.0e-6:
                    raise Error("GPU LDPC check-node mismatch")
        for offset in range(correlation_offsets):
            if abs(corr_output_host[2 * offset] - corr_signal_host[2 * offset]) > 1.0e-6:
                raise Error("GPU complex-correlation real mismatch")
            if abs(corr_output_host[2 * offset + 1] - corr_signal_host[2 * offset + 1]) > 1.0e-6:
                raise Error("GPU complex-correlation imaginary mismatch")
        print("Phase 6 GPU FFT/channel/MIMO/LDPC/correlation differential checks passed")
