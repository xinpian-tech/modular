"""Composable CPU Monte-Carlo contracts for deterministic link simulation.

All noise conversions in this module return complex noise variance ``N0``,
defined as ``E[|n|^2]``.  Consequently each real component of circular AWGN
has variance ``N0 / 2``.  Energy references are measured before the channel;
fading and other channel gain therefore remain impairments rather than
silently changing the requested SNR.

The statistics API stores raw integer counts and raw EVM energies.  Rates,
intervals, and RMS EVM are derived views, so independently simulated shards
can be merged without averaging already-rounded ratios.
"""

from std.collections import Span
from std.math import exp, isfinite, log, sqrt


comptime SNR_ESN0_DATA = 0
comptime SNR_EBN0_CODED = 1
comptime SNR_EBN0_INFORMATION = 2
comptime SNR_EBN0_INFORMATION_EXACT = SNR_EBN0_INFORMATION
comptime SNR_SAMPLE = 3

comptime MONTE_CARLO_METRIC_BER = 0
comptime MONTE_CARLO_METRIC_BLER = 1
comptime MONTE_CARLO_METRIC_PER = 2
comptime MONTE_CARLO_METRIC_CRC = 3
comptime MONTE_CARLO_METRIC_FCS = 4
comptime MONTE_CARLO_METRIC_CONVERGENCE = 5

comptime MONTE_CARLO_CONTINUE = 0
comptime MONTE_CARLO_STOP_MAX_TRIALS = 1
comptime MONTE_CARLO_STOP_TARGET_ERRORS = 2
comptime MONTE_CARLO_STOP_ABSOLUTE_CI = 3
comptime MONTE_CARLO_STOP_RELATIVE_CI = 4

comptime LINK_SEED_STREAM_PAYLOAD = UInt64(1)
comptime LINK_SEED_STREAM_CHANNEL = UInt64(2)
comptime LINK_SEED_STREAM_NOISE = UInt64(3)
comptime LINK_SEED_STREAM_IMPAIRMENT = UInt64(4)

comptime _LN_10_OVER_10 = 0.230258509299404568401799145468
comptime _DEFAULT_CONFIDENCE_Z = 1.95996398454005423552

# Non-normative deterministic CPU-reference work bounds.  They protect every
# public runner from accidentally turning a malformed setup into an
# effectively unbounded allocation or loop; they are not radio-standard
# limits.
comptime _MAX_MONTE_CARLO_TRIALS = 65_536
comptime _MAX_LINK_SWEEP_POINTS = 1_024


def _validate_snr_mode(mode: Int) raises:
    if (
        mode != SNR_ESN0_DATA
        and mode != SNR_EBN0_CODED
        and mode != SNR_EBN0_INFORMATION
        and mode != SNR_SAMPLE
    ):
        raise Error("link SNR mode is unsupported")


struct LinkSNRPoint(ImplicitlyCopyable):
    """One finite SNR coordinate in decibels with an explicit energy domain."""

    var mode: Int
    var db: Float64

    def __init__(out self, mode: Int, db: Float64) raises:
        _validate_snr_mode(mode)
        if not isfinite(db):
            raise Error("link SNR decibels must be finite")
        self.mode = mode
        self.db = db

    def validate(self) raises:
        _validate_snr_mode(self.mode)
        if not isfinite(self.db):
            raise Error("link SNR decibels must be finite")


