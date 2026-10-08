"""Bounded IEEE 802.11-2024 Clause-15/16 DSSS PLCP and PPDU.

This CPU-only golden reference implements the mandatory long PLCP and the
optional HR/DSSS short PLCP for the four CCK-interoperable data rates.  It
provides the self-synchronizing ``z^-7 + z^-4 + 1`` feedthrough scrambler,
long/short SYNC and SFD fields, SIGNAL/SERVICE/LENGTH/CRC-16 construction,
the 11 Mb/s LENGTH-extension rule, exact header-to-PSDU rate switching, MPDU
FCS, and known-boundary hard receive parsing.  The transmit and receive
composites preserve their real bit/chip intermediates and checkpoint metadata.

The declared PPDU profile accepts an MPDU bitstream without FCS, limited so
the resulting PSDU is at most 4095 octets.  The long header supports 1, 2,
5.5, and 11 Mb/s; the short header supports 2, 5.5, and 11 Mb/s.  Barker and
CCK chip modulation is composed from :mod:`dsss_cck`.  RX assumes exact chip
timing and a common nonzero complex gain; it is a deterministic hard-reference
parser, not an acquisition, equalization, or soft-decoding implementation.

PBCC, channel agility, pulse shaping, spectral masks, CCA, synchronization,
multipath equalization, RF/OTA behavior, MAC-header construction, security,
and conformance procedures are outside this bounded profile.  PBCC requests
are rejected through the SERVICE modulation-selection bit rather than being
silently interpreted as CCK.

Normative baseline: IEEE Std 802.11-2024 Clauses 15 and 16.  Bit-level rules,
the official CRC example, and the 11 Mb/s LENGTH examples are independently
traceable to the IEEE 802.11 Working Group primary archive,
P802.11b/D3.1, 18.2.2--18.2.4 (document 90845b).  That draft is a historical
cross-check only and never an authority for production qualification.
"""

from std.collections import Span
from wireless_dsp.core import Complex64
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_metadata_1d,
)
from .dsss_cck import (
    WIFI_DSSS_BARKER_CHIPS,
    WIFI_CCK_CHIPS,
    wifi_dsss_dbpsk_spread,
    wifi_dsss_dbpsk_despread_hard,
    wifi_dsss_dqpsk_spread,
    wifi_dsss_dqpsk_despread_hard,
    wifi_cck_5_5_map,
    wifi_cck_5_5_demap_hard,
    wifi_cck_11_map,
    wifi_cck_11_demap_hard,
)
from .legacy import wifi_fcs


comptime WIFI_DSSS_RATE_1_MBPS_KBPS = 1000
comptime WIFI_DSSS_RATE_2_MBPS_KBPS = 2000
comptime WIFI_DSSS_RATE_5_5_MBPS_KBPS = 5500
comptime WIFI_DSSS_RATE_11_MBPS_KBPS = 11000

comptime WIFI_DSSS_LONG_SCRAMBLER_SEED = 0x6C
comptime WIFI_DSSS_SHORT_SCRAMBLER_SEED = 0x1B
comptime WIFI_DSSS_LONG_SYNC_BITS = 128
comptime WIFI_DSSS_SHORT_SYNC_BITS = 56
comptime WIFI_DSSS_SFD_BITS = 16
comptime WIFI_DSSS_PLCP_HEADER_BITS = 48
comptime WIFI_DSSS_PLCP_CRC_INPUT_BITS = 32
comptime WIFI_DSSS_PLCP_CRC_BITS = 16
comptime WIFI_DSSS_FCS_BITS = 32
comptime WIFI_DSSS_MAX_PSDU_OCTETS = 4095


struct WifiDSSSPLCPConfig(ImplicitlyCopyable):
    """Mutable bounded Clause-15/16 PLCP configuration.

    Every public boundary accepting this record calls :meth:`validate`, so a
    caller cannot mutate a previously valid rate/preamble pair into an
    unchecked configuration.  ``locked_clocks`` is SERVICE bit 2.  PBCC is
    intentionally not a configuration choice in this CCK-only profile.
    """

    var data_rate_kbps: Int
    var short_preamble: Bool
    var locked_clocks: Bool

    def __init__(
        out self,
        data_rate_kbps: Int,
        *,
        short_preamble: Bool = False,
        locked_clocks: Bool = False,
    ) raises:
        self.data_rate_kbps = data_rate_kbps
        self.short_preamble = short_preamble
        self.locked_clocks = locked_clocks
        self.validate()

    def validate(self) raises:
        if (
            self.data_rate_kbps != WIFI_DSSS_RATE_1_MBPS_KBPS
            and self.data_rate_kbps != WIFI_DSSS_RATE_2_MBPS_KBPS
            and self.data_rate_kbps != WIFI_DSSS_RATE_5_5_MBPS_KBPS
            and self.data_rate_kbps != WIFI_DSSS_RATE_11_MBPS_KBPS
        ):
            raise Error("DSSS rate must be 1, 2, 5.5, or 11 Mb/s")
        if (
            self.short_preamble
            and self.data_rate_kbps == WIFI_DSSS_RATE_1_MBPS_KBPS
        ):
            raise Error("short PLCP does not support a 1 Mb/s PSDU")


