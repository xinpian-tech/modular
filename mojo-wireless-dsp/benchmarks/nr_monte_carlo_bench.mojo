"""Retained CPU latency for the NR PUSCH Monte-Carlo runner."""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.testing import (
    SNR_ESN0_DATA,
    SNR_EBN0_INFORMATION,
    NR_LINK_CHANNEL_AWGN,
    NR_LINK_CHANNEL_TDL_A,
    NR_LINK_CHANNEL_TDL_C,
    NR_LINK_CHANNEL_TDL_D,
    LinkSNRPoint,
    MonteCarloStop,
    NRPUSCHLinkSetup,
    NRPUSCHLinkPoint,
    simulate_nr_pusch_trials,
    simulate_nr_pusch_case,
    simulate_nr_pusch_sweep,
)
from wireless_dsp.wireless.nr.mcs_tbs import NR_MCS_TABLE_QAM64
from wireless_dsp.wireless.nr.pusch_chain import NRPUSCHConfig


comptime _WARMUPS = 3
comptime _REPETITIONS = 9


def _setup() raises -> NRPUSCHLinkSetup:
    return NRPUSCHLinkSetup(
        NRPUSCHConfig(
            64,
            8,
            5,
            2,
            8,
            2,
            3,
            17,
            1,
            0x1234,
        ),
        NR_MCS_TABLE_QAM64,
        subcarrier_spacing_hz=30000.0,
        tdl_delay_spread_ns=300.0,
        max_iterations=30,
    )


def _point_checksum(point: NRPUSCHLinkPoint) -> UInt64:
    var counters = point.result.counters
    return (
        UInt64(point.transport_block_size)
        ^ (UInt64(counters.bit_errors) << 7)
        ^ (UInt64(counters.transport_block_errors) << 23)
        ^ (UInt64(counters.convergence_failures) << 31)
        ^ UInt64(counters.evm_error_energy * 1.0e12)
        ^ (UInt64(counters.evm_reference_energy * 1.0e9) << 1)
    )


@no_inline
def _simulate_nr_pusch_trials_workload(
    setup: NRPUSCHLinkSetup,
    snr: LinkSNRPoint,
    seed: UInt64,
) raises -> NRPUSCHLinkPoint:
    return simulate_nr_pusch_trials(
        setup,
        4,
        snr,
        UInt64(18000),
        NR_LINK_CHANNEL_AWGN,
        UInt64(17),
        seed,
        UInt64(0),
        1,
    )


@no_inline
def _simulate_nr_pusch_case_workload(
    setup: NRPUSCHLinkSetup,
    snr: LinkSNRPoint,
    seed: UInt64,
    stop: MonteCarloStop,
) raises -> NRPUSCHLinkPoint:
    return simulate_nr_pusch_case(
        setup,
        4,
        snr,
        UInt64(18000),
        NR_LINK_CHANNEL_AWGN,
        UInt64(29),
        seed,
        stop,
    )


@no_inline
def _simulate_nr_pusch_sweep_workload(
    setup: NRPUSCHLinkSetup,
    mcs_indices: Span[Int, ...],
    snrs: Span[LinkSNRPoint, ...],
    snr_ids: Span[UInt64, ...],
    channels: Span[Int, ...],
    channel_seeds: Span[UInt64, ...],
    stop: MonteCarloStop,
) raises -> List[NRPUSCHLinkPoint]:
    return simulate_nr_pusch_sweep(
        setup,
        mcs_indices,
        snrs,
        snr_ids,
        channels,
        channel_seeds,
        UInt64(0x7D10_0000),
        stop,
    )


def benchmark_nr_pusch_awgn_trial() raises -> UInt64:
    var setup = _setup()
    var snr = LinkSNRPoint(SNR_ESN0_DATA, 18.0)
    comptime seed = UInt64(0xA6A0_0001)
    for _ in range(_WARMUPS):
        keep(_simulate_nr_pusch_trials_workload(setup, snr, seed))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _simulate_nr_pusch_trials_workload(setup, snr, seed)
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= _point_checksum(result) + UInt64(repetition)
        checksum *= UInt64(1099511628211)
    report_timing_samples(
        "nr_pusch_monte_carlo_awgn",
        samples,
        _WARMUPS,
        1,
        "transport_block",
    )
    print("nr_pusch_monte_carlo_awgn_checksum:", checksum)
    return checksum


def benchmark_nr_pusch_stopped_case() raises -> UInt64:
    var setup = _setup()
    var snr = LinkSNRPoint(SNR_ESN0_DATA, 18.0)
    var stop = MonteCarloStop(min_trials=1, max_trials=1)
    comptime seed = UInt64(0xCA5E_0001)
    for _ in range(_WARMUPS):
        keep(_simulate_nr_pusch_case_workload(setup, snr, seed, stop))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _simulate_nr_pusch_case_workload(
            setup, snr, seed, stop
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= (
            _point_checksum(result)
            ^ UInt64(result.result.stop_reason)
            ^ UInt64(repetition)
        )
        checksum *= UInt64(1099511628211)
    report_timing_samples(
        "nr_pusch_monte_carlo_stopped_case",
        samples,
        _WARMUPS,
        1,
        "transport_block",
    )
    print("nr_pusch_monte_carlo_case_checksum:", checksum)
    return checksum


def benchmark_nr_pusch_tdl_profile_sweep() raises -> UInt64:
    var setup = _setup()
    var mcs_indices: List[Int] = [4]
    var snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_EBN0_INFORMATION, 18.0)
    ]
    var snr_ids: List[UInt64] = [UInt64(18001)]
    var channels: List[Int] = [
        NR_LINK_CHANNEL_TDL_A,
        NR_LINK_CHANNEL_TDL_C,
        NR_LINK_CHANNEL_TDL_D,
    ]
    var channel_seeds: List[UInt64] = [UInt64(101)]
    var stop = MonteCarloStop(min_trials=1, max_trials=1)
    var mcs_span = Span(mcs_indices)
    var snr_span = Span(snrs)
    var snr_id_span = Span(snr_ids)
    var channel_span = Span(channels)
    var seed_span = Span(channel_seeds)
    for _ in range(_WARMUPS):
        keep(_simulate_nr_pusch_sweep_workload(
            setup,
            mcs_span,
            snr_span,
            snr_id_span,
            channel_span,
            seed_span,
            stop,
        ))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for repetition in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _simulate_nr_pusch_sweep_workload(
            setup,
            mcs_span,
            snr_span,
            snr_id_span,
            channel_span,
            seed_span,
            stop,
        )
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= UInt64(len(result))
        checksum ^= _point_checksum(result[0]) << 1
        checksum ^= _point_checksum(result[len(result) - 1]) << 3
        checksum ^= UInt64(repetition)
        checksum *= UInt64(1099511628211)
    report_timing_samples(
        "nr_pusch_monte_carlo_tdl_a_c_d",
        samples,
        _WARMUPS,
        3,
        "transport_block",
    )
    print("nr_pusch_monte_carlo_tdl_checksum:", checksum)
    return checksum


def main() raises:
    print_benchmark_metadata()
    var checksum = benchmark_nr_pusch_awgn_trial()
    checksum ^= benchmark_nr_pusch_stopped_case()
    checksum ^= benchmark_nr_pusch_tdl_profile_sweep()
    print("nr_pusch_monte_carlo_combined_checksum:", checksum)
