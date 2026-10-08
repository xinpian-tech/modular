"""Representative acquired 20 MHz HT/VHT BCC link.

This module joins the existing one-symbol PHY with the receiver stages that a
link-level example must not silently skip: a standards-derived legacy STF,
packet detection and coarse CFO, LTF correlation timing, residual CFO from
the LTF cyclic prefix, LTF channel estimation, a legacy L-SIG OFDM symbol,
pilot phase tracking, soft QAM demapping, and soft-input Viterbi decoding.  A
seeded flat Rician channel, AWGN, CFO, and integer timing offset are explicit
checkpoints rather than test-only modifications.

The boundary is deliberate: one spatial stream, one 20 MHz HT/VHT DATA OFDM
symbol, one HT/VHT-LTF, and one legacy 24-bit L-SIG encoded as the standard
6 Mb/s BPSK rate-1/2 symbol.  The representative L-SIG LENGTH is the modeled
PSDU length in octets (caller payload plus the synthesized four-octet FCS).
This is not a complete interoperable PPDU; it does not
build or decode HT-SIG/VHT-SIG, synthesize HT/VHT duration-spoofing LENGTH,
aggregate MPDUs, multiple DATA symbols, MIMO training, or front-end
sample-rate conversion.
"""

from std.collections import Span
from std.math import isfinite, sqrt
from wireless_dsp.core import Complex64
from wireless_dsp.channel.impairments import add_awgn, apply_cfo
from wireless_dsp.channel.models import (
    apply_integer_timing_offset,
    apply_rician_fading,
)
from wireless_dsp.dsp import (
    complex_divide,
    normalized_correlation_at,
    ofdm_demodulate,
    ofdm_modulate,
)
from wireless_dsp.fec import convolutional_encode, viterbi_decode_soft
from wireless_dsp.modem import qam_map, qam_demapper_llr_piecewise
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)
from wireless_dsp.synchronization import (
    repetition_metric,
    estimate_repetition_cfo,
)
from wireless_dsp.wireless.wifi.coding import (
    WifiBCCInterleaverProfile,
    wifi_bcc_depuncture_llrs,
    wifi_bcc_interleaver_profile,
)
from wireless_dsp.wireless.wifi.legacy import (
    wifi_data_subcarriers,
    wifi_interleave,
    wifi_legacy_signal_bits,
    wifi_map_legacy_symbol,
    wifi_pilot_polarity,
    wifi_scramble,
    wifi_fcs,
    wifi_stf_detect,
)
from wireless_dsp.wireless.wifi.phy_chain import (
    wifi_bcc_tx_20mhz,
    wifi_extract_ht_vht_data_20mhz,
    wifi_extract_ht_vht_pilots_20mhz,
    wifi_ht_vht_data_subcarriers_20mhz,
)
from wireless_dsp.wireless.wifi.pilots import (
    wifi_estimate_pilot_phase,
    wifi_correct_pilot_phase,
)
from wireless_dsp.wireless.wifi.preambles import (
    wifi_ltf_waveform_20mhz,
    wifi_ltf_channel_estimate_20mhz,
    wifi_data_pilot_subcarriers_20mhz,
    wifi_data_pilots_20mhz,
)
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    wifi_mcs_profile,
    wifi_ofdm_profile,
    wifi_data_bits_per_symbol,
)


comptime _WIFI_STF_SAMPLES = 160
comptime _WIFI_LTF_SAMPLES = 80
comptime _WIFI_SIGNAL_SAMPLES = 80
comptime _WIFI_DATA_SAMPLES = 80
comptime _WIFI_CFO_UNAMBIGUOUS_LIMIT = 0.03125


struct WifiAcquisitionTx20MHz(Movable):
    """Transmit waveform plus independently inspectable PHY checkpoints."""

    var family: Int
    var mcs_index: Int
    var payload_bit_count: Int
    var scrambler_seed: UInt8
    var symbol_index: Int
    var fcs: UInt64
    var ltf_offset: Int
    var signal_offset: Int
    var data_offset: Int
    var signal_rate_bits: List[UInt8]
    var signal_length_octets: Int
    var signal_bits: List[UInt8]
    var signal_coded_bits: List[UInt8]
    var signal_interleaved_bits: List[UInt8]
    var signal_symbols: List[Complex64]
    var data_field_bits: List[UInt8]
    var interleaved_bits: List[UInt8]
    var qam_symbols: List[Complex64]
    var stf_short_symbol: List[Complex64]
    var stf_waveform: List[Complex64]
    var ltf_waveform: List[Complex64]
    var signal_waveform: List[Complex64]
    var data_waveform: List[Complex64]
    var packet_waveform: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        family: Int,
        mcs_index: Int,
        payload_bit_count: Int,
        scrambler_seed: UInt8,
        symbol_index: Int,
        fcs: UInt64,
        ltf_offset: Int,
        signal_offset: Int,
        data_offset: Int,
        var signal_rate_bits: List[UInt8],
        signal_length_octets: Int,
        var signal_bits: List[UInt8],
        var signal_coded_bits: List[UInt8],
        var signal_interleaved_bits: List[UInt8],
        var signal_symbols: List[Complex64],
        var data_field_bits: List[UInt8],
        var interleaved_bits: List[UInt8],
        var qam_symbols: List[Complex64],
        var stf_short_symbol: List[Complex64],
        var stf_waveform: List[Complex64],
        var ltf_waveform: List[Complex64],
        var signal_waveform: List[Complex64],
        var data_waveform: List[Complex64],
        var packet_waveform: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.family = family
        self.mcs_index = mcs_index
        self.payload_bit_count = payload_bit_count
        self.scrambler_seed = scrambler_seed
        self.symbol_index = symbol_index
        self.fcs = fcs
        self.ltf_offset = ltf_offset
        self.signal_offset = signal_offset
        self.data_offset = data_offset
        self.signal_rate_bits = signal_rate_bits^
        self.signal_length_octets = signal_length_octets
        self.signal_bits = signal_bits^
        self.signal_coded_bits = signal_coded_bits^
        self.signal_interleaved_bits = signal_interleaved_bits^
        self.signal_symbols = signal_symbols^
        self.data_field_bits = data_field_bits^
        self.interleaved_bits = interleaved_bits^
        self.qam_symbols = qam_symbols^
        self.stf_short_symbol = stf_short_symbol^
        self.stf_waveform = stf_waveform^
        self.ltf_waveform = ltf_waveform^
        self.signal_waveform = signal_waveform^
        self.data_waveform = data_waveform^
        self.packet_waveform = packet_waveform^
        self.checkpoint_metadata = checkpoint_metadata^


