"""CPU evidence for acquired HT/VHT/HE/EHT Wi-Fi Monte-Carlo links."""

from std.collections import Span
from std.math import exp, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from std.utils.numerics import nan
from wireless_dsp.channel import (
    apply_standard_channel,
    wifi_tgn_profile,
    wifi_tgax_profile,
)
from wireless_dsp.testing.monte_carlo import (
    SNR_ESN0_DATA,
    SNR_EBN0_CODED,
    SNR_EBN0_INFORMATION,
    MONTE_CARLO_METRIC_BLER,
    MONTE_CARLO_METRIC_PER,
    MONTE_CARLO_STOP_MAX_TRIALS,
    LinkCounters,
    LinkSNRPoint,
    MonteCarloStop,
)
from wireless_dsp.testing.wifi_monte_carlo import (
    WIFI_LINK_CHANNEL_AWGN,
    WIFI_LINK_CHANNEL_TGN,
    WIFI_LINK_CHANNEL_TGAC,
    WIFI_LINK_CHANNEL_TGAX,
    WifiLinkSetup,
    simulate_wifi_packet_trial,
    simulate_wifi_trials,
    simulate_wifi_case,
    simulate_wifi_sweep,
)
from wireless_dsp.wireless.wifi.acquisition_chain import (
    wifi_acquisition_rx_20mhz,
    wifi_acquisition_tx_20mhz,
)
from wireless_dsp.wireless.wifi.phy_chain import (
    wifi_ht_vht_data_subcarriers_20mhz,
)
from wireless_dsp.wireless.wifi.he_eht_acquisition import (
    wifi_he_eht_acquisition_rx_20mhz,
    wifi_he_eht_acquisition_tx_20mhz,
)
from wireless_dsp.wireless.wifi.resources import (
    wifi_ru_data_subcarriers_20mhz,
)
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
)


comptime _MASTER = UInt64(0x8021_1A5E_CAFE_2026)


def _assert_counters_equal(lhs: LinkCounters, rhs: LinkCounters) raises:
    assert_equal(lhs.bit_count, rhs.bit_count)
    assert_equal(lhs.bit_errors, rhs.bit_errors)
    assert_equal(lhs.packet_count, rhs.packet_count)
    assert_equal(lhs.packet_errors, rhs.packet_errors)
    assert_equal(lhs.fcs_check_count, rhs.fcs_check_count)
    assert_equal(lhs.fcs_failures, rhs.fcs_failures)
    assert_equal(lhs.decoder_attempt_count, rhs.decoder_attempt_count)
    assert_equal(lhs.convergence_failures, rhs.convergence_failures)
    assert_equal(lhs.evm_observation_count, rhs.evm_observation_count)
    assert_equal(lhs.evm_error_energy, rhs.evm_error_energy)
    assert_equal(lhs.evm_reference_energy, rhs.evm_reference_energy)


def _setup(
    family: Int,
    mcs: Int,
    octets: Int,
    channel: Int,
    *,
    threshold: Float64 = 0.72,
) raises -> WifiLinkSetup:
    return WifiLinkSetup(
        family,
        mcs,
        octets,
        channel,
        channel_model=1,
        maximum_timing_offset=0,
        maximum_abs_cfo=0.0,
        detection_threshold=threshold,
        max_iterations=20,
    )


