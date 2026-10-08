"""Independent Rel-17 DL-PRS and positioning-time evidence.

The static vectors and packed-LFSR oracle are direct, independent
transcriptions of ETSI TS 138 211 V17.10.0 clauses 5.2.1 and 7.4.1.7.2--3.
Timing arithmetic follows ETSI TS 138 215 V17.5.0 clauses 5.1.29--30 and
5.2.2--3.  No production TX-to-RX round trip is used as an oracle.
"""

from std.math import sqrt
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.positioning import (
    NRDLPRSConfig,
    nr_dl_prs_c_init,
    nr_dl_prs_sequence,
    nr_dl_prs_frequency_offset,
    nr_dl_prs_resource,
    nr_ul_rtoa_reference_time_seconds,
    nr_ul_rtoa_seconds,
    nr_dl_rstd_seconds,
    nr_ue_rx_tx_time_difference_seconds,
    nr_gnb_rx_tx_time_difference_seconds,
)


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _independent_prs_c_init(
    sequence_id: Int,
    symbols_per_slot: Int,
    slot_number: Int,
    symbol: Int,
) -> UInt32:
    # Literal clause-7.4.1.7.2 formula, kept separate from production helpers.
    var low = UInt64(sequence_id % 1024)
    var value = (
        (UInt64(1) << 22) * UInt64(sequence_id // 1024)
        + (UInt64(1) << 10)
        * UInt64(symbols_per_slot * slot_number + symbol + 1)
        * (UInt64(2) * low + UInt64(1))
        + low
    ) % (UInt64(1) << 31)
    return UInt32(value)


def _packed_x1_step(state: UInt32) -> UInt32:
    var feedback = (state ^ (state >> UInt32(3))) & UInt32(1)
    return (state >> UInt32(1)) | (feedback << UInt32(30))


def _packed_x2_step(state: UInt32) -> UInt32:
    var feedback = (
        state
        ^ (state >> UInt32(1))
        ^ (state >> UInt32(2))
        ^ (state >> UInt32(3))
    ) & UInt32(1)
    return (state >> UInt32(1)) | (feedback << UInt32(30))


def _independent_gold_bits(c_init: UInt32, length: Int) -> List[UInt8]:
    # Packed 31-bit LFSRs are structurally independent of the production
    # array-recurrence implementation in sequences.mojo.
    var x1 = UInt32(1)
    var x2 = c_init
    for _ in range(1600):
        x1 = _packed_x1_step(x1)
        x2 = _packed_x2_step(x2)
    var output = List[UInt8](capacity=length)
    for _ in range(length):
        output.append(UInt8((x1 ^ x2) & UInt32(1)))
        x1 = _packed_x1_step(x1)
        x2 = _packed_x2_step(x2)
    return output^


def _independent_prs_sequence(
    c_init: UInt32, length: Int
) -> List[Complex64]:
    var bits = _independent_gold_bits(c_init, 2 * length)
    var scale = 1.0 / sqrt(2.0)
    var result = List[Complex64](capacity=length)
    for index in range(length):
        result.append(Complex64(
            scale * (1.0 - 2.0 * Float64(bits[2 * index])),
            scale * (1.0 - 2.0 * Float64(bits[2 * index + 1])),
        ))
    return result^


def test_prs_static_c_init_and_sequence_vectors() raises:
    # Hard-coded results of the published c_init equation at lower, upper,
    # extended-CP, and mixed-field legal boundaries.
    assert_equal(nr_dl_prs_c_init(0, 0, 0, 0), UInt32(1024))
    assert_equal(
        nr_dl_prs_c_init(4095, 3, 79, 13), UInt32(212763647)
    )
    assert_equal(
        nr_dl_prs_c_init(
            1024, 2, 39, 11, extended_cyclic_prefix=True
        ),
        UInt32(4685824),
    )
    assert_equal(nr_dl_prs_c_init(1234, 1, 7, 5), UInt32(49029330))

    var expected_bits: List[UInt8] = [
        0, 0, 1, 0, 0, 0, 1, 1,
        1, 1, 0, 1, 1, 0, 1, 1,
        1, 1, 0, 1, 0, 0, 1, 1,
        1, 0, 0, 0, 0, 1, 0, 1,
    ]
    assert_equal(_independent_gold_bits(UInt32(1024), 32), expected_bits)
    var actual = nr_dl_prs_sequence(0, 0, 0, 0, 16)
    var oracle = _independent_prs_sequence(UInt32(1024), 16)
    for index in range(16):
        _assert_close(actual[index].re, oracle[index].re, 0.0)
        _assert_close(actual[index].im, oracle[index].im, 0.0)
        _assert_close(actual[index].magnitude_squared(), 1.0, 3.0e-16)


def test_complete_prs_frequency_offset_table() raises:
    var comb2: List[Int] = [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
    var comb4: List[Int] = [0, 2, 1, 3, 0, 2, 1, 3, 0, 2, 1, 3]
    var comb6: List[Int] = [0, 3, 1, 4, 2, 5, 0, 3, 1, 4, 2, 5]
    var comb12: List[Int] = [0, 6, 3, 9, 1, 7, 4, 10, 2, 8, 5, 11]
    for relative_symbol in range(12):
        assert_equal(
            nr_dl_prs_frequency_offset(2, relative_symbol),
            comb2[relative_symbol],
        )
        assert_equal(
            nr_dl_prs_frequency_offset(4, relative_symbol),
            comb4[relative_symbol],
        )
        assert_equal(
            nr_dl_prs_frequency_offset(6, relative_symbol),
            comb6[relative_symbol],
        )
        assert_equal(
            nr_dl_prs_frequency_offset(12, relative_symbol),
            comb12[relative_symbol],
        )


def test_all_legal_symbol_comb_pairs_and_independent_mapping() raises:
    var symbol_counts: List[Int] = [2, 4, 6, 12, 4, 12, 6, 12, 12]
    var comb_sizes: List[Int] = [2, 2, 2, 2, 4, 4, 6, 6, 12]
    for pair in range(len(symbol_counts)):
        var config = NRDLPRSConfig(
            77,
            0,
            3,
            0,
            24,
            comb_sizes[pair],
            comb_sizes[pair] - 1,
            0,
            symbol_counts[pair],
        )
        var resource = nr_dl_prs_resource(config)
        var per_symbol = 24 * 12 // comb_sizes[pair]
        assert_equal(
            len(resource.values), symbol_counts[pair] * per_symbol
        )
        for relative_symbol in range(symbol_counts[pair]):
            var residue = (
                comb_sizes[pair] - 1
                + nr_dl_prs_frequency_offset(
                    comb_sizes[pair], relative_symbol
                )
            ) % comb_sizes[pair]
            for local in range(per_symbol):
                var index = relative_symbol * per_symbol + local
                assert_equal(resource.symbols[index], relative_symbol)
                assert_equal(resource.sequence_indices[index], local)
                assert_equal(
                    resource.subcarriers[index],
                    local * comb_sizes[pair] + residue,
                )

    # Differential check of every coordinate and complex value for a resource
    # whose sequence begins away from m=0.
    var config = NRDLPRSConfig(1234, 1, 7, 13, 28, 4, 3, 2, 4)
    var beta = 1.25
    var resource = nr_dl_prs_resource(config, beta)
    var per_symbol = 28 * 12 // 4
    var first_m = 13 * 12 // 4
    var sequence_length = (13 + 28) * 12 // 4
    assert_equal(len(resource.values), 4 * per_symbol)
    for relative_symbol in range(4):
        var symbol = 2 + relative_symbol
        var c_init = _independent_prs_c_init(1234, 14, 7, symbol)
        var oracle = _independent_prs_sequence(c_init, sequence_length)
        var residue = (
            3 + nr_dl_prs_frequency_offset(4, relative_symbol)
        ) % 4
        for local in range(per_symbol):
            var output_index = relative_symbol * per_symbol + local
            var sequence_index = first_m + local
            assert_equal(resource.symbols[output_index], symbol)
            assert_equal(
                resource.sequence_indices[output_index], sequence_index
            )
            assert_equal(
                resource.subcarriers[output_index],
                sequence_index * 4 + residue,
            )
            _assert_close(
                resource.values[output_index].re,
                beta * oracle[sequence_index].re,
                0.0,
            )
            _assert_close(
                resource.values[output_index].im,
                beta * oracle[sequence_index].im,
                0.0,
            )


def test_seeded_prs_formula_and_packed_lfsr_property() raises:
    var state = UInt64(0x9E3779B97F4A7C15)
    for iteration in range(193):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var sequence_id = Int(state % UInt64(4096))
        var numerology = Int((state >> UInt64(13)) % UInt64(4))
        var extended = (
            numerology == 2
            and ((state >> UInt64(29)) & UInt64(1)) != 0
        )
        var symbols_per_slot = 12 if extended else 14
        var slot_number = Int(
            (state >> UInt64(31)) % UInt64(10 * (1 << numerology))
        )
        var symbol = Int(
            (state >> UInt64(47)) % UInt64(symbols_per_slot)
        )
        var expected_c_init = _independent_prs_c_init(
            sequence_id, symbols_per_slot, slot_number, symbol
        )
        assert_equal(
            nr_dl_prs_c_init(
                sequence_id,
                numerology,
                slot_number,
                symbol,
                extended_cyclic_prefix=extended,
            ),
            expected_c_init,
        )
        var length = iteration % 67 + 1
        var actual = nr_dl_prs_sequence(
            sequence_id,
            numerology,
            slot_number,
            symbol,
            length,
            extended_cyclic_prefix=extended,
        )
        var oracle = _independent_prs_sequence(expected_c_init, length)
        for index in range(length):
            _assert_close(actual[index].re, oracle[index].re, 0.0)
            _assert_close(actual[index].im, oracle[index].im, 0.0)


def test_seeded_prs_resource_geometry_property() raises:
    var symbol_counts: List[Int] = [2, 4, 6, 12, 4, 12, 6, 12, 12]
    var comb_sizes: List[Int] = [2, 2, 2, 2, 4, 4, 6, 6, 12]
    var state = UInt64(0xA0761D6478BD642F)
    for _ in range(61):
        state = (
            state * UInt64(3202034522624059733)
            + UInt64(4354685564936845319)
        )
        var pair = Int(state % UInt64(len(symbol_counts)))
        var numerology = Int((state >> UInt64(11)) % UInt64(4))
        var extended = (
            numerology == 2
            and ((state >> UInt64(19)) & UInt64(1)) != 0
        )
        var symbols_per_slot = 12 if extended else 14
        var first_symbol = Int(
            (state >> UInt64(23))
            % UInt64(symbols_per_slot - symbol_counts[pair] + 1)
        )
        var resource_blocks = 24 + 4 * Int(
            (state >> UInt64(31)) % UInt64(9)
        )
        var first_resource_block = Int(
            (state >> UInt64(37)) % UInt64(2177)
        )
        var comb = comb_sizes[pair]
        var re_offset = Int((state >> UInt64(53)) % UInt64(comb))
        var config = NRDLPRSConfig(
            Int(state % UInt64(4096)),
            numerology,
            Int(
                (state >> UInt64(43))
                % UInt64(10 * (1 << numerology))
            ),
            first_resource_block,
            resource_blocks,
            comb,
            re_offset,
            first_symbol,
            symbol_counts[pair],
            extended_cyclic_prefix=extended,
        )
        var resource = nr_dl_prs_resource(config)
        var per_symbol = resource_blocks * 12 // comb
        var first_m = first_resource_block * 12 // comb
        assert_equal(
            len(resource.values), symbol_counts[pair] * per_symbol
        )
        for relative_symbol in range(symbol_counts[pair]):
            var residue = (
                re_offset
                + nr_dl_prs_frequency_offset(comb, relative_symbol)
            ) % comb
            for local in range(per_symbol):
                var index = relative_symbol * per_symbol + local
                assert_equal(
                    resource.symbols[index], first_symbol + relative_symbol
                )
                assert_equal(
                    resource.sequence_indices[index], first_m + local
                )
                assert_equal(
                    resource.subcarriers[index],
                    (first_m + local) * comb + residue,
                )
                _assert_close(
                    resource.values[index].magnitude_squared(),
                    1.0,
                    3.0e-16,
                )


def test_normative_positioning_time_arithmetic() raises:
    _assert_close(
        nr_ul_rtoa_reference_time_seconds(1000.0, 512, 7),
        1005.127,
        2.0e-13,
    )
    _assert_close(
        nr_ul_rtoa_seconds(1005.127000375, 1000.0, 512, 7),
        3.75e-7,
        5.0e-14,
    )
    assert_equal(nr_dl_rstd_seconds(7.25, 7.0), 0.25)
    assert_equal(nr_dl_rstd_seconds(7.0, 7.25), -0.25)
    assert_equal(nr_ue_rx_tx_time_difference_seconds(4.0, 3.5), 0.5)
    assert_equal(nr_gnb_rx_tx_time_difference_seconds(-1.0, -1.75), 0.75)

    # Seeded difference antisymmetry and common-origin invariance.
    var state = UInt64(0xD1B54A32D192ED03)
    for iteration in range(257):
        state = state * UInt64(2862933555777941757) + UInt64(3037000493)
        var lhs = Float64(Int(state % UInt64(2000001)) - 1000000) * 1.0e-6
        var rhs = Float64(
            Int((state >> UInt64(21)) % UInt64(2000001)) - 1000000
        ) * 1.0e-6
        var shift = Float64(iteration % 19 - 9) * 4.0
        var difference = nr_dl_rstd_seconds(lhs, rhs)
        assert_equal(difference, -nr_dl_rstd_seconds(rhs, lhs))
        _assert_close(
            nr_dl_rstd_seconds(lhs + shift, rhs + shift),
            difference,
            2.0e-14,
        )
        assert_equal(
            nr_ue_rx_tx_time_difference_seconds(lhs, rhs), difference
        )
        assert_equal(
            nr_gnb_rx_tx_time_difference_seconds(lhs, rhs), difference
        )

        var system_frame = (iteration * 97 + 11) % 1024
        var subframe = (iteration * 7 + 3) % 10
        var nominal = Float64(iteration - 128) * 0.25
        var expected_reference = nominal + Float64(
            10 * system_frame + subframe
        ) * 1.0e-3
        var reference = nr_ul_rtoa_reference_time_seconds(
            nominal, system_frame, subframe
        )
        _assert_close(reference, expected_reference, 0.0)
        var arrival_delta = Float64(iteration % 31 - 15) * 1.0e-7
        _assert_close(
            nr_ul_rtoa_seconds(
                reference + arrival_delta,
                nominal,
                system_frame,
                subframe,
            ),
            arrival_delta,
            8.0e-15,
        )


def test_positioning_edge_contract_and_mutation_revalidation() raises:
    with assert_raises():
        _ = nr_dl_prs_c_init(-1, 0, 0, 0)
    with assert_raises():
        _ = nr_dl_prs_c_init(4096, 0, 0, 0)
    with assert_raises():
        _ = nr_dl_prs_c_init(0, -1, 0, 0)
    with assert_raises():
        _ = nr_dl_prs_c_init(0, 4, 0, 0)
    with assert_raises():
        _ = nr_dl_prs_c_init(0, 3, 80, 0)
    with assert_raises():
        _ = nr_dl_prs_c_init(0, 0, 0, 14)
    with assert_raises():
        _ = nr_dl_prs_c_init(
            0, 1, 0, 0, extended_cyclic_prefix=True
        )
    with assert_raises():
        _ = nr_dl_prs_sequence(0, 0, 0, 0, -1)
    with assert_raises():
        _ = nr_dl_prs_sequence(0, 0, 0, 0, Int.MAX)
    with assert_raises():
        _ = nr_dl_prs_frequency_offset(3, 0)
    with assert_raises():
        _ = nr_dl_prs_frequency_offset(2, 12)

    with assert_raises():
        _ = NRDLPRSConfig(0, 0, 0, -1, 24, 2, 0, 0, 2)
    with assert_raises():
        _ = NRDLPRSConfig(0, 0, 0, 2177, 24, 2, 0, 0, 2)
    with assert_raises():
        _ = NRDLPRSConfig(0, 0, 0, 0, 23, 2, 0, 0, 2)
    with assert_raises():
        _ = NRDLPRSConfig(0, 0, 0, 0, 276, 2, 0, 0, 2)
    with assert_raises():
        _ = NRDLPRSConfig(0, 0, 0, 0, 26, 2, 0, 0, 2)
    with assert_raises():
        _ = NRDLPRSConfig(0, 0, 0, 0, 24, 4, 4, 0, 4)
    with assert_raises():
        _ = NRDLPRSConfig(0, 0, 0, 0, 24, 4, 0, 0, 2)
    with assert_raises():
        _ = NRDLPRSConfig(0, 0, 0, 0, 24, 2, 0, 3, 12)

    var mutable_config = NRDLPRSConfig(0, 0, 0, 0, 24, 2, 0, 0, 2)
    mutable_config.resource_block_count = 25
    with assert_raises():
        _ = nr_dl_prs_resource(mutable_config)
    mutable_config.resource_block_count = 24
    mutable_config.sequence_id = 4096
    with assert_raises():
        _ = nr_dl_prs_resource(mutable_config)
    mutable_config.sequence_id = 0
    with assert_raises():
        _ = nr_dl_prs_resource(
            mutable_config, nan[DType.float64]()
        )
    with assert_raises():
        _ = nr_dl_prs_resource(
            mutable_config, inf[DType.float64]()
        )
    with assert_raises():
        _ = nr_dl_prs_resource(mutable_config, 0.0)
    var minimum_beta = Float64(from_bits=UInt64(1))
    var minimum_scaled = nr_dl_prs_resource(mutable_config, minimum_beta)
    assert_equal(abs(minimum_scaled.values[0].re), minimum_beta)
    assert_equal(abs(minimum_scaled.values[0].im), minimum_beta)
    var maximum_scaled = nr_dl_prs_resource(
        mutable_config, Float64.MAX_FINITE
    )
    assert_true(maximum_scaled.values[0].re != 0.0)
    assert_true(maximum_scaled.values[0].im != 0.0)

    with assert_raises():
        _ = nr_ul_rtoa_reference_time_seconds(
            nan[DType.float64](), 0, 0
        )
    with assert_raises():
        _ = nr_ul_rtoa_reference_time_seconds(0.0, -1, 0)
    with assert_raises():
        _ = nr_ul_rtoa_reference_time_seconds(0.0, 1024, 0)
    with assert_raises():
        _ = nr_ul_rtoa_reference_time_seconds(0.0, 0, 10)
    with assert_raises():
        _ = nr_ul_rtoa_seconds(
            inf[DType.float64](), 0.0, 0, 0
        )
    with assert_raises():
        _ = nr_dl_rstd_seconds(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_ue_rx_tx_time_difference_seconds(
            Float64.MAX_FINITE, -Float64.MAX_FINITE
        )
    with assert_raises():
        _ = nr_gnb_rx_tx_time_difference_seconds(
            0.0, inf[DType.float64]()
        )
    assert_equal(
        nr_dl_rstd_seconds(Float64.MAX_FINITE, Float64.MAX_FINITE),
        0.0,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
