"""Runnable one-stream 20 MHz Wi-Fi PHY reference chains.

This module intentionally keeps the scope executable and auditable: one DATA
OFDM symbol, one spatial stream, and a flat/per-tone channel estimated from an
HT/VHT-LTF or 4x HE/EHT-LTF.  It covers HT MCS 6 and VHT MCS 8 through BCC,
and the two-codeword RU-242 plans used by HE MCS 10 and EHT MCS 13 through the
native IEEE 802.11 QC-LDPC matrices.  Every stage is returned as a checkpoint.
"""

from std.collections import Span
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import ofdm_modulate, ofdm_demodulate, complex_divide
from wireless_dsp.fec import convolutional_encode, viterbi_decode_soft
from wireless_dsp.modem import (
    qam_map,
    qam_demap_hard,
    qam_demapper_llr_piecewise,
)
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
    checkpoint_metadata_2d,
)
from .coding import (
    wifi_bcc_puncture,
    wifi_bcc_depuncture_llrs,
    wifi_bcc_interleaver_profile,
    wifi_bcc_interleave_block,
    wifi_bcc_deinterleave_block,
)
from .ldpc import (
    WifiLDPCProfile,
    wifi_ldpc_profile,
    wifi_ldpc_rate_match_block,
    wifi_ldpc_rate_recover_block,
    wifi_ldpc_decode,
)
from .legacy import wifi_scramble, wifi_fcs
from .pilots import wifi_estimate_pilot_phase, wifi_correct_pilot_phase
from .preambles import (
    wifi_ltf_channel_estimate_20mhz,
    wifi_data_pilot_subcarriers_20mhz,
    wifi_data_pilots_20mhz,
)
from .profiles import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
    wifi_mcs_profile,
    wifi_ofdm_profile,
    wifi_coded_bits_per_symbol,
    wifi_data_bits_per_symbol,
)
from .resources import (
    wifi_ru_profile,
    wifi_ru_coded_bits_per_symbol,
    wifi_ru_data_subcarriers_20mhz,
    wifi_map_ru_symbol_20mhz,
    wifi_extract_ru_data_20mhz,
    wifi_extract_ru_pilots_20mhz,
)


struct WifiBCCTx20MHz(Movable):
    var family: Int
    var mcs_index: Int
    var payload_bit_count: Int
    var data_bits_per_symbol: Int
    var coded_bits_per_symbol: Int
    var fcs: UInt64
    var data_field_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var mother_bits: List[UInt8]
    var punctured_bits: List[UInt8]
    var interleaved_bits: List[UInt8]
    var qam_symbols: List[Complex64]
    var spectrum: List[Complex64]
    var waveform: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        family: Int,
        mcs_index: Int,
        payload_bit_count: Int,
        data_bits_per_symbol: Int,
        coded_bits_per_symbol: Int,
        fcs: UInt64,
        var data_field_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var mother_bits: List[UInt8],
        var punctured_bits: List[UInt8],
        var interleaved_bits: List[UInt8],
        var qam_symbols: List[Complex64],
        var spectrum: List[Complex64],
        var waveform: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.family = family
        self.mcs_index = mcs_index
        self.payload_bit_count = payload_bit_count
        self.data_bits_per_symbol = data_bits_per_symbol
        self.coded_bits_per_symbol = coded_bits_per_symbol
        self.fcs = fcs
        self.data_field_bits = data_field_bits^
        self.scrambled_bits = scrambled_bits^
        self.mother_bits = mother_bits^
        self.punctured_bits = punctured_bits^
        self.interleaved_bits = interleaved_bits^
        self.qam_symbols = qam_symbols^
        self.spectrum = spectrum^
        self.waveform = waveform^
        self.checkpoint_metadata = checkpoint_metadata^


struct WifiBCCRx20MHz(Movable):
    var payload_bits: List[UInt8]
    var corrected_data_symbols: List[Complex64]
    var demapped_bits: List[UInt8]
    var deinterleaved_bits: List[UInt8]
    var decoded_bits: List[UInt8]
    var channel_estimate: List[Complex64]
    var equalized_spectrum: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]
    var common_phase: Float64
    var phase_slope: Float64
    var received_fcs: UInt64
    var computed_fcs: UInt64
    var service_ok: Bool
    var fcs_ok: Bool

    def __init__(
        out self,
        var payload_bits: List[UInt8],
        var corrected_data_symbols: List[Complex64],
        var demapped_bits: List[UInt8],
        var deinterleaved_bits: List[UInt8],
        var decoded_bits: List[UInt8],
        var channel_estimate: List[Complex64],
        var equalized_spectrum: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
        common_phase: Float64,
        phase_slope: Float64,
        received_fcs: UInt64,
        computed_fcs: UInt64,
        service_ok: Bool,
        fcs_ok: Bool,
    ):
        self.payload_bits = payload_bits^
        self.corrected_data_symbols = corrected_data_symbols^
        self.demapped_bits = demapped_bits^
        self.deinterleaved_bits = deinterleaved_bits^
        self.decoded_bits = decoded_bits^
        self.channel_estimate = channel_estimate^
        self.equalized_spectrum = equalized_spectrum^
        self.checkpoint_metadata = checkpoint_metadata^
        self.common_phase = common_phase
        self.phase_slope = phase_slope
        self.received_fcs = received_fcs
        self.computed_fcs = computed_fcs
        self.service_ok = service_ok
        self.fcs_ok = fcs_ok


