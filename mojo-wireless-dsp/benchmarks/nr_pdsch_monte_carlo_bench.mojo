"""Retained CPU latency for PDSCH packet and TDL Monte-Carlo paths."""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.testing.monte_carlo import (
    SNR_ESN0_DATA,
    SNR_EBN0_INFORMATION,
    LinkSNRPoint,
    MonteCarloStop,
)
from wireless_dsp.testing.nr_monte_carlo import (
    NR_LINK_CHANNEL_AWGN,
    NR_LINK_CHANNEL_TDL_A,
    NR_LINK_CHANNEL_TDL_C,
    NR_LINK_CHANNEL_TDL_D,
)
from wireless_dsp.testing.nr_pdsch_monte_carlo import (
    NRPDSCHLinkSetup,
    NRPDSCHPacketTrial,
    NRPDSCHLinkPoint,
    simulate_nr_pdsch_packet_trial,
    simulate_nr_pdsch_trials,
    simulate_nr_pdsch_case,
    simulate_nr_pdsch_sweep,
)
from wireless_dsp.wireless.nr.grid import (
    NRResourceGrid,
    nr_pdsch_dmrs_c_init,
    nr_map_pdsch_comb2,
)
from wireless_dsp.wireless.nr.pdsch import nr_pdsch_dmrs
from wireless_dsp.wireless.nr.ldpc_profile import NRLDPCProfile
from wireless_dsp.wireless.nr.mcs_tbs import (
    NR_MCS_TABLE_QAM64,
    nr_mcs_profile,
    nr_mcs_target_code_rate,
)
from wireless_dsp.wireless.nr.pdsch_chain import (
    NRPDSCHWaveformConfig,
    NRPDSCHDecodeResult,
    nr_pdsch_grid_to_waveform,
    nr_pdsch_waveform_to_grid,
    nr_pdsch_encode_transport_block,
    nr_pdsch_decode_waveform_comb2,
)


comptime _WARMUPS = 3
comptime _REPETITIONS = 9


@no_inline
def _workload_simulate_nr_pdsch_packet_trial(
    setup: NRPDSCHLinkSetup, snr: LinkSNRPoint,
) raises -> NRPDSCHPacketTrial:
    return simulate_nr_pdsch_packet_trial(
        setup, 4, snr,
        snr_identity=UInt64(18000), channel_model=NR_LINK_CHANNEL_AWGN,
        channel_seed_identity=UInt64(17), trial_index=UInt64(31),
        master_seed=UInt64(0xA6A0_1000),
    )


@no_inline
def _workload_nr_pdsch_grid_to_waveform(
    config: NRPDSCHWaveformConfig, grid: NRResourceGrid,
) raises -> List[Complex64]:
    return nr_pdsch_grid_to_waveform(config, grid)


@no_inline
def _workload_nr_pdsch_waveform_to_grid(
    config: NRPDSCHWaveformConfig, waveform: Span[Complex64, ...],
) raises -> NRResourceGrid:
    return nr_pdsch_waveform_to_grid(config, waveform)


@no_inline
def _workload_nr_pdsch_decode_waveform_comb2(
    waveform: Span[Complex64, ...], config: NRPDSCHWaveformConfig,
    null_mask: Span[UInt8, ...], profile: NRLDPCProfile,
    payload_bits: Int, modulation_order: Int,
) raises -> NRPDSCHDecodeResult:
    return nr_pdsch_decode_waveform_comb2(
        waveform, config, null_mask, profile, payload_bits,
        modulation_order, 0, 1.0e-6,
    )


@no_inline
def _workload_simulate_nr_pdsch_trials(
    setup: NRPDSCHLinkSetup, snr: LinkSNRPoint,
) raises -> NRPDSCHLinkPoint:
    return simulate_nr_pdsch_trials(
        setup, 4, snr, UInt64(20001),
        NR_LINK_CHANNEL_TDL_C, UInt64(201), UInt64(0x7D10_1000), UInt64(0), 1,
    )


@no_inline
def _workload_simulate_nr_pdsch_case(
    setup: NRPDSCHLinkSetup, snr: LinkSNRPoint, policy: MonteCarloStop,
) raises -> NRPDSCHLinkPoint:
    return simulate_nr_pdsch_case(
        setup, 4, snr, UInt64(20001),
        NR_LINK_CHANNEL_TDL_D, UInt64(301), UInt64(0x7D10_1000), policy,
    )


