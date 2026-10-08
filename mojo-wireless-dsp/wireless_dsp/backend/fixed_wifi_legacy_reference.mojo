"""Bit-exact IEEE 802.11 legacy QPSK DATA mini-PHY reference.

This hardware-facing golden model fills the protocol gap intentionally left by
``fixed_wifi_phy_reference``.  It uses the interoperable 20 MHz legacy OFDM
geometry: a 64-point transform, 16-sample DATA cyclic prefix, 48 data tones,
four pilots, QPSK, and the K=7 rate-1/2 BCC.  DATA framing contains sixteen
SERVICE bits, a byte-oriented payload, its IEEE CRC-32 FCS, six encoder tail
bits, and symbol padding.  Scrambling, tail reset, and the two-step IEEE
interleaver occur at their standard boundaries.

The receiver uses the public 52-tone legacy L-LTF configuration, represented
as GI2 plus two long symbols, for a fixed-point flat LS estimate.  Each DATA
symbol then follows the fixed FFT, flat ZF, raw QPSK LLR, soft deinterleaver,
and integer Viterbi path.  The model is deliberately bounded to a flat channel
and known timing: it is a bit-exact legacy DATA reference, not a packet
detector or a frequency-selective channel estimator.

Every arithmetic boundary uses round-to-nearest-away and two's-complement
saturation.  Wrap is rejected by the format validator.  The IFFT shifts one
bit at each of six radix-2 stages (total 1/64); the FFT has no stage shift.
Pilots and L-LTF BPSK tones use ``round(sqrt(2) * A)`` so that their power
matches QPSK with component amplitude ``A``.  The multiplier uses the fixed
Q17.16 constant 92682 and one nearest-away shift.  The accepted QPSK component
range [1024, 32767] raw in Q18.14 keeps both the FFT datapath and the Q24.18
reciprocal used by the 52-tone LS solve inside the audited numeric envelope.
"""

from std.collections import Span
from wireless_dsp.numerics.fixed import (
    OVERFLOW_SATURATE,
    ROUND_NEAREST_AWAY,
)
from wireless_dsp.numerics.quantization import (
    QFormat,
    narrow_raw,
    rounded_shift_right,
)
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYAudit,
    FixedPHYFormats,
    fixed_equalize_flat_raw,
    fixed_flat_channel_raw,
    fixed_ls_flat_channel_raw,
    fixed_ofdm_demodulate_raw,
    fixed_ofdm_modulate_raw,
    fixed_qpsk_float64_audit,
    fixed_qpsk_llrs_raw,
    fixed_qpsk_map_raw,
)
from wireless_dsp.backend.fixed_wifi_bcc_reference import (
    FixedWifiBCCDecodeResult,
    FixedWifiBCCViterbiConfig,
    fixed_wifi_bcc_encode,
    fixed_wifi_bcc_viterbi_decode_soft,
)
from wireless_dsp.testing.fixed_vectors import (
    complex_raw_checksum,
    fixed_raw_checksum,
    serialize_complex_fixed_vector,
    serialize_fixed_vector,
)
from wireless_dsp.wireless.wifi.legacy import (
    wifi_data_subcarriers,
    wifi_fcs,
    wifi_interleave,
    wifi_pilot_polarity,
    wifi_scramble,
)
from wireless_dsp.wireless.wifi.he_eht_acquisition import (
    wifi_legacy_ltf_spectrum_20mhz,
)


comptime FIXED_WIFI_LEGACY_FFT_SIZE = 64
comptime FIXED_WIFI_LEGACY_CP_LENGTH = 16
comptime FIXED_WIFI_LEGACY_DATA_TONES = 48
comptime FIXED_WIFI_LEGACY_PILOT_TONES = 4
comptime FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL = 96
comptime FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL = 48
comptime FIXED_WIFI_LEGACY_SERVICE_BITS = 16
comptime FIXED_WIFI_LEGACY_TAIL_BITS = 6
comptime FIXED_WIFI_LEGACY_FCS_BITS = 32
comptime FIXED_WIFI_LEGACY_MAX_PSDU_OCTETS = 4095
comptime FIXED_WIFI_LEGACY_MIN_AMPLITUDE_RAW = 1024
comptime FIXED_WIFI_LEGACY_MAX_AMPLITUDE_RAW = 32767