struct WifiLDPCTx20MHz(Movable):
    var family: Int
    var mcs_index: Int
    var payload_bit_count: Int
    var fcs: UInt64
    var ldpc_block_length: Int
    var shortened_bits: Int
    var punctured_bits: Int
    var repeated_bits: Int
    var frame_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var rate_matched_bits: List[UInt8]
    var tone_mapped_bits: List[UInt8]
    var qam_symbols: List[Complex64]
    var spectrum: List[Complex64]
    var waveform: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        family: Int,
        mcs_index: Int,
        payload_bit_count: Int,
        fcs: UInt64,
        ldpc_block_length: Int,
        shortened_bits: Int,
        punctured_bits: Int,
        repeated_bits: Int,
        var frame_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var rate_matched_bits: List[UInt8],
        var tone_mapped_bits: List[UInt8],
        var qam_symbols: List[Complex64],
        var spectrum: List[Complex64],
        var waveform: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
    ):
        self.family = family
        self.mcs_index = mcs_index
        self.payload_bit_count = payload_bit_count
        self.fcs = fcs
        self.ldpc_block_length = ldpc_block_length
        self.shortened_bits = shortened_bits
        self.punctured_bits = punctured_bits
        self.repeated_bits = repeated_bits
        self.frame_bits = frame_bits^
        self.scrambled_bits = scrambled_bits^
        self.rate_matched_bits = rate_matched_bits^
        self.tone_mapped_bits = tone_mapped_bits^
        self.qam_symbols = qam_symbols^
        self.spectrum = spectrum^
        self.waveform = waveform^
        self.checkpoint_metadata = checkpoint_metadata^


struct WifiLDPCRx20MHz(Movable):
    var payload_bits: List[UInt8]
    var corrected_data_symbols: List[Complex64]
    var physical_llrs: List[Float64]
    var demapped_llrs: List[Float64]
    var rate_recovered_llrs: List[Float64]
    var decoded_frame_bits: List[UInt8]
    var channel_estimate: List[Complex64]
    var equalized_spectrum: List[Complex64]
    var checkpoint_metadata: List[CheckpointMetadata]
    var common_phase: Float64
    var phase_slope: Float64
    var received_fcs: UInt64
    var computed_fcs: UInt64
    var ldpc_block_length: Int
    var ldpc_converged: Bool
    var service_ok: Bool
    var fcs_ok: Bool

    def __init__(
        out self,
        var payload_bits: List[UInt8],
        var corrected_data_symbols: List[Complex64],
        var physical_llrs: List[Float64],
        var demapped_llrs: List[Float64],
        var rate_recovered_llrs: List[Float64],
        var decoded_frame_bits: List[UInt8],
        var channel_estimate: List[Complex64],
        var equalized_spectrum: List[Complex64],
        var checkpoint_metadata: List[CheckpointMetadata],
        common_phase: Float64,
        phase_slope: Float64,
        received_fcs: UInt64,
        computed_fcs: UInt64,
        ldpc_block_length: Int,
        ldpc_converged: Bool,
        service_ok: Bool,
        fcs_ok: Bool,
    ):
        self.payload_bits = payload_bits^
        self.corrected_data_symbols = corrected_data_symbols^
        self.physical_llrs = physical_llrs^
        self.demapped_llrs = demapped_llrs^
        self.rate_recovered_llrs = rate_recovered_llrs^
        self.decoded_frame_bits = decoded_frame_bits^
        self.channel_estimate = channel_estimate^
        self.equalized_spectrum = equalized_spectrum^
        self.checkpoint_metadata = checkpoint_metadata^
        self.common_phase = common_phase
        self.phase_slope = phase_slope
        self.received_fcs = received_fcs
        self.computed_fcs = computed_fcs
        self.ldpc_block_length = ldpc_block_length
        self.ldpc_converged = ldpc_converged
        self.service_ok = service_ok
        self.fcs_ok = fcs_ok


def _append_wifi_bit_checkpoint(
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


def _append_wifi_complex_checkpoint(
    mut result: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stage: StringSlice,
    length: Int,
) raises:
    result.append(checkpoint_metadata_1d(
        testcase_id,
        stage,
        "complex64",
        length,
        layout="iq-interleaved",
    ))


def _append_wifi_float_checkpoint(
    mut result: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stage: StringSlice,
    length: Int,
    *,
    layout: StringSlice = "linear",
) raises:
    result.append(checkpoint_metadata_1d(
        testcase_id, stage, "float64", length, layout=layout
    ))


def _append_wifi_scalar_checkpoint(
    mut result: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stage: StringSlice,
    dtype: StringSlice,
    q_format: StringSlice,
) raises:
    result.append(checkpoint_metadata_1d(
        testcase_id,
        stage,
        dtype,
        1,
        q_format=q_format,
        layout="scalar",
    ))


def _append_wifi_frequency_grid_checkpoint(
    mut result: List[CheckpointMetadata],
    testcase_id: StringSlice,
    length: Int,
    *,
    stage: StringSlice = "frequency-grid",
) raises:
    result.append(checkpoint_metadata_2d(
        testcase_id,
        stage,
        "complex64",
        1,
        length,
        row_stride=length,
        layout="row-major-frequency-grid-iq-interleaved",
    ))


def _wifi_bcc_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    payload: Int,
    data_field_bits: Int,
    scrambled_bits: Int,
    mother_bits: Int,
    punctured_bits: Int,
    interleaved_bits: Int,
    qam_symbols: Int,
    spectrum: Int,
    waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=10)
    _append_wifi_bit_checkpoint(result, testcase_id, "payload-input", payload)
    _append_wifi_bit_checkpoint(
        result, testcase_id, "data-field-bits", data_field_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "scrambled-bits", scrambled_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "mother-bits", mother_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "punctured-bits", punctured_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "interleaved-bits", interleaved_bits
    )
    _append_wifi_complex_checkpoint(
        result, testcase_id, "qam-symbols", qam_symbols
    )
    _append_wifi_frequency_grid_checkpoint(result, testcase_id, spectrum)
    _append_wifi_complex_checkpoint(
        result, testcase_id, "waveform", waveform
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "fcs", "uint64", "unsigned-integer"
    )
    return result^