def test_all_four_required_phy_profiles_run_real_service_fec_and_fcs() raises:
    # Representative payloads include each chain's actual SERVICE and FCS.
    # HE/EHT use the established two-codeword RU-242 payload geometries.
    var setups = List[WifiLinkSetup](capacity=4)
    setups.append(_setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_TGN))
    setups.append(_setup(WIFI_PHY_VHT, 8, 9, WIFI_LINK_CHANNEL_TGAC))
    setups.append(_setup(WIFI_PHY_HE, 10, 205, WIFI_LINK_CHANNEL_TGAX))
    setups.append(_setup(WIFI_PHY_EHT, 13, 264, WIFI_LINK_CHANNEL_TGAX))
    var snr = LinkSNRPoint(SNR_EBN0_INFORMATION, 80.0)
    for index in range(len(setups)):
        var trial = simulate_wifi_packet_trial(
            setups[index],
            snr,
            snr_identity=UInt64(18000),
            channel_seed_identity=UInt64(71 + index),
            trial_index=UInt64(0),
            master_seed=_MASTER,
        )
        assert_true(not trial.acquisition_erasure)
        assert_true(trial.signal_ok)
        assert_true(trial.service_ok)
        assert_true(trial.fcs_ok)
        assert_true(trial.decoder_converged)
        assert_equal(trial.bit_errors, 0)
        assert_equal(trial.counters.packet_errors, 0)
        assert_equal(trial.counters.fcs_failures, 0)
        assert_true(trial.per_tone_llr_reliability)
        assert_true(trial.counters.evm_reference_energy > 0.0)

    # AWGN is a separate, non-fading sample-domain mode and does not request
    # per-tone weighting because every H[k] is unity.
    var awgn = simulate_wifi_packet_trial(
        _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN),
        snr,
        snr_identity=UInt64(18000),
        channel_seed_identity=UInt64(9),
        trial_index=UInt64(0),
        master_seed=_MASTER,
    )
    assert_true(awgn.fcs_ok)
    assert_true(not awgn.per_tone_llr_reliability)


def test_pre_channel_exact_energy_and_fft_noise_composition_oracle() raises:
    var db = 10.0
    var trial = simulate_wifi_packet_trial(
        _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN),
        LinkSNRPoint(SNR_EBN0_INFORMATION, db),
        snr_identity=UInt64(11000),
        channel_seed_identity=UInt64(4),
        trial_index=UInt64(3),
        master_seed=_MASTER,
    )
    var independent_n0 = (
        trial.pre_channel_waveform_energy / Float64(trial.payload_bit_count)
        * exp(-0.2302585092994045684 * db)
    )
    assert_almost_equal(
        trial.sample_noise_variance,
        independent_n0,
        atol=0.0,
        rtol=2.0e-14,
    )
    # IFFT has 1/N and FFT is unnormalised: time-domain N0 becomes N*N0.
    assert_equal(
        trial.frequency_bin_noise_variance,
        64.0 * trial.sample_noise_variance,
    )
    assert_equal(trial.pre_channel_sample_count, 400)

    var es_trial = simulate_wifi_packet_trial(
        _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN),
        LinkSNRPoint(SNR_ESN0_DATA, db),
        snr_identity=UInt64(11001),
        channel_seed_identity=UInt64(4),
        trial_index=UInt64(3),
        master_seed=_MASTER,
    )
    var gamma_inverse = exp(-0.2302585092994045684 * db)
    assert_almost_equal(
        es_trial.frequency_bin_noise_variance,
        es_trial.data_symbol_energy * gamma_inverse,
        atol=0.0,
        rtol=2.0e-14,
    )
    assert_almost_equal(
        es_trial.sample_noise_variance,
        es_trial.frequency_bin_noise_variance / 64.0,
        atol=0.0,
        rtol=2.0e-14,
    )

    var coded_eb_trial = simulate_wifi_packet_trial(
        _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN),
        LinkSNRPoint(SNR_EBN0_CODED, db),
        snr_identity=UInt64(11002),
        channel_seed_identity=UInt64(4),
        trial_index=UInt64(3),
        master_seed=_MASTER,
    )
    assert_almost_equal(
        coded_eb_trial.frequency_bin_noise_variance,
        coded_eb_trial.data_symbol_energy
            / Float64(coded_eb_trial.bits_per_symbol)
            * gamma_inverse,
        atol=0.0,
        rtol=2.0e-14,
    )
    assert_almost_equal(
        coded_eb_trial.sample_noise_variance,
        coded_eb_trial.frequency_bin_noise_variance / 64.0,
        atol=0.0,
        rtol=2.0e-14,
    )