@no_inline
def _workload_simulate_nr_pdsch_sweep(
    setup: NRPDSCHLinkSetup, mcs: Span[Int, ...], snrs: Span[LinkSNRPoint, ...],
    snr_ids: Span[UInt64, ...], channels: Span[Int, ...],
    channel_seeds: Span[UInt64, ...], policy: MonteCarloStop,
) raises -> List[NRPDSCHLinkPoint]:
    return simulate_nr_pdsch_sweep(
        setup, mcs, snrs, snr_ids, channels, channel_seeds,
        UInt64(0x7D10_1000), policy,
    )


def _setup() raises -> NRPDSCHLinkSetup:
    return NRPDSCHLinkSetup(
        NRPDSCHWaveformConfig(
            512,
            36,
            32,
            24,
            3,
            2,
            42,
            0,
            0,
            0x1234,
        ),
        NR_MCS_TABLE_QAM64,
        subcarrier_spacing_hz=30000.0,
        tdl_delay_spread_ns=100.0,
        max_iterations=30,
    )


def _trial_checksum(trial: NRPDSCHPacketTrial) -> UInt64:
    return (
        UInt64(trial.allocation.transport_block_size)
        ^ (UInt64(trial.counters.bit_errors) << 7)
        ^ (UInt64(trial.counters.transport_block_errors) << 23)
        ^ (UInt64(trial.counters.convergence_failures) << 31)
        ^ UInt64(trial.counters.evm_error_energy * 1.0e12)
        ^ (UInt64(trial.counters.evm_reference_energy * 1.0e9) << 1)
    )


def _point_checksum(point: NRPDSCHLinkPoint) -> UInt64:
    return (
        UInt64(point.allocation.transport_block_size)
        ^ (UInt64(point.result.counters.bit_errors) << 7)
        ^ (UInt64(point.result.counters.transport_block_errors) << 23)
        ^ UInt64(point.result.counters.evm_error_energy * 1.0e12)
    )


def _awgn_workload() raises -> UInt64:
    var trial = _workload_simulate_nr_pdsch_packet_trial(
        _setup(), LinkSNRPoint(SNR_ESN0_DATA, 18.0)
    )
    return _trial_checksum(trial)


def benchmark_nr_pdsch_awgn_packet() raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_awgn_workload())
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _awgn_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= result
        checksum *= UInt64(1099511628211)
    report_timing_samples(
        "nr_pdsch_monte_carlo_awgn",
        samples,
        _WARMUPS,
        1,
        "transport_block",
    )
    print("nr_pdsch_monte_carlo_awgn_checksum:", checksum)
    return checksum


def _waveform_rx_workload() raises -> UInt64:
    var setup = _setup()
    var mcs = nr_mcs_profile(NR_MCS_TABLE_QAM64, 4)
    var allocation = setup.allocation(4)
    var payload = List[UInt8](capacity=allocation.transport_block_size)
    for index in range(allocation.transport_block_size):
        payload.append(UInt8((13 * index + 7) & 1))
    var transmit = nr_pdsch_encode_transport_block(
        Span(payload),
        nr_mcs_target_code_rate(mcs),
        mcs.modulation_order,
        0,
        setup.waveform.coded_bit_capacity(mcs.modulation_order),
        setup.waveform.rnti,
        setup.waveform.codeword,
        setup.waveform.n_id,
    )
    var dmrs = nr_pdsch_dmrs(
        nr_pdsch_dmrs_c_init(3, 2, 42, 0),
        setup.waveform.dmrs_re_count(),
    )
    var grid = NRResourceGrid(1, setup.waveform.fft_size)
    nr_map_pdsch_comb2(
        grid,
        0,
        setup.waveform.first_subcarrier,
        setup.waveform.allocation_subcarriers(),
        setup.waveform.dmrs_offset,
        Span(transmit.symbols),
        Span(dmrs),
    )
    var waveform = _workload_nr_pdsch_grid_to_waveform(setup.waveform, grid)
    var recovered = _workload_nr_pdsch_waveform_to_grid(
        setup.waveform, Span(waveform)
    )
    var decoded = _workload_nr_pdsch_decode_waveform_comb2(
        Span(waveform),
        setup.waveform,
        Span(transmit.encoded_null_mask),
        transmit.profile,
        allocation.transport_block_size,
        mcs.modulation_order,
    )
    return (
        UInt64(len(waveform))
        ^ (UInt64(recovered.subcarrier_count) << 13)
        ^ (UInt64(len(decoded.payload)) << 29)
        ^ UInt64(abs(decoded.demapper_llrs[0]) * 1.0e-3)
    )


def benchmark_nr_pdsch_waveform_rx() raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_waveform_rx_workload())
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _waveform_rx_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= result
        checksum *= UInt64(1099511628211)
    report_timing_samples(
        "nr_pdsch_waveform_rx",
        samples,
        _WARMUPS,
        3,
        "waveform_api",
    )
    print("nr_pdsch_waveform_rx_checksum:", checksum)
    return checksum