struct WifiDSSSPLCPLength(ImplicitlyCopyable):
    """Canonical PLCP LENGTH and SERVICE length-extension interpretation."""

    var psdu_octets: Int
    var length_us: Int
    var length_extension: Bool

    def __init__(
        out self,
        psdu_octets: Int,
        length_us: Int,
        length_extension: Bool,
    ):
        self.psdu_octets = psdu_octets
        self.length_us = length_us
        self.length_extension = length_extension


struct WifiDSSSPLCPHeader(ImplicitlyCopyable):
    """Parsed canonical SIGNAL, SERVICE, LENGTH, and CRC-16 fields."""

    var config: WifiDSSSPLCPConfig
    var signal: Int
    var service: Int
    var length: WifiDSSSPLCPLength
    var crc: Int

    def __init__(
        out self,
        config: WifiDSSSPLCPConfig,
        signal: Int,
        service: Int,
        length: WifiDSSSPLCPLength,
        crc: Int,
    ):
        self.config = config
        self.signal = signal
        self.service = service
        self.length = length
        self.crc = crc


struct WifiDSSSPPDUTx(Movable):
    """Complete bounded TX result with real PLCP/PSDU bit and chip stages."""

    var header: WifiDSSSPLCPHeader
    var fcs: UInt64
    var preamble_bits: List[UInt8]
    var header_bits: List[UInt8]
    var psdu_bits: List[UInt8]
    var ppdu_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var preamble_chips: List[Complex64]
    var header_chips: List[Complex64]
    var psdu_chips: List[Complex64]
    var ppdu_chips: List[Complex64]
    var metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        header: WifiDSSSPLCPHeader,
        fcs: UInt64,
        var preamble_bits: List[UInt8],
        var header_bits: List[UInt8],
        var psdu_bits: List[UInt8],
        var ppdu_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var preamble_chips: List[Complex64],
        var header_chips: List[Complex64],
        var psdu_chips: List[Complex64],
        var ppdu_chips: List[Complex64],
        var metadata: List[CheckpointMetadata],
    ):
        self.header = header
        self.fcs = fcs
        self.preamble_bits = preamble_bits^
        self.header_bits = header_bits^
        self.psdu_bits = psdu_bits^
        self.ppdu_bits = ppdu_bits^
        self.scrambled_bits = scrambled_bits^
        self.preamble_chips = preamble_chips^
        self.header_chips = header_chips^
        self.psdu_chips = psdu_chips^
        self.ppdu_chips = ppdu_chips^
        self.metadata = metadata^


struct WifiDSSSPPDURx(Movable):
    """Known-boundary RX result with parsed PLCP, payload, and actual FCS."""

    var header: WifiDSSSPLCPHeader
    var payload_bits: List[UInt8]
    var payload_octets: List[UInt8]
    var recovered_fcs: UInt64
    var computed_fcs: UInt64
    var fcs_ok: Bool
    var scrambled_bits: List[UInt8]
    var descrambled_bits: List[UInt8]
    var metadata: List[CheckpointMetadata]

    def __init__(
        out self,
        header: WifiDSSSPLCPHeader,
        var payload_bits: List[UInt8],
        var payload_octets: List[UInt8],
        recovered_fcs: UInt64,
        computed_fcs: UInt64,
        fcs_ok: Bool,
        var scrambled_bits: List[UInt8],
        var descrambled_bits: List[UInt8],
        var metadata: List[CheckpointMetadata],
    ):
        self.header = header
        self.payload_bits = payload_bits^
        self.payload_octets = payload_octets^
        self.recovered_fcs = recovered_fcs
        self.computed_fcs = computed_fcs
        self.fcs_ok = fcs_ok
        self.scrambled_bits = scrambled_bits^
        self.descrambled_bits = descrambled_bits^
        self.metadata = metadata^


