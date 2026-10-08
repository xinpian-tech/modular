"""Deterministic CPU-only Wi-Fi packet Monte-Carlo reference.

The modeled packets deliberately reuse the repository's bounded acquired PHY
chains rather than inventing an uncoded abstraction:

* HT MCS 6 and VHT MCS 8 traverse SERVICE, scrambling, BCC, L-SIG,
  STF/LTF acquisition, soft Viterbi decoding, and FCS.
* HE MCS 10 and EHT MCS 13 traverse SERVICE, scrambling, the native WLAN
  QC-LDPC matrices, L-SIG, HE/EHT-LTF acquisition, iterative decoding, and
  FCS.

AWGN is added in the complex sample domain with ``N0 = E[|n|^2]``.  The SNR
energy reference is measured exactly on the complete transmit waveform before
the channel.  Since the forward FFT is unnormalised, receivers are given
``Nfft * N0`` as their pre-ZF bin variance.  Frequency-selective runs enable
per-tone ``|H[k]|^2`` LLR weighting after zero forcing.

An acquisition exception is a packet erasure, not a sweep exception.  The
erasure contributes one packet error, one failed synthetic end-to-end FCS
check, one convergence failure, and *all payload bits* as BER errors.  The
last choice is an explicit conservative BER upper-bound convention.  EVM is
accumulated only when acquisition returns corrected constellation symbols.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.channel import (
    add_awgn,
    apply_cfo,
    apply_integer_timing_offset,
    apply_standard_channel,
    wifi_tgn_profile,
    wifi_tgac_profile,
    wifi_tgax_profile,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.acquisition_chain import (
    wifi_acquisition_rx_20mhz,
    wifi_acquisition_tx_20mhz,
)
from wireless_dsp.wireless.wifi.he_eht_acquisition import (
    wifi_he_eht_acquisition_rx_20mhz,
    wifi_he_eht_acquisition_tx_20mhz,
)
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
)
from .monte_carlo import (
    SNR_ESN0_DATA,
    SNR_EBN0_CODED,
    MONTE_CARLO_METRIC_BER,
    MONTE_CARLO_METRIC_PER,
    MONTE_CARLO_METRIC_FCS,
    MONTE_CARLO_METRIC_CONVERGENCE,
    LINK_SEED_STREAM_PAYLOAD,
    LINK_SEED_STREAM_CHANNEL,
    LINK_SEED_STREAM_NOISE,
    LINK_SEED_STREAM_IMPAIRMENT,
    BinomialInterval,
    LinkCounters,
    LinkEnergyReference,
    LinkSNRPoint,
    MonteCarloStop,
    derive_link_seed,
    link_noise_variance,
    monte_carlo_stop_reason,
    should_stop,
    wilson_interval,
)


comptime WIFI_LINK_PROTOCOL = UInt64(0x57494649)
comptime WIFI_LINK_CHANNEL_AWGN = 0
comptime WIFI_LINK_CHANNEL_TGN = 1
comptime WIFI_LINK_CHANNEL_TGAC = 2
comptime WIFI_LINK_CHANNEL_TGAX = 3

comptime _SAMPLE_RATE_HZ = 20.0e6
comptime _MODEL_A = 0
comptime _MODEL_F = 5

# Non-normative deterministic CPU-reference resource bounds.  The payload
# limit is expressed in bits to make the checked octet-to-bit conversion
# explicit; none of these values is an IEEE PHY limit.
comptime _MAX_WIFI_PAYLOAD_BITS = 131_072
comptime _MAX_WIFI_PAYLOAD_OCTETS = _MAX_WIFI_PAYLOAD_BITS // 8
comptime _MAX_WIFI_DECODER_ITERATIONS = 256
comptime _MAX_WIFI_MONTE_CARLO_TRIALS = 65_536
comptime _MAX_WIFI_SWEEP_POINTS = 1_024
comptime _MAX_WIFI_SWEEP_WORK = 65_536


def _validate_family_mcs(family: Int, mcs_index: Int) raises:
    if (
        (family == WIFI_PHY_HT and mcs_index == 6)
        or (family == WIFI_PHY_VHT and mcs_index == 8)
        or (family == WIFI_PHY_HE and mcs_index == 10)
        or (family == WIFI_PHY_EHT and mcs_index == 13)
    ):
        return
    raise Error("Wi-Fi link setup requires HT6, VHT8, HE10, or EHT13")


struct WifiLinkSetup(ImplicitlyCopyable):
    """One bounded 20 MHz Wi-Fi PHY/channel configuration.

    ``channel_model`` uses zero-based A--F indexing.  Standard channel
    profiles are applied to the full packet waveform at 20 Msamples/s.
    ``maximum_timing_offset`` and ``maximum_abs_cfo`` bound deterministic
    impairment values derived solely from the impairment semantic seed.
    This CPU reference accepts at most 131,072 payload bits and 256 decoder
    iterations.  These are execution-capacity bounds, not IEEE limits.
    """

    var family: Int
    var mcs_index: Int
    var payload_octets: Int
    var channel_kind: Int
    var channel_model: Int
    var maximum_doppler_hz: Float64
    var maximum_timing_offset: Int
    var maximum_abs_cfo: Float64
    var detection_threshold: Float64
    var max_iterations: Int

    def __init__(
        out self,
        family: Int,
        mcs_index: Int,
        payload_octets: Int,
        channel_kind: Int,
        *,
        channel_model: Int = 1,
        maximum_doppler_hz: Float64 = 0.0,
        maximum_timing_offset: Int = 3,
        maximum_abs_cfo: Float64 = 0.0015,
        detection_threshold: Float64 = 0.72,
        max_iterations: Int = 20,
    ) raises:
        _validate_family_mcs(family, mcs_index)
        if payload_octets < 1 or payload_octets > _MAX_WIFI_PAYLOAD_OCTETS:
            raise Error("Wi-Fi Monte-Carlo payload exceeds the CPU capacity")
        if (
            channel_kind != WIFI_LINK_CHANNEL_AWGN
            and channel_kind != WIFI_LINK_CHANNEL_TGN
            and channel_kind != WIFI_LINK_CHANNEL_TGAC
            and channel_kind != WIFI_LINK_CHANNEL_TGAX
        ):
            raise Error("unsupported Wi-Fi Monte-Carlo channel")
        if channel_model < _MODEL_A or channel_model > _MODEL_F:
            raise Error("Wi-Fi standard channel model must be A through F")
        if not isfinite(maximum_doppler_hz) or maximum_doppler_hz < 0.0:
            raise Error("Wi-Fi maximum Doppler must be finite/non-negative")
        if maximum_timing_offset < 0 or maximum_timing_offset > 64:
            raise Error("Wi-Fi timing impairment bound must be in 0..64")
        if (
            not isfinite(maximum_abs_cfo)
            or maximum_abs_cfo < 0.0
            or maximum_abs_cfo >= 0.03125
        ):
            raise Error("Wi-Fi CFO bound lies outside STF acquisition range")
        if (
            not isfinite(detection_threshold)
            or detection_threshold < 0.0
            or detection_threshold > 1.0
        ):
            raise Error("Wi-Fi detection threshold must be finite in [0,1]")
        if (
            max_iterations < 1
            or max_iterations > _MAX_WIFI_DECODER_ITERATIONS
        ):
            raise Error("Wi-Fi LDPC iteration count exceeds the CPU capacity")
        self.family = family
        self.mcs_index = mcs_index
        self.payload_octets = payload_octets
        self.channel_kind = channel_kind
        self.channel_model = channel_model
        self.maximum_doppler_hz = maximum_doppler_hz
        self.maximum_timing_offset = maximum_timing_offset
        self.maximum_abs_cfo = maximum_abs_cfo
        self.detection_threshold = detection_threshold
        self.max_iterations = max_iterations

    def validate(self) raises:
        _ = WifiLinkSetup(
            self.family,
            self.mcs_index,
            self.payload_octets,
            self.channel_kind,
            channel_model=self.channel_model,
            maximum_doppler_hz=self.maximum_doppler_hz,
            maximum_timing_offset=self.maximum_timing_offset,
            maximum_abs_cfo=self.maximum_abs_cfo,
            detection_threshold=self.detection_threshold,
            max_iterations=self.max_iterations,
        )

    def mcs_identity(self) -> UInt64:
        return UInt64(self.family * 32 + self.mcs_index)

    def channel_identity(self) -> UInt64:
        return UInt64(self.channel_kind * 8 + self.channel_model)


struct WifiPacketTrial(ImplicitlyCopyable):
    """One packet outcome with reproducible seeds and raw mergeable counts."""

    var counters: LinkCounters
    var payload_seed: UInt64
    var channel_seed: UInt64
    var noise_seed: UInt64
    var impairment_seed: UInt64
    var sample_noise_variance: Float64
    var frequency_bin_noise_variance: Float64
    var data_symbol_energy: Float64
    var bits_per_symbol: Int
    var pre_channel_waveform_energy: Float64
    var pre_channel_sample_count: Int
    var payload_bit_count: Int
    var bit_errors: Int
    var timing_offset: Int
    var normalized_cfo: Float64
    var acquisition_erasure: Bool
    var signal_ok: Bool
    var service_ok: Bool
    var fcs_ok: Bool
    var decoder_converged: Bool
    var per_tone_llr_reliability: Bool

    def __init__(
        out self,
        counters: LinkCounters,
        payload_seed: UInt64,
        channel_seed: UInt64,
        noise_seed: UInt64,
        impairment_seed: UInt64,
        sample_noise_variance: Float64,
        frequency_bin_noise_variance: Float64,
        data_symbol_energy: Float64,
        bits_per_symbol: Int,
        pre_channel_waveform_energy: Float64,
        pre_channel_sample_count: Int,
        payload_bit_count: Int,
        bit_errors: Int,
        timing_offset: Int,
        normalized_cfo: Float64,
        acquisition_erasure: Bool,
        signal_ok: Bool,
        service_ok: Bool,
        fcs_ok: Bool,
        decoder_converged: Bool,
        per_tone_llr_reliability: Bool,
    ):
        self.counters = counters
        self.payload_seed = payload_seed
        self.channel_seed = channel_seed
        self.noise_seed = noise_seed
        self.impairment_seed = impairment_seed
        self.sample_noise_variance = sample_noise_variance
        self.frequency_bin_noise_variance = frequency_bin_noise_variance
        self.data_symbol_energy = data_symbol_energy
        self.bits_per_symbol = bits_per_symbol
        self.pre_channel_waveform_energy = pre_channel_waveform_energy
        self.pre_channel_sample_count = pre_channel_sample_count
        self.payload_bit_count = payload_bit_count
        self.bit_errors = bit_errors
        self.timing_offset = timing_offset
        self.normalized_cfo = normalized_cfo
        self.acquisition_erasure = acquisition_erasure
        self.signal_ok = signal_ok
        self.service_ok = service_ok
        self.fcs_ok = fcs_ok
        self.decoder_converged = decoder_converged
        self.per_tone_llr_reliability = per_tone_llr_reliability


struct WifiLinkPoint(ImplicitlyCopyable):
    """One stopped Wi-Fi Monte-Carlo point and its Wilson interval."""

    var setup: WifiLinkSetup
    var snr: LinkSNRPoint
    var snr_identity: UInt64
    var channel_seed_identity: UInt64
    var first_trial: UInt64
    var packet_trials: Int
    var counters: LinkCounters
    var stop_reason: Int
    var interval: BinomialInterval

    def __init__(
        out self,
        setup: WifiLinkSetup,
        snr: LinkSNRPoint,
        snr_identity: UInt64,
        channel_seed_identity: UInt64,
        first_trial: UInt64,
        packet_trials: Int,
        counters: LinkCounters,
        stop_reason: Int,
        interval: BinomialInterval,
    ):
        self.setup = setup
        self.snr = snr
        self.snr_identity = snr_identity
        self.channel_seed_identity = channel_seed_identity
        self.first_trial = first_trial
        self.packet_trials = packet_trials
        self.counters = counters
        self.stop_reason = stop_reason
        self.interval = interval


struct _WifiTransmit(Movable):
    var waveform: List[Complex64]
    var qam_symbols: List[Complex64]
    var bits_per_subcarrier: Int

    def __init__(
        out self,
        var waveform: List[Complex64],
        var qam_symbols: List[Complex64],
        bits_per_subcarrier: Int,
    ):
        self.waveform = waveform^
        self.qam_symbols = qam_symbols^
        self.bits_per_subcarrier = bits_per_subcarrier


struct _WifiDecodeSummary(ImplicitlyCopyable):
    var acquired: Bool
    var signal_ok: Bool
    var service_ok: Bool
    var fcs_ok: Bool
    var converged: Bool
    var bit_errors: Int
    var evm_error_energy: Float64
    var evm_reference_energy: Float64

    def __init__(out self):
        self.acquired = False
        self.signal_ok = False
        self.service_ok = False
        self.fcs_ok = False
        self.converged = False
        self.bit_errors = 0
        self.evm_error_energy = 0.0
        self.evm_reference_energy = 0.0


def _next_payload_bit(mut state: UInt64) -> UInt8:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return UInt8((state >> 63) & UInt64(1))


def _payload_bits(octets: Int, seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=8 * octets)
    for _ in range(8 * octets):
        result.append(_next_payload_bit(state))
    return result^


def _transmit(
    payload: Span[UInt8, ...],
    setup: WifiLinkSetup,
    scrambler_seed: UInt8,
    symbol_index: Int,
) raises -> _WifiTransmit:
    if setup.family == WIFI_PHY_HT or setup.family == WIFI_PHY_VHT:
        var tx = wifi_acquisition_tx_20mhz(
            payload,
            setup.family,
            setup.mcs_index,
            scrambler_seed=scrambler_seed,
            symbol_index=symbol_index,
            testcase_id="wifi-monte-carlo-bcc",
        )
        return _WifiTransmit(
            tx.packet_waveform.copy(), tx.qam_symbols.copy(),
            6 if setup.family == WIFI_PHY_HT else 8,
        )
    var tx = wifi_he_eht_acquisition_tx_20mhz(
        payload,
        setup.family,
        setup.mcs_index,
        scrambler_seed=scrambler_seed,
        symbol_index=symbol_index,
        testcase_id="wifi-monte-carlo-ldpc",
    )
    return _WifiTransmit(
        tx.packet_waveform.copy(),
        tx.data.qam_symbols.copy(),
        10 if setup.family == WIFI_PHY_HE else 12,
    )


def _waveform_energy(samples: Span[Complex64, ...]) -> Float64:
    var energy = 0.0
    for index in range(len(samples)):
        var sample = Complex64(samples[index].re, samples[index].im)
        energy += sample.magnitude_squared()
    return energy


def _symbol_energy(symbols: Span[Complex64, ...]) -> Float64:
    var energy = _waveform_energy(symbols)
    return energy / Float64(len(symbols))


def _model_name(model: Int) raises -> String:
    if model == 0:
        return String("A")
    if model == 1:
        return String("B")
    if model == 2:
        return String("C")
    if model == 3:
        return String("D")
    if model == 4:
        return String("E")
    if model == 5:
        return String("F")
    raise Error("Wi-Fi standard channel model must be A through F")


def _apply_channel(
    samples: Span[Complex64, ...], setup: WifiLinkSetup, seed: UInt64
) raises -> List[Complex64]:
    if setup.channel_kind == WIFI_LINK_CHANNEL_AWGN:
        var result = List[Complex64](capacity=len(samples))
        for index in range(len(samples)):
            result.append(Complex64(samples[index].re, samples[index].im))
        return result^
    var model = _model_name(setup.channel_model)
    if setup.channel_kind == WIFI_LINK_CHANNEL_TGN:
        var profile = wifi_tgn_profile(model)
        return apply_standard_channel(
            samples,
            profile,
            _SAMPLE_RATE_HZ,
            maximum_doppler_hz=setup.maximum_doppler_hz,
            seed=seed,
        )
    if setup.channel_kind == WIFI_LINK_CHANNEL_TGAC:
        var profile = wifi_tgac_profile(model, bandwidth_mhz=20)
        return apply_standard_channel(
            samples,
            profile,
            _SAMPLE_RATE_HZ,
            maximum_doppler_hz=setup.maximum_doppler_hz,
            seed=seed,
        )
    var profile = wifi_tgax_profile(model, bandwidth_mhz=20)
    return apply_standard_channel(
        samples,
        profile,
        _SAMPLE_RATE_HZ,
        maximum_doppler_hz=setup.maximum_doppler_hz,
        seed=seed,
    )


def _timing_offset(seed: UInt64, maximum: Int) -> Int:
    if maximum == 0:
        return 0
    return Int(seed % UInt64(maximum + 1))


def _normalized_cfo(seed: UInt64, maximum: Float64) -> Float64:
    if maximum == 0.0:
        return 0.0
    var unit = (Float64(seed >> 11) + 0.5) / 9007199254740992.0
    return maximum * (2.0 * unit - 1.0)


def _apply_impairments(
    samples: Span[Complex64, ...], timing_offset: Int, cfo: Float64
) raises -> List[Complex64]:
    var extended = List[Complex64](capacity=len(samples) + timing_offset)
    for index in range(len(samples)):
        extended.append(Complex64(samples[index].re, samples[index].im))
    for _ in range(timing_offset):
        extended.append(Complex64(0.0, 0.0))
    var delayed = apply_integer_timing_offset(Span(extended), timing_offset)
    return apply_cfo(Span(delayed), cfo)


def _hamming_errors(
    expected: Span[UInt8, ...], actual: Span[UInt8, ...]
) -> Int:
    if len(actual) != len(expected):
        return len(expected)
    var errors = 0
    for i in range(len(expected)):
        errors += 1 if expected[i] != actual[i] else 0
    return errors


def _evm_energies(
    expected: Span[Complex64, ...], actual: Span[Complex64, ...]
) -> Tuple[Float64, Float64]:
    if len(actual) != len(expected):
        return (0.0, 0.0)
    var error_energy = 0.0
    var reference_energy = 0.0
    for i in range(len(expected)):
        var dr = actual[i].re - expected[i].re
        var di = actual[i].im - expected[i].im
        error_energy += dr * dr + di * di
        var reference = Complex64(expected[i].re, expected[i].im)
        reference_energy += reference.magnitude_squared()
    return (error_energy, reference_energy)


def _decode_packet(
    observation: Span[Complex64, ...],
    payload: Span[UInt8, ...],
    qam_symbols: Span[Complex64, ...],
    setup: WifiLinkSetup,
    frequency_bin_noise_variance: Float64,
    scrambler_seed: UInt8,
    symbol_index: Int,
) raises -> _WifiDecodeSummary:
    var result = _WifiDecodeSummary()
    if setup.family == WIFI_PHY_HT or setup.family == WIFI_PHY_VHT:
        var rx = wifi_acquisition_rx_20mhz(
            observation,
            setup.family,
            setup.mcs_index,
            len(payload),
            scrambler_seed=scrambler_seed,
            symbol_index=symbol_index,
            detection_threshold=setup.detection_threshold,
            llr_noise_variance=frequency_bin_noise_variance,
            per_tone_llr_reliability=(
                setup.channel_kind != WIFI_LINK_CHANNEL_AWGN
            ),
            testcase_id="wifi-monte-carlo-bcc",
        )
        var evm = _evm_energies(qam_symbols, Span(rx.corrected_data_symbols))
        result.acquired = True
        result.signal_ok = rx.signal_ok
        result.service_ok = rx.service_ok
        result.fcs_ok = rx.fcs_ok
        result.converged = True
        result.bit_errors = _hamming_errors(payload, Span(rx.payload_bits))
        result.evm_error_energy = evm[0]
        result.evm_reference_energy = evm[1]
        return result
    var rx = wifi_he_eht_acquisition_rx_20mhz(
        observation,
        setup.family,
        setup.mcs_index,
        len(payload),
        scrambler_seed=scrambler_seed,
        symbol_index=symbol_index,
        detection_threshold=setup.detection_threshold,
        llr_noise_variance=frequency_bin_noise_variance,
        max_iterations=setup.max_iterations,
        per_tone_llr_reliability=(
            setup.channel_kind != WIFI_LINK_CHANNEL_AWGN
        ),
        testcase_id="wifi-monte-carlo-ldpc",
    )
    var evm = _evm_energies(
        qam_symbols, Span(rx.data.corrected_data_symbols)
    )
    result.acquired = True
    result.signal_ok = rx.signal_ok
    result.service_ok = rx.data.service_ok
    result.fcs_ok = rx.data.fcs_ok
    result.converged = rx.data.ldpc_converged
    result.bit_errors = _hamming_errors(payload, Span(rx.data.payload_bits))
    result.evm_error_energy = evm[0]
    result.evm_reference_energy = evm[1]
    return result


def simulate_wifi_packet_trial(
    setup: WifiLinkSetup,
    snr: LinkSNRPoint,
    *,
    snr_identity: UInt64,
    channel_seed_identity: UInt64,
    trial_index: UInt64,
    master_seed: UInt64,
) raises -> WifiPacketTrial:
    """Run one acquired Wi-Fi packet using four semantic random streams."""
    setup.validate()
    snr.validate()
    var mcs_identity = setup.mcs_identity()
    var channel_identity = setup.channel_identity()
    var payload_seed = derive_link_seed(
        master_seed,
        WIFI_LINK_PROTOCOL,
        mcs_identity,
        snr_identity,
        channel_identity,
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_PAYLOAD,
    )
    var channel_seed = derive_link_seed(
        master_seed,
        WIFI_LINK_PROTOCOL,
        mcs_identity,
        snr_identity,
        channel_identity,
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_CHANNEL,
    )
    var noise_seed = derive_link_seed(
        master_seed,
        WIFI_LINK_PROTOCOL,
        mcs_identity,
        snr_identity,
        channel_identity,
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_NOISE,
    )
    var impairment_seed = derive_link_seed(
        master_seed,
        WIFI_LINK_PROTOCOL,
        mcs_identity,
        snr_identity,
        channel_identity,
        channel_seed_identity,
        trial_index,
        LINK_SEED_STREAM_IMPAIRMENT,
    )
    var payload = _payload_bits(setup.payload_octets, payload_seed)
    var scrambler_seed = UInt8(payload_seed % UInt64(127) + UInt64(1))
    var symbol_index = Int((payload_seed >> 8) % UInt64(127))
    var tx = _transmit(
        Span(payload), setup, scrambler_seed, symbol_index
    )
    var waveform_energy = _waveform_energy(Span(tx.waveform))
    var data_symbol_energy = _symbol_energy(Span(tx.qam_symbols))
    var reference = LinkEnergyReference(
        data_symbol_energy=data_symbol_energy,
        bits_per_symbol=tx.bits_per_subcarrier,
        waveform_energy=waveform_energy,
        information_bits=len(payload),
        sample_count=len(tx.waveform),
    )
    var sample_noise_variance = link_noise_variance(snr, reference)
    var fft_size = (
        64
        if setup.family == WIFI_PHY_HT or setup.family == WIFI_PHY_VHT
        else 256
    )
    if snr.mode == SNR_ESN0_DATA or snr.mode == SNR_EBN0_CODED:
        # Es and coded-Eb are defined in the frequency-domain constellation
        # basis.  The 1/N IFFT maps their requested N0 to N0/N per sample.
        sample_noise_variance /= Float64(fft_size)
        if (
            not isfinite(sample_noise_variance)
            or sample_noise_variance <= 0.0
        ):
            raise Error("Wi-Fi constellation-domain N0 is unrepresentable")
    var frequency_bin_noise_variance = (
        Float64(fft_size) * sample_noise_variance
    )
    if not isfinite(frequency_bin_noise_variance):
        raise Error("Wi-Fi frequency-bin noise variance overflowed")
    var channel_output = _apply_channel(
        Span(tx.waveform), setup, channel_seed
    )
    var timing_offset = _timing_offset(
        impairment_seed, setup.maximum_timing_offset
    )
    var cfo = _normalized_cfo(
        impairment_seed ^ UInt64(0x9E3779B97F4A7C15),
        setup.maximum_abs_cfo,
    )
    var impaired = _apply_impairments(
        Span(channel_output), timing_offset, cfo
    )
    var observation = add_awgn(
        Span(impaired), sample_noise_variance, seed=noise_seed
    )

    # Every receiver exception in this validated bounded chain represents an
    # acquisition/field/decode erasure at this packet coordinate.
    var summary = _WifiDecodeSummary()
    try:
        summary = _decode_packet(
            Span(observation),
            Span(payload),
            Span(tx.qam_symbols),
            setup,
            frequency_bin_noise_variance,
            scrambler_seed,
            symbol_index,
        )
    except:
        summary.bit_errors = len(payload)

    var erasure = not summary.acquired
    var bit_errors = len(payload) if erasure else summary.bit_errors
    var packet_error = (
        erasure
        or not summary.signal_ok
        or not summary.service_ok
        or not summary.fcs_ok
        or not summary.converged
    )
    var fcs_failure = erasure or not summary.fcs_ok
    var convergence_failure = erasure or not summary.converged
    var counters = LinkCounters(
        bit_count=len(payload),
        bit_errors=bit_errors,
        packet_count=1,
        packet_errors=1 if packet_error else 0,
        fcs_check_count=1,
        fcs_failures=1 if fcs_failure else 0,
        decoder_attempt_count=1,
        convergence_failures=1 if convergence_failure else 0,
        evm_error_energy=summary.evm_error_energy,
        evm_reference_energy=summary.evm_reference_energy,
    )
    return WifiPacketTrial(
        counters,
        payload_seed,
        channel_seed,
        noise_seed,
        impairment_seed,
        sample_noise_variance,
        frequency_bin_noise_variance,
        data_symbol_energy,
        tx.bits_per_subcarrier,
        waveform_energy,
        len(tx.waveform),
        len(payload),
        bit_errors,
        timing_offset,
        cfo,
        erasure,
        summary.signal_ok,
        summary.service_ok,
        summary.fcs_ok,
        summary.converged,
        setup.channel_kind != WIFI_LINK_CHANNEL_AWGN,
    )


def simulate_wifi_trials(
    setup: WifiLinkSetup,
    snr: LinkSNRPoint,
    trial_count: Int,
    *,
    snr_identity: UInt64,
    channel_seed_identity: UInt64,
    first_trial: UInt64 = UInt64(0),
    master_seed: UInt64,
) raises -> LinkCounters:
    """Run a deterministic contiguous shard and return only raw statistics.

    A shard contains at most 65,536 packet trials in this non-normative CPU
    reference.  Even an empty shard revalidates mutable setup and SNR fields.
    """
    setup.validate()
    snr.validate()
    if trial_count < 0:
        raise Error("Wi-Fi Monte-Carlo trial count must be non-negative")
    if trial_count > _MAX_WIFI_MONTE_CARLO_TRIALS:
        raise Error("Wi-Fi Monte-Carlo trial count exceeds the CPU capacity")
    if (
        trial_count > 0
        and setup.payload_octets > Int.MAX // 8 // trial_count
    ):
        raise Error("Wi-Fi Monte-Carlo accumulated bit count overflows Int")
    if (
        trial_count > 0
        and UInt64(trial_count - 1) > UInt64.MAX - first_trial
    ):
        raise Error("Wi-Fi Monte-Carlo trial index range overflows UInt64")
    var counters = LinkCounters()
    for offset in range(trial_count):
        var trial = simulate_wifi_packet_trial(
            setup,
            snr,
            snr_identity=snr_identity,
            channel_seed_identity=channel_seed_identity,
            trial_index=first_trial + UInt64(offset),
            master_seed=master_seed,
        )
        counters.merge(trial.counters)
    return counters


def _metric_counts(counters: LinkCounters, metric: Int) raises -> Tuple[Int, Int]:
    if metric == MONTE_CARLO_METRIC_BER:
        return (counters.bit_count, counters.bit_errors)
    if metric == MONTE_CARLO_METRIC_PER:
        return (counters.packet_count, counters.packet_errors)
    if metric == MONTE_CARLO_METRIC_FCS:
        return (counters.fcs_check_count, counters.fcs_failures)
    if metric == MONTE_CARLO_METRIC_CONVERGENCE:
        return (
            counters.decoder_attempt_count, counters.convergence_failures
        )
    raise Error("Wi-Fi sweep supports BER, PER, FCS, or convergence stopping")


def _require_unique_u64(values: Span[UInt64, ...]) raises:
    for first in range(len(values)):
        for second in range(first + 1, len(values)):
            if values[first] == values[second]:
                raise Error("Wi-Fi sweep semantic identity axes must be unique")


def _checked_product(lhs: Int, rhs: Int) raises -> Int:
    if lhs < 0 or rhs < 0 or (rhs != 0 and lhs > Int.MAX // rhs):
        raise Error("Wi-Fi sweep point count overflows Int")
    return lhs * rhs


def simulate_wifi_case(
    setup: WifiLinkSetup,
    snr: LinkSNRPoint,
    policy: MonteCarloStop,
    *,
    snr_identity: UInt64,
    channel_seed_identity: UInt64,
    first_trial: UInt64 = UInt64(0),
    master_seed: UInt64,
    metric: Int = MONTE_CARLO_METRIC_PER,
) raises -> WifiLinkPoint:
    """Run packets until a bounded shared stopping policy fires."""
    setup.validate()
    snr.validate()
    _ = _metric_counts(LinkCounters(), metric)
    policy.validate()
    if setup.payload_octets > Int.MAX // 8 // policy.max_trials:
        raise Error("Wi-Fi Monte-Carlo accumulated bit count overflows Int")
    if first_trial > UInt64.MAX - UInt64(policy.max_trials - 1):
        raise Error("Wi-Fi Monte-Carlo trial index range overflows UInt64")
    var counters = LinkCounters()
    var packet_trials = 0
    while not should_stop(counters, policy, metric):
        var trial = simulate_wifi_packet_trial(
            setup,
            snr,
            snr_identity=snr_identity,
            channel_seed_identity=channel_seed_identity,
            trial_index=first_trial + UInt64(packet_trials),
            master_seed=master_seed,
        )
        counters.merge(trial.counters)
        packet_trials += 1
    var reason = monte_carlo_stop_reason(counters, policy, metric)
    var counts = _metric_counts(counters, metric)
    var interval = wilson_interval(
        counts[1], counts[0], z=policy.confidence_z
    )
    return WifiLinkPoint(
        setup,
        snr,
        snr_identity,
        channel_seed_identity,
        first_trial,
        packet_trials,
        counters,
        reason,
        interval,
    )


def simulate_wifi_sweep(
    setups: Span[WifiLinkSetup, ...],
    snrs: Span[LinkSNRPoint, ...],
    snr_identities: Span[UInt64, ...],
    channel_seed_identities: Span[UInt64, ...],
    policy: MonteCarloStop,
    *,
    master_seed: UInt64,
    metric: Int = MONTE_CARLO_METRIC_PER,
) raises -> List[WifiLinkPoint]:
    """Run a bounded setup/SNR/channel-seed Cartesian product.

    The non-normative CPU reference materializes at most 1,024 points and at
    most 65,536 point-trials across the complete call.
    """
    policy.validate()
    _ = _metric_counts(LinkCounters(), metric)
    if len(snrs) != len(snr_identities):
        raise Error("Wi-Fi SNR values and semantic identities must align")
    if len(setups) == 0 or len(snrs) == 0 or len(channel_seed_identities) == 0:
        raise Error("Wi-Fi sweep axes must be non-empty")
    # Compute both allocation and total-work bounds before the quadratic
    # uniqueness checks or any owned result allocation.
    var point_count = _checked_product(len(setups), len(snrs))
    point_count = _checked_product(point_count, len(channel_seed_identities))
    if point_count > _MAX_WIFI_SWEEP_POINTS:
        raise Error("Wi-Fi sweep point count exceeds the CPU capacity")
    if point_count > _MAX_WIFI_SWEEP_WORK // policy.max_trials:
        raise Error("Wi-Fi sweep work exceeds the CPU capacity")
    _require_unique_u64(snr_identities)
    _require_unique_u64(channel_seed_identities)
    for setup_index in range(len(setups)):
        _ = WifiLinkSetup(
            setups[setup_index].family,
            setups[setup_index].mcs_index,
            setups[setup_index].payload_octets,
            setups[setup_index].channel_kind,
            channel_model=setups[setup_index].channel_model,
            maximum_doppler_hz=setups[setup_index].maximum_doppler_hz,
            maximum_timing_offset=setups[setup_index].maximum_timing_offset,
            maximum_abs_cfo=setups[setup_index].maximum_abs_cfo,
            detection_threshold=setups[setup_index].detection_threshold,
            max_iterations=setups[setup_index].max_iterations,
        )
    for snr_index in range(len(snrs)):
        _ = LinkSNRPoint(snrs[snr_index].mode, snrs[snr_index].db)
    var result = List[WifiLinkPoint](capacity=point_count)
    for setup_index in range(len(setups)):
        var setup = WifiLinkSetup(
            setups[setup_index].family,
            setups[setup_index].mcs_index,
            setups[setup_index].payload_octets,
            setups[setup_index].channel_kind,
            channel_model=setups[setup_index].channel_model,
            maximum_doppler_hz=setups[setup_index].maximum_doppler_hz,
            maximum_timing_offset=setups[setup_index].maximum_timing_offset,
            maximum_abs_cfo=setups[setup_index].maximum_abs_cfo,
            detection_threshold=setups[setup_index].detection_threshold,
            max_iterations=setups[setup_index].max_iterations,
        )
        for snr_index in range(len(snrs)):
            for channel_seed_index in range(len(channel_seed_identities)):
                result.append(simulate_wifi_case(
                    setup,
                    LinkSNRPoint(
                        snrs[snr_index].mode, snrs[snr_index].db
                    ),
                    policy,
                    snr_identity=snr_identities[snr_index],
                    channel_seed_identity=channel_seed_identities[
                        channel_seed_index
                    ],
                    master_seed=master_seed,
                    metric=metric,
                ))
    return result^
