"""CPU latency distributions for the four acquired Wi-Fi link families."""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.testing.monte_carlo import (
    SNR_EBN0_INFORMATION,
    LinkSNRPoint,
    MonteCarloStop,
    LinkCounters,
)
from wireless_dsp.testing.wifi_monte_carlo import (
    WIFI_LINK_CHANNEL_TGN,
    WIFI_LINK_CHANNEL_TGAC,
    WIFI_LINK_CHANNEL_TGAX,
    WifiLinkSetup,
    WifiPacketTrial,
    WifiLinkPoint,
    simulate_wifi_packet_trial,
    simulate_wifi_trials,
    simulate_wifi_case,
    simulate_wifi_sweep,
)
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
)


comptime _WARMUPS = 3
comptime _REPETITIONS = 9
comptime _MASTER = UInt64(0x8021_1A5E_BEEF_2026)


@no_inline
def _workload_simulate_wifi_packet_trial(
    setup: WifiLinkSetup, snr: LinkSNRPoint,
) raises -> WifiPacketTrial:
    return simulate_wifi_packet_trial(
        setup,
        snr,
        snr_identity=UInt64(13500),
        channel_seed_identity=UInt64(101),
        trial_index=UInt64(31),
        master_seed=_MASTER,
    )


@no_inline
def _workload_simulate_wifi_trials(
    setup: WifiLinkSetup, snr: LinkSNRPoint,
) raises -> LinkCounters:
    return simulate_wifi_trials(
        setup, snr, 2, snr_identity=UInt64(13500),
        channel_seed_identity=UInt64(101), first_trial=UInt64(200),
        master_seed=_MASTER,
    )


@no_inline
def _workload_simulate_wifi_case(
    setup: WifiLinkSetup, snr: LinkSNRPoint, policy: MonteCarloStop,
) raises -> WifiLinkPoint:
    return simulate_wifi_case(
        setup, snr, policy, snr_identity=UInt64(13500),
        channel_seed_identity=UInt64(101), first_trial=UInt64(400),
        master_seed=_MASTER,
    )


@no_inline
def _workload_simulate_wifi_sweep(
    setups: Span[WifiLinkSetup, ...], snrs: Span[LinkSNRPoint, ...],
    snr_ids: Span[UInt64, ...], channel_seeds: Span[UInt64, ...],
    policy: MonteCarloStop,
) raises -> List[WifiLinkPoint]:
    return simulate_wifi_sweep(
        setups, snrs, snr_ids, channel_seeds, policy, master_seed=_MASTER
    )


def _benchmark_family(label: StringSlice, setup: WifiLinkSetup) raises -> UInt64:
    var snr = LinkSNRPoint(SNR_EBN0_INFORMATION, 35.0)
    for _ in range(_WARMUPS):
        keep(_workload_simulate_wifi_packet_trial(setup, snr))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var trial = _workload_simulate_wifi_packet_trial(setup, snr)
        samples.append(global_perf_counter_ns() - start)
        keep(trial)
        checksum ^= (
            trial.payload_seed
            ^ (trial.channel_seed << 7)
            ^ UInt64(trial.counters.bit_errors)
        )
        checksum *= UInt64(1099511628211)
    report_timing_samples(
        label, samples, _WARMUPS, 1, "acquired_packet_trial"
    )
    print(label, "_checksum:", checksum, sep="")
    return checksum


def benchmark_wifi_ht_mcs6_tgn() raises -> UInt64:
    return _benchmark_family(
        "wifi_monte_carlo_ht6_tgn_b",
        WifiLinkSetup(
            WIFI_PHY_HT,
            6,
            9,
            WIFI_LINK_CHANNEL_TGN,
            channel_model=1,
            maximum_timing_offset=0,
            maximum_abs_cfo=0.0,
        ),
    )


def benchmark_wifi_vht_mcs8_tgac() raises -> UInt64:
    return _benchmark_family(
        "wifi_monte_carlo_vht8_tgac_b",
        WifiLinkSetup(
            WIFI_PHY_VHT,
            8,
            9,
            WIFI_LINK_CHANNEL_TGAC,
            channel_model=1,
            maximum_timing_offset=0,
            maximum_abs_cfo=0.0,
        ),
    )


def benchmark_wifi_he_mcs10_tgax() raises -> UInt64:
    return _benchmark_family(
        "wifi_monte_carlo_he10_tgax_b",
        WifiLinkSetup(
            WIFI_PHY_HE,
            10,
            205,
            WIFI_LINK_CHANNEL_TGAX,
            channel_model=1,
            maximum_timing_offset=0,
            maximum_abs_cfo=0.0,
            max_iterations=20,
        ),
    )