struct LinkEnergyReference(ImplicitlyCopyable):
    """Pre-channel energy accounting used to convert a link SNR to ``N0``.

    ``data_symbol_energy`` is the mean energy of one data constellation
    symbol, and ``bits_per_symbol`` is the number of coded bits it carries.
    ``waveform_energy`` is the exact energy over the simulated packet scope,
    including any pilots, prefixes, guards, or headers selected by the caller.
    ``information_bits`` counts only the information bits represented by that
    scope.  ``sample_count`` counts the complex samples in the same scope.

    A conversion validates only the fields required by its SNR mode.  Unused
    floating energy fields may therefore be zero, but no field may be negative
    or non-finite.
    """

    var data_symbol_energy: Float64
    var bits_per_symbol: Int
    var waveform_energy: Float64
    var information_bits: Int
    var sample_count: Int

    def __init__(
        out self,
        *,
        data_symbol_energy: Float64 = 0.0,
        bits_per_symbol: Int = 0,
        waveform_energy: Float64 = 0.0,
        information_bits: Int = 0,
        sample_count: Int = 0,
    ) raises:
        if (
            not isfinite(data_symbol_energy)
            or data_symbol_energy < 0.0
            or not isfinite(waveform_energy)
            or waveform_energy < 0.0
            or bits_per_symbol < 0
            or information_bits < 0
            or sample_count < 0
        ):
            raise Error("link energy reference fields must be finite/non-negative")
        self.data_symbol_energy = data_symbol_energy
        self.bits_per_symbol = bits_per_symbol
        self.waveform_energy = waveform_energy
        self.information_bits = information_bits
        self.sample_count = sample_count

    def validate(self) raises:
        if (
            not isfinite(self.data_symbol_energy)
            or self.data_symbol_energy < 0.0
            or not isfinite(self.waveform_energy)
            or self.waveform_energy < 0.0
            or self.bits_per_symbol < 0
            or self.information_bits < 0
            or self.sample_count < 0
        ):
            raise Error("link energy reference fields must be finite/non-negative")


def _noise_from_log_energy(log_energy: Float64, snr_db: Float64) raises -> Float64:
    var log_noise = log_energy - _LN_10_OVER_10 * snr_db
    if not isfinite(log_noise):
        raise Error("link noise variance logarithm is unrepresentable")
    var noise_variance = exp(log_noise)
    if not isfinite(noise_variance) or noise_variance <= 0.0:
        raise Error("link noise variance is outside positive Float64 range")
    return noise_variance


def _noise_from_energy_quotient(
    numerator: Float64, denominator: Int, snr_db: Float64
) raises -> Float64:
    """Evaluate ``numerator/denominator * 10^(-snr_db/10)`` robustly."""
    var reference_energy = numerator / Float64(denominator)
    var exponent = -_LN_10_OVER_10 * snr_db
    if isfinite(exponent):
        var inverse_snr = exp(exponent)
        if isfinite(inverse_snr) and inverse_snr > 0.0:
            var direct = reference_energy * inverse_snr
            if isfinite(direct) and direct > 0.0:
                return direct
    return _noise_from_log_energy(
        log(numerator) - log(Float64(denominator)), snr_db
    )


def link_noise_variance(
    snr: LinkSNRPoint, energy: LinkEnergyReference
) raises -> Float64:
    """Convert a finite SNR coordinate to complex ``N0 = E[|n|^2]``.

    * ``SNR_ESN0_DATA`` uses ``Es`` from ``data_symbol_energy``.
    * ``SNR_EBN0_CODED`` uses ``Es / bits_per_symbol``.  Coding rate is not
      applied because this mode names energy per transmitted coded bit.
    * ``SNR_EBN0_INFORMATION`` uses the exact packet energy quotient
      ``waveform_energy / information_bits``; it never substitutes a nominal
      ``Es / (Qm * R)`` approximation.
    * ``SNR_SAMPLE`` uses exact mean complex-sample energy
      ``waveform_energy / sample_count``.

    The computation is performed in the log domain so a representable answer
    is not lost to an avoidable intermediate quotient.  A finite dB request
    whose positive ``N0`` cannot be represented is rejected.
    """
    snr.validate()
    energy.validate()
    if snr.mode == SNR_ESN0_DATA:
        if energy.data_symbol_energy <= 0.0:
            raise Error("Es/N0 requires positive data-symbol energy")
        return _noise_from_energy_quotient(
            energy.data_symbol_energy, 1, snr.db
        )
    if snr.mode == SNR_EBN0_CODED:
        if energy.data_symbol_energy <= 0.0 or energy.bits_per_symbol < 1:
            raise Error("coded Eb/N0 requires symbol energy and coded bits/symbol")
        return _noise_from_energy_quotient(
            energy.data_symbol_energy, energy.bits_per_symbol, snr.db
        )
    if snr.mode == SNR_EBN0_INFORMATION:
        if energy.waveform_energy <= 0.0 or energy.information_bits < 1:
            raise Error(
                "information Eb/N0 requires waveform energy and information bits"
            )
        return _noise_from_energy_quotient(
            energy.waveform_energy, energy.information_bits, snr.db
        )
    if energy.waveform_energy <= 0.0 or energy.sample_count < 1:
        raise Error("sample SNR requires waveform energy and complex sample count")
    return _noise_from_energy_quotient(
        energy.waveform_energy, energy.sample_count, snr.db
    )