def test_semantic_seeds_are_order_and_shard_stable() raises:
    var setup = _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN)
    var snr = LinkSNRPoint(SNR_EBN0_INFORMATION, 35.0)
    var first = simulate_wifi_packet_trial(
        setup,
        snr,
        snr_identity=UInt64(13500),
        channel_seed_identity=UInt64(77),
        trial_index=UInt64(5),
        master_seed=_MASTER,
    )
    # Interleave a different semantic coordinate, then replay the first.
    _ = simulate_wifi_packet_trial(
        setup,
        snr,
        snr_identity=UInt64(13500),
        channel_seed_identity=UInt64(78),
        trial_index=UInt64(1),
        master_seed=_MASTER,
    )
    var replay = simulate_wifi_packet_trial(
        setup,
        snr,
        snr_identity=UInt64(13500),
        channel_seed_identity=UInt64(77),
        trial_index=UInt64(5),
        master_seed=_MASTER,
    )
    assert_equal(first.payload_seed, replay.payload_seed)
    assert_equal(first.channel_seed, replay.channel_seed)
    assert_equal(first.noise_seed, replay.noise_seed)
    assert_equal(first.impairment_seed, replay.impairment_seed)
    assert_true(first.payload_seed != first.channel_seed)
    assert_true(first.channel_seed != first.noise_seed)
    assert_true(first.noise_seed != first.impairment_seed)
    _assert_counters_equal(first.counters, replay.counters)

    var whole = simulate_wifi_trials(
        setup,
        snr,
        3,
        snr_identity=UInt64(13500),
        channel_seed_identity=UInt64(77),
        first_trial=UInt64(20),
        master_seed=_MASTER,
    )
    var left = simulate_wifi_trials(
        setup,
        snr,
        1,
        snr_identity=UInt64(13500),
        channel_seed_identity=UInt64(77),
        first_trial=UInt64(20),
        master_seed=_MASTER,
    )
    var right = simulate_wifi_trials(
        setup,
        snr,
        2,
        snr_identity=UInt64(13500),
        channel_seed_identity=UInt64(77),
        first_trial=UInt64(21),
        master_seed=_MASTER,
    )
    left.merge(right)
    _assert_counters_equal(whole, left)


def test_sweep_snr_axis_reordering_preserves_semantic_point_results() raises:
    var setup = _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN)
    var setups: List[WifiLinkSetup] = [setup]
    var snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_EBN0_INFORMATION, 30.0),
        LinkSNRPoint(SNR_EBN0_INFORMATION, 35.0),
    ]
    var snr_ids: List[UInt64] = [UInt64(13000), UInt64(13500)]
    var reversed_snrs: List[LinkSNRPoint] = [snrs[1], snrs[0]]
    var reversed_ids: List[UInt64] = [snr_ids[1], snr_ids[0]]
    var channel_seeds: List[UInt64] = [UInt64(19)]
    var policy = MonteCarloStop(min_trials=1, max_trials=1)
    var ordered = simulate_wifi_sweep(
        Span(setups),
        Span(snrs),
        Span(snr_ids),
        Span(channel_seeds),
        policy,
        master_seed=_MASTER,
    )
    var reversed = simulate_wifi_sweep(
        Span(setups),
        Span(reversed_snrs),
        Span(reversed_ids),
        Span(channel_seeds),
        policy,
        master_seed=_MASTER,
    )
    assert_equal(len(ordered), 2)
    assert_equal(ordered[0].snr_identity, reversed[1].snr_identity)
    assert_equal(ordered[1].snr_identity, reversed[0].snr_identity)
    _assert_counters_equal(ordered[0].counters, reversed[1].counters)
    _assert_counters_equal(ordered[1].counters, reversed[0].counters)


