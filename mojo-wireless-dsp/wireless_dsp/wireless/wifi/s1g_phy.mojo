"""Bounded IEEE 802.11-2024 Clause 23 S1G PHY arithmetic.

This CPU-only module implements exact, deterministic pieces of the current
S1G PHY: the five OFDM bandwidth numerologies, occupied-tone sets, absolute
subcarrier-frequency arithmetic, one-spatial-stream S1G-MCS rows, and BCC SU
DATA/TXTIME geometry for long-GI S1G_1M and S1G_SHORT PPDUs.  The MCS 10
profile is the 1 MHz BPSK 1/2 code followed by twofold repetition, hence its
effective 1/4 rate and six data bits per OFDM symbol.

Normative baseline: IEEE Std 802.11-2024, Clause 23.3.4.3-23.3.4.7,
23.3.5-23.3.7, 23.4.3-23.4.4, and 23.5; Tables 23-4, 23-41,
23-42/46/50/54/58.  The active-standard page is
https://standards.ieee.org/ieee/802.11/10548/ .  IEEE GET exposes the
published PDF only through an interactive personal-account flow unavailable
to this build environment.  No unnamed historical WG material is accepted as
evidence or authority, and this implementation remains production-blocked
until the final artifact is legally supplied and checked.  This module does
not infer unavailable SIG-field semantics.

Short GI, S1G_LONG/MU, multiple spatial streams, STBC, SIG packing/parsing,
training sequences, traveling-pilot positions, BCC bit processing, LDPC,
waveform generation/reception, RF/regulatory channel selection, and CCA are
outside this module and keep the overall S1G feature PARTIAL.
"""

from std.math import isfinite


comptime WIFI_S1G_SUBCARRIER_SPACING_HZ = 31_250
comptime WIFI_S1G_FFT_PERIOD_NS = 32_000
comptime WIFI_S1G_LONG_GI_NS = 8_000
comptime WIFI_S1G_SHORT_GI_NS = 4_000
comptime WIFI_S1G_LONG_SYMBOL_NS = 40_000
comptime WIFI_S1G_SHORT_SYMBOL_NS = 36_000
comptime WIFI_S1G_SERVICE_BITS = 8
comptime WIFI_S1G_BCC_TAIL_BITS = 6
# MCS 10 instead bounds PSDU length in octets and can exceed 511 symbols.
comptime WIFI_S1G_NON_MCS10_MAX_DATA_SYMBOLS = 511
comptime WIFI_S1G_MCS10_MAX_PSDU_OCTETS = 511
comptime WIFI_S1G_MAX_PSDU_OCTETS = 797_159
comptime WIFI_S1G_MAX_PPDU_DURATION_NS = 27_920_000
comptime WIFI_S1G_1M_PREAMBLE_NS = 560_000
comptime WIFI_S1G_SHORT_PREAMBLE_NS = 240_000


def _is_s1g_bandwidth(bandwidth_mhz: Int) -> Bool:
    return (
        bandwidth_mhz == 1
        or bandwidth_mhz == 2
        or bandwidth_mhz == 4
        or bandwidth_mhz == 8
        or bandwidth_mhz == 16
    )