def _wifi_bcc_rx_checkpoint_metadata(
    testcase_id: StringSlice,
    waveform: Int,
    ltf_samples: Int,
    channel_estimate: Int,
    equalized_spectrum: Int,
    corrected_data_symbols: Int,
    demapped_bits: Int,
    deinterleaved_bits: Int,
    decoded_bits: Int,
    payload_bits: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=14)
    _append_wifi_complex_checkpoint(
        result, testcase_id, "received-waveform", waveform
    )
    _append_wifi_complex_checkpoint(
        result, testcase_id, "ltf-samples", ltf_samples
    )
    _append_wifi_complex_checkpoint(
        result, testcase_id, "channel-estimate", channel_estimate
    )
    _append_wifi_frequency_grid_checkpoint(
        result,
        testcase_id,
        equalized_spectrum,
        stage="equalized-spectrum",
    )
    _append_wifi_float_checkpoint(
        result,
        testcase_id,
        "pilot-phase-estimate",
        2,
        layout="common-phase-phase-slope",
    )
    _append_wifi_complex_checkpoint(
        result,
        testcase_id,
        "pilot-corrected-data-symbols",
        corrected_data_symbols,
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "demapped-bits", demapped_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "deinterleaved-bits", deinterleaved_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "decoded-data-field-bits", decoded_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "decoded-payload-bits", payload_bits
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "received-fcs", "uint64", "unsigned-integer"
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "computed-fcs", "uint64", "unsigned-integer"
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "service-ok", "bool", "boolean"
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "fcs-ok", "bool", "boolean"
    )
    return result^


def _wifi_ldpc_tx_checkpoint_metadata(
    testcase_id: StringSlice,
    payload: Int,
    frame_bits: Int,
    scrambled_bits: Int,
    rate_matched_bits: Int,
    tone_mapped_bits: Int,
    qam_symbols: Int,
    spectrum: Int,
    waveform: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=9)
    _append_wifi_bit_checkpoint(result, testcase_id, "payload-input", payload)
    _append_wifi_bit_checkpoint(
        result, testcase_id, "frame-bits", frame_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "scrambled-bits", scrambled_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "rate-matched-bits", rate_matched_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "tone-mapped-bits", tone_mapped_bits
    )
    _append_wifi_complex_checkpoint(
        result, testcase_id, "qam-symbols", qam_symbols
    )
    _append_wifi_frequency_grid_checkpoint(result, testcase_id, spectrum)
    _append_wifi_complex_checkpoint(
        result, testcase_id, "waveform", waveform
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "fcs", "uint64", "unsigned-integer"
    )
    return result^


def _wifi_ldpc_rx_checkpoint_metadata(
    testcase_id: StringSlice,
    waveform: Int,
    ltf_samples: Int,
    channel_estimate: Int,
    equalized_spectrum: Int,
    corrected_data_symbols: Int,
    physical_llrs: Int,
    tone_demapped_llrs: Int,
    rate_recovered_llrs: Int,
    decoded_frame_bits: Int,
    payload_bits: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=16)
    _append_wifi_complex_checkpoint(
        result, testcase_id, "received-waveform", waveform
    )
    _append_wifi_complex_checkpoint(
        result, testcase_id, "ltf-samples", ltf_samples
    )
    _append_wifi_complex_checkpoint(
        result, testcase_id, "channel-estimate", channel_estimate
    )
    _append_wifi_frequency_grid_checkpoint(
        result,
        testcase_id,
        equalized_spectrum,
        stage="equalized-spectrum",
    )
    _append_wifi_float_checkpoint(
        result,
        testcase_id,
        "pilot-phase-estimate",
        2,
        layout="common-phase-phase-slope",
    )
    _append_wifi_complex_checkpoint(
        result,
        testcase_id,
        "pilot-corrected-data-symbols",
        corrected_data_symbols,
    )
    _append_wifi_float_checkpoint(
        result, testcase_id, "physical-llrs", physical_llrs
    )
    _append_wifi_float_checkpoint(
        result, testcase_id, "tone-demapped-llrs", tone_demapped_llrs
    )
    _append_wifi_float_checkpoint(
        result, testcase_id, "rate-recovered-llrs", rate_recovered_llrs
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "decoded-frame-bits", decoded_frame_bits
    )
    _append_wifi_bit_checkpoint(
        result, testcase_id, "decoded-payload-bits", payload_bits
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "received-fcs", "uint64", "unsigned-integer"
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "computed-fcs", "uint64", "unsigned-integer"
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "ldpc-converged", "bool", "boolean"
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "service-ok", "bool", "boolean"
    )
    _append_wifi_scalar_checkpoint(
        result, testcase_id, "fcs-ok", "bool", "boolean"
    )
    return result^


struct _WifiFrame(Movable):
    var bits: List[UInt8]
    var fcs: UInt64

    def __init__(out self, var bits: List[UInt8], fcs: UInt64):
        self.bits = bits^
        self.fcs = fcs