def test_low_snr_acquisition_erasure_has_explicit_upper_bound_ber_semantics() raises:
    # A unit detection threshold plus nonzero continuous noise cannot satisfy
    # the exact normalized-correlation equality, forcing a deterministic STF
    # erasure without relying on a particular erroneous decoded payload.
    var trial = simulate_wifi_packet_trial(
        _setup(
            WIFI_PHY_HT,
            6,
            9,
            WIFI_LINK_CHANNEL_AWGN,
            threshold=1.0,
        ),
        LinkSNRPoint(SNR_EBN0_INFORMATION, -40.0),
        snr_identity=UInt64(6000),
        channel_seed_identity=UInt64(1),
        trial_index=UInt64(0),
        master_seed=_MASTER,
    )
    assert_true(trial.acquisition_erasure)
    assert_equal(trial.payload_bit_count, 72)
    assert_equal(trial.bit_errors, 72)
    assert_equal(trial.counters.bit_count, 72)
    assert_equal(trial.counters.bit_errors, 72)
    assert_equal(trial.counters.packet_errors, 1)
    assert_equal(trial.counters.fcs_check_count, 1)
    assert_equal(trial.counters.fcs_failures, 1)
    assert_equal(trial.counters.decoder_attempt_count, 1)
    assert_equal(trial.counters.convergence_failures, 1)
    assert_equal(trial.counters.evm_reference_energy, 0.0)
    assert_equal(trial.counters.evm_observation_count, 0)
    with assert_raises():
        _ = trial.counters.evm_rms()


def test_frequency_selective_post_zf_llrs_use_each_tone_h_squared() raises:
    var payload = List[UInt8](length=72, fill=UInt8(0))
    for i in range(len(payload)):
        payload[i] = UInt8((7 * i + 3) & 1)
    var tx = wifi_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_HT, 6, symbol_index=4
    )
    var faded = apply_standard_channel(
        Span(tx.packet_waveform),
        wifi_tgn_profile(String("B")),
        20.0e6,
        seed=UInt64(0xB00B_1E55),
    )
    var scalar = wifi_acquisition_rx_20mhz(
        Span(faded),
        WIFI_PHY_HT,
        6,
        len(payload),
        symbol_index=4,
        detection_threshold=0.70,
        llr_noise_variance=1.0e-6,
        per_tone_llr_reliability=False,
    )
    var weighted = wifi_acquisition_rx_20mhz(
        Span(faded),
        WIFI_PHY_HT,
        6,
        len(payload),
        symbol_index=4,
        detection_threshold=0.70,
        llr_noise_variance=1.0e-6,
        per_tone_llr_reliability=True,
    )
    var tones = wifi_ht_vht_data_subcarriers_20mhz(WIFI_PHY_HT)
    for tone in range(len(tones)):
        var bin = tones[tone] if tones[tone] >= 0 else 64 + tones[tone]
        var reliability = weighted.channel_estimate[bin].magnitude_squared()
        for bit in range(6):
            var index = tone * 6 + bit
            assert_almost_equal(
                weighted.qam_llrs[index],
                scalar.qam_llrs[index] * reliability,
                atol=1.0e-10,
                rtol=2.0e-14,
            )
    assert_true(weighted.signal_ok and weighted.service_ok and weighted.fcs_ok)


