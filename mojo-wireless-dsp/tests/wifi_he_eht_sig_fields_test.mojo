"""Independent exact evidence for bounded HE/EHT SIGNAL fields.

The CRC oracle uses eight explicit C0..C7 registers, whereas production uses
a packed register.  Pack properties use independent field assemblers and an
IEEE 802.11 working-group literal CRC example.  All results are discrete and
the tolerance is exactly zero.

Evidence is limited to non-Doppler HE SU, 242-tone one-stream HE ER SU,
20 MHz nonpunctured EHT SU U-SIG, and caller-declared EHT-SIG Common/User CRC
blocks.  The EHT tests assume that acquisition context has excluded the
sounding-NDP interpretation of the shared raw type code.  MU, TB, Trigger,
NDP, puncturing, wider placement, complete EHT-SIG field interpretation,
coding/interleaving/modulation, and waveforms are not claimed.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.wifi.he_eht_sig_fields import (
    WIFI_HE_EHT_SIG_CRC_INPUT_BITS,
    WIFI_HE_EHT_SIG_CRC_BITS,
    WIFI_HE_EHT_SIG_TAIL_BITS,
    WIFI_HE_SIG_A_BITS,
    WIFI_EHT_U_SIG_BITS,
    WIFI_HE_EHT_SIG_CODING_BCC,
    WIFI_HE_EHT_SIG_CODING_LDPC,
    WIFI_EHT_SIG_BLOCK_COMMON,
    WIFI_EHT_SIG_BLOCK_USER,
    WifiHeSigASUConfig,
    WifiEhtUSigSU20Config,
    WifiEhtSigBlockProfile,
    wifi_he_eht_sig_crc4,
    wifi_he_sig_a_su_pack,
    wifi_he_sig_a_su_parse,
    wifi_he_sig_a_su_geometry,
    wifi_eht_u_sig_su_20_pack,
    wifi_eht_u_sig_su_20_parse,
    wifi_eht_u_sig_su_20_geometry,
    wifi_eht_sig_block_pack,
    wifi_eht_sig_block_parse,
    wifi_eht_sig_block_geometry,
)


def _append_lsb(mut output: List[UInt8], value: Int, width: Int):
    for index in range(width):
        output.append(UInt8((value >> index) & 1))


def _oracle_crc4(bits: Span[UInt8, ...]) -> Int:
    # Eight scalar registers make this structurally independent of the packed
    # production implementation.
    var c0 = 1
    var c1 = 1
    var c2 = 1
    var c3 = 1
    var c4 = 1
    var c5 = 1
    var c6 = 1
    var c7 = 1
    for index in range(len(bits)):
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
        ((c7 ^ 1) << 3)
        | ((c6 ^ 1) << 2)
        | ((c5 ^ 1) << 1)
        | (c4 ^ 1)
    )


def _append_crc4(mut bits: List[UInt8]):
    var crc = _oracle_crc4(Span(bits))
    for index in range(4):
        bits.append(UInt8((crc >> (3 - index)) & 1))


def _overwrite_crc4(mut bits: List[UInt8], content_bits: Int):
    var crc = _oracle_crc4(bits[0:content_bits])
    for index in range(4):
        bits[content_bits + index] = UInt8((crc >> (3 - index)) & 1)


def _bandwidth_code(bandwidth_mhz: Int) -> Int:
    if bandwidth_mhz == 20:
        return 0
    if bandwidth_mhz == 40:
        return 1
    if bandwidth_mhz == 80:
        return 2
    return 3


def _oracle_he_sig_a(config: WifiHeSigASUConfig) -> List[UInt8]:
    var bits = List[UInt8](capacity=52)
    bits.append(UInt8(1))
    bits.append(UInt8(1 if config.beam_change else 0))
    bits.append(UInt8(1 if config.uplink else 0))
    _append_lsb(bits, config.mcs_index, 4)
    bits.append(UInt8(1 if config.dcm else 0))
    _append_lsb(bits, config.bss_color, 6)
    bits.append(UInt8(1))
    _append_lsb(bits, config.spatial_reuse, 4)
    _append_lsb(bits, _bandwidth_code(config.bandwidth_mhz), 2)
    _append_lsb(bits, config.gi_ltf_code, 2)
    _append_lsb(bits, config.space_time_streams - 1, 3)
    _append_lsb(bits, config.txop_code, 7)
    bits.append(UInt8(config.coding))
    bits.append(
        UInt8(
            1
            if config.coding == WIFI_HE_EHT_SIG_CODING_BCC
            or config.ldpc_extra_symbol
            else 0
        )
    )
    bits.append(UInt8(1 if config.stbc else 0))
    bits.append(UInt8(1 if config.beamformed else 0))
    _append_lsb(bits, config.pre_fec_padding_factor, 2)
    bits.append(UInt8(1 if config.pe_disambiguity else 0))
    bits.append(UInt8(1))
    bits.append(UInt8(0))
    _append_crc4(bits)
    for _ in range(6):
        bits.append(UInt8(0))
    return bits^


def _oracle_eht_u_sig(config: WifiEhtUSigSU20Config) -> List[UInt8]:
    var bits = List[UInt8](capacity=52)
    _append_lsb(bits, 0, 6)
    bits.append(UInt8(1 if config.uplink else 0))
    _append_lsb(bits, config.bss_color, 6)
    _append_lsb(bits, config.txop_code, 7)
    for _ in range(6):
        bits.append(UInt8(1))
    _append_lsb(bits, 1, 2)
    bits.append(UInt8(1))
    _append_lsb(bits, 0, 5)
    bits.append(UInt8(1))
    _append_lsb(bits, config.eht_sig_mcs_code, 2)
    _append_lsb(bits, config.eht_sig_symbols - 1, 5)
    _append_crc4(bits)
    for _ in range(6):
        bits.append(UInt8(0))
    return bits^


def _he_static_vector() -> List[UInt8]:
    # MCS5, DL, BSS color 37, SR9, 80 MHz, GI/LTF code3, NSTS2,
    # TXOP code42, LDPC+extra, beamformed, padding factor2, PE disambiguity.
    return [
        1, 1, 0, 1, 0, 1, 0, 0,
        1, 0, 1, 0, 0, 1, 1, 1,
        0, 0, 1, 0, 1, 1, 1, 1,
        0, 0, 0, 1, 0, 1, 0, 1,
        0, 1, 1, 0, 1, 0, 1, 1,
        1, 0, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 0,
    ]


def _u_sig_static_vector() -> List[UInt8]:
    # EHT, 20 MHz, UL, BSS color45, TXOP code17, SU/no puncturing,
    # EHT-SIG MCS code2 and seven EHT-SIG symbols.
    return [
        0, 0, 0, 0, 0, 0, 1, 1,
        0, 1, 1, 0, 1, 1, 0, 0,
        0, 1, 0, 0, 1, 1, 1, 1,
        1, 1, 1, 0, 1, 0, 0, 0,
        0, 0, 1, 0, 1, 0, 1, 1,
        0, 0, 1, 0, 0, 1, 0, 0,
        0, 0, 0, 0,
    ]


def _ieee_crc_literal_input() -> List[UInt8]:
    # Literal m0..m41 example published in IEEE 802.11-20/1875r2.  Its
    # transmitted C7..C4 output is 0,1,1,1.
    return [
        1, 1, 0, 1, 1, 1, 0, 0,
        0, 0, 0, 0, 0, 0, 1, 0,
        0, 0, 0, 0, 0, 1, 1, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 1, 0, 0, 1, 1, 0,
        1, 0,
    ]


def test_constants_crc_and_ieee_literal_exact() raises:
    assert_equal(WIFI_HE_EHT_SIG_CRC_INPUT_BITS, 42)
    assert_equal(WIFI_HE_EHT_SIG_CRC_BITS, 4)
    assert_equal(WIFI_HE_EHT_SIG_TAIL_BITS, 6)
    assert_equal(WIFI_HE_SIG_A_BITS, 52)
    assert_equal(WIFI_EHT_U_SIG_BITS, 52)
    assert_equal(WIFI_HE_EHT_SIG_CODING_BCC, 0)
    assert_equal(WIFI_HE_EHT_SIG_CODING_LDPC, 1)
    assert_equal(WIFI_EHT_SIG_BLOCK_COMMON, 0)
    assert_equal(WIFI_EHT_SIG_BLOCK_USER, 1)

    var literal = _ieee_crc_literal_input()
    assert_equal(len(literal), 42)
    assert_equal(_oracle_crc4(Span(literal)), 0b0111)
    assert_equal(wifi_he_eht_sig_crc4(Span(literal)), 0b0111)

    var singleton: List[UInt8] = [UInt8(1)]
    assert_equal(
        wifi_he_eht_sig_crc4(Span(singleton)),
        _oracle_crc4(Span(singleton)),
    )
    var empty = List[UInt8]()
    with assert_raises():
        _ = wifi_he_eht_sig_crc4(Span(empty))
    singleton[0] = UInt8(2)
    with assert_raises():
        _ = wifi_he_eht_sig_crc4(Span(singleton))


def test_he_su_static_pack_parse_and_geometry_exact() raises:
    var config = WifiHeSigASUConfig(
        5,
        beam_change=True,
        bss_color=37,
        spatial_reuse=9,
        bandwidth_mhz=80,
        gi_ltf_code=3,
        space_time_streams=2,
        txop_code=42,
        coding=WIFI_HE_EHT_SIG_CODING_LDPC,
        ldpc_extra_symbol=True,
        beamformed=True,
        pre_fec_padding_factor=2,
        pe_disambiguity=True,
    )
    var expected = _he_static_vector()
    assert_equal(expected, _oracle_he_sig_a(config))
    var actual = wifi_he_sig_a_su_pack(config)
    assert_equal(actual, expected)
    var parsed = wifi_he_sig_a_su_parse(Span(expected))
    assert_equal(parsed.extended_range, False)
    assert_equal(parsed.beam_change, True)
    assert_equal(parsed.uplink, False)
    assert_equal(parsed.mcs_index, 5)
    assert_equal(parsed.dcm, False)
    assert_equal(parsed.bss_color, 37)
    assert_equal(parsed.spatial_reuse, 9)
    assert_equal(parsed.bandwidth_mhz, 80)
    assert_equal(parsed.gi_ltf_code, 3)
    assert_equal(parsed.space_time_streams, 2)
    assert_equal(parsed.txop_code, 42)
    assert_equal(parsed.coding, WIFI_HE_EHT_SIG_CODING_LDPC)
    assert_equal(parsed.ldpc_extra_symbol, True)
    assert_equal(parsed.stbc, False)
    assert_equal(parsed.beamformed, True)
    assert_equal(parsed.pre_fec_padding_factor, 2)
    assert_equal(parsed.pe_disambiguity, True)
    assert_equal(parsed.crc, 0b1111)

    var geometry = wifi_he_sig_a_su_geometry(config)
    assert_equal(geometry.field_bits, 52)
    assert_equal(geometry.crc_covered_bits, 42)
    assert_equal(geometry.crc_bits, 4)
    assert_equal(geometry.tail_bits, 6)
    assert_equal(geometry.information_parts, 2)
    assert_equal(geometry.part_bits, 26)
    assert_equal(geometry.repetitions_per_part, 1)
    assert_equal(geometry.ofdm_symbols, 2)
    assert_equal(geometry.duration_ns, 8_000)


def test_he_er_su_restricted_profile_exact() raises:
    var config = WifiHeSigASUConfig(
        2,
        extended_range=True,
        bss_color=63,
        spatial_reuse=15,
        gi_ltf_code=1,
        txop_code=0,
        coding=WIFI_HE_EHT_SIG_CODING_BCC,
    )
    var expected = _oracle_he_sig_a(config)
    var actual = wifi_he_sig_a_su_pack(config)
    assert_equal(actual, expected)
    assert_equal(actual[34], UInt8(1))
    var parsed = wifi_he_sig_a_su_parse(
        Span(expected), extended_range=True
    )
    assert_equal(parsed.extended_range, True)
    assert_equal(parsed.mcs_index, 2)
    assert_equal(parsed.bandwidth_mhz, 20)
    assert_equal(parsed.space_time_streams, 1)
    assert_equal(parsed.coding, WIFI_HE_EHT_SIG_CODING_BCC)
    assert_equal(parsed.ldpc_extra_symbol, False)
    var geometry = wifi_he_sig_a_su_geometry(config)
    assert_equal(geometry.repetitions_per_part, 2)
    assert_equal(geometry.ofdm_symbols, 4)
    assert_equal(geometry.duration_ns, 16_000)


def test_eht_u_sig_su20_static_pack_parse_and_geometry_exact() raises:
    var config = WifiEhtUSigSU20Config(
        45,
        uplink=True,
        txop_code=17,
        eht_sig_mcs_code=2,
        eht_sig_symbols=7,
    )
    var expected = _u_sig_static_vector()
    assert_equal(expected, _oracle_eht_u_sig(config))
    var actual = wifi_eht_u_sig_su_20_pack(config)
    assert_equal(actual, expected)
    var parsed = wifi_eht_u_sig_su_20_parse(Span(expected))
    assert_equal(parsed.uplink, True)
    assert_equal(parsed.bss_color, 45)
    assert_equal(parsed.txop_code, 17)
    assert_equal(parsed.eht_sig_mcs_code, 2)
    assert_equal(parsed.eht_sig_symbols, 7)
    assert_equal(parsed.crc, 0b1001)

    var geometry = wifi_eht_u_sig_su_20_geometry(config)
    assert_equal(geometry.field_bits, 52)
    assert_equal(geometry.crc_covered_bits, 42)
    assert_equal(geometry.crc_bits, 4)
    assert_equal(geometry.tail_bits, 6)
    assert_equal(geometry.information_parts, 2)
    assert_equal(geometry.part_bits, 26)
    assert_equal(geometry.bcc_coded_bits, 104)
    assert_equal(geometry.coded_bits_per_symbol, 52)
    assert_equal(geometry.ofdm_symbols, 2)
    assert_equal(geometry.duration_ns, 8_000)


def test_eht_sig_common_and_user_blocks_exact() raises:
    var content = _ieee_crc_literal_input()
    var common_profile = WifiEhtSigBlockProfile(
        WIFI_EHT_SIG_BLOCK_COMMON, len(content)
    )
    var common = wifi_eht_sig_block_pack(common_profile, Span(content))
    assert_equal(len(common), 52)
    assert_equal(common[42], UInt8(0))
    assert_equal(common[43], UInt8(1))
    assert_equal(common[44], UInt8(1))
    assert_equal(common[45], UInt8(1))
    for index in range(46, 52):
        assert_equal(common[index], UInt8(0))
    var parsed_common = wifi_eht_sig_block_parse(
        common_profile, Span(common)
    )
    assert_equal(parsed_common.kind, WIFI_EHT_SIG_BLOCK_COMMON)
    assert_equal(parsed_common.content, content)
    assert_equal(parsed_common.crc, 0b0111)

    var user_content: List[UInt8] = [
        UInt8(1), UInt8(0), UInt8(1), UInt8(1), UInt8(0),
        UInt8(0), UInt8(1), UInt8(0), UInt8(1), UInt8(0), UInt8(1),
    ]
    var user_profile = WifiEhtSigBlockProfile(
        WIFI_EHT_SIG_BLOCK_USER, len(user_content)
    )
    var user = wifi_eht_sig_block_pack(user_profile, Span(user_content))
    var parsed_user = wifi_eht_sig_block_parse(user_profile, Span(user))
    assert_equal(parsed_user.kind, WIFI_EHT_SIG_BLOCK_USER)
    assert_equal(parsed_user.content, user_content)
    assert_equal(parsed_user.crc, _oracle_crc4(Span(user_content)))

    var geometry = wifi_eht_sig_block_geometry(user_profile)
    assert_equal(geometry.kind, WIFI_EHT_SIG_BLOCK_USER)
    assert_equal(geometry.content_bits, 11)
    assert_equal(geometry.crc_bits, 4)
    assert_equal(geometry.tail_bits, 6)
    assert_equal(geometry.total_bits, 21)


def test_mutable_boundaries_fixed_bits_and_corruption() raises:
    var he = WifiHeSigASUConfig(0)
    var he_bits = wifi_he_sig_a_su_pack(he)
    he.mcs_index = 12
    with assert_raises():
        _ = wifi_he_sig_a_su_pack(he)
    with assert_raises():
        _ = wifi_he_sig_a_su_geometry(he)
    he.mcs_index = 0
    he.dcm = True
    he.space_time_streams = 3
    with assert_raises():
        _ = wifi_he_sig_a_su_pack(he)
    he.space_time_streams = 1
    he.stbc = True
    with assert_raises():
        _ = wifi_he_sig_a_su_pack(he)
    he.stbc = False
    he.mcs_index = 2
    with assert_raises():
        _ = wifi_he_sig_a_su_pack(he)
    he.mcs_index = 0
    he.dcm = False
    he.extended_range = True
    he.bandwidth_mhz = 40
    with assert_raises():
        _ = wifi_he_sig_a_su_pack(he)

    he_bits[14] = UInt8(0)
    _overwrite_crc4(he_bits, 42)
    with assert_raises():
        _ = wifi_he_sig_a_su_parse(Span(he_bits))
    he_bits = wifi_he_sig_a_su_pack(WifiHeSigASUConfig(0))
    he_bits[34] = UInt8(0)
    _overwrite_crc4(he_bits, 42)
    with assert_raises():
        _ = wifi_he_sig_a_su_parse(Span(he_bits))
    he_bits = wifi_he_sig_a_su_pack(WifiHeSigASUConfig(0))
    he_bits[42] ^= UInt8(1)
    with assert_raises():
        _ = wifi_he_sig_a_su_parse(Span(he_bits))
    he_bits = wifi_he_sig_a_su_pack(WifiHeSigASUConfig(0))
    he_bits[51] = UInt8(1)
    with assert_raises():
        _ = wifi_he_sig_a_su_parse(Span(he_bits))
    var short_he = List[UInt8](capacity=51)
    for _ in range(51):
        short_he.append(UInt8(0))
    with assert_raises():
        _ = wifi_he_sig_a_su_parse(Span(short_he))

    var u = WifiEhtUSigSU20Config(0)
    var u_bits = wifi_eht_u_sig_su_20_pack(u)
    u.eht_sig_symbols = 33
    with assert_raises():
        _ = wifi_eht_u_sig_su_20_pack(u)
    with assert_raises():
        _ = wifi_eht_u_sig_su_20_geometry(u)
    u_bits[29] = UInt8(1)
    _overwrite_crc4(u_bits, 42)
    with assert_raises():
        _ = wifi_eht_u_sig_su_20_parse(Span(u_bits))
    u_bits = wifi_eht_u_sig_su_20_pack(WifiEhtUSigSU20Config(0))
    u_bits[25] = UInt8(0)
    _overwrite_crc4(u_bits, 42)
    with assert_raises():
        _ = wifi_eht_u_sig_su_20_parse(Span(u_bits))
    u_bits = wifi_eht_u_sig_su_20_pack(WifiEhtUSigSU20Config(0))
    u_bits[42] ^= UInt8(1)
    with assert_raises():
        _ = wifi_eht_u_sig_su_20_parse(Span(u_bits))
    u_bits = wifi_eht_u_sig_su_20_pack(WifiEhtUSigSU20Config(0))
    u_bits[51] = UInt8(1)
    with assert_raises():
        _ = wifi_eht_u_sig_su_20_parse(Span(u_bits))

    var content: List[UInt8] = [UInt8(1), UInt8(0)]
    var profile = WifiEhtSigBlockProfile(WIFI_EHT_SIG_BLOCK_COMMON, 2)
    var block = wifi_eht_sig_block_pack(profile, Span(content))
    profile.kind = 2
    with assert_raises():
        _ = wifi_eht_sig_block_pack(profile, Span(content))
    with assert_raises():
        _ = wifi_eht_sig_block_parse(profile, Span(block))
    profile.kind = WIFI_EHT_SIG_BLOCK_COMMON
    profile.content_bits = 0
    with assert_raises():
        _ = wifi_eht_sig_block_geometry(profile)
    profile.content_bits = 2
    block[2] ^= UInt8(1)
    with assert_raises():
        _ = wifi_eht_sig_block_parse(profile, Span(block))
    block = wifi_eht_sig_block_pack(profile, Span(content))
    block[11] = UInt8(1)
    with assert_raises():
        _ = wifi_eht_sig_block_parse(profile, Span(block))
    content[1] = UInt8(2)
    with assert_raises():
        _ = wifi_eht_sig_block_pack(profile, Span(content))


def test_seeded_pack_parse_differential_properties() raises:
    var seed = UInt64(0x6A09E667F3BCC909)
    var bandwidths: List[Int] = [20, 40, 80, 160]
    for iteration in range(257):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var crc_input = List[UInt8]()
        for bit_index in range(WIFI_HE_EHT_SIG_CRC_INPUT_BITS):
            crc_input.append(
                UInt8((seed >> UInt64(bit_index % 64)) & UInt64(1))
            )
        assert_equal(
            wifi_he_eht_sig_crc4(Span(crc_input)),
            _oracle_crc4(Span(crc_input)),
        )
        var extended = iteration % 7 == 0
        var coding = Int((seed >> 10) & UInt64(1))
        var he_mcs = Int(seed % UInt64(3 if extended else 12))
        var he_streams = (
            1 if extended else 1 + Int((seed >> 19) & UInt64(7))
        )
        var he_dcm = (
            iteration % 11 == 0
            and (
                he_mcs == 0
                or he_mcs == 1
                or he_mcs == 3
                or he_mcs == 4
            )
            and he_streams <= 2
        )
        var he = WifiHeSigASUConfig(
            he_mcs,
            extended_range=extended,
            beam_change=((seed >> 3) & UInt64(1)) != 0,
            uplink=((seed >> 4) & UInt64(1)) != 0,
            dcm=he_dcm,
            bss_color=Int((seed >> 5) & UInt64(63)),
            spatial_reuse=Int((seed >> 11) & UInt64(15)),
            bandwidth_mhz=(
                20 if extended else bandwidths[Int((seed >> 15) & UInt64(3))]
            ),
            gi_ltf_code=Int((seed >> 17) & UInt64(3)),
            space_time_streams=he_streams,
            txop_code=Int((seed >> 22) & UInt64(127)),
            coding=coding,
            ldpc_extra_symbol=(
                coding == WIFI_HE_EHT_SIG_CODING_LDPC
                and ((seed >> 30) & UInt64(1)) != 0
            ),
            stbc=(not he_dcm and ((seed >> 31) & UInt64(1)) != 0),
            beamformed=((seed >> 32) & UInt64(1)) != 0,
            pre_fec_padding_factor=Int((seed >> 33) & UInt64(3)),
            pe_disambiguity=((seed >> 35) & UInt64(1)) != 0,
        )
        var expected_he = _oracle_he_sig_a(he)
        var actual_he = wifi_he_sig_a_su_pack(he)
        assert_equal(actual_he, expected_he)
        var parsed_he = wifi_he_sig_a_su_parse(
            Span(expected_he), extended_range=extended
        )
        assert_equal(parsed_he.extended_range, he.extended_range)
        assert_equal(parsed_he.beam_change, he.beam_change)
        assert_equal(parsed_he.uplink, he.uplink)
        assert_equal(parsed_he.mcs_index, he.mcs_index)
        assert_equal(parsed_he.dcm, he.dcm)
        assert_equal(parsed_he.bss_color, he.bss_color)
        assert_equal(parsed_he.spatial_reuse, he.spatial_reuse)
        assert_equal(parsed_he.bandwidth_mhz, he.bandwidth_mhz)
        assert_equal(parsed_he.gi_ltf_code, he.gi_ltf_code)
        assert_equal(parsed_he.space_time_streams, he.space_time_streams)
        assert_equal(parsed_he.txop_code, he.txop_code)
        assert_equal(parsed_he.coding, he.coding)
        assert_equal(parsed_he.ldpc_extra_symbol, he.ldpc_extra_symbol)
        assert_equal(parsed_he.stbc, he.stbc)
        assert_equal(parsed_he.beamformed, he.beamformed)
        assert_equal(
            parsed_he.pre_fec_padding_factor, he.pre_fec_padding_factor
        )
        assert_equal(parsed_he.pe_disambiguity, he.pe_disambiguity)
        assert_equal(parsed_he.crc, _oracle_crc4(expected_he[0:42]))
        var he_geometry = wifi_he_sig_a_su_geometry(he)
        assert_equal(he_geometry.field_bits, 52)
        assert_equal(he_geometry.crc_covered_bits, 42)
        assert_equal(he_geometry.crc_bits, 4)
        assert_equal(he_geometry.tail_bits, 6)
        assert_equal(he_geometry.information_parts, 2)
        assert_equal(he_geometry.part_bits, 26)
        assert_equal(he_geometry.repetitions_per_part, 2 if extended else 1)
        assert_equal(he_geometry.ofdm_symbols, 4 if extended else 2)
        assert_equal(he_geometry.duration_ns, 16_000 if extended else 8_000)

        var u = WifiEhtUSigSU20Config(
            Int((seed >> 37) & UInt64(63)),
            uplink=((seed >> 43) & UInt64(1)) != 0,
            txop_code=Int((seed >> 44) & UInt64(127)),
            eht_sig_mcs_code=Int((seed >> 51) & UInt64(3)),
            eht_sig_symbols=1 + Int((seed >> 53) & UInt64(31)),
        )
        var expected_u = _oracle_eht_u_sig(u)
        var actual_u = wifi_eht_u_sig_su_20_pack(u)
        assert_equal(actual_u, expected_u)
        var parsed_u = wifi_eht_u_sig_su_20_parse(Span(expected_u))
        assert_equal(parsed_u.uplink, u.uplink)
        assert_equal(parsed_u.bss_color, u.bss_color)
        assert_equal(parsed_u.txop_code, u.txop_code)
        assert_equal(parsed_u.eht_sig_mcs_code, u.eht_sig_mcs_code)
        assert_equal(parsed_u.eht_sig_symbols, u.eht_sig_symbols)
        var u_geometry = wifi_eht_u_sig_su_20_geometry(u)
        assert_equal(u_geometry.field_bits, 52)
        assert_equal(u_geometry.crc_covered_bits, 42)
        assert_equal(u_geometry.crc_bits, 4)
        assert_equal(u_geometry.tail_bits, 6)
        assert_equal(u_geometry.information_parts, 2)
        assert_equal(u_geometry.part_bits, 26)
        assert_equal(u_geometry.bcc_coded_bits, 104)
        assert_equal(u_geometry.coded_bits_per_symbol, 52)
        assert_equal(u_geometry.ofdm_symbols, 2)
        assert_equal(u_geometry.duration_ns, 8_000)

        var content_bits = 1 + Int((seed >> 7) & UInt64(63))
        var content = List[UInt8](capacity=content_bits)
        var local = seed
        for _ in range(content_bits):
            local = local * UInt64(2862933555777941757) + UInt64(3037000493)
            content.append(UInt8((local >> 63) & UInt64(1)))
        var profile = WifiEhtSigBlockProfile(
            (
                WIFI_EHT_SIG_BLOCK_COMMON
                if (iteration & 1) == 0
                else WIFI_EHT_SIG_BLOCK_USER
            ),
            content_bits,
        )
        var block = wifi_eht_sig_block_pack(profile, Span(content))
        assert_equal(len(block), content_bits + 10)
        var parsed_block = wifi_eht_sig_block_parse(profile, Span(block))
        assert_equal(parsed_block.content, content)
        assert_equal(parsed_block.crc, _oracle_crc4(Span(content)))
        var geometry = wifi_eht_sig_block_geometry(profile)
        assert_equal(geometry.total_bits, content_bits + 10)
        assert_true(geometry.kind == profile.kind)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
