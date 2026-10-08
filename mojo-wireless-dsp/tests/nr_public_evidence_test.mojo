"""Independent numerical evidence for the public NR primitive surface.

The existing feature tests provide broad conformance and end-to-end coverage.
This file deliberately supplies different oracles against TS 38.211 V18.9.0:
literal recurrences, closed-form unitary DFT values, and hand-computed complex
division. Encoder/decoder round trips are never used as the expected result.
"""

from std.collections import Span
from std.math import cos, sin, sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr import (
    NRResourceGrid,
    NRPUSCHConfig,
    NRPUCCHFormat2Config,
    PRACH_FORMAT_A1,
    PRACH_SET_UNRESTRICTED,
    nr_gold_bits,
    nr_qpsk_sequence,
    nr_pusch_scramble,
    nr_pusch_descramble_llrs,
    nr_pusch_transform_precoding,
    nr_pusch_transform_deprecoding,
    nr_pusch_dmrs,
    nr_pusch_dmrs_c_init,
    nr_pusch_reference_dmrs,
    nr_pusch_allocation_subcarriers,
    nr_pusch_data_re_count,
    nr_map_pusch_single_layer,
    nr_pusch_grid_to_waveform,
    nr_pusch_waveform_to_grid,
    nr_ls_channel_estimate_comb2,
    nr_equalize_pdsch_comb2,
    nr_pucch_low_papr_sequence_12,
    nr_pucch_format0_sequence,
    nr_pucch_cyclic_shift_index,
    nr_pucch_scramble,
    nr_pi_over_2_bpsk,
    nr_pucch_format3_4_modulate,
    nr_pucch_block_spread,
    nr_pucch_block_despread,
    nr_pucch_format1_occ,
    nr_pucch_format1_data_occ,
    nr_pucch_format1_dmrs_occ,
    nr_pucch_format1_apply_occ,
    nr_extract_pucch_format2_data,
    nr_extract_pucch_format2_dmrs,
    nr_extract_pucch_format3_4_data_non_interlaced,
    nr_extract_pucch_format3_4_dmrs_non_interlaced,
    nr_prach_root_sequence,
    nr_prach_sequence,
    nr_prach_logical_root_count,
    nr_prach_sequence_standard,
    nr_detect_prach_unrestricted,
    nr_detect_prach_multi_root,
    nr_prach_format_parameters,
    nr_prach_allocate_preambles,
    nr_prach_preamble_sequence,
    nr_prach_frequency_sequence,
    nr_prach_normalized_waveform,
    nr_prach_normalized_cp_samples,
    nr_transport_crc,
    nr_ldpc_crc24b,
    nr_pbch_crc24c,
    nr_uci_crc_length,
    nr_uci_code_block_count,
    nr_pucch_uci_capacity,
    nr_uci_encode,
    nr_uci_decode,
    nr_pucch_format2_modulate,
    nr_pucch_format2_reference_dmrs,
    nr_pucch_format2_coded_bit_capacity,
    nr_pucch_format2_bits_checksum,
    nr_pucch_format2_waveform_sample_count,
    nr_pucch_format2_data_re_count,
    nr_pucch_format2_dmrs_re_count,
    nr_pucch_format2_grid_to_waveform,
    nr_pucch_format2_waveform_to_grid,
    nr_pucch_format2_flat_channel,
    nr_pucch_format2_descramble_llrs,
)

comptime _PI = 3.1415926535897932384626433832795


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _reference_gold(c_init: UInt32, length: Int) -> List[UInt8]:
    # Direct scalar transcription of TS 38.211 5.2.1.  Unlike the production
    # implementation this keeps only two 31-bit registers.
    var x1 = UInt32(1)
    var x2 = c_init & UInt32(0x7FFFFFFF)
    var result = List[UInt8](capacity=length)
    for n in range(1600 + length):
        var output = UInt8((x1 ^ x2) & UInt32(1))
        var x1_feedback = ((x1 >> 3) ^ x1) & UInt32(1)
        var x2_feedback = (
            (x2 >> 3) ^ (x2 >> 2) ^ (x2 >> 1) ^ x2
        ) & UInt32(1)
        x1 = (x1 >> 1) | (x1_feedback << 30)
        x2 = (x2 >> 1) | (x2_feedback << 30)
        if n >= 1600:
            result.append(output)
    return result^


