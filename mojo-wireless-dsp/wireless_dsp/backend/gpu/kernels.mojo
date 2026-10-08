"""Portable pointer-based GPU kernels for wireless DSP primitives.

The module deliberately depends only on the Mojo standard library.  Host-side
code may launch these functions through ``max.gpu.host.DeviceContext``, but the
base ``wireless_dsp`` package does not need MAX or Layout to parse or precompile
this backend.

Complex arrays use interleaved ``Float32`` storage: ``[re0, im0, re1, im1, ...]``.
All lengths are supplied at runtime as ``Int32`` kernel arguments.  Call the
matching host-side validator before allocating buffers or launching a kernel.
"""

from std.gpu import global_idx
from std.math import cos, exp, isfinite, log, sin, sqrt
from std.memory import Pointer


comptime GPU_DEFAULT_BLOCK_SIZE = 256
comptime GPU_MAX_THREADS_PER_BLOCK = 1024
comptime GPU_MAX_RUNTIME_LENGTH = 2147483647
comptime GPU_MIN_ESN0_DB = Float32(-100.0)
comptime GPU_MAX_ESN0_DB = Float32(100.0)
comptime GPU_MIN_CODED_AWGN_NOISE_VARIANCE = Float32(1.0e-8)
comptime GPU_MAX_CODED_AWGN_NOISE_VARIANCE = Float32(1.0e8)
comptime _TWO_PI = 6.283185307179586476925286766559
comptime _TWO_PI_F32 = Float32(6.2831853071795864769)
comptime _QPSK_SCALE = Float32(0.7071067811865475244)
comptime _QAM16_SCALE = Float32(0.3162277660168379332)


def _checked_product(lhs: Int, rhs: Int) raises -> Int:
    if lhs < 0 or rhs < 0:
        raise Error("GPU lengths must be non-negative")
    if lhs != 0 and rhs > GPU_MAX_RUNTIME_LENGTH // lhs:
        raise Error("GPU configuration exceeds the Int32 runtime-length limit")
    return lhs * rhs


def _validate_runtime_length(value: Int) raises:
    if value < 0 or value > GPU_MAX_RUNTIME_LENGTH:
        raise Error("GPU buffer length must fit in a non-negative Int32")


def gpu_grid_size(
    work_items: Int, block_size: Int = GPU_DEFAULT_BLOCK_SIZE
) raises -> Int:
    """Return the one-dimensional grid size for validated launch dimensions."""
    if work_items < 0 or work_items > GPU_MAX_RUNTIME_LENGTH:
        raise Error("GPU work-item count must fit in a non-negative Int32")
    if block_size <= 0 or block_size > GPU_MAX_THREADS_PER_BLOCK:
        raise Error("GPU block size must be in the inclusive range 1..1024")
    if work_items == 0:
        return 0
    return (work_items + block_size - 1) // block_size


def validate_batched_fft_config(
    fft_size: Int,
    batch_count: Int,
    input_scalar_count: Int,
    output_scalar_count: Int,
) raises -> Int:
    """Validate interleaved buffers and return one work item per FFT batch."""
    if fft_size <= 0 or (fft_size & (fft_size - 1)) != 0:
        raise Error("GPU FFT size must be a positive power of two")
    if batch_count <= 0:
        raise Error("GPU FFT batch count must be positive")
    var complex_count = _checked_product(fft_size, batch_count)
    var required_scalars = _checked_product(complex_count, 2)
    if input_scalar_count < required_scalars:
        raise Error("GPU FFT input buffer is too small")
    if output_scalar_count < required_scalars:
        raise Error("GPU FFT output buffer is too small")
    return batch_count


def validate_complex_channel_config(
    complex_count: Int,
    input_scalar_count: Int,
    coefficient_scalar_count: Int,
    noise_scalar_count: Int,
    output_scalar_count: Int,
) raises -> Int:
    """Validate ``y = h*x + noise`` buffers and return the work-item count."""
    if complex_count <= 0:
        raise Error("GPU channel complex count must be positive")
    var required_scalars = _checked_product(complex_count, 2)
    if input_scalar_count < required_scalars:
        raise Error("GPU channel input buffer is too small")
    if coefficient_scalar_count < required_scalars:
        raise Error("GPU channel coefficient buffer is too small")
    if noise_scalar_count < required_scalars:
        raise Error("GPU channel noise buffer is too small")
    if output_scalar_count < required_scalars:
        raise Error("GPU channel output buffer is too small")
    return complex_count


def validate_mimo_2x2_config(
    batch_count: Int,
    input_scalar_count: Int,
    matrix_scalar_count: Int,
    output_scalar_count: Int,
) raises -> Int:
    """Validate a shared complex 2x2 matrix and batched two-vector buffers."""
    if batch_count <= 0:
        raise Error("GPU MIMO batch count must be positive")
    var vector_scalars = _checked_product(batch_count, 4)
    if input_scalar_count < vector_scalars:
        raise Error("GPU MIMO input buffer is too small")
    if matrix_scalar_count < 8:
        raise Error("GPU MIMO matrix buffer requires eight interleaved scalars")
    if output_scalar_count < vector_scalars:
        raise Error("GPU MIMO output buffer is too small")
    return _checked_product(batch_count, 2)


def validate_complex_correlation_config(
    signal_complex_count: Int,
    reference_complex_count: Int,
    output_complex_count: Int,
    signal_scalar_count: Int,
    reference_scalar_count: Int,
    output_scalar_count: Int,
) raises -> Int:
    """Validate a valid-range ``signal * conj(reference)`` correlation launch."""
    if signal_complex_count <= 0 or reference_complex_count <= 0:
        raise Error("GPU correlation signal and reference must be non-empty")
    if reference_complex_count > signal_complex_count:
        raise Error("GPU correlation reference cannot exceed the signal")
    var maximum_outputs = signal_complex_count - reference_complex_count + 1
    if output_complex_count <= 0 or output_complex_count > maximum_outputs:
        raise Error("GPU correlation output count exceeds the valid range")
    var required_signal = _checked_product(signal_complex_count, 2)
    var required_reference = _checked_product(reference_complex_count, 2)
    var required_output = _checked_product(output_complex_count, 2)
    if signal_scalar_count < required_signal:
        raise Error("GPU correlation signal buffer is too small")
    if reference_scalar_count < required_reference:
        raise Error("GPU correlation reference buffer is too small")
    if output_scalar_count < required_output:
        raise Error("GPU correlation output buffer is too small")
    return output_complex_count