def _validate_count_pair(total: Int, failures: Int) raises:
    if total < 0 or failures < 0 or failures > total:
        raise Error("link counter failures must be within their non-negative total")


def _checked_counter_add(lhs: Int, rhs: Int) raises -> Int:
    if lhs < 0 or rhs < 0 or lhs > Int.MAX - rhs:
        raise Error("link counter merge overflows Int")
    return lhs + rhs


def _checked_energy_add(lhs: Float64, rhs: Float64) raises -> Float64:
    if not isfinite(lhs) or lhs < 0.0 or not isfinite(rhs) or rhs < 0.0:
        raise Error("link EVM energies must be finite/non-negative")
    var result = lhs + rhs
    if not isfinite(result):
        raise Error("link EVM energy merge overflows Float64")
    return result


struct LinkCounters(ImplicitlyCopyable):
    """Mergeable raw link statistics with independent metric denominators."""

    var bit_count: Int
    var bit_errors: Int
    var transport_block_count: Int
    var transport_block_errors: Int
    var packet_count: Int
    var packet_errors: Int
    var crc_check_count: Int
    var crc_failures: Int
    var fcs_check_count: Int
    var fcs_failures: Int
    var decoder_attempt_count: Int
    var convergence_failures: Int
    var evm_observation_count: Int
    var evm_error_energy: Float64
    var evm_reference_energy: Float64

    def __init__(
        out self,
        *,
        bit_count: Int = 0,
        bit_errors: Int = 0,
        transport_block_count: Int = 0,
        transport_block_errors: Int = 0,
        packet_count: Int = 0,
        packet_errors: Int = 0,
        crc_check_count: Int = 0,
        crc_failures: Int = 0,
        fcs_check_count: Int = 0,
        fcs_failures: Int = 0,
        decoder_attempt_count: Int = 0,
        convergence_failures: Int = 0,
        evm_observation_count: Int = -1,
        evm_error_energy: Float64 = 0.0,
        evm_reference_energy: Float64 = 0.0,
    ) raises:
        _validate_count_pair(bit_count, bit_errors)
        _validate_count_pair(transport_block_count, transport_block_errors)
        _validate_count_pair(packet_count, packet_errors)
        _validate_count_pair(crc_check_count, crc_failures)
        _validate_count_pair(fcs_check_count, fcs_failures)
        _validate_count_pair(decoder_attempt_count, convergence_failures)
        var observations = evm_observation_count
        if observations == -1:
            observations = 0 if evm_reference_energy == 0.0 else 1
        if (
            observations < 0
            or (
                observations == 0
                and (
                    evm_error_energy != 0.0
                    or evm_reference_energy != 0.0
                )
            )
            or (observations > 0 and evm_reference_energy <= 0.0)
            or not isfinite(evm_error_energy)
            or evm_error_energy < 0.0
            or not isfinite(evm_reference_energy)
            or evm_reference_energy < 0.0
        ):
            raise Error("link EVM observations and energies are inconsistent")
        self.bit_count = bit_count
        self.bit_errors = bit_errors
        self.transport_block_count = transport_block_count
        self.transport_block_errors = transport_block_errors
        self.packet_count = packet_count
        self.packet_errors = packet_errors
        self.crc_check_count = crc_check_count
        self.crc_failures = crc_failures
        self.fcs_check_count = fcs_check_count
        self.fcs_failures = fcs_failures
        self.decoder_attempt_count = decoder_attempt_count
        self.convergence_failures = convergence_failures
        self.evm_observation_count = observations
        self.evm_error_energy = evm_error_energy
        self.evm_reference_energy = evm_reference_energy

    def validate(self) raises:
        _validate_count_pair(self.bit_count, self.bit_errors)
        _validate_count_pair(
            self.transport_block_count, self.transport_block_errors
        )
        _validate_count_pair(self.packet_count, self.packet_errors)
        _validate_count_pair(self.crc_check_count, self.crc_failures)
        _validate_count_pair(self.fcs_check_count, self.fcs_failures)
        _validate_count_pair(
            self.decoder_attempt_count, self.convergence_failures
        )
        if (
            self.evm_observation_count < 0
            or (
                self.evm_observation_count == 0
                and (
                    self.evm_error_energy != 0.0
                    or self.evm_reference_energy != 0.0
                )
            )
            or (
                self.evm_observation_count > 0
                and self.evm_reference_energy <= 0.0
            )
            or
            not isfinite(self.evm_error_energy)
            or self.evm_error_energy < 0.0
            or not isfinite(self.evm_reference_energy)
            or self.evm_reference_energy < 0.0
        ):
            raise Error("link EVM observations and energies are inconsistent")

    def merged(self, other: Self) raises -> Self:
        """Return an overflow-checked raw-count merge without mutating inputs."""
        self.validate()
        other.validate()
        return Self(
            bit_count=_checked_counter_add(self.bit_count, other.bit_count),
            bit_errors=_checked_counter_add(self.bit_errors, other.bit_errors),
            transport_block_count=_checked_counter_add(
                self.transport_block_count, other.transport_block_count
            ),
            transport_block_errors=_checked_counter_add(
                self.transport_block_errors, other.transport_block_errors
            ),
            packet_count=_checked_counter_add(
                self.packet_count, other.packet_count
            ),
            packet_errors=_checked_counter_add(
                self.packet_errors, other.packet_errors
            ),
            crc_check_count=_checked_counter_add(
                self.crc_check_count, other.crc_check_count
            ),
            crc_failures=_checked_counter_add(
                self.crc_failures, other.crc_failures
            ),
            fcs_check_count=_checked_counter_add(
                self.fcs_check_count, other.fcs_check_count
            ),
            fcs_failures=_checked_counter_add(
                self.fcs_failures, other.fcs_failures
            ),
            decoder_attempt_count=_checked_counter_add(
                self.decoder_attempt_count, other.decoder_attempt_count
            ),
            convergence_failures=_checked_counter_add(
                self.convergence_failures, other.convergence_failures
            ),
            evm_observation_count=_checked_counter_add(
                self.evm_observation_count, other.evm_observation_count
            ),
            evm_error_energy=_checked_energy_add(
                self.evm_error_energy, other.evm_error_energy
            ),
            evm_reference_energy=_checked_energy_add(
                self.evm_reference_energy, other.evm_reference_energy
            ),
        )

    def merge(mut self, other: Self) raises:
        """Merge ``other`` atomically after every output field is validated."""
        var result = self.merged(other)
        self.bit_count = result.bit_count
        self.bit_errors = result.bit_errors
        self.transport_block_count = result.transport_block_count
        self.transport_block_errors = result.transport_block_errors
        self.packet_count = result.packet_count
        self.packet_errors = result.packet_errors
        self.crc_check_count = result.crc_check_count
        self.crc_failures = result.crc_failures
        self.fcs_check_count = result.fcs_check_count
        self.fcs_failures = result.fcs_failures
        self.decoder_attempt_count = result.decoder_attempt_count
        self.convergence_failures = result.convergence_failures
        self.evm_observation_count = result.evm_observation_count
        self.evm_error_energy = result.evm_error_energy
        self.evm_reference_energy = result.evm_reference_energy

    def ber(self) raises -> Float64:
        self.validate()
        return (
            Float64(self.bit_errors) / Float64(self.bit_count)
            if self.bit_count > 0
            else 0.0
        )

    def bler(self) raises -> Float64:
        self.validate()
        return (
            Float64(self.transport_block_errors)
            / Float64(self.transport_block_count)
            if self.transport_block_count > 0
            else 0.0
        )

    def per(self) raises -> Float64:
        self.validate()
        return (
            Float64(self.packet_errors) / Float64(self.packet_count)
            if self.packet_count > 0
            else 0.0
        )

    def crc_failure_rate(self) raises -> Float64:
        self.validate()
        return (
            Float64(self.crc_failures) / Float64(self.crc_check_count)
            if self.crc_check_count > 0
            else 0.0
        )

    def fcs_failure_rate(self) raises -> Float64:
        self.validate()
        return (
            Float64(self.fcs_failures) / Float64(self.fcs_check_count)
            if self.fcs_check_count > 0
            else 0.0
        )

    def convergence_failure_rate(self) raises -> Float64:
        self.validate()
        return (
            Float64(self.convergence_failures)
            / Float64(self.decoder_attempt_count)
            if self.decoder_attempt_count > 0
            else 0.0
        )

    def evm_rms(self) raises -> Float64:
        """Return measured RMS EVM, rejecting a run with no observations."""
        self.validate()
        if self.evm_observation_count == 0:
            raise Error("link RMS EVM is unavailable without an observation")
        if self.evm_error_energy == 0.0:
            return 0.0
        var result = (
            sqrt(self.evm_error_energy)
            / sqrt(self.evm_reference_energy)
        )
        if not isfinite(result) or result <= 0.0:
            raise Error("link RMS EVM is outside Float64 range")
        return result


