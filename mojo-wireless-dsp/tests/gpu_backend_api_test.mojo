from std.testing import assert_equal, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.backend.gpu import (
    GPU_DEFAULT_BLOCK_SIZE,
    GPU_MAX_THREADS_PER_BLOCK,
    GPU_MAX_RUNTIME_LENGTH,
    GPU_MIN_ESN0_DB,
    GPU_MAX_ESN0_DB,
    GPU_MIN_CODED_AWGN_NOISE_VARIANCE,
    GPU_MAX_CODED_AWGN_NOISE_VARIANCE,
    gpu_grid_size,
    validate_batched_fft_config,
    validate_complex_channel_config,
    validate_mimo_2x2_config,
    validate_complex_correlation_config,
    validate_ldpc_check_node_config,
    validate_batched_sparse_ldpc_min_sum_decode_config,
    validate_coded_bpsk_awgn_llr_config,
    validate_soft_llr_config,
    validate_qam_awgn_ber_sweep_config,
    batched_fft_radix2_kernel,
    batched_ifft_radix2_kernel,
    complex_channel_kernel,
    mimo_2x2_matvec_kernel,
    complex_correlation_kernel,
    ldpc_check_node_kernel,
    batched_sparse_ldpc_min_sum_decode_kernel,
    coded_bpsk_awgn_llr_kernel,
    qpsk_soft_llr_kernel,
    qam16_soft_llr_kernel,
    qam_awgn_ber_sweep_kernel,
)


def _validate_sparse_ldpc_fixture[
    llr_origin: Origin,
    row_origin: Origin,
    column_origin: Origin,
](
    llrs: Pointer[Float32, llr_origin],
    row_offsets: Pointer[Int32, row_origin],
    columns: Pointer[Int32, column_origin],
    *,
    channel_llr_count: Int = 18,
    row_offset_count: Int = 5,
    column_count: Int = 12,
    hard_bit_count: Int = 18,
    iterations_count: Int = 3,
    converged_count: Int = 3,
    syndrome_weight_count: Int = 3,
    variable_to_check_workspace_count: Int = 36,
    check_to_variable_workspace_count: Int = 36,
    posterior_workspace_count: Int = 18,
    variable_count: Int = 6,
    check_count: Int = 4,
    edge_count: Int = 12,
    batch_count: Int = 3,
    max_iterations: Int = 8,
    normalization: Float32 = 0.8,
    offset: Float32 = 0.1,
    clip: Float32 = 20.0,
) raises -> Int:
    return validate_batched_sparse_ldpc_min_sum_decode_config(
        llrs,
        row_offsets,
        columns,
        channel_llr_count,
        row_offset_count,
        column_count,
        hard_bit_count,
        iterations_count,
        converged_count,
        syndrome_weight_count,
        variable_to_check_workspace_count,
        check_to_variable_workspace_count,
        posterior_workspace_count,
        variable_count,
        check_count,
        edge_count,
        batch_count,
        max_iterations,
        normalization,
        offset,
        clip,
    )


def test_grid_size_and_launch_bounds() raises:
    assert_equal(GPU_DEFAULT_BLOCK_SIZE, 256)
    assert_equal(GPU_MAX_THREADS_PER_BLOCK, 1024)
    assert_equal(GPU_MAX_RUNTIME_LENGTH, 2147483647)
    assert_equal(gpu_grid_size(0), 0)
    assert_equal(gpu_grid_size(1), 1)
    assert_equal(gpu_grid_size(256), 1)
    assert_equal(gpu_grid_size(257), 2)
    assert_equal(gpu_grid_size(2049, 1024), 3)
    with assert_raises():
        _ = gpu_grid_size(-1)
    with assert_raises():
        _ = gpu_grid_size(1, 0)
    with assert_raises():
        _ = gpu_grid_size(1, 1025)


def test_fft_configuration_requires_power_of_two_and_full_buffers() raises:
    assert_equal(validate_batched_fft_config(1, 1, 2, 2), 1)
    assert_equal(validate_batched_fft_config(64, 3, 384, 384), 3)
    with assert_raises():
        _ = validate_batched_fft_config(0, 1, 2, 2)
    with assert_raises():
        _ = validate_batched_fft_config(12, 1, 24, 24)
    with assert_raises():
        _ = validate_batched_fft_config(8, 0, 16, 16)
    with assert_raises():
        _ = validate_batched_fft_config(8, 2, 31, 32)
    with assert_raises():
        _ = validate_batched_fft_config(8, 2, 32, 31)
    with assert_raises():
        _ = validate_batched_fft_config(1 << 30, 2, 0, 0)