def validate_ldpc_check_node_config(
    check_count: Int,
    degree: Int,
    input_llr_count: Int,
    output_llr_count: Int,
) raises -> Int:
    """Validate regular-row min-sum check-node buffers and return edge count."""
    if check_count <= 0:
        raise Error("GPU LDPC check count must be positive")
    if degree < 2:
        raise Error("GPU LDPC check-node degree must be at least two")
    var edge_count = _checked_product(check_count, degree)
    if input_llr_count < edge_count:
        raise Error("GPU LDPC input LLR buffer is too small")
    if output_llr_count < edge_count:
        raise Error("GPU LDPC output LLR buffer is too small")
    return edge_count


def validate_batched_sparse_ldpc_min_sum_decode_config[
    llr_origin: Origin,
    row_origin: Origin,
    column_origin: Origin,
](
    channel_llrs: Pointer[Float32, llr_origin],
    row_offsets: Pointer[Int32, row_origin],
    columns: Pointer[Int32, column_origin],
    channel_llr_count: Int,
    row_offset_count: Int,
    column_count: Int,
    hard_bit_count: Int,
    iterations_count: Int,
    converged_count: Int,
    syndrome_weight_count: Int,
    variable_to_check_workspace_count: Int,
    check_to_variable_workspace_count: Int,
    posterior_workspace_count: Int,
    variable_count: Int,
    check_count: Int,
    edge_count: Int,
    batch_count: Int,
    max_iterations: Int,
    normalization: Float32,
    offset: Float32,
    clip: Float32,
) raises -> Int:
    """Validate a batched CSR flooding normalized/offset min-sum decode.

    The parity-check graph is shared by every codeword.  Channel LLR, hard-bit
    and posterior buffers use ``[batch][variable]`` layout; both message
    workspaces use ``[batch][edge]`` layout; scalar results use ``[batch]``.
    The returned launch size is one sequential decoder work item per codeword.
    """
    if variable_count <= 0 or check_count <= 0 or edge_count <= 0:
        raise Error("GPU sparse LDPC dimensions must be positive")
    if (
        batch_count <= 0
        or max_iterations <= 0
        or max_iterations > GPU_MAX_RUNTIME_LENGTH
    ):
        raise Error("GPU sparse LDPC batch and iteration counts must be positive")
    if check_count >= GPU_MAX_RUNTIME_LENGTH:
        raise Error("GPU sparse LDPC row-offset count exceeds Int32 capacity")
    if (
        not isfinite(normalization)
        or normalization <= 0.0
        or normalization > 1.0
    ):
        raise Error("GPU sparse LDPC normalization must be finite and in (0, 1]")
    if not isfinite(offset) or offset < 0.0:
        raise Error("GPU sparse LDPC offset must be finite and non-negative")
    if not isfinite(clip) or clip <= 0.0:
        raise Error("GPU sparse LDPC clip must be finite and positive")

    _validate_runtime_length(channel_llr_count)
    _validate_runtime_length(row_offset_count)
    _validate_runtime_length(column_count)
    _validate_runtime_length(hard_bit_count)
    _validate_runtime_length(iterations_count)
    _validate_runtime_length(converged_count)
    _validate_runtime_length(syndrome_weight_count)
    _validate_runtime_length(variable_to_check_workspace_count)
    _validate_runtime_length(check_to_variable_workspace_count)
    _validate_runtime_length(posterior_workspace_count)

    var required_channel = _checked_product(batch_count, variable_count)
    var required_messages = _checked_product(batch_count, edge_count)
    if channel_llr_count < required_channel:
        raise Error("GPU sparse LDPC channel-LLR buffer is too small")
    if row_offset_count < check_count + 1:
        raise Error("GPU sparse LDPC row-offset buffer is too small")
    if column_count < edge_count:
        raise Error("GPU sparse LDPC column buffer is too small")
    if hard_bit_count < required_channel:
        raise Error("GPU sparse LDPC hard-bit buffer is too small")
    if iterations_count < batch_count:
        raise Error("GPU sparse LDPC iterations buffer is too small")
    if converged_count < batch_count:
        raise Error("GPU sparse LDPC converged buffer is too small")
    if syndrome_weight_count < batch_count:
        raise Error("GPU sparse LDPC syndrome-weight buffer is too small")
    if variable_to_check_workspace_count < required_messages:
        raise Error("GPU sparse LDPC variable-to-check workspace is too small")
    if check_to_variable_workspace_count < required_messages:
        raise Error("GPU sparse LDPC check-to-variable workspace is too small")
    if posterior_workspace_count < required_channel:
        raise Error("GPU sparse LDPC posterior workspace is too small")

    if row_offsets[unsafe_offset=0] != 0:
        raise Error("GPU sparse LDPC row offsets must start at zero")
    if Int(row_offsets[unsafe_offset=check_count]) != edge_count:
        raise Error("GPU sparse LDPC final row offset must equal edge count")
    for row in range(check_count):
        var start = Int(row_offsets[unsafe_offset=row])
        var end = Int(row_offsets[unsafe_offset=row + 1])
        if start < 0 or end < start or end > edge_count:
            raise Error("GPU sparse LDPC row offsets must be ordered and in range")
        if end - start < 2:
            raise Error("GPU sparse LDPC check degree must be at least two")
        for lhs in range(start, end):
            var column = Int(columns[unsafe_offset=lhs])
            if column < 0 or column >= variable_count:
                raise Error("GPU sparse LDPC column is out of range")
            for rhs in range(lhs + 1, end):
                if columns[unsafe_offset=rhs] == columns[unsafe_offset=lhs]:
                    raise Error("GPU sparse LDPC row contains a duplicate column")
    # Columns are visited above row by row, but retain this invariant if a
    # future caller supplies unused capacity after the logical edge count.
    for edge in range(edge_count):
        var column = Int(columns[unsafe_offset=edge])
        if column < 0 or column >= variable_count:
            raise Error("GPU sparse LDPC column is out of range")

    var maximum_input_magnitude = Float64(0.0)
    for index in range(required_channel):
        var value = channel_llrs[unsafe_offset=index]
        if not isfinite(value):
            raise Error("GPU sparse LDPC channel LLRs must be finite")
        maximum_input_magnitude = max(
            maximum_input_magnitude, abs(Float64(value))
        )
    # Flooding accumulation stores Float32 posterior values.  This conservative
    # all-edges-on-one-variable bound rejects only configurations whose finite
    # inputs could overflow before the configured clip is applied.
    var accumulation_bound = Float64(edge_count + 1) * max(
        maximum_input_magnitude, Float64(clip)
    )
    if accumulation_bound > Float64(3.0e38):
        raise Error("GPU sparse LDPC accumulation can exceed Float32 capacity")
    return batch_count