def _reference_unitary_dft(values: Span[Complex64, ...], inverse: Bool) -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    var direction = 1.0 if inverse else -1.0
    var scale = 1.0 / sqrt(Float64(len(values)))
    for k in range(len(values)):
        var acc = Complex64(0.0, 0.0)
        for n in range(len(values)):
            var angle = direction * 2.0 * _PI * Float64(k * n) / Float64(len(values))
            var value = Complex64(values[n].re, values[n].im)
            acc = acc + value * Complex64(cos(angle), sin(angle))
        result.append(acc * Complex64(scale, 0.0))
    return result^


def _hard_llrs(bits: Span[UInt8, ...], magnitude: Float64) -> List[Float64]:
    var result = List[Float64](capacity=len(bits))
    for i in range(len(bits)):
        result.append(magnitude if bits[i] == 0 else -magnitude)
    return result^


def _reference_prach_sequence(
    root: Int, length: Int, cyclic_shift: Int
) -> List[Complex64]:
    var result = List[Complex64](capacity=length)
    for n in range(length):
        var source = (n + cyclic_shift) % length
        var angle = (
            -_PI * Float64(root * source * (source + 1)) / Float64(length)
        )
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


def test_gold_and_qpsk_seeded_against_scalar_standard_oracle() raises:
    var seeds: List[UInt32] = [0, 1, 0x1234567, 0x7FFFFFFF]
    for seed in seeds:
        var expected = _reference_gold(seed, 257)
        assert_equal(nr_gold_bits(seed, 257), expected)
        var qpsk = nr_qpsk_sequence(seed, 128)
        var scale = 1.0 / sqrt(2.0)
        for i in range(128):
            _assert_complex_close(
                qpsk[i],
                Complex64(
                    scale * (1.0 - 2.0 * Float64(expected[2 * i])),
                    scale * (1.0 - 2.0 * Float64(expected[2 * i + 1])),
                ),
                1.0e-15,
            )
    assert_equal(len(nr_gold_bits(UInt32(7), 0)), 0)
    with assert_raises():
        _ = nr_gold_bits(UInt32(0), -1)


def test_pusch_dft_seeded_float64_differential_and_impulses() raises:
    var state = UInt64(0xD1FF3E20260821)
    var values = List[Complex64](capacity=24)
    for _ in range(24):
        state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
        var re = Float64(Int((state >> 33) & 0xFFFF) - 32768) / 32768.0
        state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
        var im = Float64(Int((state >> 33) & 0xFFFF) - 32768) / 32768.0
        values.append(Complex64(re, im))
    var actual = nr_pusch_transform_precoding(Span(values))
    var expected = _reference_unitary_dft(Span(values), False)
    for i in range(24):
        _assert_complex_close(actual[i], expected[i], 2.0e-12)
    var inverse = nr_pusch_transform_deprecoding(Span(values))
    expected = _reference_unitary_dft(Span(values), True)
    for i in range(24):
        _assert_complex_close(inverse[i], expected[i], 2.0e-12)

    var impulse = List[Complex64](length=12, fill=Complex64(0.0))
    impulse[0] = Complex64(1.0)
    actual = nr_pusch_transform_precoding(Span(impulse))
    for value in actual:
        _assert_complex_close(value, Complex64(1.0 / sqrt(12.0)), 1.0e-15)
    with assert_raises():
        _ = nr_pusch_transform_precoding(Span(values)[:13])


def test_comb2_ls_and_equalizer_hand_computed_float64_oracle() raises:
    var known: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(0.0, 1.0), Complex64(-1.0, 0.0)
    ]
    # Pilot channels are (1+2j), (3+4j), (5+6j); linear interpolation over
    # positions 0,2,4 therefore gives H[k]=(1+k)+j(2+k).
    var received: List[Complex64] = [
        Complex64(1.0, 2.0), Complex64(-4.0, 3.0), Complex64(-5.0, -6.0)
    ]
    var channel = nr_ls_channel_estimate_comb2(Span(received), Span(known), 5, 0)
    for k in range(5):
        _assert_complex_close(
            channel[k], Complex64(Float64(k + 1), Float64(k + 2)), 1.0e-12
        )
    var symbols: List[Complex64] = [Complex64(2.0, -1.0), Complex64(-0.5, 3.0)]
    var observations: List[Complex64] = [symbols[0] * channel[1], symbols[1] * channel[3]]
    var equalized = nr_equalize_pdsch_comb2(Span(observations), Span(channel), 0)
    for i in range(2):
        _assert_complex_close(equalized[i], symbols[i], 2.0e-15)