def _tdl_workload() raises -> UInt64:
    var mcs_indices: List[Int] = [4]
    var snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_EBN0_INFORMATION, 20.0)
    ]
    var snr_ids: List[UInt64] = [UInt64(20001)]
    var channels: List[Int] = [
        NR_LINK_CHANNEL_TDL_A,
        NR_LINK_CHANNEL_TDL_C,
        NR_LINK_CHANNEL_TDL_D,
    ]
    var channel_seeds: List[UInt64] = [UInt64(101)]
    var setup = _setup()
    var policy = MonteCarloStop(min_trials=1, max_trials=1)
    var points = _workload_simulate_nr_pdsch_sweep(
        setup,
        Span(mcs_indices),
        Span(snrs),
        Span(snr_ids),
        Span(channels),
        Span(channel_seeds),
        policy,
    )
    var shard = _workload_simulate_nr_pdsch_trials(setup, snrs[0])
    var stopped = _workload_simulate_nr_pdsch_case(setup, snrs[0], policy)
    var checksum = UInt64(14695981039346656037)
    for index in range(len(points)):
        checksum ^= _point_checksum(points[index])
        checksum *= UInt64(1099511628211)
    checksum ^= _point_checksum(shard)
    checksum *= UInt64(1099511628211)
    checksum ^= _point_checksum(stopped)
    checksum *= UInt64(1099511628211)
    return checksum


def benchmark_nr_pdsch_tdl_profile_sweep() raises -> UInt64:
    for _ in range(_WARMUPS):
        keep(_tdl_workload())
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var result = _tdl_workload()
        samples.append(global_perf_counter_ns() - start)
        keep(result)
        checksum ^= result
        checksum *= UInt64(1099511628211)
    report_timing_samples(
        "nr_pdsch_monte_carlo_tdl_a_c_d",
        samples,
        _WARMUPS,
        5,
        "transport_block",
    )
    print("nr_pdsch_monte_carlo_tdl_checksum:", checksum)
    return checksum


def _report_api(name: StringSlice, mut samples: List[UInt64]) raises:
    report_timing_samples(name, samples, _WARMUPS, 1, "api_call")


