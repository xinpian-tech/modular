"""Acquired one-symbol HE/EHT RU-242 LDPC reference link.

This module composes the public Wi-Fi, synchronization, channel, DSP, modem,
and FEC APIs into one auditable 20 MHz waveform-to-payload path.  The modeled
packet is

    L-STF | representative L-LTF | L-SIG | 4x HE/EHT-LTF | DATA

where the legacy fields provide packet detection, coarse CFO, and a validated
6 Mb/s L-SIG.  One 256-point (4x) HE/EHT-LTF supplies fine timing, residual
CFO, and per-tone least-squares channel estimates.  The existing RU-242 LDPC
PHY then performs pilot phase tracking, 1024/4096-QAM soft demapping, LDPC
recovery, SERVICE validation, and FCS validation.

The boundary is intentionally narrow: one spatial stream, one 20 MHz RU-242,
HE MCS 10 or EHT MCS 13, one DATA symbol, a single 4x LTF training symbol, and
a block-constant SISO acquisition channel.  The legacy L-LTF is the standard
52-tone sequence recovered from the public HT training row, with the four HT
extension tones cleared.  This is a representative acquired mini-PHY, not an
interoperable HE/EHT PPDU: it omits RL-SIG, HE/EHT-SIG, packet extensions,
multi-user allocation signaling, multiple DATA symbols, and spatial training.
The channel may be frequency-selective but is constant over this short packet;
an opt-in reliability path uses each estimated tone's post-ZF variance.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64
from wireless_dsp.channel.impairments import apply_cfo
from wireless_dsp.dsp import (
    complex_divide,
    normalized_correlation_at,
    ofdm_demodulate,
    ofdm_modulate,
)
from wireless_dsp.fec import viterbi_decode_hard, viterbi_decode_soft
from wireless_dsp.modem import qam_demap_hard, qam_demapper_llr_piecewise
from wireless_dsp.synchronization import (
    estimate_repetition_cfo,
    repetition_metric,
)
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)
from wireless_dsp.wireless.wifi.acquisition_chain import (
    WifiLegacySignalTx20MHz,
    wifi_legacy_signal_tx_20mhz,
    wifi_stf_waveform_20mhz,
)
from wireless_dsp.wireless.wifi.legacy import (
    LegacySignal,
    wifi_data_subcarriers,
    wifi_deinterleave,
    wifi_parse_legacy_signal,
    wifi_pilot_polarity,
    wifi_stf_detect,
)
from wireless_dsp.wireless.wifi.phy_chain import (
    WifiLDPCRx20MHz,
    WifiLDPCTx20MHz,
    wifi_ldpc_rx_20mhz,
    wifi_ldpc_tx_20mhz,
)
from wireless_dsp.wireless.wifi.pilots import (
    wifi_correct_pilot_phase,
    wifi_estimate_pilot_phase,
)
from wireless_dsp.wireless.wifi.preambles import (
    wifi_ltf_channel_estimate_20mhz,
    wifi_ltf_spectrum_20mhz,
    wifi_ltf_waveform_20mhz,
)
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_EHT,
    WIFI_PHY_HE,
    WIFI_PHY_HT,
)


comptime _LEGACY_STF_SAMPLES = 160
comptime _LEGACY_LTF_SAMPLES = 160
comptime _LEGACY_SIGNAL_SAMPLES = 80
comptime _HE_EHT_LTF_SAMPLES = 272
comptime _HE_EHT_DATA_SAMPLES = 272
comptime _HE_EHT_LTF_FFT_SIZE = 256
comptime _HE_EHT_GI_SAMPLES = 16


struct WifiHEEHTAcquisitionTx20MHz(Movable):
    """Waveform and retained transmit checkpoints for the bounded mini-PHY."""

    var family: Int
    var mcs_index: Int
    var payload_bit_count: Int
    var scrambler_seed: UInt8
    var symbol_index: Int
    var legacy_ltf_offset: Int
    var signal_offset: Int
    var he_eht_ltf_offset: Int
    var data_offset: Int
    var legacy_ltf_spectrum: List[Complex64]
    var legacy_stf_waveform: List[Complex64]
    var legacy_ltf_waveform: List[Complex64]
    var he_eht_ltf_waveform: List[Complex64]
    var packet_waveform: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]
    var signal: WifiLegacySignalTx20MHz
    var data: WifiLDPCTx20MHz

    def __init__(
        out self,
        family: Int,
        mcs_index: Int,
        payload_bit_count: Int,
        scrambler_seed: UInt8,
        symbol_index: Int,
        legacy_ltf_offset: Int,
        signal_offset: Int,
        he_eht_ltf_offset: Int,
        data_offset: Int,
        var legacy_ltf_spectrum: List[Complex64],
        var legacy_stf_waveform: List[Complex64],
        var legacy_ltf_waveform: List[Complex64],
        var he_eht_ltf_waveform: List[Complex64],
        var packet_waveform: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
        var signal: WifiLegacySignalTx20MHz,
        var data: WifiLDPCTx20MHz,
    ):
        self.family = family
        self.mcs_index = mcs_index
        self.payload_bit_count = payload_bit_count
        self.scrambler_seed = scrambler_seed
        self.symbol_index = symbol_index
        self.legacy_ltf_offset = legacy_ltf_offset
        self.signal_offset = signal_offset
        self.he_eht_ltf_offset = he_eht_ltf_offset
        self.data_offset = data_offset
        self.legacy_ltf_spectrum = legacy_ltf_spectrum^
        self.legacy_stf_waveform = legacy_stf_waveform^
        self.legacy_ltf_waveform = legacy_ltf_waveform^
        self.he_eht_ltf_waveform = he_eht_ltf_waveform^
        self.packet_waveform = packet_waveform^
        self.checkpoint_metadata = checkpoint_metadata^
        self.signal = signal^
        self.data = data^


struct WifiHEEHTAcquisitionRx20MHz(Movable):
    """Acquisition, legacy validation, HE/EHT LS, LDPC, and FCS evidence."""

    var family: Int
    var mcs_index: Int
    var packet_start: Int
    var stf_metric: Float64
    var coarse_cfo: Float64
    var fine_cfo: Float64
    var legacy_ltf_start: Int
    var signal_start: Int
    var he_eht_ltf_start: Int
    var data_start: Int
    var he_eht_ltf_metric: Float64
    var signal_length_octets: Int
    var signal_reserved_ok: Bool
    var signal_parity_ok: Bool
    var signal_tail_ok: Bool
    var signal_rate_ok: Bool
    var signal_length_ok: Bool
    var signal_ok: Bool
    var coarse_corrected_samples: List[Complex64]
    var corrected_samples: List[Complex64]
    var legacy_ltf_samples: List[Complex64]
    var signal_samples: List[Complex64]
    var he_eht_ltf_samples: List[Complex64]
    var data_samples: List[Complex64]
    var legacy_channel_estimate: List[Complex64]
    var signal_equalized_spectrum: List[Complex64]
    var signal_corrected_symbols: List[Complex64]
    var signal_deinterleaved_bits: List[UInt8]
    var signal_decoded_bits: List[UInt8]
    var he_eht_channel_estimate: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]
    var data: WifiLDPCRx20MHz

    def __init__(
        out self,
        family: Int,
        mcs_index: Int,
        packet_start: Int,
        stf_metric: Float64,
        coarse_cfo: Float64,
        fine_cfo: Float64,
        legacy_ltf_start: Int,
        signal_start: Int,
        he_eht_ltf_start: Int,
        data_start: Int,
        he_eht_ltf_metric: Float64,
        signal_length_octets: Int,
        signal_reserved_ok: Bool,
        signal_parity_ok: Bool,
        signal_tail_ok: Bool,
        signal_rate_ok: Bool,
        signal_length_ok: Bool,
        signal_ok: Bool,
        var coarse_corrected_samples: List[Complex64],
        var corrected_samples: List[Complex64],
        var legacy_ltf_samples: List[Complex64],
        var signal_samples: List[Complex64],
        var he_eht_ltf_samples: List[Complex64],
        var data_samples: List[Complex64],
        var legacy_channel_estimate: List[Complex64],
        var signal_equalized_spectrum: List[Complex64],
        var signal_corrected_symbols: List[Complex64],
        var signal_deinterleaved_bits: List[UInt8],
        var signal_decoded_bits: List[UInt8],
        var he_eht_channel_estimate: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
        var data: WifiLDPCRx20MHz,
    ):
        self.family = family
        self.mcs_index = mcs_index
        self.packet_start = packet_start
        self.stf_metric = stf_metric
        self.coarse_cfo = coarse_cfo
        self.fine_cfo = fine_cfo
        self.legacy_ltf_start = legacy_ltf_start
        self.signal_start = signal_start
        self.he_eht_ltf_start = he_eht_ltf_start
        self.data_start = data_start
        self.he_eht_ltf_metric = he_eht_ltf_metric
        self.signal_length_octets = signal_length_octets
        self.signal_reserved_ok = signal_reserved_ok
        self.signal_parity_ok = signal_parity_ok
        self.signal_tail_ok = signal_tail_ok
        self.signal_rate_ok = signal_rate_ok
        self.signal_length_ok = signal_length_ok
        self.signal_ok = signal_ok
        self.coarse_corrected_samples = coarse_corrected_samples^
        self.corrected_samples = corrected_samples^
        self.legacy_ltf_samples = legacy_ltf_samples^
        self.signal_samples = signal_samples^
        self.he_eht_ltf_samples = he_eht_ltf_samples^
        self.data_samples = data_samples^
        self.legacy_channel_estimate = legacy_channel_estimate^
        self.signal_equalized_spectrum = signal_equalized_spectrum^
        self.signal_corrected_symbols = signal_corrected_symbols^
        self.signal_deinterleaved_bits = signal_deinterleaved_bits^
        self.signal_decoded_bits = signal_decoded_bits^
        self.he_eht_channel_estimate = he_eht_channel_estimate^
        self.checkpoint_metadata = checkpoint_metadata^
        self.data = data^


struct _LegacySignalDecode(Movable):
    var length_octets: Int
    var reserved_ok: Bool
    var tail_ok: Bool
    var rate_ok: Bool
    var length_ok: Bool
    var equalized_spectrum: List[Complex64]
    var corrected_symbols: List[Complex64]
    var deinterleaved_bits: List[UInt8]
    var decoded_bits: List[UInt8]

    def __init__(
        out self,
        length_octets: Int,
        reserved_ok: Bool,
        tail_ok: Bool,
        rate_ok: Bool,
        length_ok: Bool,
        var equalized_spectrum: List[Complex64],
        var corrected_symbols: List[Complex64],
        var deinterleaved_bits: List[UInt8],
        var decoded_bits: List[UInt8],
    ):
        self.length_octets = length_octets
        self.reserved_ok = reserved_ok
        self.tail_ok = tail_ok
        self.rate_ok = rate_ok
        self.length_ok = length_ok
        self.equalized_spectrum = equalized_spectrum^
        self.corrected_symbols = corrected_symbols^
        self.deinterleaved_bits = deinterleaved_bits^
        self.decoded_bits = decoded_bits^


def _wifi_bin(subcarrier: Int, fft_size: Int) -> Int:
    return subcarrier if subcarrier >= 0 else fft_size + subcarrier


def _validate_family(family: Int) raises:
    if family != WIFI_PHY_HE and family != WIFI_PHY_EHT:
        raise Error("acquired RU-242 mini-PHY requires HE or EHT")


def _validate_profile(family: Int, mcs_index: Int) raises:
    _validate_family(family)
    if family == WIFI_PHY_HE:
        if mcs_index != 10:
            raise Error("acquired HE RU-242 mini-PHY requires MCS 10")
    else:
        if mcs_index != 13:
            raise Error("acquired EHT RU-242 mini-PHY requires MCS 13")


def _slice_complex(
    samples: Span[Complex64, ...], offset: Int, count: Int
) raises -> List[Complex64]:
    if offset < 0 or count < 0 or count > len(samples) or offset > len(samples) - count:
        raise Error("complex sample slice lies outside the observation")
    var result = List[Complex64](capacity=count)
    for i in range(count):
        result.append(samples[offset + i])
    return result^


def wifi_legacy_ltf_spectrum_20mhz() raises -> List[Complex64]:
    """Return the 52-tone legacy L-LTF in unshifted 64-bin FFT order.

    The public HT training row contains the legacy k=-26..26 sequence plus
    the four HT extension tones.  Clearing k=-28,-27,+27,+28 therefore gives
    the legacy long-training spectrum without duplicating a second static
    sequence table.
    """
    var spectrum = wifi_ltf_spectrum_20mhz(WIFI_PHY_HT)
    for subcarrier in [-28, -27, 27, 28]:
        spectrum[_wifi_bin(subcarrier, 64)] = Complex64(0.0, 0.0)
    return spectrum^


def wifi_legacy_ltf_waveform_20mhz() raises -> List[Complex64]:
    """Return GI2 plus two standard 64-sample legacy long symbols."""
    var spectrum = wifi_legacy_ltf_spectrum_20mhz()
    var long_symbol = ofdm_modulate(Span(spectrum), 0)
    var result = List[Complex64](capacity=_LEGACY_LTF_SAMPLES)
    for i in range(32, 64):
        result.append(long_symbol[i])
    for _ in range(2):
        for sample in long_symbol:
            result.append(sample)
    return result^


def wifi_he_eht_ltf_fine_timing_20mhz(
    samples: Span[Complex64, ...],
    family: Int,
    expected_start: Int,
    *,
    search_radius: Int = 16,
) raises -> Int:
    """Locate a 4x HE/EHT-LTF by normalized complex correlation."""
    _validate_family(family)
    if expected_start < 0 or search_radius < 0:
        raise Error("invalid HE/EHT-LTF timing-search window")
    for i in range(len(samples)):
        if not isfinite(samples[i].re) or not isfinite(samples[i].im):
            raise Error("HE/EHT-LTF timing observation must be finite")
    var known = wifi_ltf_waveform_20mhz(
        family, cyclic_prefix_samples=_HE_EHT_GI_SAMPLES
    )
    if len(samples) < len(known):
        raise Error("observation is shorter than one 4x HE/EHT-LTF")
    var available_last = len(samples) - len(known)
    var first = (
        expected_start - search_radius
        if expected_start >= search_radius
        else 0
    )
    var last = available_last
    if expected_start <= available_last:
        last = expected_start + min(
            search_radius, available_last - expected_start
        )
    if first > last:
        raise Error("HE/EHT-LTF timing-search window lies outside observation")
    var best_offset = first
    var best_metric = -1.0
    for offset in range(first, last + 1):
        var correlation = normalized_correlation_at(
            samples, Span(known), offset
        )
        var metric = correlation.magnitude_squared()
        if metric > best_metric:
            best_metric = metric
            best_offset = offset
    return best_offset


def wifi_he_eht_ltf_fine_cfo_20mhz(
    samples: Span[Complex64, ...], ltf_start: Int
) raises -> Float64:
    """Estimate residual CFO from the 16-sample GI of a 256-point LTF."""
    if (
        ltf_start < 0
        or len(samples) < _HE_EHT_LTF_FFT_SIZE + _HE_EHT_GI_SAMPLES
        or ltf_start
        > len(samples) - _HE_EHT_LTF_FFT_SIZE - _HE_EHT_GI_SAMPLES
    ):
        raise Error("invalid 4x HE/EHT-LTF CFO window")
    for i in range(_HE_EHT_GI_SAMPLES):
        var prefix = samples[ltf_start + i]
        var repeated = samples[ltf_start + _HE_EHT_LTF_FFT_SIZE + i]
        if (
            not isfinite(prefix.re)
            or not isfinite(prefix.im)
            or not isfinite(repeated.re)
            or not isfinite(repeated.im)
        ):
            raise Error("HE/EHT-LTF CFO observation must be finite")
    return estimate_repetition_cfo(
        samples,
        ltf_start,
        _HE_EHT_LTF_FFT_SIZE,
        _HE_EHT_GI_SAMPLES,
    )


def _legacy_ltf_channel_estimate_20mhz(
    samples: Span[Complex64, ...]
) raises -> List[Complex64]:
    if len(samples) != _LEGACY_LTF_SAMPLES:
        raise Error("legacy L-LTF must contain GI2 and two long symbols")
    var first = _slice_complex(samples, 32, 64)
    var second = _slice_complex(samples, 96, 64)
    var first_spectrum = ofdm_demodulate(Span(first), 64, 0)
    var second_spectrum = ofdm_demodulate(Span(second), 64, 0)
    var known = wifi_legacy_ltf_spectrum_20mhz()
    var result = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    for i in range(64):
        if known[i].magnitude_squared() > 0.0:
            var average = Complex64(
                0.5 * first_spectrum[i].re + 0.5 * second_spectrum[i].re,
                0.5 * first_spectrum[i].im + 0.5 * second_spectrum[i].im,
            )
            result[i] = complex_divide(average, known[i])
    return result^


def _decode_legacy_signal_20mhz(
    samples: Span[Complex64, ...],
    channel: Span[Complex64, ...],
    expected_length_octets: Int,
    *,
    llr_noise_variance: Float64 = 1.0,
    per_tone_llr_reliability: Bool = False,
) raises -> _LegacySignalDecode:
    if len(channel) != 64:
        raise Error("legacy L-SIG equalizer requires 64 channel bins")
    var received = ofdm_demodulate(samples, 64, 16)
    var equalized = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    for i in range(64):
        var estimate = Complex64(channel[i].re, channel[i].im)
        if estimate.re != 0.0 or estimate.im != 0.0:
            equalized[i] = complex_divide(received[i], estimate)

    var pilot_indices: List[Int] = [-21, -7, 7, 21]
    var received_pilots = List[Complex64](capacity=4)
    for subcarrier in pilot_indices:
        received_pilots.append(equalized[_wifi_bin(subcarrier, 64)])
    var polarity = wifi_pilot_polarity(0)
    var known_pilots: List[Complex64] = [
        Complex64(polarity),
        Complex64(polarity),
        Complex64(polarity),
        Complex64(-polarity),
    ]
    var phase = wifi_estimate_pilot_phase(
        Span(received_pilots), Span(known_pilots), Span(pilot_indices)
    )
    var data_indices = wifi_data_subcarriers()
    var data = List[Complex64](capacity=48)
    for subcarrier in data_indices:
        data.append(equalized[_wifi_bin(subcarrier, 64)])
    var corrected = wifi_correct_pilot_phase(
        Span(data), Span(data_indices), phase
    )
    var generators: List[Int] = [0o133, 0o171]
    var deinterleaved: List[UInt8]
    var decoded: List[UInt8]
    if per_tone_llr_reliability:
        var llrs = qam_demapper_llr_piecewise(
            Span(corrected), 1, llr_noise_variance
        )
        for tone in range(len(data_indices)):
            var estimate = channel[_wifi_bin(data_indices[tone], 64)]
            llrs[tone] *= estimate.magnitude_squared()
        var deinterleaved_llrs = List[Float64](length=48, fill=0.0)
        deinterleaved = List[UInt8](length=48, fill=UInt8(0))
        for k in range(48):
            var first = 3 * (k % 16) + k // 16
            var second = first + (first + 48 - (16 * first) // 48) % 1
            deinterleaved_llrs[k] = llrs[second]
            deinterleaved[k] = (
                UInt8(0) if deinterleaved_llrs[k] >= 0.0 else UInt8(1)
            )
        decoded = viterbi_decode_soft(
            Span(deinterleaved_llrs), Span(generators), 7, terminate=False
        )
    else:
        var hard_bits = qam_demap_hard(Span(corrected), 1)
        deinterleaved = wifi_deinterleave(Span(hard_bits), 1)
        decoded = viterbi_decode_hard(
            Span(deinterleaved), Span(generators), 7, terminate=False
        )
    var parsed: LegacySignal = wifi_parse_legacy_signal(Span(decoded))
    var reserved_ok = decoded[4] == 0
    var tail_ok = True
    for i in range(18, 24):
        if decoded[i] != 0:
            tail_ok = False
    var rate_ok = (
        parsed.rate_bits[0] == 1
        and parsed.rate_bits[1] == 1
        and parsed.rate_bits[2] == 0
        and parsed.rate_bits[3] == 1
    )
    var length_ok = parsed.length_octets == expected_length_octets
    if not reserved_ok:
        raise Error("legacy L-SIG reserved bit is nonzero")
    if not tail_ok:
        raise Error("legacy L-SIG tail validation failed")
    if not rate_ok:
        raise Error("legacy L-SIG RATE is not the required 6 Mb/s code")
    if not length_ok:
        raise Error("legacy L-SIG LENGTH does not match the expected PSDU")
    return _LegacySignalDecode(
        parsed.length_octets,
        reserved_ok,
        tail_ok,
        rate_ok,
        length_ok,
        equalized^,
        corrected^,
        deinterleaved^,
        decoded^,
    )


def _wifi_he_eht_acquisition_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    legacy_ltf_spectrum: Int,
    legacy_stf_waveform: Int,
    legacy_ltf_waveform: Int,
    he_eht_ltf_waveform: Int,
    packet_waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=5)
    for stage, length in [
        ("legacy-ltf-spectrum", legacy_ltf_spectrum),
        ("legacy-stf-waveform", legacy_stf_waveform),
        ("legacy-ltf-waveform", legacy_ltf_waveform),
        ("he-eht-ltf-waveform", he_eht_ltf_waveform),
        ("packet-waveform", packet_waveform),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "complex64",
            length,
            layout="iq-interleaved",
        ))
    return result^


def _checkpoint_metadata(
    testcase_id: StringSlice,
    observation_length: Int,
    payload_length: Int,
    ldpc_llr_length: Int,
    decoded_frame_length: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata]()
    for stage, length in [
        ("coarse-cfo-corrected-samples", observation_length),
        ("fine-cfo-corrected-samples", observation_length),
        ("legacy-ltf-samples", _LEGACY_LTF_SAMPLES),
        ("legacy-channel-estimate", 64),
        ("legacy-signal-samples", _LEGACY_SIGNAL_SAMPLES),
        ("legacy-signal-equalized-spectrum", 64),
        ("legacy-signal-pilot-corrected-symbols", 48),
        ("he-eht-ltf-samples", _HE_EHT_LTF_SAMPLES),
        ("he-eht-channel-estimate", _HE_EHT_LTF_FFT_SIZE),
        ("data-samples", _HE_EHT_DATA_SAMPLES),
        ("data-equalized-spectrum", _HE_EHT_LTF_FFT_SIZE),
    ]:
        result.append(
            checkpoint_metadata_1d(
                testcase_id,
                stage,
                "complex64",
                length,
                layout="iq-interleaved",
            )
        )
    for stage, length in [
        ("legacy-signal-deinterleaved-bits", 48),
        ("legacy-signal-decoded-bits", 24),
        ("decoded-data-field-bits", decoded_frame_length),
        ("payload-bits", payload_length),
    ]:
        result.append(
            checkpoint_metadata_1d(
                testcase_id,
                stage,
                "uint8",
                length,
                q_format="binary-u1",
                layout="bit-per-byte",
            )
        )
    result.append(
        checkpoint_metadata_1d(
            testcase_id,
            "ldpc-rate-recovered-llrs",
            "float64",
            ldpc_llr_length,
            layout="codeword-major",
        )
    )
    return result^


def wifi_he_eht_acquisition_tx_20mhz(
    payload: Span[UInt8, ...],
    family: Int,
    mcs_index: Int,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    symbol_index: Int = 0,
    testcase_id: StringSlice = "wifi-he-eht-acquisition-tx-20mhz",
) raises -> WifiHEEHTAcquisitionTx20MHz:
    """Build the bounded legacy + HE/EHT-LTF + RU-242 DATA waveform."""
    _validate_profile(family, mcs_index)
    if len(payload) % 8 != 0 or len(payload) // 8 > 4091:
        raise Error("payload must be octet-aligned and fit legacy L-SIG LENGTH")
    var data = wifi_ldpc_tx_20mhz(
        payload,
        family,
        mcs_index,
        scrambler_seed=scrambler_seed,
        symbol_index=symbol_index,
        testcase_id=testcase_id,
    )
    var stf = wifi_stf_waveform_20mhz()
    var legacy_ltf_spectrum = wifi_legacy_ltf_spectrum_20mhz()
    var legacy_ltf = wifi_legacy_ltf_waveform_20mhz()
    var signal = wifi_legacy_signal_tx_20mhz(
        len(payload) // 8 + 4, testcase_id=testcase_id
    )
    var signal_waveform = signal.waveform.copy()
    var he_eht_ltf = wifi_ltf_waveform_20mhz(
        family, cyclic_prefix_samples=_HE_EHT_GI_SAMPLES
    )
    var data_waveform = data.waveform.copy()
    if (
        len(stf) != _LEGACY_STF_SAMPLES
        or len(legacy_ltf) != _LEGACY_LTF_SAMPLES
        or len(signal_waveform) != _LEGACY_SIGNAL_SAMPLES
        or len(he_eht_ltf) != _HE_EHT_LTF_SAMPLES
        or len(data_waveform) != _HE_EHT_DATA_SAMPLES
    ):
        raise Error("internal acquired HE/EHT packet geometry mismatch")
    var legacy_ltf_offset = len(stf)
    var signal_offset = legacy_ltf_offset + len(legacy_ltf)
    var he_eht_ltf_offset = signal_offset + len(signal_waveform)
    var data_offset = he_eht_ltf_offset + len(he_eht_ltf)
    var packet = List[Complex64](
        capacity=data_offset + len(data_waveform)
    )
    for sample in stf:
        packet.append(sample)
    for sample in legacy_ltf:
        packet.append(sample)
    for sample in signal_waveform:
        packet.append(sample)
    for sample in he_eht_ltf:
        packet.append(sample)
    for sample in data_waveform:
        packet.append(sample)
    var checkpoint_metadata = (
        _wifi_he_eht_acquisition_tx_checkpoint_metadata(
            testcase_id,
            len(legacy_ltf_spectrum),
            len(stf),
            len(legacy_ltf),
            len(he_eht_ltf),
            len(packet),
        )
    )
    return WifiHEEHTAcquisitionTx20MHz(
        family,
        mcs_index,
        len(payload),
        scrambler_seed,
        symbol_index,
        legacy_ltf_offset,
        signal_offset,
        he_eht_ltf_offset,
        data_offset,
        legacy_ltf_spectrum^,
        stf^,
        legacy_ltf^,
        he_eht_ltf^,
        packet^,
        checkpoint_metadata^,
        signal^,
        data^,
    )


def wifi_he_eht_acquisition_rx_20mhz(
    observation: Span[Complex64, ...],
    family: Int,
    mcs_index: Int,
    payload_bit_count: Int,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    symbol_index: Int = 0,
    detection_threshold: Float64 = 0.82,
    llr_noise_variance: Float64 = 1.0e-6,
    max_iterations: Int = 20,
    ltf_search_radius: Int = 16,
    per_tone_llr_reliability: Bool = False,
    testcase_id: StringSlice = "wifi-he-eht-acquisition-rx-20mhz",
) raises -> WifiHEEHTAcquisitionRx20MHz:
    """Acquire, validate L-SIG, and decode one HE/EHT RU-242 DATA symbol."""
    _validate_profile(family, mcs_index)
    if (
        payload_bit_count < 0
        or payload_bit_count % 8 != 0
        or payload_bit_count // 8 > 4091
    ):
        raise Error("payload bit count must be octet-aligned and fit L-SIG")
    if not isfinite(detection_threshold) or not (
        detection_threshold >= 0.0 and detection_threshold <= 1.0
    ):
        raise Error("detection threshold must be finite and between zero and one")
    if not isfinite(llr_noise_variance) or llr_noise_variance <= 0.0:
        raise Error("LLR noise variance must be finite and positive")
    if max_iterations < 1:
        raise Error("LDPC iteration count must be positive")
    if ltf_search_radius < 0:
        raise Error("LTF search radius must be non-negative")
    if len(observation) == 0:
        raise Error("acquisition requires a nonempty observation")
    for i in range(len(observation)):
        var sample = observation[i]
        if not isfinite(sample.re) or not isfinite(sample.im):
            raise Error("acquisition observation must be finite")

    var packet_start = wifi_stf_detect(observation, detection_threshold)
    if packet_start < 0:
        raise Error("Wi-Fi legacy STF packet detection failed")
    var stf_metric = repetition_metric(
        observation, packet_start, 16, 16
    )
    var coarse_cfo = estimate_repetition_cfo(
        observation, packet_start, 16, 128
    )
    var coarse_corrected = apply_cfo(observation, -coarse_cfo)
    var expected_ltf_start = (
        packet_start
        + _LEGACY_STF_SAMPLES
        + _LEGACY_LTF_SAMPLES
        + _LEGACY_SIGNAL_SAMPLES
    )
    var he_eht_ltf_start = wifi_he_eht_ltf_fine_timing_20mhz(
        Span(coarse_corrected),
        family,
        expected_ltf_start,
        search_radius=ltf_search_radius,
    )
    var known_ltf = wifi_ltf_waveform_20mhz(
        family, cyclic_prefix_samples=_HE_EHT_GI_SAMPLES
    )
    var timing_correlation = normalized_correlation_at(
        Span(coarse_corrected), Span(known_ltf), he_eht_ltf_start
    )
    var ltf_metric = timing_correlation.magnitude_squared()
    var fine_cfo = wifi_he_eht_ltf_fine_cfo_20mhz(
        Span(coarse_corrected), he_eht_ltf_start
    )
    var corrected = apply_cfo(Span(coarse_corrected), -fine_cfo)
    if he_eht_ltf_start < _LEGACY_LTF_SAMPLES + _LEGACY_SIGNAL_SAMPLES:
        raise Error("HE/EHT-LTF timing precedes required legacy fields")
    var signal_start = he_eht_ltf_start - _LEGACY_SIGNAL_SAMPLES
    var legacy_ltf_start = signal_start - _LEGACY_LTF_SAMPLES
    var data_start = he_eht_ltf_start + _HE_EHT_LTF_SAMPLES
    var legacy_ltf_samples = _slice_complex(
        Span(corrected), legacy_ltf_start, _LEGACY_LTF_SAMPLES
    )
    var signal_samples = _slice_complex(
        Span(corrected), signal_start, _LEGACY_SIGNAL_SAMPLES
    )
    var he_eht_ltf_samples = _slice_complex(
        Span(corrected), he_eht_ltf_start, _HE_EHT_LTF_SAMPLES
    )
    var data_samples = _slice_complex(
        Span(corrected), data_start, _HE_EHT_DATA_SAMPLES
    )

    var legacy_channel = _legacy_ltf_channel_estimate_20mhz(
        Span(legacy_ltf_samples)
    )
    var signal = _decode_legacy_signal_20mhz(
        Span(signal_samples),
        Span(legacy_channel),
        payload_bit_count // 8 + 4,
        # The public variance is for the 256-point HE/EHT DATA FFT.  L-SIG
        # uses 64 points, hence its pre-ZF bin variance is one quarter.
        llr_noise_variance=0.25 * llr_noise_variance,
        per_tone_llr_reliability=per_tone_llr_reliability,
    )
    var signal_length_octets = signal.length_octets
    var signal_reserved_ok = signal.reserved_ok
    var signal_tail_ok = signal.tail_ok
    var signal_rate_ok = signal.rate_ok
    var signal_length_ok = signal.length_ok
    var signal_equalized = signal.equalized_spectrum.copy()
    var signal_corrected = signal.corrected_symbols.copy()
    var signal_deinterleaved = signal.deinterleaved_bits.copy()
    var signal_decoded = signal.decoded_bits.copy()
    var he_eht_channel = wifi_ltf_channel_estimate_20mhz(
        Span(he_eht_ltf_samples),
        family,
        cyclic_prefix_samples=_HE_EHT_GI_SAMPLES,
    )
    var data = wifi_ldpc_rx_20mhz(
        Span(data_samples),
        Span(he_eht_ltf_samples),
        family,
        mcs_index,
        payload_bit_count,
        llr_noise_variance,
        scrambler_seed=scrambler_seed,
        symbol_index=symbol_index,
        max_iterations=max_iterations,
        per_tone_llr_reliability=per_tone_llr_reliability,
        testcase_id=testcase_id,
    )
    var metadata = _checkpoint_metadata(
        testcase_id,
        len(observation),
        len(data.payload_bits),
        len(data.rate_recovered_llrs),
        len(data.decoded_frame_bits),
    )
    return WifiHEEHTAcquisitionRx20MHz(
        family,
        mcs_index,
        packet_start,
        stf_metric,
        coarse_cfo,
        fine_cfo,
        legacy_ltf_start,
        signal_start,
        he_eht_ltf_start,
        data_start,
        ltf_metric,
        signal_length_octets,
        signal_reserved_ok,
        True,
        signal_tail_ok,
        signal_rate_ok,
        signal_length_ok,
        True,
        coarse_corrected^,
        corrected^,
        legacy_ltf_samples^,
        signal_samples^,
        he_eht_ltf_samples^,
        data_samples^,
        legacy_channel^,
        signal_equalized^,
        signal_corrected^,
        signal_deinterleaved^,
        signal_decoded^,
        he_eht_channel^,
        metadata^,
        data^,
    )
