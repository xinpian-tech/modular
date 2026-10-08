"""Independent stage-composition oracles for fixed composite wrappers."""

from std.collections import Span
from std.testing import assert_equal, TestSuite
from wireless_dsp.numerics.complex_fixed import ComplexRaw
from wireless_dsp.numerics.quantization import (
    dequantize_raw,
    narrow_raw,
    rounded_shift_right,
)
from wireless_dsp.backend.fixed_phy_reference import (
    FixedPHYFormats,
    FixedPHYResult,
    fixed_equalize_flat_raw,
    fixed_flat_channel_raw,
    fixed_ls_flat_channel_raw,
    fixed_ofdm_demodulate_raw,
    fixed_ofdm_modulate_raw,
    fixed_phy_default_formats,
    fixed_phy_one_symbol_reference,
    fixed_qpsk_float64_audit,
    fixed_qpsk_hard_bits,
    fixed_qpsk_llrs_raw,
    fixed_qpsk_map_raw,
)
from wireless_dsp.backend.fixed_wifi_bcc_reference import (
    FixedWifiBCCDecodeResult,
    FixedWifiBCCViterbiConfig,
    fixed_wifi_bcc_encode,
    fixed_wifi_bcc_viterbi_decode_hard,
    fixed_wifi_bcc_viterbi_decode_soft,
)
from wireless_dsp.backend.fixed_wifi_phy_reference import (
    fixed_wifi_bcc_ofdm_reference,
)
from wireless_dsp.backend.fixed_wifi_legacy_reference import (
    fixed_wifi_legacy_reference,
)


comptime _LEGACY_FFT_SIZE = 64
comptime _LEGACY_CP_LENGTH = 16
comptime _LEGACY_DATA_TONES = 48
comptime _LEGACY_CODED_BITS_PER_SYMBOL = 96
comptime _LEGACY_DATA_BITS_PER_SYMBOL = 48
comptime _LEGACY_SERVICE_BITS = 16
comptime _LEGACY_TAIL_BITS = 6
comptime _LEGACY_FCS_BITS = 32


def _legacy_oracle_octet_bits(values: Span[UInt8, ...]) -> List[UInt8]:
    """Convert octets to the IEEE on-air LSB-first order locally."""
    var result = List[UInt8](capacity=8 * len(values))
    for value_index in range(len(values)):
        var value = values[value_index]
        for bit_index in range(8):
            result.append(UInt8((value >> UInt8(bit_index)) & UInt8(1)))
    return result^


def _legacy_oracle_crc32(values: Span[UInt8, ...]) -> UInt64:
    """Independent reflected byte-at-a-time IEEE CRC-32 implementation."""
    var crc = UInt64(0xFFFFFFFF)
    for value_index in range(len(values)):
        var octet = UInt64(values[value_index])
        for _ in range(8):
            var mix = (crc ^ octet) & UInt64(1)
            crc >>= 1
            if mix != 0:
                crc ^= UInt64(0xEDB88320)
            octet >>= 1
    return crc ^ UInt64(0xFFFFFFFF)


def _legacy_oracle_fcs_bits(value: UInt64) -> List[UInt8]:
    var result = List[UInt8](capacity=_LEGACY_FCS_BITS)
    for bit_index in range(_LEGACY_FCS_BITS):
        result.append(UInt8((value >> UInt64(bit_index)) & UInt64(1)))
    return result^