struct BinomialInterval(ImplicitlyCopyable):
    """A point estimate and bounded two-sided binomial confidence interval."""

    var estimate: Float64
    var low: Float64
    var high: Float64
    var half_width: Float64

    def __init__(
        out self,
        estimate: Float64,
        low: Float64,
        high: Float64,
    ) raises:
        if (
            not isfinite(estimate)
            or not isfinite(low)
            or not isfinite(high)
            or estimate < 0.0
            or estimate > 1.0
            or low < 0.0
            or high > 1.0
            or low > high
            or estimate < low
            or estimate > high
        ):
            raise Error("binomial interval values are invalid")
        self.estimate = estimate
        self.low = low
        self.high = high
        self.half_width = 0.5 * (high - low)

    def validate(self) raises:
        if (
            not isfinite(self.estimate)
            or not isfinite(self.low)
            or not isfinite(self.high)
            or not isfinite(self.half_width)
            or self.estimate < 0.0
            or self.estimate > 1.0
            or self.low < 0.0
            or self.high > 1.0
            or self.low > self.high
            or self.estimate < self.low
            or self.estimate > self.high
            or self.half_width != 0.5 * (self.high - self.low)
        ):
            raise Error("binomial interval values are invalid")


def wilson_interval(
    errors: Int,
    trials: Int,
    *,
    z: Float64 = _DEFAULT_CONFIDENCE_Z,
) raises -> BinomialInterval:
    """Return a Wilson score interval for a binomial failure probability.

    The empty observation has no point evidence and returns the conservative
    interval ``[0, 1]`` with estimate zero.  This makes empty merge shards
    representable; stopping policies still require their positive
    ``min_trials`` before a confidence-width criterion can fire.
    """
    _validate_count_pair(trials, errors)
    if not isfinite(z) or z <= 0.0:
        raise Error("Wilson confidence z-score must be finite/positive")
    var z_squared = z * z
    if not isfinite(z_squared):
        raise Error("Wilson confidence z-score square overflows Float64")
    if trials == 0:
        return BinomialInterval(0.0, 0.0, 1.0)
    var count = Float64(trials)
    var failures = Float64(errors)
    var estimate = failures / count
    # Algebraically equivalent to the textbook form, but the z/denominator
    # factor is applied before the square root product.  This preserves a
    # bounded interval for every accepted z whose square is representable.
    var denominator = count + z_squared
    var center = (failures + 0.5 * z_squared) / denominator
    var variance_numerator = (
        failures * (1.0 - estimate) + 0.25 * z_squared
    )
    var radius = (z / denominator) * sqrt(variance_numerator)
    var low = min(estimate, max(0.0, center - radius))
    var high = max(estimate, min(1.0, center + radius))
    return BinomialInterval(
        estimate,
        low,
        high,
    )


