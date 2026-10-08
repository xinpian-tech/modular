"""Bounded IEEE 802.11 WUR Data MC-OOK waveform primitives.

This scalar CPU reference implements a deliberately narrow adopted IEEE
802.11 TGba reference construction associated with IEEE Std 802.11-2024
Clause 30.  The profile is one 20 MHz WUR channel, one transmit chain, a
64-point IDFT sampled at 20 MHz, and BPSK coefficients on the adopted nonzero
tones.  It covers the 2 us high-data-rate and 4 us low-data-rate MC-OOK On/Off
reference waveform generators, the seven-bit symbol randomizer, and aligned
modulation of caller-supplied encoded On/Off symbols.

The adopted construction uses six even nonzero tones for the high-rate On
symbol and all twelve non-DC center tones for the low-rate On symbol.  The
useful portions contain 32 and 64 samples; randomization precedes insertion of
8- and 16-sample guard intervals.  It initializes
``G(z)=z^-7+z^-4+1`` to all ones and derives phase sign from X7 and the cyclic
shift index from X3:X1.  Data-symbol indexing here accounts for the preceding
32 or 64 two-microsecond WUR-Sync randomizer updates.

Normative publication: https://standards.ieee.org/ieee/802.11/10548/ .
IEEE 802.11 WG adopted material 11-19/1171r3 fixes the active-tone, IDFT,
truncation and GI construction; 11-18/1567r2 records the adopted symbol
randomizer polynomial, state mapping and complete cyclic-shift tables.
Adopted comment resolution 11-19/1065r2 also states that the Clause 30.3.4.4
waveform construction is an example and actual WUR-Sync/WUR-Data waveform
generation is implementation-dependent.  These APIs therefore expose that
fully specified adopted reference, not a uniquely mandatory transmitter.

Manchester encoding, WUR-Sync bit values, MAC/FCS fields, legacy preamble and
L-SIG construction, arbitrary QAM coefficient choices, multiple transmit
chains, FDMA, window overlap, RF, detection, and receive processing are not
implemented.  The adopted whole-WUR-Sync-plus-Data correlation test
(``M=16``, ``N=6``, six-byte LDR/HDR data and maximum below 0.4) is likewise
caller-owned because this module does not assemble the complete PPDU.  The
modulator therefore accepts already encoded On/Off symbol decisions and
returns discrete pre-window baseband samples; it is not a full WUR PPDU
implementation or a correlation-test compliance verdict.
"""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import ifft


comptime WIFI_WUR_DATA_RATE_LDR_BPS = 62_500
comptime WIFI_WUR_DATA_RATE_HDR_BPS = 250_000
comptime WIFI_WUR_SAMPLE_RATE_HZ = 20_000_000
comptime WIFI_WUR_IDFT_SIZE = 64
comptime WIFI_WUR_RANDOMIZER_PERIOD = 127


struct WifiWURDataOOKConfig(ImplicitlyCopyable):
    """Mutable single-channel, single-chain WUR Data MC-OOK profile."""

    var data_rate_bps: Int
    var sample_rate_hz: Int
    var idft_size: Int
    var transmit_chains: Int

    def __init__(
        out self,
        data_rate_bps: Int,
        sample_rate_hz: Int,
        idft_size: Int,
        transmit_chains: Int,
    ) raises:
        self.data_rate_bps = data_rate_bps
        self.sample_rate_hz = sample_rate_hz
        self.idft_size = idft_size
        self.transmit_chains = transmit_chains
        self.validate()

    def validate(self) raises:
        """Revalidate every mutable bounded-profile field."""
        if (
            self.data_rate_bps != WIFI_WUR_DATA_RATE_LDR_BPS
            and self.data_rate_bps != WIFI_WUR_DATA_RATE_HDR_BPS
        ):
            raise Error("WUR Data rate must be 62500 or 250000 bit/s")
        if self.sample_rate_hz != WIFI_WUR_SAMPLE_RATE_HZ:
            raise Error("bounded WUR MC-OOK requires 20 MHz sampling")
        if self.idft_size != WIFI_WUR_IDFT_SIZE:
            raise Error("bounded WUR MC-OOK requires a 64-point IDFT")
        if self.transmit_chains != 1:
            raise Error("bounded WUR MC-OOK requires one transmit chain")