struct FixedWifiLegacyResult(Movable):
    """All raw frame, mapper, OFDM, estimator, decoder, and FCS stages."""

    var payload_bytes: List[UInt8]
    var psdu_bits: List[UInt8]
    var fcs_bits: List[UInt8]
    var uncoded_data_bits: List[UInt8]
    var scrambled_data_bits: List[UInt8]
    var coded_bits: List[UInt8]
    var interleaved_bits: List[UInt8]
    var ltf_grid: List[ComplexRaw]
    var ltf_transmit_samples: List[ComplexRaw]
    var ltf_channel_samples: List[ComplexRaw]
    var ltf_received_bins: List[ComplexRaw]
    var channel_estimate: ComplexRaw
    var mapped_data_symbols: List[ComplexRaw]
    var data_frequency_grids: List[ComplexRaw]
    var data_transmit_samples: List[ComplexRaw]
    var data_channel_samples: List[ComplexRaw]
    var data_received_bins: List[ComplexRaw]
    var equalized_data_symbols: List[ComplexRaw]
    var interleaved_llrs_raw: List[Int64]
    var deinterleaved_llrs_raw: List[Int64]
    var soft_viterbi: FixedWifiBCCDecodeResult
    var descrambled_data_bits: List[UInt8]
    var recovered_payload_bytes: List[UInt8]
    var recovered_fcs_bits: List[UInt8]
    var fcs_expected: UInt64
    var fcs_recovered: UInt64
    var fcs_ok: Bool
    var service_ok: Bool
    var tail_ok: Bool
    var payload_byte_errors: Int
    var data_symbol_count: Int
    var pad_bit_count: Int
    var tail_offset: Int
    var scrambler_seed: UInt8
    var amplitude_raw: Int64
    var reference_amplitude_raw: Int64
    var audit: FixedPHYAudit

    def __init__(
        out self,
        var payload_bytes: List[UInt8],
        var psdu_bits: List[UInt8],
        var fcs_bits: List[UInt8],
        var uncoded_data_bits: List[UInt8],
        var scrambled_data_bits: List[UInt8],
        var coded_bits: List[UInt8],
        var interleaved_bits: List[UInt8],
        var ltf_grid: List[ComplexRaw],
        var ltf_transmit_samples: List[ComplexRaw],
        var ltf_channel_samples: List[ComplexRaw],
        var ltf_received_bins: List[ComplexRaw],
        channel_estimate: ComplexRaw,
        var mapped_data_symbols: List[ComplexRaw],
        var data_frequency_grids: List[ComplexRaw],
        var data_transmit_samples: List[ComplexRaw],
        var data_channel_samples: List[ComplexRaw],
        var data_received_bins: List[ComplexRaw],
        var equalized_data_symbols: List[ComplexRaw],
        var interleaved_llrs_raw: List[Int64],
        var deinterleaved_llrs_raw: List[Int64],
        var soft_viterbi: FixedWifiBCCDecodeResult,
        var descrambled_data_bits: List[UInt8],
        var recovered_payload_bytes: List[UInt8],
        var recovered_fcs_bits: List[UInt8],
        fcs_expected: UInt64,
        fcs_recovered: UInt64,
        fcs_ok: Bool,
        service_ok: Bool,
        tail_ok: Bool,
        payload_byte_errors: Int,
        data_symbol_count: Int,
        pad_bit_count: Int,
        tail_offset: Int,
        scrambler_seed: UInt8,
        amplitude_raw: Int64,
        reference_amplitude_raw: Int64,
        audit: FixedPHYAudit,
    ):
        self.payload_bytes = payload_bytes^
        self.psdu_bits = psdu_bits^
        self.fcs_bits = fcs_bits^
        self.uncoded_data_bits = uncoded_data_bits^
        self.scrambled_data_bits = scrambled_data_bits^
        self.coded_bits = coded_bits^
        self.interleaved_bits = interleaved_bits^
        self.ltf_grid = ltf_grid^
        self.ltf_transmit_samples = ltf_transmit_samples^
        self.ltf_channel_samples = ltf_channel_samples^
        self.ltf_received_bins = ltf_received_bins^
        self.channel_estimate = channel_estimate
        self.mapped_data_symbols = mapped_data_symbols^
        self.data_frequency_grids = data_frequency_grids^
        self.data_transmit_samples = data_transmit_samples^
        self.data_channel_samples = data_channel_samples^
        self.data_received_bins = data_received_bins^
        self.equalized_data_symbols = equalized_data_symbols^
        self.interleaved_llrs_raw = interleaved_llrs_raw^
        self.deinterleaved_llrs_raw = deinterleaved_llrs_raw^
        self.soft_viterbi = soft_viterbi^
        self.descrambled_data_bits = descrambled_data_bits^
        self.recovered_payload_bytes = recovered_payload_bytes^
        self.recovered_fcs_bits = recovered_fcs_bits^
        self.fcs_expected = fcs_expected
        self.fcs_recovered = fcs_recovered
        self.fcs_ok = fcs_ok
        self.service_ok = service_ok
        self.tail_ok = tail_ok
        self.payload_byte_errors = payload_byte_errors
        self.data_symbol_count = data_symbol_count
        self.pad_bit_count = pad_bit_count
        self.tail_offset = tail_offset
        self.scrambler_seed = scrambler_seed
        self.amplitude_raw = amplitude_raw
        self.reference_amplitude_raw = reference_amplitude_raw
        self.audit = audit


struct _FixedWifiLegacyLTFEstimate(Movable):
    var bins: List[ComplexRaw]
    var channel: ComplexRaw

    def __init__(
        out self, var bins: List[ComplexRaw], channel: ComplexRaw
    ):
        self.bins = bins^
        self.channel = channel