struct _WifiEqualized20MHz(Movable):
    var spectrum: List[Complex64]
    var channel: List[Complex64]

    def __init__(
        out self,
        var spectrum: List[Complex64],
        var channel: List[Complex64],
    ):
        self.spectrum = spectrum^
        self.channel = channel^


def _wifi_bin(subcarrier: Int, fft_size: Int) -> Int:
    return subcarrier if subcarrier >= 0 else fft_size + subcarrier


def _validate_payload(payload: Span[UInt8, ...]) raises:
    if len(payload) % 8 != 0:
        raise Error("Wi-Fi PSDU must contain complete octets")
    for i in range(len(payload)):
        if payload[i] > 1:
            raise Error("Wi-Fi PSDU must be binary")


def _frame_bits(payload: Span[UInt8, ...]) raises -> _WifiFrame:
    _validate_payload(payload)
    var fcs = wifi_fcs(payload)
    var result = List[UInt8](capacity=16 + len(payload) + 32)
    for _ in range(16):
        result.append(UInt8(0))
    for i in range(len(payload)):
        result.append(payload[i])
    for i in range(32):
        result.append(UInt8((fcs >> UInt64(i)) & UInt64(1)))
    return _WifiFrame(result^, fcs)


def _read_fcs(bits: Span[UInt8, ...], offset: Int) raises -> UInt64:
    if offset < 0 or offset + 32 > len(bits):
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


def wifi_ht_vht_data_subcarriers_20mhz(family: Int) raises -> List[Int]:
    """Return the 52 HT/VHT data tones in increasing-frequency order."""
    if family != WIFI_PHY_HT and family != WIFI_PHY_VHT:
        raise Error("HT/VHT data-tone helper requires HT or VHT")
    var result = List[Int](capacity=52)
    for subcarrier in range(-28, 29):
        if (
            subcarrier == 0
            or subcarrier == -21
            or subcarrier == -7
            or subcarrier == 7
            or subcarrier == 21
        ):
            continue
        result.append(subcarrier)
    return result^


def wifi_map_ht_vht_symbol_20mhz(
    data: Span[Complex64, ...],
    pilots: Span[Complex64, ...],
    family: Int,
) raises -> List[Complex64]:
    var data_indices = wifi_ht_vht_data_subcarriers_20mhz(family)
    var pilot_indices = wifi_data_pilot_subcarriers_20mhz(family)
    if len(data) != 52 or len(pilots) != 4:
        raise Error("HT/VHT 20 MHz symbol requires 52 data and four pilots")
    var spectrum = List[Complex64](length=64, fill=Complex64(0.0, 0.0))
    for i in range(len(data_indices)):
        spectrum[_wifi_bin(data_indices[i], 64)] = data[i]
    for i in range(len(pilot_indices)):
        spectrum[_wifi_bin(pilot_indices[i], 64)] = pilots[i]
    return spectrum^


def wifi_extract_ht_vht_data_20mhz(
    spectrum: Span[Complex64, ...], family: Int
) raises -> List[Complex64]:
    if len(spectrum) != 64:
        raise Error("HT/VHT 20 MHz spectrum must contain 64 bins")
    var indices = wifi_ht_vht_data_subcarriers_20mhz(family)
    var result = List[Complex64](capacity=52)
    for subcarrier in indices:
        result.append(spectrum[_wifi_bin(subcarrier, 64)])
    return result^


def wifi_extract_ht_vht_pilots_20mhz(
    spectrum: Span[Complex64, ...], family: Int
) raises -> List[Complex64]:
    if len(spectrum) != 64:
        raise Error("HT/VHT 20 MHz spectrum must contain 64 bins")
    var indices = wifi_data_pilot_subcarriers_20mhz(family)
    var result = List[Complex64](capacity=4)
    for subcarrier in indices:
        result.append(spectrum[_wifi_bin(subcarrier, 64)])
    return result^


def wifi_ldpc_tone_mapping_distance(ru_tones: Int) raises -> Int:
    """Return D_TM from IEEE 802.11ax Table 27-36."""
    if ru_tones == 26:
        return 1
    if ru_tones == 52:
        return 3
    if ru_tones == 106:
        return 6
    if ru_tones == 242:
        return 9
    if ru_tones == 484:
        return 12
    if ru_tones == 996 or ru_tones == 1992 or ru_tones == 3984:
        return 20
    raise Error("unsupported Wi-Fi LDPC tone-mapping RU")


