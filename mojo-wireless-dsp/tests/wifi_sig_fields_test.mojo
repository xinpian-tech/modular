"""Exact independent evidence for bounded HT/VHT SIGNAL-field APIs.

The static bit rows are transcribed in over-the-air bit order from the field
layouts in IEEE Std 802.11-2024 Tables 19-11, 21-12, and 21-14.  The test-side
CRC uses eight explicit registers instead of the production packed-register
implementation, and the seeded pack/parse properties are driven by separate
field assemblers.  Every checked result is discrete, so the tolerance is
exactly zero.

This is deliberately not complete PPDU evidence: MU VHT, VHT NDP SIG-B,
80+80 MHz placement, modulation/FEC/interleaving, RL-SIG, HE-SIG, U-SIG, and
EHT-SIG are outside the bounded module under test.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.wifi.sig_fields import (
    WIFI_SIG_CODING_BCC,
    WIFI_SIG_CODING_LDPC,
    WIFI_SIG_CRC_INPUT_BITS,
    WIFI_SIG_CRC_BITS,
    WIFI_SIG_TAIL_BITS,
    WIFI_HT_SIG_BITS,
    WIFI_VHT_SIG_A_BITS,
    WIFI_VHT_MAX_APEP_OCTETS,
    wifi_sig_crc8,
    wifi_ht_sig_pack,
    wifi_ht_sig_parse,
    wifi_ht_sig_geometry,
    wifi_vht_sig_a_su_pack,
    wifi_vht_sig_a_su_parse,
    wifi_vht_sig_a_su_geometry,
    wifi_vht_sig_b_su_geometry,
    wifi_vht_sig_b_su_pack,
    wifi_vht_sig_b_su_parse,
    wifi_vht_sig_b_su_bcc_input,
)


def _append_lsb(mut output: List[UInt8], value: Int, width: Int):
    for index in range(width):
        output.append(UInt8((value >> index) & 1))


def _write_lsb(mut bits: List[UInt8], offset: Int, value: Int, width: Int):
    for index in range(width):
        bits[offset + index] = UInt8((value >> index) & 1)


def _oracle_crc8(bits: Span[UInt8, ...]) -> Int:
    # Clause-19 recurrence written as eight independent C0..C7 registers.
    # This is intentionally structurally different from the packed integer
    # state used by the production routine.
    var c0 = 1
    var c1 = 1
    var c2 = 1
    var c3 = 1
    var c4 = 1
    var c5 = 1
    var c6 = 1
    var c7 = 1
    for index in range(WIFI_SIG_CRC_INPUT_BITS):
        var feedback = c7 ^ Int(bits[index])
        var old_c0 = c0
        var old_c1 = c1
        var old_c2 = c2
        var old_c3 = c3
        var old_c4 = c4
        var old_c5 = c5
        var old_c6 = c6
        c0 = feedback
        c1 = old_c0 ^ feedback
        c2 = old_c1 ^ feedback
        c3 = old_c2
        c4 = old_c3
        c5 = old_c4
        c6 = old_c5
        c7 = old_c6
    return (
        ((c7 ^ 1) << 7)
        | ((c6 ^ 1) << 6)
        | ((c5 ^ 1) << 5)
        | ((c4 ^ 1) << 4)
        | ((c3 ^ 1) << 3)
        | ((c2 ^ 1) << 2)
        | ((c1 ^ 1) << 1)
        | (c0 ^ 1)
    )


def _append_oracle_crc(mut bits: List[UInt8]):
    var crc = _oracle_crc8(Span(bits))
    for index in range(WIFI_SIG_CRC_BITS):
        bits.append(UInt8((crc >> (7 - index)) & 1))


def _overwrite_crc(mut bits: List[UInt8]):
    var crc = _oracle_crc8(Span(bits))
    for index in range(WIFI_SIG_CRC_BITS):
        bits[34 + index] = UInt8((crc >> (7 - index)) & 1)


def _prefix34(bits: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=WIFI_SIG_CRC_INPUT_BITS)
    for index in range(WIFI_SIG_CRC_INPUT_BITS):
        result.append(bits[index])
    return result^


def _oracle_ht_bits(
    mcs_index: Int,
    bandwidth_mhz: Int,
    ht_length_octets: Int,
    smoothing: Bool,
    not_sounding: Bool,
    aggregation: Bool,
    stbc_streams: Int,
    fec_coding: Int,
    short_gi: Bool,
    extension_spatial_streams: Int,
) -> List[UInt8]:
    var bits = List[UInt8](capacity=WIFI_HT_SIG_BITS)
    _append_lsb(bits, mcs_index, 7)
    bits.append(UInt8(1 if bandwidth_mhz == 40 else 0))
    _append_lsb(bits, ht_length_octets, 16)
    bits.append(UInt8(1 if smoothing else 0))
    bits.append(UInt8(1 if not_sounding else 0))
    bits.append(UInt8(1))
    bits.append(UInt8(1 if aggregation else 0))
    _append_lsb(bits, stbc_streams, 2)
    bits.append(UInt8(fec_coding))
    bits.append(UInt8(1 if short_gi else 0))
    _append_lsb(bits, extension_spatial_streams, 2)
    _append_oracle_crc(bits)
    for _ in range(WIFI_SIG_TAIL_BITS):
        bits.append(UInt8(0))
    return bits^


def _oracle_vht_a_bits(
    bandwidth_mhz: Int,
    space_time_streams: Int,
    partial_aid: Int,
    mcs_index: Int,
    group_id: Int,
    stbc: Bool,
    txop_ps_not_allowed: Bool,
    short_gi: Bool,
    short_gi_nsym_disambiguation: Bool,
    coding: Int,
    ldpc_extra_ofdm_symbol: Bool,
    beamformed: Bool,
) -> List[UInt8]:
    var bandwidth_code = 0
    if bandwidth_mhz == 40:
        bandwidth_code = 1
    elif bandwidth_mhz == 80:
        bandwidth_code = 2
    elif bandwidth_mhz == 160:
        bandwidth_code = 3
    var bits = List[UInt8](capacity=WIFI_VHT_SIG_A_BITS)
    _append_lsb(bits, bandwidth_code, 2)
    bits.append(UInt8(1))
    bits.append(UInt8(1 if stbc else 0))
    _append_lsb(bits, group_id, 6)
    _append_lsb(bits, space_time_streams - 1, 3)
    _append_lsb(bits, partial_aid, 9)
    bits.append(UInt8(1 if txop_ps_not_allowed else 0))
    bits.append(UInt8(1))
    bits.append(UInt8(1 if short_gi else 0))
    bits.append(UInt8(1 if short_gi_nsym_disambiguation else 0))
    bits.append(UInt8(coding))
    bits.append(UInt8(1 if ldpc_extra_ofdm_symbol else 0))
    _append_lsb(bits, mcs_index, 4)
    bits.append(UInt8(1 if beamformed else 0))
    bits.append(UInt8(1))
    _append_oracle_crc(bits)
    for _ in range(WIFI_SIG_TAIL_BITS):
        bits.append(UInt8(0))
    return bits^


def _sig_b_widths(bandwidth_mhz: Int) -> Tuple[Int, Int, Int, Int]:
    if bandwidth_mhz == 20:
        return (17, 3, 1, 0)
    if bandwidth_mhz == 40:
        return (19, 2, 2, 0)
    return (21, 2, 4, 1)


def _oracle_vht_b_bits(
    apep_length_octets: Int, bandwidth_mhz: Int
) -> List[UInt8]:
    var length_bits, fixed_bits, _, _ = _sig_b_widths(bandwidth_mhz)
    var length_units = (apep_length_octets + 3) // 4
    var bits = List[UInt8](capacity=length_bits + fixed_bits + 6)
    _append_lsb(bits, length_units, length_bits)
    for _ in range(fixed_bits):
        bits.append(UInt8(1))
    for _ in range(WIFI_SIG_TAIL_BITS):
        bits.append(UInt8(0))
    return bits^


def _oracle_vht_b_input(
    base_bits: Span[UInt8, ...], bandwidth_mhz: Int
) -> List[UInt8]:
    var _, _, repetitions, zero_pad = _sig_b_widths(bandwidth_mhz)
    var result = List[UInt8](capacity=len(base_bits) * repetitions + zero_pad)
    for _ in range(repetitions):
        for index in range(len(base_bits)):
            result.append(base_bits[index])
    for _ in range(zero_pad):
        result.append(UInt8(0))
    return result^


def _ht_static_vector() -> List[UInt8]:
    # MCS=6, CBW20, LENGTH=1000, smoothing/not-sounding/fixed set, all
    # remaining controls zero.  Groups are HT-SIG over-the-air octets.
    return [
        0, 1, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 1, 0, 1, 1, 1,
        1, 1, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 1, 1, 0, 1,
        0, 0, 0, 0, 0, 0, 0, 0,
    ]


def _vht_a_static_vector() -> List[UInt8]:
    # BW80, SU group 63, NSTS=1, partial AID=0x155, TXOP flag, SGI,
    # BCC, MCS8, non-beamformed.  CRC transmission bits encode 0x39.
    return [
        0, 1, 1, 0, 1, 1, 1, 1,
        1, 1, 0, 0, 0, 1, 0, 1,
        0, 1, 0, 1, 0, 1, 1, 1,
        1, 0, 0, 0, 0, 0, 0, 1,
        0, 1, 0, 0, 1, 1, 1, 0,
        0, 1, 0, 0, 0, 0, 0, 0,
    ]


def _vht_b_20_static_vector() -> List[UInt8]:
    # APEP=1500 gives Length=ceil(1500/4)=375, 17 LSB-first Length bits,
    # three fixed-one bits, and six tail-zero bits.
    return [
        1, 1, 1, 0, 1, 1, 1, 0,
        1, 0, 0, 0, 0, 0, 0, 0,
        0, 1, 1, 1, 0, 0, 0, 0,
        0, 0,
    ]


def _vht_b_40_static_vector() -> List[UInt8]:
    return [
        1, 1, 1, 0, 1, 1, 1, 0,
        1, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 1, 1, 0, 0, 0,
        0, 0, 0,
    ]


def _vht_b_80_static_vector() -> List[UInt8]:
    return [
        1, 1, 1, 0, 1, 1, 1, 0,
        1, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 0,
        0, 0, 0, 0, 0,
    ]


def test_signal_constants_and_crc_static_exact() raises:
    assert_equal(WIFI_SIG_CRC_INPUT_BITS, 34)
    assert_equal(WIFI_SIG_CRC_BITS, 8)
    assert_equal(WIFI_SIG_TAIL_BITS, 6)
    assert_equal(WIFI_HT_SIG_BITS, 48)
    assert_equal(WIFI_VHT_SIG_A_BITS, 48)
    assert_equal(WIFI_VHT_MAX_APEP_OCTETS, 1_048_575)
    assert_equal(WIFI_SIG_CODING_BCC, 0)
    assert_equal(WIFI_SIG_CODING_LDPC, 1)

    var vector = _ht_static_vector()
    var crc_input = _prefix34(Span(vector))
    assert_equal(_oracle_crc8(Span(crc_input)), 0x34)
    assert_equal(wifi_sig_crc8(Span(crc_input)), 0x34)
    var zero_input = List[UInt8](capacity=34)
    for _ in range(34):
        zero_input.append(UInt8(0))
    assert_equal(_oracle_crc8(Span(zero_input)), 0xB2)
    assert_equal(wifi_sig_crc8(Span(zero_input)), 0xB2)

    var short_input = List[UInt8](capacity=33)
    for _ in range(33):
        short_input.append(UInt8(0))
    with assert_raises():
        _ = wifi_sig_crc8(Span(short_input))
    zero_input[12] = UInt8(2)
    with assert_raises():
        _ = wifi_sig_crc8(Span(zero_input))


def test_ht_sig_transcribed_vector_pack_and_parse() raises:
    var expected = _ht_static_vector()
    var oracle = _oracle_ht_bits(
        6, 20, 1000, True, True, False, 0, WIFI_SIG_CODING_BCC,
        False, 0,
    )
    assert_equal(oracle, expected)
    var actual = wifi_ht_sig_pack(6, 20, 1000)
    assert_equal(actual, expected)
    var parsed = wifi_ht_sig_parse(Span(expected))
    assert_equal(parsed.mcs_index, 6)
    assert_equal(parsed.bandwidth_mhz, 20)
    assert_equal(parsed.ht_length_octets, 1000)
    assert_true(parsed.smoothing)
    assert_true(parsed.not_sounding)
    assert_true(not parsed.aggregation)
    assert_equal(parsed.stbc_streams, 0)
    assert_equal(parsed.fec_coding, WIFI_SIG_CODING_BCC)
    assert_true(not parsed.short_gi)
    assert_equal(parsed.extension_spatial_streams, 0)
    assert_equal(parsed.crc, 0x34)

    # Raw unequal-modulation indices remain serializable even though their
    # stream-tuple geometry is intentionally outside the bounded API.
    var unequal = wifi_ht_sig_pack(76, 40, 65535)
    var unequal_fields = wifi_ht_sig_parse(Span(unequal))
    assert_equal(unequal_fields.mcs_index, 76)
    assert_equal(unequal_fields.bandwidth_mhz, 40)
    assert_equal(unequal_fields.ht_length_octets, 65535)
    assert_equal(unequal_fields.stbc_streams, 0)


def test_ht_sig_geometry_tables_exact() raises:
    var mcs_rows: List[Int] = [0, 7, 8, 15, 16, 23, 24, 31, 32]
    var expected_streams: List[Int] = [1, 1, 2, 2, 3, 3, 4, 4, 1]
    var expected_ltf: List[Int] = [1, 1, 2, 2, 4, 4, 4, 4, 1]
    for row in range(len(mcs_rows)):
        var bandwidth = 40 if mcs_rows[row] == 32 else 20
        var geometry = wifi_ht_sig_geometry(mcs_rows[row], bandwidth)
        assert_equal(geometry.signal_bits, 48)
        assert_equal(geometry.crc_covered_bits, 34)
        assert_equal(geometry.tail_bits, 6)
        assert_equal(geometry.signal_ofdm_symbols, 2)
        assert_equal(geometry.signal_duration_ns, 8000)
        assert_equal(geometry.data_spatial_streams, expected_streams[row])
        assert_equal(geometry.space_time_streams, expected_streams[row])
        assert_equal(geometry.data_ltf_symbols, expected_ltf[row])
        assert_equal(geometry.extension_ltf_symbols, 0)
        assert_equal(geometry.total_ltf_symbols, expected_ltf[row])

    var augmented = wifi_ht_sig_geometry(
        8, 40, stbc_streams=1, extension_spatial_streams=1
    )
    assert_equal(augmented.data_spatial_streams, 2)
    assert_equal(augmented.space_time_streams, 3)
    assert_equal(augmented.data_ltf_symbols, 4)
    assert_equal(augmented.extension_ltf_symbols, 1)
    assert_equal(augmented.total_ltf_symbols, 5)


def test_ht_sig_invalid_reserved_and_extreme_edges() raises:
    with assert_raises():
        _ = wifi_ht_sig_pack(-1, 20, 1)
    with assert_raises():
        _ = wifi_ht_sig_pack(77, 20, 1)
    with assert_raises():
        _ = wifi_ht_sig_pack(32, 20, 1)
    with assert_raises():
        _ = wifi_ht_sig_pack(0, 80, 1)
    with assert_raises():
        _ = wifi_ht_sig_pack(0, 20, -1)
    with assert_raises():
        _ = wifi_ht_sig_pack(0, 20, 65536)
    with assert_raises():
        _ = wifi_ht_sig_pack(0, 20, Int.MAX)
    with assert_raises():
        _ = wifi_ht_sig_pack(0, 20, 1, stbc_streams=3)
    with assert_raises():
        _ = wifi_ht_sig_pack(0, 20, 1, fec_coding=2)
    with assert_raises():
        _ = wifi_ht_sig_pack(0, 20, 1, extension_spatial_streams=4)

    var expected = _ht_static_vector()
    var short_bits = List[UInt8](capacity=47)
    for index in range(47):
        short_bits.append(expected[index])
    with assert_raises():
        _ = wifi_ht_sig_parse(Span(short_bits))
    var bad_bit = expected.copy()
    bad_bit[0] = UInt8(2)
    with assert_raises():
        _ = wifi_ht_sig_parse(Span(bad_bit))
    var bad_fixed = expected.copy()
    bad_fixed[26] = UInt8(0)
    with assert_raises():
        _ = wifi_ht_sig_parse(Span(bad_fixed))
    var bad_crc = expected.copy()
    bad_crc[34] = UInt8(1)
    with assert_raises():
        _ = wifi_ht_sig_parse(Span(bad_crc))
    var bad_tail = expected.copy()
    bad_tail[47] = UInt8(1)
    with assert_raises():
        _ = wifi_ht_sig_parse(Span(bad_tail))

    var reserved_mcs = expected.copy()
    _write_lsb(reserved_mcs, 0, 77, 7)
    _overwrite_crc(reserved_mcs)
    with assert_raises():
        _ = wifi_ht_sig_parse(Span(reserved_mcs))
    var reserved_stbc = expected.copy()
    _write_lsb(reserved_stbc, 28, 3, 2)
    _overwrite_crc(reserved_stbc)
    with assert_raises():
        _ = wifi_ht_sig_parse(Span(reserved_stbc))

    with assert_raises():
        _ = wifi_ht_sig_geometry(33, 20)
    with assert_raises():
        _ = wifi_ht_sig_geometry(24, 20, stbc_streams=1)
    with assert_raises():
        _ = wifi_ht_sig_geometry(0, 20, stbc_streams=3)
    with assert_raises():
        _ = wifi_ht_sig_geometry(
            8, 20, stbc_streams=2, extension_spatial_streams=1
        )


def test_vht_sig_a_su_transcribed_vector_pack_and_parse() raises:
    var expected = _vht_a_static_vector()
    var oracle = _oracle_vht_a_bits(
        80, 1, 0x155, 8, 63, False, True, True, False,
        WIFI_SIG_CODING_BCC, False, False,
    )
    assert_equal(oracle, expected)
    var actual = wifi_vht_sig_a_su_pack(
        80, 1, 0x155, 8, short_gi=True
    )
    assert_equal(actual, expected)
    var crc_input = _prefix34(Span(expected))
    assert_equal(_oracle_crc8(Span(crc_input)), 0x39)
    assert_equal(wifi_sig_crc8(Span(crc_input)), 0x39)

    var parsed = wifi_vht_sig_a_su_parse(Span(expected))
    assert_equal(parsed.bandwidth_mhz, 80)
    assert_true(not parsed.stbc)
    assert_equal(parsed.group_id, 63)
    assert_equal(parsed.space_time_streams, 1)
    assert_equal(parsed.partial_aid, 0x155)
    assert_true(parsed.txop_ps_not_allowed)
    assert_true(parsed.short_gi)
    assert_true(not parsed.short_gi_nsym_disambiguation)
    assert_equal(parsed.coding, WIFI_SIG_CODING_BCC)
    assert_true(not parsed.ldpc_extra_ofdm_symbol)
    assert_equal(parsed.mcs_index, 8)
    assert_true(not parsed.beamformed)
    assert_equal(parsed.crc, 0x39)


def test_vht_sig_a_su_geometry_tables_exact() raises:
    var expected_ltf: List[Int] = [1, 2, 4, 4, 6, 6, 8, 8]
    for nsts in range(1, 9):
        var geometry = wifi_vht_sig_a_su_geometry(nsts)
        assert_equal(geometry.signal_bits, 48)
        assert_equal(geometry.crc_covered_bits, 34)
        assert_equal(geometry.tail_bits, 6)
        assert_equal(geometry.signal_ofdm_symbols, 2)
        assert_equal(geometry.signal_duration_ns, 8000)
        assert_equal(geometry.data_spatial_streams, nsts)
        assert_equal(geometry.space_time_streams, nsts)
        assert_equal(geometry.vht_ltf_symbols, expected_ltf[nsts - 1])
    for nsts in [2, 4, 6, 8]:
        var geometry = wifi_vht_sig_a_su_geometry(nsts, stbc=True)
        assert_equal(geometry.data_spatial_streams, nsts // 2)
        assert_equal(geometry.space_time_streams, nsts)
        assert_equal(geometry.vht_ltf_symbols, expected_ltf[nsts - 1])


def test_vht_sig_a_su_invalid_fixed_crc_and_profile_edges() raises:
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(10, 1, 0, 0)
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(20, 1, 0, 0, group_id=1)
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(20, 0, 0, 0)
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(20, 9, 0, 0)
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(20, 1, -1, 0)
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(20, 1, 512, 0)
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(20, 3, 0, 0, stbc=True)
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(
            20, 1, 0, 0, short_gi_nsym_disambiguation=True
        )
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(20, 1, 0, 0, coding=2)
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(
            20, 1, 0, 0, ldpc_extra_ofdm_symbol=True
        )
    with assert_raises():
        _ = wifi_vht_sig_a_su_pack(20, 1, 0, 10)

    var expected = _vht_a_static_vector()
    var short_bits = List[UInt8](capacity=47)
    for index in range(47):
        short_bits.append(expected[index])
    with assert_raises():
        _ = wifi_vht_sig_a_su_parse(Span(short_bits))
    for fixed_index in [2, 23, 33]:
        var bad_fixed = expected.copy()
        bad_fixed[fixed_index] = UInt8(0)
        with assert_raises():
            _ = wifi_vht_sig_a_su_parse(Span(bad_fixed))
    var bad_crc = expected.copy()
    bad_crc[35] = UInt8(Int(bad_crc[35]) ^ 1)
    with assert_raises():
        _ = wifi_vht_sig_a_su_parse(Span(bad_crc))
    var bad_tail = expected.copy()
    bad_tail[42] = UInt8(1)
    with assert_raises():
        _ = wifi_vht_sig_a_su_parse(Span(bad_tail))
    var bad_bit = expected.copy()
    bad_bit[10] = UInt8(2)
    with assert_raises():
        _ = wifi_vht_sig_a_su_parse(Span(bad_bit))

    var mu_group = expected.copy()
    _write_lsb(mu_group, 4, 1, 6)
    _overwrite_crc(mu_group)
    with assert_raises():
        _ = wifi_vht_sig_a_su_parse(Span(mu_group))
    var reserved_mcs = expected.copy()
    _write_lsb(reserved_mcs, 28, 15, 4)
    _overwrite_crc(reserved_mcs)
    with assert_raises():
        _ = wifi_vht_sig_a_su_parse(Span(reserved_mcs))
    var illegal_disambiguation = expected.copy()
    illegal_disambiguation[24] = UInt8(0)
    illegal_disambiguation[25] = UInt8(1)
    _overwrite_crc(illegal_disambiguation)
    with assert_raises():
        _ = wifi_vht_sig_a_su_parse(Span(illegal_disambiguation))

    with assert_raises():
        _ = wifi_vht_sig_a_su_geometry(0)
    with assert_raises():
        _ = wifi_vht_sig_a_su_geometry(9)
    with assert_raises():
        _ = wifi_vht_sig_a_su_geometry(3, stbc=True)


def test_vht_sig_b_su_static_vectors_and_geometry_exact() raises:
    var expected20 = _vht_b_20_static_vector()
    var expected40 = _vht_b_40_static_vector()
    var expected80 = _vht_b_80_static_vector()
    assert_equal(_oracle_vht_b_bits(1500, 20), expected20)
    assert_equal(_oracle_vht_b_bits(1500, 40), expected40)
    assert_equal(_oracle_vht_b_bits(1500, 80), expected80)
    assert_equal(wifi_vht_sig_b_su_pack(1500, 20), expected20)
    assert_equal(wifi_vht_sig_b_su_pack(1500, 40), expected40)
    assert_equal(wifi_vht_sig_b_su_pack(1500, 80), expected80)
    assert_equal(wifi_vht_sig_b_su_pack(1500, 160), expected80)
    assert_equal(wifi_vht_sig_b_su_pack(1497, 20), expected20)

    for bandwidth in [20, 40, 80, 160]:
        var base = _oracle_vht_b_bits(1500, bandwidth)
        var fields = wifi_vht_sig_b_su_parse(Span(base), bandwidth)
        assert_equal(fields.bandwidth_mhz, bandwidth)
        assert_equal(fields.length_units_4_octets, 375)
        assert_equal(fields.rounded_apep_length_octets, 1500)
        assert_equal(fields.base_field_bits, len(base))
        var actual_input = wifi_vht_sig_b_su_bcc_input(
            Span(base), bandwidth
        )
        var expected_input = _oracle_vht_b_input(Span(base), bandwidth)
        assert_equal(actual_input, expected_input)

    var bandwidths: List[Int] = [20, 40, 80, 160]
    var length_bits: List[Int] = [17, 19, 21, 21]
    var fixed_bits: List[Int] = [3, 2, 2, 2]
    var base_bits: List[Int] = [26, 27, 29, 29]
    var repetitions: List[Int] = [1, 2, 4, 4]
    var zero_pad: List[Int] = [0, 0, 1, 1]
    var bcc_input: List[Int] = [26, 54, 117, 117]
    var coded: List[Int] = [52, 108, 234, 234]
    var copies: List[Int] = [1, 1, 1, 2]
    for row in range(4):
        var geometry = wifi_vht_sig_b_su_geometry(bandwidths[row])
        assert_equal(geometry.bandwidth_mhz, bandwidths[row])
        assert_equal(geometry.length_bits, length_bits[row])
        assert_equal(geometry.fixed_bits, fixed_bits[row])
        assert_equal(geometry.tail_bits, 6)
        assert_equal(geometry.base_field_bits, base_bits[row])
        assert_equal(geometry.base_field_repetitions, repetitions[row])
        assert_equal(geometry.zero_pad_bits, zero_pad[row])
        assert_equal(geometry.bcc_input_bits, bcc_input[row])
        assert_equal(geometry.coded_bpsk_bits, coded[row])
        assert_equal(geometry.content_copies, copies[row])
        assert_equal(geometry.signal_ofdm_symbols, 1)
        assert_equal(geometry.signal_duration_ns, 4000)


def test_vht_sig_b_su_invalid_fixed_tail_length_and_extremes() raises:
    with assert_raises():
        _ = wifi_vht_sig_b_su_geometry(10)
    with assert_raises():
        _ = wifi_vht_sig_b_su_pack(0, 20)
    with assert_raises():
        _ = wifi_vht_sig_b_su_pack(-1, 20)
    with assert_raises():
        _ = wifi_vht_sig_b_su_pack(WIFI_VHT_MAX_APEP_OCTETS + 1, 80)
    with assert_raises():
        _ = wifi_vht_sig_b_su_pack(Int.MAX, 80)
    with assert_raises():
        _ = wifi_vht_sig_b_su_pack(524285, 20)

    var expected20 = _vht_b_20_static_vector()
    var expected40 = _vht_b_40_static_vector()
    with assert_raises():
        _ = wifi_vht_sig_b_su_parse(Span(expected40), 20)
    var bad_bit = expected20.copy()
    bad_bit[0] = UInt8(2)
    with assert_raises():
        _ = wifi_vht_sig_b_su_parse(Span(bad_bit), 20)
    var bad_fixed = expected20.copy()
    bad_fixed[17] = UInt8(0)
    with assert_raises():
        _ = wifi_vht_sig_b_su_parse(Span(bad_fixed), 20)
    with assert_raises():
        _ = wifi_vht_sig_b_su_bcc_input(Span(bad_fixed), 20)
    var bad_tail = expected20.copy()
    bad_tail[20] = UInt8(1)
    with assert_raises():
        _ = wifi_vht_sig_b_su_parse(Span(bad_tail), 20)
    var ndp_zero_length = _oracle_vht_b_bits(0, 20)
    with assert_raises():
        _ = wifi_vht_sig_b_su_parse(Span(ndp_zero_length), 20)

    # 262144 is ceil(maximum APEP/4); the next encoded unit is out of the
    # bounded VHT APEP profile even though it fits the 40 MHz raw field.
    var oversized_units = _oracle_vht_b_bits(1_048_577, 40)
    with assert_raises():
        _ = wifi_vht_sig_b_su_parse(Span(oversized_units), 40)


def test_seeded_ht_vht_pack_parse_against_independent_oracles_exact() raises:
    var seed = UInt64(0x80211AC19A21BEEF)
    for iteration in range(257):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var bandwidth_ht = 40 if ((seed >> 7) & UInt64(1)) != 0 else 20
        var mcs = Int((seed >> 13) % UInt64(33))
        if mcs == 32:
            bandwidth_ht = 40
        var ht_length = Int((seed >> 19) & UInt64(0xFFFF))
        var smoothing = ((seed >> 3) & UInt64(1)) != 0
        var not_sounding = ((seed >> 4) & UInt64(1)) != 0
        var aggregation = ((seed >> 5) & UInt64(1)) != 0
        var stbc_streams = Int((seed >> 35) % UInt64(3))
        var data_streams = 1 if mcs == 32 else mcs // 8 + 1
        if data_streams + stbc_streams > 4:
            stbc_streams = 0
        var fec_coding = Int((seed >> 39) & UInt64(1))
        var short_gi = ((seed >> 41) & UInt64(1)) != 0
        var extension_capacity = 4 - data_streams - stbc_streams
        var extension_streams = Int(
            (seed >> 43) % UInt64(extension_capacity + 1)
        )
        if extension_streams > 0:
            not_sounding = False
        var expected_ht = _oracle_ht_bits(
            mcs,
            bandwidth_ht,
            ht_length,
            smoothing,
            not_sounding,
            aggregation,
            stbc_streams,
            fec_coding,
            short_gi,
            extension_streams,
        )
        var actual_ht = wifi_ht_sig_pack(
            mcs,
            bandwidth_ht,
            ht_length,
            smoothing=smoothing,
            not_sounding=not_sounding,
            aggregation=aggregation,
            stbc_streams=stbc_streams,
            fec_coding=fec_coding,
            short_gi=short_gi,
            extension_spatial_streams=extension_streams,
        )
        assert_equal(actual_ht, expected_ht)
        var parsed_ht = wifi_ht_sig_parse(Span(expected_ht))
        assert_equal(parsed_ht.mcs_index, mcs)
        assert_equal(parsed_ht.bandwidth_mhz, bandwidth_ht)
        assert_equal(parsed_ht.ht_length_octets, ht_length)
        assert_equal(parsed_ht.smoothing, smoothing)
        assert_equal(parsed_ht.not_sounding, not_sounding)
        assert_equal(parsed_ht.aggregation, aggregation)
        assert_equal(parsed_ht.stbc_streams, stbc_streams)
        assert_equal(parsed_ht.fec_coding, fec_coding)
        assert_equal(parsed_ht.short_gi, short_gi)
        assert_equal(parsed_ht.extension_spatial_streams, extension_streams)
        var ht_crc_input = _prefix34(Span(expected_ht))
        assert_equal(
            wifi_sig_crc8(Span(ht_crc_input)),
            _oracle_crc8(Span(ht_crc_input)),
        )
        assert_equal(
            parsed_ht.crc, _oracle_crc8(Span(ht_crc_input))
        )

        var bandwidths: List[Int] = [20, 40, 80, 160]
        var bandwidth_vht = bandwidths[iteration % 4]
        var nsts = 1 + Int((seed >> 11) & UInt64(7))
        var stbc = nsts % 2 == 0 and ((seed >> 15) & UInt64(1)) != 0
        var group_id = 0 if ((seed >> 17) & UInt64(1)) != 0 else 63
        var partial_aid = Int((seed >> 21) & UInt64(0x1FF))
        var mcs_vht = Int((seed >> 31) % UInt64(10))
        if mcs_vht == 9 and bandwidth_vht == 20:
            bandwidth_vht = 40
        var txop = ((seed >> 42) & UInt64(1)) != 0
        var sgi = ((seed >> 48) & UInt64(1)) != 0
        var disambiguation = sgi and ((seed >> 49) & UInt64(1)) != 0
        var coding = Int((seed >> 50) & UInt64(1))
        var extra_symbol = (
            coding == WIFI_SIG_CODING_LDPC
            and ((seed >> 51) & UInt64(1)) != 0
        )
        var beamformed = ((seed >> 52) & UInt64(1)) != 0
        var expected_vht = _oracle_vht_a_bits(
            bandwidth_vht,
            nsts,
            partial_aid,
            mcs_vht,
            group_id,
            stbc,
            txop,
            sgi,
            disambiguation,
            coding,
            extra_symbol,
            beamformed,
        )
        var actual_vht = wifi_vht_sig_a_su_pack(
            bandwidth_vht,
            nsts,
            partial_aid,
            mcs_vht,
            group_id=group_id,
            stbc=stbc,
            txop_ps_not_allowed=txop,
            short_gi=sgi,
            short_gi_nsym_disambiguation=disambiguation,
            coding=coding,
            ldpc_extra_ofdm_symbol=extra_symbol,
            beamformed=beamformed,
        )
        assert_equal(actual_vht, expected_vht)
        var parsed_vht = wifi_vht_sig_a_su_parse(Span(expected_vht))
        assert_equal(parsed_vht.bandwidth_mhz, bandwidth_vht)
        assert_equal(parsed_vht.space_time_streams, nsts)
        assert_equal(parsed_vht.partial_aid, partial_aid)
        assert_equal(parsed_vht.mcs_index, mcs_vht)
        assert_equal(parsed_vht.group_id, group_id)
        assert_equal(parsed_vht.stbc, stbc)
        assert_equal(parsed_vht.txop_ps_not_allowed, txop)
        assert_equal(parsed_vht.short_gi, sgi)
        assert_equal(parsed_vht.short_gi_nsym_disambiguation, disambiguation)
        assert_equal(parsed_vht.coding, coding)
        assert_equal(parsed_vht.ldpc_extra_ofdm_symbol, extra_symbol)
        assert_equal(parsed_vht.beamformed, beamformed)
        var vht_crc_input = _prefix34(Span(expected_vht))
        assert_equal(
            parsed_vht.crc, _oracle_crc8(Span(vht_crc_input))
        )

        var maximum = (
            524284 if bandwidth_vht == 20
            else WIFI_VHT_MAX_APEP_OCTETS
        )
        var apep_length = 1 + Int((seed >> 9) % UInt64(maximum))
        var expected_b = _oracle_vht_b_bits(apep_length, bandwidth_vht)
        var actual_b = wifi_vht_sig_b_su_pack(
            apep_length, bandwidth_vht
        )
        assert_equal(actual_b, expected_b)
        var parsed_b = wifi_vht_sig_b_su_parse(
            Span(expected_b), bandwidth_vht
        )
        var expected_units = (apep_length + 3) // 4
        assert_equal(parsed_b.length_units_4_octets, expected_units)
        assert_equal(
            parsed_b.rounded_apep_length_octets, expected_units * 4
        )
        var expected_input = _oracle_vht_b_input(
            Span(expected_b), bandwidth_vht
        )
        var actual_input = wifi_vht_sig_b_su_bcc_input(
            Span(expected_b), bandwidth_vht
        )
        assert_equal(actual_input, expected_input)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