def _validate_binary(bits: Span[UInt8, ...], label: String) raises:
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error(label + " must contain only zero and one")


def _validate_scrambler_seed(seed: Int) raises:
    if seed < 1 or seed > 0x7F:
        raise Error("DSSS scrambler seed must be a nonzero 7-bit value")


def _append_lsb(mut output: List[UInt8], value: Int, width: Int):
    for bit in range(width):
        output.append(UInt8((value >> bit) & 1))


def _read_lsb(bits: Span[UInt8, ...], offset: Int, width: Int) -> Int:
    var value = 0
    for bit in range(width):
        value |= Int(bits[offset + bit]) << bit
    return value


def _slice_u8(
    bits: Span[UInt8, ...], offset: Int, length: Int
) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(bits[offset + index])
    return result^


def _slice_complex(
    values: Span[Complex64, ...], offset: Int, length: Int
) -> List[Complex64]:
    var result = List[Complex64](capacity=length)
    for index in range(length):
        result.append(values[offset + index])
    return result^


def _signal_for_rate(rate_kbps: Int) raises -> Int:
    if rate_kbps == WIFI_DSSS_RATE_1_MBPS_KBPS:
        return 0x0A
    if rate_kbps == WIFI_DSSS_RATE_2_MBPS_KBPS:
        return 0x14
    if rate_kbps == WIFI_DSSS_RATE_5_5_MBPS_KBPS:
        return 0x37
    if rate_kbps == WIFI_DSSS_RATE_11_MBPS_KBPS:
        return 0x6E
    raise Error("unrecognized DSSS SIGNAL rate")


def _rate_for_signal(signal: Int) raises -> Int:
    if signal == 0x0A:
        return WIFI_DSSS_RATE_1_MBPS_KBPS
    if signal == 0x14:
        return WIFI_DSSS_RATE_2_MBPS_KBPS
    if signal == 0x37:
        return WIFI_DSSS_RATE_5_5_MBPS_KBPS
    if signal == 0x6E:
        return WIFI_DSSS_RATE_11_MBPS_KBPS
    raise Error("unrecognized DSSS PLCP SIGNAL field")


def wifi_dsss_plcp_scramble(
    bits: Span[UInt8, ...], seed: Int
) raises -> List[UInt8]:
    """Apply the Clause-15/16 self-synchronizing feedthrough scrambler.

    Seed bits 6 through 0 represent delay elements Z1 through Z7.  Each
    transmitted bit is ``input XOR Z4 XOR Z7`` and is shifted into Z1.
    The public primitive accepts every nonzero seven-bit seed so receivers can
    exercise the Clause-15 compatibility requirement; composite TX uses the
    fixed long/short seeds 0x6C and 0x1B.
    """
    _validate_scrambler_seed(seed)
    var state = seed
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("DSSS scrambler input must be binary")
        var output = Int(bits[index]) ^ ((state >> 3) & 1) ^ (state & 1)
        result.append(UInt8(output))
        state = (state >> 1) | (output << 6)
    return result^


def wifi_dsss_plcp_descramble(
    bits: Span[UInt8, ...], seed: Int
) raises -> List[UInt8]:
    """Invert the feedthrough scrambler from a known initial state."""
    _validate_scrambler_seed(seed)
    var state = seed
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("DSSS descrambler input must be binary")
        var received = Int(bits[index])
        result.append(UInt8(received ^ ((state >> 3) & 1) ^ (state & 1)))
        state = (state >> 1) | (received << 6)
    return result^


def wifi_dsss_plcp_crc16(bits: Span[UInt8, ...]) raises -> Int:
    """Return reflected CCITT CRC-16 for 32 PLCP bits in transmit order.

    The state starts at all ones, uses reflected polynomial ``0x8408``, and
    is complemented after SIGNAL, SERVICE, and LENGTH.  Bit zero of the
    returned integer is the first CRC bit transmitted.
    """
    if len(bits) != WIFI_DSSS_PLCP_CRC_INPUT_BITS:
        raise Error("DSSS PLCP CRC input must contain exactly 32 bits")
    var state = 0xFFFF
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("DSSS PLCP CRC input must be binary")
        var feedback = (state & 1) ^ Int(bits[index])
        state >>= 1
        if feedback != 0:
            state ^= 0x8408
    return state ^ 0xFFFF


