"""CPU-only NR PUSCH Monte-Carlo execution over AWGN and 3GPP TDL.

The runner uses the standards-facing PUSCH waveform chain and the exact NR
MCS/TBS tables.  AWGN is injected in the complex sample domain.  CP-OFDM RX
then converts that variance to ``N * N0 / |H[k]|^2`` independently for every
data tone; no scalar post-equalizer variance stands in for a frequency-
selective channel.

Payload, channel, and Gaussian streams use domain-separated semantic seeds.
The runner deliberately uses common random numbers across SNR coordinates by
omitting the SNR identity from those three seed derivations.  Case reporting
retains the true SNR identity, and trial indices remain global, so axis
reordering and disjoint shards reproduce the same trials exactly.
"""

from std.collections import Span
from std.math import ceil, isfinite
from wireless_dsp.core import Complex64
from wireless_dsp.channel import (
    add_awgn,
    apply_standard_channel,
    tdl_profile,
)
from wireless_dsp.wireless.nr.mcs_tbs import (
    NRMCSProfile,
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
from .monte_carlo import (
    SNR_ESN0_DATA,
    SNR_EBN0_INFORMATION,
    MONTE_CARLO_METRIC_BLER,
    MONTE_CARLO_CONTINUE,
    LINK_SEED_STREAM_PAYLOAD,
    LINK_SEED_STREAM_CHANNEL,
    LINK_SEED_STREAM_NOISE,
    LinkSNRPoint,
    LinkEnergyReference,
    LinkCounters,
    MonteCarloStop,
    LinkCase,
    LinkSweepPoint,
    link_noise_variance,
    wilson_interval,
    monte_carlo_stop_reason,
    derive_link_seed,
)


comptime NR_LINK_PROTOCOL_PUSCH = UInt64(0x4E525055534348)

comptime NR_LINK_CHANNEL_AWGN = 0
comptime NR_LINK_CHANNEL_TDL_A = 1
comptime NR_LINK_CHANNEL_TDL_C = 2
comptime NR_LINK_CHANNEL_TDL_D = 3

# Non-normative deterministic CPU-reference resource bounds.  They constrain
# execution cost only and do not replace any 3GPP profile or table limit.
comptime _MAX_NR_MONTE_CARLO_FFT_SIZE = 4_096
comptime _MAX_NR_MONTE_CARLO_RESOURCE_BLOCKS = 275
comptime _MAX_NR_MONTE_CARLO_WAVEFORM_SAMPLES = 65_536
comptime _MAX_NR_MONTE_CARLO_TBS_BITS = 1_048_576
comptime _MAX_NR_MONTE_CARLO_ITERATIONS = 256
comptime _MAX_NR_MONTE_CARLO_TRIALS = 65_536
comptime _MAX_NR_MONTE_CARLO_SWEEP_POINTS = 1_024
comptime _MAX_NR_MONTE_CARLO_SWEEP_WORK = 65_536


def _validate_nr_link_channel(channel_model: Int) raises:
    if (
        channel_model != NR_LINK_CHANNEL_AWGN
        and channel_model != NR_LINK_CHANNEL_TDL_A
        and channel_model != NR_LINK_CHANNEL_TDL_C
        and channel_model != NR_LINK_CHANNEL_TDL_D
    ):
        raise Error("NR link channel must be AWGN or TDL-A/C/D")


def _validate_pusch_config(config: NRPUSCHConfig) raises:
    _ = NRPUSCHConfig(
        config.fft_size,
        config.cyclic_prefix,
        config.symbol_count,
        config.dmrs_symbol,
        config.first_subcarrier,
        config.resource_blocks,
        config.slot,
        config.n_id,
        config.n_scid,
        config.rnti,
        config.codeword,
        dmrs_n_id=config.dmrs_n_id,
        transform_precoding=config.transform_precoding,
        dmrs_cyclic_shift=config.dmrs_cyclic_shift,
    )


struct NRPUSCHLinkSetup(ImplicitlyCopyable):
    """Physical PUSCH allocation shared by every MCS and channel case.

    The runner is intentionally CP-OFDM and single-layer.  Sample rate is
    ``fft_size * subcarrier_spacing_hz``.  A TDL case is accepted only when
    its maximum sampled delay does not exceed the configured cyclic prefix.
    The scalar CPU reference additionally caps FFT size at 4,096, scheduled
    PRBs at 275, waveform samples at 65,536, transport blocks at 1,048,576
    bits, and LDPC iterations at 256.  These are non-normative work bounds.
    """

    var pusch: NRPUSCHConfig
    var mcs_table: Int
    var redundancy_version: Int
    var subcarrier_spacing_hz: Float64
    var tdl_delay_spread_ns: Float64
    var max_iterations: Int

    def __init__(
        out self,
        pusch: NRPUSCHConfig,
        mcs_table: Int,
        *,
        redundancy_version: Int = 0,
        subcarrier_spacing_hz: Float64 = 30000.0,
        tdl_delay_spread_ns: Float64 = 30.0,
        max_iterations: Int = 30,
    ) raises:
        _validate_pusch_config(pusch)
        if pusch.transform_precoding:
            raise Error("NR Monte-Carlo runner requires CP-OFDM PUSCH")
        if (
            pusch.fft_size > _MAX_NR_MONTE_CARLO_FFT_SIZE
            or pusch.resource_blocks > _MAX_NR_MONTE_CARLO_RESOURCE_BLOCKS
        ):
            raise Error("NR PUSCH setup exceeds the CPU geometry capacity")
        if (
            pusch.fft_size + pusch.cyclic_prefix
            > _MAX_NR_MONTE_CARLO_WAVEFORM_SAMPLES // pusch.symbol_count
        ):
            raise Error("NR PUSCH waveform exceeds the CPU sample capacity")
        if redundancy_version < 0 or redundancy_version > 3:
            raise Error("NR Monte-Carlo redundancy version must be in [0,3]")
        if (
            not isfinite(subcarrier_spacing_hz)
            or subcarrier_spacing_hz <= 0.0
            or not isfinite(
                Float64(pusch.fft_size) * subcarrier_spacing_hz
            )
        ):
            raise Error("NR Monte-Carlo subcarrier spacing is invalid")
        if (
            not isfinite(tdl_delay_spread_ns)
            or tdl_delay_spread_ns <= 0.0
        ):
            raise Error("NR Monte-Carlo TDL delay spread is invalid")
        if (
            max_iterations < 1
            or max_iterations > _MAX_NR_MONTE_CARLO_ITERATIONS
        ):
            raise Error("NR Monte-Carlo decoder iteration limit is invalid")
        # Validate the table without selecting a sweep index yet.  Every
        # supported table has a non-reserved row zero.
        _ = nr_mcs_profile(mcs_table, 0)
        self.pusch = pusch
        self.mcs_table = mcs_table
        self.redundancy_version = redundancy_version
        self.subcarrier_spacing_hz = subcarrier_spacing_hz
        self.tdl_delay_spread_ns = tdl_delay_spread_ns
        self.max_iterations = max_iterations

    def validate(self) raises:
        _ = NRPUSCHLinkSetup(
            self.pusch,
            self.mcs_table,
            redundancy_version=self.redundancy_version,
            subcarrier_spacing_hz=self.subcarrier_spacing_hz,
            tdl_delay_spread_ns=self.tdl_delay_spread_ns,
            max_iterations=self.max_iterations,
        )

    def sample_rate_hz(self) raises -> Float64:
        self.validate()
        return Float64(self.pusch.fft_size) * self.subcarrier_spacing_hz

    def profile(self, mcs_index: Int) raises -> NRMCSProfile:
        self.validate()
        return nr_mcs_profile(self.mcs_table, mcs_index)

    def transport_block_size(self, mcs_index: Int) raises -> Int:
        var profile = self.profile(mcs_index)
        var result = nr_transport_block_size(
            nr_pusch_data_re_count(self.pusch), profile, 1
        )
        if result > _MAX_NR_MONTE_CARLO_TBS_BITS:
            raise Error("NR PUSCH transport block exceeds the CPU capacity")
        return result


struct NRPUSCHLinkPoint(ImplicitlyCopyable):
    """One NR PUSCH case plus its exact MCS/TBS and generic link result."""

    var mcs: NRMCSProfile
    var transport_block_size: Int
    var result: LinkSweepPoint

    def __init__(
        out self,
        mcs: NRMCSProfile,
        transport_block_size: Int,
        result: LinkSweepPoint,
    ) raises:
        mcs.validate()
        if transport_block_size < 24 or transport_block_size % 8 != 0:
            raise Error("NR PUSCH link TBS must be a positive octet count")
        self.mcs = mcs
        self.transport_block_size = transport_block_size
        self.result = result


def _nr_link_mcs_identity(table: Int, index: Int) -> UInt64:
    return UInt64(64 * table + index)


def _next_payload_bit(mut state: UInt64) -> UInt8:
    state = (
        state * UInt64(6364136223846793005)
        + UInt64(1442695040888963407)
    )
    return UInt8((state >> 63) & UInt64(1))


def _payload(length: Int, seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=length)
    for _ in range(length):
        result.append(_next_payload_bit(state))
    return result^


def _waveform_energy(values: Span[Complex64, ...]) raises -> Float64:
    if len(values) == 0:
        raise Error("NR PUSCH waveform must be non-empty")
    var result = 0.0
    for index in range(len(values)):
        if (
            not isfinite(values[index].re)
            or not isfinite(values[index].im)
        ):
            raise Error("NR PUSCH waveform energy requires finite samples")
        result += (
            values[index].re * values[index].re
            + values[index].im * values[index].im
        )
        if not isfinite(result):
            raise Error("NR PUSCH waveform energy overflows Float64")
    if result <= 0.0:
        raise Error("NR PUSCH waveform energy must be positive")
    return result


def _sample_noise_variance(
    snr: LinkSNRPoint,
    waveform_energy: Float64,
    waveform_samples: Int,
    payload_bits: Int,
    fft_size: Int,
) raises -> Float64:
    if snr.mode == SNR_ESN0_DATA:
        # The QAM mapper has nominal Es=1 in the frequency-domain basis.  The
        # inverse FFT uses 1/N, so sample N0 must be divided by N before AWGN.
        var frequency_noise = link_noise_variance(
            snr,
            LinkEnergyReference(data_symbol_energy=1.0),
        )
        var sample_noise = frequency_noise / Float64(fft_size)
        if not isfinite(sample_noise) or sample_noise <= 0.0:
            raise Error("NR PUSCH Es/N0 sample variance is unrepresentable")
        return sample_noise
    if snr.mode == SNR_EBN0_INFORMATION:
        # This exact packet energy includes DM-RS, inactive tones, every IFFT,
        # and every cyclic prefix in the transmitted waveform scope.
        return link_noise_variance(
            snr,
            LinkEnergyReference(
                waveform_energy=waveform_energy,
                information_bits=payload_bits,
                sample_count=waveform_samples,
            ),
        )
    raise Error("NR PUSCH runner supports Es/N0 or exact information Eb/N0")


def _tdl_model_name(channel_model: Int) raises -> String:
    if channel_model == NR_LINK_CHANNEL_TDL_A:
        return String("A")
    if channel_model == NR_LINK_CHANNEL_TDL_C:
        return String("C")
    if channel_model == NR_LINK_CHANNEL_TDL_D:
        return String("D")
    raise Error("NR link channel is not a TDL profile")


def _channel_waveform(
    waveform: Span[Complex64, ...],
    setup: NRPUSCHLinkSetup,
    channel_model: Int,
    channel_seed: UInt64,
) raises -> List[Complex64]:
    _validate_nr_link_channel(channel_model)
    if channel_model == NR_LINK_CHANNEL_AWGN:
        var copied = List[Complex64](capacity=len(waveform))
        for index in range(len(waveform)):
            copied.append(
                Complex64(waveform[index].re, waveform[index].im)
            )
        return copied^
    var profile = tdl_profile(
        _tdl_model_name(channel_model),
        desired_delay_spread_ns=setup.tdl_delay_spread_ns,
    )
    var sample_rate = setup.sample_rate_hz()
    var maximum_delay_samples = (
        profile.maximum_delay_ns() * sample_rate * 1.0e-9
    )
    if (
        not isfinite(maximum_delay_samples)
        or Int(ceil(maximum_delay_samples)) > setup.pusch.cyclic_prefix
    ):
        raise Error("NR PUSCH TDL delay exceeds the configured cyclic prefix")
    var full = apply_standard_channel(
        waveform,
        profile,
        sample_rate,
        maximum_doppler_hz=0.0,
        seed=channel_seed,
    )
    if len(full) < len(waveform):
        raise Error("NR PUSCH channel output is unexpectedly short")
    var result = List[Complex64](capacity=len(waveform))
    for index in range(len(waveform)):
        result.append(Complex64(full[index].re, full[index].im))
    return result^


def _evm_energies(
    actual: Span[Complex64, ...], expected: Span[Complex64, ...]
) raises -> Tuple[Float64, Float64]:
    if len(actual) != len(expected) or len(actual) == 0:
        raise Error("NR PUSCH EVM vectors must be equal and non-empty")
    var error_energy = 0.0
    var reference_energy = 0.0
    for index in range(len(actual)):
        if (
            not isfinite(actual[index].re)
            or not isfinite(actual[index].im)
            or not isfinite(expected[index].re)
            or not isfinite(expected[index].im)
        ):
            raise Error("NR PUSCH EVM vectors must remain finite")
        var delta_re = actual[index].re - expected[index].re
        var delta_im = actual[index].im - expected[index].im
        error_energy += delta_re * delta_re + delta_im * delta_im
        reference_energy += (
            expected[index].re * expected[index].re
            + expected[index].im * expected[index].im
        )
        if not isfinite(error_energy) or not isfinite(reference_energy):
            raise Error("NR PUSCH EVM energy overflows Float64")
    if reference_energy <= 0.0:
        raise Error("NR PUSCH EVM reference energy must be positive")
    return (error_energy, reference_energy)


def _link_case(
    setup: NRPUSCHLinkSetup,
    mcs_index: Int,
    snr: LinkSNRPoint,
    snr_identity: UInt64,
    channel_model: Int,
    channel_seed_identity: UInt64,
) raises -> LinkCase:
    _validate_nr_link_channel(channel_model)
    _ = setup.profile(mcs_index)
    return LinkCase(
        NR_LINK_PROTOCOL_PUSCH,
        _nr_link_mcs_identity(setup.mcs_table, mcs_index),
        snr,
        snr_identity,
        UInt64(channel_model),
        channel_seed_identity,
    )


def _simulate_nr_pusch_trial(
    setup: NRPUSCHLinkSetup,
    mcs: NRMCSProfile,
    transport_block_size: Int,
    snr: LinkSNRPoint,
    channel_model: Int,
    channel_seed_identity: UInt64,
    master_seed: UInt64,
    trial_index: UInt64,
) raises -> LinkCounters:
    var mcs_identity = _nr_link_mcs_identity(mcs.table, mcs.index)
    # SNR identity zero intentionally selects common random numbers across SNR.
    var payload_seed = derive_link_seed(
        master_seed,
        NR_LINK_PROTOCOL_PUSCH,
        mcs_identity,
        UInt64(0),
        UInt64(channel_model),
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_PAYLOAD,
    )
    var channel_seed = derive_link_seed(
        master_seed,
        NR_LINK_PROTOCOL_PUSCH,
        mcs_identity,
        UInt64(0),
        UInt64(channel_model),
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_CHANNEL,
    )
    var noise_seed = derive_link_seed(
        master_seed,
        NR_LINK_PROTOCOL_PUSCH,
        mcs_identity,
        UInt64(0),
        UInt64(channel_model),
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_NOISE,
    )
    var payload = _payload(transport_block_size, payload_seed)
    var transmit = nr_pusch_encode_transport_block(
        Span(payload),
        nr_mcs_target_code_rate(mcs),
        mcs.modulation_order,
        setup.redundancy_version,
        setup.pusch,
    )
    var waveform_energy = _waveform_energy(Span(transmit.waveform))
    var sample_noise = _sample_noise_variance(
        snr,
        waveform_energy,
        len(transmit.waveform),
        transport_block_size,
        setup.pusch.fft_size,
    )
    var faded = _channel_waveform(
        Span(transmit.waveform), setup, channel_model, channel_seed
    )
    var received = add_awgn(
        Span(faded), sample_noise, seed=noise_seed
    )
    var decoded = nr_pusch_decode_waveform(
        Span(received),
        setup.pusch,
        Span(transmit.encoded_null_mask),
        transmit.profile,
        transport_block_size,
        mcs.modulation_order,
        setup.redundancy_version,
        sample_noise_variance=sample_noise,
        max_iterations=setup.max_iterations,
    )
    if len(decoded.payload) != transport_block_size:
        raise Error("NR PUSCH decoder returned an unexpected payload length")
    var bit_errors = 0
    for index in range(transport_block_size):
        if decoded.payload[index] != payload[index]:
            bit_errors += 1
    var crc_failure = 0 if decoded.transport_crc_ok else 1
    var block_failure = crc_failure
    var packet_failure = 1 if bit_errors > 0 or crc_failure != 0 else 0
    var convergence_failure = 0 if decoded.ldpc_converged else 1
    var evm = _evm_energies(
        Span(decoded.equalized_symbols), Span(transmit.modulated_symbols)
    )
    return LinkCounters(
        bit_count=transport_block_size,
        bit_errors=bit_errors,
        transport_block_count=1,
        transport_block_errors=block_failure,
        packet_count=1,
        packet_errors=packet_failure,
        crc_check_count=1,
        crc_failures=crc_failure,
        decoder_attempt_count=1,
        convergence_failures=convergence_failure,
        evm_error_energy=evm[0],
        evm_reference_energy=evm[1],
    )


def simulate_nr_pusch_trials(
    setup: NRPUSCHLinkSetup,
    mcs_index: Int,
    snr: LinkSNRPoint,
    snr_identity: UInt64,
    channel_model: Int,
    channel_seed_identity: UInt64,
    master_seed: UInt64,
    first_trial: UInt64,
    trial_count: Int,
) raises -> NRPUSCHLinkPoint:
    """Run an exact global trial range without early stopping.

    Disjoint ranges can be simulated independently and their raw counters
    merged with ``LinkCounters.merge``.  The same full range and merged shards
    produce identical integer metrics and roundoff-equivalent EVM energies.
    A direct shard is limited to 65,536 trials by the CPU reference.
    """
    setup.validate()
    snr.validate()
    _validate_nr_link_channel(channel_model)
    if trial_count < 1:
        raise Error("NR PUSCH trial count must be positive")
    if trial_count > _MAX_NR_MONTE_CARLO_TRIALS:
        raise Error("NR PUSCH trial count exceeds the CPU capacity")
    if first_trial > UInt64.MAX - UInt64(trial_count - 1):
        raise Error("NR PUSCH global trial range overflows UInt64")
    var mcs = setup.profile(mcs_index)
    var transport_block_size = setup.transport_block_size(mcs_index)
    if transport_block_size > Int.MAX // trial_count:
        raise Error("NR PUSCH accumulated bit count overflows Int")
    var counters = LinkCounters()
    for trial in range(trial_count):
        counters.merge(
            _simulate_nr_pusch_trial(
                setup,
                mcs,
                transport_block_size,
                snr,
                channel_model,
                channel_seed_identity,
                master_seed,
                first_trial + UInt64(trial),
            )
        )
    var link_case = _link_case(
        setup,
        mcs_index,
        snr,
        snr_identity,
        channel_model,
        channel_seed_identity,
    )
    return NRPUSCHLinkPoint(
        mcs,
        transport_block_size,
        LinkSweepPoint(
            link_case,
            counters,
            wilson_interval(
                counters.transport_block_errors,
                counters.transport_block_count,
            ),
            MONTE_CARLO_CONTINUE,
        ),
    )


def simulate_nr_pusch_case(
    setup: NRPUSCHLinkSetup,
    mcs_index: Int,
    snr: LinkSNRPoint,
    snr_identity: UInt64,
    channel_model: Int,
    channel_seed_identity: UInt64,
    master_seed: UInt64,
    policy: MonteCarloStop,
    *,
    first_trial: UInt64 = UInt64(0),
) raises -> NRPUSCHLinkPoint:
    """Run one case until its BLER policy fires, checking after each TB."""
    setup.validate()
    snr.validate()
    _validate_nr_link_channel(channel_model)
    policy.validate()
    if first_trial > UInt64.MAX - UInt64(policy.max_trials - 1):
        raise Error("NR PUSCH stopped trial range overflows UInt64")
    var accumulated = LinkCounters()
    var mcs = setup.profile(mcs_index)
    var transport_block_size = setup.transport_block_size(mcs_index)
    if transport_block_size > Int.MAX // policy.max_trials:
        raise Error("NR PUSCH accumulated bit count overflows Int")
    var reason = MONTE_CARLO_CONTINUE
    for trial in range(policy.max_trials):
        accumulated.merge(
            _simulate_nr_pusch_trial(
                setup,
                mcs,
                transport_block_size,
                snr,
                channel_model,
                channel_seed_identity,
                master_seed,
                first_trial + UInt64(trial),
            )
        )
        reason = monte_carlo_stop_reason(
            accumulated, policy, MONTE_CARLO_METRIC_BLER
        )
        if reason != MONTE_CARLO_CONTINUE:
            break
    var link_case = _link_case(
        setup,
        mcs_index,
        snr,
        snr_identity,
        channel_model,
        channel_seed_identity,
    )
    return NRPUSCHLinkPoint(
        mcs,
        transport_block_size,
        LinkSweepPoint(
            link_case,
            accumulated,
            wilson_interval(
                accumulated.transport_block_errors,
                accumulated.transport_block_count,
                z=policy.confidence_z,
            ),
            reason,
        ),
    )


def _checked_sweep_product(lhs: Int, rhs: Int) raises -> Int:
    if lhs < 0 or rhs < 0 or (rhs != 0 and lhs > Int.MAX // rhs):
        raise Error("NR PUSCH sweep point count overflows Int")
    return lhs * rhs


def _require_unique_ints(values: Span[Int, ...]) raises:
    for first in range(len(values)):
        for second in range(first + 1, len(values)):
            if values[first] == values[second]:
                raise Error("NR PUSCH sweep integer axes must be unique")


def _require_unique_u64(values: Span[UInt64, ...]) raises:
    for first in range(len(values)):
        for second in range(first + 1, len(values)):
            if values[first] == values[second]:
                raise Error("NR PUSCH sweep identifier axes must be unique")


def simulate_nr_pusch_sweep(
    setup: NRPUSCHLinkSetup,
    mcs_indices: Span[Int, ...],
    snr_points: Span[LinkSNRPoint, ...],
    snr_identities: Span[UInt64, ...],
    channel_models: Span[Int, ...],
    channel_seed_identities: Span[UInt64, ...],
    master_seed: UInt64,
    policy: MonteCarloStop,
) raises -> List[NRPUSCHLinkPoint]:
    """Run bounded MCS/SNR/channel/channel-seed-major cases.

    At most 1,024 points and 65,536 point-trials are executed by this
    non-normative CPU reference.
    """
    setup.validate()
    policy.validate()
    if (
        len(mcs_indices) == 0
        or len(snr_points) == 0
        or len(snr_points) != len(snr_identities)
        or len(channel_models) == 0
        or len(channel_seed_identities) == 0
    ):
        raise Error("NR PUSCH sweep axes must be non-empty and aligned")
    # Enforce allocation and total-work limits before quadratic uniqueness
    # checks.  Every product is checked before multiplication.
    var point_count = _checked_sweep_product(
        len(mcs_indices), len(snr_points)
    )
    point_count = _checked_sweep_product(point_count, len(channel_models))
    point_count = _checked_sweep_product(
        point_count, len(channel_seed_identities)
    )
    if point_count > _MAX_NR_MONTE_CARLO_SWEEP_POINTS:
        raise Error("NR PUSCH sweep point count exceeds the CPU capacity")
    if point_count > _MAX_NR_MONTE_CARLO_SWEEP_WORK // policy.max_trials:
        raise Error("NR PUSCH sweep work exceeds the CPU capacity")
    _require_unique_ints(mcs_indices)
    _require_unique_u64(snr_identities)
    _require_unique_ints(channel_models)
    _require_unique_u64(channel_seed_identities)
    for mcs_axis in range(len(mcs_indices)):
        _ = setup.profile(mcs_indices[mcs_axis])
    for snr_axis in range(len(snr_points)):
        _ = LinkSNRPoint(
            snr_points[snr_axis].mode, snr_points[snr_axis].db
        )
        if (
            snr_points[snr_axis].mode != SNR_ESN0_DATA
            and snr_points[snr_axis].mode != SNR_EBN0_INFORMATION
        ):
            raise Error("NR PUSCH sweep SNR mode is unsupported")
        if not isfinite(snr_points[snr_axis].db):
            raise Error("NR PUSCH sweep SNR must be finite")
    for channel_axis in range(len(channel_models)):
        _validate_nr_link_channel(channel_models[channel_axis])
    var result = List[NRPUSCHLinkPoint](capacity=point_count)
    for mcs_axis in range(len(mcs_indices)):
        for snr_axis in range(len(snr_points)):
            for channel_axis in range(len(channel_models)):
                for channel_seed_axis in range(
                    len(channel_seed_identities)
                ):
                    result.append(
                        simulate_nr_pusch_case(
                            setup,
                            mcs_indices[mcs_axis],
                            LinkSNRPoint(
                                snr_points[snr_axis].mode,
                                snr_points[snr_axis].db,
                            ),
                            snr_identities[snr_axis],
                            channel_models[channel_axis],
                            channel_seed_identities[channel_seed_axis],
                            master_seed,
                            policy,
                        )
                    )
    return result^