def validate_coded_bpsk_awgn_llr_config[
    bit_origin: Origin,
    noise_origin: Origin,
    seed_origin: Origin,
](
    codeword_bits: Pointer[UInt8, bit_origin],
    noise_variances: Pointer[Float32, noise_origin],
    seeds: Pointer[UInt64, seed_origin],
    codeword_bit_count: Int,
    noise_variance_count: Int,
    seed_count: Int,
    output_llr_count: Int,
    variable_count: Int,
    batch_count: Int,
) raises -> Int:
    """Validate a batched coded-BPSK real-AWGN soft-channel launch.

    Bits and output LLRs use ``[batch][variable]`` layout.  Each batch has an
    explicit real-noise variance and seed.  The accepted variance range keeps
    Box-Muller scaling and ``2*y/variance`` finite in Float32.  Sweep callers
    use the canonical seed-major/SNR-major index
    ``batch = seed_index * snr_count + snr_index``.
    """
    if variable_count <= 0 or batch_count <= 0:
        raise Error("GPU coded AWGN dimensions must be positive")
    _validate_runtime_length(codeword_bit_count)
    _validate_runtime_length(noise_variance_count)
    _validate_runtime_length(seed_count)
    _validate_runtime_length(output_llr_count)
    var required_bits = _checked_product(batch_count, variable_count)
    if codeword_bit_count < required_bits:
        raise Error("GPU coded AWGN codeword-bit buffer is too small")
    if noise_variance_count < batch_count:
        raise Error("GPU coded AWGN noise-variance buffer is too small")
    if seed_count < batch_count:
        raise Error("GPU coded AWGN seed buffer is too small")
    if output_llr_count < required_bits:
        raise Error("GPU coded AWGN output-LLR buffer is too small")
    for index in range(required_bits):
        if codeword_bits[unsafe_offset=index] > 1:
            raise Error("GPU coded AWGN input bits must be binary")
    for batch in range(batch_count):
        var noise_variance = noise_variances[unsafe_offset=batch]
        if (
            not isfinite(noise_variance)
            or noise_variance < GPU_MIN_CODED_AWGN_NOISE_VARIANCE
            or noise_variance > GPU_MAX_CODED_AWGN_NOISE_VARIANCE
        ):
            raise Error(
                "GPU coded AWGN noise variance must be finite and in 1e-8..1e8"
            )
        # Every UInt64 seed is valid.  Read the explicit entry here so callers
        # cannot accidentally validate a shorter logical seed axis.
        _ = seeds[unsafe_offset=batch]
    return required_bits


def validate_soft_llr_config(
    bits_per_symbol: Int,
    symbol_count: Int,
    noise_variance: Float32,
    iq_scalar_count: Int,
    output_llr_count: Int,
) raises -> Int:
    """Validate QPSK (2-bit) or normalized Gray 16-QAM (4-bit) LLR buffers."""
    if bits_per_symbol != 2 and bits_per_symbol != 4:
        raise Error("GPU soft demapper supports only QPSK and 16-QAM")
    if symbol_count <= 0:
        raise Error("GPU soft-demapper symbol count must be positive")
    if not isfinite(noise_variance) or not (noise_variance > 0.0):
        raise Error(
            "GPU soft-demapper noise variance must be finite and positive"
        )
    var required_iq = _checked_product(symbol_count, 2)
    var required_llrs = _checked_product(symbol_count, bits_per_symbol)
    if iq_scalar_count < required_iq:
        raise Error("GPU soft-demapper IQ buffer is too small")
    if output_llr_count < required_llrs:
        raise Error("GPU soft-demapper LLR buffer is too small")
    return symbol_count