def test_pucch_prach_crc_and_uci_static_analytic_edges() raises:
    var bits: List[UInt8] = [0, 1, 1, 0]
    var pi2 = nr_pi_over_2_bpsk(Span(bits))
    var s = 1.0 / sqrt(2.0)
    var expected: List[Complex64] = [
        Complex64(s, s), Complex64(s, -s), Complex64(-s, -s), Complex64(-s, s)
    ]
    for i in range(4):
        _assert_complex_close(pi2[i], expected[i], 1.0e-15)
    var spread = nr_pucch_block_spread(Span(expected), 4, 1)
    var despread = nr_pucch_block_despread(Span(spread), 4, 1)
    for i in range(4):
        _assert_complex_close(despread[i], expected[i], 2.0e-15)

    var root = nr_prach_root_sequence(1, 139)
    for n in [0, 1, 2, 17, 138]:
        var angle = -_PI * Float64(n * (n + 1)) / 139.0
        _assert_complex_close(root[n], Complex64(cos(angle), sin(angle)), 1.0e-14)
        assert_true(abs(root[n].magnitude_squared() - 1.0) <= 2.0e-15)

    var ascii = List[UInt8](capacity=72)
    for byte in [49, 50, 51, 52, 53, 54, 55, 56, 57]:
        for bit in range(8):
            ascii.append(UInt8((byte >> (7 - bit)) & 1))
    assert_equal(nr_ldpc_crc24b(Span(ascii)), UInt64(0x23EF52))
    # CRC-24C / CRC-24/INTERLAKEN check value for "123456789".
    assert_equal(nr_pbch_crc24c(Span(ascii)), UInt64(0xF48279))
    assert_equal(nr_transport_crc(Span(ascii)), UInt64(0x31C3))

    assert_equal(nr_uci_crc_length(3), 0)
    assert_equal(nr_uci_crc_length(12), 6)
    assert_equal(nr_uci_crc_length(20), 11)
    assert_equal(nr_uci_code_block_count(359, 1088), 1)
    assert_equal(nr_uci_code_block_count(360, 1088), 2)
    assert_equal(nr_pucch_uci_capacity(2, 3, 2), 96)
    assert_equal(nr_pucch_uci_capacity(4, 1, 10, spreading_factor=4), 60)
    with assert_raises():
        _ = nr_uci_crc_length(2)


def test_uplink_gold_dmrs_prach_seeded_properties_and_edges() raises:
    var state = UInt64(0xA11CE5EED)
    var payload = List[UInt8](capacity=97)
    var input_llrs = List[Float64](capacity=97)
    for i in range(97):
        state = state * UInt64(6364136223846793005) + UInt64(1)
        payload.append(UInt8((state >> 63) & 1))
        input_llrs.append(Float64(i + 1) * (1.0 if i % 3 != 0 else -1.0))

    comptime rnti = 0x4567
    comptime codeword = 1
    comptime n_id = 721
    var gold = _reference_gold(
        UInt32((rnti << 15) + (codeword << 14) + n_id), len(payload)
    )
    var scrambled = nr_pusch_scramble(
        Span(payload), rnti, codeword, n_id
    )
    var descrambled = nr_pusch_descramble_llrs(
        Span(input_llrs), rnti, codeword, n_id
    )
    for i in range(len(payload)):
        assert_equal(scrambled[i], payload[i] ^ gold[i])
        assert_equal(
            descrambled[i],
            input_llrs[i] if gold[i] == 0 else -input_llrs[i],
        )

    var invalid_bits: List[UInt8] = [0, 2]
    with assert_raises():
        _ = nr_pusch_scramble(Span(invalid_bits), rnti, codeword, n_id)
    with assert_raises():
        _ = nr_pusch_descramble_llrs(Span(input_llrs), -1, 0, 0)

    comptime slot = 7
    comptime symbol = 4
    comptime dmrs_n_id = 321
    comptime n_scid = 1
    var dmrs = nr_pusch_dmrs(slot, symbol, dmrs_n_id, n_scid, 73)
    var c_init = UInt32(
        (
            (1 << 17) * (14 * slot + symbol + 1) * (2 * dmrs_n_id + 1)
            + 2 * dmrs_n_id + n_scid
        ) % (1 << 31)
    )
    var dmrs_gold = _reference_gold(c_init, 2 * len(dmrs))
    var scale = 1.0 / sqrt(2.0)
    for i in range(len(dmrs)):
        _assert_complex_close(
            dmrs[i],
            Complex64(
                scale * (1.0 - 2.0 * Float64(dmrs_gold[2 * i])),
                scale * (1.0 - 2.0 * Float64(dmrs_gold[2 * i + 1])),
            ),
            1.0e-15,
        )
    with assert_raises():
        _ = nr_pusch_dmrs(0, 14, 0, 0, 1)

    var eleven = List[Complex64](length=11, fill=Complex64(0.0))
    with assert_raises():
        _ = nr_pusch_transform_deprecoding(Span(eleven))

    var expected_prach = _reference_prach_sequence(1, 139, 26)
    var actual_prach = nr_prach_sequence(1, 139, 26)
    for i in range(139):
        _assert_complex_close(actual_prach[i], expected_prach[i], 1.0e-14)
    with assert_raises():
        _ = nr_prach_sequence(1, 139, -1)

    var received = List[Complex64](capacity=139)
    var gain = Complex64(0.73, -0.29)
    for i in range(139):
        received.append(expected_prach[i] * gain)
    var detection = nr_detect_prach_unrestricted(
        Span(received), 1, 13, 4
    )
    assert_equal(detection.preamble_index, 2)
    assert_equal(detection.cyclic_shift, 26)
    assert_true(abs(detection.metric - 1.0) <= 2.0e-12)
    with assert_raises():
        _ = nr_detect_prach_unrestricted(Span(received), 1, 13, 0)