def test_he_frequency_selective_signal_soft_path_and_data_tone_reliability(
) raises:
    var payload = List[UInt8](length=205 * 8, fill=UInt8(0))
    for i in range(len(payload)):
        payload[i] = UInt8((11 * i + 5) & 1)
    var tx = wifi_he_eht_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_HE, 10, symbol_index=5
    )
    var faded = apply_standard_channel(
        Span(tx.packet_waveform),
        wifi_tgax_profile(String("B"), bandwidth_mhz=20),
        20.0e6,
        seed=UInt64(0xA11C_E55),
    )
    var scalar = wifi_he_eht_acquisition_rx_20mhz(
        Span(faded),
        WIFI_PHY_HE,
        10,
        len(payload),
        symbol_index=5,
        detection_threshold=0.70,
        llr_noise_variance=1.0e-6,
        per_tone_llr_reliability=False,
    )
    var weighted = wifi_he_eht_acquisition_rx_20mhz(
        Span(faded),
        WIFI_PHY_HE,
        10,
        len(payload),
        symbol_index=5,
        detection_threshold=0.70,
        llr_noise_variance=1.0e-6,
        per_tone_llr_reliability=True,
    )
    # The true branch also makes legacy L-SIG a per-tone weighted soft-Viterbi
    # path; both receivers retain its decoded deinterleaver checkpoint.
    assert_equal(
        weighted.signal_deinterleaved_bits,
        scalar.signal_deinterleaved_bits,
    )
    assert_true(weighted.signal_ok)
    var tones = wifi_ru_data_subcarriers_20mhz(242, 0)
    for tone in range(len(tones)):
        var bin = tones[tone] if tones[tone] >= 0 else 256 + tones[tone]
        var reliability = weighted.he_eht_channel_estimate[
            bin
        ].magnitude_squared()
        for bit in range(10):
            var index = tone * 10 + bit
            assert_almost_equal(
                weighted.data.physical_llrs[index],
                scalar.data.physical_llrs[index] * reliability,
                atol=1.0e-10,
                rtol=2.0e-14,
            )


def test_short_statistical_run_reports_wilson_ci_without_monotonic_assertion() raises:
    var point = simulate_wifi_case(
        _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN),
        LinkSNRPoint(SNR_EBN0_INFORMATION, 12.0),
        MonteCarloStop(min_trials=8, max_trials=8),
        snr_identity=UInt64(11200),
        channel_seed_identity=UInt64(42),
        master_seed=_MASTER,
        metric=MONTE_CARLO_METRIC_PER,
    )
    assert_equal(point.packet_trials, 8)
    assert_equal(point.stop_reason, MONTE_CARLO_STOP_MAX_TRIALS)
    assert_equal(point.interval.estimate, point.counters.per())
    assert_true(point.interval.low <= point.interval.estimate)
    assert_true(point.interval.high >= point.interval.estimate)
    assert_true(point.interval.half_width > 0.0)
    # Independent Wilson equation for the exact stopped raw counts.
    var n = Float64(point.counters.packet_count)
    var failures = Float64(point.counters.packet_errors)
    var p = failures / n
    var z = 1.95996398454005423552
    var z2 = z * z
    var denominator = n + z2
    var center = (failures + 0.5 * z2) / denominator
    var radius = (z / denominator) * sqrt(
        failures * (1.0 - p) + 0.25 * z2
    )
    assert_almost_equal(
        point.interval.low,
        min(p, max(0.0, center - radius)),
        atol=2.0e-15,
        rtol=2.0e-15,
    )
    assert_almost_equal(
        point.interval.high,
        max(p, min(1.0, center + radius)),
        atol=2.0e-15,
        rtol=2.0e-15,
    )


