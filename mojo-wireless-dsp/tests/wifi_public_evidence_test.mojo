"""Strict public-surface evidence for all 76 Wi-Fi functions.

Static points are transcribed from IEEE 802.11 carrier/tone tables and the
ISO/IEEE CRC-32 check vector.  Numeric checks use test-local Float64 formulas;
round trips are used only as seeded permutation/link properties, never as the
sole oracle for an implementation.
"""

from std.collections import Span
from std.math import cos, sin, sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import nan
from wireless_dsp.core import Complex64
from wireless_dsp.channel import apply_cfo
from wireless_dsp.dsp import ofdm_demodulate, ofdm_modulate
from wireless_dsp.wireless.wifi import (
    WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE, WIFI_PHY_EHT,
    wifi_scramble, wifi_interleave, wifi_deinterleave,
    wifi_data_subcarriers, wifi_map_legacy_symbol,
    wifi_extract_legacy_symbol, wifi_ls_channel_estimate, wifi_equalize,
    wifi_stf_detect, wifi_stf_coarse_cfo, wifi_pilot_polarity,
    wifi_legacy_signal_bits, wifi_parse_legacy_signal, wifi_fcs,
    wifi_mcs_profile, wifi_ofdm_profile, wifi_guard_interval_samples,
    wifi_coded_bits_per_symbol, wifi_data_bits_per_symbol,
    wifi_ru_profile, wifi_max_ru_count, wifi_ru_coded_bits_per_symbol,
    wifi_ru_data_bits_per_symbol, wifi_ru_requires_ldpc,
    wifi_ru_subcarriers_20mhz, wifi_ru_pilot_subcarriers_20mhz,
    wifi_ru_data_subcarriers_20mhz, wifi_ru_allocations_disjoint_20mhz,
    wifi_map_ru_symbol_20mhz, wifi_extract_ru_data_20mhz,
    wifi_extract_ru_pilots_20mhz, wifi_bcc_puncture_pattern,
    wifi_bcc_puncture, wifi_bcc_depuncture_llrs,
    wifi_bcc_interleaver_profile, wifi_bcc_interleave_block,
    wifi_bcc_deinterleave_block, wifi_estimate_pilot_phase,
    wifi_correct_pilot_phase, wifi_ldpc_profile, wifi_ldpc_base_shifts,
    wifi_ldpc_sparse_graph, wifi_ldpc_syndrome_ok, wifi_ldpc_encode,
    wifi_ldpc_decode, wifi_ldpc_rate_match_block,
    wifi_ldpc_rate_recover_block, wifi_ltf_values_20mhz,
    wifi_ltf_spectrum_20mhz, wifi_ltf_waveform_20mhz,
    wifi_ltf_channel_estimate_20mhz, wifi_data_pilot_subcarriers_20mhz,
    wifi_data_pilots_20mhz, wifi_ht_vht_data_subcarriers_20mhz,
    wifi_map_ht_vht_symbol_20mhz, wifi_extract_ht_vht_data_20mhz,
    wifi_extract_ht_vht_pilots_20mhz, wifi_ldpc_tone_mapping_distance,
    wifi_ldpc_tone_permutation, wifi_ldpc_tone_map_bits,
    wifi_ldpc_tone_demap_llrs, wifi_bcc_tx_20mhz, wifi_bcc_rx_20mhz,
    wifi_ldpc_tx_20mhz, wifi_ldpc_rx_20mhz, wifi_stf_spectrum_20mhz,
    wifi_stf_short_symbol_20mhz, wifi_stf_waveform_20mhz,
    wifi_legacy_signal_tx_20mhz, wifi_acquisition_tx_20mhz,
    WifiAcquisitionChannelConfig, wifi_acquisition_apply_channel_20mhz,
    wifi_ltf_fine_timing_20mhz, wifi_ltf_fine_cfo_20mhz,
    wifi_acquisition_rx_20mhz,
)
from wireless_dsp.wireless.wifi.he_eht_acquisition import (
    wifi_legacy_ltf_spectrum_20mhz,
    wifi_legacy_ltf_waveform_20mhz,
)


comptime TIGHT = 1.0e-12
comptime FFT_TOLERANCE = 2.0e-10
comptime TWO_PI = 6.283185307179586476925286766559


def _seeded_bits(count: Int, seed: UInt64) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=count)
    for _ in range(count):
        state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
        result.append(UInt8((state >> UInt64(63)) & UInt64(1)))
    return result^