struct WifiWURDataProfile(ImplicitlyCopyable):
    """Published geometry for one bounded WUR Data rate."""

    var data_rate_bps: Int
    var data_symbol_duration_ns: Int
    var useful_samples: Int
    var guard_interval_samples: Int
    var total_symbol_samples: Int
    var active_subcarriers: Int
    var sync_duration_ns: Int
    var sync_randomizer_symbols: Int

    def __init__(
        out self,
        data_rate_bps: Int,
        data_symbol_duration_ns: Int,
        useful_samples: Int,
        guard_interval_samples: Int,
        total_symbol_samples: Int,
        active_subcarriers: Int,
        sync_duration_ns: Int,
        sync_randomizer_symbols: Int,
    ):
        self.data_rate_bps = data_rate_bps
        self.data_symbol_duration_ns = data_symbol_duration_ns
        self.useful_samples = useful_samples
        self.guard_interval_samples = guard_interval_samples
        self.total_symbol_samples = total_symbol_samples
        self.active_subcarriers = active_subcarriers
        self.sync_duration_ns = sync_duration_ns
        self.sync_randomizer_symbols = sync_randomizer_symbols


struct WifiWURRandomizerState(ImplicitlyCopyable):
    """One symbol-randomizer state, phase sign, and CSD-table index."""

    var lfsr_x7_to_x1: Int
    var phase_sign: Int
    var cyclic_shift_index: Int

    def __init__(
        out self,
        lfsr_x7_to_x1: Int,
        phase_sign: Int,
        cyclic_shift_index: Int,
    ):
        self.lfsr_x7_to_x1 = lfsr_x7_to_x1
        self.phase_sign = phase_sign
        self.cyclic_shift_index = cyclic_shift_index


def wifi_wur_data_profile(
    config: WifiWURDataOOKConfig,
) raises -> WifiWURDataProfile:
    """Return the exact LDR or HDR WUR Data/SYNC geometry."""
    config.validate()
    if config.data_rate_bps == WIFI_WUR_DATA_RATE_LDR_BPS:
        return WifiWURDataProfile(
            WIFI_WUR_DATA_RATE_LDR_BPS,
            4_000,
            64,
            16,
            80,
            12,
            128_000,
            64,
        )
    return WifiWURDataProfile(
        WIFI_WUR_DATA_RATE_HDR_BPS,
        2_000,
        32,
        8,
        40,
        6,
        64_000,
        32,
    )


def wifi_wur_mc_ook_active_subcarriers(
    config: WifiWURDataOOKConfig,
) raises -> List[Int]:
    """Return ascending nonzero MC-OOK tone indices for WUR Data."""
    config.validate()
    if config.data_rate_bps == WIFI_WUR_DATA_RATE_LDR_BPS:
        return [-6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6]
    return [-6, -4, -2, 2, 4, 6]


def wifi_wur_symbol_randomizer_state(
    ppdu_symbol_index: Int,
) raises -> WifiWURRandomizerState:
    """Return the periodic randomizer state for a zero-based PPDU symbol.

    Index zero is the first WUR-Sync symbol and therefore uses the all-ones
    initialization.  The reduction modulo 127 keeps ``Int.MAX`` safe.
    """
    if ppdu_symbol_index < 0:
        raise Error("WUR randomizer symbol index must be nonnegative")
    var state = 0x7F
    for _ in range(ppdu_symbol_index % WIFI_WUR_RANDOMIZER_PERIOD):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        state = ((state << 1) & 0x7F) | feedback
    var phase_sign = 1 if ((state >> 6) & 1) == 0 else -1
    return WifiWURRandomizerState(state, phase_sign, state & 0x7)


def wifi_wur_symbol_randomizer_cyclic_shift_ns(
    config: WifiWURDataOOKConfig, ppdu_symbol_index: Int
) raises -> Int:
    """Return the complete LDR/HDR random cyclic-shift table lookup."""
    config.validate()
    var state = wifi_wur_symbol_randomizer_state(ppdu_symbol_index)
    var quantum_ns = (
        400
        if config.data_rate_bps == WIFI_WUR_DATA_RATE_LDR_BPS
        else 200
    )
    return -quantum_ns * state.cyclic_shift_index


def _validate_bpsk_coefficients(
    config: WifiWURDataOOKConfig,
    coefficients: Span[Complex64, ...],
) raises:
    var profile = wifi_wur_data_profile(config)
    if len(coefficients) != profile.active_subcarriers:
        raise Error("WUR BPSK coefficient count does not match active tones")
    for index in range(len(coefficients)):
        var value = coefficients[index]
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("WUR MC-OOK coefficients must be finite")
        if value.im != 0.0 or (value.re != -1.0 and value.re != 1.0):
            raise Error("bounded WUR MC-OOK accepts BPSK coefficients only")


def _data_ppdu_randomizer_index(
    profile: WifiWURDataProfile, data_symbol_index: Int
) raises -> Int:
    if data_symbol_index < 0:
        raise Error("WUR Data symbol index must be nonnegative")
    return (
        profile.sync_randomizer_symbols
        + data_symbol_index % WIFI_WUR_RANDOMIZER_PERIOD
    ) % WIFI_WUR_RANDOMIZER_PERIOD