def _legacy_oracle_bits_to_octets(
    values: Span[UInt8, ...]
) -> List[UInt8]:
    var result = List[UInt8](capacity=len(values) // 8)
    for offset in range(0, len(values), 8):
        var value = UInt8(0)
        for bit_index in range(8):
            value |= values[offset + bit_index] << UInt8(bit_index)
        result.append(value)
    return result^


def _legacy_oracle_bits_to_u32(values: Span[UInt8, ...]) -> UInt64:
    var result = UInt64(0)
    for bit_index in range(_LEGACY_FCS_BITS):
        result |= UInt64(values[bit_index]) << UInt64(bit_index)
    return result


def _legacy_oracle_scramble(
    bits: Span[UInt8, ...], seed: UInt8
) -> List[UInt8]:
    """Local x^7+x^4+1 additive scrambler/descrambler."""
    var state = seed
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        var feedback = ((state >> 6) ^ (state >> 3)) & UInt8(1)
        result.append(bits[index] ^ feedback)
        state = ((state << 1) & UInt8(0x7E)) | feedback
    return result^


def _legacy_oracle_parity(value: Int) -> UInt8:
    var remaining = value
    var parity = UInt8(0)
    while remaining != 0:
        parity ^= UInt8(remaining & 1)
        remaining >>= 1
    return parity


def _legacy_oracle_bcc(bits: Span[UInt8, ...]) -> List[UInt8]:
    """Independent K=7, rate-1/2 octal-133/171 shift register."""
    var state = 0
    var result = List[UInt8](capacity=2 * len(bits))
    for index in range(len(bits)):
        state = ((state << 1) | Int(bits[index])) & 0x7F
        result.append(_legacy_oracle_parity(state & 0o133))
        result.append(_legacy_oracle_parity(state & 0o171))
    return result^


def _legacy_oracle_slice_bits(
    values: Span[UInt8, ...], offset: Int, count: Int
) -> List[UInt8]:
    var result = List[UInt8](capacity=count)
    for index in range(count):
        result.append(values[offset + index])
    return result^


def _legacy_oracle_slice_i64(
    values: Span[Int64, ...], offset: Int, count: Int
) -> List[Int64]:
    var result = List[Int64](capacity=count)
    for index in range(count):
        result.append(values[offset + index])
    return result^


def _legacy_oracle_slice_complex(
    values: Span[ComplexRaw, ...], offset: Int, count: Int
) -> List[ComplexRaw]:
    var result = List[ComplexRaw](capacity=count)
    for index in range(count):
        var value = values[offset + index]
        result.append(ComplexRaw(value.re, value.im))
    return result^


def _legacy_oracle_interleave(block: Span[UInt8, ...]) -> List[UInt8]:
    """Local IEEE QPSK permutation for N_CBPS=96 and s=1."""
    var result = List[UInt8](length=96, fill=UInt8(0))
    for k in range(96):
        var first = 6 * (k % 16) + k // 16
        # The second QPSK permutation is identity because s=1; retain the
        # standard expression so this is directly reviewable against IEEE RTL.
        var second = first + (first + 96 - (16 * first) // 96) % 1
        result[second] = block[k]
    return result^


def _legacy_oracle_deinterleave(block: Span[Int64, ...]) -> List[Int64]:
    var result = List[Int64](length=96, fill=Int64(0))
    for k in range(96):
        var first = 6 * (k % 16) + k // 16
        var second = first + (first + 96 - (16 * first) // 96) % 1
        result[k] = block[second]
    return result^


def _legacy_oracle_bin(subcarrier: Int) -> Int:
    return subcarrier if subcarrier >= 0 else _LEGACY_FFT_SIZE + subcarrier


def _legacy_oracle_data_subcarriers() -> List[Int]:
    var result = List[Int](capacity=_LEGACY_DATA_TONES)
    for subcarrier in range(-26, 27):
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


def _legacy_oracle_pilot_polarity(symbol_index: Int) -> Int:
    var state = UInt8(0x7F)
    var polarity = 1
    for _ in range(symbol_index + 1):
        var feedback = ((state >> 6) ^ (state >> 3)) & UInt8(1)
        polarity = 1 if feedback == 0 else -1
        state = ((state << 1) & UInt8(0x7E)) | feedback
    return polarity


def _legacy_oracle_qpsk_map(
    bits: Span[UInt8, ...], amplitude_raw: Int64
) -> List[ComplexRaw]:
    var result = List[ComplexRaw](capacity=len(bits) // 2)
    for index in range(0, len(bits), 2):
        result.append(
            ComplexRaw(
                -amplitude_raw if bits[index] == 1 else amplitude_raw,
                -amplitude_raw if bits[index + 1] == 1 else amplitude_raw,
            )
        )
    return result^


def _legacy_oracle_ltf_values() -> List[Int]:
    """IEEE legacy L-LTF BPSK row for k=-26..26, including DC zero."""
    return [
        1, 1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 1, 1, -1,
        -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 0, 1, -1, -1, 1, 1,
        -1, 1, -1, 1, -1, -1, -1, -1, -1, 1, 1, -1, -1, 1, -1,
        1, -1, 1, 1, 1, 1,
    ]


def _legacy_oracle_ltf_grid(
    reference_amplitude_raw: Int64
) -> List[ComplexRaw]:
    var values = _legacy_oracle_ltf_values()
    var result = List[ComplexRaw](
        length=_LEGACY_FFT_SIZE, fill=ComplexRaw()
    )
    for subcarrier in range(-26, 27):
        result[_legacy_oracle_bin(subcarrier)] = ComplexRaw(
            Int64(values[subcarrier + 26]) * reference_amplitude_raw, 0
        )
    return result^


def _assert_phy_equal(
    actual: FixedPHYResult, expected: FixedPHYResult
) raises:
    assert_equal(actual.transform_size, expected.transform_size)
    assert_equal(actual.cyclic_prefix, expected.cyclic_prefix)
    assert_equal(actual.pilot_symbols, expected.pilot_symbols)
    assert_equal(actual.amplitude_raw, expected.amplitude_raw)
    assert_equal(actual.mapped_symbols, expected.mapped_symbols)
    assert_equal(actual.transmit_samples, expected.transmit_samples)
    assert_equal(actual.channel_samples, expected.channel_samples)
    assert_equal(actual.received_bins, expected.received_bins)
    assert_equal(actual.channel_estimate, expected.channel_estimate)
    assert_equal(actual.equalized_symbols, expected.equalized_symbols)
    assert_equal(actual.decoded_bits, expected.decoded_bits)
    assert_equal(actual.audit.evm_rms, expected.audit.evm_rms)
    assert_equal(actual.audit.bit_errors, expected.audit.bit_errors)
    assert_equal(actual.audit.bits_checked, expected.audit.bits_checked)


def _assert_viterbi_equal(
    actual: FixedWifiBCCDecodeResult,
    expected: FixedWifiBCCDecodeResult,
) raises:
    assert_equal(actual.bits, expected.bits)
    assert_equal(
        actual.survivor_predecessors, expected.survivor_predecessors
    )
    assert_equal(actual.survivor_decisions, expected.survivor_decisions)
    assert_equal(actual.final_metrics_raw, expected.final_metrics_raw)
    assert_equal(actual.final_reachable, expected.final_reachable)
    assert_equal(
        actual.normalization_offsets_raw,
        expected.normalization_offsets_raw,
    )
    assert_equal(actual.final_state, expected.final_state)
    assert_equal(
        actual.final_normalized_metric_raw,
        expected.final_normalized_metric_raw,
    )
    assert_equal(actual.saturation_count, expected.saturation_count)
    assert_equal(actual.steps, expected.steps)
    assert_equal(actual.terminated, expected.terminated)
    assert_equal(actual.metric_storage_bits, expected.metric_storage_bits)
    assert_equal(actual.metric_fraction_bits, expected.metric_fraction_bits)


def _compose_fixed_phy(
    bits: Span[UInt8, ...],
    transform_size: Int,
    cyclic_prefix: Int,
    flat_channel: ComplexRaw,
    amplitude_raw: Int64,
    pilot_symbols: Int,
) raises -> FixedPHYResult:
    """Compose the wrapper contract only from independently tested kernels."""
    var formats = fixed_phy_default_formats()
    var mapped = fixed_qpsk_map_raw(
        bits, formats.symbol, amplitude_raw
    )
    var transmit = fixed_ofdm_modulate_raw(
        Span(mapped),
        formats.symbol,
        formats.time,
        formats.twiddle,
        cyclic_prefix,
    )
    var channel_samples = fixed_flat_channel_raw(
        Span(transmit),
        formats.time,
        flat_channel,
        formats.channel,
        formats.time,
    )
    var received = fixed_ofdm_demodulate_raw(
        Span(channel_samples),
        transform_size,
        cyclic_prefix,
        formats.time,
        formats.frequency,
        formats.twiddle,
    )
    var estimate = fixed_ls_flat_channel_raw(
        Span(received[:pilot_symbols]),
        Span(mapped[:pilot_symbols]),
        formats.frequency,
        formats.symbol,
        formats.accumulator,
        formats.reciprocal,
        formats.channel,
    )
    var equalized = fixed_equalize_flat_raw(
        Span(received),
        formats.frequency,
        estimate,
        formats.channel,
        formats.accumulator,
        formats.reciprocal,
        formats.symbol,
    )
    var decoded = fixed_qpsk_hard_bits(
        Span(equalized), formats.symbol
    )
    var audit = fixed_qpsk_float64_audit(
        bits,
        Span(equalized),
        formats.symbol,
        dequantize_raw(amplitude_raw, formats.symbol),
    )
    return FixedPHYResult(
        transform_size,
        cyclic_prefix,
        pilot_symbols,
        amplitude_raw,
        mapped^,
        transmit^,
        channel_samples^,
        received^,
        estimate,
        equalized^,
        decoded^,
        audit,
    )


def test_fixed_phy_wrapper_matches_independent_stage_composition() raises:
    var bits: List[UInt8] = [
        0, 1, 1, 0, 1, 1, 0, 0,
        1, 0, 0, 1, 0, 0, 1, 1,
    ]
    var formats = fixed_phy_default_formats()
    var actual = fixed_phy_one_symbol_reference(
        Span(bits),
        8,
        2,
        ComplexRaw(12288, -4096),
        formats,
        8192,
        3,
    )
    var expected = _compose_fixed_phy(
        Span(bits), 8, 2, ComplexRaw(12288, -4096), 8192, 3
    )
    _assert_phy_equal(actual, expected)


def test_fixed_wifi_bcc_wrapper_matches_independent_stage_composition() raises:
    var payload = List[UInt8](capacity=58)
    for index in range(58):
        payload.append(UInt8((17 * index + index // 4 + 1) & 1))
    var formats = fixed_phy_default_formats()
    var actual = fixed_wifi_bcc_ofdm_reference(
        Span(payload),
        64,
        16,
        ComplexRaw(12288, 4096),
        formats,
        8192,
        pilot_symbols=5,
    )

    var coded = fixed_wifi_bcc_encode(Span(payload))
    var expected_phy = _compose_fixed_phy(
        Span(coded), 64, 16, ComplexRaw(12288, 4096), 8192, 5
    )
    var expected_llrs = fixed_qpsk_llrs_raw(
        Span(expected_phy.equalized_symbols),
        formats.symbol,
        formats.symbol,
    )
    var expected_hard = fixed_wifi_bcc_viterbi_decode_hard(
        Span(expected_phy.decoded_bits), metric_storage_bits=30
    )
    var expected_soft = fixed_wifi_bcc_viterbi_decode_soft(
        Span(expected_llrs), FixedWifiBCCViterbiConfig(formats.symbol, 30)
    )

    assert_equal(actual.payload_bits, payload)
    assert_equal(actual.coded_bits, coded)
    assert_equal(actual.llrs_raw, expected_llrs)
    _assert_phy_equal(actual.phy, expected_phy)
    _assert_viterbi_equal(actual.hard_viterbi, expected_hard)
    _assert_viterbi_equal(actual.soft_viterbi, expected_soft)
    assert_equal(actual.payload_bit_errors, 0)


def _assert_fixed_wifi_legacy_fixture(
    payload_bytes: Span[UInt8, ...],
    flat_channel: ComplexRaw,
    formats: FixedPHYFormats,
    amplitude_raw: Int64,
    scrambler_seed: UInt8,
) raises:
    """Rebuild every legacy wrapper checkpoint without reading its stages."""
    var payload = List[UInt8](capacity=len(payload_bytes))
    for index in range(len(payload_bytes)):
        payload.append(payload_bytes[index])
    var payload_bits = _legacy_oracle_octet_bits(payload_bytes)
    var fcs_expected = _legacy_oracle_crc32(payload_bytes)
    var fcs_bits = _legacy_oracle_fcs_bits(fcs_expected)
    var psdu = payload_bits.copy()
    for bit in fcs_bits:
        psdu.append(bit)

    var required = _LEGACY_SERVICE_BITS + len(psdu) + _LEGACY_TAIL_BITS
    var symbol_count = (
        required + _LEGACY_DATA_BITS_PER_SYMBOL - 1
    ) // _LEGACY_DATA_BITS_PER_SYMBOL
    var data_bit_count = symbol_count * _LEGACY_DATA_BITS_PER_SYMBOL
    var pad_count = data_bit_count - required
    var tail_offset = _LEGACY_SERVICE_BITS + len(psdu)
    var uncoded = List[UInt8](
        length=_LEGACY_SERVICE_BITS, fill=UInt8(0)
    )
    for bit in psdu:
        uncoded.append(bit)
    for _ in range(_LEGACY_TAIL_BITS + pad_count):
        uncoded.append(UInt8(0))
    var scrambled = _legacy_oracle_scramble(Span(uncoded), scrambler_seed)
    for index in range(_LEGACY_TAIL_BITS):
        scrambled[tail_offset + index] = UInt8(0)

    var coded = _legacy_oracle_bcc(Span(scrambled))
    var interleaved = List[UInt8](capacity=len(coded))
    for symbol_index in range(symbol_count):
        var coded_block = _legacy_oracle_slice_bits(
            Span(coded),
            symbol_index * _LEGACY_CODED_BITS_PER_SYMBOL,
            _LEGACY_CODED_BITS_PER_SYMBOL,
        )
        var permuted = _legacy_oracle_interleave(Span(coded_block))
        for bit in permuted:
            interleaved.append(bit)

    # sqrt(2) in Q17.16, rounded nearest-away for this positive product.
    var reference_amplitude_raw = (
        amplitude_raw * Int64(92682) + Int64(1 << 15)
    ) >> 16
    var carriers = _legacy_oracle_data_subcarriers()
    var mapped = List[ComplexRaw](capacity=symbol_count * _LEGACY_DATA_TONES)
    var data_grids = List[ComplexRaw](capacity=symbol_count * _LEGACY_FFT_SIZE)
    var data_transmit = List[ComplexRaw](
        capacity=symbol_count * (_LEGACY_FFT_SIZE + _LEGACY_CP_LENGTH)
    )
    for symbol_index in range(symbol_count):
        var interleaved_block = _legacy_oracle_slice_bits(
            Span(interleaved),
            symbol_index * _LEGACY_CODED_BITS_PER_SYMBOL,
            _LEGACY_CODED_BITS_PER_SYMBOL,
        )
        var qpsk = _legacy_oracle_qpsk_map(
            Span(interleaved_block), amplitude_raw
        )
        var grid = List[ComplexRaw](
            length=_LEGACY_FFT_SIZE, fill=ComplexRaw()
        )
        for tone_index in range(_LEGACY_DATA_TONES):
            grid[_legacy_oracle_bin(carriers[tone_index])] = qpsk[tone_index]
            mapped.append(qpsk[tone_index])
        var pilot = (
            reference_amplitude_raw
            if _legacy_oracle_pilot_polarity(symbol_index) > 0
            else -reference_amplitude_raw
        )
        grid[_legacy_oracle_bin(-21)] = ComplexRaw(pilot, 0)
        grid[_legacy_oracle_bin(-7)] = ComplexRaw(pilot, 0)
        grid[_legacy_oracle_bin(7)] = ComplexRaw(pilot, 0)
        grid[_legacy_oracle_bin(21)] = ComplexRaw(-pilot, 0)
        for value in grid:
            data_grids.append(value)
        var samples = fixed_ofdm_modulate_raw(
            Span(grid),
            formats.symbol,
            formats.time,
            formats.twiddle,
            _LEGACY_CP_LENGTH,
        )
        for value in samples:
            data_transmit.append(value)

    # Build the L-LTF from the independent static IEEE row, then use the
    # separately verified fixed arithmetic primitives for TX, channel and RX.
    var ltf_grid = _legacy_oracle_ltf_grid(reference_amplitude_raw)
    var gi2_and_long = fixed_ofdm_modulate_raw(
        Span(ltf_grid),
        formats.symbol,
        formats.time,
        formats.twiddle,
        32,
    )
    var ltf_transmit = List[ComplexRaw](capacity=160)
    for value in gi2_and_long:
        ltf_transmit.append(value)
    for index in range(_LEGACY_FFT_SIZE):
        ltf_transmit.append(gi2_and_long[32 + index])
    var ltf_channel = fixed_flat_channel_raw(
        Span(ltf_transmit),
        formats.time,
        flat_channel,
        formats.channel,
        formats.time,
    )
    var first_ltf_time = _legacy_oracle_slice_complex(
        Span(ltf_channel), 32, _LEGACY_FFT_SIZE
    )
    var second_ltf_time = _legacy_oracle_slice_complex(
        Span(ltf_channel), 96, _LEGACY_FFT_SIZE
    )
    var first_ltf_bins = fixed_ofdm_demodulate_raw(
        Span(first_ltf_time),
        _LEGACY_FFT_SIZE,
        0,
        formats.time,
        formats.frequency,
        formats.twiddle,
    )
    var second_ltf_bins = fixed_ofdm_demodulate_raw(
        Span(second_ltf_time),
        _LEGACY_FFT_SIZE,
        0,
        formats.time,
        formats.frequency,
        formats.twiddle,
    )
    var ltf_received_bins = List[ComplexRaw](capacity=_LEGACY_FFT_SIZE)
    for index in range(_LEGACY_FFT_SIZE):
        ltf_received_bins.append(
            ComplexRaw(
                narrow_raw(
                    rounded_shift_right(
                        first_ltf_bins[index].re
                        + second_ltf_bins[index].re,
                        1,
                        formats.frequency.rounding_mode,
                    ),
                    formats.frequency,
                ),
                narrow_raw(
                    rounded_shift_right(
                        first_ltf_bins[index].im
                        + second_ltf_bins[index].im,
                        1,
                        formats.frequency.rounding_mode,
                    ),
                    formats.frequency,
                ),
            )
        )
    var known_ltf = List[ComplexRaw](capacity=52)
    var received_ltf = List[ComplexRaw](capacity=52)
    for index in range(_LEGACY_FFT_SIZE):
        if ltf_grid[index].re != 0 or ltf_grid[index].im != 0:
            known_ltf.append(ltf_grid[index])
            received_ltf.append(ltf_received_bins[index])
    var channel_estimate = fixed_ls_flat_channel_raw(
        Span(received_ltf),
        Span(known_ltf),
        formats.frequency,
        formats.symbol,
        formats.accumulator,
        formats.reciprocal,
        formats.channel,
    )

    var data_channel = fixed_flat_channel_raw(
        Span(data_transmit),
        formats.time,
        flat_channel,
        formats.channel,
        formats.time,
    )
    var data_received_bins = List[ComplexRaw](
        capacity=symbol_count * _LEGACY_FFT_SIZE
    )
    var equalized_data = List[ComplexRaw](
        capacity=symbol_count * _LEGACY_DATA_TONES
    )
    for symbol_index in range(symbol_count):
        var time_symbol = _legacy_oracle_slice_complex(
            Span(data_channel),
            symbol_index * (_LEGACY_FFT_SIZE + _LEGACY_CP_LENGTH),
            _LEGACY_FFT_SIZE + _LEGACY_CP_LENGTH,
        )
        var bins = fixed_ofdm_demodulate_raw(
            Span(time_symbol),
            _LEGACY_FFT_SIZE,
            _LEGACY_CP_LENGTH,
            formats.time,
            formats.frequency,
            formats.twiddle,
        )
        for value in bins:
            data_received_bins.append(value)
        var equalized = fixed_equalize_flat_raw(
            Span(bins),
            formats.frequency,
            channel_estimate,
            formats.channel,
            formats.accumulator,
            formats.reciprocal,
            formats.symbol,
        )
        for tone_index in range(_LEGACY_DATA_TONES):
            equalized_data.append(
                equalized[_legacy_oracle_bin(carriers[tone_index])]
            )

    var interleaved_llrs = fixed_qpsk_llrs_raw(
        Span(equalized_data), formats.symbol, formats.symbol
    )
    var deinterleaved_llrs = List[Int64](capacity=len(interleaved_llrs))
    for symbol_index in range(symbol_count):
        var llr_block = _legacy_oracle_slice_i64(
            Span(interleaved_llrs),
            symbol_index * _LEGACY_CODED_BITS_PER_SYMBOL,
            _LEGACY_CODED_BITS_PER_SYMBOL,
        )
        var restored = _legacy_oracle_deinterleave(Span(llr_block))
        for value in restored:
            deinterleaved_llrs.append(value)
    var soft = fixed_wifi_bcc_viterbi_decode_soft(
        Span(deinterleaved_llrs),
        FixedWifiBCCViterbiConfig(formats.symbol, 30),
        terminate=False,
    )
    var decoded_scrambled = soft.bits.copy()
    var descrambled = _legacy_oracle_scramble(
        Span(decoded_scrambled), scrambler_seed
    )
    var service_ok = True
    for index in range(_LEGACY_SERVICE_BITS):
        service_ok = service_ok and descrambled[index] == 0
    var tail_ok = True
    for index in range(_LEGACY_TAIL_BITS):
        tail_ok = tail_ok and decoded_scrambled[tail_offset + index] == 0
    var recovered_payload_bits = _legacy_oracle_slice_bits(
        Span(descrambled), _LEGACY_SERVICE_BITS, len(payload_bits)
    )
    var recovered_payload = _legacy_oracle_bits_to_octets(
        Span(recovered_payload_bits)
    )
    var recovered_fcs_bits = _legacy_oracle_slice_bits(
        Span(descrambled),
        _LEGACY_SERVICE_BITS + len(payload_bits),
        _LEGACY_FCS_BITS,
    )
    var fcs_recovered = _legacy_oracle_bits_to_u32(Span(recovered_fcs_bits))
    var fcs_recalculated = _legacy_oracle_crc32(Span(recovered_payload))
    var fcs_ok = (
        fcs_recovered == fcs_recalculated and fcs_recovered == fcs_expected
    )
    var payload_byte_errors = 0
    for index in range(len(payload)):
        if recovered_payload[index] != payload[index]:
            payload_byte_errors += 1
    var audit = fixed_qpsk_float64_audit(
        Span(interleaved),
        Span(equalized_data),
        formats.symbol,
        Float64(amplitude_raw) / Float64(formats.symbol.scale()),
    )

    # Only now execute the composite wrapper.  No expected stage above reads
    # or derives from any wrapper-owned intermediate.
    var actual = fixed_wifi_legacy_reference(
        payload_bytes,
        flat_channel,
        formats,
        amplitude_raw,
        scrambler_seed=scrambler_seed,
        metric_storage_bits=30,
    )
    assert_equal(actual.payload_bytes, payload)
    assert_equal(actual.psdu_bits, psdu)
    assert_equal(actual.fcs_bits, fcs_bits)
    assert_equal(actual.uncoded_data_bits, uncoded)
    assert_equal(actual.scrambled_data_bits, scrambled)
    assert_equal(actual.coded_bits, coded)
    assert_equal(actual.interleaved_bits, interleaved)
    assert_equal(actual.ltf_grid, ltf_grid)
    assert_equal(actual.ltf_transmit_samples, ltf_transmit)
    assert_equal(actual.ltf_channel_samples, ltf_channel)
    assert_equal(actual.ltf_received_bins, ltf_received_bins)
    assert_equal(actual.channel_estimate, channel_estimate)
    assert_equal(actual.mapped_data_symbols, mapped)
    assert_equal(actual.data_frequency_grids, data_grids)
    assert_equal(actual.data_transmit_samples, data_transmit)
    assert_equal(actual.data_channel_samples, data_channel)
    assert_equal(actual.data_received_bins, data_received_bins)
    assert_equal(actual.equalized_data_symbols, equalized_data)
    assert_equal(actual.interleaved_llrs_raw, interleaved_llrs)
    assert_equal(actual.deinterleaved_llrs_raw, deinterleaved_llrs)
    _assert_viterbi_equal(actual.soft_viterbi, soft)
    assert_equal(actual.descrambled_data_bits, descrambled)
    assert_equal(actual.recovered_payload_bytes, recovered_payload)
    assert_equal(actual.recovered_fcs_bits, recovered_fcs_bits)
    assert_equal(actual.fcs_expected, fcs_expected)
    assert_equal(actual.fcs_recovered, fcs_recovered)
    assert_equal(actual.fcs_ok, fcs_ok)
    assert_equal(actual.service_ok, service_ok)
    assert_equal(actual.tail_ok, tail_ok)
    assert_equal(actual.payload_byte_errors, payload_byte_errors)
    assert_equal(actual.data_symbol_count, symbol_count)
    assert_equal(actual.pad_bit_count, pad_count)
    assert_equal(actual.tail_offset, tail_offset)
    assert_equal(actual.scrambler_seed, scrambler_seed)
    assert_equal(actual.amplitude_raw, amplitude_raw)
    assert_equal(actual.reference_amplitude_raw, reference_amplitude_raw)
    assert_equal(actual.audit.evm_rms, audit.evm_rms)
    assert_equal(actual.audit.bit_errors, audit.bit_errors)
    assert_equal(actual.audit.bits_checked, audit.bits_checked)


def test_fixed_wifi_legacy_wrapper_matches_independent_stage_composition() raises:
    var formats = fixed_phy_default_formats()
    var empty = List[UInt8]()
    _assert_fixed_wifi_legacy_fixture(
        Span(empty),
        ComplexRaw(12288, -4096),
        formats,
        8192,
        UInt8(0x5D),
    )
    var one_byte: List[UInt8] = [UInt8(0xA5)]
    _assert_fixed_wifi_legacy_fixture(
        Span(one_byte),
        ComplexRaw(12288, -4096),
        formats,
        8192,
        UInt8(0x5D),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