def wifi_ldpc_tone_permutation(
    data_subcarriers: Int, distance: Int
) raises -> List[Int]:
    """Return t(k)=D_TM*(k mod Nsd/D_TM)+floor(k*D_TM/Nsd)."""
    if data_subcarriers < 1 or distance < 1 or data_subcarriers % distance != 0:
        raise Error("invalid Wi-Fi LDPC tone-mapping dimensions")
    var result = List[Int](capacity=data_subcarriers)
    for k in range(data_subcarriers):
        result.append(
            distance * (k % (data_subcarriers // distance))
            + (k * distance) // data_subcarriers
        )
    return result^


def _wifi_ldpc_tone_geometry(ru_tones: Int) raises -> Tuple[Int, Int]:
    """Return total Nsd and the number of independently mapped subblocks."""
    if ru_tones == 26:
        return (24, 1)
    if ru_tones == 52:
        return (48, 1)
    if ru_tones == 106:
        return (102, 1)
    if ru_tones == 242:
        return (234, 1)
    if ru_tones == 484:
        return (468, 1)
    if ru_tones == 996:
        return (980, 1)
    if ru_tones == 1992:
        return (1960, 2)
    if ru_tones == 3984:
        return (3920, 4)
    raise Error("unsupported Wi-Fi LDPC tone-mapping RU")


def wifi_ldpc_tone_map_bits(
    bits: Span[UInt8, ...], bits_per_subcarrier: Int, ru_tones: Int
) raises -> List[UInt8]:
    var (nsd, subblocks) = _wifi_ldpc_tone_geometry(ru_tones)
    if bits_per_subcarrier < 1 or len(bits) != nsd * bits_per_subcarrier:
        raise Error("LDPC tone mapper requires one complete RU symbol")
    var subblock_nsd = nsd // subblocks
    var permutation = wifi_ldpc_tone_permutation(
        subblock_nsd, wifi_ldpc_tone_mapping_distance(ru_tones)
    )
    var result = List[UInt8](length=len(bits), fill=UInt8(0))
    for subblock in range(subblocks):
        for local_source in range(subblock_nsd):
            var source_tone = subblock * subblock_nsd + local_source
            var destination_tone = (
                subblock * subblock_nsd + permutation[local_source]
            )
            for bit in range(bits_per_subcarrier):
                result[destination_tone * bits_per_subcarrier + bit] = bits[
                    source_tone * bits_per_subcarrier + bit
                ]
    return result^


def wifi_ldpc_tone_demap_llrs(
    llrs: Span[Float64, ...], bits_per_subcarrier: Int, ru_tones: Int
) raises -> List[Float64]:
    var (nsd, subblocks) = _wifi_ldpc_tone_geometry(ru_tones)
    if bits_per_subcarrier < 1 or len(llrs) != nsd * bits_per_subcarrier:
        raise Error("LDPC tone demapper requires one complete RU symbol")
    var subblock_nsd = nsd // subblocks
    var permutation = wifi_ldpc_tone_permutation(
        subblock_nsd, wifi_ldpc_tone_mapping_distance(ru_tones)
    )
    var result = List[Float64](length=len(llrs), fill=0.0)
    for subblock in range(subblocks):
        for local_source in range(subblock_nsd):
            var source_tone = subblock * subblock_nsd + local_source
            var destination_tone = (
                subblock * subblock_nsd + permutation[local_source]
            )
            for bit in range(bits_per_subcarrier):
                result[source_tone * bits_per_subcarrier + bit] = llrs[
                    destination_tone * bits_per_subcarrier + bit
                ]
    return result^


def wifi_bcc_tx_20mhz(
    payload: Span[UInt8, ...],
    family: Int,
    mcs_index: Int,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    symbol_index: Int = 0,
    testcase_id: StringSlice = "wifi-bcc-tx-20mhz",
) raises -> WifiBCCTx20MHz:
    """Build one HT/VHT DATA symbol through FCS, BCC, QAM, IFFT, and CP."""
    if family != WIFI_PHY_HT and family != WIFI_PHY_VHT:
        raise Error("BCC reference chain supports HT or VHT")
    var mcs = wifi_mcs_profile(family, mcs_index)
    if mcs.spatial_streams != 1 or mcs.bits_per_subcarrier < 6:
        raise Error("reference chain requires one-stream HT/VHT 64/256-QAM")
    var ofdm = wifi_ofdm_profile(family, 20)
    var ncbps = wifi_coded_bits_per_symbol(ofdm, mcs)
    var ndbps = wifi_data_bits_per_symbol(ofdm, mcs)
    var framed = _frame_bits(payload)
    var fcs = framed.fcs
    var frame = framed.bits.copy()
    if len(frame) + 6 > ndbps:
        raise Error("PSDU does not fit one HT/VHT DATA symbol")
    var tail_start = len(frame)
    for _ in range(6):
        frame.append(UInt8(0))
    while len(frame) < ndbps:
        frame.append(UInt8(0))
    var scrambled = wifi_scramble(Span(frame), scrambler_seed)
    # Clause DATA ordering is SERVICE, PSDU/FCS, TAIL, then PAD.  Tail is
    # overwritten after scrambling; following scrambled pad bits are encoded.
    for i in range(tail_start, tail_start + 6):
        scrambled[i] = UInt8(0)
    var generators: List[Int] = [0o133, 0o171]
    var mother = convolutional_encode(
        Span(scrambled), Span(generators), 7, terminate=False
    )
    var punctured = wifi_bcc_puncture(
        Span(mother), mcs.code_rate_numerator, mcs.code_rate_denominator
    )
    if len(punctured) != ncbps:
        raise Error("internal BCC puncturing length mismatch")
    var interleaver = wifi_bcc_interleaver_profile(family, 20)
    var interleaved = wifi_bcc_interleave_block(
        Span(punctured), mcs.bits_per_subcarrier, interleaver
    )
    var symbols = qam_map(Span(interleaved), mcs.bits_per_subcarrier)
    var pilots = wifi_data_pilots_20mhz(family, symbol_index)
    var spectrum = wifi_map_ht_vht_symbol_20mhz(
        Span(symbols), Span(pilots), family
    )
    var waveform = ofdm_modulate(Span(spectrum), 16)
    var checkpoint_metadata = _wifi_bcc_tx_checkpoint_metadata(
        testcase_id,
        len(payload),
        len(frame),
        len(scrambled),
        len(mother),
        len(punctured),
        len(interleaved),
        len(symbols),
        len(spectrum),
        len(waveform),
    )
    return WifiBCCTx20MHz(
        family,
        mcs_index,
        len(payload),
        ndbps,
        ncbps,
        fcs,
        frame^,
        scrambled^,
        mother^,
        punctured^,
        interleaved^,
        symbols^,
        spectrum^,
        waveform^,
        checkpoint_metadata^,
    )


def _equalized_spectrum_20mhz(
    samples: Span[Complex64, ...],
    ltf_samples: Span[Complex64, ...],
    family: Int,
) raises -> _WifiEqualized20MHz:
    var fft_size = (
        64 if family == WIFI_PHY_HT or family == WIFI_PHY_VHT else 256
    )
    var received = ofdm_demodulate(samples, fft_size, 16)
    var channel = wifi_ltf_channel_estimate_20mhz(ltf_samples, family)
    var equalized = List[Complex64](length=fft_size, fill=Complex64(0.0, 0.0))
    for i in range(fft_size):
        if channel[i].re != 0.0 or channel[i].im != 0.0:
            equalized[i] = complex_divide(received[i], channel[i])
    return _WifiEqualized20MHz(equalized^, channel^)


def wifi_bcc_rx_20mhz(
    samples: Span[Complex64, ...],
    ltf_samples: Span[Complex64, ...],
    family: Int,
    mcs_index: Int,
    payload_bit_count: Int,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    symbol_index: Int = 0,
    testcase_id: StringSlice = "wifi-bcc-rx-20mhz",
) raises -> WifiBCCRx20MHz:
    """Receive one HT/VHT DATA symbol through FFT, LTF/pilots, BCC, and FCS."""
    if payload_bit_count < 0 or payload_bit_count % 8 != 0:
        raise Error("invalid Wi-Fi payload length")
    var mcs = wifi_mcs_profile(family, mcs_index)
    var ofdm = wifi_ofdm_profile(family, 20)
    var ndbps = wifi_data_bits_per_symbol(ofdm, mcs)
    if 16 + payload_bit_count + 32 + 6 > ndbps:
        raise Error("PSDU does not fit one HT/VHT DATA symbol")
    var equalized_result = _equalized_spectrum_20mhz(
        samples, ltf_samples, family
    )
    var equalized = equalized_result.spectrum.copy()
    var channel = equalized_result.channel.copy()
    var pilot_samples = wifi_extract_ht_vht_pilots_20mhz(
        Span(equalized), family
    )
    var known_pilots = wifi_data_pilots_20mhz(family, symbol_index)
    var pilot_indices = wifi_data_pilot_subcarriers_20mhz(family)
    var phase = wifi_estimate_pilot_phase(
        Span(pilot_samples), Span(known_pilots), Span(pilot_indices)
    )
    var data = wifi_extract_ht_vht_data_20mhz(Span(equalized), family)
    var data_indices = wifi_ht_vht_data_subcarriers_20mhz(family)
    var corrected = wifi_correct_pilot_phase(
        Span(data), Span(data_indices), phase
    )
    var demapped = qam_demap_hard(Span(corrected), mcs.bits_per_subcarrier)
    var interleaver = wifi_bcc_interleaver_profile(family, 20)
    var deinterleaved = wifi_bcc_deinterleave_block(
        Span(demapped), mcs.bits_per_subcarrier, interleaver
    )
    var punctured_llrs = List[Float64](capacity=len(deinterleaved))
    for bit in deinterleaved:
        punctured_llrs.append(20.0 if bit == 0 else -20.0)
    var mother_llrs = wifi_bcc_depuncture_llrs(
        Span(punctured_llrs),
        2 * ndbps,
        mcs.code_rate_numerator,
        mcs.code_rate_denominator,
    )
    var generators: List[Int] = [0o133, 0o171]
    # Tail precedes scrambled padding, so the final trellis state is not
    # constrained even though the tail checkpoint itself resets the encoder.
    var decoded = viterbi_decode_soft(
        Span(mother_llrs), Span(generators), 7, terminate=False
    )
    var descrambled = wifi_scramble(Span(decoded), scrambler_seed)
    var payload = List[UInt8](capacity=payload_bit_count)
    for i in range(payload_bit_count):
        payload.append(descrambled[16 + i])
    var received_fcs = _read_fcs(Span(descrambled), 16 + payload_bit_count)
    var computed_fcs = wifi_fcs(Span(payload))
    var service_ok = _service_is_zero(Span(descrambled))
    var fcs_ok = received_fcs == computed_fcs
    var checkpoint_metadata = _wifi_bcc_rx_checkpoint_metadata(
        testcase_id,
        len(samples),
        len(ltf_samples),
        len(channel),
        len(equalized),
        len(corrected),
        len(demapped),
        len(deinterleaved),
        len(descrambled),
        len(payload),
    )
    return WifiBCCRx20MHz(
        payload^,
        corrected^,
        demapped^,
        deinterleaved^,
        descrambled^,
        channel^,
        equalized^,
        checkpoint_metadata^,
        phase.common_phase,
        phase.phase_slope,
        received_fcs,
        computed_fcs,
        service_ok,
        fcs_ok,
    )


def _ldpc_chain_profile(
    family: Int, mcs_index: Int
) raises -> Tuple[Int, Int, Int, Int]:
    var mcs = wifi_mcs_profile(family, mcs_index)
    if not mcs.ldpc_only:
        raise Error("selected HE/EHT MCS does not require LDPC")
    if family == WIFI_PHY_HE:
        if mcs_index != 10:
            raise Error(
                "minimal HE LDPC chain implements MCS 10 (1024-QAM 3/4)"
            )
    elif family == WIFI_PHY_EHT:
        if mcs_index != 13:
            raise Error(
                "minimal EHT LDPC chain implements MCS 13 (4096-QAM 5/6)"
            )
    else:
        raise Error("LDPC RU chain requires HE or EHT")
    var ru = wifi_ru_profile(family, 242)
    return (
        mcs.code_rate_numerator,
        mcs.code_rate_denominator,
        mcs.bits_per_subcarrier,
        wifi_ru_coded_bits_per_symbol(ru, mcs),
    )


def _ldpc_block_length(
    frame_length: Int,
    coded_length: Int,
    rate_numerator: Int,
    rate_denominator: Int,
) raises -> Int:
    """Apply the legacy WLAN L_LDPC selection thresholds used by HE/EHT."""
    if frame_length < 1 or coded_length < 1:
        raise Error("invalid Wi-Fi LDPC selection dimensions")
    # Table 19-16.  This minimal chain only consumes its two-codeword rows.
    if coded_length <= 648:
        var threshold = frame_length * rate_denominator + (
            912 * (rate_denominator - rate_numerator)
        )
        return 1296 if coded_length * rate_denominator >= threshold else 648
    if coded_length <= 1296:
        var threshold = frame_length * rate_denominator + (
            1464 * (rate_denominator - rate_numerator)
        )
        return 1944 if coded_length * rate_denominator >= threshold else 1296
    if coded_length <= 1944:
        return 1944
    if coded_length <= 2592:
        var threshold = frame_length * rate_denominator + (
            2916 * (rate_denominator - rate_numerator)
        )
        return 1944 if coded_length * rate_denominator >= threshold else 1296
    return 1944


def _share(total: Int, index: Int, count: Int) -> Int:
    return total // count + (1 if index < total % count else 0)


def _ldpc_rate_counts(
    profile: WifiLDPCProfile, frame_length: Int, coded_length: Int
) raises -> Tuple[Int, Int, Int]:
    # This auditable RU-242 reference uses two equal-size WLAN codewords.  The
    # formulas are the 802.11 shortening/puncturing/repetition definitions.
    var shortened = 2 * profile.information_length - frame_length
    if shortened < 0 or shortened >= 2 * profile.information_length:
        raise Error("DATA bits do not fit the two-codeword LDPC reference plan")
    var punctured = max(0, 2 * profile.block_length - coded_length - shortened)
    var repeated = max(0, coded_length - 2 * profile.block_length + shortened)
    if punctured > 2 * profile.parity_length:
        raise Error("LDPC plan would puncture beyond its parity fields")
    return (shortened, punctured, repeated)


def wifi_ldpc_tx_20mhz(
    payload: Span[UInt8, ...],
    family: Int,
    mcs_index: Int,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    symbol_index: Int = 0,
    testcase_id: StringSlice = "wifi-ldpc-tx-20mhz",
) raises -> WifiLDPCTx20MHz:
    """Build one HE/EHT RU-242 symbol through WLAN LDPC and 1024/4096-QAM."""
    var (rate_numerator, rate_denominator, bpsc, ncbps) = _ldpc_chain_profile(
        family, mcs_index
    )
    var framed = _frame_bits(payload)
    var fcs = framed.fcs
    var frame = framed.bits.copy()
    var block_length = _ldpc_block_length(
        len(frame), ncbps, rate_numerator, rate_denominator
    )
    var profile = wifi_ldpc_profile(
        block_length, rate_numerator, rate_denominator
    )
    var (shortened, punctured, repeated) = _ldpc_rate_counts(
        profile, len(frame), ncbps
    )
    var scrambled = wifi_scramble(Span(frame), scrambler_seed)
    var rate_matched = List[UInt8](capacity=ncbps)
    var source = 0
    for codeword in range(2):
        var s = _share(shortened, codeword, 2)
        var p = _share(punctured, codeword, 2)
        var r = _share(repeated, codeword, 2)
        var information_length = profile.information_length - s
        var information = List[UInt8](capacity=information_length)
        for _ in range(information_length):
            information.append(scrambled[source])
            source += 1
        var block = wifi_ldpc_rate_match_block(
            Span(information),
            profile,
            shortened_bits=s,
            punctured_bits=p,
            repeated_bits=r,
        )
        for bit in block:
            rate_matched.append(bit)
    if source != len(scrambled) or len(rate_matched) != ncbps:
        raise Error("internal Wi-Fi LDPC segmentation length mismatch")
    var tone_mapped = wifi_ldpc_tone_map_bits(Span(rate_matched), bpsc, 242)
    var symbols = qam_map(Span(tone_mapped), bpsc)
    var pilots = wifi_data_pilots_20mhz(family, symbol_index)
    var spectrum = wifi_map_ru_symbol_20mhz(Span(symbols), Span(pilots), 242, 0)
    var waveform = ofdm_modulate(Span(spectrum), 16)
    var checkpoint_metadata = _wifi_ldpc_tx_checkpoint_metadata(
        testcase_id,
        len(payload),
        len(frame),
        len(scrambled),
        len(rate_matched),
        len(tone_mapped),
        len(symbols),
        len(spectrum),
        len(waveform),
    )
    return WifiLDPCTx20MHz(
        family,
        mcs_index,
        len(payload),
        fcs,
        profile.block_length,
        shortened,
        punctured,
        repeated,
        frame^,
        scrambled^,
        rate_matched^,
        tone_mapped^,
        symbols^,
        spectrum^,
        waveform^,
        checkpoint_metadata^,
    )


def wifi_ldpc_rx_20mhz(
    samples: Span[Complex64, ...],
    ltf_samples: Span[Complex64, ...],
    family: Int,
    mcs_index: Int,
    payload_bit_count: Int,
    noise_variance: Float64,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    symbol_index: Int = 0,
    max_iterations: Int = 20,
    per_tone_llr_reliability: Bool = False,
    testcase_id: StringSlice = "wifi-ldpc-rx-20mhz",
) raises -> WifiLDPCRx20MHz:
    """Receive one HE/EHT RU-242 symbol and verify SERVICE, LDPC, and FCS.

    ``noise_variance`` is the pre-ZF frequency-bin complex variance.  When
    ``per_tone_llr_reliability`` is true, each post-ZF tone's LLRs are
    multiplied by its estimated ``|H[k]|^2``.  This is equivalent to using
    the tone-specific post-ZF variance ``noise_variance / |H[k]|^2`` and is
    required for frequency-selective link simulations.  The default keeps
    the historical scalar-variance behavior for compatibility.
    """
    if payload_bit_count < 0 or payload_bit_count % 8 != 0:
        raise Error("invalid Wi-Fi payload length")
    var (rate_numerator, rate_denominator, bpsc, ncbps) = _ldpc_chain_profile(
        family, mcs_index
    )
    var frame_length = 16 + payload_bit_count + 32
    var block_length = _ldpc_block_length(
        frame_length, ncbps, rate_numerator, rate_denominator
    )
    var profile = wifi_ldpc_profile(
        block_length, rate_numerator, rate_denominator
    )
    var (shortened, punctured, repeated) = _ldpc_rate_counts(
        profile, frame_length, ncbps
    )
    var equalized_result = _equalized_spectrum_20mhz(
        samples, ltf_samples, family
    )
    var equalized = equalized_result.spectrum.copy()
    var channel = equalized_result.channel.copy()
    var received_pilots = wifi_extract_ru_pilots_20mhz(Span(equalized), 242, 0)
    var known_pilots = wifi_data_pilots_20mhz(family, symbol_index)
    var pilot_indices = wifi_data_pilot_subcarriers_20mhz(family)
    var phase = wifi_estimate_pilot_phase(
        Span(received_pilots), Span(known_pilots), Span(pilot_indices)
    )
    var data = wifi_extract_ru_data_20mhz(Span(equalized), 242, 0)
    var data_indices = wifi_ru_data_subcarriers_20mhz(242, 0)
    var corrected = wifi_correct_pilot_phase(
        Span(data), Span(data_indices), phase
    )
    var physical_llrs = qam_demapper_llr_piecewise(
        Span(corrected), bpsc, noise_variance
    )
    if per_tone_llr_reliability:
        for tone in range(len(data_indices)):
            var h = channel[_wifi_bin(data_indices[tone], 256)]
            var reliability = h.magnitude_squared()
            for bit in range(bpsc):
                physical_llrs[tone * bpsc + bit] *= reliability
    var demapped = wifi_ldpc_tone_demap_llrs(Span(physical_llrs), bpsc, 242)
    var recovered_all = List[Float64](capacity=2 * profile.block_length)
    var decoded_scrambled = List[UInt8](capacity=frame_length)
    var source = 0
    var converged = True
    for codeword in range(2):
        var s = _share(shortened, codeword, 2)
        var p = _share(punctured, codeword, 2)
        var r = _share(repeated, codeword, 2)
        var block_length = profile.block_length - s - p + r
        var block = List[Float64](capacity=block_length)
        for _ in range(block_length):
            block.append(demapped[source])
            source += 1
        var recovered = wifi_ldpc_rate_recover_block(
            Span(block),
            profile,
            shortened_bits=s,
            punctured_bits=p,
            repeated_bits=r,
        )
        for llr in recovered:
            recovered_all.append(llr)
        var decoded = wifi_ldpc_decode(
            Span(recovered), profile, max_iterations=max_iterations
        )
        converged = converged and decoded.converged
        for i in range(profile.information_length - s):
            decoded_scrambled.append(decoded.information_bits[i])
    if source != len(demapped) or len(decoded_scrambled) != frame_length:
        raise Error("internal Wi-Fi LDPC recovery length mismatch")
    var decoded_frame = wifi_scramble(Span(decoded_scrambled), scrambler_seed)
    var payload = List[UInt8](capacity=payload_bit_count)
    for i in range(payload_bit_count):
        payload.append(decoded_frame[16 + i])
    var received_fcs = _read_fcs(Span(decoded_frame), 16 + payload_bit_count)
    var computed_fcs = wifi_fcs(Span(payload))
    var service_ok = _service_is_zero(Span(decoded_frame))
    var fcs_ok = received_fcs == computed_fcs
    var checkpoint_metadata = _wifi_ldpc_rx_checkpoint_metadata(
        testcase_id,
        len(samples),
        len(ltf_samples),
        len(channel),
        len(equalized),
        len(corrected),
        len(physical_llrs),
        len(demapped),
        len(recovered_all),
        len(decoded_frame),
        len(payload),
    )
    return WifiLDPCRx20MHz(
        payload^,
        corrected^,
        physical_llrs^,
        demapped^,
        recovered_all^,
        decoded_frame^,
        channel^,
        equalized^,
        checkpoint_metadata^,
        phase.common_phase,
        phase.phase_slope,
        received_fcs,
        computed_fcs,
        profile.block_length,
        converged,
        service_ok,
        fcs_ok,
    )
