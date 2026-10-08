"""Strict CPU evidence for composable link-level Monte-Carlo contracts."""

from std.collections import Span
from std.math import erfc, exp, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from std.utils.numerics import inf, nan
from wireless_dsp.testing import (
    SNR_ESN0_DATA,
    SNR_EBN0_CODED,
    SNR_EBN0_INFORMATION,
    SNR_SAMPLE,
    MONTE_CARLO_METRIC_BER,
    MONTE_CARLO_METRIC_BLER,
    MONTE_CARLO_METRIC_PER,
    MONTE_CARLO_METRIC_CRC,
    MONTE_CARLO_METRIC_FCS,
    MONTE_CARLO_METRIC_CONVERGENCE,
    MONTE_CARLO_CONTINUE,
    MONTE_CARLO_STOP_MAX_TRIALS,
    MONTE_CARLO_STOP_TARGET_ERRORS,
    MONTE_CARLO_STOP_ABSOLUTE_CI,
    MONTE_CARLO_STOP_RELATIVE_CI,
    LINK_SEED_STREAM_PAYLOAD,
    LINK_SEED_STREAM_CHANNEL,
    LINK_SEED_STREAM_NOISE,
    LINK_SEED_STREAM_IMPAIRMENT,
    LinkSNRPoint,
    LinkEnergyReference,
    LinkCounters,
    MonteCarloStop,
    LinkCase,
    link_noise_variance,
    wilson_interval,
    monte_carlo_stop_reason,
    should_stop,
    derive_link_seed,
    cartesian_link_cases,
    make_link_sweep_point,
    simulate_qam_awgn,
)


comptime _LN_10_OVER_10 = 0.230258509299404568401799145468


def _oracle_seed_mix(value: UInt64) -> UInt64:
    var mixed = value
    mixed = (mixed ^ (mixed >> 30)) * UInt64(0xBF58476D1CE4E5B9)
    mixed = (mixed ^ (mixed >> 27)) * UInt64(0x94D049BB133111EB)
    return mixed ^ (mixed >> 31)


def _oracle_link_seed(
    master_seed: UInt64,
    protocol_id: UInt64,
    mcs_id: UInt64,
    snr_identity: UInt64,
    channel_id: UInt64,
    channel_seed_identity: UInt64,
    trial_index: UInt64,
    stream_id: UInt64,
) -> UInt64:
    var state = _oracle_seed_mix(
        master_seed ^ UInt64(0x243F6A8885A308D3)
    )
    state = _oracle_seed_mix(
        state ^ _oracle_seed_mix(
            protocol_id ^ UInt64(0x13198A2E03707344)
        )
    )
    state = _oracle_seed_mix(
        state ^ _oracle_seed_mix(mcs_id ^ UInt64(0xA4093822299F31D0))
    )
    state = _oracle_seed_mix(
        state ^ _oracle_seed_mix(
            snr_identity ^ UInt64(0x082EFA98EC4E6C89)
        )
    )
    state = _oracle_seed_mix(
        state ^ _oracle_seed_mix(channel_id ^ UInt64(0x452821E638D01377))
    )
    state = _oracle_seed_mix(
        state ^ _oracle_seed_mix(
            channel_seed_identity ^ UInt64(0xBE5466CF34E90C6C)
        )
    )
    state = _oracle_seed_mix(
        state ^ _oracle_seed_mix(
            trial_index ^ UInt64(0xC0AC29B7C97C50DD)
        )
    )
    return _oracle_seed_mix(
        state ^ _oracle_seed_mix(stream_id ^ UInt64(0x3F84D5B5B5470917))
    )


def _assert_counters_equal(lhs: LinkCounters, rhs: LinkCounters) raises:
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
    assert_equal(lhs.evm_observation_count, rhs.evm_observation_count)
    assert_almost_equal(
        lhs.evm_error_energy, rhs.evm_error_energy, atol=1.0e-14, rtol=1.0e-14
    )
    assert_almost_equal(
        lhs.evm_reference_energy,
        rhs.evm_reference_energy,
        atol=1.0e-14,
        rtol=1.0e-14,
    )


