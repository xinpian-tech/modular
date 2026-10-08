"""Representative Phase 3-6 CPU benchmarks with retained PHY results.

The cases intentionally use small iteration counts: the dense 8x8 equalizers,
one standards-based NR LDPC codeword, one HT BCC DATA symbol, one HE WLAN-LDPC
RU-242 DATA symbol, and a deterministic QAM/AWGN link simulation.  Printed
checksums and decoder/FCS state keep every measured result observable.
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
from wireless_dsp.core import Complex64
from wireless_dsp.mimo import (
    SmallComplexMatrix,
    matrix_vector_multiply,
    zf_equalize,
    mmse_equalize,
)
from wireless_dsp.testing.checkpoint import checkpoint_bits_checksum
from wireless_dsp.testing.link_simulation import (
    simulate_qam_awgn,
    simulate_qam_awgn_sweep,
)
from wireless_dsp.wireless.nr.ldpc_codec import (
    nr_ldpc_encode,
    nr_ldpc_decode,
)
from wireless_dsp.wireless.wifi.phy_chain import (
    wifi_bcc_tx_20mhz,
    wifi_bcc_rx_20mhz,
    wifi_ldpc_tx_20mhz,
    wifi_ldpc_rx_20mhz,
)
from wireless_dsp.wireless.wifi.preambles import wifi_ltf_waveform_20mhz
from wireless_dsp.wireless.wifi.profiles import WIFI_PHY_HT, WIFI_PHY_HE


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _FIXED_RUNS = 2


def _pattern_bits(length: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for i in range(length):
        result.append(UInt8((17 * i + i // 5 + salt) & 1))
    return result^


def _mimo_channel_8x8() raises -> SmallComplexMatrix:
    var channel = SmallComplexMatrix(8, 8)
    for row in range(8):
        for column in range(8):
            if row == column:
                channel[row, column] = Complex64(
                    2.0 + 0.08 * Float64(row),
                    0.01 * Float64(row),
                )
            else:
                channel[row, column] = Complex64(
                    0.015 * Float64(1 + (3 * row + column) % 7),
                    0.005 * Float64(row - column),
                )
    return channel^


def _mix_mimo(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def _fingerprint_mimo_float(value: Float64) -> UInt64:
    return _mix_mimo(
        UInt64(Int(abs(value) * 1_000_000.0)),
        UInt64(1 if value < 0.0 else 0),
    )


def _fingerprint_mimo_result(values: List[Complex64]) -> UInt64:
    var fingerprint = UInt64(len(values))
    if len(values) > 0:
        var first = values[0]
        var last = values[len(values) - 1]
        fingerprint = _mix_mimo(
            fingerprint,
            _mix_mimo(
                _fingerprint_mimo_float(first.re),
                _fingerprint_mimo_float(first.im),
            ),
        )
        fingerprint = _mix_mimo(
            fingerprint,
            _mix_mimo(
                _fingerprint_mimo_float(last.re),
                _fingerprint_mimo_float(last.im),
            ),
        )
    return fingerprint


def _record_mimo(
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
            raise Error("fixed Phase-3 MIMO result is nondeterministic")
        keep(first)
        keep(fingerprint)
    elif invocation >= _FIXED_RUNS + _WARMUPS:
        samples.append(elapsed)
        checksum = _mix_mimo(checksum, fingerprint)


def _finish_mimo(
    name: StringSlice,
    mut samples: List[UInt64],
    checksum: UInt64,
) raises -> UInt64:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")
    keep(samples)
    return checksum


@no_inline
def _workload_matrix_vector_multiply(
    channel: SmallComplexMatrix,
    transmitted: Span[Complex64, ...],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = matrix_vector_multiply(channel, transmitted)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_mimo_result(result)
        _record_mimo(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish_mimo(
        "phase3_matrix_vector_multiply", samples, checksum
    )


@no_inline
def _workload_zf_equalize(
    channel: SmallComplexMatrix,
    received: Span[Complex64, ...],
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = zf_equalize(channel, received)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_mimo_result(result)
        _record_mimo(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish_mimo("phase3_zf_equalize", samples, checksum)


@no_inline
def _workload_mmse_equalize(
    channel: SmallComplexMatrix,
    received: Span[Complex64, ...],
    noise_variance: Float64,
) raises -> UInt64:
    var samples = List[UInt64](capacity=_SAMPLES)
    var first = UInt64(0)
    var checksum = UInt64(1469598103934665603)
    for invocation in range(_FIXED_RUNS + _WARMUPS + _SAMPLES):
        var start = global_perf_counter_ns()
        var result = mmse_equalize(channel, received, noise_variance)
        var elapsed = global_perf_counter_ns() - start
        keep(result)
        var fingerprint = _fingerprint_mimo_result(result)
        _record_mimo(
            invocation, elapsed, fingerprint, first, samples, checksum
        )
    return _finish_mimo("phase3_mmse_equalize", samples, checksum)


def _benchmark_mimo() raises:
    var channel = _mimo_channel_8x8()
    var transmitted = List[Complex64](capacity=8)
    for lane in range(8):
        transmitted.append(
            Complex64(
                1.0 if lane % 2 == 0 else -1.0,
                0.5 if (lane // 2) % 2 == 0 else -0.5,
            )
        )
    var transmitted_span = Span(transmitted)
    var received = matrix_vector_multiply(channel, transmitted_span)
    var received_span = Span(received)
    var checksum = _workload_matrix_vector_multiply(
        channel, transmitted_span
    )
    checksum ^= _workload_zf_equalize(channel, received_span)
    checksum ^= _workload_mmse_equalize(channel, received_span, 0.01)
    keep(checksum)
    print("phase3_mimo_retained_checksum:", checksum)


def _benchmark_nr_ldpc() raises:
    # TS 38.212 base graph 2, Zc=20: K=10*Zc and punctured N=50*Zc.
    var information = _pattern_bits(200, 3)
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    var last_iterations = 0
    var last_converged = False
    for _ in range(_WARMUPS):
        var encoded = nr_ldpc_encode(Span(information), 2, 20)
        var llrs = List[Float64](capacity=len(encoded))
        var null_mask = List[UInt8](length=len(encoded), fill=UInt8(0))
        for bit in encoded:
            llrs.append(20.0 if bit == 0 else -20.0)
        keep(nr_ldpc_decode(
            Span(llrs), Span(null_mask), 2, 20,
            max_iterations=10, normalization=0.8,
        ))
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var encoded = nr_ldpc_encode(Span(information), 2, 20)
        var llrs = List[Float64](capacity=len(encoded))
        var null_mask = List[UInt8](length=len(encoded), fill=UInt8(0))
        for bit in encoded:
            llrs.append(20.0 if bit == 0 else -20.0)
        var decoded = nr_ldpc_decode(
            Span(llrs),
            Span(null_mask),
            2,
            20,
            max_iterations=10,
            normalization=0.8,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(encoded)
        keep(decoded)
        samples.append(elapsed)
        checksum ^= checkpoint_bits_checksum(Span(encoded))
        checksum ^= checkpoint_bits_checksum(Span(decoded.bits))
        checksum += UInt64(repetition)
        last_iterations = decoded.iterations
        last_converged = decoded.converged

    report_timing_samples(
        "phase4_nr_ldpc_bg2_z20_codeword", samples, _WARMUPS, 1,
        "ldpc_encode_decode_codeword",
    )
    checksum ^= checkpoint_bits_checksum(Span(information))
    keep(checksum)
    print("nr_ldpc_retained_checksum:", checksum)
    print("nr_ldpc_last_iterations:", last_iterations)
    print("nr_ldpc_last_converged:", last_converged)


def _benchmark_wifi_bcc() raises:
    # HT MCS 6 is a one-stream 64-QAM, rate-3/4 BCC DATA symbol.
    var payload = _pattern_bits(18 * 8, 11)
    var ltf = wifi_ltf_waveform_20mhz(WIFI_PHY_HT)
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    var last_fcs_ok = False
    for _ in range(_WARMUPS):
        var transmit = wifi_bcc_tx_20mhz(
            Span(payload), WIFI_PHY_HT, 6, symbol_index=3
        )
        keep(wifi_bcc_rx_20mhz(
            Span(transmit.waveform), Span(ltf), WIFI_PHY_HT, 6,
            len(payload), symbol_index=3,
        ))
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var transmit = wifi_bcc_tx_20mhz(
            Span(payload), WIFI_PHY_HT, 6, symbol_index=3
        )
        var receive = wifi_bcc_rx_20mhz(
            Span(transmit.waveform),
            Span(ltf),
            WIFI_PHY_HT,
            6,
            len(payload),
            symbol_index=3,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(transmit)
        keep(receive)
        samples.append(elapsed)
        checksum ^= checkpoint_bits_checksum(Span(receive.payload_bits))
        checksum ^= transmit.fcs + receive.received_fcs
        checksum += UInt64(repetition)
        last_fcs_ok = receive.fcs_ok
    report_timing_samples(
        "phase5_wifi_ht_mcs6_bcc_frame", samples, _WARMUPS, 1,
        "bcc_tx_rx_frame",
    )
    keep(checksum)
    print("wifi_ht_bcc_retained_checksum:", checksum)
    print("wifi_ht_bcc_last_fcs_ok:", last_fcs_ok)


def _benchmark_wifi_ldpc() raises:
    # HE MCS 10 exercises two N=1296, rate-3/4 WLAN-LDPC codewords on RU-242.
    var payload = _pattern_bits(205 * 8, 23)
    var ltf = wifi_ltf_waveform_20mhz(WIFI_PHY_HE)
    var samples = List[UInt64](capacity=_SAMPLES)
    var checksum = UInt64(0)
    var last_converged = False
    var last_fcs_ok = False
    for _ in range(_WARMUPS):
        var transmit = wifi_ldpc_tx_20mhz(
            Span(payload), WIFI_PHY_HE, 10, symbol_index=5
        )
        keep(wifi_ldpc_rx_20mhz(
            Span(transmit.waveform), Span(ltf), WIFI_PHY_HE, 10,
            len(payload), 0.01, symbol_index=5, max_iterations=10,
        ))
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var transmit = wifi_ldpc_tx_20mhz(
            Span(payload), WIFI_PHY_HE, 10, symbol_index=5
        )
        var receive = wifi_ldpc_rx_20mhz(
            Span(transmit.waveform),
            Span(ltf),
            WIFI_PHY_HE,
            10,
            len(payload),
            0.01,
            symbol_index=5,
            max_iterations=10,
        )
        var elapsed = global_perf_counter_ns() - start
        keep(transmit)
        keep(receive)
        samples.append(elapsed)
        checksum ^= checkpoint_bits_checksum(Span(receive.payload_bits))
        checksum ^= transmit.fcs + receive.received_fcs
        checksum += UInt64(repetition)
        last_converged = receive.ldpc_converged
        last_fcs_ok = receive.fcs_ok
    report_timing_samples(
        "phase5_wifi_he_mcs10_ldpc_frame", samples, _WARMUPS, 1,
        "ldpc_tx_rx_frame",
    )
    keep(checksum)
    print("wifi_he_ldpc_retained_checksum:", checksum)
    print("wifi_he_ldpc_last_converged:", last_converged)
    print("wifi_he_ldpc_last_fcs_ok:", last_fcs_ok)


def _benchmark_seeded_link() raises:
    comptime symbols = 4096
    comptime seed = UInt64(0x5EED20260821)
    var orders: List[Int] = [2, 4, 6, 8]
    var noises: List[Float64] = [0.01, 0.1, 1.0]
    var seeds: List[UInt64] = [
        UInt64(0x1001), UInt64(0x1002), UInt64(0x1003), UInt64(0x1004),
    ]
    for warmup in range(_WARMUPS):
        keep(simulate_qam_awgn(8, symbols, 0.05, seed=seed + UInt64(warmup)))
        keep(
            simulate_qam_awgn_sweep(
                Span(orders), Span(noises), Span(seeds), 1024
            )
        )

    var link_samples = List[UInt64](capacity=_SAMPLES)
    var sweep_samples = List[UInt64](capacity=_SAMPLES)
    var link_checksum = UInt64(0)
    var sweep_checksum = UInt64(0)
    for repetition in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var result = simulate_qam_awgn(
            8, symbols, 0.05, seed=seed + UInt64(repetition)
        )
        link_samples.append(global_perf_counter_ns() - start)
        keep(result)
        link_checksum ^= UInt64(result.bit_errors + result.bit_count)
        link_checksum += UInt64(repetition)

        start = global_perf_counter_ns()
        var sweep = simulate_qam_awgn_sweep(
            Span(orders), Span(noises), Span(seeds), 1024
        )
        sweep_samples.append(global_perf_counter_ns() - start)
        keep(sweep)
        for point in sweep:
            sweep_checksum += UInt64(point.result.bit_errors)
        sweep_checksum ^= UInt64(repetition)

    print("seeded_link_seed:", seed)
    report_timing_samples(
        "phase6_seeded_256qam_awgn_symbol",
        link_samples,
        _WARMUPS,
        symbols,
        "qam_symbol",
    )
    report_timing_samples(
        "phase6_seeded_qam_awgn_sweep_symbol",
        sweep_samples,
        _WARMUPS,
        len(orders) * len(noises) * 1024,
        "qam_symbol_across_sweep",
    )
    keep(link_checksum)
    keep(sweep_checksum)
    print("seeded_link_retained_checksum:", link_checksum)
    print("seeded_sweep_retained_checksum:", sweep_checksum)


def main() raises:
    print_benchmark_metadata()
    var alignment_probe = _pattern_bits(256, 91)
    print_runtime_buffer_alignment(
        "phase3_6_uint8_payload",
        Int(alignment_probe.unsafe_ptr()),
        align_of[UInt8](),
    )
    _benchmark_mimo()
    _benchmark_nr_ldpc()
    _benchmark_wifi_bcc()
    _benchmark_wifi_ldpc()
    _benchmark_seeded_link()