struct WifiAcquisitionChannelConfig(Movable, Copyable):
    """Explicit acquisition-channel controls, all in complex-sample units."""

    var timing_offset: Int
    var normalized_cfo: Float64
    var noise_variance: Float64
    var rician_k_factor: Float64
    var seed: UInt64

    def __init__(
        out self,
        *,
        timing_offset: Int = 8,
        normalized_cfo: Float64 = 0.002,
        noise_variance: Float64 = 1.0e-8,
        rician_k_factor: Float64 = 20.0,
        seed: UInt64 = UInt64(0x80211),
    ):
        self.timing_offset = timing_offset
        self.normalized_cfo = normalized_cfo
        self.noise_variance = noise_variance
        self.rician_k_factor = rician_k_factor
        self.seed = seed


struct WifiAcquisitionChannel20MHz(Movable):
    """Seeded channel output and the ground-truth controls used to create it."""

    var timing_offset: Int
    var normalized_cfo: Float64
    var noise_variance: Float64
    var rician_k_factor: Float64
    var seed: UInt64
    var faded_waveform: List[Complex64]
    var observation: List[Complex64]

    def __init__(
        out self,
        timing_offset: Int,
        normalized_cfo: Float64,
        noise_variance: Float64,
        rician_k_factor: Float64,
        seed: UInt64,
        var faded_waveform: List[Complex64],
        var observation: List[Complex64],
    ):
        self.timing_offset = timing_offset
        self.normalized_cfo = normalized_cfo
        self.noise_variance = noise_variance
        self.rician_k_factor = rician_k_factor
        self.seed = seed
        self.faded_waveform = faded_waveform^
        self.observation = observation^


struct WifiAcquisitionRx20MHz(Movable):
    """Acquisition, L-SIG, equalization, FEC, SERVICE, and FCS checkpoints.

    ``signal_decoded_fields`` has the stable audit layout
    ``[RATE-nibble, reserved, LENGTH-octets, parity-ok, tail-ok, rate-ok,
    length-ok]``.  RATE-nibble packs the four transmitted RATE bits MSB-first.
    """

    var packet_start: Int
    var stf_metric: Float64
    var coarse_cfo: Float64
    var fine_cfo: Float64
    var ltf_start: Int
    var signal_start: Int
    var data_start: Int
    var signal_common_phase: Float64
    var signal_phase_slope: Float64
    var common_phase: Float64
    var phase_slope: Float64
    var signal_length_octets: Int
    var received_fcs: UInt64
    var computed_fcs: UInt64
    var signal_reserved_ok: Bool
    var signal_parity_ok: Bool
    var signal_tail_ok: Bool
    var signal_rate_ok: Bool
    var signal_length_ok: Bool
    var signal_ok: Bool
    var service_ok: Bool
    var fcs_ok: Bool
    var cfo_corrected_samples: List[Complex64]
    var ltf_samples: List[Complex64]
    var signal_samples: List[Complex64]
    var data_samples: List[Complex64]
    var channel_estimate: List[Complex64]
    var signal_equalized_spectrum: List[Complex64]
    var signal_corrected_symbols: List[Complex64]
    var signal_llrs: List[Float64]
    var signal_deinterleaved_llrs: List[Float64]
    var signal_decoded_bits: List[UInt8]
    var signal_rate_bits: List[UInt8]
    var signal_decoded_fields: List[Int]
    var equalized_spectrum: List[Complex64]
    var corrected_data_symbols: List[Complex64]
    var qam_llrs: List[Float64]
    var deinterleaved_llrs: List[Float64]
    var mother_llrs: List[Float64]
    var decoded_bits: List[UInt8]
    var payload_bits: List[UInt8]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        packet_start: Int,
        stf_metric: Float64,
        coarse_cfo: Float64,
        fine_cfo: Float64,
        ltf_start: Int,
        signal_start: Int,
        data_start: Int,
        signal_common_phase: Float64,
        signal_phase_slope: Float64,
        common_phase: Float64,
        phase_slope: Float64,
        signal_length_octets: Int,
        received_fcs: UInt64,
        computed_fcs: UInt64,
        signal_reserved_ok: Bool,
        signal_parity_ok: Bool,
        signal_tail_ok: Bool,
        signal_rate_ok: Bool,
        signal_length_ok: Bool,
        signal_ok: Bool,
        service_ok: Bool,
        fcs_ok: Bool,
        var cfo_corrected_samples: List[Complex64],
        var ltf_samples: List[Complex64],
        var signal_samples: List[Complex64],
        var data_samples: List[Complex64],
        var channel_estimate: List[Complex64],
        var signal_equalized_spectrum: List[Complex64],
        var signal_corrected_symbols: List[Complex64],
        var signal_llrs: List[Float64],
        var signal_deinterleaved_llrs: List[Float64],
        var signal_decoded_bits: List[UInt8],
        var signal_rate_bits: List[UInt8],
        var signal_decoded_fields: List[Int],
        var equalized_spectrum: List[Complex64],
        var corrected_data_symbols: List[Complex64],
        var qam_llrs: List[Float64],
        var deinterleaved_llrs: List[Float64],
        var mother_llrs: List[Float64],
        var decoded_bits: List[UInt8],
        var payload_bits: List[UInt8],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.packet_start = packet_start
        self.stf_metric = stf_metric
        self.coarse_cfo = coarse_cfo
        self.fine_cfo = fine_cfo
        self.ltf_start = ltf_start
        self.signal_start = signal_start
        self.data_start = data_start
        self.signal_common_phase = signal_common_phase
        self.signal_phase_slope = signal_phase_slope
        self.common_phase = common_phase
        self.phase_slope = phase_slope
        self.signal_length_octets = signal_length_octets
        self.received_fcs = received_fcs
        self.computed_fcs = computed_fcs
        self.signal_reserved_ok = signal_reserved_ok
        self.signal_parity_ok = signal_parity_ok
        self.signal_tail_ok = signal_tail_ok
        self.signal_rate_ok = signal_rate_ok
        self.signal_length_ok = signal_length_ok
        self.signal_ok = signal_ok
        self.service_ok = service_ok
        self.fcs_ok = fcs_ok
        self.cfo_corrected_samples = cfo_corrected_samples^
        self.ltf_samples = ltf_samples^
        self.signal_samples = signal_samples^
        self.data_samples = data_samples^
        self.channel_estimate = channel_estimate^
        self.signal_equalized_spectrum = signal_equalized_spectrum^
        self.signal_corrected_symbols = signal_corrected_symbols^
        self.signal_llrs = signal_llrs^
        self.signal_deinterleaved_llrs = signal_deinterleaved_llrs^
        self.signal_decoded_bits = signal_decoded_bits^
        self.signal_rate_bits = signal_rate_bits^
        self.signal_decoded_fields = signal_decoded_fields^
        self.equalized_spectrum = equalized_spectrum^
        self.corrected_data_symbols = corrected_data_symbols^
        self.qam_llrs = qam_llrs^
        self.deinterleaved_llrs = deinterleaved_llrs^
        self.mother_llrs = mother_llrs^
        self.decoded_bits = decoded_bits^
        self.payload_bits = payload_bits^
        self.checkpoint_metadata = checkpoint_metadata^