def test_snr_modes_have_strict_complex_n0_semantics() raises:
    var symbol = LinkEnergyReference(
        data_symbol_energy=2.0, bits_per_symbol=4
    )
    assert_almost_equal(
        link_noise_variance(LinkSNRPoint(SNR_ESN0_DATA, 10.0), symbol),
        0.2,
        atol=2.0e-13,
        rtol=1.0e-12,
    )
    assert_almost_equal(
        link_noise_variance(LinkSNRPoint(SNR_EBN0_CODED, 0.0), symbol),
        0.5,
        atol=5.0e-13,
        rtol=1.0e-12,
    )

    # Exact information-bit energy includes the caller's complete waveform
    # scope.  It intentionally does not infer an Es/(Qm*R) approximation.
    var packet = LinkEnergyReference(
        waveform_energy=800.0, information_bits=100, sample_count=400
    )
    assert_almost_equal(
        link_noise_variance(
            LinkSNRPoint(SNR_EBN0_INFORMATION, 10.0), packet
        ),
        0.8,
        atol=1.0e-12,
        rtol=1.0e-12,
    )
    assert_almost_equal(
        link_noise_variance(LinkSNRPoint(SNR_SAMPLE, 10.0), packet),
        0.2,
        atol=2.0e-13,
        rtol=1.0e-12,
    )


def test_snr_conversion_matches_independent_log_domain_oracle() raises:
    var energy = LinkEnergyReference(
        data_symbol_energy=1.75,
        bits_per_symbol=7,
        waveform_energy=321.5,
        information_bits=113,
        sample_count=509,
    )
    var db_values: List[Float64] = [-80.0, -3.25, 0.0, 17.5, 120.0]
    for db in db_values:
        var linear_inverse = exp(-_LN_10_OVER_10 * db)
        assert_almost_equal(
            link_noise_variance(LinkSNRPoint(SNR_ESN0_DATA, db), energy),
            1.75 * linear_inverse,
            atol=0.0,
            rtol=1.0e-10,
        )
        assert_almost_equal(
            link_noise_variance(LinkSNRPoint(SNR_EBN0_CODED, db), energy),
            (1.75 / 7.0) * linear_inverse,
            atol=0.0,
            rtol=1.0e-10,
        )
        assert_almost_equal(
            link_noise_variance(
                LinkSNRPoint(SNR_EBN0_INFORMATION, db), energy
            ),
            (321.5 / 113.0) * linear_inverse,
            atol=0.0,
            rtol=1.0e-10,
        )
        assert_almost_equal(
            link_noise_variance(LinkSNRPoint(SNR_SAMPLE, db), energy),
            (321.5 / 509.0) * linear_inverse,
            atol=0.0,
            rtol=1.0e-10,
        )


def test_snr_validation_and_unrepresentable_n0_edges() raises:
    with assert_raises():
        _ = LinkSNRPoint(99, 0.0)
    for invalid_db in [nan[DType.float64](), inf[DType.float64]()]:
        with assert_raises():
            _ = LinkSNRPoint(SNR_ESN0_DATA, invalid_db)
    for invalid_energy in [-1.0, nan[DType.float64](), inf[DType.float64]()]:
        with assert_raises():
            _ = LinkEnergyReference(data_symbol_energy=invalid_energy)

    var empty = LinkEnergyReference()
    for mode in [
        SNR_ESN0_DATA,
        SNR_EBN0_CODED,
        SNR_EBN0_INFORMATION,
        SNR_SAMPLE,
    ]:
        with assert_raises():
            _ = link_noise_variance(LinkSNRPoint(mode, 0.0), empty)

    var valid = LinkEnergyReference(
        data_symbol_energy=1.0,
        bits_per_symbol=1,
        waveform_energy=1.0,
        information_bits=1,
        sample_count=1,
    )
    # Finite dB inputs whose mathematical positive N0 under/overflows Float64
    # are rejected instead of being silently converted to zero or infinity.
    with assert_raises():
        _ = link_noise_variance(
            LinkSNRPoint(SNR_ESN0_DATA, 1.0e308), valid
        )
    with assert_raises():
        _ = link_noise_variance(
            LinkSNRPoint(SNR_ESN0_DATA, -1.0e308), valid
        )