def test_pucch_analytic_properties_and_validation_edges() raises:
    var format0 = nr_pucch_format0_sequence(0, 0)
    var s = 1.0 / sqrt(2.0)
    _assert_complex_close(format0[0], Complex64(-s, -s), 1.0e-12)
    _assert_complex_close(format0[1], Complex64(s, s), 1.0e-12)
    _assert_complex_close(format0[5], Complex64(-s, s), 1.0e-12)
    for value in format0:
        assert_true(abs(value.magnitude_squared() - 1.0) <= 2.0e-15)
    with assert_raises():
        _ = nr_pucch_format0_sequence(-1, 0)
    with assert_raises():
        _ = nr_pucch_low_papr_sequence_12(30, 0)

    var bits = List[UInt8](capacity=63)
    for i in range(63):
        bits.append(UInt8((17 * i + i // 5 + 1) & 1))
    comptime rnti = 0x2345
    comptime n_id = 511
    var gold = _reference_gold(UInt32((rnti << 10) + n_id), len(bits))
    var scrambled = nr_pucch_scramble(Span(bits), rnti, n_id)
    for i in range(len(bits)):
        assert_equal(scrambled[i], bits[i] ^ gold[i])
    var invalid_bits: List[UInt8] = [0, 2]
    with assert_raises():
        _ = nr_pucch_scramble(Span(invalid_bits), rnti, n_id)

    var pi2 = nr_pi_over_2_bpsk(Span(bits))
    for i in range(len(bits)):
        var sign = 1.0 - 2.0 * Float64(bits[i])
        var expected = (
            Complex64(s * sign, s * sign)
            if i % 2 == 0
            else Complex64(-s * sign, s * sign)
        )
        _assert_complex_close(pi2[i], expected, 1.0e-15)
    with assert_raises():
        _ = nr_pi_over_2_bpsk(Span(invalid_bits))

    var even_bits = List[UInt8](capacity=64)
    for i in range(64):
        even_bits.append(bits[i % len(bits)])
    var format34 = nr_pucch_format3_4_modulate(
        Span(even_bits), rnti, n_id
    )
    var format34_gold = _reference_gold(
        UInt32((rnti << 10) + n_id), len(even_bits)
    )
    for i in range(len(format34)):
        _assert_complex_close(
            format34[i],
            Complex64(
                s
                * (1.0 - 2.0 * Float64(even_bits[2 * i] ^ format34_gold[2 * i])),
                s
                * (1.0 - 2.0 * Float64(even_bits[2 * i + 1] ^ format34_gold[2 * i + 1])),
            ),
            1.0e-15,
        )
    var format2 = nr_pucch_format2_modulate(Span(even_bits), rnti, n_id)
    for i in range(len(format2)):
        _assert_complex_close(
            format2[i],
            Complex64(
                s
                * (1.0 - 2.0 * Float64(even_bits[2 * i] ^ format34_gold[2 * i])),
                s
                * (1.0 - 2.0 * Float64(even_bits[2 * i + 1] ^ format34_gold[2 * i + 1])),
            ),
            1.0e-15,
        )
    var odd_bits: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = nr_pucch_format3_4_modulate(Span(odd_bits), rnti, n_id)
    var too_short_format2: List[UInt8] = [0, 1]
    with assert_raises():
        _ = nr_pucch_format2_modulate(Span(too_short_format2), rnti, n_id)

    var originals: List[Complex64] = [
        Complex64(0.25, -0.75), Complex64(-1.25, 0.5)
    ]
    var analytically_spread = List[Complex64](capacity=8)
    for value in originals:
        for m in range(4):
            var angle = -2.0 * _PI * Float64(3 * m) / 4.0
            analytically_spread.append(value * Complex64(cos(angle), sin(angle)))
    var spread = nr_pucch_block_spread(Span(originals), 4, 3)
    for i in range(len(analytically_spread)):
        _assert_complex_close(spread[i], analytically_spread[i], 2.0e-15)
    var despread = nr_pucch_block_despread(
        Span(analytically_spread), 4, 3
    )
    for i in range(len(originals)):
        _assert_complex_close(despread[i], originals[i], 2.0e-15)
    with assert_raises():
        _ = nr_pucch_block_despread(Span(analytically_spread)[:7], 4, 3)
    with assert_raises():
        _ = nr_pucch_block_spread(Span(originals), 3, 0)

    for length in range(1, 8):
        for row in range(length):
            var occ = nr_pucch_format1_occ(length, row)
            var energy = 0.0
            for value in occ:
                energy += value.magnitude_squared()
            assert_true(abs(energy - Float64(length)) <= 2.0e-12)
    with assert_raises():
        _ = nr_pucch_format1_occ(0, 0)

    for symbols in range(4, 15):
        var data_occ = nr_pucch_format1_data_occ(symbols, 0)
        var dmrs_occ = nr_pucch_format1_dmrs_occ(symbols, 0)
        for value in data_occ:
            assert_true(abs(value.magnitude_squared() - 1.0) <= 2.0e-15)
        for value in dmrs_occ:
            assert_true(abs(value.magnitude_squared() - 1.0) <= 2.0e-15)
    with assert_raises():
        _ = nr_pucch_format1_data_occ(3, 0)
    with assert_raises():
        _ = nr_pucch_format1_dmrs_occ(15, 0)

    var sequence: List[Complex64] = [
        Complex64(2.0, -1.0), Complex64(-3.0, 0.5)
    ]
    var occ: List[Complex64] = [
        Complex64(1.0), Complex64(0.0, 1.0), Complex64(-1.0)
    ]
    var applied = nr_pucch_format1_apply_occ(Span(sequence), Span(occ))
    for row in range(3):
        for column in range(2):
            _assert_complex_close(
                applied[2 * row + column],
                occ[row] * sequence[column],
                0.0,
            )
    var empty = List[Complex64]()
    with assert_raises():
        _ = nr_pucch_format1_apply_occ(Span(empty), Span(occ))

    # Populate the grid independently, without using the public mapper.
    var grid = NRResourceGrid(4, 48)
    var expected_data = List[Complex64]()
    var expected_dmrs = List[Complex64]()
    for local_symbol in range(2):
        for local in range(12):
            var value = Complex64(
                Float64(100 * local_symbol + local),
                -Float64(100 * local_symbol + local) - 0.25,
            )
            grid[1 + local_symbol, 12 + local] = value
            if local % 3 == 1:
                expected_dmrs.append(value)
            else:
                expected_data.append(value)
    assert_equal(
        nr_extract_pucch_format2_data(grid, 1, 12, 1, 2), expected_data
    )
    assert_equal(
        nr_extract_pucch_format2_dmrs(grid, 1, 12, 1, 2), expected_dmrs
    )
    with assert_raises():
        _ = nr_extract_pucch_format2_data(grid, 4, 12, 1, 1)
    with assert_raises():
        _ = nr_extract_pucch_format2_dmrs(grid, 1, 42, 1, 1)

    # Format-3/4 extraction from a grid populated directly from the normative
    # four-symbol position rule: without hopping, local symbol 1 is DM-RS.
    var format34_grid = NRResourceGrid(14, 96)
    var expected_format34_data = List[Complex64]()
    var expected_format34_dmrs = List[Complex64]()
    for local_symbol in range(4):
        for local_subcarrier in range(12):
            var value = Complex64(
                Float64(100 * local_symbol + local_subcarrier + 1),
                Float64(local_symbol - local_subcarrier) - 0.5,
            )
            format34_grid[3 + local_symbol, 24 + local_subcarrier] = value
            if local_symbol == 1:
                expected_format34_dmrs.append(value)
            else:
                expected_format34_data.append(value)
    assert_equal(
        nr_extract_pucch_format3_4_data_non_interlaced(
            format34_grid, 3, 24, 1, 4
        ),
        expected_format34_data,
    )
    assert_equal(
        nr_extract_pucch_format3_4_dmrs_non_interlaced(
            format34_grid, 3, 24, 1, 4
        ),
        expected_format34_dmrs,
    )
    with assert_raises():
        _ = nr_extract_pucch_format3_4_data_non_interlaced(
            format34_grid, 3, 90, 1, 4
        )
    with assert_raises():
        _ = nr_extract_pucch_format3_4_dmrs_non_interlaced(
            format34_grid, 3, 24, 1, 3
        )


def test_prach_uplink_and_pucch_waveform_independent_oracles() raises:
    var parameters = nr_prach_format_parameters(
        PRACH_FORMAT_A1, numerology=0, sequence_length=139
    )
    var allocations = nr_prach_allocate_preambles(
        0, 139, 13, PRACH_SET_UNRESTRICTED, 1
    )
    var preamble = nr_prach_preamble_sequence(allocations[0], 139)
    var expected_preamble = _reference_prach_sequence(
        allocations[0].root_u, 139, allocations[0].cyclic_shift
    )
    var standard_sequence = nr_prach_sequence_standard(
        allocations[0].root_u, 139, allocations[0].cyclic_shift
    )
    for i in range(139):
        _assert_complex_close(preamble[i], expected_preamble[i], 1.0e-14)
        _assert_complex_close(
            standard_sequence[i], expected_preamble[i], 1.0e-14
        )
    with assert_raises():
        _ = nr_prach_preamble_sequence(allocations[0], 140)
    with assert_raises():
        _ = nr_prach_sequence_standard(allocations[0].root_u, 139, 139)

    # The target crosses from the first logical root to the second; its input
    # is generated only by the scalar Zadoff-Chu formula above.
    var detector_allocations = nr_prach_allocate_preambles(
        0, 139, 13, PRACH_SET_UNRESTRICTED, 14
    )
    var detector_target = detector_allocations[12]
    var detector_reference = _reference_prach_sequence(
        detector_target.root_u, 139, detector_target.cyclic_shift
    )
    var detector_input = List[Complex64](capacity=139)
    var detector_gain = Complex64(-0.41, 0.87)
    for value in detector_reference:
        detector_input.append(value * detector_gain)
    var multi_detection = nr_detect_prach_multi_root(
        Span(detector_input), 0, 13, PRACH_SET_UNRESTRICTED, 14
    )
    assert_equal(multi_detection.preamble_index, 12)
    assert_equal(multi_detection.logical_root_index, detector_target.logical_root_index)
    assert_equal(multi_detection.root_u, detector_target.root_u)
    assert_equal(multi_detection.cyclic_shift, detector_target.cyclic_shift)
    assert_true(abs(multi_detection.metric - 1.0) <= 3.0e-12)

    var frequency = nr_prach_frequency_sequence(Span(preamble))
    var unitary = _reference_unitary_dft(Span(expected_preamble), False)
    for i in range(139):
        _assert_complex_close(
            frequency[i],
            unitary[i] * Complex64(sqrt(139.0), 0.0),
            3.0e-10,
        )
    with assert_raises():
        _ = nr_prach_frequency_sequence(Span(preamble)[:138])
    var wrong_preamble = List[Complex64](length=138, fill=Complex64(0.0))
    with assert_raises():
        _ = nr_prach_normalized_waveform(Span(wrong_preamble), parameters)
    var normalized = nr_prach_normalized_waveform(Span(preamble), parameters)
    assert_true(len(normalized) > len(preamble))

    var config = NRPUSCHConfig(16, 2, 2, 0, 0, 1, 0, 30, 0, 0x44)
    var dmrs = nr_pusch_reference_dmrs(config)
    assert_equal(len(dmrs), 6)
    for value in dmrs:
        assert_true(abs(value.magnitude_squared() - 1.0) <= 2.0e-15)
    var transform_config = NRPUSCHConfig(
        16, 2, 2, 0, 0, 1, 0, 30, 0, 0x44,
        transform_precoding=True, dmrs_cyclic_shift=11,
    )
    var transform_dmrs = nr_pusch_reference_dmrs(transform_config)
    assert_equal(len(transform_dmrs), 6)
    for value in transform_dmrs:
        assert_true(abs(value.magnitude_squared() - 1.0) <= 2.0e-15)

    var data = List[Complex64](capacity=12)
    for i in range(12):
        data.append(Complex64(Float64(i + 1), -Float64(i + 1)))
    var mapped = nr_map_pusch_single_layer(config, Span(data), Span(dmrs))
    for local in range(16):
        if local < 12 and local % 2 == 0:
            _assert_complex_close(mapped[0, local], dmrs[local // 2], 0.0)
        else:
            _assert_complex_close(mapped[0, local], Complex64(0.0), 0.0)
        _assert_complex_close(
            mapped[1, local], data[local] if local < 12 else Complex64(0.0), 0.0
        )
    with assert_raises():
        _ = nr_map_pusch_single_layer(
            config, Span(data)[:11], Span(dmrs)
        )

    var independent_grid = NRResourceGrid(2, 16)
    independent_grid[0, 0] = Complex64(1.0)
    independent_grid[1, 1] = Complex64(0.0, 1.0)
    var waveform = nr_pusch_grid_to_waveform(config, independent_grid)
    for symbol in range(2):
        var spectrum = List[Complex64](capacity=16)
        for k in range(16):
            spectrum.append(independent_grid[symbol, k])
        var expected_unitary = _reference_unitary_dft(Span(spectrum), True)
        for local in range(18):
            var time_index = (local + 14) % 16
            _assert_complex_close(
                waveform[18 * symbol + local],
                expected_unitary[time_index] * Complex64(0.25, 0.0),
                2.0e-14,
            )
    var wrong_grid = NRResourceGrid(2, 32)
    with assert_raises():
        _ = nr_pusch_grid_to_waveform(config, wrong_grid)

    # Independently synthesize two CP-OFDM symbols: DC on row zero and FFT bin
    # one on row one.  This exercises the inverse public direction without a
    # production modulator roundtrip.
    var analytic_pusch_waveform = List[Complex64](capacity=36)
    for _ in range(18):
        analytic_pusch_waveform.append(Complex64(1.0 / 16.0))
    for local in range(18):
        var time_index = (local + 14) % 16
        var angle = 2.0 * _PI * Float64(time_index) / 16.0
        analytic_pusch_waveform.append(
            Complex64(cos(angle) / 16.0, sin(angle) / 16.0)
        )
    var analytic_pusch_grid = nr_pusch_waveform_to_grid(
        config, Span(analytic_pusch_waveform)
    )
    for subcarrier in range(16):
        _assert_complex_close(
            analytic_pusch_grid[0, subcarrier],
            Complex64(1.0) if subcarrier == 0 else Complex64(0.0),
            2.0e-14,
        )
        _assert_complex_close(
            analytic_pusch_grid[1, subcarrier],
            Complex64(1.0) if subcarrier == 1 else Complex64(0.0),
            2.0e-14,
        )
    with assert_raises():
        _ = nr_pusch_waveform_to_grid(
            config, Span(analytic_pusch_waveform)[:35]
        )

    # Independent TS-derived UCI K=12/E=96 codeword, not an encoder roundtrip.
    var static_uci: List[UInt8] = [
        0,1,0,0,0,1,0,0,1,1,1,0,0,0,0,0,
        0,1,0,0,1,1,1,1,1,1,0,0,0,0,0,1,
        1,0,1,1,1,0,1,1,1,0,1,1,0,1,1,0,
        0,0,0,0,1,1,0,1,1,0,0,0,0,1,1,1,
        1,0,0,1,0,1,1,0,0,0,0,0,0,1,1,1,
        1,1,0,1,1,0,0,0,1,1,1,1,0,0,1,1,
    ]
    var expected_uci: List[UInt8] = [1,0,0,1,1,0,0,1,1,0,0,1]
    var encoded_uci = nr_uci_encode(Span(expected_uci), 96)
    assert_equal(encoded_uci.bits, static_uci)
    var decoded_uci = nr_uci_decode(Span(_hard_llrs(Span(static_uci), 24.0)), 12)
    assert_equal(decoded_uci.bits, expected_uci)
    assert_true(decoded_uci.crc_ok and decoded_uci.parity_ok)
    with assert_raises():
        _ = nr_uci_decode(Span(_hard_llrs(Span(static_uci), 24.0)), 2)

    var reference_config = NRPUCCHFormat2Config(
        128, 4, 159, 12, 2, 108, 1023, 65535, 65535
    )
    var reference_dmrs = nr_pucch_format2_reference_dmrs(reference_config)
    assert_equal(len(reference_dmrs), 8)
    for value in reference_dmrs:
        assert_true(abs(value.magnitude_squared() - 1.0) <= 2.0e-15)

    var channel_input: List[Complex64] = [
        Complex64(0.25, -0.5),
        Complex64(-1.0, 2.0),
        Complex64(3.5, 0.125),
    ]
    var channel_gain = Complex64(-0.4, 0.75)
    var faded = nr_pucch_format2_flat_channel(
        Span(channel_input), channel_gain, noise_variance=0.0
    )
    for i in range(len(channel_input)):
        _assert_complex_close(
            faded[i], channel_input[i] * channel_gain, 0.0
        )
    var empty_waveform = List[Complex64]()
    with assert_raises():
        _ = nr_pucch_format2_flat_channel(
            Span(empty_waveform), channel_gain
        )

    var waveform_config = NRPUCCHFormat2Config(
        128, 0, 0, 0, 1, 0, 1, 1, 1
    )
    var impulse_grid = NRResourceGrid(14, 128)
    impulse_grid[0, 0] = Complex64(1.0)
    var impulse_waveform = nr_pucch_format2_grid_to_waveform(
        waveform_config, impulse_grid
    )
    assert_equal(len(impulse_waveform), 138)
    for value in impulse_waveform:
        _assert_complex_close(value, Complex64(1.0 / 128.0), 2.0e-15)
    var invalid_grid = NRResourceGrid(14, 256)
    with assert_raises():
        _ = nr_pucch_format2_grid_to_waveform(waveform_config, invalid_grid)

    var analytic_waveform = List[Complex64](
        length=138, fill=Complex64(1.0 / 128.0)
    )
    var recovered_grid = nr_pucch_format2_waveform_to_grid(
        waveform_config, Span(analytic_waveform)
    )
    _assert_complex_close(recovered_grid[0, 0], Complex64(1.0), 2.0e-14)
    for k in range(1, 128):
        _assert_complex_close(recovered_grid[0, k], Complex64(0.0), 2.0e-14)
    with assert_raises():
        _ = nr_pucch_format2_waveform_to_grid(
            waveform_config, Span(analytic_waveform)[:137]
        )

    var chain_llrs = List[Float64](capacity=97)
    for i in range(97):
        chain_llrs.append(Float64(i) - 31.25)
    var chain_gold = _reference_gold(UInt32((0x1234 << 10) + 73), 97)
    var chain_descrambled = nr_pucch_format2_descramble_llrs(
        Span(chain_llrs), 0x1234, 73
    )
    for i in range(97):
        assert_equal(
            chain_descrambled[i],
            chain_llrs[i] if chain_gold[i] == 0 else -chain_llrs[i],
        )
    with assert_raises():
        _ = nr_pucch_format2_descramble_llrs(Span(chain_llrs), -1, 73)


def test_uplink_table_config_and_artifact_boundary_evidence() raises:
    # All four standardized root lengths plus an immediately adjacent invalid
    # length exercise the complete shape of this small configuration API.
    for length in [139, 571, 839, 1151]:
        assert_equal(nr_prach_logical_root_count(length), length - 1)
    with assert_raises():
        _ = nr_prach_logical_root_count(140)

    var prach_parameters = nr_prach_format_parameters(
        PRACH_FORMAT_A1, numerology=0, sequence_length=139
    )
    assert_true(nr_prach_normalized_cp_samples(prach_parameters) > 0)

    var cyclic_shift = nr_pucch_cyclic_shift_index(
        0, 13, 11, 11, 1023
    )
    assert_true(cyclic_shift >= 0 and cyclic_shift < 12)
    with assert_raises():
        _ = nr_pucch_cyclic_shift_index(0, 14, 0, 0, 0)

    var empty_bits = List[UInt8]()
    assert_equal(
        nr_pucch_format2_bits_checksum(Span(empty_bits)),
        UInt64(14695981039346656037),
    )
    var invalid_bits: List[UInt8] = [0, 2]
    with assert_raises():
        _ = nr_pucch_format2_bits_checksum(Span(invalid_bits))

    assert_equal(nr_pucch_format2_data_re_count(1, 1), 8)
    assert_equal(nr_pucch_format2_dmrs_re_count(1, 1), 4)
    with assert_raises():
        _ = nr_pucch_format2_data_re_count(0, 1)
    with assert_raises():
        _ = nr_pucch_format2_dmrs_re_count(1, 0)

    var pucch_min = NRPUCCHFormat2Config(128, 0, 0, 0, 1, 0, 0, 0, 0)
    assert_equal(nr_pucch_format2_coded_bit_capacity(pucch_min), 16)
    assert_equal(nr_pucch_format2_waveform_sample_count(pucch_min), 138)

    var pusch_min = NRPUSCHConfig(16, 0, 2, 0, 0, 1, 0, 0, 0, 0)
    assert_equal(nr_pusch_allocation_subcarriers(pusch_min), 12)
    assert_equal(nr_pusch_data_re_count(pusch_min), 12)
    assert_true(
        UInt64(nr_pusch_dmrs_c_init(Int.MAX, 13, 65535, 1))
        < (UInt64(1) << UInt64(31))
    )
    with assert_raises():
        _ = nr_pusch_dmrs_c_init(0, 14, 0, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
