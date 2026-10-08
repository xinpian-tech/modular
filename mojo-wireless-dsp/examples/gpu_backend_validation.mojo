"""Capability-gated differential validation for the optional GPU backend.

Build with the wireless DSP, MAX, and kernel include roots.  On a machine
without a compatible accelerator this executable still proves that the host
integration parses and reports an explicit skip.  With an accelerator it
launches every public Phase 6 kernel and compares the result with an
independent scalar CPU oracle.
"""

from std.collections import Span
from std.math import cos, exp, isfinite, log, sin, sqrt
from std.sys import has_accelerator
from std.time import global_perf_counter_ns
from max.gpu.host import DeviceContext
from wireless_dsp.fec import ldpc_decode_min_sum
from wireless_dsp.testing import simulate_qam_awgn_sweep
from wireless_dsp.backend.gpu import (
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


comptime _BLOCK_SIZE = 64
comptime _TWO_PI = 6.283185307179586476925286766559
comptime _TWO_PI_F32 = Float32(6.2831853071795864769)
comptime _QPSK_SCALE = Float32(0.7071067811865475244)
comptime _QAM16_SCALE = Float32(0.3162277660168379332)


struct _BerOracleSample:
    var received_re: Float32
    var received_im: Float32
    var bit_i_sign: Int32
    var bit_i_magnitude: Int32
    var bit_q_sign: Int32
    var bit_q_magnitude: Int32

    def __init__(
        out self,
        received_re: Float32,
        received_im: Float32,
        bit_i_sign: Int32,
        bit_i_magnitude: Int32,
        bit_q_sign: Int32,
        bit_q_magnitude: Int32,
    ):
        self.received_re = received_re
        self.received_im = received_im
        self.bit_i_sign = bit_i_sign
        self.bit_i_magnitude = bit_i_magnitude
        self.bit_q_sign = bit_q_sign
        self.bit_q_magnitude = bit_q_magnitude


struct _CodedLDPCOracle(Movable):
    var llrs: List[Float32]
    var decoded_bits: List[UInt8]
    var iterations: List[Int32]
    var converged: List[UInt8]
    var syndrome_weights: List[Int32]
    var block_errors_by_snr: List[Int]
    var llr_checksum: Int64
    var result_checksum: Int64

    def __init__(
        out self,
        var llrs: List[Float32],
        var decoded_bits: List[UInt8],
        var iterations: List[Int32],
        var converged: List[UInt8],
        var syndrome_weights: List[Int32],
        var block_errors_by_snr: List[Int],
        llr_checksum: Int64,
        result_checksum: Int64,
    ):
        self.llrs = llrs^
        self.decoded_bits = decoded_bits^
        self.iterations = iterations^
        self.converged = converged^
        self.syndrome_weights = syndrome_weights^
        self.block_errors_by_snr = block_errors_by_snr^
        self.llr_checksum = llr_checksum
        self.result_checksum = result_checksum


def _require_close(
    actual: Float32, expected: Float32, tolerance: Float32, label: String
) raises:
    if abs(actual - expected) > tolerance:
        raise Error(
            label
            + ": expected "
            + String(expected)
            + ", observed "
            + String(actual)
        )


def _require_close_scaled(
    actual: Float32,
    expected: Float32,
    absolute_tolerance: Float32,
    relative_tolerance: Float32,
    label: String,
) raises:
    var limit = absolute_tolerance + relative_tolerance * abs(expected)
    if not isfinite(actual) or abs(actual - expected) > limit:
        raise Error(
            label
            + ": expected "
            + String(expected)
            + ", observed "
            + String(actual)
            + ", tolerance "
            + String(limit)
        )


def _oracle_counter_word(
    seed: UInt64, counter: UInt64, stream: UInt64
) -> UInt64:
    var value = (
        seed
        + UInt64(0x9E3779B97F4A7C15) * (counter + UInt64(1))
        + UInt64(0xD1B54A32D192ED03) * (stream + UInt64(1))
    )
    value = (value ^ (value >> 30)) * UInt64(0xBF58476D1CE4E5B9)
    value = (value ^ (value >> 27)) * UInt64(0x94D049BB133111EB)
    return value ^ (value >> 31)


def _oracle_uniform_open(
    seed: UInt64, counter: UInt64, stream: UInt64
) -> Float32:
    var word = _oracle_counter_word(seed, counter, stream)
    return (
        Float32(UInt32(word >> 40)) + Float32(0.5)
    ) * Float32(5.9604644775390625e-8)


def _oracle_ber_sample(
    seed: UInt64,
    symbol: Int,
    bits_per_symbol: Int,
    esn0_db: Float32,
) -> _BerOracleSample:
    """Scalar CPU realization of the documented counter-RNG channel spec."""
    var counter = UInt64(symbol)
    var source_word = _oracle_counter_word(seed, counter, UInt64(0))
    var bit_i_sign = Int32(source_word & UInt64(1))
    var bit_i_magnitude = Int32((source_word >> 1) & UInt64(1))
    var bit_q_sign = Int32((source_word >> 2) & UInt64(1))
    var bit_q_magnitude = Int32((source_word >> 3) & UInt64(1))
    var transmitted_re: Float32
    var transmitted_im: Float32
    if bits_per_symbol == 2:
        transmitted_re = _QPSK_SCALE if bit_i_sign == 0 else -_QPSK_SCALE
        transmitted_im = (
            _QPSK_SCALE if bit_i_magnitude == 0 else -_QPSK_SCALE
        )
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
    var u1 = _oracle_uniform_open(seed, counter, UInt64(1))
    var u2 = _oracle_uniform_open(seed, counter, UInt64(2))
    var noise_variance = exp(Float32(-0.2302585092994045684) * esn0_db)
    var radius = (
        sqrt(noise_variance * Float32(0.5))
        * sqrt(Float32(-2.0) * log(u1))
    )
    var angle = _TWO_PI_F32 * u2
    return _BerOracleSample(
        transmitted_re + radius * cos(angle),
        transmitted_im + radius * sin(angle),
        bit_i_sign,
        bit_i_magnitude,
        bit_q_sign,
        bit_q_magnitude,
    )


def _oracle_component_llrs(
    value: Float32,
    noise_variance: Float32,
) -> Tuple[Float32, Float32]:
    # Exhaustive distance partitions are intentionally independent of the
    # branch-minimized formulas in the GPU kernel.
    var inner = _QAM16_SCALE
    var outer = Float32(3.0) * inner
    var sign_zero = Float32(3.402823466e38)
    var sign_one = Float32(3.402823466e38)
    var magnitude_zero = Float32(3.402823466e38)
    var magnitude_one = Float32(3.402823466e38)
    for level_index in range(4):
        var level: Float32
        var sign_bit: Int
        var magnitude_bit: Int
        if level_index == 0:
            level = -outer
            sign_bit = 1
            magnitude_bit = 0
        elif level_index == 1:
            level = -inner
            sign_bit = 1
            magnitude_bit = 1
        elif level_index == 2:
            level = inner
            sign_bit = 0
            magnitude_bit = 1
        else:
            level = outer
            sign_bit = 0
            magnitude_bit = 0
        var difference = value - level
        var distance = difference * difference
        if sign_bit == 0:
            sign_zero = min(sign_zero, distance)
        else:
            sign_one = min(sign_one, distance)
        if magnitude_bit == 0:
            magnitude_zero = min(magnitude_zero, distance)
        else:
            magnitude_one = min(magnitude_one, distance)
    return (
        (sign_one - sign_zero) / noise_variance,
        (magnitude_one - magnitude_zero) / noise_variance,
    )


def _oracle_sample_errors(
    sample: _BerOracleSample,
    bits_per_symbol: Int,
    noise_variance: Float32,
) -> Int:
    var errors = 0
    if bits_per_symbol == 2:
        var hard_re = Int32(0) if sample.received_re >= 0.0 else Int32(1)
        var hard_im = Int32(0) if sample.received_im >= 0.0 else Int32(1)
        if hard_re != sample.bit_i_sign:
            errors += 1
        if hard_im != sample.bit_i_magnitude:
            errors += 1
        return errors
    for component in range(2):
        var value = sample.received_re if component == 0 else sample.received_im
        var source_sign = (
            sample.bit_i_sign if component == 0 else sample.bit_q_sign
        )
        var source_magnitude = (
            sample.bit_i_magnitude
            if component == 0
            else sample.bit_q_magnitude
        )
        var sign_llr, magnitude_llr = _oracle_component_llrs(
            value, noise_variance
        )
        var hard_sign = Int32(0) if sign_llr >= 0.0 else Int32(1)
        var hard_magnitude = Int32(0) if magnitude_llr >= 0.0 else Int32(1)
        if hard_sign != source_sign:
            errors += 1
        if hard_magnitude != source_magnitude:
            errors += 1
    return errors


def _validate_ber_oracle_contract() raises:
    """Run a platform-independent seeded sweep before the GPU capability gate."""
    comptime symbols_per_case = 4096
    var esn0_values: List[Float32] = [-2.0, 2.0, 6.0, 10.0]
    var seeds: List[UInt64] = [
        UInt64(0),
        UInt64(0x0123456789ABCDEF),
        UInt64(0xFEDCBA9876543210),
    ]
    var expected_qpsk: List[Int] = [
        1777, 855, 172, 6,
        1659, 841, 173, 7,
        1725, 841, 189, 5,
    ]
    var expected_qam16: List[Int] = [
        5557, 3902, 2344, 974,
        5443, 3846, 2296, 985,
        5451, 3919, 2287, 936,
    ]
    for modulation in range(2):
        var bits_per_symbol = 2 if modulation == 0 else 4
        var case_index = 0
        for seed in seeds:
            var previous_errors = symbols_per_case * bits_per_symbol + 1
            for esn0_db in esn0_values:
                var noise_variance = exp(
                    Float32(-0.2302585092994045684) * esn0_db
                )
                var errors = 0
                for symbol in range(symbols_per_case):
                    var sample = _oracle_ber_sample(
                        seed, symbol, bits_per_symbol, esn0_db
                    )
                    errors += _oracle_sample_errors(
                        sample, bits_per_symbol, noise_variance
                    )
                var expected_errors = (
                    expected_qpsk[case_index]
                    if modulation == 0
                    else expected_qam16[case_index]
                )
                if errors != expected_errors:
                    raise Error(
                        "seeded QAM/AWGN CPU oracle checksum changed for case "
                        + String(case_index)
                        + ": expected "
                        + String(expected_errors)
                        + ", observed "
                        + String(errors)
                    )
                if errors > previous_errors:
                    raise Error("seeded QAM/AWGN oracle BER is not monotonic")
                previous_errors = errors
                case_index += 1

    # Compare the Float32 counter-based sweep against the independent public
    # Float64 link oracle.  The generators intentionally differ, so this is a
    # statistical BER comparison rather than a sample-by-sample equality.
    var modulation_orders: List[Int] = [2, 4]
    var noise_variances = List[Float64](capacity=len(esn0_values))
    for esn0_db in esn0_values:
        noise_variances.append(
            Float64(exp(Float32(-0.2302585092994045684) * esn0_db))
        )
    var reference_points = simulate_qam_awgn_sweep(
        Span(modulation_orders),
        Span(noise_variances),
        Span(seeds),
        symbols_per_case,
    )
    for modulation in range(2):
        var bits_per_symbol = modulation_orders[modulation]
        for esn0_index in range(len(esn0_values)):
            for seed_index in range(len(seeds)):
                var case_index = seed_index * len(esn0_values) + esn0_index
                var counter_errors = (
                    expected_qpsk[case_index]
                    if modulation == 0
                    else expected_qam16[case_index]
                )
                var counter_ber = (
                    Float64(counter_errors)
                    / Float64(symbols_per_case * bits_per_symbol)
                )
                var reference_index = (
                    modulation * len(esn0_values) * len(seeds)
                    + esn0_index * len(seeds)
                    + seed_index
                )
                var reference_ber = reference_points[reference_index].result.ber
                if abs(counter_ber - reference_ber) > 0.04:
                    raise Error(
                        "Float32 GPU BER contract diverged from the independent "
                        "Float64 link oracle"
                    )
    var qpsk_checksum = 0
    var qam16_checksum = 0
    for case_index in range(len(expected_qpsk)):
        qpsk_checksum += (case_index + 1) * expected_qpsk[case_index]
        qam16_checksum += (case_index + 1) * expected_qam16[case_index]
    print(
        "Phase 6 CPU BER contract points:",
        2 * len(esn0_values) * len(seeds),
        "symbols_per_point:",
        symbols_per_case,
        "QPSK_error_checksum:",
        qpsk_checksum,
        "16QAM_error_checksum:",
        qam16_checksum,
    )


def _sparse_ldpc_rows() -> List[Int]:
    return [0, 3, 6, 9, 12]


def _sparse_ldpc_columns() -> List[Int]:
    return [
        0, 1, 3,
        1, 2, 4,
        2, 3, 5,
        0, 4, 5,
    ]


def _sparse_ldpc_llr_cases() -> List[List[Float64]]:
    return [
        [6.0, 6.0, 6.0, 6.0, 6.0, 6.0],
        [6.0, -0.5, 6.0, 6.0, -0.25, 6.0],
        [6.0, -6.0, -6.0, -6.0, 6.0, 6.0],
        [0.2, -0.1, 0.05, -0.02, 0.01, -0.03],
        [-0.1, 0.2, -0.3, 0.4, -0.5, 0.6],
    ]


def _sparse_syndrome_weight(
    bits: Span[UInt8, ...],
    row_offsets: Span[Int, ...],
    columns: Span[Int, ...],
) -> Int:
    var weight = 0
    for row in range(len(row_offsets) - 1):
        var parity = UInt8(0)
        for edge in range(row_offsets[row], row_offsets[row + 1]):
            parity ^= bits[columns[edge]]
        if parity != 0:
            weight += 1
    return weight


def _validate_sparse_ldpc_cpu_contract() raises:
    """Validate nontrivial correction and failure syndromes before GPU gating."""
    var rows = _sparse_ldpc_rows()
    var columns = _sparse_ldpc_columns()
    var cases = _sparse_ldpc_llr_cases()
    var expected_bits: List[UInt8] = [
        0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0,
        0, 1, 1, 1, 0, 0,
        0, 1, 0, 1, 0, 1,
        1, 0, 1, 0, 1, 0,
    ]
    var expected_iterations: List[Int] = [1, 1, 1, 8, 8]
    var expected_converged: List[Bool] = [True, True, True, False, False]
    var expected_syndrome_weights: List[Int] = [0, 0, 0, 2, 2]
    var checksum = 0
    for case_index in range(len(cases)):
        var decoded = ldpc_decode_min_sum(
            Span(cases[case_index]),
            Span(rows),
            Span(columns),
            max_iterations=8,
            normalization=0.8,
            offset=0.1,
            clip=20.0,
        )
        if decoded.iterations != expected_iterations[case_index]:
            raise Error("sparse LDPC CPU oracle iteration checksum changed")
        if decoded.converged != expected_converged[case_index]:
            raise Error("sparse LDPC CPU oracle convergence checksum changed")
        for variable in range(6):
            var expected = expected_bits[6 * case_index + variable]
            if decoded.bits[variable] != expected:
                raise Error("sparse LDPC CPU oracle hard bits changed")
            checksum += (
                (case_index + 1)
                * (variable + 1)
                * Int(decoded.bits[variable])
            )
        var syndrome_weight = _sparse_syndrome_weight(
            Span(decoded.bits), Span(rows), Span(columns)
        )
        if syndrome_weight != expected_syndrome_weights[case_index]:
            raise Error("sparse LDPC CPU oracle syndrome weight changed")
        checksum += (case_index + 1) * (
            17 * decoded.iterations + 31 * syndrome_weight
        )
    # Case one starts with two negative hard decisions and exercises genuine
    # graph-based correction to the all-zero codeword rather than passthrough.
    if cases[1][1] >= 0.0 or cases[1][4] >= 0.0:
        raise Error("sparse LDPC correction oracle lost its injected errors")
    print(
        "Phase 6 sparse LDPC CPU oracle codewords:",
        len(cases),
        "checksum:",
        checksum,
    )


def _coded_ldpc_codewords() -> List[UInt8]:
    # The eight codewords of the nontrivial 6-variable/4-check CSR graph.
    return [
        0, 0, 0, 0, 0, 0,
        0, 1, 1, 1, 0, 0,
        1, 1, 0, 0, 1, 0,
        1, 0, 1, 1, 1, 0,
        1, 1, 1, 0, 0, 1,
        1, 0, 0, 1, 0, 1,
        0, 0, 1, 0, 1, 1,
        0, 1, 0, 1, 1, 1,
    ]


def _coded_ldpc_noise_variances() -> List[Float32]:
    # Descending real sigma^2 corresponds to increasing Es/N0 for BPSK.
    return [4.0, 1.0, 0.25, 0.04]


def _coded_ldpc_seed(seed_index: Int) -> UInt64:
    return (
        UInt64(0xA5A5D3C17E21B409)
        + UInt64(seed_index) * UInt64(0x9E3779B97F4A7C15)
    )


def _oracle_coded_bpsk_llr(
    bit: UInt8,
    noise_variance: Float32,
    seed: UInt64,
    variable: Int,
) -> Float32:
    var counter = UInt64(variable)
    var u1 = _oracle_uniform_open(seed, counter, UInt64(11))
    var u2 = _oracle_uniform_open(seed, counter, UInt64(12))
    var standard_normal = (
        sqrt(Float32(-2.0) * log(u1)) * cos(_TWO_PI_F32 * u2)
    )
    var transmitted = Float32(1.0) if bit == 0 else Float32(-1.0)
    var received = transmitted + sqrt(noise_variance) * standard_normal
    return Float32(2.0) * received / noise_variance


def _run_coded_ldpc_cpu_oracle() raises -> _CodedLDPCOracle:
    comptime variable_count = 6
    comptime snr_count = 4
    comptime seed_count = 64
    comptime batch_count = snr_count * seed_count
    var rows = _sparse_ldpc_rows()
    var columns = _sparse_ldpc_columns()
    var codewords = _coded_ldpc_codewords()
    var noise_variances = _coded_ldpc_noise_variances()
    var llrs = List[Float32](capacity=batch_count * variable_count)
    var decoded_bits = List[UInt8](capacity=batch_count * variable_count)
    var iterations = List[Int32](capacity=batch_count)
    var converged = List[UInt8](capacity=batch_count)
    var syndrome_weights = List[Int32](capacity=batch_count)
    var block_errors_by_snr = List[Int](length=snr_count, fill=0)
    var llr_checksum = Int64(0)
    var result_checksum = Int64(0)

    # Fixed seed-major/SNR-major layout.  The codeword and seed are constant
    # across the four SNR points, so only sigma scales the shared Gaussian.
    for seed_index in range(seed_count):
        var seed = _coded_ldpc_seed(seed_index)
        var codeword_index = seed_index % 8
        for snr_index in range(snr_count):
            var batch = seed_index * snr_count + snr_index
            var noise_variance = noise_variances[snr_index]
            var cpu_llrs = List[Float64](capacity=variable_count)
            for variable in range(variable_count):
                var bit = codewords[codeword_index * variable_count + variable]
                var llr = _oracle_coded_bpsk_llr(
                    bit, noise_variance, seed, variable
                )
                llrs.append(llr)
                cpu_llrs.append(Float64(llr))
                var flat_index = batch * variable_count + variable
                llr_checksum += (
                    Int64(flat_index + 1)
                    * Int64(Int(llr * Float32(1024.0)))
                )
            var decoded = ldpc_decode_min_sum(
                Span(cpu_llrs),
                Span(rows),
                Span(columns),
                max_iterations=8,
                normalization=Float64(Float32(0.8)),
                offset=Float64(Float32(0.1)),
                clip=20.0,
            )
            iterations.append(Int32(decoded.iterations))
            converged.append(UInt8(1) if decoded.converged else UInt8(0))
            var syndrome_weight = _sparse_syndrome_weight(
                Span(decoded.bits), Span(rows), Span(columns)
            )
            syndrome_weights.append(Int32(syndrome_weight))
            var block_error = not decoded.converged
            for variable in range(variable_count):
                var bit = decoded.bits[variable]
                decoded_bits.append(bit)
                if bit != codewords[codeword_index * variable_count + variable]:
                    block_error = True
                result_checksum += (
                    Int64(batch + 1) * Int64(variable + 1) * Int64(bit)
                )
            if block_error:
                block_errors_by_snr[snr_index] += 1
            result_checksum += Int64(batch + 1) * (
                Int64(17 * decoded.iterations + 31 * syndrome_weight)
            )
    return _CodedLDPCOracle(
        llrs^,
        decoded_bits^,
        iterations^,
        converged^,
        syndrome_weights^,
        block_errors_by_snr^,
        llr_checksum,
        result_checksum,
    )


def _validate_coded_ldpc_cpu_contract() raises:
    var first = _run_coded_ldpc_cpu_oracle()
    var second = _run_coded_ldpc_cpu_oracle()
    var expected_bler_errors: List[Int] = [24, 4, 0, 0]
    if first.llr_checksum != Int64(-577727661):
        raise Error("coded LDPC CPU LLR checksum changed")
    if first.result_checksum != Int64(1066062):
        raise Error("coded LDPC CPU decoder checksum changed")
    if (
        first.llr_checksum != second.llr_checksum
        or first.result_checksum != second.result_checksum
    ):
        raise Error("coded LDPC CPU oracle is not reproducible")
    for index in range(len(first.llrs)):
        if first.llrs[index] != second.llrs[index]:
            raise Error("coded LDPC CPU channel LLR replay changed")
        if first.decoded_bits[index] != second.decoded_bits[index]:
            raise Error("coded LDPC CPU decoded-bit replay changed")
    var converged_count = 0
    for batch in range(len(first.iterations)):
        if (
            first.iterations[batch] != second.iterations[batch]
            or first.converged[batch] != second.converged[batch]
            or first.syndrome_weights[batch] != second.syndrome_weights[batch]
        ):
            raise Error("coded LDPC CPU decoder replay changed")
        if first.converged[batch] == 1:
            converged_count += 1
    for snr_index in range(len(first.block_errors_by_snr)):
        if first.block_errors_by_snr[snr_index] != expected_bler_errors[snr_index]:
            raise Error("coded LDPC CPU BLER checksum changed")
        if (
            first.block_errors_by_snr[snr_index]
            != second.block_errors_by_snr[snr_index]
        ):
            raise Error("coded LDPC CPU BLER replay changed")
        if (
            snr_index > 0
            and first.block_errors_by_snr[snr_index]
            > first.block_errors_by_snr[snr_index - 1]
        ):
            raise Error("coded LDPC CPU BLER increased with SNR")
    if converged_count == 0 or converged_count == len(first.iterations):
        raise Error("coded LDPC oracle must cover convergence and failure")
    var codewords = _coded_ldpc_codewords()
    var all_zero = True
    var nonzero = False
    for variable in range(6):
        all_zero = all_zero and codewords[variable] == 0
        nonzero = nonzero or codewords[6 + variable] != 0
    if not all_zero or not nonzero:
        raise Error("coded LDPC oracle lost zero/nonzero codeword coverage")
    print(
        "Phase 6 coded LDPC CPU oracle batches:",
        len(first.iterations),
        "BLER_errors_by_SNR:",
        first.block_errors_by_snr,
        "llr_checksum:",
        first.llr_checksum,
        "result_checksum:",
        first.result_checksum,
    )


def _validate_fft(mut context: DeviceContext) raises:
    comptime fft_size = 8
    comptime batch_count = 2
    comptime complex_count = fft_size * batch_count
    comptime scalar_count = 2 * complex_count
    var work_items = validate_batched_fft_config(
        fft_size, batch_count, scalar_count, scalar_count
    )

    var input_host = context.enqueue_create_host_buffer[DType.float32](
        scalar_count
    )
    for batch in range(batch_count):
        for index in range(fft_size):
            var scalar_index = 2 * (batch * fft_size + index)
            input_host[scalar_index] = (
                Float32((3 * index + batch) % 7) * 0.125 - 0.375
            )
            input_host[scalar_index + 1] = (
                Float32((5 * index + 2 * batch) % 9) * 0.0625 - 0.25
            )

    var input_device = context.enqueue_create_buffer[DType.float32](scalar_count)
    var fft_device = context.enqueue_create_buffer[DType.float32](scalar_count)
    var ifft_device = context.enqueue_create_buffer[DType.float32](scalar_count)
    var fft_host = context.enqueue_create_host_buffer[DType.float32](scalar_count)
    var ifft_host = context.enqueue_create_host_buffer[DType.float32](scalar_count)
    context.enqueue_copy(dst_buf=input_device, src_buf=input_host)
    context.enqueue_function[batched_fft_radix2_kernel](
        input_device,
        fft_device,
        Int32(fft_size),
        Int32(batch_count),
        grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_function[batched_ifft_radix2_kernel](
        fft_device,
        ifft_device,
        Int32(fft_size),
        Int32(batch_count),
        grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_copy(dst_buf=fft_host, src_buf=fft_device)
    context.enqueue_copy(dst_buf=ifft_host, src_buf=ifft_device)
    context.synchronize()

    # Independent O(N^2) DFT oracle: the GPU implementation itself is an
    # iterative radix-2 FFT, so this catches its permutation/stage mistakes.
    for batch in range(batch_count):
        for frequency in range(fft_size):
            var expected_re = Float32(0.0)
            var expected_im = Float32(0.0)
            for time in range(fft_size):
                var input_index = 2 * (batch * fft_size + time)
                var angle = (
                    -_TWO_PI * Float64(frequency * time) / Float64(fft_size)
                )
                var twiddle_re = Float32(cos(angle))
                var twiddle_im = Float32(sin(angle))
                var re = input_host[input_index]
                var im = input_host[input_index + 1]
                expected_re += re * twiddle_re - im * twiddle_im
                expected_im += re * twiddle_im + im * twiddle_re
            var output_index = 2 * (batch * fft_size + frequency)
            _require_close(
                fft_host[output_index], expected_re, 2.0e-4, "GPU FFT real"
            )
            _require_close(
                fft_host[output_index + 1],
                expected_im,
                2.0e-4,
                "GPU FFT imaginary",
            )
    for index in range(scalar_count):
        _require_close(
            ifft_host[index], input_host[index], 2.0e-4, "GPU IFFT round trip"
        )


def _validate_channel(mut context: DeviceContext) raises:
    comptime complex_count = 7
    comptime scalar_count = 2 * complex_count
    var work_items = validate_complex_channel_config(
        complex_count,
        scalar_count,
        scalar_count,
        scalar_count,
        scalar_count,
    )
    var input_host = context.enqueue_create_host_buffer[DType.float32](
        scalar_count
    )
    var coefficient_host = context.enqueue_create_host_buffer[DType.float32](
        scalar_count
    )
    var noise_host = context.enqueue_create_host_buffer[DType.float32](
        scalar_count
    )
    var output_host = context.enqueue_create_host_buffer[DType.float32](
        scalar_count
    )
    for index in range(complex_count):
        input_host[2 * index] = Float32(index) * 0.25 - 0.5
        input_host[2 * index + 1] = Float32(index % 3) * 0.5 - 0.25
        coefficient_host[2 * index] = 0.5 + Float32(index) * 0.03125
        coefficient_host[2 * index + 1] = -0.25
        noise_host[2 * index] = 0.0625
        noise_host[2 * index + 1] = -0.03125
    var input_device = context.enqueue_create_buffer[DType.float32](scalar_count)
    var coefficient_device = context.enqueue_create_buffer[DType.float32](
        scalar_count
    )
    var noise_device = context.enqueue_create_buffer[DType.float32](scalar_count)
    var output_device = context.enqueue_create_buffer[DType.float32](scalar_count)
    context.enqueue_copy(dst_buf=input_device, src_buf=input_host)
    context.enqueue_copy(dst_buf=coefficient_device, src_buf=coefficient_host)
    context.enqueue_copy(dst_buf=noise_device, src_buf=noise_host)
    context.enqueue_function[complex_channel_kernel](
        input_device,
        coefficient_device,
        noise_device,
        output_device,
        Int32(complex_count),
        grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_copy(dst_buf=output_host, src_buf=output_device)
    context.synchronize()
    for index in range(complex_count):
        var re = input_host[2 * index]
        var im = input_host[2 * index + 1]
        var hr = coefficient_host[2 * index]
        var hi = coefficient_host[2 * index + 1]
        _require_close(
            output_host[2 * index],
            re * hr - im * hi + noise_host[2 * index],
            1.0e-6,
            "GPU channel real",
        )
        _require_close(
            output_host[2 * index + 1],
            re * hi + im * hr + noise_host[2 * index + 1],
            1.0e-6,
            "GPU channel imaginary",
        )


def _validate_mimo(mut context: DeviceContext) raises:
    comptime batch_count = 3
    comptime vector_scalar_count = 4 * batch_count
    comptime matrix_scalar_count = 8
    var work_items = validate_mimo_2x2_config(
        batch_count,
        vector_scalar_count,
        matrix_scalar_count,
        vector_scalar_count,
    )
    var input_host = context.enqueue_create_host_buffer[DType.float32](
        vector_scalar_count
    )
    var matrix_host = context.enqueue_create_host_buffer[DType.float32](
        matrix_scalar_count
    )
    var output_host = context.enqueue_create_host_buffer[DType.float32](
        vector_scalar_count
    )
    for index in range(vector_scalar_count):
        input_host[index] = Float32((index * 3) % 11) * 0.125 - 0.5
    var matrix_values: List[Float32] = [
        0.75,
        0.125,
        -0.25,
        0.5,
        0.375,
        -0.25,
        1.0,
        0.0,
    ]
    for index in range(matrix_scalar_count):
        matrix_host[index] = matrix_values[index]
    var input_device = context.enqueue_create_buffer[DType.float32](
        vector_scalar_count
    )
    var matrix_device = context.enqueue_create_buffer[DType.float32](
        matrix_scalar_count
    )
    var output_device = context.enqueue_create_buffer[DType.float32](
        vector_scalar_count
    )
    context.enqueue_copy(dst_buf=input_device, src_buf=input_host)
    context.enqueue_copy(dst_buf=matrix_device, src_buf=matrix_host)
    context.enqueue_function[mimo_2x2_matvec_kernel](
        input_device,
        matrix_device,
        output_device,
        Int32(batch_count),
        grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_copy(dst_buf=output_host, src_buf=output_device)
    context.synchronize()
    for batch in range(batch_count):
        for row in range(2):
            var expected_re = Float32(0.0)
            var expected_im = Float32(0.0)
            for column in range(2):
                var matrix_index = 2 * (2 * row + column)
                var input_index = 2 * (2 * batch + column)
                var wr = matrix_host[matrix_index]
                var wi = matrix_host[matrix_index + 1]
                var xr = input_host[input_index]
                var xi = input_host[input_index + 1]
                expected_re += wr * xr - wi * xi
                expected_im += wr * xi + wi * xr
            var output_index = 2 * (2 * batch + row)
            _require_close(
                output_host[output_index], expected_re, 1.0e-6, "GPU MIMO real"
            )
            _require_close(
                output_host[output_index + 1],
                expected_im,
                1.0e-6,
                "GPU MIMO imaginary",
            )


def _validate_correlation(mut context: DeviceContext) raises:
    comptime signal_count = 7
    comptime reference_count = 3
    comptime output_count = signal_count - reference_count + 1
    var work_items = validate_complex_correlation_config(
        signal_count,
        reference_count,
        output_count,
        2 * signal_count,
        2 * reference_count,
        2 * output_count,
    )
    var signal_host = context.enqueue_create_host_buffer[DType.float32](
        2 * signal_count
    )
    var reference_host = context.enqueue_create_host_buffer[DType.float32](
        2 * reference_count
    )
    var output_host = context.enqueue_create_host_buffer[DType.float32](
        2 * output_count
    )
    for index in range(signal_count):
        signal_host[2 * index] = Float32(index) * 0.125 - 0.25
        signal_host[2 * index + 1] = Float32(index % 4) * 0.25 - 0.375
    var reference_values: List[Float32] = [
        0.5, -0.25, 0.125, 0.5, -0.375, 0.25
    ]
    for index in range(2 * reference_count):
        reference_host[index] = reference_values[index]
    var signal_device = context.enqueue_create_buffer[DType.float32](
        2 * signal_count
    )
    var reference_device = context.enqueue_create_buffer[DType.float32](
        2 * reference_count
    )
    var output_device = context.enqueue_create_buffer[DType.float32](
        2 * output_count
    )
    context.enqueue_copy(dst_buf=signal_device, src_buf=signal_host)
    context.enqueue_copy(dst_buf=reference_device, src_buf=reference_host)
    context.enqueue_function[complex_correlation_kernel](
        signal_device,
        reference_device,
        output_device,
        Int32(signal_count),
        Int32(reference_count),
        Int32(output_count),
        grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_copy(dst_buf=output_host, src_buf=output_device)
    context.synchronize()
    for offset in range(output_count):
        var expected_re = Float32(0.0)
        var expected_im = Float32(0.0)
        for index in range(reference_count):
            var signal_index = 2 * (offset + index)
            var reference_index = 2 * index
            var sr = signal_host[signal_index]
            var si = signal_host[signal_index + 1]
            var rr = reference_host[reference_index]
            var ri = reference_host[reference_index + 1]
            expected_re += sr * rr + si * ri
            expected_im += si * rr - sr * ri
        _require_close(
            output_host[2 * offset],
            expected_re,
            1.0e-6,
            "GPU correlation real",
        )
        _require_close(
            output_host[2 * offset + 1],
            expected_im,
            1.0e-6,
            "GPU correlation imaginary",
        )


def _validate_ldpc(mut context: DeviceContext) raises:
    comptime check_count = 2
    comptime degree = 4
    comptime edge_count = check_count * degree
    var work_items = validate_ldpc_check_node_config(
        check_count, degree, edge_count, edge_count
    )
    var input_host = context.enqueue_create_host_buffer[DType.float32](edge_count)
    var output_host = context.enqueue_create_host_buffer[DType.float32](edge_count)
    var values: List[Float32] = [
        1.0,
        -2.0,
        3.0,
        -4.0,
        -0.5,
        1.5,
        2.5,
        -3.5,
    ]
    for index in range(edge_count):
        input_host[index] = values[index]
    var input_device = context.enqueue_create_buffer[DType.float32](edge_count)
    var output_device = context.enqueue_create_buffer[DType.float32](edge_count)
    context.enqueue_copy(dst_buf=input_device, src_buf=input_host)
    context.enqueue_function[ldpc_check_node_kernel](
        input_device,
        output_device,
        Int32(check_count),
        Int32(degree),
        grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_copy(dst_buf=output_host, src_buf=output_device)
    context.synchronize()
    for check in range(check_count):
        for excluded in range(degree):
            var expected_magnitude = Float32(3.402823466e38)
            var expected_sign = 1
            for local_edge in range(degree):
                if local_edge != excluded:
                    var value = input_host[check * degree + local_edge]
                    expected_magnitude = min(expected_magnitude, abs(value))
                    if value < 0.0:
                        expected_sign = -expected_sign
            var expected = (
                expected_magnitude if expected_sign > 0 else -expected_magnitude
            )
            _require_close(
                output_host[check * degree + excluded],
                expected,
                1.0e-6,
                "GPU LDPC check node",
            )


def _validate_sparse_ldpc_decoder(mut context: DeviceContext) raises:
    comptime variable_count = 6
    comptime check_count = 4
    comptime edge_count = 12
    comptime batch_count = 5
    comptime max_iterations = 8
    comptime channel_count = batch_count * variable_count
    comptime message_count = batch_count * edge_count
    comptime normalization = Float32(0.8)
    comptime offset = Float32(0.1)
    comptime clip = Float32(20.0)

    var rows = _sparse_ldpc_rows()
    var columns = _sparse_ldpc_columns()
    var cases = _sparse_ldpc_llr_cases()
    var row_host = context.enqueue_create_host_buffer[DType.int32](
        check_count + 1
    )
    var column_host = context.enqueue_create_host_buffer[DType.int32](
        edge_count
    )
    var channel_host = context.enqueue_create_host_buffer[DType.float32](
        channel_count
    )
    for index in range(check_count + 1):
        row_host[index] = Int32(rows[index])
    for edge in range(edge_count):
        column_host[edge] = Int32(columns[edge])
    for codeword in range(batch_count):
        for variable in range(variable_count):
            channel_host[codeword * variable_count + variable] = Float32(
                cases[codeword][variable]
            )
    var work_items = validate_batched_sparse_ldpc_min_sum_decode_config(
        channel_host.unsafe_ptr(),
        row_host.unsafe_ptr(),
        column_host.unsafe_ptr(),
        channel_count,
        check_count + 1,
        edge_count,
        channel_count,
        batch_count,
        batch_count,
        batch_count,
        message_count,
        message_count,
        channel_count,
        variable_count,
        check_count,
        edge_count,
        batch_count,
        max_iterations,
        normalization,
        offset,
        clip,
    )

    var channel_device = context.enqueue_create_buffer[DType.float32](
        channel_count
    )
    var row_device = context.enqueue_create_buffer[DType.int32](check_count + 1)
    var column_device = context.enqueue_create_buffer[DType.int32](edge_count)
    var hard_device = context.enqueue_create_buffer[DType.uint8](channel_count)
    var iteration_device = context.enqueue_create_buffer[DType.int32](batch_count)
    var converged_device = context.enqueue_create_buffer[DType.uint8](batch_count)
    var syndrome_device = context.enqueue_create_buffer[DType.int32](batch_count)
    var variable_to_check_device = context.enqueue_create_buffer[DType.float32](
        message_count
    )
    var check_to_variable_device = context.enqueue_create_buffer[DType.float32](
        message_count
    )
    var posterior_device = context.enqueue_create_buffer[DType.float32](
        channel_count
    )
    var hard_host = context.enqueue_create_host_buffer[DType.uint8](channel_count)
    var iteration_host = context.enqueue_create_host_buffer[DType.int32](
        batch_count
    )
    var converged_host = context.enqueue_create_host_buffer[DType.uint8](
        batch_count
    )
    var syndrome_host = context.enqueue_create_host_buffer[DType.int32](
        batch_count
    )
    var variable_to_check_host = context.enqueue_create_host_buffer[
        DType.float32
    ](message_count)
    var check_to_variable_host = context.enqueue_create_host_buffer[
        DType.float32
    ](message_count)
    var posterior_host = context.enqueue_create_host_buffer[DType.float32](
        channel_count
    )
    context.enqueue_copy(dst_buf=channel_device, src_buf=channel_host)
    context.enqueue_copy(dst_buf=row_device, src_buf=row_host)
    context.enqueue_copy(dst_buf=column_device, src_buf=column_host)
    context.enqueue_function[batched_sparse_ldpc_min_sum_decode_kernel](
        channel_device,
        row_device,
        column_device,
        hard_device,
        iteration_device,
        converged_device,
        syndrome_device,
        variable_to_check_device,
        check_to_variable_device,
        posterior_device,
        Int32(channel_count),
        Int32(check_count + 1),
        Int32(edge_count),
        Int32(channel_count),
        Int32(batch_count),
        Int32(batch_count),
        Int32(batch_count),
        Int32(message_count),
        Int32(message_count),
        Int32(channel_count),
        Int32(variable_count),
        Int32(check_count),
        Int32(edge_count),
        Int32(batch_count),
        Int32(max_iterations),
        normalization,
        offset,
        clip,
        grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_copy(dst_buf=hard_host, src_buf=hard_device)
    context.enqueue_copy(dst_buf=iteration_host, src_buf=iteration_device)
    context.enqueue_copy(dst_buf=converged_host, src_buf=converged_device)
    context.enqueue_copy(dst_buf=syndrome_host, src_buf=syndrome_device)
    context.enqueue_copy(
        dst_buf=variable_to_check_host, src_buf=variable_to_check_device
    )
    context.enqueue_copy(
        dst_buf=check_to_variable_host, src_buf=check_to_variable_device
    )
    context.enqueue_copy(dst_buf=posterior_host, src_buf=posterior_device)
    context.synchronize()

    var result_checksum = 0
    for codeword in range(batch_count):
        var cpu = ldpc_decode_min_sum(
            Span(cases[codeword]),
            Span(rows),
            Span(columns),
            max_iterations=max_iterations,
            normalization=Float64(normalization),
            offset=Float64(offset),
            clip=Float64(clip),
        )
        if iteration_host[codeword] != Int32(cpu.iterations):
            raise Error("GPU sparse LDPC iteration count differs from CPU")
        var expected_converged = UInt8(1) if cpu.converged else UInt8(0)
        if converged_host[codeword] != expected_converged:
            raise Error("GPU sparse LDPC convergence flag differs from CPU")
        var gpu_bits = List[UInt8](capacity=variable_count)
        for variable in range(variable_count):
            var bit = hard_host[codeword * variable_count + variable]
            gpu_bits.append(bit)
            if bit != cpu.bits[variable]:
                raise Error("GPU sparse LDPC hard decision differs from CPU")
            result_checksum += (
                (codeword + 1) * (variable + 1) * Int(bit)
            )
            var posterior = posterior_host[
                codeword * variable_count + variable
            ]
            if not isfinite(posterior) or abs(posterior) > clip:
                raise Error("GPU sparse LDPC posterior workspace is invalid")
        var expected_syndrome = _sparse_syndrome_weight(
            Span(gpu_bits), Span(rows), Span(columns)
        )
        if syndrome_host[codeword] != Int32(expected_syndrome):
            raise Error("GPU sparse LDPC syndrome weight differs from hard bits")
        if (syndrome_host[codeword] == 0) != (converged_host[codeword] == 1):
            raise Error("GPU sparse LDPC convergence/syndrome invariant failed")
        result_checksum += (codeword + 1) * (
            17 * Int(iteration_host[codeword])
            + 31 * Int(syndrome_host[codeword])
        )
    for index in range(message_count):
        var v2c = variable_to_check_host[index]
        var c2v = check_to_variable_host[index]
        if not isfinite(v2c) or abs(v2c) > clip:
            raise Error("GPU sparse LDPC v2c workspace is invalid")
        if not isfinite(c2v) or abs(c2v) > clip:
            raise Error("GPU sparse LDPC c2v workspace is invalid")

    comptime repetitions = 9
    var start = global_perf_counter_ns()
    for _ in range(repetitions):
        context.enqueue_function[batched_sparse_ldpc_min_sum_decode_kernel](
            channel_device,
            row_device,
            column_device,
            hard_device,
            iteration_device,
            converged_device,
            syndrome_device,
            variable_to_check_device,
            check_to_variable_device,
            posterior_device,
            Int32(channel_count),
            Int32(check_count + 1),
            Int32(edge_count),
            Int32(channel_count),
            Int32(batch_count),
            Int32(batch_count),
            Int32(batch_count),
            Int32(message_count),
            Int32(message_count),
            Int32(channel_count),
            Int32(variable_count),
            Int32(check_count),
            Int32(edge_count),
            Int32(batch_count),
            Int32(max_iterations),
            normalization,
            offset,
            clip,
            grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
            block_dim=_BLOCK_SIZE,
        )
    context.synchronize()
    var elapsed_ns = global_perf_counter_ns() - start
    if elapsed_ns <= 0:
        raise Error("GPU sparse LDPC benchmark timer did not advance")
    var repeat_hard_host = context.enqueue_create_host_buffer[DType.uint8](
        channel_count
    )
    var repeat_iteration_host = context.enqueue_create_host_buffer[DType.int32](
        batch_count
    )
    var repeat_converged_host = context.enqueue_create_host_buffer[DType.uint8](
        batch_count
    )
    var repeat_syndrome_host = context.enqueue_create_host_buffer[DType.int32](
        batch_count
    )
    context.enqueue_copy(dst_buf=repeat_hard_host, src_buf=hard_device)
    context.enqueue_copy(dst_buf=repeat_iteration_host, src_buf=iteration_device)
    context.enqueue_copy(dst_buf=repeat_converged_host, src_buf=converged_device)
    context.enqueue_copy(dst_buf=repeat_syndrome_host, src_buf=syndrome_device)
    context.synchronize()
    for index in range(channel_count):
        if repeat_hard_host[index] != hard_host[index]:
            raise Error("GPU sparse LDPC hard output is not reproducible")
    for codeword in range(batch_count):
        if repeat_iteration_host[codeword] != iteration_host[codeword]:
            raise Error("GPU sparse LDPC iteration output is not reproducible")
        if repeat_converged_host[codeword] != converged_host[codeword]:
            raise Error("GPU sparse LDPC convergence output is not reproducible")
        if repeat_syndrome_host[codeword] != syndrome_host[codeword]:
            raise Error("GPU sparse LDPC syndrome output is not reproducible")
    var codewords_per_second = (
        Float64(batch_count * repetitions) * 1.0e9 / Float64(elapsed_ns)
    )
    print(
        "GPU sparse LDPC batch:",
        batch_count,
        "repetitions:",
        repetitions,
        "elapsed_ns:",
        elapsed_ns,
        "codewords_per_second:",
        codewords_per_second,
        "result_checksum:",
        result_checksum,
    )


def _validate_coded_ldpc_bler(mut context: DeviceContext) raises:
    comptime variable_count = 6
    comptime check_count = 4
    comptime edge_count = 12
    comptime snr_count = 4
    comptime seed_count = 64
    comptime batch_count = snr_count * seed_count
    comptime total_bit_count = batch_count * variable_count
    comptime message_count = batch_count * edge_count
    comptime max_iterations = 8
    comptime normalization = Float32(0.8)
    comptime offset = Float32(0.1)
    comptime clip = Float32(20.0)

    var rows = _sparse_ldpc_rows()
    var columns = _sparse_ldpc_columns()
    var codewords = _coded_ldpc_codewords()
    var noise_variances = _coded_ldpc_noise_variances()
    var oracle = _run_coded_ldpc_cpu_oracle()
    var bit_host = context.enqueue_create_host_buffer[DType.uint8](
        total_bit_count
    )
    var noise_host = context.enqueue_create_host_buffer[DType.float32](
        batch_count
    )
    var seed_host = context.enqueue_create_host_buffer[DType.uint64](batch_count)
    var row_host = context.enqueue_create_host_buffer[DType.int32](
        check_count + 1
    )
    var column_host = context.enqueue_create_host_buffer[DType.int32](edge_count)
    for row in range(check_count + 1):
        row_host[row] = Int32(rows[row])
    for edge in range(edge_count):
        column_host[edge] = Int32(columns[edge])
    for seed_index in range(seed_count):
        var seed = _coded_ldpc_seed(seed_index)
        var codeword_index = seed_index % 8
        for snr_index in range(snr_count):
            var batch = seed_index * snr_count + snr_index
            noise_host[batch] = noise_variances[snr_index]
            seed_host[batch] = seed
            for variable in range(variable_count):
                bit_host[batch * variable_count + variable] = codewords[
                    codeword_index * variable_count + variable
                ]

    var channel_work_items = validate_coded_bpsk_awgn_llr_config(
        bit_host.unsafe_ptr(),
        noise_host.unsafe_ptr(),
        seed_host.unsafe_ptr(),
        total_bit_count,
        batch_count,
        batch_count,
        total_bit_count,
        variable_count,
        batch_count,
    )
    var decoder_work_items = (
        validate_batched_sparse_ldpc_min_sum_decode_config(
            oracle.llrs.unsafe_ptr(),
            row_host.unsafe_ptr(),
            column_host.unsafe_ptr(),
            total_bit_count,
            check_count + 1,
            edge_count,
            total_bit_count,
            batch_count,
            batch_count,
            batch_count,
            message_count,
            message_count,
            total_bit_count,
            variable_count,
            check_count,
            edge_count,
            batch_count,
            max_iterations,
            normalization,
            offset,
            clip,
        )
    )

    var bit_device = context.enqueue_create_buffer[DType.uint8](total_bit_count)
    var noise_device = context.enqueue_create_buffer[DType.float32](batch_count)
    var seed_device = context.enqueue_create_buffer[DType.uint64](batch_count)
    var llr_device = context.enqueue_create_buffer[DType.float32](total_bit_count)
    var row_device = context.enqueue_create_buffer[DType.int32](check_count + 1)
    var column_device = context.enqueue_create_buffer[DType.int32](edge_count)
    var hard_device = context.enqueue_create_buffer[DType.uint8](total_bit_count)
    var iteration_device = context.enqueue_create_buffer[DType.int32](batch_count)
    var converged_device = context.enqueue_create_buffer[DType.uint8](batch_count)
    var syndrome_device = context.enqueue_create_buffer[DType.int32](batch_count)
    var variable_to_check_device = context.enqueue_create_buffer[DType.float32](
        message_count
    )
    var check_to_variable_device = context.enqueue_create_buffer[DType.float32](
        message_count
    )
    var posterior_device = context.enqueue_create_buffer[DType.float32](
        total_bit_count
    )
    var llr_host = context.enqueue_create_host_buffer[DType.float32](
        total_bit_count
    )
    var hard_host = context.enqueue_create_host_buffer[DType.uint8](total_bit_count)
    var iteration_host = context.enqueue_create_host_buffer[DType.int32](
        batch_count
    )
    var converged_host = context.enqueue_create_host_buffer[DType.uint8](
        batch_count
    )
    var syndrome_host = context.enqueue_create_host_buffer[DType.int32](
        batch_count
    )
    var variable_to_check_host = context.enqueue_create_host_buffer[
        DType.float32
    ](message_count)
    var check_to_variable_host = context.enqueue_create_host_buffer[
        DType.float32
    ](message_count)
    var posterior_host = context.enqueue_create_host_buffer[DType.float32](
        total_bit_count
    )
    context.enqueue_copy(dst_buf=bit_device, src_buf=bit_host)
    context.enqueue_copy(dst_buf=noise_device, src_buf=noise_host)
    context.enqueue_copy(dst_buf=seed_device, src_buf=seed_host)
    context.enqueue_copy(dst_buf=row_device, src_buf=row_host)
    context.enqueue_copy(dst_buf=column_device, src_buf=column_host)
    context.enqueue_function[coded_bpsk_awgn_llr_kernel](
        bit_device,
        noise_device,
        seed_device,
        llr_device,
        Int32(total_bit_count),
        Int32(batch_count),
        Int32(batch_count),
        Int32(total_bit_count),
        Int32(variable_count),
        Int32(batch_count),
        Int32(total_bit_count),
        grid_dim=gpu_grid_size(channel_work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_function[batched_sparse_ldpc_min_sum_decode_kernel](
        llr_device,
        row_device,
        column_device,
        hard_device,
        iteration_device,
        converged_device,
        syndrome_device,
        variable_to_check_device,
        check_to_variable_device,
        posterior_device,
        Int32(total_bit_count),
        Int32(check_count + 1),
        Int32(edge_count),
        Int32(total_bit_count),
        Int32(batch_count),
        Int32(batch_count),
        Int32(batch_count),
        Int32(message_count),
        Int32(message_count),
        Int32(total_bit_count),
        Int32(variable_count),
        Int32(check_count),
        Int32(edge_count),
        Int32(batch_count),
        Int32(max_iterations),
        normalization,
        offset,
        clip,
        grid_dim=gpu_grid_size(decoder_work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_copy(dst_buf=llr_host, src_buf=llr_device)
    context.enqueue_copy(dst_buf=hard_host, src_buf=hard_device)
    context.enqueue_copy(dst_buf=iteration_host, src_buf=iteration_device)
    context.enqueue_copy(dst_buf=converged_host, src_buf=converged_device)
    context.enqueue_copy(dst_buf=syndrome_host, src_buf=syndrome_device)
    context.enqueue_copy(
        dst_buf=variable_to_check_host, src_buf=variable_to_check_device
    )
    context.enqueue_copy(
        dst_buf=check_to_variable_host, src_buf=check_to_variable_device
    )
    context.enqueue_copy(dst_buf=posterior_host, src_buf=posterior_device)
    context.synchronize()

    var gpu_block_errors = List[Int](length=snr_count, fill=0)
    var result_checksum = Int64(0)
    for batch in range(batch_count):
        var seed_index = batch // snr_count
        var snr_index = batch % snr_count
        var codeword_index = seed_index % 8
        var block_error = converged_host[batch] == 0
        if iteration_host[batch] != oracle.iterations[batch]:
            raise Error("GPU coded LDPC iteration count differs from CPU")
        if converged_host[batch] != oracle.converged[batch]:
            raise Error("GPU coded LDPC convergence flag differs from CPU")
        if syndrome_host[batch] != oracle.syndrome_weights[batch]:
            raise Error("GPU coded LDPC syndrome weight differs from CPU")
        if (syndrome_host[batch] == 0) != (converged_host[batch] == 1):
            raise Error("GPU coded LDPC convergence/syndrome invariant failed")
        for variable in range(variable_count):
            var index = batch * variable_count + variable
            _require_close_scaled(
                llr_host[index],
                oracle.llrs[index],
                5.0e-5,
                5.0e-5,
                "GPU coded BPSK channel LLR",
            )
            if hard_host[index] != oracle.decoded_bits[index]:
                raise Error("GPU coded LDPC decoded bit differs from CPU")
            if hard_host[index] != codewords[
                codeword_index * variable_count + variable
            ]:
                block_error = True
            var posterior = posterior_host[index]
            if not isfinite(posterior) or abs(posterior) > clip:
                raise Error("GPU coded LDPC posterior workspace is invalid")
            result_checksum += (
                Int64(batch + 1)
                * Int64(variable + 1)
                * Int64(hard_host[index])
            )
        if block_error:
            gpu_block_errors[snr_index] += 1
        result_checksum += Int64(batch + 1) * (
            Int64(
                17 * Int(iteration_host[batch])
                + 31 * Int(syndrome_host[batch])
            )
        )
    for index in range(message_count):
        if not isfinite(variable_to_check_host[index]):
            raise Error("GPU coded LDPC v2c workspace is non-finite")
        if not isfinite(check_to_variable_host[index]):
            raise Error("GPU coded LDPC c2v workspace is non-finite")
    if result_checksum != oracle.result_checksum:
        raise Error("GPU coded LDPC decoded-result checksum differs from CPU")
    for snr_index in range(snr_count):
        if gpu_block_errors[snr_index] != oracle.block_errors_by_snr[snr_index]:
            raise Error("GPU coded LDPC BLER differs from CPU")
        if (
            snr_index > 0
            and gpu_block_errors[snr_index]
            > gpu_block_errors[snr_index - 1]
        ):
            raise Error("GPU coded LDPC BLER increased with SNR")

    comptime repetitions = 9
    var start = global_perf_counter_ns()
    for _ in range(repetitions):
        context.enqueue_function[coded_bpsk_awgn_llr_kernel](
            bit_device,
            noise_device,
            seed_device,
            llr_device,
            Int32(total_bit_count),
            Int32(batch_count),
            Int32(batch_count),
            Int32(total_bit_count),
            Int32(variable_count),
            Int32(batch_count),
            Int32(total_bit_count),
            grid_dim=gpu_grid_size(channel_work_items, _BLOCK_SIZE),
            block_dim=_BLOCK_SIZE,
        )
        context.enqueue_function[batched_sparse_ldpc_min_sum_decode_kernel](
            llr_device,
            row_device,
            column_device,
            hard_device,
            iteration_device,
            converged_device,
            syndrome_device,
            variable_to_check_device,
            check_to_variable_device,
            posterior_device,
            Int32(total_bit_count),
            Int32(check_count + 1),
            Int32(edge_count),
            Int32(total_bit_count),
            Int32(batch_count),
            Int32(batch_count),
            Int32(batch_count),
            Int32(message_count),
            Int32(message_count),
            Int32(total_bit_count),
            Int32(variable_count),
            Int32(check_count),
            Int32(edge_count),
            Int32(batch_count),
            Int32(max_iterations),
            normalization,
            offset,
            clip,
            grid_dim=gpu_grid_size(decoder_work_items, _BLOCK_SIZE),
            block_dim=_BLOCK_SIZE,
        )
    context.synchronize()
    var elapsed_ns = global_perf_counter_ns() - start
    if elapsed_ns <= 0:
        raise Error("GPU coded LDPC BLER benchmark timer did not advance")
    var repeat_llr_host = context.enqueue_create_host_buffer[DType.float32](
        total_bit_count
    )
    var repeat_hard_host = context.enqueue_create_host_buffer[DType.uint8](
        total_bit_count
    )
    var repeat_iteration_host = context.enqueue_create_host_buffer[DType.int32](
        batch_count
    )
    var repeat_converged_host = context.enqueue_create_host_buffer[DType.uint8](
        batch_count
    )
    var repeat_syndrome_host = context.enqueue_create_host_buffer[DType.int32](
        batch_count
    )
    context.enqueue_copy(dst_buf=repeat_llr_host, src_buf=llr_device)
    context.enqueue_copy(dst_buf=repeat_hard_host, src_buf=hard_device)
    context.enqueue_copy(dst_buf=repeat_iteration_host, src_buf=iteration_device)
    context.enqueue_copy(dst_buf=repeat_converged_host, src_buf=converged_device)
    context.enqueue_copy(dst_buf=repeat_syndrome_host, src_buf=syndrome_device)
    context.synchronize()
    for index in range(total_bit_count):
        if repeat_llr_host[index] != llr_host[index]:
            raise Error("GPU coded BPSK LLR replay is not deterministic")
        if repeat_hard_host[index] != hard_host[index]:
            raise Error("GPU coded LDPC hard-bit replay is not deterministic")
    for batch in range(batch_count):
        if repeat_iteration_host[batch] != iteration_host[batch]:
            raise Error("GPU coded LDPC iteration replay is not deterministic")
        if repeat_converged_host[batch] != converged_host[batch]:
            raise Error("GPU coded LDPC convergence replay is not deterministic")
        if repeat_syndrome_host[batch] != syndrome_host[batch]:
            raise Error("GPU coded LDPC syndrome replay is not deterministic")
    var blocks_per_second = (
        Float64(batch_count * repetitions) * 1.0e9 / Float64(elapsed_ns)
    )
    print(
        "GPU coded LDPC BLER batches:",
        batch_count,
        "BLER_errors_by_SNR:",
        gpu_block_errors,
        "repetitions:",
        repetitions,
        "elapsed_ns:",
        elapsed_ns,
        "blocks_per_second:",
        blocks_per_second,
        "result_checksum:",
        result_checksum,
    )


def _validate_soft_llrs(mut context: DeviceContext) raises:
    comptime symbol_count = 5
    comptime iq_count = 2 * symbol_count
    comptime noise_variance = Float32(0.25)
    comptime qpsk_llr_count = 2 * symbol_count
    comptime qam16_llr_count = 4 * symbol_count
    var qpsk_work_items = validate_soft_llr_config(
        2, symbol_count, noise_variance, iq_count, qpsk_llr_count
    )
    var qam16_work_items = validate_soft_llr_config(
        4, symbol_count, noise_variance, iq_count, qam16_llr_count
    )
    var iq_host = context.enqueue_create_host_buffer[DType.float32](iq_count)
    var samples: List[Float32] = [
        0.8,
        0.6,
        -0.7,
        0.9,
        0.25,
        -0.35,
        -1.1,
        -0.2,
        0.0,
        1.2,
    ]
    for index in range(iq_count):
        iq_host[index] = samples[index]
    var iq_device = context.enqueue_create_buffer[DType.float32](iq_count)
    var qpsk_device = context.enqueue_create_buffer[DType.float32](qpsk_llr_count)
    var qam16_device = context.enqueue_create_buffer[DType.float32](qam16_llr_count)
    var qpsk_host = context.enqueue_create_host_buffer[DType.float32](
        qpsk_llr_count
    )
    var qam16_host = context.enqueue_create_host_buffer[DType.float32](
        qam16_llr_count
    )
    context.enqueue_copy(dst_buf=iq_device, src_buf=iq_host)
    context.enqueue_function[qpsk_soft_llr_kernel](
        iq_device,
        qpsk_device,
        Int32(symbol_count),
        noise_variance,
        grid_dim=gpu_grid_size(qpsk_work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_function[qam16_soft_llr_kernel](
        iq_device,
        qam16_device,
        Int32(symbol_count),
        noise_variance,
        grid_dim=gpu_grid_size(qam16_work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_copy(dst_buf=qpsk_host, src_buf=qpsk_device)
    context.enqueue_copy(dst_buf=qam16_host, src_buf=qam16_device)
    context.synchronize()

    var qpsk_scale = Float32(0.7071067811865475244)
    for index in range(iq_count):
        # Algebraically independent form of the two-distance max-log result.
        var expected = Float32(4.0) * qpsk_scale * iq_host[index] / noise_variance
        _require_close(qpsk_host[index], expected, 1.0e-5, "GPU QPSK LLR")

    var inner = Float32(0.3162277660168379332)
    var levels: List[Float32] = [
        -3.0 * inner, -inner, inner, 3.0 * inner
    ]
    var sign_bits: List[Int] = [1, 1, 0, 0]
    var magnitude_bits: List[Int] = [0, 1, 1, 0]
    for symbol in range(symbol_count):
        for component in range(2):
            var value = iq_host[2 * symbol + component]
            var sign_zero = Float32(3.402823466e38)
            var sign_one = Float32(3.402823466e38)
            var magnitude_zero = Float32(3.402823466e38)
            var magnitude_one = Float32(3.402823466e38)
            for level_index in range(4):
                var difference = value - levels[level_index]
                var distance = difference * difference
                if sign_bits[level_index] == 0:
                    sign_zero = min(sign_zero, distance)
                else:
                    sign_one = min(sign_one, distance)
                if magnitude_bits[level_index] == 0:
                    magnitude_zero = min(magnitude_zero, distance)
                else:
                    magnitude_one = min(magnitude_one, distance)
            var output_index = 4 * symbol + 2 * component
            _require_close(
                qam16_host[output_index],
                (sign_one - sign_zero) / noise_variance,
                1.0e-5,
                "GPU 16-QAM sign LLR",
            )
            _require_close(
                qam16_host[output_index + 1],
                (magnitude_one - magnitude_zero) / noise_variance,
                1.0e-5,
                "GPU 16-QAM magnitude LLR",
            )


def _validate_ber_sweep(
    mut context: DeviceContext, bits_per_symbol: Int
) raises:
    comptime symbols_per_case = 4096
    comptime esn0_count = 4
    comptime seed_count = 3
    comptime case_count = esn0_count * seed_count
    comptime total_symbols = symbols_per_case * case_count
    comptime received_scalar_count = 2 * total_symbols

    var esn0_host = context.enqueue_create_host_buffer[DType.float32](esn0_count)
    esn0_host[0] = -2.0
    esn0_host[1] = 2.0
    esn0_host[2] = 6.0
    esn0_host[3] = 10.0
    var seed_host = context.enqueue_create_host_buffer[DType.uint64](seed_count)
    seed_host[0] = UInt64(0)
    seed_host[1] = UInt64(0x0123456789ABCDEF)
    seed_host[2] = UInt64(0xFEDCBA9876543210)
    var llr_count = total_symbols * bits_per_symbol
    var work_items = validate_qam_awgn_ber_sweep_config(
        bits_per_symbol,
        symbols_per_case,
        esn0_host.unsafe_ptr(),
        esn0_count,
        seed_count,
        esn0_count,
        seed_count,
        received_scalar_count,
        llr_count,
        total_symbols,
    )

    var esn0_device = context.enqueue_create_buffer[DType.float32](esn0_count)
    var seed_device = context.enqueue_create_buffer[DType.uint64](seed_count)
    var received_device = context.enqueue_create_buffer[DType.float32](
        received_scalar_count
    )
    var llr_device = context.enqueue_create_buffer[DType.float32](llr_count)
    var error_device = context.enqueue_create_buffer[DType.int32](total_symbols)
    var received_host = context.enqueue_create_host_buffer[DType.float32](
        received_scalar_count
    )
    var llr_host = context.enqueue_create_host_buffer[DType.float32](llr_count)
    var error_host = context.enqueue_create_host_buffer[DType.int32](
        total_symbols
    )
    context.enqueue_copy(dst_buf=esn0_device, src_buf=esn0_host)
    context.enqueue_copy(dst_buf=seed_device, src_buf=seed_host)
    context.enqueue_function[qam_awgn_ber_sweep_kernel](
        esn0_device,
        seed_device,
        received_device,
        llr_device,
        error_device,
        Int32(bits_per_symbol),
        Int32(symbols_per_case),
        Int32(esn0_count),
        Int32(seed_count),
        Int32(total_symbols),
        grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
        block_dim=_BLOCK_SIZE,
    )
    context.enqueue_copy(dst_buf=received_host, src_buf=received_device)
    context.enqueue_copy(dst_buf=llr_host, src_buf=llr_device)
    context.enqueue_copy(dst_buf=error_host, src_buf=error_device)
    context.synchronize()

    var gpu_case_errors = List[Int](length=case_count, fill=0)
    var oracle_case_errors = List[Int](length=case_count, fill=0)
    for work_item in range(total_symbols):
        var case_index = work_item // symbols_per_case
        var symbol = work_item % symbols_per_case
        var seed_index = case_index // esn0_count
        var esn0_index = case_index % esn0_count
        var noise_variance = exp(
            Float32(-0.2302585092994045684) * esn0_host[esn0_index]
        )
        var sample = _oracle_ber_sample(
            seed_host[seed_index],
            symbol,
            bits_per_symbol,
            esn0_host[esn0_index],
        )
        _require_close_scaled(
            received_host[2 * work_item],
            sample.received_re,
            3.0e-5,
            3.0e-5,
            "GPU BER sweep received real",
        )
        _require_close_scaled(
            received_host[2 * work_item + 1],
            sample.received_im,
            3.0e-5,
            3.0e-5,
            "GPU BER sweep received imaginary",
        )

        var expected_errors = 0
        if bits_per_symbol == 2:
            var expected_re = (
                Float32(4.0)
                * _QPSK_SCALE
                * sample.received_re
                / noise_variance
            )
            var expected_im = (
                Float32(4.0)
                * _QPSK_SCALE
                * sample.received_im
                / noise_variance
            )
            _require_close_scaled(
                llr_host[2 * work_item],
                expected_re,
                3.0e-4,
                2.0e-4,
                "GPU BER sweep QPSK I LLR",
            )
            _require_close_scaled(
                llr_host[2 * work_item + 1],
                expected_im,
                3.0e-4,
                2.0e-4,
                "GPU BER sweep QPSK Q LLR",
            )
            var hard_re = Int32(0) if expected_re >= 0.0 else Int32(1)
            var hard_im = Int32(0) if expected_im >= 0.0 else Int32(1)
            if hard_re != sample.bit_i_sign:
                expected_errors += 1
            if hard_im != sample.bit_i_magnitude:
                expected_errors += 1
        else:
            for component in range(2):
                var value = (
                    sample.received_re
                    if component == 0
                    else sample.received_im
                )
                var source_sign = (
                    sample.bit_i_sign
                    if component == 0
                    else sample.bit_q_sign
                )
                var source_magnitude = (
                    sample.bit_i_magnitude
                    if component == 0
                    else sample.bit_q_magnitude
                )
                var expected_sign, expected_magnitude = _oracle_component_llrs(
                    value, noise_variance
                )
                var llr_index = 4 * work_item + 2 * component
                _require_close_scaled(
                    llr_host[llr_index],
                    expected_sign,
                    3.0e-4,
                    2.0e-4,
                    "GPU BER sweep 16-QAM sign LLR",
                )
                _require_close_scaled(
                    llr_host[llr_index + 1],
                    expected_magnitude,
                    3.0e-4,
                    2.0e-4,
                    "GPU BER sweep 16-QAM magnitude LLR",
                )
                var hard_sign = (
                    Int32(0) if expected_sign >= 0.0 else Int32(1)
                )
                var hard_magnitude = (
                    Int32(0) if expected_magnitude >= 0.0 else Int32(1)
                )
                if hard_sign != source_sign:
                    expected_errors += 1
                if hard_magnitude != source_magnitude:
                    expected_errors += 1
        if error_host[work_item] != Int32(expected_errors):
            raise Error("GPU BER sweep per-symbol hard-error mismatch")
        if (
            error_host[work_item] < 0
            or error_host[work_item] > Int32(bits_per_symbol)
        ):
            raise Error("GPU BER sweep emitted an invalid bit-error count")
        gpu_case_errors[case_index] += Int(error_host[work_item])
        oracle_case_errors[case_index] += expected_errors

    for case_index in range(case_count):
        if gpu_case_errors[case_index] != oracle_case_errors[case_index]:
            raise Error("GPU BER sweep aggregate error mismatch")
    var error_checksum = 0
    for case_index in range(case_count):
        error_checksum += (case_index + 1) * gpu_case_errors[case_index]
    for seed_index in range(seed_count):
        for esn0_index in range(1, esn0_count):
            var previous = gpu_case_errors[
                seed_index * esn0_count + esn0_index - 1
            ]
            var current = gpu_case_errors[
                seed_index * esn0_count + esn0_index
            ]
            if current > previous:
                raise Error("GPU BER sweep errors increased with Es/N0")

    # The initial differential launch is also the warm-up.  Repeated kernel
    # launches provide an observable device-side throughput sample and verify
    # that counter-based results are independent of launch history.
    comptime repetitions = 9
    var start = global_perf_counter_ns()
    for _ in range(repetitions):
        context.enqueue_function[qam_awgn_ber_sweep_kernel](
            esn0_device,
            seed_device,
            received_device,
            llr_device,
            error_device,
            Int32(bits_per_symbol),
            Int32(symbols_per_case),
            Int32(esn0_count),
            Int32(seed_count),
            Int32(total_symbols),
            grid_dim=gpu_grid_size(work_items, _BLOCK_SIZE),
            block_dim=_BLOCK_SIZE,
        )
    context.synchronize()
    var elapsed_ns = global_perf_counter_ns() - start
    if elapsed_ns <= 0:
        raise Error("GPU BER sweep benchmark timer did not advance")
    var repeated_error_host = context.enqueue_create_host_buffer[DType.int32](
        total_symbols
    )
    context.enqueue_copy(dst_buf=repeated_error_host, src_buf=error_device)
    context.synchronize()
    for work_item in range(total_symbols):
        if repeated_error_host[work_item] != error_host[work_item]:
            raise Error("GPU BER sweep is not reproducible for a fixed seed")
    var symbols_per_second = (
        Float64(total_symbols * repetitions)
        * 1.0e9
        / Float64(elapsed_ns)
    )
    print(
        "GPU QAM/AWGN BER sweep bits_per_symbol:",
        bits_per_symbol,
        "symbols:",
        total_symbols,
        "repetitions:",
        repetitions,
        "elapsed_ns:",
        elapsed_ns,
        "symbols_per_second:",
        symbols_per_second,
        "error_checksum:",
        error_checksum,
    )


def main() raises:
    _validate_ber_oracle_contract()
    _validate_sparse_ldpc_cpu_contract()
    _validate_coded_ldpc_cpu_contract()
    comptime if not has_accelerator():
        print(
            "Phase 6 seeded QAM/AWGN and coded LDPC BLER CPU oracles passed; "
            "pointer GPU host "
            "integration compiled; device execution/differential/throughput "
            "skipped (no compatible accelerator)"
        )
    else:
        var context = DeviceContext()
        _validate_fft(context)
        _validate_channel(context)
        _validate_mimo(context)
        _validate_correlation(context)
        _validate_ldpc(context)
        _validate_sparse_ldpc_decoder(context)
        _validate_coded_ldpc_bler(context)
        _validate_soft_llrs(context)
        _validate_ber_sweep(context, 2)
        _validate_ber_sweep(context, 4)
        print(
            "Phase 6 GPU FFT/IFFT/channel/MIMO/correlation/LDPC decoder/LLR, "
            "seeded SNR-batched BER, and coded-LDPC BLER differential checks "
            "passed"
        )