def test_snr_n0_drives_bpsk_and_qpsk_analytic_ber() raises:
    # 3.0103 dB is a linear ratio of two.  For unit-energy BPSK this gives
    # N0=0.5 and Pb=0.5*erfc(sqrt(1/N0)).
    comptime snr_db = 3.010299956639812
    var bpsk_energy = LinkEnergyReference(
        data_symbol_energy=1.0, bits_per_symbol=1
    )
    var bpsk_n0 = link_noise_variance(
        LinkSNRPoint(SNR_ESN0_DATA, snr_db), bpsk_energy
    )
    var bpsk = simulate_qam_awgn(
        1, 80000, bpsk_n0, seed=UInt64(0xB05E_0001)
    )
    var bpsk_theory = 0.5 * erfc(sqrt(1.0 / bpsk_n0))
    var bpsk_standard_error = sqrt(
        bpsk_theory * (1.0 - bpsk_theory) / Float64(bpsk.bit_count)
    )
    assert_true(abs(bpsk.ber - bpsk_theory) <= 6.0 * bpsk_standard_error)

    # For QPSK, coded Eb=Es/2.  At the same Eb/N0, N0=0.25 and the bit
    # probability is 0.5*erfc(sqrt(1/(2*N0))).
    var qpsk_energy = LinkEnergyReference(
        data_symbol_energy=1.0, bits_per_symbol=2
    )
    var qpsk_n0 = link_noise_variance(
        LinkSNRPoint(SNR_EBN0_CODED, snr_db), qpsk_energy
    )
    var qpsk = simulate_qam_awgn(
        2, 60000, qpsk_n0, seed=UInt64(0xA05E_0002)
    )
    var qpsk_theory = 0.5 * erfc(sqrt(1.0 / (2.0 * qpsk_n0)))
    var qpsk_standard_error = sqrt(
        qpsk_theory * (1.0 - qpsk_theory) / Float64(qpsk.bit_count)
    )
    assert_true(abs(qpsk.ber - qpsk_theory) <= 6.0 * qpsk_standard_error)


def test_link_counters_keep_independent_raw_metrics_and_evm() raises:
    var counters = LinkCounters(
        bit_count=1000,
        bit_errors=25,
        transport_block_count=20,
        transport_block_errors=3,
        packet_count=10,
        packet_errors=4,
        crc_check_count=20,
        crc_failures=2,
        fcs_check_count=10,
        fcs_failures=3,
        decoder_attempt_count=40,
        convergence_failures=5,
        evm_error_energy=4.0,
        evm_reference_energy=16.0,
    )
    assert_equal(counters.ber(), 0.025)
    assert_equal(counters.bler(), 0.15)
    assert_equal(counters.per(), 0.4)
    assert_equal(counters.crc_failure_rate(), 0.1)
    assert_equal(counters.fcs_failure_rate(), 0.3)
    assert_equal(counters.convergence_failure_rate(), 0.125)
    assert_equal(counters.evm_observation_count, 1)
    assert_equal(counters.evm_rms(), 0.5)

    var unavailable = LinkCounters()
    assert_equal(unavailable.evm_observation_count, 0)
    with assert_raises():
        _ = unavailable.evm_rms()

    var extreme = LinkCounters(
        evm_error_energy=1.0e308, evm_reference_energy=1.0e-308
    )
    assert_almost_equal(
        extreme.evm_rms(), 1.0e308, atol=0.0, rtol=2.0e-13
    )


def test_link_counter_merge_is_associative_and_shard_stable() raises:
    var full = LinkCounters()
    var shard_zero = LinkCounters()
    var shard_one = LinkCounters()
    var shard_two = LinkCounters()
    for trial in range(97):
        var bit_errors = (7 * trial + 3) % 11
        var failed = 1 if trial % 7 == 0 else 0
        var trial_count = LinkCounters(
            bit_count=100,
            bit_errors=bit_errors,
            transport_block_count=1,
            transport_block_errors=failed,
            packet_count=1,
            packet_errors=failed,
            crc_check_count=1,
            crc_failures=failed,
            fcs_check_count=1,
            fcs_failures=failed,
            decoder_attempt_count=2,
            convergence_failures=1 if trial % 13 == 0 else 0,
            evm_error_energy=Float64(trial + 1) * 0.001,
            evm_reference_energy=2.0,
        )
        full.merge(trial_count)
        if trial % 3 == 0:
            shard_zero.merge(trial_count)
        elif trial % 3 == 1:
            shard_one.merge(trial_count)
        else:
            shard_two.merge(trial_count)
    var left = shard_zero.merged(shard_one).merged(shard_two)
    var right = shard_zero.merged(shard_one.merged(shard_two))
    _assert_counters_equal(full, left)
    _assert_counters_equal(left, right)
    assert_equal(full.evm_observation_count, 97)