def test_channel_and_mimo_configuration_boundaries() raises:
    assert_equal(validate_complex_channel_config(7, 14, 14, 14, 14), 7)
    with assert_raises():
        _ = validate_complex_channel_config(0, 0, 0, 0, 0)
    with assert_raises():
        _ = validate_complex_channel_config(7, 14, 13, 14, 14)
    assert_equal(validate_mimo_2x2_config(3, 12, 8, 12), 6)
    with assert_raises():
        _ = validate_mimo_2x2_config(0, 0, 8, 0)
    with assert_raises():
        _ = validate_mimo_2x2_config(2, 8, 7, 8)
    with assert_raises():
        _ = validate_mimo_2x2_config(2, 7, 8, 8)


def test_correlation_configuration_enforces_valid_range() raises:
    assert_equal(
        validate_complex_correlation_config(7, 3, 5, 14, 6, 10), 5
    )
    # Prefix-only correlation output is intentionally supported.
    assert_equal(
        validate_complex_correlation_config(7, 3, 2, 14, 6, 4), 2
    )
    with assert_raises():
        _ = validate_complex_correlation_config(3, 4, 1, 6, 8, 2)
    with assert_raises():
        _ = validate_complex_correlation_config(7, 3, 6, 14, 6, 12)
    with assert_raises():
        _ = validate_complex_correlation_config(7, 3, 5, 14, 5, 10)


def test_ldpc_check_node_configuration_enforces_degree_and_edges() raises:
    assert_equal(validate_ldpc_check_node_config(5, 4, 20, 20), 20)
    with assert_raises():
        _ = validate_ldpc_check_node_config(0, 4, 0, 0)
    with assert_raises():
        _ = validate_ldpc_check_node_config(5, 1, 5, 5)
    with assert_raises():
        _ = validate_ldpc_check_node_config(5, 4, 19, 20)
    with assert_raises():
        _ = validate_ldpc_check_node_config(5, 4, 20, 19)


def test_batched_sparse_ldpc_decoder_configuration_and_csr_edges() raises:
    var row_offsets: List[Int32] = [0, 3, 6, 9, 12]
    var columns: List[Int32] = [
        0, 1, 3,
        1, 2, 4,
        2, 3, 5,
        0, 4, 5,
    ]
    var llrs = List[Float32](length=18, fill=Float32(2.0))
    assert_equal(
        _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
        ),
        3,
    )

    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            variable_count=0,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            max_iterations=0,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            normalization=nan[DType.float32](),
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            normalization=inf[DType.float32](),
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            normalization=0.0,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            normalization=1.01,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            offset=-0.01,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            offset=nan[DType.float32](),
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            offset=inf[DType.float32](),
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            clip=inf[DType.float32](),
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            clip=nan[DType.float32](),
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            clip=0.0,
        )

    var saved = row_offsets[0]
    row_offsets[0] = 1
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
        )
    row_offsets[0] = saved
    saved = row_offsets[1]
    row_offsets[1] = 1
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
        )
    row_offsets[1] = saved
    saved = row_offsets[2]
    row_offsets[2] = 2
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
        )
    row_offsets[2] = saved
    saved = row_offsets[4]
    row_offsets[4] = 11
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
        )
    row_offsets[4] = saved

    var saved_column = columns[0]
    columns[0] = -1
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
        )
    columns[0] = 6
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
        )
    columns[0] = columns[1]
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
        )
    columns[0] = saved_column

    llrs[7] = nan[DType.float32]()
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
        )
    llrs[7] = 2.0
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            channel_llr_count=17,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            row_offset_count=4,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            column_count=11,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            hard_bit_count=17,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            iterations_count=2,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            converged_count=2,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            syndrome_weight_count=2,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            variable_to_check_workspace_count=35,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            check_to_variable_workspace_count=35,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            posterior_workspace_count=17,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            batch_count=GPU_MAX_RUNTIME_LENGTH,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            hard_bit_count=GPU_MAX_RUNTIME_LENGTH + 1,
        )
    with assert_raises():
        _ = _validate_sparse_ldpc_fixture(
            llrs.unsafe_ptr(),
            row_offsets.unsafe_ptr(),
            columns.unsafe_ptr(),
            clip=Float32(3.0e38),
        )


