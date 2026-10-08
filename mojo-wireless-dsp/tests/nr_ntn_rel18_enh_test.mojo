"""Independent evidence for bounded Rel-18 NR-NTN enhancements."""

from std.testing import (
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
    TestSuite,
)
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.ntn_rel18_enh import (
    NR_NTN_REL18_SSB_PER_CG_ONE_EIGHTH,
    NR_NTN_REL18_SSB_PER_CG_ONE_FOURTH,
    NR_NTN_REL18_SSB_PER_CG_HALF,
    NR_NTN_REL18_SSB_PER_CG_ONE,
    NR_NTN_REL18_SSB_PER_CG_TWO,
    NR_NTN_REL18_SSB_PER_CG_FOUR,
    NR_NTN_REL18_SSB_PER_CG_EIGHT,
    NR_NTN_REL18_SSB_PER_CG_SIXTEEN,
    NRNTNRel18RACHlessCGConfig,
    nr_ntn_rel18_cg_ssb_above_threshold,
    nr_ntn_rel18_cg_resources_per_mapping_cycle,
    nr_ntn_rel18_cg_mapping,
)


def _oracle_ratio(code: Int) raises -> Tuple[Int, Int]:
    # Independent literal transcription of the ASN.1 ENUMERATED values.
    if code == 0:
        return (1, 8)
    if code == 1:
        return (1, 4)
    if code == 2:
        return (1, 2)
    if code == 3:
        return (1, 1)
    if code == 4:
        return (2, 1)
    if code == 5:
        return (4, 1)
    if code == 6:
        return (8, 1)
    if code == 7:
        return (16, 1)
    raise Error("test oracle enum out of range")


def _oracle_selected_indices(bitmap: Int, width: Int) -> List[Int]:
    # Parse the ASN.1 BIT STRING independently, MSB/index-zero first.
    var result = List[Int]()
    for index in range(width):
        var raw_bit = width - 1 - index
        if ((bitmap >> raw_bit) & 1) == 1:
            result.append(index)
    return result^


def _oracle_mapping(
    ssb_bitmap: Int,
    width: Int,
    code: Int,
    dmrs_bitmap: Int,
    sequence_count: Int,
    ssb_index: Int,
    replica: Int,
) raises -> Tuple[Int, Int, Int, Int, Int, Int, Int, Int, Int]:
    # This parser/formula oracle shares no production helper or result type.
    var ssbs = _oracle_selected_indices(ssb_bitmap, width)
    var ports = _oracle_selected_indices(dmrs_bitmap, 8)
    var rank = -1
    for ordinal in range(len(ssbs)):
        if ssbs[ordinal] == ssb_index:
            rank = ordinal
    if rank < 0:
        raise Error("test oracle SSB is absent")
    var ratio = _oracle_ratio(code)
    var resource: Int
    var first_rank: Int
    var group_size = 1
    if ratio[1] > 1:
        resource = rank * ratio[1] + replica
        first_rank = rank
    else:
        resource = rank // ratio[0]
        first_rank = resource * ratio[0]
        group_size = min(ratio[0], len(ssbs) - first_rank)
    var dmrs_count = len(ports) * sequence_count
    var dmrs_id = resource % dmrs_count
    var port = ports[dmrs_id % len(ports)]
    var sequence = dmrs_id // len(ports)
    return (
        rank,
        ssbs[first_rank],
        first_rank,
        group_size,
        resource,
        resource // dmrs_count,
        dmrs_id,
        port,
        sequence,
    )