def wifi_dsss_plcp_preamble_bits(
    *, short_preamble: Bool = False
) -> List[UInt8]:
    """Return raw SYNC+SFD bits before scrambling, first bit in time first."""
    var sync_bits = (
        WIFI_DSSS_SHORT_SYNC_BITS
        if short_preamble
        else WIFI_DSSS_LONG_SYNC_BITS
    )
    var result = List[UInt8](capacity=sync_bits + WIFI_DSSS_SFD_BITS)
    var sync_value = UInt8(0 if short_preamble else 1)
    for _ in range(sync_bits):
        result.append(sync_value)
    _append_lsb(result, 0x05CF if short_preamble else 0xF3A0, 16)
    return result^


def wifi_dsss_plcp_length(
    psdu_octets: Int, config: WifiDSSSPLCPConfig
) raises -> WifiDSSSPLCPLength:
    """Compute exact integer-microsecond LENGTH and 11 Mb/s extension bit."""
    config.validate()
    if psdu_octets < 1 or psdu_octets > WIFI_DSSS_MAX_PSDU_OCTETS:
        raise Error("DSSS PSDU length must be in [1,4095] octets")
    var length_us: Int
    var extension = False
    if config.data_rate_kbps == WIFI_DSSS_RATE_1_MBPS_KBPS:
        length_us = 8 * psdu_octets
    elif config.data_rate_kbps == WIFI_DSSS_RATE_2_MBPS_KBPS:
        length_us = 4 * psdu_octets
    elif config.data_rate_kbps == WIFI_DSSS_RATE_5_5_MBPS_KBPS:
        length_us = (16 * psdu_octets + 10) // 11
    else:
        length_us = (8 * psdu_octets + 10) // 11
        extension = length_us * 11 - 8 * psdu_octets >= 8
    if length_us > 0xFFFF:
        raise Error("DSSS PLCP LENGTH exceeds its unsigned 16-bit field")
    return WifiDSSSPLCPLength(psdu_octets, length_us, extension)


def wifi_dsss_plcp_header_pack(
    psdu_octets: Int, config: WifiDSSSPLCPConfig
) raises -> List[UInt8]:
    """Pack canonical SIGNAL/SERVICE/LENGTH/CRC bits before scrambling."""
    config.validate()
    var geometry = wifi_dsss_plcp_length(psdu_octets, config)
    var signal = _signal_for_rate(config.data_rate_kbps)
    var service = (4 if config.locked_clocks else 0) | (
        0x80 if geometry.length_extension else 0
    )
    var result = List[UInt8](capacity=WIFI_DSSS_PLCP_HEADER_BITS)
    _append_lsb(result, signal, 8)
    _append_lsb(result, service, 8)
    _append_lsb(result, geometry.length_us, 16)
    var crc = wifi_dsss_plcp_crc16(Span(result))
    _append_lsb(result, crc, WIFI_DSSS_PLCP_CRC_BITS)
    return result^


def wifi_dsss_plcp_header_parse(
    bits: Span[UInt8, ...], *, short_preamble: Bool = False
) raises -> WifiDSSSPLCPHeader:
    """Validate and parse one canonical unscrambled PLCP header."""
    if len(bits) != WIFI_DSSS_PLCP_HEADER_BITS:
        raise Error("DSSS PLCP header must contain exactly 48 bits")
    _validate_binary(bits, "DSSS PLCP header")
    var expected_crc = wifi_dsss_plcp_crc16(
        Span(_slice_u8(bits, 0, WIFI_DSSS_PLCP_CRC_INPUT_BITS))
    )
    var recovered_crc = _read_lsb(bits, 32, WIFI_DSSS_PLCP_CRC_BITS)
    if recovered_crc != expected_crc:
        raise Error("DSSS PLCP header CRC-16 failure")

    var signal = _read_lsb(bits, 0, 8)
    var service = _read_lsb(bits, 8, 8)
    # Reserved b0/b1/b4/b5/b6 and PBCC modulation-select b3 are zero in the
    # declared CCK profile.  b2 and b7 are the only accepted controls.
    if (service & 0x7B) != 0:
        raise Error("DSSS PLCP SERVICE requests reserved or PBCC behavior")
    var rate = _rate_for_signal(signal)
    var config = WifiDSSSPLCPConfig(
        rate,
        short_preamble=short_preamble,
        locked_clocks=(service & 4) != 0,
    )
    var length_us = _read_lsb(bits, 16, 16)
    if length_us == 0:
        raise Error("DSSS PLCP LENGTH must be nonzero")
    var extension = (service & 0x80) != 0
    var psdu_octets: Int
    if rate == WIFI_DSSS_RATE_1_MBPS_KBPS:
        if length_us % 8 != 0 or extension:
            raise Error("noncanonical 1 Mb/s DSSS LENGTH/SERVICE")
        psdu_octets = length_us // 8
    elif rate == WIFI_DSSS_RATE_2_MBPS_KBPS:
        if length_us % 4 != 0 or extension:
            raise Error("noncanonical 2 Mb/s DSSS LENGTH/SERVICE")
        psdu_octets = length_us // 4
    elif rate == WIFI_DSSS_RATE_5_5_MBPS_KBPS:
        if extension:
            raise Error("5.5 Mb/s CCK shall not set LENGTH extension")
        psdu_octets = (length_us * 11) // 16
    else:
        psdu_octets = (length_us * 11) // 8 - (1 if extension else 0)
    var geometry = wifi_dsss_plcp_length(psdu_octets, config)
    if (
        geometry.length_us != length_us
        or geometry.length_extension != extension
    ):
        raise Error("DSSS PLCP LENGTH/SERVICE is not a canonical CCK encoding")
    return WifiDSSSPLCPHeader(
        config, signal, service, geometry, recovered_crc
    )