def validate_qam_awgn_ber_sweep_config[origin: Origin](
    bits_per_symbol: Int,
    symbols_per_case: Int,
    esn0_db_values: Pointer[Float32, origin],
    esn0_count: Int,
    seed_count: Int,
    esn0_buffer_count: Int,
    seed_buffer_count: Int,
    received_iq_scalar_count: Int,
    output_llr_count: Int,
    output_error_count: Int,
) raises -> Int:
    """Validate an Es/N0-by-seed QAM/AWGN BER sweep.

    Cases use seed-major layout: ``[seed][Es/N0][symbol]``.  QPSK and
    normalized Gray 16-QAM both have unit mean symbol energy, so each finite
    Es/N0 value maps to complex noise variance ``10**(-EsN0/10)``.  The
    returned work-item count is the total number of symbols across all cases.
    Each output error element is the number of hard-decision bit errors for
    one symbol, allowing a deterministic host reduction without atomics.
    """
    if bits_per_symbol != 2 and bits_per_symbol != 4:
        raise Error("GPU BER sweep supports only QPSK and 16-QAM")
    if symbols_per_case <= 0:
        raise Error("GPU BER sweep symbols per case must be positive")
    if esn0_count <= 0 or seed_count <= 0:
        raise Error("GPU BER sweep requires Es/N0 values and seeds")
    if esn0_buffer_count < esn0_count:
        raise Error("GPU BER sweep Es/N0 buffer is too small")
    if seed_buffer_count < seed_count:
        raise Error("GPU BER sweep seed buffer is too small")
    for index in range(esn0_count):
        var value = esn0_db_values[unsafe_offset=index]
        if (
            not isfinite(value)
            or value < GPU_MIN_ESN0_DB
            or value > GPU_MAX_ESN0_DB
        ):
            raise Error("GPU BER sweep Es/N0 must be finite and in -100..100 dB")
    var case_count = _checked_product(esn0_count, seed_count)
    var total_symbols = _checked_product(case_count, symbols_per_case)
    var required_iq = _checked_product(total_symbols, 2)
    var required_llrs = _checked_product(total_symbols, bits_per_symbol)
    if received_iq_scalar_count < required_iq:
        raise Error("GPU BER sweep received-IQ buffer is too small")
    if output_llr_count < required_llrs:
        raise Error("GPU BER sweep output-LLR buffer is too small")
    if output_error_count < total_symbols:
        raise Error("GPU BER sweep output-error buffer is too small")
    return total_symbols


@always_inline
def _bit_reverse(index: Int, size: Int) -> Int:
    var value = index
    var reversed = 0
    var remaining = size
    while remaining > 1:
        reversed = (reversed << 1) | (value & 1)
        value >>= 1
        remaining >>= 1
    return reversed


@always_inline
def _batched_fft_radix2[
    inverse: Bool
](
    input: Pointer[Float32, ImmutAnyOrigin],
    output: Pointer[Float32, MutAnyOrigin],
    fft_size_dev: Int32,
    batch_count_dev: Int32,
):
    var batch = global_idx.x
    var fft_size = Int(fft_size_dev)
    var batch_count = Int(batch_count_dev)
    if batch >= batch_count:
        return

    var base = batch * fft_size

    # First copy in natural order.  The subsequent in-place permutation means
    # the kernel also works when input and output alias exactly.
    for index in range(fft_size):
        var scalar_index = 2 * (base + index)
        output[unsafe_offset=scalar_index] = input[unsafe_offset=scalar_index]
        output[unsafe_offset=scalar_index + 1] = input[
            unsafe_offset=scalar_index + 1
        ]

    for index in range(fft_size):
        var reversed = _bit_reverse(index, fft_size)
        if reversed > index:
            var lhs = 2 * (base + index)
            var rhs = 2 * (base + reversed)
            var lhs_re = output[unsafe_offset=lhs]
            var lhs_im = output[unsafe_offset=lhs + 1]
            output[unsafe_offset=lhs] = output[unsafe_offset=rhs]
            output[unsafe_offset=lhs + 1] = output[unsafe_offset=rhs + 1]
            output[unsafe_offset=rhs] = lhs_re
            output[unsafe_offset=rhs + 1] = lhs_im

    var stage_size = 2
    while stage_size <= fft_size:
        var half = stage_size // 2
        for group in range(0, fft_size, stage_size):
            for offset in range(half):
                var angle = (
                    (_TWO_PI if inverse else -_TWO_PI)
                    * Float64(offset)
                    / Float64(stage_size)
                )
                var twiddle_re = Float32(cos(angle))
                var twiddle_im = Float32(sin(angle))
                var even_index = 2 * (base + group + offset)
                var odd_index = 2 * (base + group + offset + half)
                var even_re = output[unsafe_offset=even_index]
                var even_im = output[unsafe_offset=even_index + 1]
                var odd_re = output[unsafe_offset=odd_index]
                var odd_im = output[unsafe_offset=odd_index + 1]
                var product_re = odd_re * twiddle_re - odd_im * twiddle_im
                var product_im = odd_re * twiddle_im + odd_im * twiddle_re
                output[unsafe_offset=even_index] = even_re + product_re
                output[unsafe_offset=even_index + 1] = even_im + product_im
                output[unsafe_offset=odd_index] = even_re - product_re
                output[unsafe_offset=odd_index + 1] = even_im - product_im
        stage_size <<= 1

    comptime if inverse:
        var scale = Float32(1.0) / Float32(fft_size)
        for index in range(fft_size):
            var scalar_index = 2 * (base + index)
            output[unsafe_offset=scalar_index] *= scale
            output[unsafe_offset=scalar_index + 1] *= scale


def batched_fft_radix2_kernel(
    input: Pointer[Float32, ImmutAnyOrigin],
    output: Pointer[Float32, MutAnyOrigin],
    fft_size: Int32,
    batch_count: Int32,
):
    """Forward radix-2 FFT, one readable reference thread per batch."""
    _batched_fft_radix2[False](input, output, fft_size, batch_count)


def batched_ifft_radix2_kernel(
    input: Pointer[Float32, ImmutAnyOrigin],
    output: Pointer[Float32, MutAnyOrigin],
    fft_size: Int32,
    batch_count: Int32,
):
    """Normalized inverse radix-2 FFT, one readable reference thread per batch."""
    _batched_fft_radix2[True](input, output, fft_size, batch_count)


def complex_channel_kernel(
    input: Pointer[Float32, ImmutAnyOrigin],
    coefficients: Pointer[Float32, ImmutAnyOrigin],
    noise: Pointer[Float32, ImmutAnyOrigin],
    output: Pointer[Float32, MutAnyOrigin],
    complex_count_dev: Int32,
):
    """Apply pointwise ``output = coefficients * input + noise``."""
    var index = global_idx.x
    var complex_count = Int(complex_count_dev)
    if index >= complex_count:
        return
    var scalar_index = 2 * index
    var re = input[unsafe_offset=scalar_index]
    var im = input[unsafe_offset=scalar_index + 1]
    var hr = coefficients[unsafe_offset=scalar_index]
    var hi = coefficients[unsafe_offset=scalar_index + 1]
    output[unsafe_offset=scalar_index] = (
        re * hr - im * hi + noise[unsafe_offset=scalar_index]
    )
    output[unsafe_offset=scalar_index + 1] = (
        re * hi + im * hr + noise[unsafe_offset=scalar_index + 1]
    )