def test_coded_bpsk_awgn_llr_configuration_and_numeric_edges() raises:
    assert_equal(GPU_MIN_CODED_AWGN_NOISE_VARIANCE, Float32(1.0e-8))
    assert_equal(GPU_MAX_CODED_AWGN_NOISE_VARIANCE, Float32(1.0e8))
    var bits: List[UInt8] = [
        0, 0, 0, 0, 0, 0,
        0, 1, 1, 1, 0, 0,
        1, 1, 0, 0, 1, 0,
    ]
    var noise_variances: List[Float32] = [2.0, 0.5, 0.1]
    var seeds: List[UInt64] = [
        UInt64(0), UInt64(1), UInt64(0xFFFFFFFFFFFFFFFF)
    ]
    assert_equal(
        validate_coded_bpsk_awgn_llr_config(
            bits.unsafe_ptr(),
            noise_variances.unsafe_ptr(),
            seeds.unsafe_ptr(),
            18,
            3,
            3,
            18,
            6,
            3,
        ),
        18,
    )
    var edge_bits: List[UInt8] = [0, 1]
    var edge_noise: List[Float32] = [
        GPU_MIN_CODED_AWGN_NOISE_VARIANCE,
        GPU_MAX_CODED_AWGN_NOISE_VARIANCE,
    ]
    var edge_seeds: List[UInt64] = [
        UInt64(0), UInt64(0xFFFFFFFFFFFFFFFF)
    ]
    assert_equal(
        validate_coded_bpsk_awgn_llr_config(
            edge_bits.unsafe_ptr(),
            edge_noise.unsafe_ptr(),
            edge_seeds.unsafe_ptr(),
            2,
            2,
            2,
            2,
            1,
            2,
        ),
        2,
    )

    bits[5] = 2
    with assert_raises():
        _ = validate_coded_bpsk_awgn_llr_config(
            bits.unsafe_ptr(),
            noise_variances.unsafe_ptr(),
            seeds.unsafe_ptr(),
            18,
            3,
            3,
            18,
            6,
            3,
        )
    bits[5] = 0
    var invalid_noise: List[Float32] = [
        nan[DType.float32](),
        inf[DType.float32](),
        1.0e-9,
        1.0e9,
    ]
    var one_bit: List[UInt8] = [0]
    var one_seed: List[UInt64] = [UInt64(7)]
    var one_noise = List[Float32](length=1, fill=Float32(1.0))
    for invalid in invalid_noise:
        one_noise[0] = invalid
        with assert_raises():
            _ = validate_coded_bpsk_awgn_llr_config(
                one_bit.unsafe_ptr(),
                one_noise.unsafe_ptr(),
                one_seed.unsafe_ptr(),
                1,
                1,
                1,
                1,
                1,
                1,
            )
    one_noise[0] = 1.0

    with assert_raises():
        _ = validate_coded_bpsk_awgn_llr_config(
            bits.unsafe_ptr(),
            noise_variances.unsafe_ptr(),
            seeds.unsafe_ptr(),
            17,
            3,
            3,
            18,
            6,
            3,
        )
    with assert_raises():
        _ = validate_coded_bpsk_awgn_llr_config(
            bits.unsafe_ptr(),
            noise_variances.unsafe_ptr(),
            seeds.unsafe_ptr(),
            18,
            2,
            3,
            18,
            6,
            3,
        )
    with assert_raises():
        _ = validate_coded_bpsk_awgn_llr_config(
            bits.unsafe_ptr(),
            noise_variances.unsafe_ptr(),
            seeds.unsafe_ptr(),
            18,
            3,
            2,
            18,
            6,
            3,
        )
    with assert_raises():
        _ = validate_coded_bpsk_awgn_llr_config(
            bits.unsafe_ptr(),
            noise_variances.unsafe_ptr(),
            seeds.unsafe_ptr(),
            18,
            3,
            3,
            17,
            6,
            3,
        )
    with assert_raises():
        _ = validate_coded_bpsk_awgn_llr_config(
            bits.unsafe_ptr(),
            noise_variances.unsafe_ptr(),
            seeds.unsafe_ptr(),
            18,
            3,
            3,
            18,
            0,
            3,
        )
    with assert_raises():
        _ = validate_coded_bpsk_awgn_llr_config(
            bits.unsafe_ptr(),
            noise_variances.unsafe_ptr(),
            seeds.unsafe_ptr(),
            18,
            3,
            3,
            18,
            6,
            GPU_MAX_RUNTIME_LENGTH,
        )
    with assert_raises():
        _ = validate_coded_bpsk_awgn_llr_config(
            one_bit.unsafe_ptr(),
            one_noise.unsafe_ptr(),
            one_seed.unsafe_ptr(),
            1,
            1,
            1,
            GPU_MAX_RUNTIME_LENGTH + 1,
            1,
            1,
        )