def test_link_counter_validation_checked_overflow_and_atomic_merge() raises:
    with assert_raises():
        _ = LinkCounters(bit_count=1, bit_errors=2)
    with assert_raises():
        _ = LinkCounters(packet_count=-1)
    with assert_raises():
        _ = LinkCounters(evm_error_energy=1.0, evm_reference_energy=0.0)
    with assert_raises():
        _ = LinkCounters(evm_observation_count=1)
    with assert_raises():
        _ = LinkCounters(
            evm_observation_count=0,
            evm_error_energy=1.0,
            evm_reference_energy=1.0,
        )
    with assert_raises():
        _ = LinkCounters(
            evm_error_energy=nan[DType.float64](),
            evm_reference_energy=1.0,
        )

    var integer_limit = LinkCounters(bit_count=Int.MAX)
    with assert_raises():
        integer_limit.merge(LinkCounters(bit_count=1))
    assert_equal(integer_limit.bit_count, Int.MAX)

    var energy_limit = LinkCounters(
        bit_count=7,
        evm_error_energy=Float64.MAX_FINITE,
        evm_reference_energy=Float64.MAX_FINITE,
    )
    with assert_raises():
        energy_limit.merge(
            LinkCounters(evm_error_energy=1.0e308, evm_reference_energy=1.0e308)
        )
    # A failed merge has strong exception safety: no earlier integer field was
    # committed before the EVM overflow was discovered.
    assert_equal(energy_limit.bit_count, 7)
    assert_equal(energy_limit.evm_error_energy, Float64.MAX_FINITE)


def test_wilson_interval_known_vectors_symmetry_and_edges() raises:
    var middle = wilson_interval(5, 10)
    assert_almost_equal(middle.low, 0.23659309051256394, atol=2.0e-15)
    assert_almost_equal(middle.high, 0.7634069094874361, atol=2.0e-15)
    assert_equal(middle.estimate, 0.5)
    assert_almost_equal(middle.half_width, 0.2634069094874361, atol=2.0e-15)

    var zero = wilson_interval(0, 10)
    var all = wilson_interval(10, 10)
    assert_equal(zero.low, 0.0)
    assert_equal(all.high, 1.0)
    assert_almost_equal(zero.high, 0.2775327998628892, atol=2.0e-15)
    assert_almost_equal(all.low, 1.0 - zero.high, atol=2.0e-15)

    var empty = wilson_interval(0, 0)
    assert_equal(empty.estimate, 0.0)
    assert_equal(empty.low, 0.0)
    assert_equal(empty.high, 1.0)
    assert_equal(empty.half_width, 0.5)
    with assert_raises():
        _ = wilson_interval(1, 0)
    with assert_raises():
        _ = wilson_interval(-1, 10)
    with assert_raises():
        _ = wilson_interval(1, 10, z=0.0)
    with assert_raises():
        _ = wilson_interval(1, 10, z=Float64.MAX_FINITE)
    var mutated = wilson_interval(2, 10)
    mutated.half_width = 0.0
    with assert_raises():
        mutated.validate()