def mimo_2x2_matvec_kernel(
    input: Pointer[Float32, ImmutAnyOrigin],
    matrix: Pointer[Float32, ImmutAnyOrigin],
    output: Pointer[Float32, MutAnyOrigin],
    batch_count_dev: Int32,
):
    """Multiply batched complex two-vectors by one shared complex 2x2 matrix."""
    var work_item = global_idx.x
    var batch_count = Int(batch_count_dev)
    if work_item >= 2 * batch_count:
        return
    var batch = work_item // 2
    var row = work_item % 2
    var acc_re = Float32(0.0)
    var acc_im = Float32(0.0)
    for column in range(2):
        var matrix_index = 2 * (2 * row + column)
        var input_index = 2 * (2 * batch + column)
        var wr = matrix[unsafe_offset=matrix_index]
        var wi = matrix[unsafe_offset=matrix_index + 1]
        var xr = input[unsafe_offset=input_index]
        var xi = input[unsafe_offset=input_index + 1]
        acc_re += wr * xr - wi * xi
        acc_im += wr * xi + wi * xr
    var output_index = 2 * work_item
    output[unsafe_offset=output_index] = acc_re
    output[unsafe_offset=output_index + 1] = acc_im


def complex_correlation_kernel(
    signal: Pointer[Float32, ImmutAnyOrigin],
    reference: Pointer[Float32, ImmutAnyOrigin],
    output: Pointer[Float32, MutAnyOrigin],
    signal_complex_count_dev: Int32,
    reference_complex_count_dev: Int32,
    output_complex_count_dev: Int32,
):
    """Compute valid-range correlation ``sum(signal * conj(reference))``."""
    var offset = global_idx.x
    var signal_complex_count = Int(signal_complex_count_dev)
    var reference_complex_count = Int(reference_complex_count_dev)
    var output_complex_count = Int(output_complex_count_dev)
    if (
        offset >= output_complex_count
        or offset + reference_complex_count > signal_complex_count
    ):
        return
    var acc_re = Float32(0.0)
    var acc_im = Float32(0.0)
    for index in range(reference_complex_count):
        var signal_index = 2 * (offset + index)
        var reference_index = 2 * index
        var sr = signal[unsafe_offset=signal_index]
        var si = signal[unsafe_offset=signal_index + 1]
        var rr = reference[unsafe_offset=reference_index]
        var ri = reference[unsafe_offset=reference_index + 1]
        acc_re += sr * rr + si * ri
        acc_im += si * rr - sr * ri
    output[unsafe_offset=2 * offset] = acc_re
    output[unsafe_offset=2 * offset + 1] = acc_im


def ldpc_check_node_kernel(
    input_llrs: Pointer[Float32, ImmutAnyOrigin],
    output_llrs: Pointer[Float32, MutAnyOrigin],
    check_count_dev: Int32,
    degree_dev: Int32,
):
    """Regular-row min-sum check-node update, one work item per edge."""
    var edge = global_idx.x
    var check_count = Int(check_count_dev)
    var degree = Int(degree_dev)
    if edge >= check_count * degree:
        return
    var check = edge // degree
    var excluded = edge % degree
    var magnitude = Float32(3.402823466e38)
    var sign = Int32(1)
    for local_edge in range(degree):
        if local_edge != excluded:
            var value = input_llrs[
                unsafe_offset=check * degree + local_edge
            ]
            magnitude = min(magnitude, abs(value))
            if value < 0.0:
                sign = -sign
    output_llrs[unsafe_offset=edge] = magnitude if sign > 0 else -magnitude