def _validate_formats(formats: FixedPHYFormats) raises:
    for qformat in [
        formats.symbol,
        formats.time,
        formats.channel,
        formats.frequency,
        formats.accumulator,
        formats.reciprocal,
        formats.twiddle,
    ]:
        if qformat.rounding_mode != ROUND_NEAREST_AWAY:
            raise Error("fixed legacy Wi-Fi requires nearest-away rounding")
        if qformat.overflow_mode != OVERFLOW_SATURATE:
            raise Error("fixed legacy Wi-Fi rejects wrap arithmetic")
    if (
        formats.symbol.storage_bits > 30
        or formats.time.storage_bits > 30
        or formats.twiddle.storage_bits > 24
    ):
        raise Error("fixed legacy Wi-Fi formats exceed FFT guard widths")
    if (
        formats.symbol.storage_bits != 18
        or formats.symbol.fraction_bits != 14
        or formats.time.storage_bits != 18
        or formats.time.fraction_bits != 14
        or formats.channel.storage_bits != 18
        or formats.channel.fraction_bits != 14
        or formats.frequency.storage_bits != 24
        or formats.frequency.fraction_bits != 14
        or formats.accumulator.storage_bits != 30
        or formats.accumulator.fraction_bits != 20
        or formats.reciprocal.storage_bits != 24
        or formats.reciprocal.fraction_bits != 18
        or formats.twiddle.storage_bits != 18
        or formats.twiddle.fraction_bits != 16
    ):
        raise Error("fixed legacy Wi-Fi requires the audited default Q contract")


def _bin(subcarrier: Int) -> Int:
    return subcarrier if subcarrier >= 0 else 64 + subcarrier


def _reference_amplitude_raw(amplitude_raw: Int64) raises -> Int64:
    # sqrt(2) quantized to Q17.16.  The positive product makes nearest-away
    # equivalent to adding half an LSB before the declared 16-bit shift.
    return rounded_shift_right(
        amplitude_raw * Int64(92682), 16, ROUND_NEAREST_AWAY
    )


def _append_octet_bits(mut output: List[UInt8], octet: UInt8):
    for bit_index in range(8):
        output.append(UInt8((octet >> UInt8(bit_index)) & 1))


def _octets_to_bits(values: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * len(values))
    for index in range(len(values)):
        _append_octet_bits(result, values[index])
    return result^


