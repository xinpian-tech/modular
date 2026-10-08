"""IEEE 802.11-2024 Clause 17 OFDM and Clause 18 ERP-OFDM PPDU reference.

This CPU-only module composes the repository's legacy WLAN primitives into a
bounded, interoperable 20 MHz, one-spatial-stream NON_HT PPDU.  All eight
Clause-17 rates are represented: 6, 9, 12, 18, 24, 36, 48, and 54 Mb/s.  The
transmit path includes MPDU FCS, SERVICE, scrambling, explicit BCC tail and
pad, K=7 BCC puncturing, per-symbol interleaving, BPSK/QPSK/16-QAM/64-QAM,
pilot polarity, the 52 occupied legacy tones, 64-point IFFT, and 0.8 us GI.
It also builds the legacy STF, LTF, and L-SIG fields.  The receive path uses
known PPDU timing, estimates all 52 trained tones from the two L-LTF symbols,
decodes and validates L-SIG before deriving DATA geometry, recovers the
scrambler seed from the zero SERVICE prefix, and reports an actual FCS result.

Clause 18 ERP-OFDM inherits the Clause 17 transmit procedure except for the
6 us signal extension described by 18.3.2.4.  That extension is idle time
after the PPDU, so it is represented in medium-occupancy geometry and is not
fabricated as transmitted complex samples.  The ERP protection helper checks
the normative associated-NonERP implication for the Use_Protection bit but
does not choose RTS/CTS versus CTS-to-self; that choice is MAC policy.

Normative baseline: IEEE Std 802.11-2024, Clauses 17.3 and 18.3, published
2025-04-28 at https://standards.ieee.org/ieee/802.11/10548/ .  The current
Clause-18 reuse wording is also recorded in the IEEE 802.11 Working Group
REVme adopted resolution for CID 283 (11-21/0727r5).  RF, CCA/CS, packet
detection, timing/CFO acquisition, transmit spectral masks, window overlap,
MAC frame construction above FCS, and protection-mechanism policy are outside
this deliberately synchronized baseband boundary.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import ofdm_modulate, ofdm_demodulate, complex_divide
from wireless_dsp.fec import convolutional_encode, viterbi_decode_soft
from wireless_dsp.modem import qam_map, qam_demap_hard
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
    checkpoint_metadata_2d,
)
from .coding import (
    wifi_bcc_puncture,
    wifi_bcc_depuncture_llrs,
)
from .legacy import (
    LegacySignal,
    wifi_scramble,
    wifi_interleave,
    wifi_deinterleave,
    wifi_data_subcarriers,
    wifi_pilot_polarity,
    wifi_legacy_signal_bits,
    wifi_parse_legacy_signal,
    wifi_fcs,
)
from .acquisition_chain import wifi_stf_waveform_20mhz
from .he_eht_acquisition import (
    wifi_legacy_ltf_spectrum_20mhz,
    wifi_legacy_ltf_waveform_20mhz,
)
from .pilots import wifi_estimate_pilot_phase, wifi_correct_pilot_phase


comptime WIFI_OFDM_CLAUSE_17 = 17
comptime WIFI_ERP_OFDM_CLAUSE_18 = 18

comptime WIFI_OFDM_FFT_SIZE = 64
comptime WIFI_OFDM_GI_SAMPLES = 16
comptime WIFI_OFDM_SYMBOL_SAMPLES = 80
comptime WIFI_OFDM_STF_SAMPLES = 160
comptime WIFI_OFDM_LTF_SAMPLES = 160
comptime WIFI_OFDM_LSIG_SAMPLES = 80
comptime WIFI_ERP_SIGNAL_EXTENSION_SAMPLES = 120


struct WifiOFDMERPConfig(ImplicitlyCopyable):
    """Mutable bounded Clause-17/18 transmit profile.

    Every public boundary taking this record revalidates all fields, so a
    caller cannot mutate a once-valid profile into an unchecked one.
    """

    var clause: Int
    var rate_mbps: Int
    var scrambler_seed: UInt8

    def __init__(
        out self,
        clause: Int,
        rate_mbps: Int,
        *,
        scrambler_seed: UInt8 = UInt8(0x5D),
    ) raises:
        self.clause = clause
        self.rate_mbps = rate_mbps
        self.scrambler_seed = scrambler_seed
        self.validate()

    def validate(self) raises:
        if (
            self.clause != WIFI_OFDM_CLAUSE_17
            and self.clause != WIFI_ERP_OFDM_CLAUSE_18
        ):
            raise Error("OFDM profile must select IEEE 802.11 Clause 17 or 18")
        if (
            self.rate_mbps != 6
            and self.rate_mbps != 9
            and self.rate_mbps != 12
            and self.rate_mbps != 18
            and self.rate_mbps != 24
            and self.rate_mbps != 36
            and self.rate_mbps != 48
            and self.rate_mbps != 54
        ):
            raise Error("legacy OFDM rate must be 6/9/12/18/24/36/48/54 Mb/s")
        if self.scrambler_seed == 0 or self.scrambler_seed > UInt8(0x7F):
            raise Error("OFDM scrambler seed must be a nonzero 7-bit value")


struct WifiOFDMERPRateProfile(ImplicitlyCopyable):
    """Exact Clause-17 rate-row and Clause-18 inheritance parameters."""

    var clause: Int
    var rate_mbps: Int
    var rate_code_lsb_first: Int
    var bits_per_subcarrier: Int
    var code_rate_numerator: Int
    var code_rate_denominator: Int
    var coded_bits_per_symbol: Int
    var data_bits_per_symbol: Int
    var signal_extension_samples: Int
    var sifs_ns: Int

    def __init__(
        out self,
        clause: Int,
        rate_mbps: Int,
        rate_code_lsb_first: Int,
        bits_per_subcarrier: Int,
        code_rate_numerator: Int,
        code_rate_denominator: Int,
        coded_bits_per_symbol: Int,
        data_bits_per_symbol: Int,
    ):
        self.clause = clause
        self.rate_mbps = rate_mbps
        self.rate_code_lsb_first = rate_code_lsb_first
        self.bits_per_subcarrier = bits_per_subcarrier
        self.code_rate_numerator = code_rate_numerator
        self.code_rate_denominator = code_rate_denominator
        self.coded_bits_per_symbol = coded_bits_per_symbol
        self.data_bits_per_symbol = data_bits_per_symbol
        self.signal_extension_samples = (
            WIFI_ERP_SIGNAL_EXTENSION_SAMPLES
            if clause == WIFI_ERP_OFDM_CLAUSE_18
            else 0
        )
        self.sifs_ns = (
            10_000
            if clause == WIFI_ERP_OFDM_CLAUSE_18
            else 16_000
        )


struct WifiOFDMERPGeometry(ImplicitlyCopyable):
    """Normative DATA padding and synchronized baseband PPDU geometry."""

    var psdu_length_octets: Int
    var data_bits_before_pad: Int
    var pad_bits: Int
    var data_symbols: Int
    var ppdu_samples: Int
    var signal_extension_samples: Int
    var medium_occupancy_samples: Int
    var ppdu_duration_ns: Int
    var medium_occupancy_duration_ns: Int

    def __init__(
        out self,
        psdu_length_octets: Int,
        data_bits_before_pad: Int,
        pad_bits: Int,
        data_symbols: Int,
        ppdu_samples: Int,
        signal_extension_samples: Int,
    ):
        self.psdu_length_octets = psdu_length_octets
        self.data_bits_before_pad = data_bits_before_pad
        self.pad_bits = pad_bits
        self.data_symbols = data_symbols
        self.ppdu_samples = ppdu_samples
        self.signal_extension_samples = signal_extension_samples
        self.medium_occupancy_samples = ppdu_samples + signal_extension_samples
        self.ppdu_duration_ns = ppdu_samples * 50
        self.medium_occupancy_duration_ns = (
            self.medium_occupancy_samples * 50
        )


struct WifiERPProtectionDecision(ImplicitlyCopyable):
    """Validated ERP Use_Protection state without mechanism policy."""

    var non_erp_sta_associated: Bool
    var use_protection: Bool
    var protect_erp_ofdm_exchange: Bool
    var signal_extension_samples: Int
    var mechanism_selection_is_policy: Bool

    def __init__(
        out self,
        non_erp_sta_associated: Bool,
        use_protection: Bool,
    ):
        self.non_erp_sta_associated = non_erp_sta_associated
        self.use_protection = use_protection
        self.protect_erp_ofdm_exchange = use_protection
        self.signal_extension_samples = WIFI_ERP_SIGNAL_EXTENSION_SAMPLES
        self.mechanism_selection_is_policy = True


struct WifiOFDMERPTx20MHz(Movable):
    """All Clause-17/18 transmit checkpoints for one synchronized PPDU."""

    var profile: WifiOFDMERPRateProfile
    var geometry: WifiOFDMERPGeometry
    var scrambler_seed: UInt8
    var fcs: UInt64
    var lsig_bits: List[UInt8]
    var lsig_coded_bits: List[UInt8]
    var lsig_interleaved_bits: List[UInt8]
    var lsig_symbols: List[Complex64]
    var lsig_spectrum: List[Complex64]
    var lsig_waveform: List[Complex64]
    var data_field_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var mother_bits: List[UInt8]
    var punctured_bits: List[UInt8]
    var interleaved_bits: List[UInt8]
    var qam_symbols: List[Complex64]
    var data_spectra: List[Complex64]
    var data_waveform: List[Complex64]
    var stf_waveform: List[Complex64]
    var ltf_waveform: List[Complex64]
    var ppdu_waveform: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        profile: WifiOFDMERPRateProfile,
        geometry: WifiOFDMERPGeometry,
        scrambler_seed: UInt8,
        fcs: UInt64,
        var lsig_bits: List[UInt8],
        var lsig_coded_bits: List[UInt8],
        var lsig_interleaved_bits: List[UInt8],
        var lsig_symbols: List[Complex64],
        var lsig_spectrum: List[Complex64],
        var lsig_waveform: List[Complex64],
        var data_field_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var mother_bits: List[UInt8],
        var punctured_bits: List[UInt8],
        var interleaved_bits: List[UInt8],
        var qam_symbols: List[Complex64],
        var data_spectra: List[Complex64],
        var data_waveform: List[Complex64],
        var stf_waveform: List[Complex64],
        var ltf_waveform: List[Complex64],
        var ppdu_waveform: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.profile = profile
        self.geometry = geometry
        self.scrambler_seed = scrambler_seed
        self.fcs = fcs
        self.lsig_bits = lsig_bits^
        self.lsig_coded_bits = lsig_coded_bits^
        self.lsig_interleaved_bits = lsig_interleaved_bits^
        self.lsig_symbols = lsig_symbols^
        self.lsig_spectrum = lsig_spectrum^
        self.lsig_waveform = lsig_waveform^
        self.data_field_bits = data_field_bits^
        self.scrambled_bits = scrambled_bits^
        self.mother_bits = mother_bits^
        self.punctured_bits = punctured_bits^
        self.interleaved_bits = interleaved_bits^
        self.qam_symbols = qam_symbols^
        self.data_spectra = data_spectra^
        self.data_waveform = data_waveform^
        self.stf_waveform = stf_waveform^
        self.ltf_waveform = ltf_waveform^
        self.ppdu_waveform = ppdu_waveform^
        self.checkpoint_metadata = checkpoint_metadata^


struct WifiOFDMERPRx20MHz(Movable):
    """Decoded fields, inverse-chain checkpoints, and FCS decision."""

    var profile: WifiOFDMERPRateProfile
    var geometry: WifiOFDMERPGeometry
    var scrambler_seed: UInt8
    var channel_estimate: List[Complex64]
    var lsig_equalized_symbols: List[Complex64]
    var lsig_demapped_bits: List[UInt8]
    var lsig_deinterleaved_bits: List[UInt8]
    var lsig_decoded_bits: List[UInt8]
    var equalized_data_symbols: List[Complex64]
    var demapped_bits: List[UInt8]
    var deinterleaved_bits: List[UInt8]
    var depunctured_llrs: List[Float64]
    var decoded_scrambled_bits: List[UInt8]
    var descrambled_bits: List[UInt8]
    var mpdu_bits_without_fcs: List[UInt8]
    var received_fcs: UInt64
    var computed_fcs: UInt64
    var service_ok: Bool
    var tail_ok: Bool
    var fcs_ok: Bool
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        profile: WifiOFDMERPRateProfile,
        geometry: WifiOFDMERPGeometry,
        scrambler_seed: UInt8,
        var channel_estimate: List[Complex64],
        var lsig_equalized_symbols: List[Complex64],
        var lsig_demapped_bits: List[UInt8],
        var lsig_deinterleaved_bits: List[UInt8],
        var lsig_decoded_bits: List[UInt8],
        var equalized_data_symbols: List[Complex64],
        var demapped_bits: List[UInt8],
        var deinterleaved_bits: List[UInt8],
        var depunctured_llrs: List[Float64],
        var decoded_scrambled_bits: List[UInt8],
        var descrambled_bits: List[UInt8],
        var mpdu_bits_without_fcs: List[UInt8],
        received_fcs: UInt64,
        computed_fcs: UInt64,
        service_ok: Bool,
        tail_ok: Bool,
        fcs_ok: Bool,
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.profile = profile
        self.geometry = geometry
        self.scrambler_seed = scrambler_seed
        self.channel_estimate = channel_estimate^
        self.lsig_equalized_symbols = lsig_equalized_symbols^
        self.lsig_demapped_bits = lsig_demapped_bits^
        self.lsig_deinterleaved_bits = lsig_deinterleaved_bits^
        self.lsig_decoded_bits = lsig_decoded_bits^
        self.equalized_data_symbols = equalized_data_symbols^
        self.demapped_bits = demapped_bits^
        self.deinterleaved_bits = deinterleaved_bits^
        self.depunctured_llrs = depunctured_llrs^
        self.decoded_scrambled_bits = decoded_scrambled_bits^
        self.descrambled_bits = descrambled_bits^
        self.mpdu_bits_without_fcs = mpdu_bits_without_fcs^
        self.received_fcs = received_fcs
        self.computed_fcs = computed_fcs
        self.service_ok = service_ok
        self.tail_ok = tail_ok
        self.fcs_ok = fcs_ok
        self.checkpoint_metadata = checkpoint_metadata^


def _rate_profile(clause: Int, rate_mbps: Int) raises -> WifiOFDMERPRateProfile:
    if (
        clause != WIFI_OFDM_CLAUSE_17
        and clause != WIFI_ERP_OFDM_CLAUSE_18
    ):
        raise Error("OFDM profile must select IEEE 802.11 Clause 17 or 18")
    if rate_mbps == 6:
        return WifiOFDMERPRateProfile(clause, 6, 0b1011, 1, 1, 2, 48, 24)
    if rate_mbps == 9:
        return WifiOFDMERPRateProfile(clause, 9, 0b1111, 1, 3, 4, 48, 36)
    if rate_mbps == 12:
        return WifiOFDMERPRateProfile(clause, 12, 0b1010, 2, 1, 2, 96, 48)
    if rate_mbps == 18:
        return WifiOFDMERPRateProfile(clause, 18, 0b1110, 2, 3, 4, 96, 72)
    if rate_mbps == 24:
        return WifiOFDMERPRateProfile(clause, 24, 0b1001, 4, 1, 2, 192, 96)
    if rate_mbps == 36:
        return WifiOFDMERPRateProfile(clause, 36, 0b1101, 4, 3, 4, 192, 144)
    if rate_mbps == 48:
        return WifiOFDMERPRateProfile(clause, 48, 0b1000, 6, 2, 3, 288, 192)
    if rate_mbps == 54:
        return WifiOFDMERPRateProfile(clause, 54, 0b1100, 6, 3, 4, 288, 216)
    raise Error("unknown legacy OFDM RATE field")


def wifi_ofdm_erp_rate_profile(
    config: WifiOFDMERPConfig,
) raises -> WifiOFDMERPRateProfile:
    """Return the exact RATE/N_CBPS/N_DBPS row after mutable revalidation."""
    config.validate()
    return _rate_profile(config.clause, config.rate_mbps)


def _validate_lsig_length(psdu_length_octets: Int) raises:
    if psdu_length_octets < 0 or psdu_length_octets > 4095:
        raise Error("legacy OFDM L-SIG LENGTH must lie in [0,4095]")


def wifi_ofdm_erp_geometry(
    config: WifiOFDMERPConfig, psdu_length_octets: Int
) raises -> WifiOFDMERPGeometry:
    """Return SERVICE/PSDU/tail/pad and PPDU/medium-occupancy geometry."""
    config.validate()
    _validate_lsig_length(psdu_length_octets)
    var profile = _rate_profile(config.clause, config.rate_mbps)
    # The 12-bit LENGTH bound makes every product below safely representable.
    var before_pad = 16 + 8 * psdu_length_octets + 6
    var symbols = (
        before_pad + profile.data_bits_per_symbol - 1
    ) // profile.data_bits_per_symbol
    var padded = symbols * profile.data_bits_per_symbol
    var ppdu_samples = (
        WIFI_OFDM_STF_SAMPLES
        + WIFI_OFDM_LTF_SAMPLES
        + WIFI_OFDM_LSIG_SAMPLES
        + symbols * WIFI_OFDM_SYMBOL_SAMPLES
    )
    return WifiOFDMERPGeometry(
        psdu_length_octets,
        before_pad,
        padded - before_pad,
        symbols,
        ppdu_samples,
        profile.signal_extension_samples,
    )


def _rate_bits(profile: WifiOFDMERPRateProfile) -> List[UInt8]:
    var result = List[UInt8](capacity=4)
    for bit in range(4):
        result.append(UInt8((profile.rate_code_lsb_first >> bit) & 1))
    return result^


def wifi_ofdm_erp_lsig_bits(
    config: WifiOFDMERPConfig, psdu_length_octets: Int
) raises -> List[UInt8]:
    """Build the 24 raw RATE/fixed/LENGTH/parity/tail L-SIG bits."""
    config.validate()
    _validate_lsig_length(psdu_length_octets)
    var profile = _rate_profile(config.clause, config.rate_mbps)
    var rate = _rate_bits(profile)
    return wifi_legacy_signal_bits(Span(rate), psdu_length_octets)


def wifi_erp_protection_decision(
    non_erp_sta_associated: Bool, use_protection: Bool
) raises -> WifiERPProtectionDecision:
    """Validate the associated-NonERP implication and expose protection need.

    A true Use_Protection bit without an associated NonERP STA remains legal:
    overlapping-BSS conditions can require it.  Selection of an actual RTS/CTS
    or CTS-to-self exchange is intentionally outside this deterministic API.
    """
    if non_erp_sta_associated and not use_protection:
        raise Error("an associated NonERP STA requires Use_Protection=1")
    return WifiERPProtectionDecision(
        non_erp_sta_associated, use_protection
    )


def _bin(subcarrier: Int) -> Int:
    return subcarrier if subcarrier >= 0 else WIFI_OFDM_FFT_SIZE + subcarrier


def _slice_u8(
    bits: Span[UInt8, ...], offset: Int, count: Int
) raises -> List[UInt8]:
    if offset < 0 or count < 0 or count > len(bits) or offset > len(bits) - count:
        raise Error("bit slice lies outside the OFDM checkpoint")
    var result = List[UInt8](capacity=count)
    for index in range(count):
        result.append(bits[offset + index])
    return result^


def _slice_complex(
    samples: Span[Complex64, ...], offset: Int, count: Int
) raises -> List[Complex64]:
    if (
        offset < 0
        or count < 0
        or count > len(samples)
        or offset > len(samples) - count
    ):
        raise Error("sample slice lies outside the OFDM PPDU")
    var result = List[Complex64](capacity=count)
    for index in range(count):
        result.append(samples[offset + index])
    return result^


def _legacy_spectrum(
    data: Span[Complex64, ...], symbol_index: Int
) raises -> List[Complex64]:
    if len(data) != 48:
        raise Error("legacy OFDM mapping requires 48 data tones")
    var spectrum = List[Complex64](
        length=WIFI_OFDM_FFT_SIZE, fill=Complex64(0.0, 0.0)
    )
    var carriers = wifi_data_subcarriers()
    for index in range(48):
        spectrum[_bin(carriers[index])] = data[index]
    var polarity = wifi_pilot_polarity(symbol_index)
    spectrum[_bin(-21)] = Complex64(polarity)
    spectrum[_bin(-7)] = Complex64(polarity)
    spectrum[_bin(7)] = Complex64(polarity)
    spectrum[_bin(21)] = Complex64(-polarity)
    return spectrum^


def _append_bit_checkpoint(
    mut result: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stage: StringSlice,
    length: Int,
) raises:
    result.append(checkpoint_metadata_1d(
        testcase_id,
        stage,
        "uint8",
        length,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))


def _append_complex_checkpoint(
    mut result: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stage: StringSlice,
    length: Int,
) raises:
    result.append(checkpoint_metadata_1d(
        testcase_id, stage, "complex64", length, layout="iq-interleaved"
    ))


def _tx_metadata(
    testcase_id: StringSlice,
    mpdu_bits: Int,
    lsig_bits: Int,
    lsig_coded: Int,
    lsig_interleaved: Int,
    lsig_symbols: Int,
    data_bits: Int,
    scrambled: Int,
    mother: Int,
    punctured: Int,
    interleaved: Int,
    qam: Int,
    spectra: Int,
    data_waveform: Int,
    stf: Int,
    ltf: Int,
    lsig_waveform: Int,
    ppdu: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=20)
    _append_bit_checkpoint(result, testcase_id, "mpdu-without-fcs", mpdu_bits)
    for stage, length in [
        ("lsig-bits", lsig_bits),
        ("lsig-coded-bits", lsig_coded),
        ("lsig-interleaved-bits", lsig_interleaved),
    ]:
        _append_bit_checkpoint(result, testcase_id, stage, length)
    _append_complex_checkpoint(result, testcase_id, "lsig-symbols", lsig_symbols)
    result.append(checkpoint_metadata_2d(
        testcase_id,
        "lsig-spectrum",
        "complex64",
        1,
        WIFI_OFDM_FFT_SIZE,
        row_stride=WIFI_OFDM_FFT_SIZE,
        layout="row-major-unshifted-fft-bins",
    ))
    for stage, length in [
        ("data-field-bits", data_bits),
        ("scrambled-bits", scrambled),
        ("mother-bits", mother),
        ("punctured-bits", punctured),
        ("interleaved-bits", interleaved),
    ]:
        _append_bit_checkpoint(result, testcase_id, stage, length)
    _append_complex_checkpoint(result, testcase_id, "qam-symbols", qam)
    result.append(checkpoint_metadata_2d(
        testcase_id,
        "data-spectra",
        "complex64",
        spectra // WIFI_OFDM_FFT_SIZE,
        WIFI_OFDM_FFT_SIZE,
        row_stride=WIFI_OFDM_FFT_SIZE,
        layout="row-major-unshifted-fft-bins",
    ))
    for stage, length in [
        ("data-waveform", data_waveform),
        ("stf-waveform", stf),
        ("ltf-waveform", ltf),
        ("lsig-waveform", lsig_waveform),
        ("ppdu-waveform", ppdu),
    ]:
        _append_complex_checkpoint(result, testcase_id, stage, length)
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "fcs",
        "uint64",
        1,
        q_format="unsigned-integer",
        layout="scalar",
    ))
    return result^


def _validate_mpdu_without_fcs(bits: Span[UInt8, ...]) raises:
    if len(bits) % 8 != 0:
        raise Error("OFDM MPDU input must contain complete octets")
    if len(bits) > 8 * (4095 - 4):
        raise Error("MPDU plus four-octet FCS exceeds L-SIG LENGTH")
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("OFDM MPDU input must be binary")


def wifi_ofdm_erp_tx_20mhz(
    mpdu_bits_without_fcs: Span[UInt8, ...],
    config: WifiOFDMERPConfig,
    *,
    testcase_id: StringSlice = "wifi-ofdm-erp-tx-20mhz",
) raises -> WifiOFDMERPTx20MHz:
    """Build one complete synchronized Clause-17 or ERP-OFDM PPDU."""
    config.validate()
    _validate_mpdu_without_fcs(mpdu_bits_without_fcs)
    var profile = _rate_profile(config.clause, config.rate_mbps)
    var psdu_octets = len(mpdu_bits_without_fcs) // 8 + 4
    var geometry = wifi_ofdm_erp_geometry(config, psdu_octets)

    var lsig_bits = wifi_ofdm_erp_lsig_bits(config, psdu_octets)
    var generators: List[Int] = [0o133, 0o171]
    var lsig_coded = convolutional_encode(
        Span(lsig_bits), Span(generators), 7, terminate=False
    )
    var lsig_interleaved = wifi_interleave(Span(lsig_coded), 1)
    var lsig_symbols = qam_map(Span(lsig_interleaved), 1)
    var lsig_spectrum = _legacy_spectrum(Span(lsig_symbols), 0)
    var lsig_waveform = ofdm_modulate(
        Span(lsig_spectrum), WIFI_OFDM_GI_SAMPLES
    )

    var fcs = wifi_fcs(mpdu_bits_without_fcs)
    var data = List[UInt8](
        capacity=geometry.data_symbols * profile.data_bits_per_symbol
    )
    for _ in range(16):
        data.append(UInt8(0))
    for index in range(len(mpdu_bits_without_fcs)):
        data.append(mpdu_bits_without_fcs[index])
    for bit in range(32):
        data.append(UInt8((fcs >> UInt64(bit)) & UInt64(1)))
    var tail_start = len(data)
    for _ in range(6):
        data.append(UInt8(0))
    while len(data) < geometry.data_symbols * profile.data_bits_per_symbol:
        data.append(UInt8(0))

    var scrambled = wifi_scramble(Span(data), config.scrambler_seed)
    # The six encoder-reset tail bits are overwritten after scrambling.
    for index in range(tail_start, tail_start + 6):
        scrambled[index] = UInt8(0)
    var mother = convolutional_encode(
        Span(scrambled), Span(generators), 7, terminate=False
    )
    var punctured = wifi_bcc_puncture(
        Span(mother),
        profile.code_rate_numerator,
        profile.code_rate_denominator,
    )
    var expected_coded = (
        geometry.data_symbols * profile.coded_bits_per_symbol
    )
    if len(punctured) != expected_coded:
        raise Error("internal OFDM puncturing geometry mismatch")

    var interleaved = List[UInt8](capacity=expected_coded)
    var all_qam = List[Complex64](capacity=48 * geometry.data_symbols)
    var spectra = List[Complex64](
        capacity=WIFI_OFDM_FFT_SIZE * geometry.data_symbols
    )
    var data_waveform = List[Complex64](
        capacity=WIFI_OFDM_SYMBOL_SAMPLES * geometry.data_symbols
    )
    for symbol in range(geometry.data_symbols):
        var coded_block = _slice_u8(
            Span(punctured),
            symbol * profile.coded_bits_per_symbol,
            profile.coded_bits_per_symbol,
        )
        var interleaved_block = wifi_interleave(
            Span(coded_block), profile.bits_per_subcarrier
        )
        for bit in interleaved_block:
            interleaved.append(bit)
        var qam = qam_map(
            Span(interleaved_block), profile.bits_per_subcarrier
        )
        for value in qam:
            all_qam.append(value)
        var spectrum = _legacy_spectrum(Span(qam), symbol + 1)
        for value in spectrum:
            spectra.append(value)
        var waveform = ofdm_modulate(
            Span(spectrum), WIFI_OFDM_GI_SAMPLES
        )
        for value in waveform:
            data_waveform.append(value)

    var stf = wifi_stf_waveform_20mhz()
    var ltf = wifi_legacy_ltf_waveform_20mhz()
    if (
        len(stf) != WIFI_OFDM_STF_SAMPLES
        or len(ltf) != WIFI_OFDM_LTF_SAMPLES
        or len(lsig_waveform) != WIFI_OFDM_LSIG_SAMPLES
    ):
        raise Error("legacy OFDM preamble geometry mismatch")
    var ppdu = List[Complex64](capacity=geometry.ppdu_samples)
    for value in stf:
        ppdu.append(value)
    for value in ltf:
        ppdu.append(value)
    for value in lsig_waveform:
        ppdu.append(value)
    for value in data_waveform:
        ppdu.append(value)
    if len(ppdu) != geometry.ppdu_samples:
        raise Error("internal OFDM PPDU sample geometry mismatch")

    var metadata = _tx_metadata(
        testcase_id,
        len(mpdu_bits_without_fcs),
        len(lsig_bits),
        len(lsig_coded),
        len(lsig_interleaved),
        len(lsig_symbols),
        len(data),
        len(scrambled),
        len(mother),
        len(punctured),
        len(interleaved),
        len(all_qam),
        len(spectra),
        len(data_waveform),
        len(stf),
        len(ltf),
        len(lsig_waveform),
        len(ppdu),
    )
    return WifiOFDMERPTx20MHz(
        profile,
        geometry,
        config.scrambler_seed,
        fcs,
        lsig_bits^,
        lsig_coded^,
        lsig_interleaved^,
        lsig_symbols^,
        lsig_spectrum^,
        lsig_waveform^,
        data^,
        scrambled^,
        mother^,
        punctured^,
        interleaved^,
        all_qam^,
        spectra^,
        data_waveform^,
        stf^,
        ltf^,
        ppdu^,
        metadata^,
    )


def _ltf_channel_estimate(
    samples: Span[Complex64, ...]
) raises -> List[Complex64]:
    var first_time = _slice_complex(samples, WIFI_OFDM_STF_SAMPLES + 32, 64)
    var second_time = _slice_complex(samples, WIFI_OFDM_STF_SAMPLES + 96, 64)
    var first = ofdm_demodulate(Span(first_time), 64, 0)
    var second = ofdm_demodulate(Span(second_time), 64, 0)
    var known = wifi_legacy_ltf_spectrum_20mhz()
    var channel = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    for index in range(64):
        if known[index].re != 0.0 or known[index].im != 0.0:
            # Half before add keeps the finite-input average scale safe.
            var average = Complex64(
                first[index].re * 0.5 + second[index].re * 0.5,
                first[index].im * 0.5 + second[index].im * 0.5,
            )
            channel[index] = complex_divide(average, known[index])
            if channel[index].re == 0.0 and channel[index].im == 0.0:
                raise Error("legacy L-LTF produced a zero occupied-tone channel")
    return channel^


def _equalized_spectrum(
    waveform: Span[Complex64, ...], channel: Span[Complex64, ...]
) raises -> List[Complex64]:
    if len(channel) != 64:
        raise Error("legacy OFDM channel estimate must contain 64 bins")
    var received = ofdm_demodulate(
        waveform, WIFI_OFDM_FFT_SIZE, WIFI_OFDM_GI_SAMPLES
    )
    var result = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    for index in range(64):
        if channel[index].re != 0.0 or channel[index].im != 0.0:
            var observation = Complex64(
                received[index].re, received[index].im
            )
            var coefficient = Complex64(
                channel[index].re, channel[index].im
            )
            result[index] = complex_divide(observation, coefficient)
    return result^


def _pilot_corrected_data(
    spectrum: Span[Complex64, ...], symbol_index: Int
) raises -> List[Complex64]:
    if len(spectrum) != 64:
        raise Error("legacy OFDM spectrum must contain 64 bins")
    var polarity = wifi_pilot_polarity(symbol_index)
    var known: List[Complex64] = [
        Complex64(polarity),
        Complex64(polarity),
        Complex64(polarity),
        Complex64(-polarity),
    ]
    var pilot_indices: List[Int] = [-21, -7, 7, 21]
    var received = List[Complex64](capacity=4)
    for subcarrier in pilot_indices:
        received.append(spectrum[_bin(subcarrier)])
    var estimate = wifi_estimate_pilot_phase(
        Span(received), Span(known), Span(pilot_indices)
    )
    var carriers = wifi_data_subcarriers()
    var data = List[Complex64](capacity=48)
    for subcarrier in carriers:
        data.append(spectrum[_bin(subcarrier)])
    return wifi_correct_pilot_phase(Span(data), Span(carriers), estimate)


def _rate_from_lsig(rate_bits: Span[UInt8, ...], clause: Int) raises -> WifiOFDMERPRateProfile:
    if len(rate_bits) != 4:
        raise Error("decoded legacy RATE field must contain four bits")
    var code = 0
    for bit in range(4):
        if rate_bits[bit] > 1:
            raise Error("decoded legacy RATE field must be binary")
        code |= Int(rate_bits[bit]) << bit
    for rate in [6, 9, 12, 18, 24, 36, 48, 54]:
        var profile = _rate_profile(clause, rate)
        if profile.rate_code_lsb_first == code:
            return profile
    raise Error("decoded L-SIG RATE is reserved")


def _recover_scrambler_seed(
    decoded_scrambled: Span[UInt8, ...]
) raises -> UInt8:
    if len(decoded_scrambled) < 7:
        raise Error("decoded DATA is too short to recover scrambler seed")
    var zeros = List[UInt8](length=7, fill=UInt8(0))
    var matches = 0
    var recovered = UInt8(0)
    for candidate in range(1, 128):
        var prefix = wifi_scramble(Span(zeros), UInt8(candidate))
        var equal = True
        for index in range(7):
            equal = equal and prefix[index] == decoded_scrambled[index]
        if equal:
            recovered = UInt8(candidate)
            matches += 1
    if matches != 1:
        raise Error("SERVICE prefix does not identify one scrambler seed")
    return recovered


def _read_fcs(bits: Span[UInt8, ...], offset: Int) raises -> UInt64:
    if offset < 0 or offset > len(bits) - 32:
        raise Error("decoded FCS lies outside DATA")
    var result = UInt64(0)
    for bit in range(32):
        result |= UInt64(bits[offset + bit]) << UInt64(bit)
    return result


def _rx_metadata(
    testcase_id: StringSlice,
    received: Int,
    channel: Int,
    lsig_symbols: Int,
    lsig_demapped: Int,
    lsig_deinterleaved: Int,
    lsig_decoded: Int,
    equalized_data: Int,
    demapped: Int,
    deinterleaved: Int,
    depunctured: Int,
    decoded: Int,
    descrambled: Int,
    payload: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=18)
    _append_complex_checkpoint(result, testcase_id, "received-ppdu", received)
    _append_complex_checkpoint(result, testcase_id, "ltf-channel-estimate", channel)
    _append_complex_checkpoint(result, testcase_id, "lsig-equalized-symbols", lsig_symbols)
    for stage, length in [
        ("lsig-demapped-bits", lsig_demapped),
        ("lsig-deinterleaved-bits", lsig_deinterleaved),
        ("lsig-decoded-bits", lsig_decoded),
    ]:
        _append_bit_checkpoint(result, testcase_id, stage, length)
    _append_complex_checkpoint(result, testcase_id, "equalized-data-symbols", equalized_data)
    for stage, length in [
        ("demapped-bits", demapped),
        ("deinterleaved-bits", deinterleaved),
    ]:
        _append_bit_checkpoint(result, testcase_id, stage, length)
    result.append(checkpoint_metadata_1d(
        testcase_id, "depunctured-llrs", "float64", depunctured
    ))
    for stage, length in [
        ("decoded-scrambled-bits", decoded),
        ("descrambled-data-bits", descrambled),
        ("mpdu-without-fcs", payload),
    ]:
        _append_bit_checkpoint(result, testcase_id, stage, length)
    for stage, dtype, q_format in [
        ("received-fcs", "uint64", "unsigned-integer"),
        ("computed-fcs", "uint64", "unsigned-integer"),
        ("service-ok", "bool", "boolean"),
        ("tail-ok", "bool", "boolean"),
        ("fcs-ok", "bool", "boolean"),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            dtype,
            1,
            q_format=q_format,
            layout="scalar",
        ))
    return result^


def wifi_ofdm_erp_rx_20mhz(
    ppdu_waveform: Span[Complex64, ...],
    clause: Int,
    *,
    testcase_id: StringSlice = "wifi-ofdm-erp-rx-20mhz",
) raises -> WifiOFDMERPRx20MHz:
    """Decode a synchronized Clause-17/18 PPDU and verify its actual FCS.

    Input contains transmitted PPDU samples only.  Clause 18's following
    6 us idle signal extension is represented by returned geometry, not input
    zeros.  The fixed timing boundary starts L-LTF at sample 160, L-SIG at
    320, and DATA at 400; acquisition and CCA are intentionally separate.
    """
    if (
        clause != WIFI_OFDM_CLAUSE_17
        and clause != WIFI_ERP_OFDM_CLAUSE_18
    ):
        raise Error("OFDM receiver must select IEEE 802.11 Clause 17 or 18")
    if len(ppdu_waveform) < 400 + WIFI_OFDM_SYMBOL_SAMPLES:
        raise Error("OFDM observation is shorter than a minimum PPDU")
    for index in range(len(ppdu_waveform)):
        if (
            not isfinite(ppdu_waveform[index].re)
            or not isfinite(ppdu_waveform[index].im)
        ):
            raise Error("OFDM PPDU samples must be finite")

    var channel = _ltf_channel_estimate(ppdu_waveform)
    var lsig_waveform = _slice_complex(
        ppdu_waveform, WIFI_OFDM_STF_SAMPLES + WIFI_OFDM_LTF_SAMPLES, 80
    )
    var lsig_spectrum = _equalized_spectrum(
        Span(lsig_waveform), Span(channel)
    )
    var lsig_symbols = _pilot_corrected_data(Span(lsig_spectrum), 0)
    var lsig_demapped = qam_demap_hard(Span(lsig_symbols), 1)
    var lsig_deinterleaved = wifi_deinterleave(Span(lsig_demapped), 1)
    var lsig_llrs = List[Float64](capacity=48)
    for bit in lsig_deinterleaved:
        lsig_llrs.append(24.0 if bit == 0 else -24.0)
    var generators: List[Int] = [0o133, 0o171]
    var lsig_decoded = viterbi_decode_soft(
        Span(lsig_llrs), Span(generators), 7, terminate=False
    )
    if len(lsig_decoded) != 24:
        raise Error("legacy L-SIG decoder returned an invalid length")
    if lsig_decoded[4] != 0:
        raise Error("legacy L-SIG fixed bit is nonzero")
    for index in range(18, 24):
        if lsig_decoded[index] != 0:
            raise Error("legacy L-SIG tail is nonzero")
    var fields: LegacySignal = wifi_parse_legacy_signal(Span(lsig_decoded))
    var profile = _rate_from_lsig(Span(fields.rate_bits), clause)
    if fields.length_octets < 4:
        raise Error("FCS-driven OFDM PPDU requires L-SIG LENGTH of at least four")
    var recovered_config = WifiOFDMERPConfig(
        clause, profile.rate_mbps, scrambler_seed=UInt8(1)
    )
    var geometry = wifi_ofdm_erp_geometry(
        recovered_config, fields.length_octets
    )
    if len(ppdu_waveform) != geometry.ppdu_samples:
        raise Error("OFDM PPDU length does not match decoded L-SIG geometry")

    var equalized_data = List[Complex64](capacity=48 * geometry.data_symbols)
    var demapped = List[UInt8](
        capacity=geometry.data_symbols * profile.coded_bits_per_symbol
    )
    var deinterleaved = List[UInt8](
        capacity=geometry.data_symbols * profile.coded_bits_per_symbol
    )
    for symbol in range(geometry.data_symbols):
        var waveform = _slice_complex(
            ppdu_waveform,
            400 + symbol * WIFI_OFDM_SYMBOL_SAMPLES,
            WIFI_OFDM_SYMBOL_SAMPLES,
        )
        var spectrum = _equalized_spectrum(Span(waveform), Span(channel))
        var corrected = _pilot_corrected_data(Span(spectrum), symbol + 1)
        for value in corrected:
            equalized_data.append(value)
        var mapped = qam_demap_hard(
            Span(corrected), profile.bits_per_subcarrier
        )
        for bit in mapped:
            demapped.append(bit)
        var restored = wifi_deinterleave(
            Span(mapped), profile.bits_per_subcarrier
        )
        for bit in restored:
            deinterleaved.append(bit)

    var punctured_llrs = List[Float64](capacity=len(deinterleaved))
    for bit in deinterleaved:
        punctured_llrs.append(24.0 if bit == 0 else -24.0)
    var decoded_bit_count = geometry.data_symbols * profile.data_bits_per_symbol
    var depunctured = wifi_bcc_depuncture_llrs(
        Span(punctured_llrs),
        2 * decoded_bit_count,
        profile.code_rate_numerator,
        profile.code_rate_denominator,
    )
    var decoded_scrambled = viterbi_decode_soft(
        Span(depunctured), Span(generators), 7, terminate=False
    )
    if len(decoded_scrambled) != decoded_bit_count:
        raise Error("legacy DATA decoder returned an invalid length")
    var seed = _recover_scrambler_seed(Span(decoded_scrambled))
    var descrambled = wifi_scramble(Span(decoded_scrambled), seed)

    var payload_bit_count = 8 * (fields.length_octets - 4)
    var tail_start = 16 + payload_bit_count + 32
    var service_ok = True
    for index in range(16):
        service_ok = service_ok and descrambled[index] == 0
    var tail_ok = True
    for index in range(tail_start, tail_start + 6):
        tail_ok = tail_ok and decoded_scrambled[index] == 0
    var payload = _slice_u8(Span(descrambled), 16, payload_bit_count)
    var received_fcs = _read_fcs(Span(descrambled), 16 + payload_bit_count)
    var computed_fcs = wifi_fcs(Span(payload))
    var fcs_ok = received_fcs == computed_fcs
    var metadata = _rx_metadata(
        testcase_id,
        len(ppdu_waveform),
        len(channel),
        len(lsig_symbols),
        len(lsig_demapped),
        len(lsig_deinterleaved),
        len(lsig_decoded),
        len(equalized_data),
        len(demapped),
        len(deinterleaved),
        len(depunctured),
        len(decoded_scrambled),
        len(descrambled),
        len(payload),
    )
    return WifiOFDMERPRx20MHz(
        profile,
        geometry,
        seed,
        channel^,
        lsig_symbols^,
        lsig_demapped^,
        lsig_deinterleaved^,
        lsig_decoded^,
        equalized_data^,
        demapped^,
        deinterleaved^,
        depunctured^,
        decoded_scrambled^,
        descrambled^,
        payload^,
        received_fcs,
        computed_fcs,
        service_ok,
        tail_ok,
        fcs_ok,
        metadata^,
    )