struct WifiS1GOFDMProfile(ImplicitlyCopyable):
    """Exact Clause-23 OFDM numerology for one S1G channel width."""

    var bandwidth_mhz: Int
    var fft_size: Int
    var data_subcarriers: Int
    var pilot_subcarriers: Int
    var occupied_subcarriers: Int
    var highest_occupied_index: Int
    var subcarrier_spacing_hz: Int
    var fft_period_ns: Int
    var long_gi_ns: Int
    var short_gi_ns: Int
    var long_symbol_ns: Int
    var short_symbol_ns: Int

    def __init__(out self, bandwidth_mhz: Int) raises:
        if not _is_s1g_bandwidth(bandwidth_mhz):
            raise Error("S1G bandwidth must be 1, 2, 4, 8, or 16 MHz")
        self.bandwidth_mhz = bandwidth_mhz
        self.fft_size = 32 * bandwidth_mhz
        if bandwidth_mhz == 1:
            self.data_subcarriers = 24
            self.pilot_subcarriers = 2
            self.highest_occupied_index = 13
        elif bandwidth_mhz == 2:
            self.data_subcarriers = 52
            self.pilot_subcarriers = 4
            self.highest_occupied_index = 28
        elif bandwidth_mhz == 4:
            self.data_subcarriers = 108
            self.pilot_subcarriers = 6
            self.highest_occupied_index = 58
        elif bandwidth_mhz == 8:
            self.data_subcarriers = 234
            self.pilot_subcarriers = 8
            self.highest_occupied_index = 122
        else:
            self.data_subcarriers = 468
            self.pilot_subcarriers = 16
            self.highest_occupied_index = 250
        self.occupied_subcarriers = (
            self.data_subcarriers + self.pilot_subcarriers
        )
        self.subcarrier_spacing_hz = WIFI_S1G_SUBCARRIER_SPACING_HZ
        self.fft_period_ns = WIFI_S1G_FFT_PERIOD_NS
        self.long_gi_ns = WIFI_S1G_LONG_GI_NS
        self.short_gi_ns = WIFI_S1G_SHORT_GI_NS
        self.long_symbol_ns = WIFI_S1G_LONG_SYMBOL_NS
        self.short_symbol_ns = WIFI_S1G_SHORT_SYMBOL_NS

    def validate(self) raises:
        """Reject mutation away from the exact Clause-23 numerology row."""
        var expected = WifiS1GOFDMProfile(self.bandwidth_mhz)
        if (
            self.fft_size != expected.fft_size
            or self.data_subcarriers != expected.data_subcarriers
            or self.pilot_subcarriers != expected.pilot_subcarriers
            or self.occupied_subcarriers != expected.occupied_subcarriers
            or self.highest_occupied_index
            != expected.highest_occupied_index
            or self.subcarrier_spacing_hz
            != expected.subcarrier_spacing_hz
            or self.fft_period_ns != expected.fft_period_ns
            or self.long_gi_ns != expected.long_gi_ns
            or self.short_gi_ns != expected.short_gi_ns
            or self.long_symbol_ns != expected.long_symbol_ns
            or self.short_symbol_ns != expected.short_symbol_ns
        ):
            raise Error("S1G OFDM profile no longer matches Clause 23")


def wifi_s1g_ofdm_profile(
    bandwidth_mhz: Int,
) raises -> WifiS1GOFDMProfile:
    """Return the complete Table 23-4 row for a supported S1G width."""
    return WifiS1GOFDMProfile(bandwidth_mhz)


def _s1g_tone_is_occupied(bandwidth_mhz: Int, tone_index: Int) -> Bool:
    if bandwidth_mhz == 1:
        return tone_index >= -13 and tone_index <= 13 and tone_index != 0
    if bandwidth_mhz == 2:
        return tone_index >= -28 and tone_index <= 28 and tone_index != 0
    if bandwidth_mhz == 4:
        return (
            (tone_index >= -58 and tone_index <= -2)
            or (tone_index >= 2 and tone_index <= 58)
        )
    if bandwidth_mhz == 8:
        return (
            (tone_index >= -122 and tone_index <= -2)
            or (tone_index >= 2 and tone_index <= 122)
        )
    return (
        (tone_index >= -250 and tone_index <= -130)
        or (tone_index >= -126 and tone_index <= -6)
        or (tone_index >= 6 and tone_index <= 126)
        or (tone_index >= 130 and tone_index <= 250)
    )


def wifi_s1g_occupied_subcarriers(
    bandwidth_mhz: Int,
) raises -> List[Int]:
    """Return ascending occupied-tone indices from Clause 23.3.7.

    The result includes DATA and traveling-pilot tones but excludes DC and
    every guard/notch tone.  It does not label the symbol-dependent pilots.
    """
    var profile = wifi_s1g_ofdm_profile(bandwidth_mhz)
    var tones = List[Int](capacity=profile.occupied_subcarriers)
    for tone_index in range(
        -profile.highest_occupied_index,
        profile.highest_occupied_index + 1,
    ):
        if _s1g_tone_is_occupied(bandwidth_mhz, tone_index):
            tones.append(tone_index)
    if len(tones) != profile.occupied_subcarriers:
        raise Error("internal S1G occupied-tone cardinality mismatch")
    return tones^


def wifi_s1g_subcarrier_frequency_hz(
    center_frequency_hz: Float64,
    bandwidth_mhz: Int,
    tone_index: Int,
) raises -> Float64:
    """Map one occupied S1G tone to its absolute center frequency.

    This is ``f_c + k * 31.25 kHz`` from Clause 23.3.7.  Regulatory channel
    legality is caller-owned; this boundary only requires a positive finite
    center and an occupied tone of the declared bandwidth.
    """
    _ = wifi_s1g_ofdm_profile(bandwidth_mhz)
    if not isfinite(center_frequency_hz) or center_frequency_hz <= 0.0:
        raise Error("S1G center frequency must be positive and finite")
    if not _s1g_tone_is_occupied(bandwidth_mhz, tone_index):
        raise Error("S1G tone index is not occupied for this bandwidth")
    var result = center_frequency_hz + Float64(
        tone_index * WIFI_S1G_SUBCARRIER_SPACING_HZ
    )
    if not isfinite(result) or result <= 0.0:
        raise Error("S1G absolute subcarrier frequency is not representable")
    return result