def _bits_to_octets(values: Span[UInt8, ...]) raises -> List[UInt8]:
    if len(values) % 8 != 0:
        raise Error("fixed legacy Wi-Fi octet conversion needs full bytes")
    var result = List[UInt8](capacity=len(values) // 8)
    for offset in range(0, len(values), 8):
        var value = UInt8(0)
        for bit_index in range(8):
            if values[offset + bit_index] > 1:
                raise Error("fixed legacy Wi-Fi bits must be binary")
            value |= values[offset + bit_index] << UInt8(bit_index)
        result.append(value)
    return result^


def _fcs_bits(value: UInt64) -> List[UInt8]:
    var result = List[UInt8](capacity=FIXED_WIFI_LEGACY_FCS_BITS)
    for bit_index in range(FIXED_WIFI_LEGACY_FCS_BITS):
        result.append(UInt8((value >> UInt64(bit_index)) & 1))
    return result^


def _bits_to_u32(values: Span[UInt8, ...]) raises -> UInt64:
    if len(values) != FIXED_WIFI_LEGACY_FCS_BITS:
        raise Error("fixed legacy Wi-Fi FCS must contain 32 bits")
    var result = UInt64(0)
    for bit_index in range(FIXED_WIFI_LEGACY_FCS_BITS):
        if values[bit_index] > 1:
            raise Error("fixed legacy Wi-Fi FCS bits must be binary")
        result |= UInt64(values[bit_index]) << UInt64(bit_index)
    return result


def _copy_bits(
    values: Span[UInt8, ...], offset: Int, count: Int
) raises -> List[UInt8]:
    if offset < 0 or count < 0 or count > len(values) or offset > len(values) - count:
        raise Error("fixed legacy Wi-Fi bit slice is out of range")
    var result = List[UInt8](capacity=count)
    for index in range(count):
        result.append(values[offset + index])
    return result^


def _copy_i64(
    values: Span[Int64, ...], offset: Int, count: Int
) raises -> List[Int64]:
    if offset < 0 or count < 0 or count > len(values) or offset > len(values) - count:
        raise Error("fixed legacy Wi-Fi LLR slice is out of range")
    var result = List[Int64](capacity=count)
    for index in range(count):
        result.append(values[offset + index])
    return result^


def _copy_complex(
    values: Span[ComplexRaw, ...], offset: Int, count: Int
) raises -> List[ComplexRaw]:
    if offset < 0 or count < 0 or count > len(values) or offset > len(values) - count:
        raise Error("fixed legacy Wi-Fi complex slice is out of range")
    var result = List[ComplexRaw](capacity=count)
    for index in range(count):
        result.append(
            ComplexRaw(values[offset + index].re, values[offset + index].im)
        )
    return result^


def _deinterleave_llrs(block: Span[Int64, ...]) raises -> List[Int64]:
    if len(block) != FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL:
        raise Error("fixed legacy Wi-Fi LLR block must contain 96 values")
    # QPSK has s=max(N_BPSC/2,1)=1, so the second permutation is identity.
    # Retain the complete formula to keep this directly comparable to RTL.
    comptime n_cbps = FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL
    comptime s = 1
    var result = List[Int64](length=n_cbps, fill=Int64(0))
    for k in range(n_cbps):
        var first = (n_cbps // 16) * (k % 16) + k // 16
        var second = (
            s * (first // s)
            + (first + n_cbps - (16 * first) // n_cbps) % s
        )
        result[k] = block[second]
    return result^


def _build_ltf_grid(
    formats: FixedPHYFormats, amplitude_raw: Int64
) raises -> List[ComplexRaw]:
    var standard = wifi_legacy_ltf_spectrum_20mhz()
    if len(standard) != FIXED_WIFI_LEGACY_FFT_SIZE:
        raise Error("public legacy L-LTF spectrum must contain 64 bins")
    var result = List[ComplexRaw](capacity=FIXED_WIFI_LEGACY_FFT_SIZE)
    var active = 0
    for index in range(FIXED_WIFI_LEGACY_FFT_SIZE):
        var value = Int64(0)
        if standard[index].re > 0.5:
            value = amplitude_raw
            active += 1
        elif standard[index].re < -0.5:
            value = -amplitude_raw
            active += 1
        elif standard[index].re != 0.0 or standard[index].im != 0.0:
            raise Error("public legacy L-LTF must be real BPSK or zero")
        result.append(ComplexRaw(value, 0))
    if active != 52:
        raise Error("public legacy L-LTF must contain 52 active tones")
    return result^


def _build_ltf_waveform(
    grid: Span[ComplexRaw, ...], formats: FixedPHYFormats
) raises -> List[ComplexRaw]:
    # fixed_ofdm_modulate_raw(grid, CP=32) yields GI2 followed by the first
    # long symbol.  Append the same 64-sample symbol for the second L-LTF.
    var gi2_and_long = fixed_ofdm_modulate_raw(
        grid,
        formats.symbol,
        formats.time,
        formats.twiddle,
        32,
    )
    var result = List[ComplexRaw](capacity=160)
    for value in gi2_and_long:
        result.append(value)
    for index in range(64):
        result.append(gi2_and_long[32 + index])
    return result^


def _estimate_ltf_channel(
    received_samples: Span[ComplexRaw, ...],
    ltf_grid: Span[ComplexRaw, ...],
    formats: FixedPHYFormats,
) raises -> _FixedWifiLegacyLTFEstimate:
    if len(received_samples) != 160 or len(ltf_grid) != 64:
        raise Error("fixed legacy L-LTF dimensions are invalid")
    var first_time = _copy_complex(received_samples, 32, 64)
    var second_time = _copy_complex(received_samples, 96, 64)
    var first_bins = fixed_ofdm_demodulate_raw(
        Span(first_time), 64, 0, formats.time, formats.frequency, formats.twiddle
    )
    var second_bins = fixed_ofdm_demodulate_raw(
        Span(second_time), 64, 0, formats.time, formats.frequency, formats.twiddle
    )
    var averaged = List[ComplexRaw](capacity=64)
    for index in range(64):
        averaged.append(
            ComplexRaw(
                narrow_raw(
                    rounded_shift_right(
                        first_bins[index].re + second_bins[index].re,
                        1,
                        formats.frequency.rounding_mode,
                    ),
                    formats.frequency,
                ),
                narrow_raw(
                    rounded_shift_right(
                        first_bins[index].im + second_bins[index].im,
                        1,
                        formats.frequency.rounding_mode,
                    ),
                    formats.frequency,
                ),
            )
        )
    var known_active = List[ComplexRaw](capacity=52)
    var received_active = List[ComplexRaw](capacity=52)
    for index in range(64):
        if ltf_grid[index].re != 0 or ltf_grid[index].im != 0:
            known_active.append(ltf_grid[index])
            received_active.append(averaged[index])
    if len(known_active) != 52:
        raise Error("fixed legacy L-LTF active-tone count is invalid")
    var estimate = fixed_ls_flat_channel_raw(
        Span(received_active),
        Span(known_active),
        formats.frequency,
        formats.symbol,
        formats.accumulator,
        formats.reciprocal,
        formats.channel,
    )
    return _FixedWifiLegacyLTFEstimate(averaged^, estimate)


def fixed_wifi_legacy_reference(
    payload_bytes: Span[UInt8, ...],
    flat_channel: ComplexRaw,
    formats: FixedPHYFormats,
    amplitude_raw: Int64,
    *,
    scrambler_seed: UInt8 = UInt8(0x5D),
    metric_storage_bits: Int = 30,
) raises -> FixedWifiLegacyResult:
    """Run a standard-allocation legacy QPSK DATA frame through fixed RX.

    The input is the payload portion of the PSDU.  This reference appends the
    four FCS octets and therefore accepts at most 4091 payload octets under the
    4095-octet legacy PSDU bound.  Known timing and one flat complex channel
    are intentional scope boundaries.
    """
    _validate_formats(formats)
    if len(payload_bytes) > FIXED_WIFI_LEGACY_MAX_PSDU_OCTETS - 4:
        raise Error("fixed legacy Wi-Fi payload exceeds the 4095-octet PSDU")
    if (
        amplitude_raw < FIXED_WIFI_LEGACY_MIN_AMPLITUDE_RAW
        or amplitude_raw > FIXED_WIFI_LEGACY_MAX_AMPLITUDE_RAW
        or amplitude_raw > formats.symbol.max_raw()
        or amplitude_raw > formats.time.max_raw()
    ):
        raise Error("fixed legacy Wi-Fi QPSK amplitude is outside its audited range")
    if scrambler_seed == 0 or scrambler_seed > UInt8(0x7F):
        raise Error("fixed legacy Wi-Fi scrambler seed must be nonzero 7-bit")
    var viterbi_config = FixedWifiBCCViterbiConfig(
        formats.symbol, metric_storage_bits
    )
    var reference_amplitude_raw = _reference_amplitude_raw(amplitude_raw)
    if (
        reference_amplitude_raw > formats.symbol.max_raw()
        or reference_amplitude_raw > formats.time.max_raw()
    ):
        raise Error("fixed legacy Wi-Fi pilot/L-LTF amplitude exceeds its format")

    var payload = List[UInt8](capacity=len(payload_bytes))
    for index in range(len(payload_bytes)):
        payload.append(payload_bytes[index])
    var payload_bits = _octets_to_bits(payload_bytes)
    var fcs_expected = wifi_fcs(Span(payload_bits))
    var fcs_bits = _fcs_bits(fcs_expected)
    var psdu = payload_bits.copy()
    for bit in fcs_bits:
        psdu.append(bit)

    var required = FIXED_WIFI_LEGACY_SERVICE_BITS + len(psdu) + FIXED_WIFI_LEGACY_TAIL_BITS
    var symbol_count = (
        required + FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL - 1
    ) // FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL
    var data_bit_count = symbol_count * FIXED_WIFI_LEGACY_DATA_BITS_PER_SYMBOL
    var pad_count = data_bit_count - required
    var tail_offset = FIXED_WIFI_LEGACY_SERVICE_BITS + len(psdu)
    var uncoded = List[UInt8](length=FIXED_WIFI_LEGACY_SERVICE_BITS, fill=UInt8(0))
    for bit in psdu:
        uncoded.append(bit)
    for _ in range(FIXED_WIFI_LEGACY_TAIL_BITS + pad_count):
        uncoded.append(UInt8(0))
    var scrambled = wifi_scramble(Span(uncoded), scrambler_seed)
    for index in range(FIXED_WIFI_LEGACY_TAIL_BITS):
        scrambled[tail_offset + index] = UInt8(0)

    var coded = fixed_wifi_bcc_encode(Span(scrambled), terminate=False)
    if len(coded) != symbol_count * FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL:
        raise Error("fixed legacy Wi-Fi coded DATA length is inconsistent")
    var interleaved = List[UInt8](capacity=len(coded))
    for symbol_index in range(symbol_count):
        var block = _copy_bits(
            Span(coded),
            symbol_index * FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
            FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
        )
        var permuted = wifi_interleave(Span(block), 2)
        for bit in permuted:
            interleaved.append(bit)

    var carriers = wifi_data_subcarriers()
    if len(carriers) != FIXED_WIFI_LEGACY_DATA_TONES:
        raise Error("public legacy Wi-Fi data-tone table must contain 48 tones")
    var mapped = List[ComplexRaw](capacity=symbol_count * 48)
    var grids = List[ComplexRaw](capacity=symbol_count * 64)
    var transmit = List[ComplexRaw](capacity=symbol_count * 80)
    for symbol_index in range(symbol_count):
        var bit_block = _copy_bits(
            Span(interleaved),
            symbol_index * FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
            FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
        )
        var qpsk = fixed_qpsk_map_raw(
            Span(bit_block), formats.symbol, amplitude_raw
        )
        var grid = List[ComplexRaw](length=64, fill=ComplexRaw())
        for tone_index in range(48):
            grid[_bin(carriers[tone_index])] = qpsk[tone_index]
            mapped.append(qpsk[tone_index])
        var polarity = wifi_pilot_polarity(symbol_index)
        var pilot = (
            reference_amplitude_raw
            if polarity > 0.0
            else -reference_amplitude_raw
        )
        grid[_bin(-21)] = ComplexRaw(pilot, 0)
        grid[_bin(-7)] = ComplexRaw(pilot, 0)
        grid[_bin(7)] = ComplexRaw(pilot, 0)
        grid[_bin(21)] = ComplexRaw(-pilot, 0)
        for value in grid:
            grids.append(value)
        var samples = fixed_ofdm_modulate_raw(
            Span(grid),
            formats.symbol,
            formats.time,
            formats.twiddle,
            FIXED_WIFI_LEGACY_CP_LENGTH,
        )
        for value in samples:
            transmit.append(value)

    var ltf_grid = _build_ltf_grid(formats, reference_amplitude_raw)
    var ltf_tx = _build_ltf_waveform(Span(ltf_grid), formats)
    var ltf_channel = fixed_flat_channel_raw(
        Span(ltf_tx),
        formats.time,
        flat_channel,
        formats.channel,
        formats.time,
    )
    var ltf_estimate = _estimate_ltf_channel(
        Span(ltf_channel), Span(ltf_grid), formats
    )
    var channel_estimate = ltf_estimate.channel
    var ltf_bins = ltf_estimate.bins.copy()

    var through_channel = fixed_flat_channel_raw(
        Span(transmit),
        formats.time,
        flat_channel,
        formats.channel,
        formats.time,
    )
    var received_bins = List[ComplexRaw](capacity=symbol_count * 64)
    var equalized_data = List[ComplexRaw](capacity=symbol_count * 48)
    for symbol_index in range(symbol_count):
        var samples = _copy_complex(Span(through_channel), symbol_index * 80, 80)
        var bins = fixed_ofdm_demodulate_raw(
            Span(samples),
            64,
            16,
            formats.time,
            formats.frequency,
            formats.twiddle,
        )
        for value in bins:
            received_bins.append(value)
        var equalized = fixed_equalize_flat_raw(
            Span(bins),
            formats.frequency,
            channel_estimate,
            formats.channel,
            formats.accumulator,
            formats.reciprocal,
            formats.symbol,
        )
        for tone_index in range(48):
            equalized_data.append(equalized[_bin(carriers[tone_index])])

    var interleaved_llrs = fixed_qpsk_llrs_raw(
        Span(equalized_data), formats.symbol, formats.symbol
    )
    var deinterleaved_llrs = List[Int64](capacity=len(interleaved_llrs))
    for symbol_index in range(symbol_count):
        var block = _copy_i64(
            Span(interleaved_llrs),
            symbol_index * FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
            FIXED_WIFI_LEGACY_CODED_BITS_PER_SYMBOL,
        )
        var restored = _deinterleave_llrs(Span(block))
        for value in restored:
            deinterleaved_llrs.append(value)

    var soft = fixed_wifi_bcc_viterbi_decode_soft(
        Span(deinterleaved_llrs),
        viterbi_config,
        terminate=False,
    )
    if len(soft.bits) != data_bit_count:
        raise Error("fixed legacy Wi-Fi Viterbi length is inconsistent")
    var decoded_scrambled = soft.bits.copy()
    var descrambled = wifi_scramble(Span(decoded_scrambled), scrambler_seed)

    var service_ok = True
    for index in range(FIXED_WIFI_LEGACY_SERVICE_BITS):
        service_ok = service_ok and descrambled[index] == 0
    var tail_ok = True
    for index in range(FIXED_WIFI_LEGACY_TAIL_BITS):
        tail_ok = tail_ok and decoded_scrambled[tail_offset + index] == 0
    var recovered_payload_bits = _copy_bits(
        Span(descrambled), FIXED_WIFI_LEGACY_SERVICE_BITS, len(payload_bits)
    )
    var recovered_payload = _bits_to_octets(Span(recovered_payload_bits))
    var recovered_fcs = _copy_bits(
        Span(descrambled),
        FIXED_WIFI_LEGACY_SERVICE_BITS + len(payload_bits),
        FIXED_WIFI_LEGACY_FCS_BITS,
    )
    var fcs_recovered = _bits_to_u32(Span(recovered_fcs))
    var recalculated_fcs = wifi_fcs(Span(recovered_payload_bits))
    var errors = 0
    for index in range(len(payload)):
        if recovered_payload[index] != payload[index]:
            errors += 1
    var audit = fixed_qpsk_float64_audit(
        Span(interleaved),
        Span(equalized_data),
        formats.symbol,
        Float64(amplitude_raw) / Float64(formats.symbol.scale()),
    )
    return FixedWifiLegacyResult(
        payload^,
        psdu^,
        fcs_bits^,
        uncoded^,
        scrambled^,
        coded^,
        interleaved^,
        ltf_grid^,
        ltf_tx^,
        ltf_channel^,
        ltf_bins^,
        channel_estimate,
        mapped^,
        grids^,
        transmit^,
        through_channel^,
        received_bins^,
        equalized_data^,
        interleaved_llrs^,
        deinterleaved_llrs^,
        soft^,
        descrambled^,
        recovered_payload^,
        recovered_fcs^,
        fcs_expected,
        fcs_recovered,
        fcs_recovered == recalculated_fcs and fcs_recovered == fcs_expected,
        service_ok,
        tail_ok,
        errors,
        symbol_count,
        pad_count,
        tail_offset,
        scrambler_seed,
        amplitude_raw,
        reference_amplitude_raw,
        audit,
    )


def _u8_raw(values: Span[UInt8, ...]) -> List[Int64]:
    var result = List[Int64](capacity=len(values))
    for index in range(len(values)):
        result.append(Int64(values[index]))
    return result^


def _int_raw(values: Span[Int, ...]) -> List[Int64]:
    var result = List[Int64](capacity=len(values))
    for index in range(len(values)):
        result.append(Int64(values[index]))
    return result^


def _mix_word(mut state: UInt64, value: UInt64):
    for byte_index in range(8):
        state ^= UInt64(UInt8((value >> UInt64(8 * byte_index)) & UInt64(0xFF)))
        state *= UInt64(1099511628211)


def fixed_wifi_legacy_result_checksum(result: FixedWifiLegacyResult) -> UInt64:
    """FNV-compose the numeric contract and every exported raw checkpoint."""
    var payload_raw = _u8_raw(Span(result.payload_bytes))
    var psdu_raw = _u8_raw(Span(result.psdu_bits))
    var fcs_raw = _u8_raw(Span(result.fcs_bits))
    var uncoded_raw = _u8_raw(Span(result.uncoded_data_bits))
    var scrambled_raw = _u8_raw(Span(result.scrambled_data_bits))
    var coded_raw = _u8_raw(Span(result.coded_bits))
    var interleaved_raw = _u8_raw(Span(result.interleaved_bits))
    var decoded_raw = _u8_raw(Span(result.soft_viterbi.bits))
    var descrambled_raw = _u8_raw(Span(result.descrambled_data_bits))
    var recovered_raw = _u8_raw(Span(result.recovered_payload_bytes))
    var recovered_fcs_raw = _u8_raw(Span(result.recovered_fcs_bits))
    var predecessors = _int_raw(Span(result.soft_viterbi.survivor_predecessors))
    var decisions = _u8_raw(Span(result.soft_viterbi.survivor_decisions))
    var reachable = _u8_raw(Span(result.soft_viterbi.final_reachable))
    var state = UInt64(14695981039346656037)
    for scalar in [
        UInt64(2),
        UInt64(result.data_symbol_count),
        UInt64(result.pad_bit_count),
        UInt64(result.tail_offset),
        UInt64(result.scrambler_seed),
        UInt64(result.amplitude_raw),
        UInt64(result.reference_amplitude_raw),
        result.fcs_expected,
        result.fcs_recovered,
        UInt64(result.fcs_ok),
        UInt64(result.service_ok),
        UInt64(result.tail_ok),
        UInt64(result.payload_byte_errors),
        UInt64(result.soft_viterbi.final_state),
        UInt64(result.soft_viterbi.final_normalized_metric_raw),
        UInt64(result.soft_viterbi.saturation_count),
    ]:
        _mix_word(state, scalar)
    for checksum in [
        fixed_raw_checksum(Span(payload_raw)),
        fixed_raw_checksum(Span(psdu_raw)),
        fixed_raw_checksum(Span(fcs_raw)),
        fixed_raw_checksum(Span(uncoded_raw)),
        fixed_raw_checksum(Span(scrambled_raw)),
        fixed_raw_checksum(Span(coded_raw)),
        fixed_raw_checksum(Span(interleaved_raw)),
        complex_raw_checksum(Span(result.ltf_grid)),
        complex_raw_checksum(Span(result.ltf_transmit_samples)),
        complex_raw_checksum(Span(result.ltf_channel_samples)),
        complex_raw_checksum(Span(result.ltf_received_bins)),
        complex_raw_checksum(Span(result.mapped_data_symbols)),
        complex_raw_checksum(Span(result.data_frequency_grids)),
        complex_raw_checksum(Span(result.data_transmit_samples)),
        complex_raw_checksum(Span(result.data_channel_samples)),
        complex_raw_checksum(Span(result.data_received_bins)),
        complex_raw_checksum(Span(result.equalized_data_symbols)),
        fixed_raw_checksum(Span(result.interleaved_llrs_raw)),
        fixed_raw_checksum(Span(result.deinterleaved_llrs_raw)),
        fixed_raw_checksum(Span(predecessors)),
        fixed_raw_checksum(Span(decisions)),
        fixed_raw_checksum(Span(result.soft_viterbi.final_metrics_raw)),
        fixed_raw_checksum(Span(reachable)),
        fixed_raw_checksum(Span(result.soft_viterbi.normalization_offsets_raw)),
        fixed_raw_checksum(Span(decoded_raw)),
        fixed_raw_checksum(Span(descrambled_raw)),
        fixed_raw_checksum(Span(recovered_raw)),
        fixed_raw_checksum(Span(recovered_fcs_raw)),
    ]:
        _mix_word(state, checksum)
    _mix_word(
        state,
        complex_raw_checksum(Span([result.channel_estimate])),
    )
    return state


def fixed_wifi_legacy_canonical_rtl_vectors(
    result: FixedWifiLegacyResult, formats: FixedPHYFormats
) raises -> String:
    """Serialize every raw stage with Q, shape, stride, scale, and checksum."""
    _validate_formats(formats)
    var bit_q = QFormat(2, 0, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var byte_q = QFormat(9, 0, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var state_q = QFormat(8, 0, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE)
    var metric_q = QFormat(
        result.soft_viterbi.metric_storage_bits,
        result.soft_viterbi.metric_fraction_bits,
        ROUND_NEAREST_AWAY,
        OVERFLOW_SATURATE,
    )
    var payload_raw = _u8_raw(Span(result.payload_bytes))
    var psdu_raw = _u8_raw(Span(result.psdu_bits))
    var fcs_raw = _u8_raw(Span(result.fcs_bits))
    var uncoded_raw = _u8_raw(Span(result.uncoded_data_bits))
    var scrambled_raw = _u8_raw(Span(result.scrambled_data_bits))
    var coded_raw = _u8_raw(Span(result.coded_bits))
    var interleaved_raw = _u8_raw(Span(result.interleaved_bits))
    var predecessors = _int_raw(Span(result.soft_viterbi.survivor_predecessors))
    var decisions = _u8_raw(Span(result.soft_viterbi.survivor_decisions))
    var reachable = _u8_raw(Span(result.soft_viterbi.final_reachable))
    var decoded_raw = _u8_raw(Span(result.soft_viterbi.bits))
    var descrambled_raw = _u8_raw(Span(result.descrambled_data_bits))
    var recovered_raw = _u8_raw(Span(result.recovered_payload_bytes))
    var recovered_fcs_raw = _u8_raw(Span(result.recovered_fcs_bits))
    var estimate: List[ComplexRaw] = [result.channel_estimate]
    var control_raw: List[Int64] = [
        Int64(2),
        Int64(FIXED_WIFI_LEGACY_FFT_SIZE),
        Int64(FIXED_WIFI_LEGACY_CP_LENGTH),
        Int64(FIXED_WIFI_LEGACY_DATA_TONES),
        Int64(FIXED_WIFI_LEGACY_PILOT_TONES),
        Int64(result.data_symbol_count),
        Int64(result.pad_bit_count),
        Int64(result.tail_offset),
        Int64(result.scrambler_seed),
        result.amplitude_raw,
        result.reference_amplitude_raw,
        Int64(result.fcs_expected),
        Int64(result.fcs_recovered),
        Int64(result.fcs_ok),
        Int64(result.service_ok),
        Int64(result.tail_ok),
        Int64(result.payload_byte_errors),
        Int64(result.soft_viterbi.steps),
        Int64(result.soft_viterbi.final_state),
        result.soft_viterbi.final_normalized_metric_raw,
        Int64(result.soft_viterbi.saturation_count),
    ]
    var control_q = QFormat(
        34, 0, ROUND_NEAREST_AWAY, OVERFLOW_SATURATE
    )
    var text = String()
    text.write(
        "MWDSP-FIXED-WIFI-LEGACY-V2\n",
        "testcase=fixed-wifi-legacy-qpsk-r12\n",
        "version=2\n",
        "fft_size=64\n",
        "data_cp=16\n",
        "ltf_layout=GI32+2x64\n",
        "data_tones=48\n",
        "pilot_tones=-21,-7,7,21\n",
        "modulation=QPSK\n",
        "bcc=K7-R1/2-133-171\n",
        "service_bits=16\n",
        "tail_bits=6-reset-after-scramble\n",
        "pad_bits=", result.pad_bit_count, "\n",
        "data_symbols=", result.data_symbol_count, "\n",
        "scrambler_seed=", result.scrambler_seed, "\n",
        "qpsk_component_amplitude_raw=", result.amplitude_raw, "\n",
        "pilot_ltf_amplitude_raw=", result.reference_amplitude_raw, "\n",
        "pilot_ltf_scale=sqrt2-q17.16-92682\n",
        "ifft_schedule=6x-right-shift-1\n",
        "fft_schedule=6x-right-shift-0\n",
        "rounding=nearest-away\n",
        "overflow=saturate\n",
        "wrap=disabled\n",
        "viterbi_survivor_shape=", result.soft_viterbi.steps, "x64\n",
        "checksum_algorithm=fnv1a64-int64-little-endian\n",
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "frame-control",
            Span(control_raw),
            control_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "payload-octets",
            Span(payload_raw),
            byte_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "psdu-bits",
            Span(psdu_raw),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "fcs-bits",
            Span(fcs_raw),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "uncoded-data-bits",
            Span(uncoded_raw),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "scrambled-tail-reset-bits",
            Span(scrambled_raw),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "bcc-coded-bits",
            Span(coded_raw),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "per-symbol-interleaved-bits",
            Span(interleaved_raw),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "legacy-ltf-grid",
            Span(result.ltf_grid),
            formats.symbol,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "legacy-ltf-transmit",
            Span(result.ltf_transmit_samples),
            formats.time,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "legacy-ltf-channel",
            Span(result.ltf_channel_samples),
            formats.time,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "legacy-ltf-averaged-fft",
            Span(result.ltf_received_bins),
            formats.frequency,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "legacy-ltf-flat-ls",
            Span(estimate),
            formats.channel,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "qpsk-data-tones",
            Span(result.mapped_data_symbols),
            formats.symbol,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "data-frequency-grids",
            Span(result.data_frequency_grids),
            formats.symbol,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "data-ifft-cp",
            Span(result.data_transmit_samples),
            formats.time,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "data-flat-channel",
            Span(result.data_channel_samples),
            formats.time,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "data-fft-bins",
            Span(result.data_received_bins),
            formats.frequency,
            version=2,
        )
    )
    text.write(
        serialize_complex_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "data-flat-zf",
            Span(result.equalized_data_symbols),
            formats.symbol,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "interleaved-qpsk-llrs",
            Span(result.interleaved_llrs_raw),
            formats.symbol,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "deinterleaved-qpsk-llrs",
            Span(result.deinterleaved_llrs_raw),
            formats.symbol,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "soft-survivor-predecessors",
            Span(predecessors),
            state_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "soft-survivor-decisions",
            Span(decisions),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "soft-final-metrics",
            Span(result.soft_viterbi.final_metrics_raw),
            metric_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "soft-final-reachable",
            Span(reachable),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "soft-metric-normalization",
            Span(result.soft_viterbi.normalization_offsets_raw),
            metric_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "decoded-scrambled-data",
            Span(decoded_raw),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "descrambled-data",
            Span(descrambled_raw),
            bit_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "recovered-payload-octets",
            Span(recovered_raw),
            byte_q,
            version=2,
        )
    )
    text.write(
        serialize_fixed_vector(
            "fixed-wifi-legacy-qpsk-r12",
            "recovered-fcs-bits",
            Span(recovered_fcs_raw),
            bit_q,
            version=2,
        )
    )
    text.write(
        "MWDSP-FIXED-WIFI-LEGACY-CHECKSUM-V2\nchecksum=",
        fixed_wifi_legacy_result_checksum(result),
        "\n",
    )
    return text^
