"""Strict CPU evidence for NR PUSCH MCS/SNR/TDL Monte-Carlo execution."""

from std.collections import Span
from std.math import isfinite, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from std.utils.numerics import nan
from wireless_dsp.core import Complex64
from wireless_dsp.channel import apply_standard_channel, tdl_profile
from wireless_dsp.testing import (
    SNR_ESN0_DATA,
    SNR_EBN0_INFORMATION,
    SNR_SAMPLE,
    MONTE_CARLO_STOP_MAX_TRIALS,
    NR_LINK_CHANNEL_AWGN,
    NR_LINK_CHANNEL_TDL_A,
    NR_LINK_CHANNEL_TDL_C,
    NR_LINK_CHANNEL_TDL_D,
    LinkSNRPoint,
    LinkCounters,
    MonteCarloStop,
    NRPUSCHLinkSetup,
    simulate_nr_pusch_trials,
    simulate_nr_pusch_case,
    simulate_nr_pusch_sweep,
)
from wireless_dsp.wireless.nr.mcs_tbs import (
    NR_MCS_TABLE_QAM64,
    nr_mcs_profile,
    nr_mcs_target_code_rate,
    nr_transport_block_size,
)
from wireless_dsp.wireless.nr.pusch_chain import (
    NRPUSCHConfig,
    nr_pusch_data_re_count,
    nr_pusch_encode_transport_block,
    nr_pusch_decode_waveform,
)


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