def _wifi_acquisition_rx_checkpoint_metadata(
    testcase_id: StringSlice,
    cfo_corrected_samples: Int,
    ltf_samples: Int,
    signal_samples: Int,
    data_samples: Int,
    channel_estimate: Int,
    signal_equalized_spectrum: Int,
    signal_corrected_symbols: Int,
    signal_llrs: Int,
    signal_deinterleaved_llrs: Int,
    signal_decoded_bits: Int,
    signal_rate_bits: Int,
    signal_decoded_fields: Int,
    equalized_spectrum: Int,
    corrected_data_symbols: Int,
    qam_llrs: Int,
    deinterleaved_llrs: Int,
    mother_llrs: Int,
    decoded_bits: Int,
    payload_bits: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=19)
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "cfo-corrected-samples",
        "complex64",
        cfo_corrected_samples,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "ltf-samples",
        "complex64",
        ltf_samples,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "legacy-signal-samples",
        "complex64",
        signal_samples,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "data-samples",
        "complex64",
        data_samples,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "channel-estimate",
        "complex64",
        channel_estimate,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "legacy-signal-equalized-spectrum",
        "complex64",
        signal_equalized_spectrum,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "legacy-signal-pilot-corrected-symbols",
        "complex64",
        signal_corrected_symbols,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "legacy-signal-llrs",
        "float64",
        signal_llrs,
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "legacy-signal-deinterleaved-llrs",
        "float64",
        signal_deinterleaved_llrs,
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "legacy-signal-decoded-bits",
        "uint8",
        signal_decoded_bits,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "legacy-signal-rate-bits",
        "uint8",
        signal_rate_bits,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "legacy-signal-decoded-fields",
        "int64",
        signal_decoded_fields,
        layout="rate-reserved-length-validity",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "data-equalized-spectrum",
        "complex64",
        equalized_spectrum,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "data-pilot-corrected-symbols",
        "complex64",
        corrected_data_symbols,
        layout="iq-interleaved",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "qam-llrs", "float64", qam_llrs
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "deinterleaved-llrs",
        "float64",
        deinterleaved_llrs,
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id, "depunctured-mother-llrs", "float64", mother_llrs
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "decoded-data-field-bits",
        "uint8",
        decoded_bits,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "payload-bits",
        "uint8",
        payload_bits,
        q_format="binary-u1",
        layout="bit-per-byte",
    ))
    return result^


def _wifi_bin(subcarrier: Int) -> Int:
    return subcarrier if subcarrier >= 0 else 64 + subcarrier


def wifi_stf_spectrum_20mhz() -> List[Complex64]:
    """Return the legacy STF tones in unshifted 64-bin FFT order.

    The twelve occupied tones and ``sqrt(13/6)`` scaling are the legacy STF
    sequence.  Because every occupied tone is a multiple of four, its IFFT is
    exactly 16-sample periodic.
    """
    var scale = sqrt(13.0 / 6.0)
    var positive = Complex64(scale, scale)
    var negative = Complex64(-scale, -scale)
    var result = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    result[_wifi_bin(-24)] = positive
    result[_wifi_bin(-20)] = negative
    result[_wifi_bin(-16)] = positive
    result[_wifi_bin(-12)] = negative
    result[_wifi_bin(-8)] = negative
    result[_wifi_bin(-4)] = positive
    result[_wifi_bin(4)] = negative
    result[_wifi_bin(8)] = negative
    result[_wifi_bin(12)] = positive
    result[_wifi_bin(16)] = positive
    result[_wifi_bin(20)] = positive
    result[_wifi_bin(24)] = positive
    return result^


def wifi_stf_short_symbol_20mhz() raises -> List[Complex64]:
    """Return one of the ten identical 16-sample legacy short symbols."""
    var spectrum = wifi_stf_spectrum_20mhz()
    var time = ofdm_modulate(Span(spectrum), 0)
    var result = List[Complex64](capacity=16)
    for i in range(16):
        result.append(time[i])
    return result^