def benchmark_wifi_eht_mcs13_tgax() raises -> UInt64:
    return _benchmark_family(
        "wifi_monte_carlo_eht13_tgax_b",
        WifiLinkSetup(
            WIFI_PHY_EHT,
            13,
            264,
            WIFI_LINK_CHANNEL_TGAX,
            channel_model=1,
            maximum_timing_offset=0,
            maximum_abs_cfo=0.0,
            max_iterations=20,
        ),
    )


def benchmark_wifi_trial_shard_api() raises -> UInt64:
    var setup = WifiLinkSetup(
        WIFI_PHY_HT,
        6,
        9,
        WIFI_LINK_CHANNEL_TGN,
        maximum_timing_offset=0,
        maximum_abs_cfo=0.0,
    )
    var snr = LinkSNRPoint(SNR_EBN0_INFORMATION, 35.0)
    for _ in range(_WARMUPS):
        keep(_workload_simulate_wifi_trials(setup, snr))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var counters = _workload_simulate_wifi_trials(setup, snr)
        samples.append(global_perf_counter_ns() - start)
        keep(counters)
        checksum ^= UInt64(counters.bit_errors)
        checksum *= UInt64(1099511628211)
        checksum ^= UInt64(counters.packet_errors)
    report_timing_samples(
        "wifi_monte_carlo_trial_shard",
        samples,
        _WARMUPS,
        2,
        "acquired_packet_trial",
    )
    print("wifi_monte_carlo_trial_shard_checksum:", checksum)
    return checksum


def benchmark_wifi_stopped_case_api() raises -> UInt64:
    var setup = WifiLinkSetup(
        WIFI_PHY_HT,
        6,
        9,
        WIFI_LINK_CHANNEL_TGN,
        maximum_timing_offset=0,
        maximum_abs_cfo=0.0,
    )
    var snr = LinkSNRPoint(SNR_EBN0_INFORMATION, 35.0)
    var policy = MonteCarloStop(min_trials=2, max_trials=2)
    for _ in range(_WARMUPS):
        keep(_workload_simulate_wifi_case(setup, snr, policy))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var point = _workload_simulate_wifi_case(setup, snr, policy)
        samples.append(global_perf_counter_ns() - start)
        keep(point)
        checksum ^= UInt64(point.counters.bit_errors)
        checksum *= UInt64(1099511628211)
        checksum ^= UInt64(point.stop_reason)
    report_timing_samples(
        "wifi_monte_carlo_stopped_case",
        samples,
        _WARMUPS,
        2,
        "acquired_packet_trial",
    )
    print("wifi_monte_carlo_stopped_case_checksum:", checksum)
    return checksum


def benchmark_wifi_cartesian_sweep_api() raises -> UInt64:
    var setups: List[WifiLinkSetup] = [WifiLinkSetup(
        WIFI_PHY_HT,
        6,
        9,
        WIFI_LINK_CHANNEL_TGN,
        maximum_timing_offset=0,
        maximum_abs_cfo=0.0,
    )]
    var snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_EBN0_INFORMATION, 35.0)
    ]
    var snr_ids: List[UInt64] = [UInt64(13500)]
    var channel_seeds: List[UInt64] = [UInt64(101)]
    var policy = MonteCarloStop(min_trials=1, max_trials=1)
    var setups_span = Span(setups)
    var snrs_span = Span(snrs)
    var snr_ids_span = Span(snr_ids)
    var channel_seeds_span = Span(channel_seeds)
    for _ in range(_WARMUPS):
        keep(_workload_simulate_wifi_sweep(
            setups_span, snrs_span, snr_ids_span, channel_seeds_span, policy
        ))
    var samples = List[UInt64](capacity=_REPETITIONS)
    var checksum = UInt64(14695981039346656037)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var points = _workload_simulate_wifi_sweep(
            setups_span, snrs_span, snr_ids_span, channel_seeds_span, policy
        )
        samples.append(global_perf_counter_ns() - start)
        keep(points)
        checksum ^= UInt64(points[0].counters.bit_errors)
        checksum *= UInt64(1099511628211)
        checksum ^= UInt64(points[0].stop_reason)
    report_timing_samples(
        "wifi_monte_carlo_cartesian_sweep",
        samples,
        _WARMUPS,
        1,
        "link_point",
    )
    print("wifi_monte_carlo_cartesian_sweep_checksum:", checksum)
    return checksum


def main() raises:
    print_benchmark_metadata()
    var checksum = benchmark_wifi_ht_mcs6_tgn()
    checksum ^= benchmark_wifi_trial_shard_api()
    checksum ^= benchmark_wifi_stopped_case_api()
    checksum ^= benchmark_wifi_cartesian_sweep_api()
    print("wifi_monte_carlo_combined_checksum:", checksum)