def _s1g_mcs_parameters(mcs_index: Int) raises -> Tuple[Int, Int, Int, Int]:
    if mcs_index == 0:
        return (1, 1, 2, 1)
    if mcs_index == 1:
        return (2, 1, 2, 1)
    if mcs_index == 2:
        return (2, 3, 4, 1)
    if mcs_index == 3:
        return (4, 1, 2, 1)
    if mcs_index == 4:
        return (4, 3, 4, 1)
    if mcs_index == 5:
        return (6, 2, 3, 1)
    if mcs_index == 6:
        return (6, 3, 4, 1)
    if mcs_index == 7:
        return (6, 5, 6, 1)
    if mcs_index == 8:
        return (8, 3, 4, 1)
    if mcs_index == 9:
        return (8, 5, 6, 1)
    if mcs_index == 10:
        return (1, 1, 4, 2)
    raise Error("S1G-MCS index must be in [0,10]")


struct WifiS1GMCSProfile(ImplicitlyCopyable):
    """One-spatial-stream S1G-MCS row for long-GI DATA symbols."""

    var bandwidth_mhz: Int
    var mcs_index: Int
    var bits_per_subcarrier: Int
    var effective_code_rate_numerator: Int
    var effective_code_rate_denominator: Int
    var bcc_repetition_factor: Int
    var data_subcarriers: Int
    var pilot_subcarriers: Int
    var coded_bits_per_symbol: Int
    var data_bits_per_symbol: Int
    var long_gi_data_rate_bps: Int

    def __init__(
        out self, bandwidth_mhz: Int, mcs_index: Int
    ) raises:
        var ofdm = wifi_s1g_ofdm_profile(bandwidth_mhz)
        if mcs_index == 10 and bandwidth_mhz != 1:
            raise Error("S1G-MCS 10 is valid only at 1 MHz with one stream")
        if mcs_index == 9 and bandwidth_mhz == 2:
            raise Error("S1G-MCS 9 is not valid at 2 MHz with one stream")
        var (bpsc, rate_numerator, rate_denominator, repetition) = (
            _s1g_mcs_parameters(mcs_index)
        )
        var coded_bits = ofdm.data_subcarriers * bpsc
        if coded_bits % rate_denominator != 0:
            raise Error("S1G-MCS row has a nonintegral data-bit count")
        var data_bits = coded_bits // rate_denominator * rate_numerator
        self.bandwidth_mhz = bandwidth_mhz
        self.mcs_index = mcs_index
        self.bits_per_subcarrier = bpsc
        self.effective_code_rate_numerator = rate_numerator
        self.effective_code_rate_denominator = rate_denominator
        self.bcc_repetition_factor = repetition
        self.data_subcarriers = ofdm.data_subcarriers
        self.pilot_subcarriers = ofdm.pilot_subcarriers
        self.coded_bits_per_symbol = coded_bits
        self.data_bits_per_symbol = data_bits
        self.long_gi_data_rate_bps = data_bits * 25_000

    def validate(self) raises:
        """Reject mutation away from the exact single-stream MCS row."""
        var expected = WifiS1GMCSProfile(
            self.bandwidth_mhz, self.mcs_index
        )
        if (
            self.bits_per_subcarrier != expected.bits_per_subcarrier
            or self.effective_code_rate_numerator
            != expected.effective_code_rate_numerator
            or self.effective_code_rate_denominator
            != expected.effective_code_rate_denominator
            or self.bcc_repetition_factor != expected.bcc_repetition_factor
            or self.data_subcarriers != expected.data_subcarriers
            or self.pilot_subcarriers != expected.pilot_subcarriers
            or self.coded_bits_per_symbol
            != expected.coded_bits_per_symbol
            or self.data_bits_per_symbol != expected.data_bits_per_symbol
            or self.long_gi_data_rate_bps
            != expected.long_gi_data_rate_bps
        ):
            raise Error("S1G-MCS profile no longer matches Clause 23")


def wifi_s1g_mcs_profile(
    bandwidth_mhz: Int, mcs_index: Int
) raises -> WifiS1GMCSProfile:
    """Return an exact one-stream Table 23-42/46/50/54/58 MCS row."""
    return WifiS1GMCSProfile(bandwidth_mhz, mcs_index)