def batched_sparse_ldpc_min_sum_decode_kernel(
    channel_llrs: Pointer[Float32, ImmutAnyOrigin],
    row_offsets: Pointer[Int32, ImmutAnyOrigin],
    columns: Pointer[Int32, ImmutAnyOrigin],
    hard_bits: Pointer[UInt8, MutAnyOrigin],
    iterations: Pointer[Int32, MutAnyOrigin],
    converged: Pointer[UInt8, MutAnyOrigin],
    syndrome_weights: Pointer[Int32, MutAnyOrigin],
    variable_to_check_workspace: Pointer[Float32, MutAnyOrigin],
    check_to_variable_workspace: Pointer[Float32, MutAnyOrigin],
    posterior_workspace: Pointer[Float32, MutAnyOrigin],
    channel_llr_count_dev: Int32,
    row_offset_count_dev: Int32,
    column_count_dev: Int32,
    hard_bit_count_dev: Int32,
    iterations_count_dev: Int32,
    converged_count_dev: Int32,
    syndrome_weight_count_dev: Int32,
    variable_to_check_workspace_count_dev: Int32,
    check_to_variable_workspace_count_dev: Int32,
    posterior_workspace_count_dev: Int32,
    variable_count_dev: Int32,
    check_count_dev: Int32,
    edge_count_dev: Int32,
    batch_count_dev: Int32,
    max_iterations_dev: Int32,
    normalization: Float32,
    offset: Float32,
    clip: Float32,
):
    """Decode one CSR LDPC codeword per work item using flooding min-sum.

    All storage is caller-owned.  LLR, hard-bit and posterior buffers use
    ``[batch][variable]`` layout; message workspaces use ``[batch][edge]``;
    result arrays use ``[batch]``.  The final syndrome weight is the number of
    unsatisfied parity checks and is zero exactly when ``converged`` is one.
    """
    var codeword = global_idx.x
    var channel_llr_count = Int(channel_llr_count_dev)
    var row_offset_count = Int(row_offset_count_dev)
    var column_count = Int(column_count_dev)
    var hard_bit_count = Int(hard_bit_count_dev)
    var iterations_count = Int(iterations_count_dev)
    var converged_count = Int(converged_count_dev)
    var syndrome_weight_count = Int(syndrome_weight_count_dev)
    var variable_to_check_workspace_count = Int(
        variable_to_check_workspace_count_dev
    )
    var check_to_variable_workspace_count = Int(
        check_to_variable_workspace_count_dev
    )
    var posterior_workspace_count = Int(posterior_workspace_count_dev)
    var variable_count = Int(variable_count_dev)
    var check_count = Int(check_count_dev)
    var edge_count = Int(edge_count_dev)
    var batch_count = Int(batch_count_dev)
    var max_iterations = Int(max_iterations_dev)
    if codeword >= batch_count:
        return
    if (
        variable_count <= 0
        or check_count <= 0
        or edge_count <= 0
        or batch_count <= 0
        or max_iterations <= 0
        or not isfinite(normalization)
        or normalization <= 0.0
        or normalization > 1.0
        or not isfinite(offset)
        or offset < 0.0
        or not isfinite(clip)
        or clip <= 0.0
    ):
        return
    var required_channel = batch_count * variable_count
    var required_messages = batch_count * edge_count
    if (
        channel_llr_count < required_channel
        or row_offset_count < check_count + 1
        or column_count < edge_count
        or hard_bit_count < required_channel
        or iterations_count < batch_count
        or converged_count < batch_count
        or syndrome_weight_count < batch_count
        or variable_to_check_workspace_count < required_messages
        or check_to_variable_workspace_count < required_messages
        or posterior_workspace_count < required_channel
    ):
        return

    var variable_base = codeword * variable_count
    var edge_base = codeword * edge_count
    for edge in range(edge_count):
        var variable = Int(columns[unsafe_offset=edge])
        variable_to_check_workspace[unsafe_offset=edge_base + edge] = (
            channel_llrs[unsafe_offset=variable_base + variable]
        )

    var final_syndrome_weight = Int32(check_count)
    for iteration in range(max_iterations):
        for row in range(check_count):
            var start = Int(row_offsets[unsafe_offset=row])
            var end = Int(row_offsets[unsafe_offset=row + 1])
            var minimum = Float32(3.402823466e38)
            var second = Float32(3.402823466e38)
            var minimum_edge = -1
            var all_sign = Int32(1)
            for edge in range(start, end):
                var value = variable_to_check_workspace[
                    unsafe_offset=edge_base + edge
                ]
                var magnitude = abs(value)
                if magnitude < minimum:
                    second = minimum
                    minimum = magnitude
                    minimum_edge = edge
                elif magnitude < second:
                    second = magnitude
                if value < 0.0:
                    all_sign = -all_sign
            for edge in range(start, end):
                var value = variable_to_check_workspace[
                    unsafe_offset=edge_base + edge
                ]
                var magnitude = second if edge == minimum_edge else minimum
                magnitude = max(
                    Float32(0.0), normalization * magnitude - offset
                )
                var sign = -all_sign if value < 0.0 else all_sign
                check_to_variable_workspace[unsafe_offset=edge_base + edge] = (
                    magnitude if sign > 0 else -magnitude
                )

        for variable in range(variable_count):
            posterior_workspace[unsafe_offset=variable_base + variable] = (
                channel_llrs[unsafe_offset=variable_base + variable]
            )
        for edge in range(edge_count):
            var variable = Int(columns[unsafe_offset=edge])
            posterior_workspace[unsafe_offset=variable_base + variable] += (
                check_to_variable_workspace[unsafe_offset=edge_base + edge]
            )
        for variable in range(variable_count):
            var posterior = posterior_workspace[
                unsafe_offset=variable_base + variable
            ]
            posterior = max(-clip, min(clip, posterior))
            posterior_workspace[unsafe_offset=variable_base + variable] = (
                posterior
            )
            hard_bits[unsafe_offset=variable_base + variable] = (
                UInt8(0) if posterior >= 0.0 else UInt8(1)
            )

        final_syndrome_weight = Int32(0)
        for row in range(check_count):
            var parity = UInt8(0)
            var start = Int(row_offsets[unsafe_offset=row])
            var end = Int(row_offsets[unsafe_offset=row + 1])
            for edge in range(start, end):
                var variable = Int(columns[unsafe_offset=edge])
                parity ^= hard_bits[unsafe_offset=variable_base + variable]
            if parity != 0:
                final_syndrome_weight += 1
        if final_syndrome_weight == 0:
            iterations[unsafe_offset=codeword] = Int32(iteration + 1)
            converged[unsafe_offset=codeword] = UInt8(1)
            syndrome_weights[unsafe_offset=codeword] = Int32(0)
            return

        for edge in range(edge_count):
            var variable = Int(columns[unsafe_offset=edge])
            variable_to_check_workspace[unsafe_offset=edge_base + edge] = max(
                -clip,
                min(
                    clip,
                    posterior_workspace[unsafe_offset=variable_base + variable]
                    - check_to_variable_workspace[
                        unsafe_offset=edge_base + edge
                    ],
                ),
            )

    iterations[unsafe_offset=codeword] = Int32(max_iterations)
    converged[unsafe_offset=codeword] = UInt8(0)
    syndrome_weights[unsafe_offset=codeword] = final_syndrome_weight


@always_inline
def _squared_distance(value: Float32, level: Float32) -> Float32:
    var difference = value - level
    return difference * difference


def qpsk_soft_llr_kernel(
    iq: Pointer[Float32, ImmutAnyOrigin],
    output_llrs: Pointer[Float32, MutAnyOrigin],
    symbol_count_dev: Int32,
    noise_variance: Float32,
):
    """Max-log LLRs for unit-energy Gray QPSK; positive means bit zero."""
    var symbol = global_idx.x
    var symbol_count = Int(symbol_count_dev)
    if symbol >= symbol_count:
        return
    for component in range(2):
        var value = iq[unsafe_offset=2 * symbol + component]
        var distance_zero = _squared_distance(value, _QPSK_SCALE)
        var distance_one = _squared_distance(value, -_QPSK_SCALE)
        output_llrs[unsafe_offset=2 * symbol + component] = (
            (distance_one - distance_zero) / noise_variance
        )