def wifi_stf_waveform_20mhz() raises -> List[Complex64]:
    """Return the ten-short-symbol, 160-sample legacy STF."""
    var short = wifi_stf_short_symbol_20mhz()
    var result = List[Complex64](capacity=_WIFI_STF_SAMPLES)
    for _ in range(10):
        for i in range(16):
            result.append(short[i])
    return result^


struct WifiLegacySignalTx20MHz(Movable):
    """Standard 20 MHz legacy L-SIG BPSK symbol and coding checkpoints."""

    var rate_bits: List[UInt8]
    var length_octets: Int
    var bits: List[UInt8]
    var coded_bits: List[UInt8]
    var interleaved_bits: List[UInt8]
    var symbols: List[Complex64]
    var waveform: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        var rate_bits: List[UInt8],
        length_octets: Int,
        var bits: List[UInt8],
        var coded_bits: List[UInt8],
        var interleaved_bits: List[UInt8],
        var symbols: List[Complex64],
        var waveform: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.rate_bits = rate_bits^
        self.length_octets = length_octets
        self.bits = bits^
        self.coded_bits = coded_bits^
        self.interleaved_bits = interleaved_bits^
        self.symbols = symbols^
        self.waveform = waveform^
        self.checkpoint_metadata = checkpoint_metadata^


def _wifi_legacy_signal_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    rate_bits: Int,
    bits: Int,
    coded_bits: Int,
    interleaved_bits: Int,
    symbols: Int,
    waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=6)
    for stage, length in [
        ("rate-bits", rate_bits),
        ("bits", bits),
        ("coded-bits", coded_bits),
        ("interleaved-bits", interleaved_bits),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "uint8",
            length,
            q_format="binary-u1",
            layout="bit-per-byte",
        ))
    for stage, length in [
        ("symbols", symbols),
        ("waveform", waveform),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "complex64",
            length,
            layout="iq-interleaved",
        ))
    return result^


