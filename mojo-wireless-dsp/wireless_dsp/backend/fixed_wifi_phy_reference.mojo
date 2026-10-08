"""Coded fixed-point BCC/QPSK/OFDM mini-PHY golden reference.

This module connects the IEEE 802.11 K=7, rate-1/2 integer BCC model to the
existing fixed QPSK/OFDM/flat-LS/ZF chain.  It deliberately models one dense
OFDM symbol rather than an interoperable Wi-Fi PPDU: there is no puncturing,
interleaver, STF/LTF/SIGNAL, FCS, or standard subcarrier allocation.  The
purpose is a fully bit-exact coded hardware pipeline with inspectable integer
LLRs and hard/soft Viterbi checkpoints.

With six zero tail bits, a payload must contain ``N-6`` bits for an N-point
transform.  Rate-1/2 coding then produces exactly ``2*N`` bits, which fill N
QPSK tones without padding or hidden shortening.
"""

from std.collections import Span
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.quantization import QFormat
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYFormats,
    FixedPHYResult,
    fixed_phy_one_symbol_reference,
    fixed_phy_result_checksum,
    fixed_phy_canonical_rtl_vectors,
    fixed_qpsk_llrs_raw,
)
from wireless_dsp.backend.fixed_wifi_bcc_reference import (
    WIFI_BCC_CONSTRAINT_LENGTH,
    FixedWifiBCCDecodeResult,
    FixedWifiBCCViterbiConfig,
    fixed_wifi_bcc_canonical_rtl_vectors,
    fixed_wifi_bcc_encode,
    fixed_wifi_bcc_result_checksum,
    fixed_wifi_bcc_viterbi_decode_hard,
    fixed_wifi_bcc_viterbi_decode_soft,
)


struct FixedWifiPHYResult(Movable):
    """Every coded, waveform, LLR, and Viterbi checkpoint in stage order."""

    var payload_bits: List[UInt8]
    var coded_bits: List[UInt8]
    var llrs_raw: List[Int64]
    var phy: FixedPHYResult
    var hard_viterbi: FixedWifiBCCDecodeResult
    var soft_viterbi: FixedWifiBCCDecodeResult
    var payload_bit_errors: Int

    def __init__(
        out self,
        var payload_bits: List[UInt8],
        var coded_bits: List[UInt8],
        var llrs_raw: List[Int64],
        var phy: FixedPHYResult,
        var hard_viterbi: FixedWifiBCCDecodeResult,
        var soft_viterbi: FixedWifiBCCDecodeResult,
        payload_bit_errors: Int,
    ):
        self.payload_bits = payload_bits^
        self.coded_bits = coded_bits^
        self.llrs_raw = llrs_raw^
        self.phy = phy^
        self.hard_viterbi = hard_viterbi^
        self.soft_viterbi = soft_viterbi^
        self.payload_bit_errors = payload_bit_errors


def fixed_wifi_bcc_ofdm_reference(
    payload_bits: Span[UInt8, ...],
    transform_size: Int,
    cyclic_prefix: Int,
    flat_channel: ComplexRaw,
    formats: FixedPHYFormats,
    amplitude_raw: Int64,
    *,
    pilot_symbols: Int = 1,
    metric_storage_bits: Int = 30,
) raises -> FixedWifiPHYResult:
    """Run payload -> BCC -> fixed PHY -> raw LLR -> Viterbi -> payload."""
    if len(payload_bits) + WIFI_BCC_CONSTRAINT_LENGTH - 1 != transform_size:
        raise Error("fixed coded PHY payload must contain transform_size-6 bits")
    var payload = List[UInt8](capacity=len(payload_bits))
    for index in range(len(payload_bits)):
        if payload_bits[index] > 1:
            raise Error("fixed coded PHY payload must be binary")
        payload.append(payload_bits[index])

    var coded = fixed_wifi_bcc_encode(payload_bits)
    var phy = fixed_phy_one_symbol_reference(
        Span(coded),
        transform_size,
        cyclic_prefix,
        flat_channel,
        formats,
        amplitude_raw,
        pilot_symbols,
    )
    var llrs = fixed_qpsk_llrs_raw(
        Span(phy.equalized_symbols), formats.symbol, formats.symbol
    )
    var hard = fixed_wifi_bcc_viterbi_decode_hard(
        Span(phy.decoded_bits), metric_storage_bits=metric_storage_bits
    )
    var soft = fixed_wifi_bcc_viterbi_decode_soft(
        Span(llrs),
        FixedWifiBCCViterbiConfig(formats.symbol, metric_storage_bits),
    )
    var errors = 0
    for index in range(len(payload)):
        if soft.bits[index] != payload[index]:
            errors += 1
    return FixedWifiPHYResult(
        payload^, coded^, llrs^, phy^, hard^, soft^, errors
    )


def _mix_checksum_word(mut state: UInt64, word: UInt64):
    for byte_index in range(8):
        state ^= UInt64(
            UInt8((word >> UInt64(8 * byte_index)) & UInt64(0xff))
        )
        state *= UInt64(1099511628211)


def fixed_wifi_phy_result_checksum(
    result: FixedWifiPHYResult, llr_format: QFormat
) raises -> UInt64:
    """FNV-1a composition of the fixed PHY and complete BCC checkpoints."""
    var bcc_checksum = fixed_wifi_bcc_result_checksum(
        Span(result.payload_bits),
        Span(result.coded_bits),
        Span(result.llrs_raw),
        llr_format,
        result.hard_viterbi,
        result.soft_viterbi,
    )
    var state = UInt64(14695981039346656037)
    _mix_checksum_word(state, fixed_phy_result_checksum(result.phy))
    _mix_checksum_word(state, bcc_checksum)
    _mix_checksum_word(state, UInt64(result.payload_bit_errors))
    return state


def fixed_wifi_phy_canonical_rtl_vectors(
    result: FixedWifiPHYResult, formats: FixedPHYFormats
) raises -> String:
    """Serialize the connected BCC and PHY pipelines plus a joint checksum."""
    var text = String()
    text.write(
        fixed_wifi_bcc_canonical_rtl_vectors(
            Span(result.payload_bits),
            Span(result.coded_bits),
            Span(result.llrs_raw),
            formats.symbol,
            result.hard_viterbi,
            result.soft_viterbi,
        )
    )
    text.write(fixed_phy_canonical_rtl_vectors(result.phy, formats))
    text.write(
        "MWDSP-FIXED-WIFI-PHY-CHECKSUM-V1\nchecksum=",
        fixed_wifi_phy_result_checksum(result, formats.symbol),
        "\n",
    )
    return text^