def main() raises:
    print_benchmark_metadata()
    # Build and validate every owned fixture before the first timer starts.
    var setup = _setup()
    var mcs = nr_mcs_profile(NR_MCS_TABLE_QAM64, 4)
    var allocation = setup.allocation(4)
    var payload = List[UInt8](capacity=allocation.transport_block_size)
    for index in range(allocation.transport_block_size):
        payload.append(UInt8((13 * index + 7) & 1))
    var payload_span = Span(payload)
    var transmit = nr_pdsch_encode_transport_block(
        payload_span,
        nr_mcs_target_code_rate(mcs),
        mcs.modulation_order,
        0,
        setup.waveform.coded_bit_capacity(mcs.modulation_order),
        setup.waveform.rnti,
        setup.waveform.codeword,
        setup.waveform.n_id,
    )
    var dmrs = nr_pdsch_dmrs(
        nr_pdsch_dmrs_c_init(3, 2, 42, 0),
        setup.waveform.dmrs_re_count(),
    )
    var grid = NRResourceGrid(1, setup.waveform.fft_size)
    nr_map_pdsch_comb2(
        grid,
        0,
        setup.waveform.first_subcarrier,
        setup.waveform.allocation_subcarriers(),
        setup.waveform.dmrs_offset,
        Span(transmit.symbols),
        Span(dmrs),
    )
    var waveform = _workload_nr_pdsch_grid_to_waveform(setup.waveform, grid)
    var waveform_span = Span(waveform)
    var null_mask_span = Span(transmit.encoded_null_mask)
    var mcs_indices: List[Int] = [4]
    var snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_EBN0_INFORMATION, 20.0)
    ]
    var snr_ids: List[UInt64] = [UInt64(20001)]
    var channels: List[Int] = [
        NR_LINK_CHANNEL_TDL_A,
        NR_LINK_CHANNEL_TDL_C,
        NR_LINK_CHANNEL_TDL_D,
    ]
    var channel_seeds: List[UInt64] = [UInt64(101)]
    var mcs_indices_span = Span(mcs_indices)
    var snrs_span = Span(snrs)
    var snr_ids_span = Span(snr_ids)
    var channels_span = Span(channels)
    var channel_seeds_span = Span(channel_seeds)
    var policy = MonteCarloStop(min_trials=1, max_trials=1)
    var packet_snr = LinkSNRPoint(SNR_ESN0_DATA, 18.0)
    var trial_snr = LinkSNRPoint(SNR_EBN0_INFORMATION, 20.0)

    for _ in range(_WARMUPS):
        keep(_workload_nr_pdsch_grid_to_waveform(setup.waveform, grid))
        keep(_workload_nr_pdsch_waveform_to_grid(setup.waveform, waveform_span))
        keep(_workload_nr_pdsch_decode_waveform_comb2(
            waveform_span,
            setup.waveform,
            null_mask_span,
            transmit.profile,
            allocation.transport_block_size,
            mcs.modulation_order,
        ))
        keep(_workload_simulate_nr_pdsch_packet_trial(setup, packet_snr))
        keep(_workload_simulate_nr_pdsch_trials(setup, trial_snr))
        keep(_workload_simulate_nr_pdsch_case(setup, trial_snr, policy))
        keep(_workload_simulate_nr_pdsch_sweep(
            setup,
            mcs_indices_span,
            snrs_span,
            snr_ids_span,
            channels_span,
            channel_seeds_span,
            policy,
        ))

    var grid_to_waveform_samples = List[UInt64](capacity=_REPETITIONS)
    var waveform_to_grid_samples = List[UInt64](capacity=_REPETITIONS)
    var decode_samples = List[UInt64](capacity=_REPETITIONS)
    var packet_samples = List[UInt64](capacity=_REPETITIONS)
    var trials_samples = List[UInt64](capacity=_REPETITIONS)
    var case_samples = List[UInt64](capacity=_REPETITIONS)
    var sweep_samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var r0 = _workload_nr_pdsch_grid_to_waveform(setup.waveform, grid)
        grid_to_waveform_samples.append(global_perf_counter_ns() - start)
        keep(r0)
        checksum ^= UInt64(len(r0)) ^ UInt64(r0[0].magnitude_squared() * 1.0e9)
        checksum *= UInt64(1099511628211)

        start = global_perf_counter_ns()
        var r1 = _workload_nr_pdsch_waveform_to_grid(setup.waveform, waveform_span)
        waveform_to_grid_samples.append(global_perf_counter_ns() - start)
        keep(r1)
        checksum ^= UInt64(r1.subcarrier_count)
        checksum *= UInt64(1099511628211)

        start = global_perf_counter_ns()
        var r2 = _workload_nr_pdsch_decode_waveform_comb2(
            waveform_span,
            setup.waveform,
            null_mask_span,
            transmit.profile,
            allocation.transport_block_size,
            mcs.modulation_order,
        )
        decode_samples.append(global_perf_counter_ns() - start)
        keep(r2)
        checksum ^= UInt64(len(r2.payload)) ^ UInt64(r2.ldpc_converged)
        checksum *= UInt64(1099511628211)

        start = global_perf_counter_ns()
        var r3 = _workload_simulate_nr_pdsch_packet_trial(setup, packet_snr)
        packet_samples.append(global_perf_counter_ns() - start)
        keep(r3)
        checksum ^= _trial_checksum(r3)
        checksum *= UInt64(1099511628211)

        start = global_perf_counter_ns()
        var r4 = _workload_simulate_nr_pdsch_trials(setup, trial_snr)
        trials_samples.append(global_perf_counter_ns() - start)
        keep(r4)
        checksum ^= _point_checksum(r4)
        checksum *= UInt64(1099511628211)

        start = global_perf_counter_ns()
        var r5 = _workload_simulate_nr_pdsch_case(setup, trial_snr, policy)
        case_samples.append(global_perf_counter_ns() - start)
        keep(r5)
        checksum ^= _point_checksum(r5)
        checksum *= UInt64(1099511628211)

        start = global_perf_counter_ns()
        var r6 = _workload_simulate_nr_pdsch_sweep(
            setup,
            mcs_indices_span,
            snrs_span,
            snr_ids_span,
            channels_span,
            channel_seeds_span,
            policy,
        )
        sweep_samples.append(global_perf_counter_ns() - start)
        keep(r6)
        checksum ^= UInt64(len(r6)) ^ _point_checksum(r6[0])
        checksum *= UInt64(1099511628211)

    _report_api("nr_pdsch_grid_to_waveform", grid_to_waveform_samples)
    _report_api("nr_pdsch_waveform_to_grid", waveform_to_grid_samples)
    _report_api("nr_pdsch_decode_waveform_comb2", decode_samples)
    _report_api("simulate_nr_pdsch_packet_trial", packet_samples)
    _report_api("simulate_nr_pdsch_trials", trials_samples)
    _report_api("simulate_nr_pdsch_case", case_samples)
    _report_api("simulate_nr_pdsch_sweep", sweep_samples)
    keep(checksum)
    print("nr_pdsch_monte_carlo_combined_checksum:", checksum)