def qam16_soft_llr_kernel(
    iq: Pointer[Float32, ImmutAnyOrigin],
    output_llrs: Pointer[Float32, MutAnyOrigin],
    symbol_count_dev: Int32,
    noise_variance: Float32,
):
    """Max-log LLRs for unit-energy Gray 16-QAM; positive means bit zero.

    Per real component the Gray labels from negative to positive are
    ``10, 11, 01, 00``.  Output order is ``I-sign, I-mag, Q-sign, Q-mag``.
    """
    var symbol = global_idx.x
    var symbol_count = Int(symbol_count_dev)
    if symbol >= symbol_count:
        return
    var inner = _QAM16_SCALE
    var outer = Float32(3.0) * _QAM16_SCALE
    for component in range(2):
        var value = iq[unsafe_offset=2 * symbol + component]
        var d_negative_outer = _squared_distance(value, -outer)
        var d_negative_inner = _squared_distance(value, -inner)
        var d_positive_inner = _squared_distance(value, inner)
        var d_positive_outer = _squared_distance(value, outer)

        # Sign bit: zero on positive levels, one on negative levels.
        var sign_zero = min(d_positive_inner, d_positive_outer)
        var sign_one = min(d_negative_inner, d_negative_outer)
        # Magnitude bit: zero on outer levels, one on inner levels.
        var magnitude_zero = min(d_negative_outer, d_positive_outer)
        var magnitude_one = min(d_negative_inner, d_positive_inner)
        var output_index = 4 * symbol + 2 * component
        output_llrs[unsafe_offset=output_index] = (
            (sign_one - sign_zero) / noise_variance
        )
        output_llrs[unsafe_offset=output_index + 1] = (
            (magnitude_one - magnitude_zero) / noise_variance
        )


@always_inline
def _ber_counter_word(seed: UInt64, counter: UInt64, stream: UInt64) -> UInt64:
    """Counter-based SplitMix64 word used by the reproducible BER sweep."""
    var value = (
        seed
        + UInt64(0x9E3779B97F4A7C15) * (counter + UInt64(1))
        + UInt64(0xD1B54A32D192ED03) * (stream + UInt64(1))
    )
    value = (value ^ (value >> 30)) * UInt64(0xBF58476D1CE4E5B9)
    value = (value ^ (value >> 27)) * UInt64(0x94D049BB133111EB)
    return value ^ (value >> 31)


@always_inline
def _ber_uniform_open(seed: UInt64, counter: UInt64, stream: UInt64) -> Float32:
    # The upper 24 random bits map to the open interval (0, 1), matching the
    # precision of Float32 while ensuring Box-Muller never evaluates log(0).
    var word = _ber_counter_word(seed, counter, stream)
    return (
        Float32(UInt32(word >> 40)) + Float32(0.5)
    ) * Float32(5.9604644775390625e-8)


def coded_bpsk_awgn_llr_kernel(
    codeword_bits: Pointer[UInt8, ImmutAnyOrigin],
    noise_variances: Pointer[Float32, ImmutAnyOrigin],
    seeds: Pointer[UInt64, ImmutAnyOrigin],
    output_llrs: Pointer[Float32, MutAnyOrigin],
    codeword_bit_count_dev: Int32,
    noise_variance_count_dev: Int32,
    seed_count_dev: Int32,
    output_llr_count_dev: Int32,
    variable_count_dev: Int32,
    batch_count_dev: Int32,
    total_bit_count_dev: Int32,
):
    """Generate seeded real-AWGN LLRs for batched coded BPSK bits.

    Bits and LLRs use ``[batch][variable]`` layout; variance and seed use
    ``[batch]``.  Bit zero maps to +1 and bit one maps to -1.  The variance is
    the real noise-component variance ``sigma^2``, hence the exact channel LLR
    is ``2*y/sigma^2``.  The counter RNG depends only on the explicit seed and
    variable index.  With the canonical seed-major/SNR-major batch index, the
    same seed therefore obtains common standard Gaussian samples at every SNR.
    """
    var work_item = global_idx.x
    var codeword_bit_count = Int(codeword_bit_count_dev)
    var noise_variance_count = Int(noise_variance_count_dev)
    var seed_count = Int(seed_count_dev)
    var output_llr_count = Int(output_llr_count_dev)
    var variable_count = Int(variable_count_dev)
    var batch_count = Int(batch_count_dev)
    var total_bit_count = Int(total_bit_count_dev)
    if work_item >= total_bit_count:
        return
    if variable_count <= 0 or batch_count <= 0:
        return
    var required_bits = batch_count * variable_count
    if (
        total_bit_count != required_bits
        or codeword_bit_count < required_bits
        or noise_variance_count < batch_count
        or seed_count < batch_count
        or output_llr_count < required_bits
    ):
        return
    var batch = work_item // variable_count
    var variable = work_item % variable_count
    var bit = codeword_bits[unsafe_offset=work_item]
    var noise_variance = noise_variances[unsafe_offset=batch]
    if (
        bit > 1
        or not isfinite(noise_variance)
        or noise_variance < GPU_MIN_CODED_AWGN_NOISE_VARIANCE
        or noise_variance > GPU_MAX_CODED_AWGN_NOISE_VARIANCE
    ):
        return
    var seed = seeds[unsafe_offset=batch]
    var counter = UInt64(variable)
    var u1 = _ber_uniform_open(seed, counter, UInt64(11))
    var u2 = _ber_uniform_open(seed, counter, UInt64(12))
    var standard_normal = (
        sqrt(Float32(-2.0) * log(u1)) * cos(_TWO_PI_F32 * u2)
    )
    var transmitted = Float32(1.0) if bit == 0 else Float32(-1.0)
    var received = transmitted + sqrt(noise_variance) * standard_normal
    output_llrs[unsafe_offset=work_item] = (
        Float32(2.0) * received / noise_variance
    )