def test_wifi_monte_carlo_checked_edges() raises:
    with assert_raises():
        _ = WifiLinkSetup(WIFI_PHY_HT, 5, 9, WIFI_LINK_CHANNEL_AWGN)
    with assert_raises():
        _ = WifiLinkSetup(WIFI_PHY_HT, 6, 0, WIFI_LINK_CHANNEL_AWGN)
    with assert_raises():
        _ = WifiLinkSetup(WIFI_PHY_HT, 6, 9, 99)
    with assert_raises():
        _ = WifiLinkSetup(
            WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_TGN, channel_model=6
        )
    with assert_raises():
        _ = WifiLinkSetup(
            WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN,
            maximum_abs_cfo=0.04,
        )
    with assert_raises():
        _ = simulate_wifi_trials(
            _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN),
            LinkSNRPoint(SNR_EBN0_INFORMATION, 10.0),
            -1,
            snr_identity=UInt64(1),
            channel_seed_identity=UInt64(1),
            master_seed=_MASTER,
        )
    with assert_raises():
        _ = simulate_wifi_packet_trial(
            _setup(WIFI_PHY_HT, 6, 100, WIFI_LINK_CHANNEL_AWGN),
            LinkSNRPoint(SNR_EBN0_INFORMATION, 10.0),
            snr_identity=UInt64(1),
            channel_seed_identity=UInt64(1),
            trial_index=UInt64(0),
            master_seed=_MASTER,
        )
    var last_trial = simulate_wifi_trials(
        _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN),
        LinkSNRPoint(SNR_EBN0_INFORMATION, 100.0),
        1,
        snr_identity=UInt64(1),
        channel_seed_identity=UInt64(1),
        first_trial=UInt64.MAX,
        master_seed=_MASTER,
    )
    assert_equal(last_trial.packet_count, 1)
    with assert_raises():
        _ = simulate_wifi_trials(
            _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN),
            LinkSNRPoint(SNR_EBN0_INFORMATION, 100.0),
            2,
            snr_identity=UInt64(1),
            channel_seed_identity=UInt64(1),
            first_trial=UInt64.MAX,
            master_seed=_MASTER,
        )
    with assert_raises():
        _ = simulate_wifi_case(
            _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN),
            LinkSNRPoint(SNR_EBN0_INFORMATION, 10.0),
            MonteCarloStop(min_trials=1, max_trials=1),
            snr_identity=UInt64(1),
            channel_seed_identity=UInt64(1),
            master_seed=_MASTER,
            metric=MONTE_CARLO_METRIC_BLER,
        )
    var setups: List[WifiLinkSetup] = [
        _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN)
    ]
    var snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_EBN0_INFORMATION, 10.0),
        LinkSNRPoint(SNR_EBN0_INFORMATION, 11.0),
    ]
    var duplicate_ids: List[UInt64] = [UInt64(1), UInt64(1)]
    var channel_seeds: List[UInt64] = [UInt64(1)]
    with assert_raises():
        _ = simulate_wifi_sweep(
            Span(setups),
            Span(snrs),
            Span(duplicate_ids),
            Span(channel_seeds),
            MonteCarloStop(min_trials=1, max_trials=1),
            master_seed=_MASTER,
        )


