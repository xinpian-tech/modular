"""Strict CPU evidence for the NR PDSCH waveform Monte-Carlo runner."""

from std.collections import Span
from std.math import cos, exp, isfinite, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from std.utils.numerics import nan
from wireless_dsp.channel import apply_standard_channel, tdl_profile
from wireless_dsp.core import Complex64
from wireless_dsp.testing.monte_carlo import (
    SNR_ESN0_DATA,
    SNR_EBN0_INFORMATION,
    SNR_SAMPLE,
    MONTE_CARLO_STOP_MAX_TRIALS,
    LinkSNRPoint,
    LinkCounters,
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
from wireless_dsp.wireless.nr.mcs_tbs import (
    NR_MCS_TABLE_QAM64,
    nr_mcs_profile,
    nr_mcs_target_code_rate,
    nr_transport_block_allocation,
)
from wireless_dsp.wireless.nr.pdsch_chain import (
    NRPDSCHWaveformConfig,
    nr_pdsch_grid_to_waveform,
    nr_pdsch_waveform_to_grid,
    nr_pdsch_encode_transport_block,
    nr_pdsch_decode_waveform_comb2,
)
from wireless_dsp.wireless.nr.ldpc_profile import nr_ldpc_profile


comptime _TWO_PI = 6.283185307179586476925286766559


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


def _payload(length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(UInt8((13 * index + index // 5 + 1) & 1))
    return result^


def _trim(values: Span[Complex64, ...], length: Int) -> List[Complex64]:
    var result = List[Complex64](capacity=length)
    for index in range(length):
        result.append(values[index])
    return result^


def _assert_counter_integers_equal(
    lhs: LinkCounters, rhs: LinkCounters
) raises:
    assert_equal(lhs.bit_count, rhs.bit_count)
    assert_equal(lhs.bit_errors, rhs.bit_errors)
    assert_equal(lhs.transport_block_count, rhs.transport_block_count)
    assert_equal(lhs.transport_block_errors, rhs.transport_block_errors)
    assert_equal(lhs.packet_count, rhs.packet_count)
    assert_equal(lhs.packet_errors, rhs.packet_errors)
    assert_equal(lhs.crc_check_count, rhs.crc_check_count)
    assert_equal(lhs.crc_failures, rhs.crc_failures)
    assert_equal(lhs.fcs_check_count, rhs.fcs_check_count)
    assert_equal(lhs.fcs_failures, rhs.fcs_failures)
    assert_equal(lhs.decoder_attempt_count, rhs.decoder_attempt_count)
    assert_equal(lhs.convergence_failures, rhs.convergence_failures)


def test_pdsch_waveform_helpers_match_independent_single_tone_dft() raises:
    var config = NRPDSCHWaveformConfig(
        16, 4, 2, 1, 0, 0, 1, 0, 0, 1
    )
    var grid = NRResourceGrid(1, 16)
    comptime active_tone = 3
    grid[0, active_tone] = Complex64(1.0, 0.0)
    var waveform = nr_pdsch_grid_to_waveform(config, grid)
    assert_equal(len(waveform), 20)
    for output in range(len(waveform)):
        var time = output - 4 if output >= 4 else output + 12
        var angle = _TWO_PI * Float64(active_tone * time) / 16.0
        assert_almost_equal(waveform[output].re, cos(angle) / 16.0)
        assert_almost_equal(waveform[output].im, sin(angle) / 16.0)
    var recovered = nr_pdsch_waveform_to_grid(config, Span(waveform))
    for tone in range(16):
        assert_almost_equal(recovered[0, tone].re, grid[0, tone].re)
        assert_almost_equal(recovered[0, tone].im, grid[0, tone].im)
    with assert_raises():
        _ = nr_pdsch_grid_to_waveform(
            config, NRResourceGrid(2, config.fft_size)
        )
    var short_waveform = List[Complex64](
        length=len(waveform) - 1, fill=Complex64(0.0)
    )
    with assert_raises():
        _ = nr_pdsch_waveform_to_grid(config, Span(short_waveform))


def test_pdsch_real_mcs_tbs_replay_and_exact_information_ebn0() raises:
    var setup = _setup()
    comptime mcs_index = 4
    var profile = nr_mcs_profile(NR_MCS_TABLE_QAM64, mcs_index)
    var expected = nr_transport_block_allocation(
        24, 1, 6, 0, profile, 1
    )
    var first = simulate_nr_pdsch_packet_trial(
        setup,
        mcs_index,
        LinkSNRPoint(SNR_EBN0_INFORMATION, 18.0),
        snr_identity=UInt64(18001),
        channel_model=NR_LINK_CHANNEL_AWGN,
        channel_seed_identity=UInt64(17),
        trial_index=UInt64(0),
        master_seed=UInt64(0x5EED_38000),
    )
    var replay = simulate_nr_pdsch_packet_trial(
        setup,
        mcs_index,
        LinkSNRPoint(SNR_EBN0_INFORMATION, 18.0),
        snr_identity=UInt64(18001),
        channel_model=NR_LINK_CHANNEL_AWGN,
        channel_seed_identity=UInt64(17),
        trial_index=UInt64(0),
        master_seed=UInt64(0x5EED_38000),
    )
    assert_equal(first.mcs.index, mcs_index)
    assert_equal(first.allocation.resource_elements_per_prb, 6)
    assert_equal(first.allocation.total_resource_elements, 144)
    assert_equal(expected.transport_block_size, 80)
    assert_equal(
        first.allocation.transport_block_size,
        expected.transport_block_size,
    )
    assert_equal(first.counters.bit_count, expected.transport_block_size)
    assert_equal(first.counters.transport_block_count, 1)
    assert_equal(first.counters.crc_check_count, 1)
    assert_equal(first.counters.fcs_check_count, 0)
    assert_equal(first.counters.decoder_attempt_count, 1)
    assert_true(not first.receiver_erasure)
    assert_equal(first.counters.bit_errors, 0)
    assert_equal(first.counters.transport_block_errors, 0)
    var expected_n0 = (
        first.waveform_energy
        / Float64(expected.transport_block_size)
        * exp(-0.2302585092994045684 * 18.0)
    )
    assert_almost_equal(
        first.sample_noise_variance,
        expected_n0,
        atol=0.0,
        rtol=2.0e-15,
    )
    assert_equal(
        first.frequency_bin_noise_variance,
        512.0 * first.sample_noise_variance,
    )
    assert_equal(first.payload_seed, replay.payload_seed)
    assert_equal(first.channel_seed, replay.channel_seed)
    assert_equal(first.noise_seed, replay.noise_seed)
    assert_true(first.payload_seed != first.channel_seed)
    assert_true(first.payload_seed != first.noise_seed)
    assert_true(first.channel_seed != first.noise_seed)
    _assert_counter_integers_equal(first.counters, replay.counters)
    assert_equal(
        first.counters.evm_error_energy,
        replay.counters.evm_error_energy,
    )
    var aggregate = simulate_nr_pdsch_trials(
        setup,
        mcs_index,
        LinkSNRPoint(SNR_EBN0_INFORMATION, 18.0),
        UInt64(18001),
        NR_LINK_CHANNEL_AWGN,
        UInt64(17),
        UInt64(0x5EED_38000),
        UInt64(0),
        1,
    )
    _assert_counter_integers_equal(first.counters, aggregate.result.counters)
    assert_equal(
        first.counters.evm_error_energy,
        aggregate.result.counters.evm_error_energy,
    )


def test_pdsch_sample_n0_has_independent_per_tone_qpsk_llrs() raises:
    var setup = _setup()
    comptime mcs_index = 4
    var mcs = nr_mcs_profile(NR_MCS_TABLE_QAM64, mcs_index)
    var allocation = setup.allocation(mcs_index)
    var payload = _payload(allocation.transport_block_size)
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
    var waveform = nr_pdsch_grid_to_waveform(setup.waveform, grid)
    var profile = tdl_profile("C", desired_delay_spread_ns=100.0)
    var full = apply_standard_channel(
        Span(waveform),
        profile,
        setup.sample_rate_hz(),
        seed=UInt64(0xC001),
    )
    var received = _trim(Span(full), len(waveform))
    comptime sample_n0 = 0.00025
    var decoded = nr_pdsch_decode_waveform_comb2(
        Span(received),
        setup.waveform,
        Span(transmit.encoded_null_mask),
        transmit.profile,
        allocation.transport_block_size,
        mcs.modulation_order,
        0,
        sample_n0,
    )
    var minimum_power = Float64.MAX_FINITE
    var maximum_power = 0.0
    for local in range(setup.waveform.allocation_subcarriers()):
        var power = decoded.channel_estimate[local].magnitude_squared()
        minimum_power = min(minimum_power, power)
        maximum_power = max(maximum_power, power)
    assert_true(maximum_power - minimum_power > 1.0e-3)

    var qpsk_factor = 2.0 * sqrt(2.0)
    for symbol in range(min(48, len(decoded.equalized_symbols))):
        var local = 2 * symbol + 1
        var power = decoded.channel_estimate[local].magnitude_squared()
        var tone_n0 = sample_n0 * 512.0 / power
        assert_almost_equal(
            decoded.demapper_llrs[2 * symbol],
            qpsk_factor * decoded.equalized_symbols[symbol].re / tone_n0,
            atol=1.0e-10,
            rtol=2.0e-12,
        )
        assert_almost_equal(
            decoded.demapper_llrs[2 * symbol + 1],
            qpsk_factor * decoded.equalized_symbols[symbol].im / tone_n0,
            atol=1.0e-10,
            rtol=2.0e-12,
        )


def test_pdsch_tdl_sweep_axis_reorder_replay_and_shard_merge() raises:
    var setup = _setup()
    var mcs_indices: List[Int] = [4]
    var snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_ESN0_DATA, 30.0)
    ]
    var snr_ids: List[UInt64] = [UInt64(30000)]
    var channels: List[Int] = [
        NR_LINK_CHANNEL_TDL_A,
        NR_LINK_CHANNEL_TDL_C,
        NR_LINK_CHANNEL_TDL_D,
    ]
    var channel_seeds: List[UInt64] = [UInt64(101), UInt64(103)]
    var policy = MonteCarloStop(min_trials=1, max_trials=1)
    var first = simulate_nr_pdsch_sweep(
        setup,
        Span(mcs_indices),
        Span(snrs),
        Span(snr_ids),
        Span(channels),
        Span(channel_seeds),
        UInt64(0x38_214_0001),
        policy,
    )
    var replay = simulate_nr_pdsch_sweep(
        setup,
        Span(mcs_indices),
        Span(snrs),
        Span(snr_ids),
        Span(channels),
        Span(channel_seeds),
        UInt64(0x38_214_0001),
        policy,
    )
    assert_equal(len(first), 6)
    for index in range(6):
        assert_equal(
            first[index].result.stop_reason,
            MONTE_CARLO_STOP_MAX_TRIALS,
        )
        _assert_counter_integers_equal(
            first[index].result.counters,
            replay[index].result.counters,
        )
        assert_equal(
            first[index].result.counters.evm_error_energy,
            replay[index].result.counters.evm_error_energy,
        )
    var explicit_first = simulate_nr_pdsch_case(
        setup,
        4,
        LinkSNRPoint(SNR_ESN0_DATA, 30.0),
        UInt64(30000),
        NR_LINK_CHANNEL_TDL_A,
        UInt64(101),
        UInt64(0x38_214_0001),
        policy,
    )
    _assert_counter_integers_equal(
        first[0].result.counters, explicit_first.result.counters
    )

    var reversed_channels: List[Int] = [
        NR_LINK_CHANNEL_TDL_D,
        NR_LINK_CHANNEL_TDL_C,
        NR_LINK_CHANNEL_TDL_A,
    ]
    var reversed_seeds: List[UInt64] = [UInt64(103), UInt64(101)]
    var reordered = simulate_nr_pdsch_sweep(
        setup,
        Span(mcs_indices),
        Span(snrs),
        Span(snr_ids),
        Span(reversed_channels),
        Span(reversed_seeds),
        UInt64(0x38_214_0001),
        policy,
    )
    for channel_axis in range(3):
        for seed_axis in range(2):
            var original = channel_axis * 2 + seed_axis
            var reordered_index = (2 - channel_axis) * 2 + (1 - seed_axis)
            _assert_counter_integers_equal(
                first[original].result.counters,
                reordered[reordered_index].result.counters,
            )

    var full = simulate_nr_pdsch_trials(
        setup,
        4,
        LinkSNRPoint(SNR_EBN0_INFORMATION, 20.0),
        UInt64(20001),
        NR_LINK_CHANNEL_TDL_C,
        UInt64(77),
        UInt64(0x5A4D_0002),
        UInt64(0),
        3,
    )
    var shard_a = simulate_nr_pdsch_trials(
        setup,
        4,
        LinkSNRPoint(SNR_EBN0_INFORMATION, 20.0),
        UInt64(20001),
        NR_LINK_CHANNEL_TDL_C,
        UInt64(77),
        UInt64(0x5A4D_0002),
        UInt64(0),
        1,
    )
    var shard_b = simulate_nr_pdsch_trials(
        setup,
        4,
        LinkSNRPoint(SNR_EBN0_INFORMATION, 20.0),
        UInt64(20001),
        NR_LINK_CHANNEL_TDL_C,
        UInt64(77),
        UInt64(0x5A4D_0002),
        UInt64(1),
        2,
    )
    var merged = shard_a.result.counters.merged(shard_b.result.counters)
    _assert_counter_integers_equal(full.result.counters, merged)
    assert_almost_equal(
        full.result.counters.evm_error_energy,
        merged.evm_error_energy,
        atol=1.0e-12,
        rtol=2.0e-14,
    )


def test_pdsch_wilson_erasure_and_validation_edges() raises:
    var setup = _setup()
    var point = simulate_nr_pdsch_case(
        setup,
        4,
        LinkSNRPoint(SNR_ESN0_DATA, 24.0),
        UInt64(24000),
        NR_LINK_CHANNEL_AWGN,
        UInt64(1),
        UInt64(0x5700_0002),
        MonteCarloStop(min_trials=1, max_trials=2),
    )
    assert_equal(point.result.counters.transport_block_count, 2)
    assert_equal(point.result.counters.transport_block_errors, 0)
    assert_equal(point.result.stop_reason, MONTE_CARLO_STOP_MAX_TRIALS)
    assert_equal(point.result.interval.low, 0.0)
    comptime z = 1.95996398454005423552
    assert_almost_equal(
        point.result.interval.high,
        z * z / (2.0 + z * z),
        atol=2.0e-16,
        rtol=2.0e-15,
    )
    var explicit_range = simulate_nr_pdsch_trials(
        setup,
        4,
        LinkSNRPoint(SNR_ESN0_DATA, 24.0),
        UInt64(24000),
        NR_LINK_CHANNEL_AWGN,
        UInt64(1),
        UInt64(0x5700_0002),
        UInt64(0),
        2,
    )
    _assert_counter_integers_equal(
        point.result.counters, explicit_range.result.counters
    )

    var empty = simulate_nr_pdsch_trials(
        setup,
        4,
        LinkSNRPoint(SNR_ESN0_DATA, 24.0),
        UInt64(24000),
        NR_LINK_CHANNEL_AWGN,
        UInt64(1),
        UInt64(0x5700_0002),
        UInt64.MAX,
        0,
    )
    assert_equal(empty.result.counters.transport_block_count, 0)
    assert_equal(empty.result.interval.low, 0.0)
    assert_equal(empty.result.interval.high, 1.0)

    var erasure = simulate_nr_pdsch_packet_trial(
        setup,
        4,
        LinkSNRPoint(SNR_ESN0_DATA, 24.0),
        snr_identity=UInt64(24000),
        channel_model=NR_LINK_CHANNEL_AWGN,
        channel_seed_identity=UInt64(1),
        trial_index=UInt64(0),
        master_seed=UInt64(0xE245_0001),
        receiver_fixture_failure=True,
    )
    assert_true(erasure.receiver_erasure)
    assert_equal(erasure.bit_errors, erasure.allocation.transport_block_size)
    assert_equal(erasure.counters.transport_block_errors, 1)
    assert_equal(erasure.counters.packet_errors, 1)
    assert_equal(erasure.counters.crc_failures, 1)
    assert_equal(erasure.counters.convergence_failures, 1)
    assert_equal(erasure.counters.evm_error_energy, 0.0)
    assert_equal(erasure.counters.evm_reference_energy, 0.0)
    assert_equal(erasure.counters.evm_observation_count, 0)
    with assert_raises():
        _ = erasure.counters.evm_rms()

    with assert_raises():
        _ = simulate_nr_pdsch_trials(
            setup,
            4,
            LinkSNRPoint(SNR_SAMPLE, 0.0),
            UInt64(0),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            UInt64(0),
            1,
        )
    with assert_raises():
        _ = simulate_nr_pdsch_trials(
            setup,
            4,
            LinkSNRPoint(SNR_ESN0_DATA, 0.0),
            UInt64(0),
            99,
            UInt64(1),
            UInt64(1),
            UInt64(0),
            1,
        )
    with assert_raises():
        _ = simulate_nr_pdsch_trials(
            setup,
            31,
            LinkSNRPoint(SNR_ESN0_DATA, 0.0),
            UInt64(0),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            UInt64(0),
            1,
        )
    with assert_raises():
        _ = simulate_nr_pdsch_trials(
            setup,
            4,
            LinkSNRPoint(SNR_ESN0_DATA, 0.0),
            UInt64(0),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            UInt64.MAX,
            2,
        )
    var empty_waveform = List[Complex64]()
    var empty_mask = List[UInt8]()
    with assert_raises():
        _ = nr_pdsch_decode_waveform_comb2(
            Span(empty_waveform),
            setup.waveform,
            Span(empty_mask),
            nr_ldpc_profile(24, 0.5),
            24,
            2,
            0,
            0.0,
        )
    var no_mcs = List[Int]()
    var one_snr: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_ESN0_DATA, 0.0)
    ]
    var one_snr_id: List[UInt64] = [UInt64(0)]
    var one_channel: List[Int] = [NR_LINK_CHANNEL_AWGN]
    var one_channel_seed: List[UInt64] = [UInt64(0)]
    with assert_raises():
        _ = simulate_nr_pdsch_sweep(
            setup,
            Span(no_mcs),
            Span(one_snr),
            Span(one_snr_id),
            Span(one_channel),
            Span(one_channel_seed),
            UInt64(1),
            MonteCarloStop(min_trials=1, max_trials=1),
        )
    var short_cp_setup = NRPDSCHLinkSetup(
        NRPDSCHWaveformConfig(
            512, 1, 32, 24, 3, 2, 42, 0, 0, 0x1234
        ),
        NR_MCS_TABLE_QAM64,
        tdl_delay_spread_ns=100.0,
    )
    with assert_raises():
        _ = simulate_nr_pdsch_packet_trial(
            short_cp_setup,
            4,
            LinkSNRPoint(SNR_ESN0_DATA, 20.0),
            snr_identity=UInt64(20000),
            channel_model=NR_LINK_CHANNEL_TDL_D,
            channel_seed_identity=UInt64(1),
            trial_index=UInt64(0),
            master_seed=UInt64(1),
        )


def test_pdsch_cpu_capacity_caps_and_zero_trial_revalidation() raises:
    # The exact FFT/waveform/iteration boundaries remain legal setup metadata
    # and require no large waveform allocation.
    var maximum = NRPDSCHLinkSetup(
        NRPDSCHWaveformConfig(
            4_096,
            4_096,
            0,
            275,
            0,
            0,
            0,
            0,
            0,
            1,
        ),
        NR_MCS_TABLE_QAM64,
        max_iterations=256,
    )
    maximum.validate()
    assert_equal(
        maximum.waveform.fft_size + maximum.waveform.cyclic_prefix,
        8_192,
    )
    assert_true(maximum.allocation(4).transport_block_size <= 1_048_576)

    with assert_raises():
        _ = NRPDSCHLinkSetup(
            NRPDSCHWaveformConfig(
                8_192, 0, 0, 1, 0, 0, 0, 0, 0, 1
            ),
            NR_MCS_TABLE_QAM64,
        )
    for invalid_iterations in [257, Int.MAX, Int.MIN]:
        with assert_raises():
            _ = NRPDSCHLinkSetup(
                _setup().waveform,
                NR_MCS_TABLE_QAM64,
                max_iterations=invalid_iterations,
            )

    var mutated = _setup()
    mutated.max_iterations = Int.MAX
    with assert_raises():
        mutated.validate()
    mutated = _setup()
    mutated.waveform.fft_size = 8_192
    with assert_raises():
        mutated.validate()

    var setup = _setup()
    var snr = LinkSNRPoint(SNR_ESN0_DATA, 20.0)
    with assert_raises():
        _ = simulate_nr_pdsch_packet_trial(
            mutated,
            4,
            snr,
            snr_identity=UInt64(20_000),
            channel_model=NR_LINK_CHANNEL_AWGN,
            channel_seed_identity=UInt64(1),
            trial_index=UInt64(0),
            master_seed=UInt64(1),
        )
    with assert_raises():
        _ = simulate_nr_pdsch_case(
            mutated,
            4,
            snr,
            UInt64(20_000),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            MonteCarloStop(min_trials=1, max_trials=1),
        )
    for invalid_count in [65_537, Int.MAX, Int.MIN]:
        with assert_raises():
            _ = simulate_nr_pdsch_trials(
                setup,
                4,
                snr,
                UInt64(20_000),
                NR_LINK_CHANNEL_AWGN,
                UInt64(1),
                UInt64(1),
                UInt64(0),
                invalid_count,
            )

    # Empty shards are useful merge identities but still revalidate mutable
    # setup and SNR fields before returning.
    var mutated_setup = setup
    mutated_setup.max_iterations = Int.MAX
    with assert_raises():
        _ = simulate_nr_pdsch_trials(
            mutated_setup,
            4,
            snr,
            UInt64(20_000),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            UInt64(0),
            0,
        )
    var mutated_snr = snr
    mutated_snr.db = nan[DType.float64]()
    with assert_raises():
        _ = simulate_nr_pdsch_trials(
            setup,
            4,
            mutated_snr,
            UInt64(20_000),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            UInt64(0),
            0,
        )

    # Point and total-work caps fire before quadratic uniqueness scans.
    var too_many_mcs = List[Int](length=1_025, fill=4)
    var one_snr: List[LinkSNRPoint] = [snr]
    var one_snr_id: List[UInt64] = [UInt64(20_000)]
    var one_channel: List[Int] = [NR_LINK_CHANNEL_AWGN]
    var one_channel_seed: List[UInt64] = [UInt64(1)]
    var one_mcs: List[Int] = [4]
    with assert_raises():
        _ = simulate_nr_pdsch_sweep(
            mutated,
            Span(one_mcs),
            Span(one_snr),
            Span(one_snr_id),
            Span(one_channel),
            Span(one_channel_seed),
            UInt64(1),
            MonteCarloStop(min_trials=1, max_trials=1),
        )
    with assert_raises():
        _ = simulate_nr_pdsch_sweep(
            setup,
            Span(too_many_mcs),
            Span(one_snr),
            Span(one_snr_id),
            Span(one_channel),
            Span(one_channel_seed),
            UInt64(1),
            MonteCarloStop(min_trials=1, max_trials=1),
        )
    var point_capacity_mcs = List[Int](length=1_024, fill=4)
    with assert_raises():
        _ = simulate_nr_pdsch_sweep(
            setup,
            Span(point_capacity_mcs),
            Span(one_snr),
            Span(one_snr_id),
            Span(one_channel),
            Span(one_channel_seed),
            UInt64(1),
            MonteCarloStop(min_trials=1, max_trials=65),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