def _mix(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * UInt64(1099511628211)


def test_complete_rel18_enum_table_static_bitmap_and_dmrs_order() raises:
    var enum_codes: List[Int] = [
        NR_NTN_REL18_SSB_PER_CG_ONE_EIGHTH,
        NR_NTN_REL18_SSB_PER_CG_ONE_FOURTH,
        NR_NTN_REL18_SSB_PER_CG_HALF,
        NR_NTN_REL18_SSB_PER_CG_ONE,
        NR_NTN_REL18_SSB_PER_CG_TWO,
        NR_NTN_REL18_SSB_PER_CG_FOUR,
        NR_NTN_REL18_SSB_PER_CG_EIGHT,
        NR_NTN_REL18_SSB_PER_CG_SIXTEEN,
    ]
    var expected_resources: List[Int] = [32, 16, 8, 4, 2, 1, 1, 1]
    # Short ASN.1 1010 selects indexes [0,2], proving that the leftmost bit
    # is index zero rather than the host integer's least-significant bit.
    var short = NRNTNRel18RACHlessCGConfig(
        4, 0xA, NR_NTN_REL18_SSB_PER_CG_ONE, 0x80, 1
    )
    assert_equal(nr_ntn_rel18_cg_mapping(short, 0).ssb_ordinal, 0)
    assert_equal(nr_ntn_rel18_cg_mapping(short, 2).ssb_ordinal, 1)
    # ASN.1 10110100 selects SSB indexes [0,2,3,5].  ASN.1 10100000
    # selects DM-RS ports [0,2].  With two sequences, DMRSid order is
    # (port,sequence) = (0,0),(2,0),(0,1),(2,1).
    for code in range(8):
        var config = NRNTNRel18RACHlessCGConfig(
            8, 0xB4, enum_codes[code], 0xA0, 2
        )
        assert_equal(
            nr_ntn_rel18_cg_resources_per_mapping_cycle(config),
            expected_resources[code],
        )

    var one = NRNTNRel18RACHlessCGConfig(
        8, 0xB4, NR_NTN_REL18_SSB_PER_CG_ONE, 0xA0, 2
    )
    var one0 = nr_ntn_rel18_cg_mapping(one, 0)
    var one1 = nr_ntn_rel18_cg_mapping(one, 2)
    var one2 = nr_ntn_rel18_cg_mapping(one, 3)
    var one3 = nr_ntn_rel18_cg_mapping(one, 5)
    assert_equal(one0.resource_ordinal, 0)
    assert_equal(one0.dmrs_port_index, 0)
    assert_equal(one0.dmrs_sequence_index, 0)
    assert_equal(one1.resource_ordinal, 1)
    assert_equal(one1.dmrs_port_index, 2)
    assert_equal(one1.dmrs_sequence_index, 0)
    assert_equal(one2.resource_ordinal, 2)
    assert_equal(one2.dmrs_port_index, 0)
    assert_equal(one2.dmrs_sequence_index, 1)
    assert_equal(one3.resource_ordinal, 3)
    assert_equal(one3.dmrs_port_index, 2)
    assert_equal(one3.dmrs_sequence_index, 1)

    var two = NRNTNRel18RACHlessCGConfig(
        8, 0xB4, NR_NTN_REL18_SSB_PER_CG_TWO, 0xA0, 2
    )
    var two0 = nr_ntn_rel18_cg_mapping(two, 0)
    var two1 = nr_ntn_rel18_cg_mapping(two, 2)
    var two2 = nr_ntn_rel18_cg_mapping(two, 3)
    assert_equal(two0.resource_ordinal, 0)
    assert_equal(two1.resource_ordinal, 0)
    assert_equal(two0.ssb_group_first_index, 0)
    assert_equal(two0.ssb_group_size, 2)
    assert_equal(two2.resource_ordinal, 1)
    assert_equal(two2.ssb_group_first_index, 3)
    assert_equal(two2.ssb_group_size, 2)

    var half = NRNTNRel18RACHlessCGConfig(
        8, 0xB4, NR_NTN_REL18_SSB_PER_CG_HALF, 0xA0, 2
    )
    assert_equal(nr_ntn_rel18_cg_mapping(half, 0, 0).resource_ordinal, 0)
    assert_equal(nr_ntn_rel18_cg_mapping(half, 0, 1).resource_ordinal, 1)
    assert_equal(nr_ntn_rel18_cg_mapping(half, 2, 0).resource_ordinal, 2)
    assert_equal(nr_ntn_rel18_cg_mapping(half, 2, 1).resource_ordinal, 3)

    var eighth = NRNTNRel18RACHlessCGConfig(
        8, 0xB4, NR_NTN_REL18_SSB_PER_CG_ONE_EIGHTH, 0xA0, 2
    )
    var last = nr_ntn_rel18_cg_mapping(eighth, 5, 7)
    assert_equal(last.resource_ordinal, 31)
    assert_equal(last.pusch_configuration_period_index, 7)
    assert_equal(last.dmrs_resource_index, 3)
    assert_equal(last.dmrs_port_index, 2)
    assert_equal(last.dmrs_sequence_index, 1)

    # The maximum resource ordinal in the bounded medium-bitmap profile is
    # exactly 63.  Int128 cycle sizing plus validated widths rule out ordinal
    # multiplication overflow before the public mapping calculation.
    var bounded_max = NRNTNRel18RACHlessCGConfig(
        8, 0xFF, NR_NTN_REL18_SSB_PER_CG_ONE_EIGHTH, 0x80, 1
    )
    assert_equal(
        nr_ntn_rel18_cg_resources_per_mapping_cycle(bounded_max), 64
    )
    assert_equal(
        nr_ntn_rel18_cg_mapping(bounded_max, 7, 7).resource_ordinal, 63
    )

    # A retained exhaustive literal-profile checksum pins every public field.
    var checksum = UInt64(1469598103934665603)
    var ssbs: List[Int] = [0, 2, 3, 5]
    for code in range(8):
        var config = NRNTNRel18RACHlessCGConfig(
            8, 0xB4, code, 0xA0, 2
        )
        var ratio = _oracle_ratio(code)
        for ssb in ssbs:
            for replica in range(ratio[1]):
                var mapped = nr_ntn_rel18_cg_mapping(
                    config, ssb, replica
                )
                checksum = _mix(checksum, UInt64(code))
                checksum = _mix(checksum, UInt64(mapped.ssb_index))
                checksum = _mix(checksum, UInt64(mapped.ssb_ordinal))
                checksum = _mix(
                    checksum, UInt64(mapped.ssb_group_first_index)
                )
                checksum = _mix(
                    checksum, UInt64(mapped.ssb_group_first_ordinal)
                )
                checksum = _mix(checksum, UInt64(mapped.ssb_group_size))
                checksum = _mix(
                    checksum, UInt64(mapped.mapping_replica_index)
                )
                checksum = _mix(checksum, UInt64(mapped.resource_ordinal))
                checksum = _mix(
                    checksum,
                    UInt64(mapped.pusch_configuration_period_index),
                )
                checksum = _mix(
                    checksum, UInt64(mapped.dmrs_resource_index)
                )
                checksum = _mix(checksum, UInt64(mapped.dmrs_port_index))
                checksum = _mix(
                    checksum, UInt64(mapped.dmrs_sequence_index)
                )
    assert_equal(checksum, UInt64(3878024900838035943))


def test_rsrp_threshold_strict_boundary_and_exact_special_value() raises:
    # RSRP-Range 100 is exactly -56 dBm as a threshold.
    assert_false(nr_ntn_rel18_cg_ssb_above_threshold(-56.0, 100))
    assert_true(nr_ntn_rel18_cg_ssb_above_threshold(-55.999999999, 100))
    assert_false(nr_ntn_rel18_cg_ssb_above_threshold(-56.000000001, 100))
    assert_false(nr_ntn_rel18_cg_ssb_above_threshold(-156.0, 0))
    assert_true(nr_ntn_rel18_cg_ssb_above_threshold(-155.999, 0))
    assert_false(nr_ntn_rel18_cg_ssb_above_threshold(-30.0, 126))
    assert_true(nr_ntn_rel18_cg_ssb_above_threshold(-29.999, 126))
    # RSRP-Range 127 denotes an infinite threshold, not +127 dBm.
    assert_false(
        nr_ntn_rel18_cg_ssb_above_threshold(Float64.MAX_FINITE, 127)
    )
    assert_true(
        nr_ntn_rel18_cg_ssb_above_threshold(Float64.MAX_FINITE, 0)
    )
    assert_false(
        nr_ntn_rel18_cg_ssb_above_threshold(-Float64.MAX_FINITE, 0)
    )


def test_seeded_threshold_matches_independent_integer_tenth_dbm_oracle() raises:
    var seed = UInt64(0x13198A2E03707344)
    for _ in range(1025):
        seed = seed * UInt64(2862933555777941757) + UInt64(3037000493)
        var threshold = Int((seed >> 32) & UInt64(127))
        var measured_tenth_dbm = -1800 + Int(seed % UInt64(1801))
        var measured_dbm = Float64(measured_tenth_dbm) / 10.0
        var expected = (
            threshold != 127
            and measured_tenth_dbm > (threshold - 156) * 10
        )
        assert_equal(
            nr_ntn_rel18_cg_ssb_above_threshold(
                measured_dbm, threshold
            ),
            expected,
        )


def test_seeded_mapping_matches_independent_bitmap_parser_oracle() raises:
    var seed = UInt64(0x243F6A8885A308D3)
    for case_index in range(257):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var width = 4 if (case_index & 1) == 0 else 8
        var ssb_limit = 0xF if width == 4 else 0xFF
        var ssb_bitmap = Int(seed & UInt64(ssb_limit))
        if ssb_bitmap == 0:
            ssb_bitmap = 1
        var dmrs_bitmap = Int((seed >> 16) & UInt64(0xFF))
        if dmrs_bitmap == 0:
            dmrs_bitmap = 1
        var code = Int((seed >> 32) & UInt64(7))
        var sequence_count = 1 + Int((seed >> 40) & UInt64(1))
        var config = NRNTNRel18RACHlessCGConfig(
            width,
            ssb_bitmap,
            code,
            dmrs_bitmap,
            sequence_count,
        )
        var ssbs = _oracle_selected_indices(ssb_bitmap, width)
        var ratio = _oracle_ratio(code)
        var expected_resources = (
            len(ssbs) * ratio[1] + ratio[0] - 1
        ) // ratio[0]
        assert_equal(
            nr_ntn_rel18_cg_resources_per_mapping_cycle(config),
            expected_resources,
        )
        for ssb in ssbs:
            for replica in range(ratio[1]):
                var expected = _oracle_mapping(
                    ssb_bitmap,
                    width,
                    code,
                    dmrs_bitmap,
                    sequence_count,
                    ssb,
                    replica,
                )
                var actual = nr_ntn_rel18_cg_mapping(
                    config, ssb, replica
                )
                assert_equal(actual.ssb_ordinal, expected[0])
                assert_equal(actual.ssb_group_first_index, expected[1])
                assert_equal(actual.ssb_group_first_ordinal, expected[2])
                assert_equal(actual.ssb_group_size, expected[3])
                assert_equal(actual.resource_ordinal, expected[4])
                assert_equal(
                    actual.pusch_configuration_period_index, expected[5]
                )
                assert_equal(actual.dmrs_resource_index, expected[6])
                assert_equal(actual.dmrs_port_index, expected[7])
                assert_equal(actual.dmrs_sequence_index, expected[8])
                assert_true(
                    actual == nr_ntn_rel18_cg_mapping(
                        config, ssb, replica
                    )
                )


def test_public_edges_nonfinite_integer_extremes_and_mutation_revalidation() raises:
    for invalid_width in [Int.MIN, -1, 0, 3, 5, 64, Int.MAX]:
        with assert_raises():
            _ = NRNTNRel18RACHlessCGConfig(
                invalid_width, 1, 3, 0x80, 1
            )
    for invalid_bitmap in [Int.MIN, -1, 0, 0x100, Int.MAX]:
        with assert_raises():
            _ = NRNTNRel18RACHlessCGConfig(
                8, invalid_bitmap, 3, 0x80, 1
            )
    # Pin the short BIT STRING boundary independently.  Values that fit the
    # medium eight-bit profile must still be rejected by the four-bit profile.
    for invalid_short_bitmap in [0x10, 0x1F, 0x80, 0xFF]:
        with assert_raises():
            _ = NRNTNRel18RACHlessCGConfig(
                4, invalid_short_bitmap, 3, 0x80, 1
            )
    for invalid_code in [Int.MIN, -1, 8, Int.MAX]:
        with assert_raises():
            _ = NRNTNRel18RACHlessCGConfig(
                8, 0x80, invalid_code, 0x80, 1
            )
    for invalid_ports in [Int.MIN, -1, 0, 0x100, Int.MAX]:
        with assert_raises():
            _ = NRNTNRel18RACHlessCGConfig(
                8, 0x80, 3, invalid_ports, 1
            )
    for invalid_sequences in [Int.MIN, -1, 0, 3, Int.MAX]:
        with assert_raises():
            _ = NRNTNRel18RACHlessCGConfig(
                8, 0x80, 3, 0x80, invalid_sequences
            )

    var valid = NRNTNRel18RACHlessCGConfig(8, 0xB4, 3, 0xA0, 2)
    for invalid_ssb in [Int.MIN, -1, 1, 6, 8, Int.MAX]:
        with assert_raises():
            _ = nr_ntn_rel18_cg_mapping(valid, invalid_ssb)
    for invalid_replica in [Int.MIN, -1, 8, Int.MAX]:
        var fractional = NRNTNRel18RACHlessCGConfig(
            8, 0xB4, 0, 0xA0, 2
        )
        with assert_raises():
            _ = nr_ntn_rel18_cg_mapping(
                fractional, 0, invalid_replica
            )
    with assert_raises():
        _ = nr_ntn_rel18_cg_mapping(valid, 0, 1)

    with assert_raises():
        _ = nr_ntn_rel18_cg_ssb_above_threshold(
            nan[DType.float64](), 100
        )
    with assert_raises():
        _ = nr_ntn_rel18_cg_ssb_above_threshold(
            inf[DType.float64](), 100
        )
    with assert_raises():
        _ = nr_ntn_rel18_cg_ssb_above_threshold(
            -inf[DType.float64](), 100
        )
    for invalid_threshold in [Int.MIN, -1, 128, Int.MAX]:
        with assert_raises():
            _ = nr_ntn_rel18_cg_ssb_above_threshold(
                -100.0, invalid_threshold
            )

    var mutated = valid
    mutated.ssb_bitmap_width = 64
    with assert_raises():
        _ = nr_ntn_rel18_cg_resources_per_mapping_cycle(mutated)
    mutated = valid
    mutated.ssb_subset_bitmap = 0
    with assert_raises():
        _ = nr_ntn_rel18_cg_mapping(mutated, 0)
    mutated = valid
    mutated.ssb_per_cg_pusch = Int.MAX
    with assert_raises():
        _ = nr_ntn_rel18_cg_resources_per_mapping_cycle(mutated)
    mutated = valid
    mutated.dmrs_port_bitmap = 0
    with assert_raises():
        _ = nr_ntn_rel18_cg_mapping(mutated, 0)
    mutated = valid
    mutated.dmrs_sequence_count = Int.MIN
    with assert_raises():
        _ = nr_ntn_rel18_cg_mapping(mutated, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