def test_monte_carlo_stopping_min_max_error_and_ci_rules() raises:
    var target = MonteCarloStop(
        min_trials=100, max_trials=1000, target_errors=10
    )
    assert_equal(
        monte_carlo_stop_reason(
            LinkCounters(bit_count=99, bit_errors=10),
            target,
            MONTE_CARLO_METRIC_BER,
        ),
        MONTE_CARLO_CONTINUE,
    )
    assert_equal(
        monte_carlo_stop_reason(
            LinkCounters(bit_count=100, bit_errors=10),
            target,
            MONTE_CARLO_METRIC_BER,
        ),
        MONTE_CARLO_STOP_TARGET_ERRORS,
    )
    assert_equal(
        monte_carlo_stop_reason(
            LinkCounters(bit_count=1000, bit_errors=0),
            target,
            MONTE_CARLO_METRIC_BER,
        ),
        MONTE_CARLO_STOP_MAX_TRIALS,
    )

    var absolute = MonteCarloStop(
        min_trials=100,
        max_trials=10000,
        max_absolute_half_width=0.01,
    )
    assert_equal(
        monte_carlo_stop_reason(
            LinkCounters(transport_block_count=1000),
            absolute,
            MONTE_CARLO_METRIC_BLER,
        ),
        MONTE_CARLO_STOP_ABSOLUTE_CI,
    )
    var relative = MonteCarloStop(
        min_trials=100,
        max_trials=20000,
        max_relative_half_width=0.1,
    )
    assert_equal(
        monte_carlo_stop_reason(
            LinkCounters(packet_count=10000, packet_errors=1000),
            relative,
            MONTE_CARLO_METRIC_PER,
        ),
        MONTE_CARLO_STOP_RELATIVE_CI,
    )
    assert_equal(
        monte_carlo_stop_reason(
            LinkCounters(packet_count=10000),
            relative,
            MONTE_CARLO_METRIC_PER,
        ),
        MONTE_CARLO_CONTINUE,
    )
    assert_true(
        should_stop(
            LinkCounters(crc_check_count=100, crc_failures=10),
            target,
            MONTE_CARLO_METRIC_CRC,
        )
    )
    assert_true(
        should_stop(
            LinkCounters(fcs_check_count=100, fcs_failures=10),
            target,
            MONTE_CARLO_METRIC_FCS,
        )
    )
    assert_true(
        should_stop(
            LinkCounters(decoder_attempt_count=100, convergence_failures=10),
            target,
            MONTE_CARLO_METRIC_CONVERGENCE,
        )
    )


def test_monte_carlo_policy_and_metric_validation_edges() raises:
    with assert_raises():
        _ = MonteCarloStop(min_trials=0, max_trials=1)
    with assert_raises():
        _ = MonteCarloStop(min_trials=2, max_trials=1)
    with assert_raises():
        _ = MonteCarloStop(
            min_trials=1, max_trials=2, max_absolute_half_width=0.6
        )
    with assert_raises():
        _ = MonteCarloStop(
            min_trials=1,
            max_trials=2,
            max_relative_half_width=nan[DType.float64](),
        )
    with assert_raises():
        _ = MonteCarloStop(
            min_trials=1, max_trials=2, confidence_z=Float64.MAX_FINITE
        )
    var valid = MonteCarloStop(min_trials=1, max_trials=2)
    with assert_raises():
        _ = monte_carlo_stop_reason(LinkCounters(), valid, 99)
    with assert_raises():
        _ = should_stop(LinkCounters(), valid, 99)