struct MonteCarloStop(ImplicitlyCopyable):
    """Metric-specific deterministic Monte-Carlo stopping policy.

    A zero target or width disables that optional criterion.  ``max_trials``
    is a hard cap and is checked first.  Other criteria are checked only after
    ``min_trials``.  Relative half-width is measured against the observed
    failure rate and therefore cannot stop a run with zero observed failures.
    The generic CPU reference accepts at most 65,536 trials per case; this is
    a non-normative execution-capacity bound.
    """

    var min_trials: Int
    var max_trials: Int
    var target_errors: Int
    var max_absolute_half_width: Float64
    var max_relative_half_width: Float64
    var confidence_z: Float64

    def __init__(
        out self,
        *,
        min_trials: Int,
        max_trials: Int,
        target_errors: Int = 0,
        max_absolute_half_width: Float64 = 0.0,
        max_relative_half_width: Float64 = 0.0,
        confidence_z: Float64 = _DEFAULT_CONFIDENCE_Z,
    ) raises:
        if (
            min_trials < 1
            or max_trials < min_trials
            or max_trials > _MAX_MONTE_CARLO_TRIALS
            or target_errors < 0
        ):
            raise Error("Monte-Carlo trial and target-error limits are invalid")
        if (
            not isfinite(max_absolute_half_width)
            or max_absolute_half_width < 0.0
            or max_absolute_half_width > 0.5
            or not isfinite(max_relative_half_width)
            or max_relative_half_width < 0.0
            or not isfinite(confidence_z)
            or confidence_z <= 0.0
            or not isfinite(confidence_z * confidence_z)
        ):
            raise Error("Monte-Carlo confidence stopping fields are invalid")
        self.min_trials = min_trials
        self.max_trials = max_trials
        self.target_errors = target_errors
        self.max_absolute_half_width = max_absolute_half_width
        self.max_relative_half_width = max_relative_half_width
        self.confidence_z = confidence_z

    def validate(self) raises:
        if (
            self.min_trials < 1
            or self.max_trials < self.min_trials
            or self.max_trials > _MAX_MONTE_CARLO_TRIALS
            or self.target_errors < 0
            or not isfinite(self.max_absolute_half_width)
            or self.max_absolute_half_width < 0.0
            or self.max_absolute_half_width > 0.5
            or not isfinite(self.max_relative_half_width)
            or self.max_relative_half_width < 0.0
            or not isfinite(self.confidence_z)
            or self.confidence_z <= 0.0
            or not isfinite(self.confidence_z * self.confidence_z)
        ):
            raise Error("Monte-Carlo stopping policy is invalid")