def test_soft_llr_configuration_covers_qpsk_and_qam16() raises:
    assert_equal(validate_soft_llr_config(2, 9, 0.25, 18, 18), 9)
    assert_equal(validate_soft_llr_config(4, 9, 0.25, 18, 36), 9)
    with assert_raises():
        _ = validate_soft_llr_config(6, 9, 0.25, 18, 54)
    with assert_raises():
        _ = validate_soft_llr_config(2, 0, 0.25, 0, 0)
    with assert_raises():
        _ = validate_soft_llr_config(2, 9, 0.0, 18, 18)
    with assert_raises():
        _ = validate_soft_llr_config(4, 9, 0.25, 17, 36)
    with assert_raises():
        _ = validate_soft_llr_config(4, 9, 0.25, 18, 35)
    with assert_raises():
        _ = validate_soft_llr_config(
            2, 9, inf[DType.float32](), 18, 18
        )
    with assert_raises():
        _ = validate_soft_llr_config(
            2, 9, nan[DType.float32](), 18, 18
        )


def test_qam_awgn_ber_sweep_configuration_and_numeric_boundaries() raises:
    assert_equal(GPU_MIN_ESN0_DB, Float32(-100.0))
    assert_equal(GPU_MAX_ESN0_DB, Float32(100.0))
    var esn0_values: List[Float32] = [-4.0, 0.0, 8.0]
    assert_equal(
        validate_qam_awgn_ber_sweep_config(
            4,
            5,
            esn0_values.unsafe_ptr(),
            3,
            2,
            3,
            2,
            60,
            120,
            30,
        ),
        30,
    )
    var endpoints: List[Float32] = [GPU_MIN_ESN0_DB, GPU_MAX_ESN0_DB]
    assert_equal(
        validate_qam_awgn_ber_sweep_config(
            2,
            1,
            endpoints.unsafe_ptr(),
            2,
            1,
            2,
            1,
            4,
            4,
            2,
        ),
        2,
    )

    with assert_raises():
        _ = validate_qam_awgn_ber_sweep_config(
            6, 5, esn0_values.unsafe_ptr(), 3, 2, 3, 2, 60, 180, 30
        )
    with assert_raises():
        _ = validate_qam_awgn_ber_sweep_config(
            2, 0, esn0_values.unsafe_ptr(), 3, 2, 3, 2, 0, 0, 0
        )
    with assert_raises():
        _ = validate_qam_awgn_ber_sweep_config(
            2, 5, esn0_values.unsafe_ptr(), 3, 0, 3, 0, 0, 0, 0
        )
    with assert_raises():
        _ = validate_qam_awgn_ber_sweep_config(
            2, 5, esn0_values.unsafe_ptr(), 3, 2, 2, 2, 60, 60, 30
        )
    with assert_raises():
        _ = validate_qam_awgn_ber_sweep_config(
            2, 5, esn0_values.unsafe_ptr(), 3, 2, 3, 1, 60, 60, 30
        )
    with assert_raises():
        _ = validate_qam_awgn_ber_sweep_config(
            2, 5, esn0_values.unsafe_ptr(), 3, 2, 3, 2, 59, 60, 30
        )
    with assert_raises():
        _ = validate_qam_awgn_ber_sweep_config(
            4, 5, esn0_values.unsafe_ptr(), 3, 2, 3, 2, 60, 119, 30
        )
    with assert_raises():
        _ = validate_qam_awgn_ber_sweep_config(
            2, 5, esn0_values.unsafe_ptr(), 3, 2, 3, 2, 60, 60, 29
        )

    var invalid_values: List[Float32] = [
        nan[DType.float32](),
        inf[DType.float32](),
        -101.0,
        101.0,
    ]
    var invalid_single = List[Float32](length=1, fill=Float32(0.0))
    for index in range(len(invalid_values)):
        invalid_single[0] = invalid_values[index]
        with assert_raises():
            _ = validate_qam_awgn_ber_sweep_config(
                2,
                1,
                invalid_single.unsafe_ptr(),
                1,
                1,
                1,
                1,
                2,
                2,
                1,
            )
    with assert_raises():
        _ = validate_qam_awgn_ber_sweep_config(
            4,
            GPU_MAX_RUNTIME_LENGTH,
            esn0_values.unsafe_ptr(),
            3,
            2,
            3,
            2,
            0,
            0,
            0,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