def test_monte_carlo_capacity_caps_and_mutable_revalidation() raises:
    # The exact non-normative trial cap remains legal; its successor and the
    # integer extremes fail during policy construction, before any runner can
    # enter a loop.
    var maximum = MonteCarloStop(min_trials=65_536, max_trials=65_536)
    maximum.validate()
    assert_equal(maximum.max_trials, 65_536)
    with assert_raises():
        _ = MonteCarloStop(min_trials=1, max_trials=65_537)
    with assert_raises():
        _ = MonteCarloStop(min_trials=1, max_trials=Int.MAX)
    with assert_raises():
        _ = MonteCarloStop(min_trials=Int.MIN, max_trials=1)
    with assert_raises():
        _ = MonteCarloStop(min_trials=1, max_trials=Int.MIN)

    var mutated = MonteCarloStop(min_trials=1, max_trials=1)
    mutated.max_trials = Int.MAX
    with assert_raises():
        mutated.validate()
    with assert_raises():
        _ = monte_carlo_stop_reason(
            LinkCounters(), mutated, MONTE_CARLO_METRIC_BER
        )
    with assert_raises():
        _ = should_stop(LinkCounters(), mutated, MONTE_CARLO_METRIC_BER)
    mutated.max_trials = 1
    mutated.min_trials = Int.MIN
    with assert_raises():
        mutated.validate()

    # The allocation cap is checked before the O(N^2) uniqueness walk.  The
    # exact 1,024-point boundary is materialized, while its successor is
    # rejected without attempting an oversized result allocation.
    var protocols = List[UInt64](capacity=1_025)
    for index in range(1_024):
        protocols.append(UInt64(index))
    var mcs: List[UInt64] = [UInt64(1)]
    var snrs: List[LinkSNRPoint] = [LinkSNRPoint(SNR_SAMPLE, 0.0)]
    var snr_ids: List[UInt64] = [UInt64(1)]
    var channels: List[UInt64] = [UInt64(1)]
    var channel_seeds: List[UInt64] = [UInt64(1)]
    var at_capacity = cartesian_link_cases(
        Span(protocols),
        Span(mcs),
        Span(snrs),
        Span(snr_ids),
        Span(channels),
        Span(channel_seeds),
    )
    assert_equal(len(at_capacity), 1_024)
    var mutated_snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_SAMPLE, 0.0)
    ]
    mutated_snrs[0].db = nan[DType.float64]()
    with assert_raises():
        _ = cartesian_link_cases(
            Span(protocols),
            Span(mcs),
            Span(mutated_snrs),
            Span(snr_ids),
            Span(channels),
            Span(channel_seeds),
        )
    protocols.append(UInt64(1_024))
    with assert_raises():
        _ = cartesian_link_cases(
            Span(protocols),
            Span(mcs),
            Span(snrs),
            Span(snr_ids),
            Span(channels),
            Span(channel_seeds),
        )


def test_semantic_seed_is_axis_order_and_shard_stable() raises:
    comptime master = UInt64(0x5EED_2026_0822)
    var baseline = derive_link_seed(
        master, UInt64(5), UInt64(13), UInt64(37), UInt64(4),
        UInt64(99), UInt64(17), LINK_SEED_STREAM_NOISE,
    )
    assert_equal(baseline, UInt64(7558107049404232145))
    assert_equal(
        baseline,
        derive_link_seed(
            master, UInt64(5), UInt64(13), UInt64(37), UInt64(4),
            UInt64(99), UInt64(17), LINK_SEED_STREAM_NOISE,
        ),
    )
    assert_true(
        baseline
        != derive_link_seed(
            master, UInt64(5), UInt64(13), UInt64(37), UInt64(4),
            UInt64(99), UInt64(17), LINK_SEED_STREAM_PAYLOAD,
        )
    )
    assert_true(
        derive_link_seed(
            master, UInt64(5), UInt64(13), UInt64(37), UInt64(4),
            UInt64(99), UInt64(17), LINK_SEED_STREAM_CHANNEL,
        )
        != derive_link_seed(
            master, UInt64(5), UInt64(13), UInt64(37), UInt64(4),
            UInt64(99), UInt64(17), LINK_SEED_STREAM_IMPAIRMENT,
        )
    )
    var boundary = derive_link_seed(
        UInt64.MAX,
        UInt64(0),
        UInt64.MAX,
        UInt64(0),
        UInt64.MAX,
        UInt64(0),
        UInt64.MAX,
        UInt64.MAX,
    )
    assert_equal(
        boundary,
        derive_link_seed(
            UInt64.MAX,
            UInt64(0),
            UInt64.MAX,
            UInt64(0),
            UInt64.MAX,
            UInt64(0),
            UInt64.MAX,
            UInt64.MAX,
        ),
    )

    # Trial indices are global semantic coordinates.  A contiguous run and
    # two interleaved shards therefore reconstruct exactly the same seeds.
    var contiguous = List[UInt64](capacity=64)
    var reconstructed = List[UInt64](length=64, fill=UInt64(0))
    for trial in range(64):
        var seed = derive_link_seed(
            master, UInt64(5), UInt64(13), UInt64(37), UInt64(4),
            UInt64(99), UInt64(trial), LINK_SEED_STREAM_NOISE,
        )
        contiguous.append(seed)
    for shard in range(2):
        for trial in range(shard, 64, 2):
            reconstructed[trial] = derive_link_seed(
                master, UInt64(5), UInt64(13), UInt64(37), UInt64(4),
                UInt64(99), UInt64(trial), LINK_SEED_STREAM_NOISE,
            )
    for trial in range(64):
        assert_equal(contiguous[trial], reconstructed[trial])