def _octets_to_bits(octets: Span[UInt8, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * len(octets))
    for index in range(len(octets)):
        _append_lsb(result, Int(octets[index]), 8)
    return result^


def _bits_to_octets(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    if len(bits) % 8 != 0:
        raise Error("DSSS PSDU bits must contain complete octets")
    _validate_binary(bits, "DSSS PSDU")
    var result = List[UInt8](capacity=len(bits) // 8)
    for octet in range(len(bits) // 8):
        result.append(UInt8(_read_lsb(bits, 8 * octet, 8)))
    return result^


def _dbpsk_final_phase(bits: Span[UInt8, ...], initial: Int) -> Int:
    var phase = initial
    for index in range(len(bits)):
        phase = (phase + 2 * Int(bits[index])) & 3
    return phase


def _dqpsk_change(first: Int, second: Int) -> Int:
    return second if first == 0 else 3 - second


def _dqpsk_final_phase(bits: Span[UInt8, ...], initial: Int) -> Int:
    var phase = initial
    for symbol in range(len(bits) // 2):
        phase = (
            phase
            + _dqpsk_change(
                Int(bits[2 * symbol]), Int(bits[2 * symbol + 1])
            )
        ) & 3
    return phase


def _map_psdu(
    bits: Span[UInt8, ...], rate_kbps: Int, initial_phase: Int
) raises -> List[Complex64]:
    if rate_kbps == WIFI_DSSS_RATE_1_MBPS_KBPS:
        return wifi_dsss_dbpsk_spread(
            bits, initial_phase_quadrant=initial_phase
        )
    if rate_kbps == WIFI_DSSS_RATE_2_MBPS_KBPS:
        return wifi_dsss_dqpsk_spread(
            bits, initial_phase_quadrant=initial_phase
        )
    if rate_kbps == WIFI_DSSS_RATE_5_5_MBPS_KBPS:
        return wifi_cck_5_5_map(
            bits, initial_phase_quadrant=initial_phase, symbol_offset=0
        )
    return wifi_cck_11_map(
        bits, initial_phase_quadrant=initial_phase, symbol_offset=0
    )


def _data_chip_count(psdu_octets: Int, rate_kbps: Int) -> Int:
    var bits = 8 * psdu_octets
    if rate_kbps == WIFI_DSSS_RATE_1_MBPS_KBPS:
        return bits * WIFI_DSSS_BARKER_CHIPS
    if rate_kbps == WIFI_DSSS_RATE_2_MBPS_KBPS:
        return (bits // 2) * WIFI_DSSS_BARKER_CHIPS
    if rate_kbps == WIFI_DSSS_RATE_5_5_MBPS_KBPS:
        return (bits // 4) * WIFI_CCK_CHIPS
    return (bits // 8) * WIFI_CCK_CHIPS


def _reference_from_last_barker_chip(
    chips: Span[Complex64, ...]
) raises -> Complex64:
    if len(chips) < WIFI_DSSS_BARKER_CHIPS:
        raise Error("DSSS phase reference needs one Barker symbol")
    # The final coefficient of + - + + - + + + - - - is -1.
    var last = chips[len(chips) - 1]
    return Complex64(-last.re, -last.im)


def _append_bit_metadata(
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
        layout="bit-per-byte-first-in-time",
    ))


def _append_chip_metadata(
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
        layout="complex-chip-first-in-time",
    ))


def _tx_metadata(
    testcase_id: StringSlice,
    preamble_bits: Int,
    header_bits: Int,
    psdu_bits: Int,
    ppdu_bits: Int,
    scrambled_bits: Int,
    preamble_chips: Int,
    header_chips: Int,
    psdu_chips: Int,
    ppdu_chips: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=10)
    for stage, length in [
        ("preamble-bits", preamble_bits),
        ("plcp-header-bits", header_bits),
        ("psdu-bits-with-fcs", psdu_bits),
        ("ppdu-bits", ppdu_bits),
        ("scrambled-ppdu-bits", scrambled_bits),
    ]:
        _append_bit_metadata(result, testcase_id, stage, length)
    for stage, length in [
        ("preamble-chips", preamble_chips),
        ("plcp-header-chips", header_chips),
        ("psdu-chips", psdu_chips),
        ("ppdu-chips", ppdu_chips),
    ]:
        _append_chip_metadata(result, testcase_id, stage, length)
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "mpdu-fcs",
        "uint64",
        1,
        q_format="unsigned-u32",
        layout="scalar",
    ))
    return result^


def wifi_dsss_ppdu_tx(
    mpdu_octets_without_fcs: Span[UInt8, ...],
    config: WifiDSSSPLCPConfig,
    *,
    testcase_id: StringSlice = "wifi-dsss-plcp-tx",
) raises -> WifiDSSSPPDUTx:
    """Build one bounded long/short DSSS or HR/DSSS CCK PPDU chipstream."""
    config.validate()
    if len(mpdu_octets_without_fcs) > WIFI_DSSS_MAX_PSDU_OCTETS - 4:
        raise Error("DSSS MPDU plus four-octet FCS exceeds 4095 octets")
    var payload_bits = _octets_to_bits(mpdu_octets_without_fcs)
    var fcs = wifi_fcs(Span(payload_bits))
    var psdu_bits = payload_bits.copy()
    for bit in range(WIFI_DSSS_FCS_BITS):
        psdu_bits.append(UInt8((fcs >> UInt64(bit)) & UInt64(1)))

    var psdu_octets = len(mpdu_octets_without_fcs) + 4
    var header_bits = wifi_dsss_plcp_header_pack(psdu_octets, config)
    var header = wifi_dsss_plcp_header_parse(
        Span(header_bits), short_preamble=config.short_preamble
    )
    var preamble_bits = wifi_dsss_plcp_preamble_bits(
        short_preamble=config.short_preamble
    )
    var ppdu_bits = List[UInt8](
        capacity=len(preamble_bits) + len(header_bits) + len(psdu_bits)
    )
    for bit in preamble_bits:
        ppdu_bits.append(bit)
    for bit in header_bits:
        ppdu_bits.append(bit)
    for bit in psdu_bits:
        ppdu_bits.append(bit)
    var seed = (
        WIFI_DSSS_SHORT_SCRAMBLER_SEED
        if config.short_preamble
        else WIFI_DSSS_LONG_SCRAMBLER_SEED
    )
    var scrambled = wifi_dsss_plcp_scramble(Span(ppdu_bits), seed)

    var preamble_scrambled = _slice_u8(
        Span(scrambled), 0, len(preamble_bits)
    )
    var header_scrambled = _slice_u8(
        Span(scrambled), len(preamble_bits), len(header_bits)
    )
    var psdu_scrambled = _slice_u8(
        Span(scrambled), len(preamble_bits) + len(header_bits), len(psdu_bits)
    )

    var preamble_chips = wifi_dsss_dbpsk_spread(Span(preamble_scrambled))
    var preamble_phase = _dbpsk_final_phase(Span(preamble_scrambled), 0)
    var header_chips: List[Complex64]
    var header_phase: Int
    if config.short_preamble:
        header_chips = wifi_dsss_dqpsk_spread(
            Span(header_scrambled), initial_phase_quadrant=preamble_phase
        )
        header_phase = _dqpsk_final_phase(
            Span(header_scrambled), preamble_phase
        )
    else:
        header_chips = wifi_dsss_dbpsk_spread(
            Span(header_scrambled), initial_phase_quadrant=preamble_phase
        )
        header_phase = _dbpsk_final_phase(
            Span(header_scrambled), preamble_phase
        )
    var psdu_chips = _map_psdu(
        Span(psdu_scrambled), config.data_rate_kbps, header_phase
    )
    var ppdu_chips = List[Complex64](
        capacity=len(preamble_chips) + len(header_chips) + len(psdu_chips)
    )
    for value in preamble_chips:
        ppdu_chips.append(value)
    for value in header_chips:
        ppdu_chips.append(value)
    for value in psdu_chips:
        ppdu_chips.append(value)
    var metadata = _tx_metadata(
        testcase_id,
        len(preamble_bits),
        len(header_bits),
        len(psdu_bits),
        len(ppdu_bits),
        len(scrambled),
        len(preamble_chips),
        len(header_chips),
        len(psdu_chips),
        len(ppdu_chips),
    )
    return WifiDSSSPPDUTx(
        header,
        fcs,
        preamble_bits^,
        header_bits^,
        psdu_bits^,
        ppdu_bits^,
        scrambled^,
        preamble_chips^,
        header_chips^,
        psdu_chips^,
        ppdu_chips^,
        metadata^,
    )


def _demap_psdu(
    chips: Span[Complex64, ...],
    rate_kbps: Int,
    reference: Complex64,
) raises -> List[UInt8]:
    if rate_kbps == WIFI_DSSS_RATE_1_MBPS_KBPS:
        return wifi_dsss_dbpsk_despread_hard(
            chips, initial_reference=reference
        )
    if rate_kbps == WIFI_DSSS_RATE_2_MBPS_KBPS:
        return wifi_dsss_dqpsk_despread_hard(
            chips, initial_reference=reference
        )
    if rate_kbps == WIFI_DSSS_RATE_5_5_MBPS_KBPS:
        return wifi_cck_5_5_demap_hard(
            chips, initial_reference=reference, symbol_offset=0
        )
    return wifi_cck_11_demap_hard(
        chips, initial_reference=reference, symbol_offset=0
    )


def _validate_preamble(
    bits: Span[UInt8, ...], short_preamble: Bool
) raises:
    var expected = wifi_dsss_plcp_preamble_bits(
        short_preamble=short_preamble
    )
    if len(bits) != len(expected):
        raise Error("DSSS preamble bit geometry mismatch")
    for index in range(len(expected)):
        if bits[index] != expected[index]:
            raise Error("DSSS SYNC/SFD validation failure")


def _rx_metadata(
    testcase_id: StringSlice,
    chips: Int,
    scrambled_bits: Int,
    descrambled_bits: Int,
    payload_bits: Int,
    payload_octets: Int,
) raises -> List[CheckpointMetadata]:
    var result = List[CheckpointMetadata](capacity=8)
    _append_chip_metadata(result, testcase_id, "received-ppdu-chips", chips)
    for stage, length in [
        ("demapped-scrambled-bits", scrambled_bits),
        ("descrambled-ppdu-bits", descrambled_bits),
        ("recovered-mpdu-bits", payload_bits),
    ]:
        _append_bit_metadata(result, testcase_id, stage, length)
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "recovered-mpdu-octets",
        "uint8",
        payload_octets,
        q_format="unsigned-u8",
        layout="octet-first-in-time",
    ))
    for stage in ["recovered-fcs", "computed-fcs"]:
        result.append(checkpoint_metadata_1d(
            testcase_id,
            stage,
            "uint64",
            1,
            q_format="unsigned-u32",
            layout="scalar",
        ))
    result.append(checkpoint_metadata_1d(
        testcase_id,
        "fcs-ok",
        "bool",
        1,
        q_format="boolean",
        layout="scalar",
    ))
    return result^


def wifi_dsss_ppdu_rx(
    chips: Span[Complex64, ...],
    *,
    short_preamble: Bool = False,
    testcase_id: StringSlice = "wifi-dsss-plcp-rx",
) raises -> WifiDSSSPPDURx:
    """Parse a known-boundary bounded DSSS/HR-DSSS PPDU and verify FCS.

    Header CRC, SYNC/SFD, canonical LENGTH, reserved SERVICE bits, PBCC, exact
    chip geometry, nonfinite samples, zero-energy symbols, and incomplete
    groups are rejected.  A payload corruption is returned with ``fcs_ok``
    false so packet-error accounting is based on the actual recovered FCS.
    """
    var preamble_bits_count = (
        WIFI_DSSS_SHORT_SYNC_BITS + WIFI_DSSS_SFD_BITS
        if short_preamble
        else WIFI_DSSS_LONG_SYNC_BITS + WIFI_DSSS_SFD_BITS
    )
    var preamble_chip_count = preamble_bits_count * WIFI_DSSS_BARKER_CHIPS
    var header_chip_count = (
        (WIFI_DSSS_PLCP_HEADER_BITS // 2) * WIFI_DSSS_BARKER_CHIPS
        if short_preamble
        else WIFI_DSSS_PLCP_HEADER_BITS * WIFI_DSSS_BARKER_CHIPS
    )
    var prefix_chip_count = preamble_chip_count + header_chip_count
    if len(chips) <= prefix_chip_count:
        raise Error("DSSS PPDU is too short for PLCP plus one PSDU")

    var preamble_chips = _slice_complex(
        chips, 0, preamble_chip_count
    )
    var preamble_scrambled = wifi_dsss_dbpsk_despread_hard(
        Span(preamble_chips)
    )
    var preamble_reference = _reference_from_last_barker_chip(
        Span(preamble_chips)
    )
    var header_chips = _slice_complex(
        chips, preamble_chip_count, header_chip_count
    )
    var header_scrambled: List[UInt8]
    if short_preamble:
        header_scrambled = wifi_dsss_dqpsk_despread_hard(
            Span(header_chips), initial_reference=preamble_reference
        )
    else:
        header_scrambled = wifi_dsss_dbpsk_despread_hard(
            Span(header_chips), initial_reference=preamble_reference
        )
    var prefix_scrambled = preamble_scrambled.copy()
    for bit in header_scrambled:
        prefix_scrambled.append(bit)
    var seed = (
        WIFI_DSSS_SHORT_SCRAMBLER_SEED
        if short_preamble
        else WIFI_DSSS_LONG_SCRAMBLER_SEED
    )
    var prefix_plain = wifi_dsss_plcp_descramble(
        Span(prefix_scrambled), seed
    )
    var preamble_plain = _slice_u8(
        Span(prefix_plain), 0, preamble_bits_count
    )
    _validate_preamble(Span(preamble_plain), short_preamble)
    var header_plain = _slice_u8(
        Span(prefix_plain), preamble_bits_count, WIFI_DSSS_PLCP_HEADER_BITS
    )
    var header = wifi_dsss_plcp_header_parse(
        Span(header_plain), short_preamble=short_preamble
    )
    if header.length.psdu_octets < 4:
        raise Error("DSSS composite PSDU is too short to contain an FCS")
    var expected_data_chips = _data_chip_count(
        header.length.psdu_octets, header.config.data_rate_kbps
    )
    if len(chips) != prefix_chip_count + expected_data_chips:
        raise Error("DSSS PPDU chip count does not match decoded LENGTH/rate")
    var header_reference = _reference_from_last_barker_chip(
        Span(header_chips)
    )
    var data_chips = _slice_complex(
        chips, prefix_chip_count, expected_data_chips
    )
    var data_scrambled = _demap_psdu(
        Span(data_chips), header.config.data_rate_kbps, header_reference
    )
    var all_scrambled = prefix_scrambled.copy()
    for bit in data_scrambled:
        all_scrambled.append(bit)
    var all_plain = wifi_dsss_plcp_descramble(Span(all_scrambled), seed)
    var expected_plain_bits = (
        preamble_bits_count
        + WIFI_DSSS_PLCP_HEADER_BITS
        + 8 * header.length.psdu_octets
    )
    if len(all_plain) != expected_plain_bits:
        raise Error("DSSS descrambled PPDU bit geometry mismatch")

    var payload_bit_count = 8 * (header.length.psdu_octets - 4)
    var payload_offset = preamble_bits_count + WIFI_DSSS_PLCP_HEADER_BITS
    var payload_bits = _slice_u8(
        Span(all_plain), payload_offset, payload_bit_count
    )
    var payload_octets = _bits_to_octets(Span(payload_bits))
    var recovered_fcs = UInt64(0)
    for bit in range(WIFI_DSSS_FCS_BITS):
        recovered_fcs |= (
            UInt64(all_plain[payload_offset + payload_bit_count + bit])
            << UInt64(bit)
        )
    var computed_fcs = wifi_fcs(Span(payload_bits))
    var metadata = _rx_metadata(
        testcase_id,
        len(chips),
        len(all_scrambled),
        len(all_plain),
        len(payload_bits),
        len(payload_octets),
    )
    return WifiDSSSPPDURx(
        header,
        payload_bits^,
        payload_octets^,
        recovered_fcs,
        computed_fcs,
        recovered_fcs == computed_fcs,
        all_scrambled^,
        all_plain^,
        metadata^,
    )