def _payload(octets: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * octets)
    for i in range(8 * octets):
        result.append(UInt8((13 * i + i // 5 + salt) & 1))
    return result^


def _scaled_ltf(family: Int, channel: Complex64) raises -> List[Complex64]:
    var ltf = wifi_ltf_waveform_20mhz(family)
    var result = List[Complex64](capacity=len(ltf))
    for value in ltf:
        result.append(value * channel)
    return result^


def _assert_complex_lists_close(
    actual: List[Complex64], expected: List[Complex64], tolerance: Float64
) raises:
    assert_equal(len(actual), len(expected))
    for i in range(len(actual)):
        assert_true(abs(actual[i].re - expected[i].re) <= tolerance)
        assert_true(abs(actual[i].im - expected[i].im) <= tolerance)


def _naive_ofdm_symbol(
    spectrum: Span[Complex64, ...], cyclic_prefix: Int
) -> List[Complex64]:
    """Test-only O(N^2) inverse DFT, independent of the production FFT."""
    var time = List[Complex64](capacity=len(spectrum))
    for sample_index in range(len(spectrum)):
        var value = Complex64(0.0, 0.0)
        for bin_index in range(len(spectrum)):
            var angle = (
                TWO_PI * Float64(sample_index * bin_index)
                / Float64(len(spectrum))
            )
            value = value + Complex64(
                spectrum[bin_index].re, spectrum[bin_index].im
            ) * Complex64(cos(angle), sin(angle))
        time.append(Complex64(
            value.re / Float64(len(spectrum)),
            value.im / Float64(len(spectrum)),
        ))
    var result = List[Complex64](capacity=len(time) + cyclic_prefix)
    for i in range(len(time) - cyclic_prefix, len(time)):
        result.append(time[i])
    for value in time:
        result.append(value)
    return result^


def _legacy_carriers_static() -> List[Int]:
    return [
        -26, -25, -24, -23, -22, -20, -19, -18,
        -17, -16, -15, -14, -13, -12, -11, -10,
        -9, -8, -6, -5, -4, -3, -2, -1,
        1, 2, 3, 4, 5, 6, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 22, 23, 24, 25, 26,
    ]


def _ht_ltf_values_static() -> List[Int]:
    """IEEE HT-LTF row for k=-28..28, transcribed in the test."""
    return [
        1, 1, 1, 1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 1,
        1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 0,
        1, -1, -1, 1, 1, -1, 1, -1, 1, -1, -1, -1, -1, -1,
        1, 1, -1, -1, 1, -1, 1, -1, 1, 1, 1, 1, -1, -1,
    ]


def _manual_legacy_deinterleave(
    interleaved: Span[UInt8, ...], bpsc: Int
) -> List[UInt8]:
    var ncbps = 48 * bpsc
    var s = max(bpsc // 2, 1)
    var result = List[UInt8](length=ncbps, fill=UInt8(0))
    for k in range(ncbps):
        var first = (ncbps // 16) * (k % 16) + k // 16
        var second = (
            s * (first // s)
            + (first + ncbps - (16 * first) // ncbps) % s
        )
        result[k] = interleaved[second]
    return result^


def _manual_fcs(bits: Span[UInt8, ...]) -> UInt64:
    var register = UInt64(0xFFFFFFFF)
    for i in range(len(bits)):
        var feedback = (register & UInt64(1)) ^ UInt64(bits[i])
        register >>= UInt64(1)
        if feedback != 0:
            register ^= UInt64(0xEDB88320)
    return register ^ UInt64(0xFFFFFFFF)


def _manual_scramble(bits: Span[UInt8, ...], seed: UInt8) -> List[UInt8]:
    var state = seed
    var result = List[UInt8](capacity=len(bits))
    for i in range(len(bits)):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        result.append(bits[i] ^ feedback)
        state = ((state << 1) & 0x7E) | feedback
    return result^


def _parity(value: Int) -> UInt8:
    var remaining = value
    var result = UInt8(0)
    while remaining != 0:
        result ^= UInt8(remaining & 1)
        remaining >>= 1
    return result


def _manual_bcc_unterminated(bits: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=2 * len(bits))
    var register = 0
    for i in range(len(bits)):
        register = ((register << 1) | Int(bits[i])) & 0x7F
        result.append(_parity(register & 0o133))
        result.append(_parity(register & 0o171))
    return result^


def _manual_puncture_bits(
    bits: Span[UInt8, ...], pattern: Span[UInt8, ...]
) -> List[UInt8]:
    var result = List[UInt8]()
    for i in range(len(bits)):
        if pattern[i % len(pattern)] == 1:
            result.append(bits[i])
    return result^


def _manual_depuncture(
    llrs: Span[Float64, ...], pattern: Span[UInt8, ...], mother_length: Int
) -> List[Float64]:
    var result = List[Float64](capacity=mother_length)
    var source = 0
    for i in range(mother_length):
        if pattern[i % len(pattern)] == 1:
            result.append(llrs[source])
            source += 1
        else:
            result.append(0.0)
    return result^


def _manual_interleave(
    bits: Span[UInt8, ...], bpsc: Int, columns: Int,
    rows_per_modulation_bit: Int, rotation_subcarriers: Int,
    spatial_stream_index: Int,
) -> List[UInt8]:
    var ncbps = len(bits)
    var rows = rows_per_modulation_bit * bpsc
    var s = max(bpsc // 2, 1)
    var rotation = (
        ((2 * spatial_stream_index) % 3 + 3 * (spatial_stream_index // 3))
        * rotation_subcarriers * bpsc
    ) % ncbps
    var result = List[UInt8](length=ncbps, fill=UInt8(0))
    for k in range(ncbps):
        var first = rows * (k % columns) + k // columns
        var second = (
            s * (first // s)
            + (first + ncbps - (columns * first) // ncbps) % s
        )
        result[(second + ncbps - rotation) % ncbps] = bits[k]
    return result^


def _manual_tone_map_bits(
    bits: Span[UInt8, ...], bpsc: Int, nsd: Int, distance: Int,
    subblocks: Int,
) -> List[UInt8]:
    var block_nsd = nsd // subblocks
    var result = List[UInt8](length=len(bits), fill=UInt8(0))
    for block in range(subblocks):
        for source in range(block_nsd):
            var destination = (
                distance * (source % (block_nsd // distance))
                + (source * distance) // block_nsd
            )
            for bit in range(bpsc):
                result[(block * block_nsd + destination) * bpsc + bit] = bits[
                    (block * block_nsd + source) * bpsc + bit
                ]
    return result^


def _manual_signal_bits(
    rate: Span[UInt8, ...], length_octets: Int
) -> List[UInt8]:
    var result = List[UInt8](capacity=24)
    var parity = UInt8(0)
    for i in range(len(rate)):
        result.append(rate[i])
        parity ^= rate[i]
    result.append(UInt8(0))
    for shift in range(12):
        var bit = UInt8((length_octets >> shift) & 1)
        result.append(bit)
        parity ^= bit
    result.append(parity)
    for _ in range(6):
        result.append(UInt8(0))
    return result^


def _manual_pilot_polarity(symbol_index: Int) -> Float64:
    """Test-local x^7+x^4+1 recurrence for the complete 127-symbol row."""
    var state = UInt8(0x7F)
    var polarity = 1.0
    for _ in range(symbol_index + 1):
        var feedback = ((state >> 6) ^ (state >> 3)) & 1
        polarity = 1.0 if feedback == 0 else -1.0
        state = ((state << 1) & 0x7E) | feedback
    return polarity


def _manual_data_pilots_20mhz(
    family: Int, symbol_index: Int
) raises -> List[Complex64]:
    var polarity = 1.0
    var base: List[Int]
    if family == WIFI_PHY_HT or family == WIFI_PHY_VHT:
        base = [1, 1, 1, -1]
        polarity = _manual_pilot_polarity(symbol_index)
    elif family == WIFI_PHY_HE or family == WIFI_PHY_EHT:
        base = [1, 1, 1, -1, -1, 1, 1, 1]
        if family == WIFI_PHY_EHT:
            polarity = _manual_pilot_polarity(symbol_index)
    else:
        raise Error("unknown manual pilot family")
    var rotation = symbol_index % len(base) if len(base) == 8 else 0
    var result = List[Complex64](capacity=len(base))
    for i in range(len(base)):
        result.append(
            Complex64(polarity * Float64(base[(i + rotation) % len(base)]))
        )
    return result^


def _static_ltf_values(
    count: Int,
    active_words: Span[UInt64, ...],
    negative_words: Span[UInt64, ...],
) -> List[Int]:
    """Decode a compact test-only transcription of a published LTF row."""
    var result = List[Int](capacity=count)
    for i in range(count):
        var mask = UInt64(1) << UInt64(i % 64)
        var active = (active_words[i // 64] & mask) != 0
        var negative = (negative_words[i // 64] & mask) != 0
        result.append(-1 if negative else (1 if active else 0))
    return result^


def _independent_ltf_values(family: Int) raises -> List[Int]:
    if family == WIFI_PHY_HT or family == WIFI_PHY_VHT:
        var active: List[UInt64] = [UInt64(0x01FFFFFFEFFFFFFF)]
        var negative: List[UInt64] = [UInt64(0x018567D4C0A60530)]
        return _static_ltf_values(57, Span(active), Span(negative))
    if family == WIFI_PHY_HE or family == WIFI_PHY_EHT:
        var active: List[UInt64] = [
            UInt64(0xFFFFFFFFFFFFFFFF),
            UInt64(0xF1FFFFFFFFFFFFFF),
            UInt64(0xFFFFFFFFFFFFFFFF),
            UInt64(0x001FFFFFFFFFFFFF),
        ]
        var negative: List[UInt64] = [
            UInt64(0xF21D84D0A79F622B),
            UInt64(0x502E3EA237CFD7A6),
            UInt64(0x09ECBD7E7D88AD89),
            UInt64(0x00057720C35E9BC8),
        ]
        return _static_ltf_values(245, Span(active), Span(negative))
    raise Error("unknown test LTF family")


def _independent_ltf_spectrum(family: Int) raises -> List[Complex64]:
    var values = _independent_ltf_values(family)
    var fft_size = (
        64 if family == WIFI_PHY_HT or family == WIFI_PHY_VHT else 256
    )
    var first = -28 if fft_size == 64 else -122
    var result = List[Complex64](
        length=fft_size, fill=Complex64(0.0, 0.0)
    )
    for i in range(len(values)):
        var subcarrier = first + i
        result[
            subcarrier if subcarrier >= 0 else fft_size + subcarrier
        ] = Complex64(Float64(values[i]))
    return result^


def _append_manual_range(mut result: List[Int], first: Int, last: Int):
    for subcarrier in range(first, last + 1):
        result.append(subcarrier)


def _manual_ru_subcarriers_20mhz(
    ru_tones: Int, ru_index: Int
) raises -> List[Int]:
    """Independent range-table transcription of the complete 20 MHz plan."""
    var result = List[Int](capacity=ru_tones)
    if ru_tones == 26:
        var first: List[Int] = [-121, -95, -68, -42, -16, 17, 43, 70, 96]
        var last: List[Int] = [-96, -70, -43, -17, 16, 42, 68, 95, 121]
        if ru_index < 0 or ru_index >= 9:
            raise Error("manual RU-26 index")
        if ru_index == 4:
            _append_manual_range(result, -16, -4)
            _append_manual_range(result, 4, 16)
        else:
            _append_manual_range(result, first[ru_index], last[ru_index])
    elif ru_tones == 52:
        var first: List[Int] = [-121, -68, 17, 70]
        var last: List[Int] = [-70, -17, 68, 121]
        if ru_index < 0 or ru_index >= 4:
            raise Error("manual RU-52 index")
        _append_manual_range(result, first[ru_index], last[ru_index])
    elif ru_tones == 106:
        if ru_index == 0:
            _append_manual_range(result, -122, -17)
        elif ru_index == 1:
            _append_manual_range(result, 17, 122)
        else:
            raise Error("manual RU-106 index")
    elif ru_tones == 242 and ru_index == 0:
        _append_manual_range(result, -122, -2)
        _append_manual_range(result, 2, 122)
    else:
        raise Error("manual unsupported 20 MHz RU")
    return result^


def _manual_ru_pilots_20mhz(
    ru_tones: Int, ru_index: Int
) raises -> List[Int]:
    var occupied = _manual_ru_subcarriers_20mhz(ru_tones, ru_index)
    var candidates: List[Int] = [
        -116, -90, -48, -22, 22, 48, 90, 116
    ]
    if ru_tones == 26 or ru_tones == 52:
        candidates = [
            -116, -102, -90, -76, -62, -48, -36, -22, -10,
            10, 22, 36, 48, 62, 76, 90, 102, 116,
        ]
    var result = List[Int]()
    for candidate in candidates:
        for subcarrier in occupied:
            if subcarrier == candidate:
                result.append(candidate)
                break
    return result^


def _manual_ru_data_subcarriers_20mhz(
    ru_tones: Int, ru_index: Int
) raises -> List[Int]:
    var occupied = _manual_ru_subcarriers_20mhz(ru_tones, ru_index)
    var pilots = _manual_ru_pilots_20mhz(ru_tones, ru_index)
    var result = List[Int]()
    for subcarrier in occupied:
        var is_pilot = False
        for pilot in pilots:
            if subcarrier == pilot:
                is_pilot = True
                break
        if not is_pilot:
            result.append(subcarrier)
    return result^


def _manual_ru_allocations_disjoint_20mhz(
    ru_tones: Span[Int, ...], ru_indices: Span[Int, ...]
) raises -> Bool:
    for left in range(len(ru_tones)):
        var left_tones = _manual_ru_subcarriers_20mhz(
            ru_tones[left], ru_indices[left]
        )
        for right in range(left):
            var right_tones = _manual_ru_subcarriers_20mhz(
                ru_tones[right], ru_indices[right]
            )
            for left_tone in left_tones:
                for right_tone in right_tones:
                    if left_tone == right_tone:
                        return False
    return True


def _assert_max_ru_rows(
    family: Int,
    bandwidth_mhz: Int,
    ru_sizes: Span[Int, ...],
    expected_counts: Span[Int, ...],
) raises:
    assert_equal(len(ru_sizes), len(expected_counts))
    for i in range(len(ru_sizes)):
        assert_equal(
            wifi_max_ru_count(family, bandwidth_mhz, ru_sizes[i]),
            expected_counts[i],
        )


def _assert_complete_ru_tone_row(ru_tones: Int, ru_index: Int) raises:
    var expected_occupied = _manual_ru_subcarriers_20mhz(
        ru_tones, ru_index
    )
    var expected_pilots = _manual_ru_pilots_20mhz(ru_tones, ru_index)
    var expected_data = _manual_ru_data_subcarriers_20mhz(
        ru_tones, ru_index
    )
    assert_equal(
        wifi_ru_subcarriers_20mhz(ru_tones, ru_index), expected_occupied
    )
    assert_equal(
        wifi_ru_pilot_subcarriers_20mhz(ru_tones, ru_index),
        expected_pilots,
    )
    assert_equal(
        wifi_ru_data_subcarriers_20mhz(ru_tones, ru_index), expected_data
    )


def test_legacy_static_analytic_float64_and_seeded_properties() raises:
    # IEEE x^7+x^4+1 first 32 output chips for seed 0x5d and all-zero input.
    var zeros = List[UInt8](length=32, fill=UInt8(0))
    var expected: List[UInt8] = [
        0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1,
        1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 1,
    ]
    assert_equal(wifi_scramble(Span(zeros), UInt8(0x5D)), expected)
    var carriers = wifi_data_subcarriers()
    var static_carriers = _legacy_carriers_static()
    assert_equal(carriers, static_carriers)
    for i in range(len(carriers)):
        assert_true(carriers[i] != 0)
        assert_true(
            carriers[i] != -21 and carriers[i] != -7
            and carriers[i] != 7 and carriers[i] != 21
        )
        if i > 0:
            assert_true(carriers[i] > carriers[i - 1])
    # Exhaust the full polarity period and a second period against a separate
    # recurrence.  Periodicity is property evidence, not a production
    # round-trip.
    for symbol_index in range(254):
        var expected_polarity = _manual_pilot_polarity(symbol_index)
        assert_equal(wifi_pilot_polarity(symbol_index), expected_polarity)
        if symbol_index >= 127:
            assert_equal(
                wifi_pilot_polarity(symbol_index),
                wifi_pilot_polarity(symbol_index - 127),
            )

    for bpsc in [1, 2, 4, 6]:
        var bits = _seeded_bits(48 * bpsc, UInt64(0x80211000 + bpsc))
        var interleaved = wifi_interleave(Span(bits), bpsc)
        # Independent index equation pins more than an inverse round trip.
        var k = 17
        var ncbps = 48 * bpsc
        var s = max(bpsc // 2, 1)
        var first = (ncbps // 16) * (k % 16) + k // 16
        var second = s * (first // s) + (first + ncbps - (16 * first) // ncbps) % s
        assert_equal(interleaved[second], bits[k])
        assert_equal(wifi_deinterleave(Span(interleaved), bpsc), bits)
        # An arbitrary interleaved-domain input is compared with the explicit
        # IEEE inverse-index equation, not with wifi_interleave.
        var received_order = _seeded_bits(
            48 * bpsc, UInt64(0xDE1A0000 + bpsc)
        )
        assert_equal(
            wifi_deinterleave(Span(received_order), bpsc),
            _manual_legacy_deinterleave(Span(received_order), bpsc),
        )

    var tones = List[Complex64](capacity=48)
    for i in range(48):
        tones.append(Complex64(Float64(i) / 17.0 - 1.0, Float64(i % 7) / 11.0))
    var waveform = wifi_map_legacy_symbol(Span(tones), symbol_index=4)
    # Independent IEEE carrier list plus a naive O(N^2) IFFT pins the mapper.
    var expected_spectrum = List[Complex64](
        length=64, fill=Complex64(0.0, 0.0)
    )
    for i in range(48):
        var subcarrier = static_carriers[i]
        var bin_index = subcarrier if subcarrier >= 0 else 64 + subcarrier
        expected_spectrum[bin_index] = tones[i]
    # Published legacy pilot row at symbol four has polarity -1.
    expected_spectrum[64 - 21] = Complex64(-1.0)
    expected_spectrum[64 - 7] = Complex64(-1.0)
    expected_spectrum[7] = Complex64(-1.0)
    expected_spectrum[21] = Complex64(1.0)
    var expected_waveform = _naive_ofdm_symbol(Span(expected_spectrum), 16)
    _assert_complex_lists_close(waveform, expected_waveform, FFT_TOLERANCE)
    var spectrum = ofdm_demodulate(Span(waveform), 64, 16)
    assert_true(abs(spectrum[64 - 21].re + 1.0) <= FFT_TOLERANCE)
    var extracted = wifi_extract_legacy_symbol(Span(waveform))
    for i in range(48):
        assert_true(abs(extracted[i].re - tones[i].re) <= FFT_TOLERANCE)
        assert_true(abs(extracted[i].im - tones[i].im) <= FFT_TOLERANCE)
    # Feed the extractor a waveform built only by the test-local naive IFFT.
    var independently_extracted = wifi_extract_legacy_symbol(
        Span(expected_waveform)
    )
    _assert_complex_lists_close(independently_extracted, tones, FFT_TOLERANCE)

    var known: List[Complex64] = [Complex64(1.0, -2.0), Complex64(-0.5, 0.25)]
    var h: List[Complex64] = [Complex64(0.75, -0.2), Complex64(-0.4, 0.3)]
    var received = List[Complex64](capacity=2)
    for i in range(2):
        received.append(known[i] * h[i])
    var estimate = wifi_ls_channel_estimate(Span(received), Span(known))
    var equalized = wifi_equalize(Span(received), Span(estimate))
    for i in range(2):
        # Float64 complex-division differential against the hand result.
        var denominator = known[i].re * known[i].re + known[i].im * known[i].im
        var expected_re = (received[i].re * known[i].re + received[i].im * known[i].im) / denominator
        var expected_im = (received[i].im * known[i].re - received[i].re * known[i].im) / denominator
        assert_true(abs(estimate[i].re - expected_re) <= TIGHT)
        assert_true(abs(estimate[i].im - expected_im) <= TIGHT)
        assert_true(abs(equalized[i].re - known[i].re) <= TIGHT)
        assert_true(abs(equalized[i].im - known[i].im) <= TIGHT)

    var repeated = List[Complex64](capacity=5 + 64)
    for _ in range(5):
        repeated.append(Complex64(0.0))
    for _ in range(4):
        for i in range(16):
            repeated.append(Complex64(Float64((5 * i + 1) % 7) - 3.0, Float64((3 * i + 2) % 5) - 2.0))
    var shifted = apply_cfo(Span(repeated), 0.00275)
    assert_equal(wifi_stf_detect(Span(shifted), 0.99), 5)
    assert_true(abs(wifi_stf_coarse_cfo(Span(shifted), 5) - 0.00275) <= TIGHT)

    var rate: List[UInt8] = [1, 1, 0, 1]
    var signal = wifi_legacy_signal_bits(Span(rate), 4095)
    assert_equal(signal, _manual_signal_bits(Span(rate), 4095))
    var parsed = wifi_parse_legacy_signal(Span(signal))
    assert_equal(parsed.length_octets, 4095)
    assert_equal(parsed.rate_bits, rate)
    for length in [0, 1, 37, 4095]:
        var manual_signal = _manual_signal_bits(Span(rate), length)
        var manual_parsed = wifi_parse_legacy_signal(Span(manual_signal))
        assert_equal(manual_parsed.rate_bits, rate)
        assert_equal(manual_parsed.length_octets, length)
    # Seeded valid fields exercise the parser against a separately assembled
    # bit layout and parity equation across the full 12-bit LENGTH domain.
    for trial in range(32):
        var property_rate = _seeded_bits(
            4, UInt64(0x51A000 + trial)
        )
        var property_length = (trial * 2053 + 73) & 0xFFF
        var property_signal = _manual_signal_bits(
            Span(property_rate), property_length
        )
        assert_equal(
            wifi_legacy_signal_bits(Span(property_rate), property_length),
            property_signal,
        )
        var property_parsed = wifi_parse_legacy_signal(
            Span(property_signal)
        )
        assert_equal(property_parsed.rate_bits, property_rate)
        assert_equal(property_parsed.length_octets, property_length)
    # Independent ISO/IEEE CRC-32 "123456789" vector.
    var octets: List[Int] = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]
    var check = List[UInt8]()
    for octet in octets:
        for bit in range(8):
            check.append(UInt8((octet >> bit) & 1))
    assert_equal(wifi_fcs(Span(check)), UInt64(0xCBF43926))
    for count in [0, 1, 7, 8, 63, 257]:
        var property_bits = _seeded_bits(count, UInt64(0xFC5000 + count))
        assert_equal(
            wifi_fcs(Span(property_bits)), _manual_fcs(Span(property_bits))
        )
    with assert_raises():
        _ = wifi_scramble(Span(zeros), UInt8(0))
    with assert_raises():
        _ = wifi_parse_legacy_signal(Span(zeros))


def test_profiles_resources_and_bcc_normative_edges() raises:
    # Exhaust every regular MCS row with a compact test-local transcription of
    # modulation and coding rate.  HT repeats rows 0..7 for one through four
    # spatial streams; VHT/HE/EHT stream counts are explicit API inputs.
    var expected_bpsc: List[Int] = [
        1, 2, 2, 4, 4, 6, 6, 6, 8, 8, 10, 10, 12, 12
    ]
    var expected_rate_numerator: List[Int] = [
        1, 1, 3, 1, 3, 2, 3, 5, 3, 5, 3, 5, 3, 5
    ]
    var expected_rate_denominator: List[Int] = [
        2, 2, 4, 2, 4, 3, 4, 6, 4, 6, 4, 6, 4, 6
    ]
    for mcs_index in range(32):
        var profile = wifi_mcs_profile(WIFI_PHY_HT, mcs_index)
        var row = mcs_index % 8
        assert_equal(profile.bits_per_subcarrier, expected_bpsc[row])
        assert_equal(
            profile.code_rate_numerator, expected_rate_numerator[row]
        )
        assert_equal(
            profile.code_rate_denominator, expected_rate_denominator[row]
        )
        assert_equal(profile.spatial_streams, mcs_index // 8 + 1)
        assert_true(not profile.dcm and not profile.ldpc_only)
    for family, row_count in [
        (WIFI_PHY_VHT, 10), (WIFI_PHY_HE, 12), (WIFI_PHY_EHT, 14)
    ]:
        for mcs_index in range(row_count):
            for spatial_streams in [1, 8]:
                var profile = wifi_mcs_profile(
                    family, mcs_index, spatial_streams=spatial_streams
                )
                assert_equal(
                    profile.bits_per_subcarrier,
                    expected_bpsc[mcs_index],
                )
                assert_equal(
                    profile.code_rate_numerator,
                    expected_rate_numerator[mcs_index],
                )
                assert_equal(
                    profile.code_rate_denominator,
                    expected_rate_denominator[mcs_index],
                )
                assert_equal(profile.spatial_streams, spatial_streams)
                assert_equal(
                    profile.ldpc_only,
                    (family == WIFI_PHY_HE or family == WIFI_PHY_EHT)
                    and mcs_index >= 10,
                )
    for dcm_mcs in [0, 1, 3, 4]:
        for spatial_streams in [1, 2]:
            var dcm_profile = wifi_mcs_profile(
                WIFI_PHY_HE,
                dcm_mcs,
                spatial_streams=spatial_streams,
                dcm=True,
            )
            assert_true(dcm_profile.dcm)
            assert_equal(dcm_profile.spatial_streams, spatial_streams)
    var eht14_full = wifi_mcs_profile(WIFI_PHY_EHT, 14)
    var eht15_full = wifi_mcs_profile(WIFI_PHY_EHT, 15)
    assert_equal(
        (
            eht14_full.bits_per_subcarrier,
            eht14_full.code_rate_numerator,
            eht14_full.code_rate_denominator,
            eht14_full.spatial_streams,
        ),
        (1, 1, 2, 1),
    )
    assert_true(
        eht14_full.dcm and eht14_full.duplicate_mode and eht14_full.ldpc_only
    )
    assert_true(
        eht15_full.dcm
        and not eht15_full.duplicate_mode
        and not eht15_full.ldpc_only
    )

    var ht = wifi_mcs_profile(WIFI_PHY_HT, 31)
    var vht = wifi_mcs_profile(WIFI_PHY_VHT, 9, spatial_streams=3)
    var he = wifi_mcs_profile(WIFI_PHY_HE, 11)
    var eht = wifi_mcs_profile(WIFI_PHY_EHT, 14)
    assert_equal((ht.bits_per_subcarrier, ht.spatial_streams), (6, 4))
    assert_equal((vht.bits_per_subcarrier, vht.code_rate_numerator), (8, 5))
    assert_true(he.ldpc_only)
    assert_true(eht.dcm and eht.duplicate_mode and eht.ldpc_only)
    var ht40 = wifi_ofdm_profile(WIFI_PHY_HT, 40)
    var he20 = wifi_ofdm_profile(WIFI_PHY_HE, 20)
    assert_equal(wifi_guard_interval_samples(ht40, 400), 16)
    assert_equal(wifi_coded_bits_per_symbol(he20, he), 2340)
    assert_equal(wifi_data_bits_per_symbol(he20, he), 1950)

    # Complete full-band OFDM profile table.  These tuples are test fixtures,
    # not values derived from another production profile helper.
    for (
        family,
        bandwidth,
        fft_size,
        data_subcarriers,
        pilot_subcarriers,
        occupied_subcarriers,
        useful_symbol_ns,
        default_guard_interval_ns,
        maximum_spatial_streams,
    ) in [
        (WIFI_PHY_HT, 20, 64, 52, 4, 56, 3200, 800, 4),
        (WIFI_PHY_HT, 40, 128, 108, 6, 114, 3200, 800, 4),
        (WIFI_PHY_VHT, 20, 64, 52, 4, 56, 3200, 800, 8),
        (WIFI_PHY_VHT, 40, 128, 108, 6, 114, 3200, 800, 8),
        (WIFI_PHY_VHT, 80, 256, 234, 8, 242, 3200, 800, 8),
        (WIFI_PHY_VHT, 160, 512, 468, 16, 484, 3200, 800, 8),
        (WIFI_PHY_HE, 20, 256, 234, 8, 242, 12800, 800, 8),
        (WIFI_PHY_HE, 40, 512, 468, 16, 484, 12800, 800, 8),
        (WIFI_PHY_HE, 80, 1024, 980, 16, 996, 12800, 800, 8),
        (WIFI_PHY_HE, 160, 2048, 1960, 32, 1992, 12800, 800, 8),
        (WIFI_PHY_EHT, 20, 256, 234, 8, 242, 12800, 800, 8),
        (WIFI_PHY_EHT, 40, 512, 468, 16, 484, 12800, 800, 8),
        (WIFI_PHY_EHT, 80, 1024, 980, 16, 996, 12800, 800, 8),
        (WIFI_PHY_EHT, 160, 2048, 1960, 32, 1992, 12800, 800, 8),
        (WIFI_PHY_EHT, 320, 4096, 3920, 64, 3984, 12800, 800, 8),
    ]:
        var profile = wifi_ofdm_profile(family, bandwidth)
        assert_equal(profile.fft_size, fft_size)
        assert_equal(profile.data_subcarriers, data_subcarriers)
        assert_equal(profile.pilot_subcarriers, pilot_subcarriers)
        assert_equal(profile.occupied_subcarriers, occupied_subcarriers)
        assert_equal(profile.useful_symbol_ns, useful_symbol_ns)
        assert_equal(
            profile.default_guard_interval_ns, default_guard_interval_ns
        )
        assert_equal(
            profile.maximum_spatial_streams, maximum_spatial_streams
        )
        var guard_intervals: List[Int]
        if family == WIFI_PHY_HT or family == WIFI_PHY_VHT:
            guard_intervals = [400, 800]
        else:
            guard_intervals = [800, 1600, 3200]
        for guard_interval_ns in guard_intervals:
            assert_equal(
                wifi_guard_interval_samples(profile, guard_interval_ns),
                fft_size * guard_interval_ns // useful_symbol_ns,
            )
        var mcs0 = wifi_mcs_profile(family, 0)
        var expected_coded = data_subcarriers
        assert_equal(
            wifi_coded_bits_per_symbol(profile, mcs0), expected_coded
        )
        assert_equal(
            wifi_data_bits_per_symbol(profile, mcs0), expected_coded // 2
        )

    # Exhaust full-band capacity arithmetic over every legal MCS/NSS row for
    # every legal bandwidth.  The expectation is computed directly from the
    # fixture Nsd, modulation, DCM/DUP and rational coding-rate fields.
    for family, bandwidth in [
        (WIFI_PHY_HT, 20),
        (WIFI_PHY_HT, 40),
        (WIFI_PHY_VHT, 20),
        (WIFI_PHY_VHT, 40),
        (WIFI_PHY_VHT, 80),
        (WIFI_PHY_VHT, 160),
        (WIFI_PHY_HE, 20),
        (WIFI_PHY_HE, 40),
        (WIFI_PHY_HE, 80),
        (WIFI_PHY_HE, 160),
        (WIFI_PHY_EHT, 20),
        (WIFI_PHY_EHT, 40),
        (WIFI_PHY_EHT, 80),
        (WIFI_PHY_EHT, 160),
        (WIFI_PHY_EHT, 320),
    ]:
        var ofdm = wifi_ofdm_profile(family, bandwidth)
        if family == WIFI_PHY_HT:
            for mcs_index in range(32):
                var mcs = wifi_mcs_profile(family, mcs_index)
                var expected_coded = (
                    ofdm.data_subcarriers
                    * mcs.bits_per_subcarrier
                    * mcs.spatial_streams
                )
                var expected_data_numerator = (
                    expected_coded * mcs.code_rate_numerator
                )
                assert_equal(
                    wifi_coded_bits_per_symbol(ofdm, mcs), expected_coded
                )
                assert_equal(
                    wifi_data_bits_per_symbol(ofdm, mcs),
                    expected_data_numerator // mcs.code_rate_denominator,
                )
        else:
            var regular_rows = (
                10 if family == WIFI_PHY_VHT
                else (12 if family == WIFI_PHY_HE else 14)
            )
            for mcs_index in range(regular_rows):
                for spatial_streams in range(1, 9):
                    var mcs = wifi_mcs_profile(
                        family,
                        mcs_index,
                        spatial_streams=spatial_streams,
                    )
                    var expected_coded = (
                        ofdm.data_subcarriers
                        * mcs.bits_per_subcarrier
                        * spatial_streams
                    )
                    var expected_data_numerator = (
                        expected_coded * mcs.code_rate_numerator
                    )
                    assert_equal(
                        wifi_coded_bits_per_symbol(ofdm, mcs),
                        expected_coded,
                    )
                    if (
                        family == WIFI_PHY_VHT
                        and expected_data_numerator
                        % mcs.code_rate_denominator != 0
                    ):
                        with assert_raises():
                            _ = wifi_data_bits_per_symbol(ofdm, mcs)
                    else:
                        assert_equal(
                            wifi_data_bits_per_symbol(ofdm, mcs),
                            expected_data_numerator
                            // mcs.code_rate_denominator,
                        )
            if family == WIFI_PHY_HE:
                for dcm_mcs in [0, 1, 3, 4]:
                    for spatial_streams in [1, 2]:
                        var mcs = wifi_mcs_profile(
                            family,
                            dcm_mcs,
                            spatial_streams=spatial_streams,
                            dcm=True,
                        )
                        var expected_coded = (
                            ofdm.data_subcarriers
                            * mcs.bits_per_subcarrier
                            * spatial_streams
                            // 2
                        )
                        assert_equal(
                            wifi_coded_bits_per_symbol(ofdm, mcs),
                            expected_coded,
                        )
                        assert_equal(
                            wifi_data_bits_per_symbol(ofdm, mcs),
                            expected_coded * mcs.code_rate_numerator
                            // mcs.code_rate_denominator,
                        )
            elif family == WIFI_PHY_EHT:
                var mcs14 = wifi_mcs_profile(family, 14)
                if bandwidth == 20 or bandwidth == 40:
                    with assert_raises():
                        _ = wifi_coded_bits_per_symbol(ofdm, mcs14)
                    with assert_raises():
                        _ = wifi_data_bits_per_symbol(ofdm, mcs14)
                else:
                    var source_data_subcarriers = (
                        468 if bandwidth == 80
                        else (980 if bandwidth == 160 else 1960)
                    )
                    var expected_coded = source_data_subcarriers // 2
                    assert_equal(
                        wifi_coded_bits_per_symbol(ofdm, mcs14),
                        expected_coded,
                    )
                    assert_equal(
                        wifi_data_bits_per_symbol(ofdm, mcs14),
                        expected_coded // 2,
                    )
                var mcs15 = wifi_mcs_profile(family, 15)
                var expected_coded = ofdm.data_subcarriers // 2
                assert_equal(
                    wifi_coded_bits_per_symbol(ofdm, mcs15),
                    expected_coded,
                )
                assert_equal(
                    wifi_data_bits_per_symbol(ofdm, mcs15),
                    expected_coded // 2,
                )

    var ru26 = wifi_ru_profile(WIFI_PHY_HE, 26)
    var ru242 = wifi_ru_profile(WIFI_PHY_HE, 242)
    assert_equal((ru26.data_subcarriers, ru26.pilot_subcarriers), (24, 2))
    assert_equal(wifi_max_ru_count(WIFI_PHY_HE, 20, 26), 9)
    var he0 = wifi_mcs_profile(WIFI_PHY_HE, 0)
    assert_equal(wifi_ru_coded_bits_per_symbol(ru26, he0), 24)
    assert_equal(wifi_ru_data_bits_per_symbol(ru26, he0), 12)
    assert_true(wifi_ru_requires_ldpc(ru242, he))

    var ru_sizes: List[Int] = [26, 52, 106, 242, 484, 996, 1992, 3984]
    var ru_data_counts: List[Int] = [24, 48, 102, 234, 468, 980, 1960, 3920]
    var ru_pilot_counts: List[Int] = [2, 4, 4, 8, 16, 16, 32, 64]
    var ru_minimum_bandwidths: List[Int] = [20, 20, 20, 20, 40, 80, 160, 320]
    for family in [WIFI_PHY_HE, WIFI_PHY_EHT]:
        var row_count = 7 if family == WIFI_PHY_HE else 8
        for row in range(row_count):
            var profile = wifi_ru_profile(family, ru_sizes[row])
            assert_equal(profile.ru_tones, ru_sizes[row])
            assert_equal(profile.data_subcarriers, ru_data_counts[row])
            assert_equal(profile.pilot_subcarriers, ru_pilot_counts[row])
            assert_equal(
                profile.minimum_bandwidth_mhz,
                ru_minimum_bandwidths[row],
            )
            assert_equal(profile.requires_ldpc, row >= 4)
            var mcs0 = wifi_mcs_profile(family, 0)
            assert_equal(
                wifi_ru_coded_bits_per_symbol(profile, mcs0),
                ru_data_counts[row],
            )
            assert_equal(
                wifi_ru_data_bits_per_symbol(profile, mcs0),
                ru_data_counts[row] // 2,
            )
            assert_equal(
                wifi_ru_requires_ldpc(profile, mcs0), row >= 4
            )

            var regular_rows = 12 if family == WIFI_PHY_HE else 14
            for mcs_index in range(regular_rows):
                for spatial_streams in range(1, 9):
                    var mcs = wifi_mcs_profile(
                        family,
                        mcs_index,
                        spatial_streams=spatial_streams,
                    )
                    var invalid_high_order = (
                        mcs.bits_per_subcarrier >= 10
                        and profile.ru_tones < 242
                    )
                    if invalid_high_order:
                        with assert_raises():
                            _ = wifi_ru_coded_bits_per_symbol(profile, mcs)
                        with assert_raises():
                            _ = wifi_ru_data_bits_per_symbol(profile, mcs)
                        with assert_raises():
                            _ = wifi_ru_requires_ldpc(profile, mcs)
                    else:
                        var expected_coded = (
                            profile.data_subcarriers
                            * mcs.bits_per_subcarrier
                            * spatial_streams
                        )
                        assert_equal(
                            wifi_ru_coded_bits_per_symbol(profile, mcs),
                            expected_coded,
                        )
                        assert_equal(
                            wifi_ru_data_bits_per_symbol(profile, mcs),
                            expected_coded * mcs.code_rate_numerator
                            // mcs.code_rate_denominator,
                        )
                        assert_equal(
                            wifi_ru_requires_ldpc(profile, mcs),
                            profile.requires_ldpc
                            or mcs.ldpc_only
                            or spatial_streams > 4,
                        )
            if family == WIFI_PHY_HE:
                for dcm_mcs in [0, 1, 3, 4]:
                    for spatial_streams in [1, 2]:
                        var mcs = wifi_mcs_profile(
                            family,
                            dcm_mcs,
                            spatial_streams=spatial_streams,
                            dcm=True,
                        )
                        var expected_coded = (
                            profile.data_subcarriers
                            * mcs.bits_per_subcarrier
                            * spatial_streams
                            // 2
                        )
                        assert_equal(
                            wifi_ru_coded_bits_per_symbol(profile, mcs),
                            expected_coded,
                        )
                        assert_equal(
                            wifi_ru_data_bits_per_symbol(profile, mcs),
                            expected_coded * mcs.code_rate_numerator
                            // mcs.code_rate_denominator,
                        )
                        assert_equal(
                            wifi_ru_requires_ldpc(profile, mcs),
                            profile.requires_ldpc,
                        )
            else:
                var mcs14 = wifi_mcs_profile(family, 14)
                with assert_raises():
                    _ = wifi_ru_coded_bits_per_symbol(profile, mcs14)
                with assert_raises():
                    _ = wifi_ru_data_bits_per_symbol(profile, mcs14)
                with assert_raises():
                    _ = wifi_ru_requires_ldpc(profile, mcs14)
                var mcs15 = wifi_mcs_profile(family, 15)
                var expected_coded = profile.data_subcarriers // 2
                assert_equal(
                    wifi_ru_coded_bits_per_symbol(profile, mcs15),
                    expected_coded,
                )
                assert_equal(
                    wifi_ru_data_bits_per_symbol(profile, mcs15),
                    expected_coded // 2,
                )
                assert_equal(
                    wifi_ru_requires_ldpc(profile, mcs15),
                    profile.requires_ldpc,
                )

    # Every valid maximum-equal-RU row for 20 through 160 MHz is checked for
    # both HE and EHT, with the eight EHT-only 320 MHz rows separate.
    var ru20: List[Int] = [26, 52, 106, 242]
    var counts20: List[Int] = [9, 4, 2, 1]
    var ru40: List[Int] = [26, 52, 106, 242, 484]
    var counts40: List[Int] = [18, 8, 4, 2, 1]
    var ru80: List[Int] = [26, 52, 106, 242, 484, 996]
    var counts80: List[Int] = [37, 16, 8, 4, 2, 1]
    var ru160: List[Int] = [26, 52, 106, 242, 484, 996, 1992]
    var counts160: List[Int] = [74, 32, 16, 8, 4, 2, 1]
    for family in [WIFI_PHY_HE, WIFI_PHY_EHT]:
        _assert_max_ru_rows(family, 20, Span(ru20), Span(counts20))
        _assert_max_ru_rows(family, 40, Span(ru40), Span(counts40))
        _assert_max_ru_rows(family, 80, Span(ru80), Span(counts80))
        _assert_max_ru_rows(family, 160, Span(ru160), Span(counts160))
    var counts320: List[Int] = [148, 64, 32, 16, 8, 4, 2, 1]
    _assert_max_ru_rows(
        WIFI_PHY_EHT, 320, Span(ru_sizes), Span(counts320)
    )

    for ru_index in range(9):
        _assert_complete_ru_tone_row(26, ru_index)
    for ru_index in range(4):
        _assert_complete_ru_tone_row(52, ru_index)
    for ru_index in range(2):
        _assert_complete_ru_tone_row(106, ru_index)
    _assert_complete_ru_tone_row(242, 0)

    # Exhaust all pairs of legal allocations against a test-local set
    # intersection rather than using map/extract as the oracle.
    var allocation_sizes: List[Int] = []
    var allocation_indices: List[Int] = []
    for ru_index in range(9):
        allocation_sizes.append(26)
        allocation_indices.append(ru_index)
    for ru_index in range(4):
        allocation_sizes.append(52)
        allocation_indices.append(ru_index)
    for ru_index in range(2):
        allocation_sizes.append(106)
        allocation_indices.append(ru_index)
    allocation_sizes.append(242)
    allocation_indices.append(0)
    for left in range(len(allocation_sizes)):
        for right in range(len(allocation_sizes)):
            var pair_sizes: List[Int] = [
                allocation_sizes[left], allocation_sizes[right]
            ]
            var pair_indices: List[Int] = [
                allocation_indices[left], allocation_indices[right]
            ]
            assert_equal(
                wifi_ru_allocations_disjoint_20mhz(
                    Span(pair_sizes), Span(pair_indices)
                ),
                _manual_ru_allocations_disjoint_20mhz(
                    Span(pair_sizes), Span(pair_indices)
                ),
            )

    assert_equal(wifi_ru_subcarriers_20mhz(26, 4), [-16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
    assert_equal(wifi_ru_pilot_subcarriers_20mhz(26, 4), [-10, 10])
    assert_equal(len(wifi_ru_data_subcarriers_20mhz(26, 4)), 24)
    var sizes: List[Int] = [52, 52, 52, 52]
    var indices: List[Int] = [0, 1, 2, 3]
    assert_true(wifi_ru_allocations_disjoint_20mhz(Span(sizes), Span(indices)))
    var ru_data = List[Complex64](capacity=24)
    for i in range(24):
        ru_data.append(Complex64(Float64(i), -Float64(i)))
    var ru_pilots: List[Complex64] = [Complex64(1.0), Complex64(-1.0)]
    var ru_spectrum = wifi_map_ru_symbol_20mhz(Span(ru_data), Span(ru_pilots), 26, 4)
    # RU-26 index four is the published split-center allocation.  Construct
    # every expected FFT bin by hand so map/extract are not mutual oracles.
    var ru_occupied: List[Int] = [
        -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4,
        4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    ]
    var manual_ru_spectrum = List[Complex64](
        length=256, fill=Complex64(0.0, 0.0)
    )
    var data_source = 0
    var pilot_source = 0
    for subcarrier in ru_occupied:
        var bin_index = subcarrier if subcarrier >= 0 else 256 + subcarrier
        if subcarrier == -10 or subcarrier == 10:
            manual_ru_spectrum[bin_index] = ru_pilots[pilot_source]
            pilot_source += 1
        else:
            manual_ru_spectrum[bin_index] = ru_data[data_source]
            data_source += 1
    assert_equal(ru_spectrum, manual_ru_spectrum)
    assert_equal(wifi_extract_ru_data_20mhz(Span(ru_spectrum), 26, 4), ru_data)
    assert_equal(wifi_extract_ru_pilots_20mhz(Span(ru_spectrum), 26, 4), ru_pilots)
    assert_equal(
        wifi_extract_ru_data_20mhz(Span(manual_ru_spectrum), 26, 4),
        ru_data,
    )
    assert_equal(
        wifi_extract_ru_pilots_20mhz(Span(manual_ru_spectrum), 26, 4),
        ru_pilots,
    )

    assert_equal(wifi_bcc_puncture_pattern(3, 4), [1, 1, 1, 0, 0, 1])
    var mother: List[UInt8] = [0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0]
    assert_equal(wifi_bcc_puncture(Span(mother), 3, 4), [0, 1, 1, 0, 0, 1, 1, 0])
    var llrs: List[Float64] = [1.0, -2.0, -3.0, 4.0, 5.0, -6.0, -7.0, 8.0]
    assert_equal(wifi_bcc_depuncture_llrs(Span(llrs), 12, 3, 4), [1.0, -2.0, -3.0, 0.0, 0.0, 4.0, 5.0, -6.0, -7.0, 0.0, 0.0, 8.0])
    for numerator, denominator in [(1, 2), (2, 3), (3, 4), (5, 6)]:
        var pattern: List[UInt8]
        if numerator == 1:
            pattern = [1, 1]
        elif numerator == 2:
            pattern = [1, 1, 1, 0]
        elif numerator == 3:
            pattern = [1, 1, 1, 0, 0, 1]
        else:
            pattern = [1, 1, 1, 0, 0, 1, 1, 0, 0, 1]
        var property_mother = _seeded_bits(
            83, UInt64(0xBCC000 + 10 * numerator + denominator)
        )
        var expected_punctured = _manual_puncture_bits(
            Span(property_mother), Span(pattern)
        )
        var actual_punctured = wifi_bcc_puncture(
            Span(property_mother), numerator, denominator
        )
        assert_equal(actual_punctured, expected_punctured)
        var property_llrs = List[Float64](capacity=len(actual_punctured))
        for i in range(len(actual_punctured)):
            property_llrs.append(Float64(i) - 17.25)
        assert_equal(
            wifi_bcc_depuncture_llrs(
                Span(property_llrs), 83, numerator, denominator
            ),
            _manual_depuncture(Span(property_llrs), Span(pattern), 83),
        )

    # Exhaust the HT/VHT full-band table and every HE/EHT RU/DCM geometry.
    for family, bandwidth, block_data, columns, rows, rotation, blocks in [
        (WIFI_PHY_HT, 20, 52, 13, 4, 11, 1),
        (WIFI_PHY_HT, 40, 108, 18, 6, 29, 1),
        (WIFI_PHY_VHT, 20, 52, 13, 4, 11, 1),
        (WIFI_PHY_VHT, 40, 108, 18, 6, 29, 1),
        (WIFI_PHY_VHT, 80, 234, 26, 9, 58, 1),
        (WIFI_PHY_VHT, 160, 234, 26, 9, 58, 2),
    ]:
        var profile = wifi_bcc_interleaver_profile(family, bandwidth)
        assert_equal(profile.block_data_subcarriers, block_data)
        assert_equal(profile.columns, columns)
        assert_equal(profile.rows_per_modulation_bit, rows)
        assert_equal(profile.rotation_subcarriers, rotation)
        assert_equal(profile.blocks_per_symbol, blocks)
        assert_true(not profile.dcm)
    for family in [WIFI_PHY_HE, WIFI_PHY_EHT]:
        var bandwidths: List[Int] = [20, 40, 80, 160]
        if family == WIFI_PHY_EHT:
            bandwidths.append(320)
        for bandwidth in bandwidths:
            for ru_tones, block_data, columns, rows, rotation in [
                (26, 24, 8, 3, 2),
                (52, 48, 16, 3, 11),
                (106, 102, 17, 6, 29),
                (242, 234, 26, 9, 58),
            ]:
                var profile = wifi_bcc_interleaver_profile(
                    family, bandwidth, ru_tones=ru_tones
                )
                assert_equal(profile.block_data_subcarriers, block_data)
                assert_equal(profile.columns, columns)
                assert_equal(profile.rows_per_modulation_bit, rows)
                assert_equal(profile.rotation_subcarriers, rotation)
                assert_equal(profile.blocks_per_symbol, 1)
                assert_true(not profile.dcm)
            for ru_tones, block_data, columns, rows, rotation in [
                (26, 12, 4, 3, 2),
                (52, 24, 8, 3, 2),
                (106, 51, 17, 3, 11),
                (242, 117, 13, 9, 29),
            ]:
                var profile = wifi_bcc_interleaver_profile(
                    family, bandwidth, ru_tones=ru_tones, dcm=True
                )
                assert_equal(profile.block_data_subcarriers, block_data)
                assert_equal(profile.columns, columns)
                assert_equal(profile.rows_per_modulation_bit, rows)
                assert_equal(profile.rotation_subcarriers, rotation)
                assert_equal(profile.blocks_per_symbol, 1)
                assert_true(profile.dcm)

    var inter_profile = wifi_bcc_interleaver_profile(WIFI_PHY_HT, 20)
    var seeded = _seeded_bits(312, UInt64(0xBCCA11))
    var interleaved = wifi_bcc_interleave_block(Span(seeded), 6, inter_profile)
    assert_equal(wifi_bcc_deinterleave_block(Span(interleaved), 6, inter_profile), seeded)
    var arbitrary_interleaved = _seeded_bits(312, UInt64(0xDEC0DE))
    var expected_deinterleaved = List[UInt8](length=312, fill=UInt8(0))
    # HT20: columns=13, rows-per-modulation-bit=4, rotation=11.
    var rows = 24
    var s = 3
    # Stream index two selects one 11-subcarrier cyclic rotation.
    var rotation = (1 * 11 * 6) % 312
    for k in range(312):
        var first = rows * (k % 13) + k // 13
        var second = s * (first // s) + (first + 312 - (13 * first) // 312) % s
        var destination = (second + 312 - rotation) % 312
        expected_deinterleaved[k] = arbitrary_interleaved[destination]
    assert_equal(
        wifi_bcc_deinterleave_block(
            Span(arbitrary_interleaved), 6, inter_profile,
            spatial_stream_index=2,
        ),
        expected_deinterleaved,
    )
    var impulse = List[UInt8](length=52, fill=UInt8(0))
    impulse[13] = 1
    assert_equal(wifi_bcc_interleave_block(Span(impulse), 1, inter_profile)[1], UInt8(1))
    with assert_raises():
        _ = wifi_ofdm_profile(WIFI_PHY_HT, 80)
    with assert_raises():
        _ = wifi_ru_subcarriers_20mhz(26, 9)


def test_pilots_and_preambles_float64_differential() raises:
    var indices: List[Int] = [-116, -48, 22, 90]
    var known: List[Complex64] = [Complex64(1.0), Complex64(-1.0), Complex64(1.0), Complex64(-1.0)]
    var common = 0.37
    var slope = -0.00125
    var received = List[Complex64](capacity=4)
    for i in range(4):
        var phase = common + slope * Float64(indices[i])
        received.append(known[i] * Complex64(cos(phase), sin(phase)))
    var phase_estimate = wifi_estimate_pilot_phase(Span(received), Span(known), Span(indices))
    assert_true(abs(phase_estimate.common_phase - common) <= TIGHT)
    assert_true(abs(phase_estimate.phase_slope - slope) <= TIGHT)
    var corrected = wifi_correct_pilot_phase(Span(received), Span(indices), phase_estimate)
    for i in range(4):
        assert_true(abs(corrected[i].re - known[i].re) <= TIGHT)
        assert_true(abs(corrected[i].im - known[i].im) <= TIGHT)

    for family in [WIFI_PHY_HT, WIFI_PHY_VHT]:
        assert_equal(
            wifi_data_pilot_subcarriers_20mhz(family),
            [-21, -7, 7, 21],
        )
    for family in [WIFI_PHY_HE, WIFI_PHY_EHT]:
        assert_equal(
            wifi_data_pilot_subcarriers_20mhz(family),
            [-116, -90, -48, -22, 22, 48, 90, 116],
        )
    # Two complete polarity periods cover every HT/VHT/EHT polarity row;
    # HE's eight-row rotation is covered repeatedly in the same sweep.
    for family in [WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE, WIFI_PHY_EHT]:
        for symbol_index in range(254):
            assert_equal(
                wifi_data_pilots_20mhz(family, symbol_index),
                _manual_data_pilots_20mhz(family, symbol_index),
            )

    for family in [WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE, WIFI_PHY_EHT]:
        var expected_values = _independent_ltf_values(family)
        var expected_spectrum = _independent_ltf_spectrum(family)
        assert_equal(wifi_ltf_values_20mhz(family), expected_values)
        assert_equal(wifi_ltf_spectrum_20mhz(family), expected_spectrum)
        var expected_waveform = _naive_ofdm_symbol(
            Span(expected_spectrum), 16
        )
        _assert_complex_lists_close(
            wifi_ltf_waveform_20mhz(family),
            expected_waveform,
            FFT_TOLERANCE,
        )

    var channel = Complex64(0.73, -0.19)
    var ltf = wifi_ltf_waveform_20mhz(WIFI_PHY_EHT)
    var impaired = List[Complex64](capacity=len(ltf))
    for sample in ltf:
        impaired.append(sample * channel)
    var channel_estimate = wifi_ltf_channel_estimate_20mhz(Span(impaired), WIFI_PHY_EHT)
    var known_spectrum = wifi_ltf_spectrum_20mhz(WIFI_PHY_EHT)
    for i in range(256):
        if known_spectrum[i].magnitude_squared() > 0.0:
            assert_true(abs(channel_estimate[i].re - channel.re) <= FFT_TOLERANCE)
            assert_true(abs(channel_estimate[i].im - channel.im) <= FFT_TOLERANCE)

    # Independent HT-LTF static row + naive IFFT supplies a true differential
    # for the channel estimator, with a frequency-selective analytic channel.
    var static_values = _ht_ltf_values_static()
    var received_spectrum = List[Complex64](
        length=64, fill=Complex64(0.0, 0.0)
    )
    var expected_channel = List[Complex64](
        length=64, fill=Complex64(0.0, 0.0)
    )
    for i in range(57):
        var subcarrier = i - 28
        var bin_index = subcarrier if subcarrier >= 0 else 64 + subcarrier
        if static_values[i] != 0:
            var h = Complex64(
                0.65 + 0.003 * Float64(subcarrier),
                -0.21 + 0.002 * Float64(subcarrier),
            )
            expected_channel[bin_index] = h
            received_spectrum[bin_index] = Complex64(
                Float64(static_values[i]) * h.re,
                Float64(static_values[i]) * h.im,
            )
    var independent_ltf = _naive_ofdm_symbol(Span(received_spectrum), 16)
    var independent_estimate = wifi_ltf_channel_estimate_20mhz(
        Span(independent_ltf), WIFI_PHY_HT
    )
    _assert_complex_lists_close(
        independent_estimate, expected_channel, FFT_TOLERANCE
    )


def test_wlan_ldpc_static_codeword_and_rate_evidence() raises:
    for block_length in [648, 1296, 1944]:
        for numerator, denominator, block_rows in [
            (1, 2, 12), (2, 3, 8), (3, 4, 6), (5, 6, 4)
        ]:
            var complete_profile = wifi_ldpc_profile(
                block_length, numerator, denominator
            )
            assert_equal(complete_profile.lifting_size, block_length // 24)
            assert_equal(complete_profile.block_rows, block_rows)
            assert_equal(
                complete_profile.parity_length,
                block_rows * complete_profile.lifting_size,
            )
            assert_equal(
                complete_profile.information_length,
                block_length - complete_profile.parity_length,
            )
            var complete_shifts = wifi_ldpc_base_shifts(complete_profile)
            assert_equal(len(complete_shifts), block_rows * 24)
            for shift in complete_shifts:
                assert_true(
                    shift == -1
                    or (shift >= 0 and shift < complete_profile.lifting_size)
                )
            var complete_graph = wifi_ldpc_sparse_graph(complete_profile)
            assert_equal(
                len(complete_graph.row_offsets),
                complete_profile.parity_length + 1,
            )
            assert_equal(complete_graph.row_offsets[0], 0)
            assert_equal(
                complete_graph.row_offsets[
                    len(complete_graph.row_offsets) - 1
                ],
                len(complete_graph.columns),
            )
            for row in range(complete_profile.parity_length):
                assert_true(
                    complete_graph.row_offsets[row]
                    <= complete_graph.row_offsets[row + 1]
                )
            for column in complete_graph.columns:
                assert_true(column >= 0 and column < block_length)

    var profile = wifi_ldpc_profile(648, 1, 2)
    var shifts = wifi_ldpc_base_shifts(profile)
    assert_equal((profile.information_length, profile.parity_length, len(shifts)), (324, 324, 288))
    assert_equal((shifts[0], shifts[1], shifts[12], shifts[13]), (0, -1, 1, 0))
    var graph = wifi_ldpc_sparse_graph(profile)
    assert_equal(len(graph.row_offsets), 325)
    var codeword = List[UInt8](length=648, fill=UInt8(0))
    # KAIST CoCoA published N=648, R=1/2 minimum codeword positions (1-based).
    var positions: List[Int] = [98, 99, 250, 315, 369, 396, 423, 439, 449, 476, 502, 568, 569, 596, 623]
    for position in positions:
        codeword[position - 1] = 1
    assert_true(wifi_ldpc_syndrome_ok(Span(codeword), profile))
    var information = List[UInt8](capacity=324)
    for i in range(324):
        information.append(codeword[i])
    assert_equal(wifi_ldpc_encode(Span(information), profile), codeword)
    var llrs = List[Float64](capacity=648)
    for bit in codeword:
        llrs.append(24.0 if bit == 0 else -24.0)
    var decoded = wifi_ldpc_decode(Span(llrs), profile, max_iterations=5)
    assert_true(decoded.converged)
    assert_equal(decoded.codeword_bits, codeword)
    var seeded_information = _seeded_bits(324, UInt64(0x1D0CDEC0DE))
    var seeded_codeword = wifi_ldpc_encode(Span(seeded_information), profile)
    var seeded_llrs = List[Float64](capacity=648)
    for i in range(648):
        # Unequal magnitudes exercise the min-sum path while preserving sign.
        var magnitude = 7.0 + Float64((17 * i + 3) % 11)
        seeded_llrs.append(
            magnitude if seeded_codeword[i] == 0 else -magnitude
        )
    var seeded_decoded = wifi_ldpc_decode(
        Span(seeded_llrs), profile, max_iterations=8
    )
    assert_true(seeded_decoded.converged)
    assert_equal(seeded_decoded.information_bits, seeded_information)
    var transmitted = wifi_ldpc_rate_match_block(Span(information), profile, punctured_bits=3, repeated_bits=5)
    var expected_transmitted = List[UInt8](capacity=650)
    for i in range(645):
        expected_transmitted.append(codeword[i])
    for i in range(5):
        expected_transmitted.append(codeword[i])
    # The mother codeword is an external KAIST vector; slicing and repetition
    # below are a test-local implementation of WLAN rate matching.
    assert_equal(transmitted, expected_transmitted)
    var transmitted_llrs = List[Float64](capacity=len(transmitted))
    for bit in transmitted:
        transmitted_llrs.append(3.0 if bit == 0 else -3.0)
    var recovered = wifi_ldpc_rate_recover_block(Span(transmitted_llrs), profile, punctured_bits=3, repeated_bits=5)
    assert_equal(len(recovered), 648)
    assert_equal((recovered[645], recovered[646], recovered[647]), (0.0, 0.0, 0.0))


def test_tone_maps_and_all_four_phy_families() raises:
    var ht_indices = wifi_ht_vht_data_subcarriers_20mhz(WIFI_PHY_HT)
    var expected_ht_indices: List[Int] = [
        -28, -27, -26, -25, -24, -23, -22, -20,
        -19, -18, -17, -16, -15, -14, -13, -12,
        -11, -10, -9, -8, -6, -5, -4, -3,
        -2, -1, 1, 2, 3, 4, 5, 6,
        8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 22, 23, 24,
        25, 26, 27, 28,
    ]
    assert_equal(ht_indices, expected_ht_indices)
    assert_equal(
        wifi_ht_vht_data_subcarriers_20mhz(WIFI_PHY_VHT),
        expected_ht_indices,
    )
    var data = List[Complex64](capacity=52)
    for i in range(52):
        data.append(Complex64(Float64(i + 1), Float64(-i)))
    var pilots = wifi_data_pilots_20mhz(WIFI_PHY_VHT, 3)
    var spectrum = wifi_map_ht_vht_symbol_20mhz(Span(data), Span(pilots), WIFI_PHY_VHT)
    var manual_spectrum = List[Complex64](
        length=64, fill=Complex64(0.0, 0.0)
    )
    var manual_data_source = 0
    var manual_pilot_source = 0
    for subcarrier in range(-28, 29):
        if subcarrier == 0:
            continue
        var bin_index = subcarrier if subcarrier >= 0 else 64 + subcarrier
        if (
            subcarrier == -21 or subcarrier == -7
            or subcarrier == 7 or subcarrier == 21
        ):
            manual_spectrum[bin_index] = pilots[manual_pilot_source]
            manual_pilot_source += 1
        else:
            manual_spectrum[bin_index] = data[manual_data_source]
            manual_data_source += 1
    assert_equal(spectrum, manual_spectrum)
    assert_equal(wifi_extract_ht_vht_data_20mhz(Span(spectrum), WIFI_PHY_VHT), data)
    assert_equal(wifi_extract_ht_vht_pilots_20mhz(Span(spectrum), WIFI_PHY_VHT), pilots)
    assert_equal(
        wifi_extract_ht_vht_data_20mhz(
            Span(manual_spectrum), WIFI_PHY_VHT
        ),
        data,
    )
    assert_equal(
        wifi_extract_ht_vht_pilots_20mhz(
            Span(manual_spectrum), WIFI_PHY_VHT
        ),
        pilots,
    )
    for ru_tones, expected_distance in [
        (26, 1),
        (52, 3),
        (106, 6),
        (242, 9),
        (484, 12),
        (996, 20),
        (1992, 20),
        (3984, 20),
    ]:
        assert_equal(
            wifi_ldpc_tone_mapping_distance(ru_tones), expected_distance
        )
    var permutation = wifi_ldpc_tone_permutation(234, 9)
    var expected_permutation = List[Int](capacity=234)
    for source in range(234):
        expected_permutation.append(
            9 * (source % 26) + (source * 9) // 234
        )
    assert_equal(permutation, expected_permutation)
    for data_subcarriers, distance in [
        (24, 1),
        (48, 3),
        (102, 6),
        (234, 9),
        (468, 12),
        (980, 20),
    ]:
        var actual = wifi_ldpc_tone_permutation(
            data_subcarriers, distance
        )
        var expected = List[Int](capacity=data_subcarriers)
        var seen = List[Bool](length=data_subcarriers, fill=False)
        for source in range(data_subcarriers):
            var destination = (
                distance * (source % (data_subcarriers // distance))
                + (source * distance) // data_subcarriers
            )
            expected.append(destination)
            assert_true(destination >= 0 and destination < data_subcarriers)
            assert_true(not seen[destination])
            seen[destination] = True
        assert_equal(actual, expected)
    var bits = _seeded_bits(468, UInt64(0x1D0C))
    var mapped = wifi_ldpc_tone_map_bits(Span(bits), 2, 242)
    assert_equal(
        mapped, _manual_tone_map_bits(Span(bits), 2, 234, 9, 1)
    )
    var mapped_llrs = List[Float64](capacity=468)
    for bit in mapped:
        mapped_llrs.append(2.0 if bit == 0 else -2.0)
    var demapped = wifi_ldpc_tone_demap_llrs(Span(mapped_llrs), 2, 242)
    for i in range(468):
        assert_equal(demapped[i] > 0.0, bits[i] == 0)
    var arbitrary_physical = List[Float64](capacity=468)
    for i in range(468):
        arbitrary_physical.append(Float64((31 * i + 7) % 103) - 51.25)
    var expected_logical = List[Float64](length=468, fill=0.0)
    for source_tone in range(234):
        var destination_tone = (
            9 * (source_tone % 26) + (source_tone * 9) // 234
        )
        for bit in range(2):
            expected_logical[source_tone * 2 + bit] = arbitrary_physical[
                destination_tone * 2 + bit
            ]
    assert_equal(
        wifi_ldpc_tone_demap_llrs(
            Span(arbitrary_physical), 2, 242
        ),
        expected_logical,
    )

    var ht_payload = _payload(18, 1)
    var ht_tx = wifi_bcc_tx_20mhz(Span(ht_payload), WIFI_PHY_HT, 6, symbol_index=2)
    var ht_ltf = _scaled_ltf(WIFI_PHY_HT, Complex64(1.0))
    var ht_rx = wifi_bcc_rx_20mhz(Span(ht_tx.waveform), Span(ht_ltf), WIFI_PHY_HT, 6, len(ht_payload), symbol_index=2)
    assert_true(ht_rx.service_ok and ht_rx.fcs_ok)
    assert_equal(ht_rx.payload_bits, ht_payload)
    var vht_payload = _payload(24, 2)
    var vht_tx = wifi_bcc_tx_20mhz(Span(vht_payload), WIFI_PHY_VHT, 8)
    var vht_ltf = _scaled_ltf(WIFI_PHY_VHT, Complex64(1.0))
    var vht_rx = wifi_bcc_rx_20mhz(Span(vht_tx.waveform), Span(vht_ltf), WIFI_PHY_VHT, 8, len(vht_payload))
    assert_true(vht_rx.fcs_ok)
    assert_equal(vht_rx.payload_bits, vht_payload)

    for family, mcs, octets in [(WIFI_PHY_HE, 10, 205), (WIFI_PHY_EHT, 13, 264)]:
        var payload = _payload(octets, family)
        var tx = wifi_ldpc_tx_20mhz(Span(payload), family, mcs, symbol_index=1)
        var family_ltf = _scaled_ltf(family, Complex64(1.0))
        var rx = wifi_ldpc_rx_20mhz(Span(tx.waveform), Span(family_ltf), family, mcs, len(payload), 0.01, symbol_index=1, max_iterations=8)
        assert_true(rx.ldpc_converged and rx.service_ok and rx.fcs_ok)
        assert_equal(rx.payload_bits, payload)


def test_tx_builders_against_independent_bit_and_index_formulas() raises:
    var payload = _payload(18, 0x51)
    var tx = wifi_bcc_tx_20mhz(
        Span(payload), WIFI_PHY_HT, 6, symbol_index=2
    )
    var expected_fcs = _manual_fcs(Span(payload))
    assert_equal(tx.fcs, expected_fcs)
    var expected_frame = List[UInt8](capacity=234)
    for _ in range(16):
        expected_frame.append(UInt8(0))
    for bit in payload:
        expected_frame.append(bit)
    for shift in range(32):
        expected_frame.append(
            UInt8((expected_fcs >> UInt64(shift)) & UInt64(1))
        )
    var tail_start = len(expected_frame)
    for _ in range(6):
        expected_frame.append(UInt8(0))
    while len(expected_frame) < 234:
        expected_frame.append(UInt8(0))
    assert_equal(tx.data_field_bits, expected_frame)
    var expected_scrambled = _manual_scramble(
        Span(expected_frame), UInt8(0x5D)
    )
    for i in range(tail_start, tail_start + 6):
        expected_scrambled[i] = UInt8(0)
    assert_equal(tx.scrambled_bits, expected_scrambled)
    var expected_mother = _manual_bcc_unterminated(Span(expected_scrambled))
    assert_equal(tx.mother_bits, expected_mother)
    var rate_three_quarters: List[UInt8] = [1, 1, 1, 0, 0, 1]
    var expected_punctured = _manual_puncture_bits(
        Span(expected_mother), Span(rate_three_quarters)
    )
    assert_equal(tx.punctured_bits, expected_punctured)
    assert_equal(
        tx.interleaved_bits,
        _manual_interleave(
            Span(expected_punctured), 6, 13, 4, 11, 0
        ),
    )

    var he_payload = _payload(205, 0x62)
    var he_tx = wifi_ldpc_tx_20mhz(
        Span(he_payload), WIFI_PHY_HE, 10, symbol_index=4
    )
    var he_fcs = _manual_fcs(Span(he_payload))
    var expected_he_frame = List[UInt8](capacity=16 + len(he_payload) + 32)
    for _ in range(16):
        expected_he_frame.append(UInt8(0))
    for bit in he_payload:
        expected_he_frame.append(bit)
    for shift in range(32):
        expected_he_frame.append(
            UInt8((he_fcs >> UInt64(shift)) & UInt64(1))
        )
    assert_equal(he_tx.fcs, he_fcs)
    assert_equal(he_tx.frame_bits, expected_he_frame)
    assert_equal(
        he_tx.scrambled_bits,
        _manual_scramble(Span(expected_he_frame), UInt8(0x5D)),
    )
    assert_equal(
        he_tx.tone_mapped_bits,
        _manual_tone_map_bits(
            Span(he_tx.rate_matched_bits), 10, 234, 9, 1
        ),
    )

    var acquisition_payload = _payload(9, 0x73)
    var acquisition = wifi_acquisition_tx_20mhz(
        Span(acquisition_payload), WIFI_PHY_HT, 6, symbol_index=2
    )
    assert_equal(acquisition.fcs, _manual_fcs(Span(acquisition_payload)))
    assert_equal((acquisition.ltf_offset, acquisition.signal_offset, acquisition.data_offset), (160, 240, 320))
    var expected_packet = List[Complex64](capacity=400)
    for value in acquisition.stf_waveform:
        expected_packet.append(value)
    for value in acquisition.ltf_waveform:
        expected_packet.append(value)
    for value in acquisition.signal_waveform:
        expected_packet.append(value)
    for value in acquisition.data_waveform:
        expected_packet.append(value)
    assert_equal(acquisition.packet_waveform, expected_packet)


def test_wifi_public_validation_edges() raises:
    var empty_complex = List[Complex64]()
    var empty_complex_rhs = List[Complex64]()
    var one_complex: List[Complex64] = [Complex64(1.0)]
    var wrong_legacy = List[Complex64](length=47, fill=Complex64(0.0))
    with assert_raises():
        _ = wifi_map_legacy_symbol(Span(wrong_legacy))
    var short_legacy = List[Complex64](length=79, fill=Complex64(0.0))
    with assert_raises():
        _ = wifi_extract_legacy_symbol(Span(short_legacy))
    with assert_raises():
        _ = wifi_ls_channel_estimate(
            Span(empty_complex), Span(empty_complex_rhs)
        )
    with assert_raises():
        _ = wifi_equalize(Span(one_complex), Span(empty_complex))
    var no_repetition = List[Complex64](length=64, fill=Complex64(0.0))
    assert_equal(wifi_stf_detect(Span(no_repetition), 0.8), -1)
    with assert_raises():
        _ = wifi_stf_detect(Span(no_repetition), 1.01)
    with assert_raises():
        _ = wifi_stf_coarse_cfo(Span(one_complex), 0)
    var bad_bit: List[UInt8] = [2]
    with assert_raises():
        _ = wifi_fcs(Span(bad_bit))

    var too_few_ru_data = List[Complex64](length=23, fill=Complex64(0.0))
    var ru_pilots: List[Complex64] = [Complex64(1.0), Complex64(-1.0)]
    with assert_raises():
        _ = wifi_map_ru_symbol_20mhz(
            Span(too_few_ru_data), Span(ru_pilots), 26, 4
        )
    var short_ru_spectrum = List[Complex64](
        length=255, fill=Complex64(0.0)
    )
    with assert_raises():
        _ = wifi_extract_ru_data_20mhz(Span(short_ru_spectrum), 26, 4)
    with assert_raises():
        _ = wifi_extract_ru_pilots_20mhz(Span(short_ru_spectrum), 26, 4)

    with assert_raises():
        _ = wifi_bcc_puncture(Span(bad_bit), 1, 2)
    var one_llr: List[Float64] = [1.0]
    with assert_raises():
        _ = wifi_bcc_depuncture_llrs(Span(one_llr), 12, 3, 4)
    var nan_llr: List[Float64] = [nan[DType.float64]()]
    with assert_raises():
        _ = wifi_bcc_depuncture_llrs(Span(nan_llr), 1, 1, 2)
    var ht_profile = wifi_bcc_interleaver_profile(WIFI_PHY_HT, 20)
    var short_bcc = List[UInt8](length=311, fill=UInt8(0))
    with assert_raises():
        _ = wifi_bcc_deinterleave_block(Span(short_bcc), 6, ht_profile)

    var phase_indices: List[Int] = [0]
    var phase_known: List[Complex64] = [Complex64(1.0)]
    var phase_received: List[Complex64] = [Complex64(1.0)]
    var phase = wifi_estimate_pilot_phase(
        Span(phase_received), Span(phase_known), Span(phase_indices)
    )
    var empty_indices = List[Int]()
    with assert_raises():
        _ = wifi_correct_pilot_phase(
            Span(one_complex), Span(empty_indices), phase
        )

    var profile = wifi_ldpc_profile(648, 1, 2)
    var short_llrs = List[Float64](length=647, fill=1.0)
    with assert_raises():
        _ = wifi_ldpc_decode(Span(short_llrs), profile)
    with assert_raises():
        _ = wifi_ltf_channel_estimate_20mhz(
            Span(short_legacy), WIFI_PHY_HT
        )

    var wrong_ht_data = List[Complex64](length=51, fill=Complex64(0.0))
    var ht_pilots = List[Complex64](length=4, fill=Complex64(1.0))
    with assert_raises():
        _ = wifi_map_ht_vht_symbol_20mhz(
            Span(wrong_ht_data), Span(ht_pilots), WIFI_PHY_HT
        )
    var short_ht_spectrum = List[Complex64](
        length=63, fill=Complex64(0.0)
    )
    with assert_raises():
        _ = wifi_extract_ht_vht_data_20mhz(
            Span(short_ht_spectrum), WIFI_PHY_HT
        )
    with assert_raises():
        _ = wifi_extract_ht_vht_pilots_20mhz(
            Span(short_ht_spectrum), WIFI_PHY_HT
        )

    var wrong_tone_bits = List[UInt8](length=467, fill=UInt8(0))
    with assert_raises():
        _ = wifi_ldpc_tone_map_bits(Span(wrong_tone_bits), 2, 242)
    var wrong_tone_llrs = List[Float64](length=467, fill=0.0)
    with assert_raises():
        _ = wifi_ldpc_tone_demap_llrs(Span(wrong_tone_llrs), 2, 242)

    var non_octet: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = wifi_bcc_tx_20mhz(Span(non_octet), WIFI_PHY_HT, 6)
    with assert_raises():
        var empty_ltf = List[Complex64]()
        _ = wifi_bcc_rx_20mhz(
            Span(empty_complex), Span(empty_ltf), WIFI_PHY_HT, 6, 1
        )
    with assert_raises():
        _ = wifi_ldpc_tx_20mhz(Span(non_octet), WIFI_PHY_HE, 10)
    with assert_raises():
        var empty_ldpc_ltf = List[Complex64]()
        _ = wifi_ldpc_rx_20mhz(
            Span(empty_complex), Span(empty_ldpc_ltf), WIFI_PHY_HE, 10, 1, 0.1
        )


def test_acquisition_stf_lsig_fine_cfo_and_seeded_link() raises:
    var stf_spectrum = wifi_stf_spectrum_20mhz()
    var scale = sqrt(13.0 / 6.0)
    var expected_stf_spectrum = List[Complex64](
        length=64, fill=Complex64(0.0, 0.0)
    )
    var stf_carriers: List[Int] = [
        -24, -20, -16, -12, -8, -4, 4, 8, 12, 16, 20, 24
    ]
    var stf_signs: List[Int] = [1, -1, 1, -1, -1, 1, -1, -1, 1, 1, 1, 1]
    for i in range(12):
        var subcarrier = stf_carriers[i]
        var value = Float64(stf_signs[i]) * scale
        expected_stf_spectrum[
            subcarrier if subcarrier >= 0 else 64 + subcarrier
        ] = Complex64(value, value)
    assert_equal(stf_spectrum, expected_stf_spectrum)
    var short = wifi_stf_short_symbol_20mhz()
    var stf = wifi_stf_waveform_20mhz()
    assert_equal((len(short), len(stf)), (16, 160))
    var expected_stf_symbol = _naive_ofdm_symbol(
        Span(expected_stf_spectrum), 0
    )
    for i in range(16):
        assert_true(
            abs(short[i].re - expected_stf_symbol[i].re)
            <= FFT_TOLERANCE
        )
        assert_true(
            abs(short[i].im - expected_stf_symbol[i].im)
            <= FFT_TOLERANCE
        )
    for i in range(16):
        for repetition in range(10):
            assert_equal(stf[repetition * 16 + i], short[i])

    var signal_rate: List[UInt8] = [1, 1, 0, 1]
    for length_octets in [0, 1, 13, 4095]:
        var lsig = wifi_legacy_signal_tx_20mhz(length_octets)
        var expected_bits = _manual_signal_bits(
            Span(signal_rate), length_octets
        )
        var expected_coded = _manual_bcc_unterminated(Span(expected_bits))
        var expected_interleaved = _manual_interleave(
            Span(expected_coded), 1, 16, 3, 0, 0
        )
        var expected_symbols = List[Complex64](capacity=48)
        for bit in expected_interleaved:
            expected_symbols.append(
                Complex64(-1.0 if bit == 1 else 1.0)
            )
        var expected_signal_spectrum = List[Complex64](
            length=64, fill=Complex64(0.0, 0.0)
        )
        var data_carriers = _legacy_carriers_static()
        for i in range(48):
            var subcarrier = data_carriers[i]
            expected_signal_spectrum[
                subcarrier if subcarrier >= 0 else 64 + subcarrier
            ] = expected_symbols[i]
        expected_signal_spectrum[64 - 21] = Complex64(1.0)
        expected_signal_spectrum[64 - 7] = Complex64(1.0)
        expected_signal_spectrum[7] = Complex64(1.0)
        expected_signal_spectrum[21] = Complex64(-1.0)
        var expected_waveform = _naive_ofdm_symbol(
            Span(expected_signal_spectrum), 16
        )
        assert_equal(lsig.rate_bits, signal_rate)
        assert_equal(lsig.length_octets, length_octets)
        assert_equal(lsig.bits, expected_bits)
        assert_equal(lsig.coded_bits, expected_coded)
        assert_equal(lsig.interleaved_bits, expected_interleaved)
        assert_equal(lsig.symbols, expected_symbols)
        _assert_complex_lists_close(
            lsig.waveform, expected_waveform, FFT_TOLERANCE
        )

    var payload = _payload(9, 3)
    var tx = wifi_acquisition_tx_20mhz(Span(payload), WIFI_PHY_HT, 6, symbol_index=3)
    var config = WifiAcquisitionChannelConfig(timing_offset=9, normalized_cfo=0.002, noise_variance=1.0e-10, rician_k_factor=30.0, seed=UInt64(0x80211E))
    var channel = wifi_acquisition_apply_channel_20mhz(Span(tx.packet_waveform), config)
    var repeat = wifi_acquisition_apply_channel_20mhz(Span(tx.packet_waveform), config)
    assert_equal(channel.observation, repeat.observation)
    var analytic_config = WifiAcquisitionChannelConfig(
        timing_offset=3,
        normalized_cfo=-0.00125,
        noise_variance=0.0,
        rician_k_factor=7.0,
        seed=UInt64(0xC0FFEE),
    )
    var analytic_channel = wifi_acquisition_apply_channel_20mhz(
        Span(tx.packet_waveform), analytic_config
    )
    assert_equal(
        len(analytic_channel.observation),
        len(analytic_channel.faded_waveform) + 3,
    )
    for i in range(len(analytic_channel.observation)):
        var expected = Complex64(0.0, 0.0)
        if i >= 3:
            var faded = analytic_channel.faded_waveform[i - 3]
            var angle = TWO_PI * analytic_config.normalized_cfo * Float64(i)
            expected = faded * Complex64(cos(angle), sin(angle))
        assert_true(
            abs(analytic_channel.observation[i].re - expected.re) <= TIGHT
        )
        assert_true(
            abs(analytic_channel.observation[i].im - expected.im) <= TIGHT
        )
    assert_equal(wifi_ltf_fine_timing_20mhz(Span(channel.observation), WIFI_PHY_HT, 169), 169)
    # On an isolated LTF, the CP and body copies are exactly 64 apart.
    var cfo_ltf = apply_cfo(Span(tx.ltf_waveform), 0.00125)
    assert_true(abs(wifi_ltf_fine_cfo_20mhz(Span(cfo_ltf), 0) - 0.00125) <= TIGHT)
    var rx = wifi_acquisition_rx_20mhz(Span(channel.observation), WIFI_PHY_HT, 6, len(payload), symbol_index=3, detection_threshold=0.82, llr_noise_variance=1.0e-8)
    assert_true(abs(rx.packet_start - 9) <= 2)
    assert_true(abs(rx.coarse_cfo + rx.fine_cfo - 0.002) < 3.0e-6)
    assert_true(rx.signal_ok and rx.service_ok and rx.fcs_ok)
    assert_equal(rx.payload_bits, payload)
    with assert_raises():
        _ = wifi_ltf_fine_timing_20mhz(Span(channel.observation), WIFI_PHY_HE, 169)


def test_legacy_l_ltf_full_independent_artifacts() raises:
    """Full packed static spectrum plus test-only O(N^2) inverse DFT."""
    var expected_spectrum = _independent_ltf_spectrum(WIFI_PHY_HT)
    for subcarrier in [-28, -27, 27, 28]:
        expected_spectrum[
            subcarrier if subcarrier >= 0 else 64 + subcarrier
        ] = Complex64(0.0, 0.0)
    var actual_spectrum = wifi_legacy_ltf_spectrum_20mhz()
    assert_equal(actual_spectrum, expected_spectrum)
    var long_symbol = _naive_ofdm_symbol(Span(expected_spectrum), 0)
    var expected_waveform = List[Complex64](capacity=160)
    for i in range(32, 64):
        expected_waveform.append(long_symbol[i])
    for _ in range(2):
        for sample in long_symbol:
            expected_waveform.append(sample)
    var actual_waveform = wifi_legacy_ltf_waveform_20mhz()
    _assert_complex_lists_close(
        actual_waveform, expected_waveform, FFT_TOLERANCE
    )
    for i in range(32):
        assert_equal(actual_waveform[i], actual_waveform[64 + i])
    for i in range(64):
        assert_equal(actual_waveform[32 + i], actual_waveform[96 + i])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