def _wifi_acquisition_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    signal_rate_bits: Int,
    signal_bits: Int,
    signal_coded_bits: Int,
    signal_interleaved_bits: Int,
    signal_symbols: Int,
    data_field_bits: Int,
    interleaved_bits: Int,
    qam_symbols: Int,
    stf_short_symbol: Int,
    stf_waveform: Int,
    ltf_waveform: Int,
    signal_waveform: Int,
    data_waveform: Int,
    packet_waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=14)
    for stage, length in [
        ("signal-rate-bits", signal_rate_bits),
        ("signal-bits", signal_bits),
        ("signal-coded-bits", signal_coded_bits),
        ("signal-interleaved-bits", signal_interleaved_bits),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "uint8",
            length,
            q_format="binary-u1",
            layout="bit-per-byte",
        ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "signal-symbols",
        "complex64",
        signal_symbols,
        layout="iq-interleaved",
    ))
    for stage, length in [
        ("data-field-bits", data_field_bits),
        ("interleaved-bits", interleaved_bits),
    ]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "uint8",
            length,
            q_format="binary-u1",
            layout="bit-per-byte",
        ))
    for stage, length in [
        ("qam-symbols", qam_symbols),
        ("stf-short-symbol", stf_short_symbol),
        ("stf-waveform", stf_waveform),
        ("ltf-waveform", ltf_waveform),
        ("signal-waveform", signal_waveform),
        ("data-waveform", data_waveform),
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


def wifi_legacy_signal_tx_20mhz(
    length_octets: Int,
    *,
    testcase_id: StringSlice = "wifi-legacy-signal-tx-20mhz",
) raises -> WifiLegacySignalTx20MHz:
    """Build one IEEE 802.11 legacy SIGNAL symbol at 6 Mb/s.

    The 24 uncoded bits are RATE=``[1,1,0,1]`` in transmission order,
    reserved=0, the 12-bit LSB-first LENGTH, even parity, and six zero tail
    bits.  The complete field is encoded by the K=7 133/171 rate-1/2 BCC,
    legacy 48-tone BPSK interleaver, standard pilot row, 64-point IFFT, and
    16-sample cyclic prefix.
    """
    if length_octets < 0 or length_octets > 4095:
        raise Error("legacy SIGNAL LENGTH must be between zero and 4095")
    var rate_bits: List[UInt8] = [1, 1, 0, 1]
    var bits = wifi_legacy_signal_bits(Span(rate_bits), length_octets)
    var generators: List[Int] = [0o133, 0o171]
    # L-SIG already carries its six explicit zero tail bits.
    var coded = convolutional_encode(
        Span(bits), Span(generators), 7, terminate=False
    )
    if len(coded) != 48:
        raise Error("internal legacy SIGNAL BCC length mismatch")
    var interleaved = wifi_interleave(Span(coded), 1)
    var symbols = qam_map(Span(interleaved), 1)
    var waveform = wifi_map_legacy_symbol(Span(symbols), symbol_index=0)
    var checkpoint_metadata = _wifi_legacy_signal_tx_checkpoint_metadata(
        testcase_id,
        len(rate_bits),
        len(bits),
        len(coded),
        len(interleaved),
        len(symbols),
        len(waveform),
    )
    return WifiLegacySignalTx20MHz(
        rate_bits^,
        length_octets,
        bits^,
        coded^,
        interleaved^,
        symbols^,
        waveform^,
        checkpoint_metadata^,
    )


def wifi_acquisition_tx_20mhz(
    payload: Span[UInt8, ...],
    family: Int,
    mcs_index: Int,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    symbol_index: Int = 0,
    testcase_id: StringSlice = "wifi-acquisition-tx-20mhz",
) raises -> WifiAcquisitionTx20MHz:
    """Create STF + LTF + legacy L-SIG + one BCC DATA symbol."""
    if family != WIFI_PHY_HT and family != WIFI_PHY_VHT:
        raise Error("acquisition chain supports HT or VHT BCC")
    var phy = wifi_bcc_tx_20mhz(
        payload,
        family,
        mcs_index,
        scrambler_seed=scrambler_seed,
        symbol_index=symbol_index,
        testcase_id=testcase_id,
    )
    var data_field_bits = phy.data_field_bits.copy()
    var interleaved_bits = phy.interleaved_bits.copy()
    var qam_symbols = phy.qam_symbols.copy()
    var data = phy.waveform.copy()
    var fcs = phy.fcs
    var short = wifi_stf_short_symbol_20mhz()
    var stf = wifi_stf_waveform_20mhz()
    var ltf = wifi_ltf_waveform_20mhz(family)
    var signal_length_octets = (len(payload) + 32) // 8
    var signal = wifi_legacy_signal_tx_20mhz(
        signal_length_octets, testcase_id=testcase_id
    )
    var signal_rate_bits = signal.rate_bits.copy()
    var signal_bits = signal.bits.copy()
    var signal_coded_bits = signal.coded_bits.copy()
    var signal_interleaved_bits = signal.interleaved_bits.copy()
    var signal_symbols = signal.symbols.copy()
    var signal_waveform = signal.waveform.copy()
    var packet = List[Complex64](
        capacity=len(stf) + len(ltf) + len(signal_waveform) + len(data)
    )
    for sample in stf:
        packet.append(sample)
    for sample in ltf:
        packet.append(sample)
    for sample in signal_waveform:
        packet.append(sample)
    for sample in data:
        packet.append(sample)
    var checkpoint_metadata = _wifi_acquisition_tx_checkpoint_metadata(
        testcase_id,
        len(signal_rate_bits),
        len(signal_bits),
        len(signal_coded_bits),
        len(signal_interleaved_bits),
        len(signal_symbols),
        len(data_field_bits),
        len(interleaved_bits),
        len(qam_symbols),
        len(short),
        len(stf),
        len(ltf),
        len(signal_waveform),
        len(data),
        len(packet),
    )
    return WifiAcquisitionTx20MHz(
        family,
        mcs_index,
        len(payload),
        scrambler_seed,
        symbol_index,
        fcs,
        len(stf),
        len(stf) + len(ltf),
        len(stf) + len(ltf) + len(signal_waveform),
        signal_rate_bits^,
        signal_length_octets,
        signal_bits^,
        signal_coded_bits^,
        signal_interleaved_bits^,
        signal_symbols^,
        data_field_bits^,
        interleaved_bits^,
        qam_symbols^,
        short^,
        stf^,
        ltf^,
        signal_waveform^,
        data^,
        packet^,
        checkpoint_metadata^,
    )


def _validate_channel_config(config: WifiAcquisitionChannelConfig) raises:
    if config.timing_offset < 0 or config.timing_offset > 64:
        raise Error("acquisition timing offset must be between zero and 64")
    if (
        not isfinite(config.normalized_cfo)
        or config.normalized_cfo <= -_WIFI_CFO_UNAMBIGUOUS_LIMIT
        or config.normalized_cfo >= _WIFI_CFO_UNAMBIGUOUS_LIMIT
    ):
        raise Error("CFO lies outside the 16-sample STF unambiguous range")
    if not isfinite(config.noise_variance) or config.noise_variance < 0.0:
        raise Error("noise variance must be finite and non-negative")
    if not isfinite(config.rician_k_factor) or config.rician_k_factor < 0.0:
        raise Error("Rician K factor must be finite and non-negative")


def wifi_acquisition_apply_channel_20mhz(
    samples: Span[Complex64, ...], config: WifiAcquisitionChannelConfig
) raises -> WifiAcquisitionChannel20MHz:
    """Apply seeded flat Rician fading, delay, CFO, and seeded AWGN."""
    _validate_channel_config(config)
    if len(samples) == 0:
        raise Error("acquisition channel requires a nonempty waveform")
    var faded = apply_rician_fading(
        samples,
        config.rician_k_factor,
        seed=config.seed,
        block_fading=True,
    )
    # Extend before the fixed-length timing primitive so a positive delay does
    # not truncate the final DATA samples.
    var extended = faded.copy()
    for _ in range(config.timing_offset):
        extended.append(Complex64(0.0, 0.0))
    var delayed = apply_integer_timing_offset(
        Span(extended), config.timing_offset
    )
    var shifted = apply_cfo(Span(delayed), config.normalized_cfo)
    var observation = add_awgn(
        Span(shifted),
        config.noise_variance,
        seed=config.seed ^ UInt64(0xD1B54A32D192ED03),
    )
    return WifiAcquisitionChannel20MHz(
        config.timing_offset,
        config.normalized_cfo,
        config.noise_variance,
        config.rician_k_factor,
        config.seed,
        faded^,
        observation^,
    )


def _normalized_correlation(
    samples: Span[Complex64, ...],
    offset: Int,
    known: Span[Complex64, ...],
) raises -> Float64:
    var correlation = normalized_correlation_at(samples, known, offset)
    return min(1.0, correlation.magnitude_squared())


def wifi_ltf_fine_timing_20mhz(
    samples: Span[Complex64, ...],
    family: Int,
    expected_start: Int,
    *,
    search_radius: Int = 12,
) raises -> Int:
    """Correlate the known HT/VHT-LTF around the STF-derived boundary."""
    if family != WIFI_PHY_HT and family != WIFI_PHY_VHT:
        raise Error("acquisition LTF timing supports HT or VHT")
    if search_radius < 0 or expected_start < 0:
        raise Error("invalid LTF timing-search window")
    for index in range(len(samples)):
        if not isfinite(samples[index].re) or not isfinite(samples[index].im):
            raise Error("LTF timing observation must be finite")
    var known = wifi_ltf_waveform_20mhz(family)
    if len(samples) < len(known):
        raise Error("LTF timing observation is shorter than the reference")
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
        raise Error("LTF timing-search window lies outside the observation")
    var best_offset = first
    var best_metric = -1.0
    for offset in range(first, last + 1):
        var metric = _normalized_correlation(samples, offset, Span(known))
        if metric > best_metric:
            best_metric = metric
            best_offset = offset
    return best_offset


def wifi_ltf_fine_cfo_20mhz(
    samples: Span[Complex64, ...], ltf_start: Int
) raises -> Float64:
    """Estimate residual CFO from the 16-sample LTF cyclic prefix.

    The LTF cyclic prefix repeats the final 16 samples of the 64-sample
    training symbol.  Their 64-sample phase separation gives a residual-CFO
    range of +/-1/128 cycles/sample after the wider-range STF estimate.
    """
    return estimate_repetition_cfo(samples, ltf_start, 64, 16)


def _slice_complex(
    samples: Span[Complex64, ...], offset: Int, count: Int
) raises -> List[Complex64]:
    if (
        offset < 0
        or count < 0
        or offset > len(samples)
        or count > len(samples) - offset
    ):
        raise Error("complex sample slice lies outside observation")
    var result = List[Complex64](capacity=count)
    for i in range(count):
        result.append(samples[offset + i])
    return result^


def _bcc_deinterleave_llrs(
    llrs: Span[Float64, ...],
    bits_per_subcarrier: Int,
    profile: WifiBCCInterleaverProfile,
) raises -> List[Float64]:
    """Float-valued inverse of the public bit-domain BCC interleaver."""
    var coded_bits = profile.block_data_subcarriers * bits_per_subcarrier
    var rows = profile.rows_per_modulation_bit * bits_per_subcarrier
    if (
        bits_per_subcarrier < 1
        or len(llrs) != coded_bits
        or rows * profile.columns != coded_bits
    ):
        raise Error("BCC LLR input must contain one complete interleaver block")
    var s = max(bits_per_subcarrier // 2, 1)
    # The representative link is one spatial stream, so the stream rotation is
    # zero while the first two standard permutations remain explicit.
    var result = List[Float64](length=coded_bits, fill=0.0)
    for k in range(coded_bits):
        var first = rows * (k % profile.columns) + k // profile.columns
        var second = (
            s * (first // s)
            + (first + coded_bits - (profile.columns * first) // coded_bits) % s
        )
        result[k] = llrs[second]
    return result^


def _legacy_signal_deinterleave_llrs(
    llrs: Span[Float64, ...],
) raises -> List[Float64]:
    """Invert the standard 48-bit legacy BPSK interleaver on soft values."""
    if len(llrs) != 48:
        raise Error("legacy SIGNAL requires exactly 48 BPSK LLRs")
    var result = List[Float64](length=48, fill=0.0)
    for k in range(48):
        # N_CBPS=48 and s=1 reduce the two standard permutations to this
        # explicit address.  Preserve the general expression for auditability.
        var first = 3 * (k % 16) + k // 16
        var second = first + (first + 48 - (16 * first) // 48) % 1
        result[k] = llrs[second]
    return result^


struct _WifiLegacySignalDecoded(Movable):
    var rate_bits: List[UInt8]
    var length_octets: Int
    var reserved_ok: Bool
    var parity_ok: Bool
    var tail_ok: Bool
    var rate_ok: Bool
    var length_ok: Bool
    var decoded_fields: List[Int]

    def __init__(
        out self,
        var rate_bits: List[UInt8],
        length_octets: Int,
        reserved_ok: Bool,
        parity_ok: Bool,
        tail_ok: Bool,
        rate_ok: Bool,
        length_ok: Bool,
        var decoded_fields: List[Int],
    ):
        self.rate_bits = rate_bits^
        self.length_octets = length_octets
        self.reserved_ok = reserved_ok
        self.parity_ok = parity_ok
        self.tail_ok = tail_ok
        self.rate_ok = rate_ok
        self.length_ok = length_ok
        self.decoded_fields = decoded_fields^


def _validate_legacy_signal_decoded(
    bits: Span[UInt8, ...], expected_length_octets: Int
) raises -> _WifiLegacySignalDecoded:
    if len(bits) != 24:
        raise Error("legacy SIGNAL decoder must produce exactly 24 bits")
    for i in range(len(bits)):
        if bits[i] > 1:
            raise Error("legacy SIGNAL decoder produced a non-binary bit")

    var rate_bits = List[UInt8](capacity=4)
    var rate_code = 0
    for i in range(4):
        rate_bits.append(bits[i])
        rate_code = (rate_code << 1) | Int(bits[i])
    var rate_ok = (
        bits[0] == 1
        and bits[1] == 1
        and bits[2] == 0
        and bits[3] == 1
    )
    var reserved_ok = bits[4] == 0
    var length_octets = 0
    for i in range(12):
        length_octets |= Int(bits[5 + i]) << i
    var parity = UInt8(0)
    for i in range(18):
        parity ^= bits[i]
    var parity_ok = parity == 0
    var tail_ok = True
    for i in range(18, 24):
        if bits[i] != 0:
            tail_ok = False
    var length_ok = length_octets == expected_length_octets
    var fields: List[Int] = [
        rate_code,
        Int(bits[4]),
        length_octets,
        Int(parity_ok),
        Int(tail_ok),
        Int(rate_ok),
        Int(length_ok),
    ]

    # Validate L-SIG before any DATA demapping.  Separate errors make an
    # integration failure attributable to the corresponding decoded field.
    if not parity_ok:
        raise Error("legacy SIGNAL even-parity validation failed")
    if not tail_ok:
        raise Error("legacy SIGNAL tail validation failed")
    if not rate_ok:
        raise Error("legacy SIGNAL RATE is not the required 6 Mb/s code")
    if not reserved_ok:
        raise Error("legacy SIGNAL reserved bit is nonzero")
    if not length_ok:
        raise Error("legacy SIGNAL LENGTH does not match the expected PSDU")
    return _WifiLegacySignalDecoded(
        rate_bits^,
        length_octets,
        reserved_ok,
        parity_ok,
        tail_ok,
        rate_ok,
        length_ok,
        fields^,
    )


def _read_fcs(bits: Span[UInt8, ...], offset: Int) raises -> UInt64:
    if offset < 0 or offset > len(bits) or 32 > len(bits) - offset:
        raise Error("FCS lies outside decoded DATA bits")
    var result = UInt64(0)
    for i in range(32):
        result |= UInt64(bits[offset + i]) << UInt64(i)
    return result


def _service_is_zero(bits: Span[UInt8, ...]) -> Bool:
    if len(bits) < 16:
        return False
    for i in range(16):
        if bits[i] != 0:
            return False
    return True


def _equalize_ofdm_symbol_20mhz(
    samples: Span[Complex64, ...], channel: Span[Complex64, ...]
) raises -> List[Complex64]:
    if len(channel) != 64:
        raise Error("20 MHz OFDM equalizer requires 64 channel bins")
    var received = ofdm_demodulate(samples, 64, 16)
    var equalized = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    for i in range(64):
        var h = Complex64(channel[i].re, channel[i].im)
        if h.re != 0.0 or h.im != 0.0:
            equalized[i] = complex_divide(received[i], h)
    return equalized^


def wifi_acquisition_rx_20mhz(
    observation: Span[Complex64, ...],
    family: Int,
    mcs_index: Int,
    payload_bit_count: Int,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    symbol_index: Int = 0,
    detection_threshold: Float64 = 0.82,
    llr_noise_variance: Float64 = 1.0e-6,
    per_tone_llr_reliability: Bool = False,
    testcase_id: StringSlice = "wifi-acquisition-rx-20mhz",
) raises -> WifiAcquisitionRx20MHz:
    """Acquire and decode one representative 20 MHz HT/VHT BCC packet.

    ``llr_noise_variance`` is the pre-ZF frequency-bin complex variance.  If
    ``per_tone_llr_reliability`` is true, post-ZF LLRs are weighted by the
    estimated ``|H[k]|^2`` for their own subcarrier.  This implements the
    exact per-tone reliability change caused by zero-forcing over a
    frequency-selective channel.  The default preserves the earlier scalar
    behavior.
    """
    if family != WIFI_PHY_HT and family != WIFI_PHY_VHT:
        raise Error("acquisition chain supports HT or VHT BCC")
    if payload_bit_count < 0 or payload_bit_count % 8 != 0:
        raise Error("invalid Wi-Fi payload length")
    if not isfinite(detection_threshold) or not (
        detection_threshold >= 0.0 and detection_threshold <= 1.0
    ):
        raise Error("detection threshold must be finite and between zero and one")
    if not isfinite(llr_noise_variance) or llr_noise_variance <= 0.0:
        raise Error("LLR noise variance must be finite and positive")
    var mcs = wifi_mcs_profile(family, mcs_index)
    if mcs.spatial_streams != 1 or mcs.bits_per_subcarrier < 6:
        raise Error("acquisition chain requires one-stream 64/256-QAM BCC")
    var ofdm = wifi_ofdm_profile(family, 20)
    var ndbps = wifi_data_bits_per_symbol(ofdm, mcs)
    if 16 + payload_bit_count + 32 + 6 > ndbps:
        raise Error("PSDU does not fit one HT/VHT DATA symbol")

    var packet_start = wifi_stf_detect(observation, detection_threshold)
    if packet_start < 0:
        raise Error("Wi-Fi STF packet detection failed")
    var stf_metric = repetition_metric(
        observation, packet_start, 16, 16
    )
    # Average eight adjacent repetitions instead of discarding the available
    # STF energy after detection.  The result is still the 16-sample coarse-CFO
    # estimator and has the same +/-1/(2*16) acquisition range.
    var coarse_cfo = estimate_repetition_cfo(
        observation, packet_start, 16, 128
    )
    var coarse_corrected = apply_cfo(observation, -coarse_cfo)
    var ltf_start = wifi_ltf_fine_timing_20mhz(
        Span(coarse_corrected),
        family,
        packet_start + _WIFI_STF_SAMPLES,
    )
    var fine_cfo = wifi_ltf_fine_cfo_20mhz(
        Span(coarse_corrected), ltf_start
    )
    var corrected_observation = apply_cfo(Span(coarse_corrected), -fine_cfo)
    var signal_start = ltf_start + _WIFI_LTF_SAMPLES
    var data_start = signal_start + _WIFI_SIGNAL_SAMPLES
    var ltf_samples = _slice_complex(
        Span(corrected_observation), ltf_start, _WIFI_LTF_SAMPLES
    )
    var signal_samples = _slice_complex(
        Span(corrected_observation), signal_start, _WIFI_SIGNAL_SAMPLES
    )
    var data_samples = _slice_complex(
        Span(corrected_observation), data_start, _WIFI_DATA_SAMPLES
    )
    var channel = wifi_ltf_channel_estimate_20mhz(
        Span(ltf_samples), family
    )

    # Decode and validate the complete legacy SIGNAL symbol before touching
    # DATA.  The same per-tone LTF estimate applies because the channel is
    # constant over this short packet (it need not be frequency-flat).
    var signal_equalized = _equalize_ofdm_symbol_20mhz(
        Span(signal_samples), Span(channel)
    )
    var signal_pilot_indices: List[Int] = [-21, -7, 7, 21]
    var signal_received_pilots = List[Complex64](capacity=4)
    for subcarrier in signal_pilot_indices:
        signal_received_pilots.append(
            signal_equalized[_wifi_bin(subcarrier)]
        )
    var signal_polarity = wifi_pilot_polarity(0)
    var signal_known_pilots: List[Complex64] = [
        Complex64(signal_polarity),
        Complex64(signal_polarity),
        Complex64(signal_polarity),
        Complex64(-signal_polarity),
    ]
    var signal_phase = wifi_estimate_pilot_phase(
        Span(signal_received_pilots),
        Span(signal_known_pilots),
        Span(signal_pilot_indices),
    )
    var legacy_data_indices = wifi_data_subcarriers()
    var signal_equalized_data = List[Complex64](capacity=48)
    for subcarrier in legacy_data_indices:
        signal_equalized_data.append(signal_equalized[_wifi_bin(subcarrier)])
    var signal_corrected = wifi_correct_pilot_phase(
        Span(signal_equalized_data), Span(legacy_data_indices), signal_phase
    )
    var signal_llrs = qam_demapper_llr_piecewise(
        Span(signal_corrected), 1, llr_noise_variance
    )
    if per_tone_llr_reliability:
        for tone in range(len(legacy_data_indices)):
            var h = channel[_wifi_bin(legacy_data_indices[tone])]
            signal_llrs[tone] *= h.magnitude_squared()
    var signal_deinterleaved = _legacy_signal_deinterleave_llrs(
        Span(signal_llrs)
    )
    var generators: List[Int] = [0o133, 0o171]
    var signal_decoded = viterbi_decode_soft(
        Span(signal_deinterleaved), Span(generators), 7, terminate=False
    )
    var signal_fields = _validate_legacy_signal_decoded(
        Span(signal_decoded), (payload_bit_count + 32) // 8
    )
    var signal_rate_bits = signal_fields.rate_bits.copy()
    var signal_decoded_fields = signal_fields.decoded_fields.copy()
    var signal_length_octets = signal_fields.length_octets
    var signal_reserved_ok = signal_fields.reserved_ok
    var signal_parity_ok = signal_fields.parity_ok
    var signal_tail_ok = signal_fields.tail_ok
    var signal_rate_ok = signal_fields.rate_ok
    var signal_length_ok = signal_fields.length_ok
    var signal_ok = (
        signal_reserved_ok
        and signal_parity_ok
        and signal_tail_ok
        and signal_rate_ok
        and signal_length_ok
    )

    var equalized = _equalize_ofdm_symbol_20mhz(
        Span(data_samples), Span(channel)
    )

    var received_pilots = wifi_extract_ht_vht_pilots_20mhz(
        Span(equalized), family
    )
    var known_pilots = wifi_data_pilots_20mhz(family, symbol_index)
    var pilot_indices = wifi_data_pilot_subcarriers_20mhz(family)
    var phase = wifi_estimate_pilot_phase(
        Span(received_pilots), Span(known_pilots), Span(pilot_indices)
    )
    var equalized_data = wifi_extract_ht_vht_data_20mhz(
        Span(equalized), family
    )
    var data_indices = wifi_ht_vht_data_subcarriers_20mhz(family)
    var corrected_data = wifi_correct_pilot_phase(
        Span(equalized_data), Span(data_indices), phase
    )
    var qam_llrs = qam_demapper_llr_piecewise(
        Span(corrected_data), mcs.bits_per_subcarrier, llr_noise_variance
    )
    if per_tone_llr_reliability:
        for tone in range(len(data_indices)):
            var h = channel[_wifi_bin(data_indices[tone])]
            var reliability = h.magnitude_squared()
            for bit in range(mcs.bits_per_subcarrier):
                qam_llrs[tone * mcs.bits_per_subcarrier + bit] *= reliability
    var interleaver = wifi_bcc_interleaver_profile(family, 20)
    var deinterleaved = _bcc_deinterleave_llrs(
        Span(qam_llrs), mcs.bits_per_subcarrier, interleaver
    )
    var mother = wifi_bcc_depuncture_llrs(
        Span(deinterleaved),
        2 * ndbps,
        mcs.code_rate_numerator,
        mcs.code_rate_denominator,
    )
    var decoded = viterbi_decode_soft(
        Span(mother), Span(generators), 7, terminate=False
    )
    var descrambled = wifi_scramble(Span(decoded), scrambler_seed)
    var payload = List[UInt8](capacity=payload_bit_count)
    for i in range(payload_bit_count):
        payload.append(descrambled[16 + i])
    var received_fcs = _read_fcs(
        Span(descrambled), 16 + payload_bit_count
    )
    var computed_fcs = wifi_fcs(Span(payload))
    var checkpoint_metadata = _wifi_acquisition_rx_checkpoint_metadata(
        testcase_id,
        len(corrected_observation),
        len(ltf_samples),
        len(signal_samples),
        len(data_samples),
        len(channel),
        len(signal_equalized),
        len(signal_corrected),
        len(signal_llrs),
        len(signal_deinterleaved),
        len(signal_decoded),
        len(signal_rate_bits),
        len(signal_decoded_fields),
        len(equalized),
        len(corrected_data),
        len(qam_llrs),
        len(deinterleaved),
        len(mother),
        len(descrambled),
        len(payload),
    )
    return WifiAcquisitionRx20MHz(
        packet_start,
        stf_metric,
        coarse_cfo,
        fine_cfo,
        ltf_start,
        signal_start,
        data_start,
        signal_phase.common_phase,
        signal_phase.phase_slope,
        phase.common_phase,
        phase.phase_slope,
        signal_length_octets,
        received_fcs,
        computed_fcs,
        signal_reserved_ok,
        signal_parity_ok,
        signal_tail_ok,
        signal_rate_ok,
        signal_length_ok,
        signal_ok,
        _service_is_zero(Span(descrambled)),
        received_fcs == computed_fcs,
        corrected_observation^,
        ltf_samples^,
        signal_samples^,
        data_samples^,
        channel^,
        signal_equalized^,
        signal_corrected^,
        signal_llrs^,
        signal_deinterleaved^,
        signal_decoded^,
        signal_rate_bits^,
        signal_decoded_fields^,
        equalized^,
        corrected_data^,
        qam_llrs^,
        deinterleaved^,
        mother^,
        descrambled^,
        payload^,
        checkpoint_metadata^,
    )