def test_seeded_stop_seed_and_sweep_point_independent_oracles() raises:
    var seed_state = UInt64(0x4D4F_4E54_4543_4152)
    for trial in range(1021):
        seed_state = (
            seed_state * UInt64(6364136223846793005) + UInt64(1)
        )
        var master = seed_state
        var protocol = seed_state ^ UInt64(trial)
        var mcs = seed_state >> 7
        var snr_identity = seed_state << 11
        var channel = seed_state >> 19
        var channel_seed = seed_state << 23
        var trial_index = UInt64(trial) * UInt64(17)
        var stream = seed_state ^ UInt64(0xC001_D00D)
        assert_equal(
            derive_link_seed(
                master,
                protocol,
                mcs,
                snr_identity,
                channel,
                channel_seed,
                trial_index,
                stream,
            ),
            _oracle_link_seed(
                master,
                protocol,
                mcs,
                snr_identity,
                channel,
                channel_seed,
                trial_index,
                stream,
            ),
        )

    var policy = MonteCarloStop(
        min_trials=10, max_trials=100, target_errors=5
    )
    var link_case = LinkCase(
        UInt64(1), UInt64(2), LinkSNRPoint(SNR_SAMPLE, 3.0),
        UInt64(3000), UInt64(4), UInt64(5),
    )
    for trials in range(121):
        var errors = trials % 9
        if errors > trials:
            errors = trials
        var counters = LinkCounters(
            bit_count=trials, bit_errors=errors
        )
        var expected = MONTE_CARLO_CONTINUE
        if trials >= 100:
            expected = MONTE_CARLO_STOP_MAX_TRIALS
        elif trials >= 10 and errors >= 5:
            expected = MONTE_CARLO_STOP_TARGET_ERRORS
        assert_equal(
            monte_carlo_stop_reason(
                counters, policy, MONTE_CARLO_METRIC_BER
            ),
            expected,
        )
        assert_equal(
            should_stop(counters, policy, MONTE_CARLO_METRIC_BER),
            expected != MONTE_CARLO_CONTINUE,
        )
        var point = make_link_sweep_point(
            link_case, counters, policy, MONTE_CARLO_METRIC_BER
        )
        assert_equal(point.stop_reason, expected)
        assert_equal(point.counters.bit_count, trials)
        assert_equal(point.counters.bit_errors, errors)
        assert_equal(point.link_case.protocol_id, UInt64(1))
        if trials == 0:
            assert_equal(point.interval.estimate, 0.0)
        else:
            assert_almost_equal(
                point.interval.estimate,
                Float64(errors) / Float64(trials),
                atol=1.0e-15,
                rtol=1.0e-15,
            )