def _metric_counts(counters: LinkCounters, metric: Int) raises -> Tuple[Int, Int]:
    counters.validate()
    if metric == MONTE_CARLO_METRIC_BER:
        return (counters.bit_count, counters.bit_errors)
    if metric == MONTE_CARLO_METRIC_BLER:
        return (
            counters.transport_block_count,
            counters.transport_block_errors,
        )
    if metric == MONTE_CARLO_METRIC_PER:
        return (counters.packet_count, counters.packet_errors)
    if metric == MONTE_CARLO_METRIC_CRC:
        return (counters.crc_check_count, counters.crc_failures)
    if metric == MONTE_CARLO_METRIC_FCS:
        return (counters.fcs_check_count, counters.fcs_failures)
    if metric == MONTE_CARLO_METRIC_CONVERGENCE:
        return (
            counters.decoder_attempt_count,
            counters.convergence_failures,
        )
    raise Error("Monte-Carlo metric is unsupported")


def monte_carlo_stop_reason(
    counters: LinkCounters,
    policy: MonteCarloStop,
    metric: Int,
) raises -> Int:
    """Return a stable reason code, preferring hard cap then error/CI criteria."""
    policy.validate()
    var counts = _metric_counts(counters, metric)
    var trials = counts[0]
    var errors = counts[1]
    if trials >= policy.max_trials:
        return MONTE_CARLO_STOP_MAX_TRIALS
    if trials < policy.min_trials:
        return MONTE_CARLO_CONTINUE
    if policy.target_errors > 0 and errors >= policy.target_errors:
        return MONTE_CARLO_STOP_TARGET_ERRORS
    if (
        policy.max_absolute_half_width > 0.0
        or policy.max_relative_half_width > 0.0
    ):
        var interval = wilson_interval(
            errors, trials, z=policy.confidence_z
        )
        if (
            policy.max_absolute_half_width > 0.0
            and interval.half_width <= policy.max_absolute_half_width
        ):
            return MONTE_CARLO_STOP_ABSOLUTE_CI
        if (
            policy.max_relative_half_width > 0.0
            and errors > 0
            and interval.half_width / interval.estimate
            <= policy.max_relative_half_width
        ):
            return MONTE_CARLO_STOP_RELATIVE_CI
    return MONTE_CARLO_CONTINUE