def _payload(length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(UInt8((13 * index + index // 5 + 1) & 1))
    return result^


def _trim(values: Span[Complex64, ...], length: Int) -> List[Complex64]:
    var result = List[Complex64](capacity=length)
    for index in range(length):
        result.append(Complex64(values[index].re, values[index].im))
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


def test_pusch_runner_uses_exact_mcs_tbs_and_replays_awgn() raises:
    var setup = _setup()
    comptime mcs_index = 4
    var expected_mcs = nr_mcs_profile(NR_MCS_TABLE_QAM64, mcs_index)
    var expected_tbs = nr_transport_block_size(
        nr_pusch_data_re_count(setup.pusch), expected_mcs, 1
    )
    var snr = LinkSNRPoint(SNR_ESN0_DATA, 24.0)
    var first = simulate_nr_pusch_trials(
        setup,
        mcs_index,
        snr,
        UInt64(24000),
        NR_LINK_CHANNEL_AWGN,
        UInt64(11),
        UInt64(0x5EED_38000),
        UInt64(0),
        1,
    )
    var replay = simulate_nr_pusch_trials(
        setup,
        mcs_index,
        snr,
        UInt64(24000),
        NR_LINK_CHANNEL_AWGN,
        UInt64(11),
        UInt64(0x5EED_38000),
        UInt64(0),
        1,
    )
    assert_equal(first.mcs.table, NR_MCS_TABLE_QAM64)
    assert_equal(first.mcs.index, mcs_index)
    assert_equal(first.mcs.modulation_order, expected_mcs.modulation_order)
    assert_equal(first.transport_block_size, expected_tbs)
    assert_equal(first.result.counters.bit_count, expected_tbs)
    assert_equal(first.result.counters.transport_block_count, 1)
    assert_equal(first.result.counters.crc_check_count, 1)
    assert_equal(first.result.counters.decoder_attempt_count, 1)
    assert_equal(first.result.counters.fcs_check_count, 0)
    assert_equal(first.result.counters.bit_errors, 0)
    assert_equal(first.result.counters.transport_block_errors, 0)
    assert_true(isfinite(first.result.counters.evm_rms()))
    _assert_counter_integers_equal(
        first.result.counters, replay.result.counters
    )
    assert_equal(
        first.result.counters.evm_error_energy,
        replay.result.counters.evm_error_energy,
    )
    assert_equal(
        first.result.counters.evm_reference_energy,
        replay.result.counters.evm_reference_energy,
    )


def test_pusch_sample_n0_is_scaled_per_tone_after_frequency_selective_zf() raises:
    var setup = _setup()
    comptime mcs_index = 4
    var mcs = nr_mcs_profile(NR_MCS_TABLE_QAM64, mcs_index)
    var payload_bits = setup.transport_block_size(mcs_index)
    var payload = _payload(payload_bits)
    var transmit = nr_pusch_encode_transport_block(
        Span(payload),
        nr_mcs_target_code_rate(mcs),
        mcs.modulation_order,
        0,
        setup.pusch,
    )
    var profile = tdl_profile("C", desired_delay_spread_ns=300.0)
    var full = apply_standard_channel(
        Span(transmit.waveform),
        profile,
        setup.sample_rate_hz(),
        seed=UInt64(0xC001),
    )
    var received = _trim(Span(full), len(transmit.waveform))
    comptime sample_n0 = 0.0025
    var decoded = nr_pusch_decode_waveform(
        Span(received),
        setup.pusch,
        Span(transmit.encoded_null_mask),
        transmit.profile,
        payload_bits,
        mcs.modulation_order,
        0,
        sample_noise_variance=sample_n0,
    )
    assert_equal(
        len(decoded.demapper_llrs),
        len(decoded.equalized_symbols) * mcs.modulation_order,
    )
    var minimum_power = Float64.MAX_FINITE
    var maximum_power = 0.0
    var allocation = 12 * setup.pusch.resource_blocks
    for tone in range(allocation):
        var magnitude = decoded.channel_estimate[tone].magnitude()
        var power = magnitude * magnitude
        minimum_power = min(minimum_power, power)
        maximum_power = max(maximum_power, power)
    assert_true(maximum_power - minimum_power > 1.0e-3)

    # Independent QPSK max-log formula.  Each symbol uses the channel estimate
    # at its local subcarrier, proving the API did not substitute one scalar.
    var qpsk_factor = 2.0 * sqrt(2.0)
    for symbol in range(min(48, len(decoded.equalized_symbols))):
        var tone = symbol % allocation
        var magnitude = decoded.channel_estimate[tone].magnitude()
        var tone_n0 = (
            sample_n0 * Float64(setup.pusch.fft_size)
            / magnitude / magnitude
        )
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


def test_pusch_tdl_a_c_d_sweep_order_replay_and_exact_information_ebn0() raises:
    var setup = _setup()
    var mcs_indices: List[Int] = [4]
    var snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_ESN0_DATA, 30.0),
        LinkSNRPoint(SNR_EBN0_INFORMATION, 24.0),
    ]
    var snr_ids: List[UInt64] = [UInt64(30000), UInt64(24001)]
    var channels: List[Int] = [
        NR_LINK_CHANNEL_TDL_A,
        NR_LINK_CHANNEL_TDL_C,
        NR_LINK_CHANNEL_TDL_D,
    ]
    var channel_seeds: List[UInt64] = [UInt64(101), UInt64(103)]
    var policy = MonteCarloStop(min_trials=1, max_trials=1)
    var first = simulate_nr_pusch_sweep(
        setup,
        Span(mcs_indices),
        Span(snrs),
        Span(snr_ids),
        Span(channels),
        Span(channel_seeds),
        UInt64(0x38_901_0001),
        policy,
    )
    var replay = simulate_nr_pusch_sweep(
        setup,
        Span(mcs_indices),
        Span(snrs),
        Span(snr_ids),
        Span(channels),
        Span(channel_seeds),
        UInt64(0x38_901_0001),
        policy,
    )
    var manual_first = simulate_nr_pusch_case(
        setup,
        mcs_indices[0],
        snrs[0],
        snr_ids[0],
        channels[0],
        channel_seeds[0],
        UInt64(0x38_901_0001),
        policy,
    )
    assert_equal(len(first), 12)
    _assert_counter_integers_equal(
        first[0].result.counters, manual_first.result.counters
    )
    assert_equal(
        first[0].result.counters.evm_error_energy,
        manual_first.result.counters.evm_error_energy,
    )
    assert_equal(first[0].result.link_case.snr_identity, UInt64(30000))
    assert_equal(
        first[0].result.link_case.channel_id,
        UInt64(NR_LINK_CHANNEL_TDL_A),
    )
    assert_equal(
        first[1].result.link_case.channel_seed_identity,
        UInt64(103),
    )
    assert_equal(
        first[2].result.link_case.channel_id,
        UInt64(NR_LINK_CHANNEL_TDL_C),
    )
    assert_equal(first[6].result.link_case.snr_identity, UInt64(24001))
    for index in range(len(first)):
        assert_equal(first[index].result.counters.transport_block_count, 1)
        assert_equal(
            first[index].result.stop_reason,
            MONTE_CARLO_STOP_MAX_TRIALS,
        )
        assert_true(isfinite(first[index].result.counters.evm_rms()))
        _assert_counter_integers_equal(
            first[index].result.counters,
            replay[index].result.counters,
        )
        assert_equal(
            first[index].result.counters.evm_error_energy,
            replay[index].result.counters.evm_error_energy,
        )

    # Axis position is not part of any random stream.  Reversing channel and
    # seed axes only permutes the exact case results.
    var reversed_channels: List[Int] = [
        NR_LINK_CHANNEL_TDL_D,
        NR_LINK_CHANNEL_TDL_C,
        NR_LINK_CHANNEL_TDL_A,
    ]
    var reversed_seeds: List[UInt64] = [UInt64(103), UInt64(101)]
    var reordered = simulate_nr_pusch_sweep(
        setup,
        Span(mcs_indices),
        Span(snrs),
        Span(snr_ids),
        Span(reversed_channels),
        Span(reversed_seeds),
        UInt64(0x38_901_0001),
        policy,
    )
    for snr_axis in range(2):
        for channel_axis in range(3):
            for seed_axis in range(2):
                var original_index = snr_axis * 6 + channel_axis * 2 + seed_axis
                var reordered_index = (
                    snr_axis * 6
                    + (2 - channel_axis) * 2
                    + (1 - seed_axis)
                )
                _assert_counter_integers_equal(
                    first[original_index].result.counters,
                    reordered[reordered_index].result.counters,
                )
                assert_equal(
                    first[original_index].result.counters.evm_error_energy,
                    reordered[reordered_index].result.counters.evm_error_energy,
                )


def test_pusch_global_trial_shards_merge_to_full_run() raises:
    var setup = _setup()
    var snr = LinkSNRPoint(SNR_EBN0_INFORMATION, 18.0)
    var full = simulate_nr_pusch_trials(
        setup,
        4,
        snr,
        UInt64(18001),
        NR_LINK_CHANNEL_TDL_C,
        UInt64(77),
        UInt64(0x5A4D_0001),
        UInt64(0),
        4,
    )
    var first = simulate_nr_pusch_trials(
        setup,
        4,
        snr,
        UInt64(18001),
        NR_LINK_CHANNEL_TDL_C,
        UInt64(77),
        UInt64(0x5A4D_0001),
        UInt64(0),
        2,
    )
    var second = simulate_nr_pusch_trials(
        setup,
        4,
        snr,
        UInt64(18001),
        NR_LINK_CHANNEL_TDL_C,
        UInt64(77),
        UInt64(0x5A4D_0001),
        UInt64(2),
        2,
    )
    var merged = first.result.counters.merged(second.result.counters)
    _assert_counter_integers_equal(full.result.counters, merged)
    assert_almost_equal(
        full.result.counters.evm_error_energy,
        merged.evm_error_energy,
        atol=1.0e-12,
        rtol=2.0e-14,
    )
    assert_equal(
        full.result.counters.evm_reference_energy,
        merged.evm_reference_energy,
    )


def test_pusch_wilson_stop_and_validation_edges() raises:
    var setup = _setup()
    var policy = MonteCarloStop(min_trials=1, max_trials=2)
    var point = simulate_nr_pusch_case(
        setup,
        4,
        LinkSNRPoint(SNR_ESN0_DATA, 24.0),
        UInt64(24000),
        NR_LINK_CHANNEL_AWGN,
        UInt64(1),
        UInt64(0x5700_0001),
        policy,
    )
    assert_equal(point.result.counters.transport_block_count, 2)
    assert_equal(point.result.stop_reason, MONTE_CARLO_STOP_MAX_TRIALS)
    assert_true(point.result.interval.low >= 0.0)
    assert_true(point.result.interval.high <= 1.0)
    var manual_trials = simulate_nr_pusch_trials(
        setup,
        4,
        LinkSNRPoint(SNR_ESN0_DATA, 24.0),
        UInt64(24000),
        NR_LINK_CHANNEL_AWGN,
        UInt64(1),
        UInt64(0x5700_0001),
        UInt64(0),
        2,
    )
    _assert_counter_integers_equal(
        point.result.counters, manual_trials.result.counters
    )
    assert_equal(
        point.result.counters.evm_error_energy,
        manual_trials.result.counters.evm_error_energy,
    )

    with assert_raises():
        _ = simulate_nr_pusch_trials(
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
        _ = simulate_nr_pusch_trials(
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
        _ = simulate_nr_pusch_trials(
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
        _ = simulate_nr_pusch_trials(
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
    with assert_raises():
        _ = NRPUSCHLinkSetup(
            setup.pusch,
            NR_MCS_TABLE_QAM64,
            tdl_delay_spread_ns=nan[DType.float64](),
        )
    with assert_raises():
        _ = simulate_nr_pusch_case(
            setup,
            4,
            LinkSNRPoint(SNR_ESN0_DATA, 0.0),
            UInt64(0),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            policy,
            first_trial=UInt64.MAX,
        )
    var no_mcs = List[Int]()
    var one_snr: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_ESN0_DATA, 0.0)
    ]
    var one_snr_id: List[UInt64] = [UInt64(1)]
    var one_channel: List[Int] = [NR_LINK_CHANNEL_AWGN]
    var one_channel_seed: List[UInt64] = [UInt64(1)]
    with assert_raises():
        _ = simulate_nr_pusch_sweep(
            setup,
            Span(no_mcs),
            Span(one_snr),
            Span(one_snr_id),
            Span(one_channel),
            Span(one_channel_seed),
            UInt64(1),
            policy,
        )


def test_pusch_cpu_capacity_caps_and_integer_extremes() raises:
    # The exact FFT/RB/waveform/iteration boundaries are legal setup metadata;
    # no waveform is allocated by these constructor checks.
    var maximum = NRPUSCHLinkSetup(
        NRPUSCHConfig(
            4_096,
            4_096,
            8,
            2,
            0,
            275,
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
        (maximum.pusch.fft_size + maximum.pusch.cyclic_prefix)
            * maximum.pusch.symbol_count,
        65_536,
    )
    assert_true(maximum.transport_block_size(4) <= 1_048_576)

    with assert_raises():
        _ = NRPUSCHLinkSetup(
            NRPUSCHConfig(8_192, 0, 2, 0, 0, 1, 0, 0, 0, 1),
            NR_MCS_TABLE_QAM64,
        )
    with assert_raises():
        _ = NRPUSCHLinkSetup(
            NRPUSCHConfig(4_096, 0, 2, 0, 0, 276, 0, 0, 0, 1),
            NR_MCS_TABLE_QAM64,
        )
    with assert_raises():
        _ = NRPUSCHLinkSetup(
            NRPUSCHConfig(
                4_096, 4_096, 9, 2, 0, 1, 0, 0, 0, 1
            ),
            NR_MCS_TABLE_QAM64,
        )
    for invalid_iterations in [257, Int.MAX, Int.MIN]:
        with assert_raises():
            _ = NRPUSCHLinkSetup(
                _setup().pusch,
                NR_MCS_TABLE_QAM64,
                max_iterations=invalid_iterations,
            )

    var mutated = _setup()
    mutated.max_iterations = Int.MAX
    with assert_raises():
        mutated.validate()
    mutated = _setup()
    mutated.pusch.fft_size = 8_192
    with assert_raises():
        mutated.validate()

    var setup = _setup()
    var snr = LinkSNRPoint(SNR_ESN0_DATA, 20.0)
    with assert_raises():
        _ = simulate_nr_pusch_trials(
            mutated,
            4,
            snr,
            UInt64(20_000),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            UInt64(0),
            1,
        )
    with assert_raises():
        _ = simulate_nr_pusch_case(
            mutated,
            4,
            snr,
            UInt64(20_000),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            MonteCarloStop(min_trials=1, max_trials=1),
        )
    var mutated_snr = snr
    mutated_snr.db = nan[DType.float64]()
    with assert_raises():
        _ = simulate_nr_pusch_case(
            setup,
            4,
            mutated_snr,
            UInt64(20_000),
            NR_LINK_CHANNEL_AWGN,
            UInt64(1),
            UInt64(1),
            MonteCarloStop(min_trials=1, max_trials=1),
        )
    for invalid_count in [65_537, Int.MAX, Int.MIN]:
        with assert_raises():
            _ = simulate_nr_pusch_trials(
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

    # Point and total-work rejection happens before the O(N^2) uniqueness
    # scans; repeated MCS entries deliberately detect that ordering.
    var too_many_mcs = List[Int](length=1_025, fill=4)
    var one_snr: List[LinkSNRPoint] = [snr]
    var one_snr_id: List[UInt64] = [UInt64(20_000)]
    var one_channel: List[Int] = [NR_LINK_CHANNEL_AWGN]
    var one_channel_seed: List[UInt64] = [UInt64(1)]
    var one_mcs: List[Int] = [4]
    with assert_raises():
        _ = simulate_nr_pusch_sweep(
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
        _ = simulate_nr_pusch_sweep(
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
        _ = simulate_nr_pusch_sweep(
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