def test_wifi_capacity_caps_and_zero_trial_mutable_revalidation() raises:
    # Exact payload/iteration caps are legal setup metadata and allocate
    # nothing.  Their successors and both signed integer extremes fail before
    # payload multiplication or decoder entry.
    var maximum = WifiLinkSetup(
        WIFI_PHY_HT,
        6,
        16_384,
        WIFI_LINK_CHANNEL_AWGN,
        max_iterations=256,
    )
    maximum.validate()
    assert_equal(maximum.payload_octets * 8, 131_072)
    with assert_raises():
        _ = WifiLinkSetup(
            WIFI_PHY_HT, 6, 16_385, WIFI_LINK_CHANNEL_AWGN
        )
    with assert_raises():
        _ = WifiLinkSetup(
            WIFI_PHY_HT, 6, Int.MAX, WIFI_LINK_CHANNEL_AWGN
        )
    with assert_raises():
        _ = WifiLinkSetup(
            WIFI_PHY_HT, 6, Int.MIN, WIFI_LINK_CHANNEL_AWGN
        )
    with assert_raises():
        _ = WifiLinkSetup(
            WIFI_PHY_HT,
            6,
            9,
            WIFI_LINK_CHANNEL_AWGN,
            max_iterations=257,
        )
    with assert_raises():
        _ = WifiLinkSetup(
            WIFI_PHY_HT,
            6,
            9,
            WIFI_LINK_CHANNEL_AWGN,
            max_iterations=Int.MAX,
        )
    with assert_raises():
        _ = WifiLinkSetup(
            WIFI_PHY_HT,
            6,
            9,
            WIFI_LINK_CHANNEL_AWGN,
            max_iterations=Int.MIN,
        )

    var setup = _setup(WIFI_PHY_HT, 6, 9, WIFI_LINK_CHANNEL_AWGN)
    var snr = LinkSNRPoint(SNR_EBN0_INFORMATION, 20.0)
    var empty = simulate_wifi_trials(
        setup,
        snr,
        0,
        snr_identity=UInt64(1),
        channel_seed_identity=UInt64(1),
        master_seed=_MASTER,
    )
    assert_equal(empty.packet_count, 0)
    for invalid_count in [65_537, Int.MAX, Int.MIN]:
        with assert_raises():
            _ = simulate_wifi_trials(
                setup,
                snr,
                invalid_count,
                snr_identity=UInt64(1),
                channel_seed_identity=UInt64(1),
                master_seed=_MASTER,
            )

    var mutated_setup = setup
    mutated_setup.payload_octets = Int.MAX
    with assert_raises():
        _ = simulate_wifi_trials(
            mutated_setup,
            snr,
            0,
            snr_identity=UInt64(1),
            channel_seed_identity=UInt64(1),
            master_seed=_MASTER,
        )
    mutated_setup = setup
    mutated_setup.max_iterations = Int.MAX
    with assert_raises():
        _ = simulate_wifi_trials(
            mutated_setup,
            snr,
            0,
            snr_identity=UInt64(1),
            channel_seed_identity=UInt64(1),
            master_seed=_MASTER,
        )
    with assert_raises():
        _ = simulate_wifi_packet_trial(
            mutated_setup,
            snr,
            snr_identity=UInt64(1),
            channel_seed_identity=UInt64(1),
            trial_index=UInt64(0),
            master_seed=_MASTER,
        )
    with assert_raises():
        _ = simulate_wifi_case(
            mutated_setup,
            snr,
            MonteCarloStop(min_trials=1, max_trials=1),
            snr_identity=UInt64(1),
            channel_seed_identity=UInt64(1),
            master_seed=_MASTER,
        )
    var mutated_snr = snr
    mutated_snr.db = nan[DType.float64]()
    with assert_raises():
        _ = simulate_wifi_trials(
            setup,
            mutated_snr,
            0,
            snr_identity=UInt64(1),
            channel_seed_identity=UInt64(1),
            master_seed=_MASTER,
        )

    # The point and total-work caps fire before quadratic uniqueness checks or
    # packet execution, so repeated setup fixtures are sufficient sentinels.
    var too_many_setups = List[WifiLinkSetup](
        length=1_025, fill=setup
    )
    var one_snr: List[LinkSNRPoint] = [snr]
    var one_snr_id: List[UInt64] = [UInt64(1)]
    var one_channel_seed: List[UInt64] = [UInt64(1)]
    var mutated_setups: List[WifiLinkSetup] = [mutated_setup]
    with assert_raises():
        _ = simulate_wifi_sweep(
            Span(mutated_setups),
            Span(one_snr),
            Span(one_snr_id),
            Span(one_channel_seed),
            MonteCarloStop(min_trials=1, max_trials=1),
            master_seed=_MASTER,
        )
    with assert_raises():
        _ = simulate_wifi_sweep(
            Span(too_many_setups),
            Span(one_snr),
            Span(one_snr_id),
            Span(one_channel_seed),
            MonteCarloStop(min_trials=1, max_trials=1),
            master_seed=_MASTER,
        )
    var point_capacity_setups = List[WifiLinkSetup](
        length=1_024, fill=setup
    )
    with assert_raises():
        _ = simulate_wifi_sweep(
            Span(point_capacity_setups),
            Span(one_snr),
            Span(one_snr_id),
            Span(one_channel_seed),
            MonteCarloStop(min_trials=1, max_trials=65),
            master_seed=_MASTER,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