def should_stop(
    counters: LinkCounters,
    policy: MonteCarloStop,
    metric: Int,
) raises -> Bool:
    """Return whether the metric has met any enabled stopping condition."""
    return monte_carlo_stop_reason(counters, policy, metric) != MONTE_CARLO_CONTINUE


def _mix_link_seed(value: UInt64) -> UInt64:
    """SplitMix64 finalizer used only as a stable semantic seed hash."""
    var mixed = value
    mixed = (mixed ^ (mixed >> 30)) * UInt64(0xBF58476D1CE4E5B9)
    mixed = (mixed ^ (mixed >> 27)) * UInt64(0x94D049BB133111EB)
    return mixed ^ (mixed >> 31)


def derive_link_seed(
    master_seed: UInt64,
    protocol_id: UInt64,
    mcs_id: UInt64,
    snr_identity: UInt64,
    channel_id: UInt64,
    channel_seed_identity: UInt64,
    trial_index: UInt64,
    stream_id: UInt64,
) -> UInt64:
    """Derive one seed solely from semantic coordinates, never loop order.

    Payload, channel, noise, and impairment generators receive distinct
    ``stream_id`` values.  Reordering Cartesian axes or assigning disjoint
    trial-index ranges to shards cannot alter a case seed.  A caller that
    deliberately wants common random numbers across SNR points may pass the
    same ``snr_identity`` to those seed derivations while retaining the real
    SNR identity in ``LinkCase`` for reporting.
    """
    var state = _mix_link_seed(master_seed ^ UInt64(0x243F6A8885A308D3))
    state = _mix_link_seed(
        state ^ _mix_link_seed(protocol_id ^ UInt64(0x13198A2E03707344))
    )
    state = _mix_link_seed(
        state ^ _mix_link_seed(mcs_id ^ UInt64(0xA4093822299F31D0))
    )
    state = _mix_link_seed(
        state ^ _mix_link_seed(snr_identity ^ UInt64(0x082EFA98EC4E6C89))
    )
    state = _mix_link_seed(
        state ^ _mix_link_seed(channel_id ^ UInt64(0x452821E638D01377))
    )
    state = _mix_link_seed(
        state
        ^ _mix_link_seed(
            channel_seed_identity ^ UInt64(0xBE5466CF34E90C6C)
        )
    )
    state = _mix_link_seed(
        state ^ _mix_link_seed(trial_index ^ UInt64(0xC0AC29B7C97C50DD))
    )
    return _mix_link_seed(
        state ^ _mix_link_seed(stream_id ^ UInt64(0x3F84D5B5B5470917))
    )


struct LinkCase(ImplicitlyCopyable):
    """One protocol/MCS/SNR/channel/channel-seed Cartesian coordinate."""

    var protocol_id: UInt64
    var mcs_id: UInt64
    var snr: LinkSNRPoint
    var snr_identity: UInt64
    var channel_id: UInt64
    var channel_seed_identity: UInt64

    def __init__(
        out self,
        protocol_id: UInt64,
        mcs_id: UInt64,
        snr: LinkSNRPoint,
        snr_identity: UInt64,
        channel_id: UInt64,
        channel_seed_identity: UInt64,
    ) raises:
        snr.validate()
        self.protocol_id = protocol_id
        self.mcs_id = mcs_id
        self.snr = snr
        self.snr_identity = snr_identity
        self.channel_id = channel_id
        self.channel_seed_identity = channel_seed_identity

    def seed(
        self,
        master_seed: UInt64,
        trial_index: UInt64,
        stream_id: UInt64,
    ) -> UInt64:
        return derive_link_seed(
            master_seed,
            self.protocol_id,
            self.mcs_id,
            self.snr_identity,
            self.channel_id,
            self.channel_seed_identity,
            trial_index,
            stream_id,
        )