def qam_awgn_ber_sweep_kernel(
    esn0_db_values: Pointer[Float32, ImmutAnyOrigin],
    seeds: Pointer[UInt64, ImmutAnyOrigin],
    received_iq: Pointer[Float32, MutAnyOrigin],
    output_llrs: Pointer[Float32, MutAnyOrigin],
    output_bit_errors: Pointer[Int32, MutAnyOrigin],
    bits_per_symbol_dev: Int32,
    symbols_per_case_dev: Int32,
    esn0_count_dev: Int32,
    seed_count_dev: Int32,
    total_symbol_count_dev: Int32,
):
    """Run one deterministic QAM/AWGN Monte-Carlo symbol per GPU work item.

    The case layout is ``[seed][Es/N0][symbol]``.  Within one seed, all Es/N0
    cases reuse the same source bits and normalized Gaussian sample (common
    random numbers), then scale that sample by the case noise variance.  This
    makes SNR trends less noisy and makes every output reproducible regardless
    of launch geometry.  Outputs retain received IQ, max-log soft LLRs and a
    per-symbol error count so callers can compare checkpoints and aggregate
    BER without nondeterministic atomics.
    """
    var work_item = global_idx.x
    var bits_per_symbol = Int(bits_per_symbol_dev)
    var symbols_per_case = Int(symbols_per_case_dev)
    var esn0_count = Int(esn0_count_dev)
    var seed_count = Int(seed_count_dev)
    var total_symbol_count = Int(total_symbol_count_dev)
    if work_item >= total_symbol_count:
        return

    var case_index = work_item // symbols_per_case
    var symbol_in_case = work_item % symbols_per_case
    var seed_index = case_index // esn0_count
    var esn0_index = case_index % esn0_count
    if seed_index >= seed_count:
        return

    var seed = seeds[unsafe_offset=seed_index]
    var counter = UInt64(symbol_in_case)
    var source_word = _ber_counter_word(seed, counter, UInt64(0))
    var bit_i_sign = Int32(source_word & UInt64(1))
    var bit_i_magnitude = Int32((source_word >> 1) & UInt64(1))
    var bit_q_sign = Int32((source_word >> 2) & UInt64(1))
    var bit_q_magnitude = Int32((source_word >> 3) & UInt64(1))

    var transmitted_re: Float32
    var transmitted_im: Float32
    if bits_per_symbol == 2:
        transmitted_re = _QPSK_SCALE if bit_i_sign == 0 else -_QPSK_SCALE
        transmitted_im = _QPSK_SCALE if bit_i_magnitude == 0 else -_QPSK_SCALE
    else:
        var i_magnitude = (
            Float32(3.0) * _QAM16_SCALE
            if bit_i_magnitude == 0
            else _QAM16_SCALE
        )
        var q_magnitude = (
            Float32(3.0) * _QAM16_SCALE
            if bit_q_magnitude == 0
            else _QAM16_SCALE
        )
        transmitted_re = i_magnitude if bit_i_sign == 0 else -i_magnitude
        transmitted_im = q_magnitude if bit_q_sign == 0 else -q_magnitude

    var u1 = _ber_uniform_open(seed, counter, UInt64(1))
    var u2 = _ber_uniform_open(seed, counter, UInt64(2))
    var esn0_db = esn0_db_values[unsafe_offset=esn0_index]
    var noise_variance = exp(Float32(-0.2302585092994045684) * esn0_db)
    var radius = (
        sqrt(noise_variance * Float32(0.5))
        * sqrt(Float32(-2.0) * log(u1))
    )
    var angle = _TWO_PI_F32 * u2
    var received_re = transmitted_re + radius * cos(angle)
    var received_im = transmitted_im + radius * sin(angle)
    var iq_index = 2 * work_item
    received_iq[unsafe_offset=iq_index] = received_re
    received_iq[unsafe_offset=iq_index + 1] = received_im

    var errors = Int32(0)
    if bits_per_symbol == 2:
        var llr_re = (
            Float32(4.0) * _QPSK_SCALE * received_re / noise_variance
        )
        var llr_im = (
            Float32(4.0) * _QPSK_SCALE * received_im / noise_variance
        )
        var llr_index = 2 * work_item
        output_llrs[unsafe_offset=llr_index] = llr_re
        output_llrs[unsafe_offset=llr_index + 1] = llr_im
        var hard_re = Int32(0) if llr_re >= 0.0 else Int32(1)
        var hard_im = Int32(0) if llr_im >= 0.0 else Int32(1)
        if hard_re != bit_i_sign:
            errors += 1
        if hard_im != bit_i_magnitude:
            errors += 1
    else:
        var inner = _QAM16_SCALE
        var outer = Float32(3.0) * _QAM16_SCALE
        for component in range(2):
            var value = received_re if component == 0 else received_im
            var source_sign = bit_i_sign if component == 0 else bit_q_sign
            var source_magnitude = (
                bit_i_magnitude if component == 0 else bit_q_magnitude
            )
            var d_negative_outer = _squared_distance(value, -outer)
            var d_negative_inner = _squared_distance(value, -inner)
            var d_positive_inner = _squared_distance(value, inner)
            var d_positive_outer = _squared_distance(value, outer)
            var sign_llr = (
                min(d_negative_inner, d_negative_outer)
                - min(d_positive_inner, d_positive_outer)
            ) / noise_variance
            var magnitude_llr = (
                min(d_negative_inner, d_positive_inner)
                - min(d_negative_outer, d_positive_outer)
            ) / noise_variance
            var llr_index = 4 * work_item + 2 * component
            output_llrs[unsafe_offset=llr_index] = sign_llr
            output_llrs[unsafe_offset=llr_index + 1] = magnitude_llr
            var hard_sign = Int32(0) if sign_llr >= 0.0 else Int32(1)
            var hard_magnitude = (
                Int32(0) if magnitude_llr >= 0.0 else Int32(1)
            )
            if hard_sign != source_sign:
                errors += 1
            if hard_magnitude != source_magnitude:
                errors += 1
    output_bit_errors[unsafe_offset=work_item] = errors