struct WifiS1GBCCSUConfig(ImplicitlyCopyable):
    """Mutable one-stream, BCC, long-GI S1G_1M/S1G_SHORT profile."""

    var bandwidth_mhz: Int
    var mcs_index: Int
    var psdu_length_octets: Int

    def __init__(
        out self,
        bandwidth_mhz: Int,
        mcs_index: Int,
        psdu_length_octets: Int,
    ) raises:
        self.bandwidth_mhz = bandwidth_mhz
        self.mcs_index = mcs_index
        self.psdu_length_octets = psdu_length_octets
        self.validate()

    def validate(self) raises:
        """Revalidate all mutable fields and the Clause-23 LENGTH bound."""
        var mcs = wifi_s1g_mcs_profile(
            self.bandwidth_mhz, self.mcs_index
        )
        if self.psdu_length_octets < 1:
            raise Error("bounded S1G data PSDU length must be positive")
        if self.psdu_length_octets > WIFI_S1G_MAX_PSDU_OCTETS:
            raise Error("S1G PSDU length exceeds the PHY absolute maximum")
        if (
            self.mcs_index == 10
            and self.psdu_length_octets
            > WIFI_S1G_MCS10_MAX_PSDU_OCTETS
        ):
            raise Error("S1G-MCS 10 PSDU length must not exceed 511 octets")
        var bits = (
            8 * self.psdu_length_octets
            + WIFI_S1G_SERVICE_BITS
            + WIFI_S1G_BCC_TAIL_BITS
        )
        var symbols = (
            bits + mcs.data_bits_per_symbol - 1
        ) // mcs.data_bits_per_symbol
        if (
            self.mcs_index != 10
            and symbols > WIFI_S1G_NON_MCS10_MAX_DATA_SYMBOLS
        ):
            raise Error("S1G PPDU LENGTH exceeds 511 DATA symbols")


struct WifiS1GBCCSUGeometry(ImplicitlyCopyable):
    """Exact SERVICE, tail, pad, symbol, and TXTIME geometry."""

    var bandwidth_mhz: Int
    var mcs_index: Int
    var psdu_length_octets: Int
    var data_bits_per_symbol: Int
    var data_bits_before_pad: Int
    var pad_bits: Int
    var data_symbols: Int
    var preamble_duration_ns: Int
    var data_duration_ns: Int
    var ppdu_duration_ns: Int
    var s1g_1m_format: Bool

    def __init__(
        out self,
        bandwidth_mhz: Int,
        mcs_index: Int,
        psdu_length_octets: Int,
        data_bits_per_symbol: Int,
        data_bits_before_pad: Int,
        pad_bits: Int,
        data_symbols: Int,
        preamble_duration_ns: Int,
        data_duration_ns: Int,
    ):
        self.bandwidth_mhz = bandwidth_mhz
        self.mcs_index = mcs_index
        self.psdu_length_octets = psdu_length_octets
        self.data_bits_per_symbol = data_bits_per_symbol
        self.data_bits_before_pad = data_bits_before_pad
        self.pad_bits = pad_bits
        self.data_symbols = data_symbols
        self.preamble_duration_ns = preamble_duration_ns
        self.data_duration_ns = data_duration_ns
        self.ppdu_duration_ns = preamble_duration_ns + data_duration_ns
        self.s1g_1m_format = bandwidth_mhz == 1


def wifi_s1g_bcc_su_long_gi_geometry(
    config: WifiS1GBCCSUConfig,
) raises -> WifiS1GBCCSUGeometry:
    """Compute exact one-stream BCC SU long-GI DATA and PPDU geometry.

    The caller supplies the complete PSDU length, including any MAC FCS.
    1 MHz selects S1G_1M; 2/4/8/16 MHz select S1G_SHORT.  This boundary
    deliberately does not choose S1G_LONG or MU behavior.
    """
    config.validate()
    var mcs = wifi_s1g_mcs_profile(
        config.bandwidth_mhz, config.mcs_index
    )
    var bits = (
        8 * config.psdu_length_octets
        + WIFI_S1G_SERVICE_BITS
        + WIFI_S1G_BCC_TAIL_BITS
    )
    var symbols = (
        bits + mcs.data_bits_per_symbol - 1
    ) // mcs.data_bits_per_symbol
    var pad_bits = symbols * mcs.data_bits_per_symbol - bits
    var preamble_ns = (
        WIFI_S1G_1M_PREAMBLE_NS
        if config.bandwidth_mhz == 1
        else WIFI_S1G_SHORT_PREAMBLE_NS
    )
    return WifiS1GBCCSUGeometry(
        config.bandwidth_mhz,
        config.mcs_index,
        config.psdu_length_octets,
        mcs.data_bits_per_symbol,
        bits,
        pad_bits,
        symbols,
        preamble_ns,
        symbols * WIFI_S1G_LONG_SYMBOL_NS,
    )