def test_cartesian_cases_have_documented_order_and_semantic_seeds() raises:
    var protocols: List[UInt64] = [UInt64(10), UInt64(20)]
    var mcs: List[UInt64] = [UInt64(3), UInt64(7)]
    var snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_ESN0_DATA, 0.0),
        LinkSNRPoint(SNR_ESN0_DATA, 5.0),
    ]
    var snr_ids: List[UInt64] = [UInt64(100), UInt64(105)]
    var channels: List[UInt64] = [UInt64(1), UInt64(2)]
    var channel_seeds: List[UInt64] = [UInt64(41), UInt64(43)]
    var cases = cartesian_link_cases(
        Span(protocols),
        Span(mcs),
        Span(snrs),
        Span(snr_ids),
        Span(channels),
        Span(channel_seeds),
    )
    assert_equal(len(cases), 32)
    assert_equal(cases[0].protocol_id, UInt64(10))
    assert_equal(cases[0].mcs_id, UInt64(3))
    assert_equal(cases[0].snr_identity, UInt64(100))
    assert_equal(cases[0].channel_id, UInt64(1))
    assert_equal(cases[0].channel_seed_identity, UInt64(41))
    assert_equal(cases[1].channel_seed_identity, UInt64(43))
    assert_equal(cases[2].channel_id, UInt64(2))
    assert_equal(cases[4].snr_identity, UInt64(105))
    assert_equal(cases[8].mcs_id, UInt64(7))
    assert_equal(cases[16].protocol_id, UInt64(20))

    var reordered_protocols: List[UInt64] = [UInt64(20), UInt64(10)]
    var reordered_mcs: List[UInt64] = [UInt64(7), UInt64(3)]
    var reordered_snrs: List[LinkSNRPoint] = [
        LinkSNRPoint(SNR_ESN0_DATA, 5.0),
        LinkSNRPoint(SNR_ESN0_DATA, 0.0),
    ]
    var reordered_snr_ids: List[UInt64] = [UInt64(105), UInt64(100)]
    var reordered_channels: List[UInt64] = [UInt64(2), UInt64(1)]
    var reordered_channel_seeds: List[UInt64] = [UInt64(43), UInt64(41)]
    var reordered = cartesian_link_cases(
        Span(reordered_protocols),
        Span(reordered_mcs),
        Span(reordered_snrs),
        Span(reordered_snr_ids),
        Span(reordered_channels),
        Span(reordered_channel_seeds),
    )
    # The target coordinate is first in the original and last after reversing
    # every axis.  Its semantic seed is identical despite loop-order changes.
    var first_seed = derive_link_seed(
        UInt64(1234),
        cases[0].protocol_id,
        cases[0].mcs_id,
        cases[0].snr_identity,
        cases[0].channel_id,
        cases[0].channel_seed_identity,
        UInt64(9),
        LINK_SEED_STREAM_NOISE,
    )
    var last = len(reordered) - 1
    var reordered_seed = derive_link_seed(
        UInt64(1234),
        reordered[last].protocol_id,
        reordered[last].mcs_id,
        reordered[last].snr_identity,
        reordered[last].channel_id,
        reordered[last].channel_seed_identity,
        UInt64(9),
        LINK_SEED_STREAM_NOISE,
    )
    assert_equal(first_seed, reordered_seed)


def test_cartesian_and_sweep_point_validation_edges() raises:
    var empty_ids = List[UInt64]()
    var one_protocol: List[UInt64] = [UInt64(1)]
    var one_mcs: List[UInt64] = [UInt64(1)]
    var one_channel: List[UInt64] = [UInt64(1)]
    var one_channel_seed: List[UInt64] = [UInt64(1)]
    var duplicate_ids: List[UInt64] = [UInt64(1), UInt64(1)]
    var snrs: List[LinkSNRPoint] = [LinkSNRPoint(SNR_SAMPLE, 0.0)]
    var snr_ids: List[UInt64] = [UInt64(0)]
    with assert_raises():
        _ = cartesian_link_cases(
            Span(empty_ids), Span(one_mcs), Span(snrs), Span(snr_ids),
            Span(one_channel), Span(one_channel_seed),
        )
    with assert_raises():
        _ = cartesian_link_cases(
            Span(duplicate_ids), Span(one_mcs), Span(snrs), Span(snr_ids),
            Span(one_channel), Span(one_channel_seed),
        )
    with assert_raises():
        _ = cartesian_link_cases(
            Span(one_protocol), Span(one_mcs), Span(snrs), Span(empty_ids),
            Span(one_channel), Span(one_channel_seed),
        )

    var link_case = LinkCase(
        UInt64(1), UInt64(2), LinkSNRPoint(SNR_SAMPLE, 3.0),
        UInt64(3000), UInt64(4), UInt64(5),
    )
    var counters = LinkCounters(packet_count=100, packet_errors=10)
    var policy = MonteCarloStop(
        min_trials=50, max_trials=1000, target_errors=10
    )
    var point = make_link_sweep_point(
        link_case, counters, policy, MONTE_CARLO_METRIC_PER
    )
    assert_equal(point.link_case.protocol_id, UInt64(1))
    assert_equal(point.counters.packet_errors, 10)
    assert_equal(point.interval.estimate, 0.1)
    assert_equal(point.stop_reason, MONTE_CARLO_STOP_TARGET_ERRORS)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