def _mc_ook_on_symbol_validated(
    config: WifiWURDataOOKConfig,
    profile: WifiWURDataProfile,
    coefficients: Span[Complex64, ...],
    ppdu_symbol_index: Int,
) raises -> List[Complex64]:
    var tones = wifi_wur_mc_ook_active_subcarriers(config)
    var bins = List[Complex64](
        length=WIFI_WUR_IDFT_SIZE, fill=Complex64(0.0, 0.0)
    )
    for index in range(len(tones)):
        var tone = tones[index]
        var bin_index = tone if tone >= 0 else WIFI_WUR_IDFT_SIZE + tone
        bins[bin_index] = coefficients[index]

    var transformed = ifft(Span(bins))
    var idft_scale = Float64(WIFI_WUR_IDFT_SIZE) * sqrt(
        2.0 / Float64(profile.active_subcarriers)
    )
    var state = wifi_wur_symbol_randomizer_state(ppdu_symbol_index)
    var shift_ns = wifi_wur_symbol_randomizer_cyclic_shift_ns(
        config, ppdu_symbol_index
    )
    var shift_samples = -shift_ns // 50
    var randomized = List[Complex64](capacity=profile.useful_samples)
    for sample in range(profile.useful_samples):
        var source = (sample + shift_samples) % profile.useful_samples
        var value = transformed[source]
        var scale = idft_scale * Float64(state.phase_sign)
        var output = Complex64(value.re * scale, value.im * scale)
        if not isfinite(output.re) or not isfinite(output.im):
            raise Error("WUR MC-OOK waveform result is not representable")
        randomized.append(output)

    var result = List[Complex64](capacity=profile.total_symbol_samples)
    for sample in range(
        profile.useful_samples - profile.guard_interval_samples,
        profile.useful_samples,
    ):
        result.append(randomized[sample])
    for sample in range(profile.useful_samples):
        result.append(randomized[sample])
    return result^


def wifi_wur_data_mc_ook_on_symbol(
    config: WifiWURDataOOKConfig,
    bpsk_coefficients: Span[Complex64, ...],
    data_symbol_index: Int,
) raises -> List[Complex64]:
    """Generate one randomized, GI-prefixed WUR Data MC-OOK On symbol.

    ``data_symbol_index`` is zero-based within WUR-Data.  The randomizer state
    includes the preceding WUR-Sync updates.  Returned samples are the
    single-chain, pre-window discrete baseband intermediate.
    """
    config.validate()
    var profile = wifi_wur_data_profile(config)
    _validate_bpsk_coefficients(config, bpsk_coefficients)
    var ppdu_index = _data_ppdu_randomizer_index(
        profile, data_symbol_index
    )
    return _mc_ook_on_symbol_validated(
        config, profile, bpsk_coefficients, ppdu_index
    )


def wifi_wur_data_mc_ook_off_symbol(
    config: WifiWURDataOOKConfig,
) raises -> List[Complex64]:
    """Generate one exact all-zero WUR Data MC-OOK Off symbol."""
    config.validate()
    var profile = wifi_wur_data_profile(config)
    return List[Complex64](
        length=profile.total_symbol_samples, fill=Complex64(0.0, 0.0)
    )


def wifi_wur_data_mc_ook_modulate(
    config: WifiWURDataOOKConfig,
    encoded_on_off_symbols: Span[UInt8, ...],
    bpsk_coefficients: Span[Complex64, ...],
) raises -> List[Complex64]:
    """Modulate an already encoded WUR Data On/Off decision sequence.

    This boundary deliberately does not infer Manchester coding or MAC/FCS
    fields.  The randomizer starts after the rate-dependent WUR-Sync field.
    """
    config.validate()
    var profile = wifi_wur_data_profile(config)
    _validate_bpsk_coefficients(config, bpsk_coefficients)
    if len(encoded_on_off_symbols) == 0:
        raise Error("WUR MC-OOK modulation requires at least one symbol")
    if len(encoded_on_off_symbols) > Int.MAX // profile.total_symbol_samples:
        raise Error("WUR MC-OOK output shape overflows Int")
    for index in range(len(encoded_on_off_symbols)):
        if encoded_on_off_symbols[index] > 1:
            raise Error("WUR MC-OOK decisions must be binary")

    var result = List[Complex64](
        capacity=len(encoded_on_off_symbols) * profile.total_symbol_samples
    )
    for data_symbol in range(len(encoded_on_off_symbols)):
        if encoded_on_off_symbols[data_symbol] == 0:
            for _ in range(profile.total_symbol_samples):
                result.append(Complex64(0.0, 0.0))
            continue
        var ppdu_index = _data_ppdu_randomizer_index(profile, data_symbol)
        var one = _mc_ook_on_symbol_validated(
            config, profile, bpsk_coefficients, ppdu_index
        )
        for sample in range(len(one)):
            result.append(one[sample])
    return result^