def _checked_case_product(lhs: Int, rhs: Int) raises -> Int:
    if lhs < 0 or rhs < 0 or (rhs != 0 and lhs > Int.MAX // rhs):
        raise Error("link Cartesian sweep point count overflows Int")
    return lhs * rhs


def _require_unique_ids(values: Span[UInt64, ...]) raises:
    for first in range(len(values)):
        for second in range(first + 1, len(values)):
            if values[first] == values[second]:
                raise Error(
                    "link Cartesian semantic identifiers must be unique per axis"
                )


def cartesian_link_cases(
    protocol_ids: Span[UInt64, ...],
    mcs_ids: Span[UInt64, ...],
    snr_points: Span[LinkSNRPoint, ...],
    snr_identities: Span[UInt64, ...],
    channel_ids: Span[UInt64, ...],
    channel_seed_identities: Span[UInt64, ...],
) raises -> List[LinkCase]:
    """Build a checked stable Cartesian sweep.

    Output order is protocol-major, MCS-major, SNR-major, channel-major, then
    channel-seed-major.  Semantic identifiers must be unique within each axis;
    explicit identities, rather than loop indices, feed ``derive_link_seed``.
    At most 1,024 points are materialized by this non-normative CPU reference.
    """
    if (
        len(protocol_ids) == 0
        or len(mcs_ids) == 0
        or len(snr_points) == 0
        or len(channel_ids) == 0
        or len(channel_seed_identities) == 0
        or len(snr_points) != len(snr_identities)
    ):
        raise Error("link Cartesian sweep axes must be non-empty and aligned")
    # Bound the output before the quadratic uniqueness checks and before the
    # owned List allocation.  Each multiplication is overflow-safe.
    var point_count = _checked_case_product(
        len(protocol_ids), len(mcs_ids)
    )
    point_count = _checked_case_product(point_count, len(snr_points))
    point_count = _checked_case_product(point_count, len(channel_ids))
    point_count = _checked_case_product(
        point_count, len(channel_seed_identities)
    )
    if point_count > _MAX_LINK_SWEEP_POINTS:
        raise Error("link Cartesian sweep exceeds the CPU reference capacity")
    _require_unique_ids(protocol_ids)
    _require_unique_ids(mcs_ids)
    _require_unique_ids(snr_identities)
    _require_unique_ids(channel_ids)
    _require_unique_ids(channel_seed_identities)
    for snr_index in range(len(snr_points)):
        _validate_snr_mode(snr_points[snr_index].mode)
        if not isfinite(snr_points[snr_index].db):
            raise Error("link SNR decibels must be finite")
    var result = List[LinkCase](capacity=point_count)
    for protocol_index in range(len(protocol_ids)):
        for mcs_index in range(len(mcs_ids)):
            for snr_index in range(len(snr_points)):
                for channel_index in range(len(channel_ids)):
                    for channel_seed_index in range(
                        len(channel_seed_identities)
                    ):
                        result.append(
                            LinkCase(
                                protocol_ids[protocol_index],
                                mcs_ids[mcs_index],
                                LinkSNRPoint(
                                    snr_points[snr_index].mode,
                                    snr_points[snr_index].db,
                                ),
                                snr_identities[snr_index],
                                channel_ids[channel_index],
                                channel_seed_identities[channel_seed_index],
                            )
                        )
    return result^


struct LinkSweepPoint(ImplicitlyCopyable):
    """One reported case with raw statistics, interval, and stopping reason."""

    var link_case: LinkCase
    var counters: LinkCounters
    var interval: BinomialInterval
    var stop_reason: Int

    def __init__(
        out self,
        link_case: LinkCase,
        counters: LinkCounters,
        interval: BinomialInterval,
        stop_reason: Int,
    ) raises:
        link_case.snr.validate()
        counters.validate()
        interval.validate()
        if (
            stop_reason < MONTE_CARLO_CONTINUE
            or stop_reason > MONTE_CARLO_STOP_RELATIVE_CI
        ):
            raise Error("link sweep stopping reason is invalid")
        self.link_case = link_case
        self.counters = counters
        self.interval = interval
        self.stop_reason = stop_reason


def make_link_sweep_point(
    link_case: LinkCase,
    counters: LinkCounters,
    policy: MonteCarloStop,
    metric: Int,
) raises -> LinkSweepPoint:
    """Materialize a report point from the same metric used for stopping."""
    var counts = _metric_counts(counters, metric)
    return LinkSweepPoint(
        link_case,
        counters,
        wilson_interval(counts[1], counts[0], z=policy.confidence_z),
        monte_carlo_stop_reason(counters, policy, metric),
    )
