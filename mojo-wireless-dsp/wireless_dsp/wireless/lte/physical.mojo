"""Bounded LTE FDD physical-layer primitives from 3GPP TS 36.211 V18.0.2.

The module deliberately implements the ordinary 15 kHz, normal-CP, SISO/FDD
profile.  It covers the shared Gold generator, legacy synchronization signals,
cell-specific reference signals (CRS), the six standardized LTE bandwidths,
ordinary PDSCH/PUSCH scrambling, SC-FDMA transform precoding, a direct-parameter
PUSCH DM-RS reference profile, format-0 long PRACH sequence processing, and
bounded SISO shared-channel resource mapping.  TDD timing, extended CP,
NB-IoT, sidelink, MBSFN, hopping/OCC/multi-layer precoding, scheduler/control
resource selection, and radio-rate PRACH frequency placement are outside this
bounded profile.
"""

from std.collections import Span
from std.math import cos, floor, isfinite, sin, sqrt
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import dft_reference, normalized_correlation_at


comptime _PI = 3.1415926535897932384626433832795
comptime _LTE_MAX_RESOURCE_BLOCKS = 110
comptime _LTE_PRACH_LONG_SEQUENCE_LENGTH = 839
comptime _LTE_PRACH_FORMAT0_NORMALIZED_CP = 108


def lte_gold_bits(c_init: UInt32, length: Int) raises -> List[UInt8]:
    """TS 36.211 clause 7.2 length-31 Gold sequence with ``N_c=1600``."""
    comptime nc = 1600
    if c_init >= (UInt32(1) << UInt32(31)):
        raise Error("LTE Gold initialization must be a 31-bit value")
    if length < 0 or length > Int.MAX - nc - 31:
        raise Error(
            "LTE Gold sequence length is outside the supported Int range"
        )
    var total = nc + length + 31
    var x1 = List[UInt8](length=total, fill=UInt8(0))
    var x2 = List[UInt8](length=total, fill=UInt8(0))
    x1[0] = 1
    for index in range(31):
        x2[index] = UInt8((c_init >> UInt32(index)) & UInt32(1))
    for index in range(total - 31):
        x1[index + 31] = x1[index + 3] ^ x1[index]
        x2[index + 31] = (
            x2[index + 3] ^ x2[index + 2] ^ x2[index + 1] ^ x2[index]
        )
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(x1[index + nc] ^ x2[index + nc])
    return result^


def lte_pss_root(n_id_2: Int) raises -> Int:
    """Return Table 6.11.1.1-1's Zadoff--Chu root for ``N_ID^(2)``."""
    if n_id_2 == 0:
        return 25
    if n_id_2 == 1:
        return 29
    if n_id_2 == 2:
        return 34
    raise Error("LTE N_ID^(2) must be 0, 1, or 2")


def lte_pss(n_id_2: Int) raises -> List[Complex64]:
    """Generate the 62 frequency-domain PSS values of clause 6.11.1.1."""
    var root = lte_pss_root(n_id_2)
    var result = List[Complex64](capacity=62)
    for index in range(62):
        var product = index * (index + 1)
        if index >= 31:
            product = (index + 1) * (index + 2)
        var angle = -_PI * Float64(root * product) / 63.0
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


def _lte_sss_bases() -> Tuple[List[UInt8], List[UInt8], List[UInt8]]:
    var x_s = List[UInt8](length=31, fill=UInt8(0))
    var x_c = List[UInt8](length=31, fill=UInt8(0))
    var x_z = List[UInt8](length=31, fill=UInt8(0))
    x_s[4] = 1
    x_c[4] = 1
    x_z[4] = 1
    for index in range(26):
        x_s[index + 5] = x_s[index + 2] ^ x_s[index]
        x_c[index + 5] = x_c[index + 3] ^ x_c[index]
        x_z[index + 5] = (
            x_z[index + 4] ^ x_z[index + 2] ^ x_z[index + 1] ^ x_z[index]
        )
    return (x_s^, x_c^, x_z^)


def lte_sss_indices(n_id_1: Int) raises -> Tuple[Int, Int]:
    """Return Table 6.11.2.1-1's algorithmic ``(m0,m1)`` pair."""
    if n_id_1 < 0 or n_id_1 > 167:
        raise Error("LTE N_ID^(1) must be in [0,167]")
    var q_prime = n_id_1 // 30
    var q = (n_id_1 + q_prime * (q_prime + 1) // 2) // 30
    var m_prime = n_id_1 + q * (q + 1) // 2
    var m0 = m_prime % 31
    var m1 = (m0 + m_prime // 31 + 1) % 31
    return (m0, m1)


def lte_sss(physical_cell_id: Int, subframe: Int) raises -> List[Float64]:
    """Generate the 62 SSS chips for any of the 504 PCIs in subframe 0 or 5."""
    if physical_cell_id < 0 or physical_cell_id > 503:
        raise Error("LTE physical cell identity must be in [0,503]")
    if subframe != 0 and subframe != 5:
        raise Error("ordinary FDD LTE SSS is generated for subframe 0 or 5")
    var n_id_1 = physical_cell_id // 3
    var n_id_2 = physical_cell_id % 3
    var indices = lte_sss_indices(n_id_1)
    var m0 = indices[0]
    var m1 = indices[1]
    var bases = _lte_sss_bases()
    var result = List[Float64](length=62, fill=0.0)
    for index in range(31):
        var s0 = 1.0 - 2.0 * Float64(bases[0][(index + m0) % 31])
        var s1 = 1.0 - 2.0 * Float64(bases[0][(index + m1) % 31])
        var c0 = 1.0 - 2.0 * Float64(bases[1][(index + n_id_2) % 31])
        var c1 = 1.0 - 2.0 * Float64(bases[1][(index + n_id_2 + 3) % 31])
        var z0 = 1.0 - 2.0 * Float64(bases[2][(index + m0 % 8) % 31])
        var z1 = 1.0 - 2.0 * Float64(bases[2][(index + m1 % 8) % 31])
        if subframe == 0:
            result[2 * index] = s0 * c0
            result[2 * index + 1] = s1 * c1 * z0
        else:
            result[2 * index] = s1 * c0
            result[2 * index + 1] = s0 * c1 * z1
    return result^


struct LTEFDDConfiguration(ImplicitlyCopyable):
    """One standardized LTE FDD bandwidth with a practical baseband FFT."""

    var channel_bandwidth_khz: Int
    var downlink_resource_blocks: Int
    var uplink_resource_blocks: Int
    var fft_size: Int
    var sample_rate_hz: Int
    var subcarrier_spacing_hz: Int
    var symbols_per_slot: Int
    var slots_per_subframe: Int

    def __init__(out self, channel_bandwidth_khz: Int) raises:
        var resource_blocks: Int
        var fft_size: Int
        if channel_bandwidth_khz == 1400:
            resource_blocks = 6
            fft_size = 128
        elif channel_bandwidth_khz == 3000:
            resource_blocks = 15
            fft_size = 256
        elif channel_bandwidth_khz == 5000:
            resource_blocks = 25
            fft_size = 512
        elif channel_bandwidth_khz == 10000:
            resource_blocks = 50
            fft_size = 1024
        elif channel_bandwidth_khz == 15000:
            resource_blocks = 75
            fft_size = 1536
        elif channel_bandwidth_khz == 20000:
            resource_blocks = 100
            fft_size = 2048
        else:
            raise Error(
                "LTE FDD bandwidth must be 1.4, 3, 5, 10, 15, or 20 MHz"
            )
        self.channel_bandwidth_khz = channel_bandwidth_khz
        self.downlink_resource_blocks = resource_blocks
        self.uplink_resource_blocks = resource_blocks
        self.fft_size = fft_size
        self.sample_rate_hz = fft_size * 15000
        self.subcarrier_spacing_hz = 15000
        self.symbols_per_slot = 7
        self.slots_per_subframe = 2


def lte_fdd_configuration(
    channel_bandwidth_khz: Int,
) raises -> LTEFDDConfiguration:
    """Select one of the six ordinary LTE FDD channel-bandwidth profiles."""
    return LTEFDDConfiguration(channel_bandwidth_khz)


def lte_normal_cp_samples(
    configuration: LTEFDDConfiguration, symbol_in_slot: Int
) raises -> Int:
    """Return the scaled 160/144-sample normal CP for one 15 kHz symbol."""
    if symbol_in_slot < 0 or symbol_in_slot >= 7:
        raise Error("LTE normal-CP symbol index must be in [0,6]")
    # Reconstructing the profile rejects mutated/corrupt public values.
    var expected = LTEFDDConfiguration(configuration.channel_bandwidth_khz)
    if (
        expected.downlink_resource_blocks
        != configuration.downlink_resource_blocks
        or expected.uplink_resource_blocks
        != configuration.uplink_resource_blocks
        or expected.fft_size != configuration.fft_size
        or expected.sample_rate_hz != configuration.sample_rate_hz
        or expected.subcarrier_spacing_hz != configuration.subcarrier_spacing_hz
        or expected.symbols_per_slot != configuration.symbols_per_slot
        or expected.slots_per_subframe != configuration.slots_per_subframe
    ):
        raise Error("LTE FDD configuration fields are inconsistent")
    var reference_samples = 160 if symbol_in_slot == 0 else 144
    return reference_samples * configuration.fft_size // 2048


def lte_crs_c_init(
    physical_cell_id: Int, slot: Int, symbol_in_slot: Int
) raises -> UInt32:
    """Clause 6.10.1.1 normal-CP CRS Gold initialization."""
    if physical_cell_id < 0 or physical_cell_id > 503:
        raise Error("LTE physical cell identity must be in [0,503]")
    if slot < 0 or slot > 19:
        raise Error("LTE slot number must be in [0,19]")
    if symbol_in_slot < 0 or symbol_in_slot > 6:
        raise Error("LTE normal-CP symbol index must be in [0,6]")
    var value = (
        1024
        * (7 * (slot + 1) + symbol_in_slot + 1)
        * (2 * physical_cell_id + 1)
        + 2 * physical_cell_id
        + 1
    )
    return UInt32(value)


def lte_crs_sequence(
    physical_cell_id: Int, slot: Int, symbol_in_slot: Int
) raises -> List[Complex64]:
    """Generate all 220 normal-CP CRS QPSK values for one OFDM symbol."""
    var bits = lte_gold_bits(
        lte_crs_c_init(physical_cell_id, slot, symbol_in_slot),
        4 * _LTE_MAX_RESOURCE_BLOCKS,
    )
    var scale = 1.0 / sqrt(2.0)
    var result = List[Complex64](capacity=2 * _LTE_MAX_RESOURCE_BLOCKS)
    for index in range(2 * _LTE_MAX_RESOURCE_BLOCKS):
        result.append(
            Complex64(
                scale * (1.0 - 2.0 * Float64(bits[2 * index])),
                scale * (1.0 - 2.0 * Float64(bits[2 * index + 1])),
            )
        )
    return result^


struct LTECRSResourceElement(ImplicitlyCopyable):
    """One CRS resource element in a slot-local active-subcarrier grid."""

    var antenna_port: Int
    var symbol_in_slot: Int
    var subcarrier: Int
    var sequence_index: Int
    var value: Complex64

    def __init__(
        out self,
        antenna_port: Int,
        symbol_in_slot: Int,
        subcarrier: Int,
        sequence_index: Int,
        value: Complex64,
    ):
        self.antenna_port = antenna_port
        self.symbol_in_slot = symbol_in_slot
        self.subcarrier = subcarrier
        self.sequence_index = sequence_index
        self.value = value


def _lte_crs_v(slot: Int, symbol_in_slot: Int, antenna_port: Int) raises -> Int:
    if antenna_port == 0:
        return 0 if symbol_in_slot == 0 else 3
    if antenna_port == 1:
        return 3 if symbol_in_slot == 0 else 0
    if antenna_port == 2:
        return 3 * (slot % 2)
    if antenna_port == 3:
        return (3 + 3 * (slot % 2)) % 6
    raise Error("LTE CRS antenna port must be in [0,3]")


def lte_crs_port_mapping(
    physical_cell_id: Int,
    slot: Int,
    antenna_port: Int,
    downlink_resource_blocks: Int,
) raises -> List[LTECRSResourceElement]:
    """Map normal-CP CRS for antenna port 0--3 over one LTE downlink slot."""
    if physical_cell_id < 0 or physical_cell_id > 503:
        raise Error("LTE physical cell identity must be in [0,503]")
    if slot < 0 or slot > 19:
        raise Error("LTE slot number must be in [0,19]")
    if antenna_port < 0 or antenna_port > 3:
        raise Error("LTE CRS antenna port must be in [0,3]")
    if downlink_resource_blocks < 6 or downlink_resource_blocks > 110:
        raise Error(
            "LTE downlink bandwidth must contain 6 to 110 resource blocks"
        )
    var symbols = List[Int]()
    if antenna_port <= 1:
        symbols.append(0)
        symbols.append(4)
    else:
        symbols.append(1)
    var result = List[LTECRSResourceElement](
        capacity=len(symbols) * 2 * downlink_resource_blocks
    )
    var v_shift = physical_cell_id % 6
    for symbol_in_slot in symbols:
        var v = _lte_crs_v(slot, symbol_in_slot, antenna_port)
        var offset = (v + v_shift) % 6
        var sequence = lte_crs_sequence(physical_cell_id, slot, symbol_in_slot)
        for local_index in range(2 * downlink_resource_blocks):
            var sequence_index = (
                local_index
                + _LTE_MAX_RESOURCE_BLOCKS
                - downlink_resource_blocks
            )
            result.append(
                LTECRSResourceElement(
                    antenna_port,
                    symbol_in_slot,
                    6 * local_index + offset,
                    sequence_index,
                    sequence[sequence_index],
                )
            )
    return result^


def lte_pdsch_scrambling_c_init(
    rnti: Int, codeword: Int, slot: Int, physical_cell_id: Int
) raises -> UInt32:
    """Clause 6.3.1 ordinary PDSCH scrambling initialization."""
    if rnti < 0 or rnti > 0xFFFF:
        raise Error("LTE RNTI must be in [0,65535]")
    if codeword < 0 or codeword > 1:
        raise Error("LTE PDSCH codeword number must be zero or one")
    if slot < 0 or slot > 19:
        raise Error("LTE slot number must be in [0,19]")
    if physical_cell_id < 0 or physical_cell_id > 503:
        raise Error("LTE physical cell identity must be in [0,503]")
    return UInt32(
        rnti * (1 << 14)
        + codeword * (1 << 13)
        + (slot // 2) * (1 << 9)
        + physical_cell_id
    )


def lte_pdsch_scramble(
    bits: Span[UInt8, ...],
    rnti: Int,
    codeword: Int,
    slot: Int,
    physical_cell_id: Int,
) raises -> List[UInt8]:
    """Scramble ordinary binary PDSCH data for one codeword/subframe."""
    var sequence = lte_gold_bits(
        lte_pdsch_scrambling_c_init(rnti, codeword, slot, physical_cell_id),
        len(bits),
    )
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("LTE PDSCH input must contain only zero and one")
        result.append(bits[index] ^ sequence[index])
    return result^


def _lte_valid_transform_allocation(resource_blocks: Int) -> Bool:
    """Return whether ``12 * resource_blocks`` is a 2/3/5-smooth DFT size."""
    if resource_blocks < 1:
        return False
    var remainder = resource_blocks
    while remainder % 2 == 0:
        remainder //= 2
    while remainder % 3 == 0:
        remainder //= 3
    while remainder % 5 == 0:
        remainder //= 5
    return remainder == 1


def _validate_sc_fdma_samples(symbols: Span[Complex64, ...]) raises:
    if len(symbols) < 12 or len(symbols) > 12 * _LTE_MAX_RESOURCE_BLOCKS:
        raise Error("LTE SC-FDMA length must span 1 to 110 resource blocks")
    if len(symbols) % 12 != 0:
        raise Error("LTE SC-FDMA length must span whole resource blocks")
    if not _lte_valid_transform_allocation(len(symbols) // 12):
        raise Error("LTE SC-FDMA transform size must be 2/3/5-smooth")
    for index in range(len(symbols)):
        var value = symbols[index]
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("LTE SC-FDMA samples must be finite")


def lte_sc_fdma_transform_precoding(
    symbols: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Clause 5.3.3 unitary M-point DFT spreading for one SC-FDMA symbol."""
    _validate_sc_fdma_samples(symbols)
    var result = dft_reference(symbols, unitary=True)
    for value in result:
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("LTE SC-FDMA transform result must remain finite")
    return result^


def lte_sc_fdma_transform_deprecoding(
    symbols: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Unitary inverse wrapper for receiver-side SC-FDMA de-spreading."""
    _validate_sc_fdma_samples(symbols)
    var result = dft_reference(symbols, inverse=True, unitary=True)
    for value in result:
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("LTE SC-FDMA inverse result must remain finite")
    return result^


def lte_pusch_scrambling_c_init(
    rnti: Int, codeword: Int, slot: Int, physical_cell_id: Int
) raises -> UInt32:
    """TS 36.211 clause 5.3.1 ordinary PUSCH Gold initialization.

    ``slot`` is ``n_s`` and therefore identifies the containing subframe via
    ``floor(n_s/2)``.  Placeholder/repetition tags from TS 36.212 are outside
    this binary-vector primitive and must be resolved by the caller.
    """
    if rnti < 0 or rnti > 0xFFFF:
        raise Error("LTE PUSCH RNTI must be in [0,65535]")
    if codeword < 0 or codeword > 1:
        raise Error("LTE PUSCH codeword number must be zero or one")
    if slot < 0 or slot > 19:
        raise Error("LTE PUSCH slot number must be in [0,19]")
    if physical_cell_id < 0 or physical_cell_id > 503:
        raise Error("LTE physical cell identity must be in [0,503]")
    var value = (
        UInt64(rnti) * (UInt64(1) << UInt64(14))
        + UInt64(codeword) * (UInt64(1) << UInt64(13))
        + UInt64(slot // 2) * (UInt64(1) << UInt64(9))
        + UInt64(physical_cell_id)
    )
    if value >= (UInt64(1) << UInt64(31)):
        raise Error("LTE PUSCH scrambling initialization exceeds 31 bits")
    return UInt32(value)


def lte_pusch_scramble(
    bits: Span[UInt8, ...],
    rnti: Int,
    codeword: Int,
    slot: Int,
    physical_cell_id: Int,
) raises -> List[UInt8]:
    """Scramble ordinary binary PUSCH data with clause 5.3.1's sequence."""
    var sequence = lte_gold_bits(
        lte_pusch_scrambling_c_init(rnti, codeword, slot, physical_cell_id),
        len(bits),
    )
    var result = List[UInt8](capacity=len(bits))
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("LTE PUSCH input must contain only zero and one")
        result.append(bits[index] ^ sequence[index])
    return result^


def _lte_is_prime(value: Int) -> Bool:
    if value < 2:
        return False
    if value % 2 == 0:
        return value == 2
    var divisor = 3
    while divisor <= value // divisor:
        if value % divisor == 0:
            return False
        divisor += 2
    return True


def _lte_largest_prime_below(value: Int) raises -> Int:
    var candidate = value - 1
    while candidate >= 2:
        if _lte_is_prime(candidate):
            return candidate
        candidate -= 1
    raise Error("LTE base-sequence length has no smaller prime")


def _lte_pusch_dmrs_short_phase_row(
    group_number: Int,
    allocated_resource_blocks: Int,
) raises -> List[Int]:
    # Literal transcription of TS 36.211 V18.0.2, Tables 5.5.1.2-1
    # and 5.5.1.2-2. The returned row is owned by the caller.
    if allocated_resource_blocks == 1:
        if group_number == 0:
            return [-1, 1, 3, -3, 3, 3, 1, 1, 3, 1, -3, 3]
        elif group_number == 1:
            return [1, 1, 3, 3, 3, -1, 1, -3, -3, 1, -3, 3]
        elif group_number == 2:
            return [1, 1, -3, -3, -3, -1, -3, -3, 1, -3, 1, -1]
        elif group_number == 3:
            return [-1, 1, 1, 1, 1, -1, -3, -3, 1, -3, 3, -1]
        elif group_number == 4:
            return [-1, 3, 1, -1, 1, -1, -3, -1, 1, -1, 1, 3]
        elif group_number == 5:
            return [1, -3, 3, -1, -1, 1, 1, -1, -1, 3, -3, 1]
        elif group_number == 6:
            return [-1, 3, -3, -3, -3, 3, 1, -1, 3, 3, -3, 1]
        elif group_number == 7:
            return [-3, -1, -1, -1, 1, -3, 3, -1, 1, -3, 3, 1]
        elif group_number == 8:
            return [1, -3, 3, 1, -1, -1, -1, 1, 1, 3, -1, 1]
        elif group_number == 9:
            return [1, -3, -1, 3, 3, -1, -3, 1, 1, 1, 1, 1]
        elif group_number == 10:
            return [-1, 3, -1, 1, 1, -3, -3, -1, -3, -3, 3, -1]
        elif group_number == 11:
            return [3, 1, -1, -1, 3, 3, -3, 1, 3, 1, 3, 3]
        elif group_number == 12:
            return [1, -3, 1, 1, -3, 1, 1, 1, -3, -3, -3, 1]
        elif group_number == 13:
            return [3, 3, -3, 3, -3, 1, 1, 3, -1, -3, 3, 3]
        elif group_number == 14:
            return [-3, 1, -1, -3, -1, 3, 1, 3, 3, 3, -1, 1]
        elif group_number == 15:
            return [3, -1, 1, -3, -1, -1, 1, 1, 3, 1, -1, -3]
        elif group_number == 16:
            return [1, 3, 1, -1, 1, 3, 3, 3, -1, -1, 3, -1]
        elif group_number == 17:
            return [-3, 1, 1, 3, -3, 3, -3, -3, 3, 1, 3, -1]
        elif group_number == 18:
            return [-3, 3, 1, 1, -3, 1, -3, -3, -1, -1, 1, -3]
        elif group_number == 19:
            return [-1, 3, 1, 3, 1, -1, -1, 3, -3, -1, -3, -1]
        elif group_number == 20:
            return [-1, -3, 1, 1, 1, 1, 3, 1, -1, 1, -3, -1]
        elif group_number == 21:
            return [-1, 3, -1, 1, -3, -3, -3, -3, -3, 1, -1, -3]
        elif group_number == 22:
            return [1, 1, -3, -3, -3, -3, -1, 3, -3, 1, -3, 3]
        elif group_number == 23:
            return [1, 1, -1, -3, -1, -3, 1, -1, 1, 3, -1, 1]
        elif group_number == 24:
            return [1, 1, 3, 1, 3, 3, -1, 1, -1, -3, -3, 1]
        elif group_number == 25:
            return [1, -3, 3, 3, 1, 3, 3, 1, -3, -1, -1, 3]
        elif group_number == 26:
            return [1, 3, -3, -3, 3, -3, 1, -1, -1, 3, -1, -3]
        elif group_number == 27:
            return [-3, -1, -3, -1, -3, 3, 1, -1, 1, 3, -3, -3]
        elif group_number == 28:
            return [-1, 3, -3, 3, -1, 3, 3, -3, 3, 3, -1, -1]
        elif group_number == 29:
            return [3, -3, -3, -1, -1, -3, -1, 3, -3, 3, 1, -1]
    elif allocated_resource_blocks == 2:
        if group_number == 0:
            return [
                -1,
                3,
                1,
                -3,
                3,
                -1,
                1,
                3,
                -3,
                3,
                1,
                3,
                -3,
                3,
                1,
                1,
                -1,
                1,
                3,
                -3,
                3,
                -3,
                -1,
                -3,
            ]
        elif group_number == 1:
            return [
                -3,
                3,
                -3,
                -3,
                -3,
                1,
                -3,
                -3,
                3,
                -1,
                1,
                1,
                1,
                3,
                1,
                -1,
                3,
                -3,
                -3,
                1,
                3,
                1,
                1,
                -3,
            ]
        elif group_number == 2:
            return [
                3,
                -1,
                3,
                3,
                1,
                1,
                -3,
                3,
                3,
                3,
                3,
                1,
                -1,
                3,
                -1,
                1,
                1,
                -1,
                -3,
                -1,
                -1,
                1,
                3,
                3,
            ]
        elif group_number == 3:
            return [
                -1,
                -3,
                1,
                1,
                3,
                -3,
                1,
                1,
                -3,
                -1,
                -1,
                1,
                3,
                1,
                3,
                1,
                -1,
                3,
                1,
                1,
                -3,
                -1,
                -3,
                -1,
            ]
        elif group_number == 4:
            return [
                -1,
                -1,
                -1,
                -3,
                -3,
                -1,
                1,
                1,
                3,
                3,
                -1,
                3,
                -1,
                1,
                -1,
                -3,
                1,
                -1,
                -3,
                -3,
                1,
                -3,
                -1,
                -1,
            ]
        elif group_number == 5:
            return [
                -3,
                1,
                1,
                3,
                -1,
                1,
                3,
                1,
                -3,
                1,
                -3,
                1,
                1,
                -1,
                -1,
                3,
                -1,
                -3,
                3,
                -3,
                -3,
                -3,
                1,
                1,
            ]
        elif group_number == 6:
            return [
                1,
                1,
                -1,
                -1,
                3,
                -3,
                -3,
                3,
                -3,
                1,
                -1,
                -1,
                1,
                -1,
                1,
                1,
                -1,
                -3,
                -1,
                1,
                -1,
                3,
                -1,
                -3,
            ]
        elif group_number == 7:
            return [
                -3,
                3,
                3,
                -1,
                -1,
                -3,
                -1,
                3,
                1,
                3,
                1,
                3,
                1,
                1,
                -1,
                3,
                1,
                -1,
                1,
                3,
                -3,
                -1,
                -1,
                1,
            ]
        elif group_number == 8:
            return [
                -3,
                1,
                3,
                -3,
                1,
                -1,
                -3,
                3,
                -3,
                3,
                -1,
                -1,
                -1,
                -1,
                1,
                -3,
                -3,
                -3,
                1,
                -3,
                -3,
                -3,
                1,
                -3,
            ]
        elif group_number == 9:
            return [
                1,
                1,
                -3,
                3,
                3,
                -1,
                -3,
                -1,
                3,
                -3,
                3,
                3,
                3,
                -1,
                1,
                1,
                -3,
                1,
                -1,
                1,
                1,
                -3,
                1,
                1,
            ]
        elif group_number == 10:
            return [
                -1,
                1,
                -3,
                -3,
                3,
                -1,
                3,
                -1,
                -1,
                -3,
                -3,
                -3,
                -1,
                -3,
                -3,
                1,
                -1,
                1,
                3,
                3,
                -1,
                1,
                -1,
                3,
            ]
        elif group_number == 11:
            return [
                1,
                3,
                3,
                -3,
                -3,
                1,
                3,
                1,
                -1,
                -3,
                -3,
                -3,
                3,
                3,
                -3,
                3,
                3,
                -1,
                -3,
                3,
                -1,
                1,
                -3,
                1,
            ]
        elif group_number == 12:
            return [
                1,
                3,
                3,
                1,
                1,
                1,
                -1,
                -1,
                1,
                -3,
                3,
                -1,
                1,
                1,
                -3,
                3,
                3,
                -1,
                -3,
                3,
                -3,
                -1,
                -3,
                -1,
            ]
        elif group_number == 13:
            return [
                3,
                -1,
                -1,
                -1,
                -1,
                -3,
                -1,
                3,
                3,
                1,
                -1,
                1,
                3,
                3,
                3,
                -1,
                1,
                1,
                -3,
                1,
                3,
                -1,
                -3,
                3,
            ]
        elif group_number == 14:
            return [
                -3,
                -3,
                3,
                1,
                3,
                1,
                -3,
                3,
                1,
                3,
                1,
                1,
                3,
                3,
                -1,
                -1,
                -3,
                1,
                -3,
                -1,
                3,
                1,
                1,
                3,
            ]
        elif group_number == 15:
            return [
                -1,
                -1,
                1,
                -3,
                1,
                3,
                -3,
                1,
                -1,
                -3,
                -1,
                3,
                1,
                3,
                1,
                -1,
                -3,
                -3,
                -1,
                -1,
                -3,
                -3,
                -3,
                -1,
            ]
        elif group_number == 16:
            return [
                -1,
                -3,
                3,
                -1,
                -1,
                -1,
                -1,
                1,
                1,
                -3,
                3,
                1,
                3,
                3,
                1,
                -1,
                1,
                -3,
                1,
                -3,
                1,
                1,
                -3,
                -1,
            ]
        elif group_number == 17:
            return [
                1,
                3,
                -1,
                3,
                3,
                -1,
                -3,
                1,
                -1,
                -3,
                3,
                3,
                3,
                -1,
                1,
                1,
                3,
                -1,
                -3,
                -1,
                3,
                -1,
                -1,
                -1,
            ]
        elif group_number == 18:
            return [
                1,
                1,
                1,
                1,
                1,
                -1,
                3,
                -1,
                -3,
                1,
                1,
                3,
                -3,
                1,
                -3,
                -1,
                1,
                1,
                -3,
                -3,
                3,
                1,
                1,
                -3,
            ]
        elif group_number == 19:
            return [
                1,
                3,
                3,
                1,
                -1,
                -3,
                3,
                -1,
                3,
                3,
                3,
                -3,
                1,
                -1,
                1,
                -1,
                -3,
                -1,
                1,
                3,
                -1,
                3,
                -3,
                -3,
            ]
        elif group_number == 20:
            return [
                -1,
                -3,
                3,
                -3,
                -3,
                -3,
                -1,
                -1,
                -3,
                -1,
                -3,
                3,
                1,
                3,
                -3,
                -1,
                3,
                -1,
                1,
                -1,
                3,
                -3,
                1,
                -1,
            ]
        elif group_number == 21:
            return [
                -3,
                -3,
                1,
                1,
                -1,
                1,
                -1,
                1,
                -1,
                3,
                1,
                -3,
                -1,
                1,
                -1,
                1,
                -1,
                -1,
                3,
                3,
                -3,
                -1,
                1,
                -3,
            ]
        elif group_number == 22:
            return [
                -3,
                -1,
                -3,
                3,
                1,
                -1,
                -3,
                -1,
                -3,
                -3,
                3,
                -3,
                3,
                -3,
                -1,
                1,
                3,
                1,
                -3,
                1,
                3,
                3,
                -1,
                -3,
            ]
        elif group_number == 23:
            return [
                -1,
                -1,
                -1,
                -1,
                3,
                3,
                3,
                1,
                3,
                3,
                -3,
                1,
                3,
                -1,
                3,
                -1,
                3,
                3,
                -3,
                3,
                1,
                -1,
                3,
                3,
            ]
        elif group_number == 24:
            return [
                1,
                -1,
                3,
                3,
                -1,
                -3,
                3,
                -3,
                -1,
                -1,
                3,
                -1,
                3,
                -1,
                -1,
                1,
                1,
                1,
                1,
                -1,
                -1,
                -3,
                -1,
                3,
            ]
        elif group_number == 25:
            return [
                1,
                -1,
                1,
                -1,
                3,
                -1,
                3,
                1,
                1,
                -1,
                -1,
                -3,
                1,
                1,
                -3,
                1,
                3,
                -3,
                1,
                1,
                -3,
                -3,
                -1,
                -1,
            ]
        elif group_number == 26:
            return [
                -3,
                -1,
                1,
                3,
                1,
                1,
                -3,
                -1,
                -1,
                -3,
                3,
                -3,
                3,
                1,
                -3,
                3,
                -3,
                1,
                -1,
                1,
                -3,
                1,
                1,
                1,
            ]
        elif group_number == 27:
            return [
                -1,
                -3,
                3,
                3,
                1,
                1,
                3,
                -1,
                -3,
                -1,
                -1,
                -1,
                3,
                1,
                -3,
                -3,
                -1,
                3,
                -3,
                -1,
                -3,
                -1,
                -3,
                -1,
            ]
        elif group_number == 28:
            return [
                -1,
                -3,
                -1,
                -1,
                1,
                -3,
                -1,
                -1,
                1,
                -1,
                -3,
                1,
                1,
                -3,
                1,
                -3,
                -3,
                3,
                1,
                1,
                -1,
                3,
                -1,
                -1,
            ]
        elif group_number == 29:
            return [
                1,
                1,
                -1,
                -1,
                -3,
                -1,
                3,
                -1,
                3,
                -1,
                1,
                3,
                1,
                -1,
                3,
                1,
                3,
                -3,
                -3,
                1,
                -1,
                -1,
                1,
                3,
            ]
    raise Error("LTE short PUSCH DM-RS requires one or two RBs")


def _lte_pusch_dmrs_ifdma_short_phase_row(
    group_number: Int,
    reference_signal_subcarriers: Int,
) raises -> List[Int]:
    # Literal transcription of TS 36.211 V18.0.2, Tables 5.5.1.2-3
    # and 5.5.1.2-4. The returned row is owned by the caller.
    if reference_signal_subcarriers == 6:
        if group_number == 0:
            return [-1, -3, 3, -3, 3, -3]
        elif group_number == 1:
            return [-1, 3, -1, 1, 1, 1]
        elif group_number == 2:
            return [3, -1, -3, -3, 1, 3]
        elif group_number == 3:
            return [3, -1, -1, 1, -1, -1]
        elif group_number == 4:
            return [-1, -1, -3, 1, -3, -1]
        elif group_number == 5:
            return [1, 3, -3, -1, -3, 3]
        elif group_number == 6:
            return [-3, 3, -1, -1, 1, -3]
        elif group_number == 7:
            return [-1, -3, -3, 1, 3, 3]
        elif group_number == 8:
            return [3, -1, -1, 3, 1, 3]
        elif group_number == 9:
            return [3, -3, 3, 1, -1, 1]
        elif group_number == 10:
            return [-3, 1, -3, -3, -3, -3]
        elif group_number == 11:
            return [-3, -3, -3, 1, -3, -3]
        elif group_number == 12:
            return [3, -3, 1, -1, -3, -3]
        elif group_number == 13:
            return [3, -3, 3, -1, -1, -3]
        elif group_number == 14:
            return [3, -1, 1, 3, 3, 1]
        elif group_number == 15:
            return [-1, 1, -1, -3, 1, 1]
        elif group_number == 16:
            return [-3, -1, -3, -1, 3, 3]
        elif group_number == 17:
            return [1, -1, 3, -3, 3, 3]
        elif group_number == 18:
            return [1, 3, 1, 1, -3, 3]
        elif group_number == 19:
            return [-1, -3, -1, -1, 3, -3]
        elif group_number == 20:
            return [3, -1, -3, -1, -1, -3]
        elif group_number == 21:
            return [3, 1, 3, -3, -3, 1]
        elif group_number == 22:
            return [1, 3, -1, -1, 1, -1]
        elif group_number == 23:
            return [-3, 1, -3, 3, 3, 3]
        elif group_number == 24:
            return [1, 3, -3, 3, -3, 3]
        elif group_number == 25:
            return [-1, -1, 1, -3, 1, -1]
        elif group_number == 26:
            return [1, -3, -1, -1, 3, 1]
        elif group_number == 27:
            return [-3, -1, -1, 3, 1, 1]
        elif group_number == 28:
            return [-1, 3, -3, -3, -3, 3]
        elif group_number == 29:
            return [3, 1, -1, 1, 3, 1]
    elif reference_signal_subcarriers == 18:
        if group_number == 0:
            return [-3, -3, -3, -3, -3, -1, 1, -1, -3, 3, -1, 3, -1, 3, -3, -1, -1, 3]
        elif group_number == 1:
            return [-3, -3, -3, -3, -3, -1, 1, -1, 1, -3, -3, -3, 1, -1, 3, -3, -3, 1]
        elif group_number == 2:
            return [-3, -3, -3, -3, -3, -1, 1, 1, 3, -3, 1, 1, -3, 1, -3, 3, 1, -1]
        elif group_number == 3:
            return [-3, -3, -3, -3, -3, -1, 1, 3, -3, -1, 3, -1, 3, 1, -1, -3, 3, -3]
        elif group_number == 4:
            return [-3, -3, -3, -3, -3, -1, 3, -3, -1, 1, -1, -3, 3, 3, 1, -3, 1, -1]
        elif group_number == 5:
            return [-3, -3, -3, -3, -3, 1, -3, -3, -3, -3, 1, 1, 1, -3, 1, 1, -3, -3]
        elif group_number == 6:
            return [-3, -3, -3, -3, -3, 1, -3, -3, 1, 1, -3, -3, -3, 1, -1, 3, -1, 3]
        elif group_number == 7:
            return [-3, -3, -3, -3, -3, 1, -3, -1, 3, -1, 3, 3, -1, -1, 1, 3, 3, -1]
        elif group_number == 8:
            return [-3, -3, -3, -3, -3, 1, -1, -1, -1, -3, 3, -1, 3, -3, 3, -1, 1, 3]
        elif group_number == 9:
            return [-3, -3, -3, -3, -3, 3, -3, 1, -1, 3, -3, 3, 3, -1, -3, 1, 1, -3]
        elif group_number == 10:
            return [-3, -3, -3, -3, -3, 3, -1, -3, -3, 1, 1, 3, -3, -1, 3, -1, 3, 1]
        elif group_number == 11:
            return [-3, -3, -3, -3, -3, 3, 3, -1, -1, -1, 3, 1, -3, 3, -1, 1, -3, 1]
        elif group_number == 12:
            return [-3, -3, -3, -3, -1, -3, -3, -3, 1, 3, 1, -1, 3, -3, -1, -3, 1, 1]
        elif group_number == 13:
            return [-3, -3, -3, -3, -1, -3, -3, 1, -1, -1, 3, -3, -3, 1, 3, 1, -3, 1]
        elif group_number == 14:
            return [-3, -3, -3, -3, -1, -3, -3, 1, 3, -3, -1, 3, 1, 3, -1, 3, -1, -3]
        elif group_number == 15:
            return [-3, -3, -3, -3, -1, -3, -1, 3, -3, 1, -3, 1, -1, -3, -3, 1, 1, 3]
        elif group_number == 16:
            return [-3, -3, -3, -3, -1, -1, 3, -3, 3, -1, -3, 1, 1, -1, -3, -1, 3, -3]
        elif group_number == 17:
            return [-3, -3, -3, -3, -1, -1, 3, -1, -3, 1, 3, -1, -3, -3, 1, 3, -1, 1]
        elif group_number == 18:
            return [-3, -3, -3, -3, -1, 3, -1, -1, 3, 3, -1, -3, 1, 1, 1, -1, -3, -1]
        elif group_number == 19:
            return [-3, -3, -3, -3, -1, 3, 1, -3, -1, -3, 3, 1, -1, 3, -1, 1, 3, -1]
        elif group_number == 20:
            return [-3, -3, -3, -3, 1, -3, -3, 3, 1, 1, -3, -1, 1, 3, 3, -1, 3, -1]
        elif group_number == 21:
            return [-3, -3, -3, -3, 1, -3, 1, 3, 1, -1, -1, 3, 3, -1, 1, 1, -3, 3]
        elif group_number == 22:
            return [-3, -3, -3, -3, 1, -3, 3, -3, -1, 3, 1, 1, -1, -1, 3, 3, -1, 3]
        elif group_number == 23:
            return [-3, -3, -3, -3, 1, -3, 3, -1, 3, -3, -1, -1, -1, 1, -3, -3, 3, 1]
        elif group_number == 24:
            return [-3, -3, -3, -3, 1, 1, 3, 1, 1, -1, 3, 1, 1, 3, -1, -3, 1, 3]
        elif group_number == 25:
            return [-3, -3, -3, -3, 1, 3, 3, 3, 1, -3, 1, -3, -3, 3, -3, 1, -1, -3]
        elif group_number == 26:
            return [-3, -3, -3, -3, 3, 1, 3, 3, -1, 3, -3, -3, -1, 3, -1, -1, -3, 1]
        elif group_number == 27:
            return [-3, -3, -3, -1, -3, -3, -1, -1, -3, 3, 3, 1, -3, -1, -1, 3, 1, -3]
        elif group_number == 28:
            return [-3, -3, -3, -1, -3, 1, -1, 1, -3, 3, 1, -3, -1, 1, 3, 1, -1, -1]
        elif group_number == 29:
            return [-3, -3, -3, -1, -3, 3, 1, 1, -1, -1, 1, 3, 1, -3, 1, -3, -1, 1]
    raise Error("LTE IFDMA short PUSCH DM-RS phase row is unavailable")


def _validate_lte_pusch_dmrs_parameters(
    group_number: Int,
    sequence_number: Int,
    allocated_resource_blocks: Int,
) raises:
    if group_number < 0 or group_number > 29:
        raise Error("LTE PUSCH DM-RS sequence group must be in [0,29]")
    if sequence_number < 0 or sequence_number > 1:
        raise Error("LTE PUSCH DM-RS sequence number must be zero or one")
    if allocated_resource_blocks < 1 or allocated_resource_blocks > 110:
        raise Error("LTE PUSCH DM-RS supports 1 to 110 RBs")
    if allocated_resource_blocks < 6 and sequence_number != 0:
        raise Error("LTE sequence hopping requires at least six PUSCH RBs")


def lte_pusch_dmrs_ifdma_short_base_sequence(
    group_number: Int,
    reference_signal_subcarriers: Int,
) raises -> List[Complex64]:
    """Generate the direct Tables 5.5.1.2-3/-4 IFDMA base sequence.

    The caller supplies the already resolved sequence group ``u`` and exact
    reference-signal length, which must be 6 or 18 subcarriers.  Both tables
    define only base-sequence number ``v=0``.  This primitive does not infer
    ``ul-DMRS-IFDMA``, DCI fields, ``delta``, ``m``, hopping, cyclic shifts,
    OCC, or physical-resource mapping.
    """
    if group_number < 0 or group_number > 29:
        raise Error("LTE PUSCH DM-RS sequence group must be in [0,29]")
    if (
        reference_signal_subcarriers != 6
        and reference_signal_subcarriers != 18
    ):
        raise Error("LTE IFDMA short PUSCH DM-RS length must be 6 or 18")
    var phases = _lte_pusch_dmrs_ifdma_short_phase_row(
        group_number, reference_signal_subcarriers
    )
    var result = List[Complex64](capacity=reference_signal_subcarriers)
    for phase in phases:
        var angle = _PI * Float64(phase) / 4.0
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


def lte_pusch_dmrs_base_sequence(
    group_number: Int,
    sequence_number: Int,
    allocated_resource_blocks: Int,
) raises -> List[Complex64]:
    """Generate clauses 5.5.1.1--5.5.1.2's direct ``u,v`` base sequence.

    One and two RBs use Tables 5.5.1.2-1 and 5.5.1.2-2, respectively; three
    through 110 RBs use the Zadoff--Chu branch.  The caller supplies the
    already resolved sequence group ``u`` and sequence number ``v``; group
    and sequence hopping are not inferred here.  The length-dependent domain
    is explicit: allocations of one through five RBs require ``v=0``; six
    through 110 RBs permit ``v`` in ``{0,1}``.  This integer-RB API does not
    represent the separate IFDMA/sub-RB sequence lengths in Tables
    5.5.1.2-3 and 5.5.1.2-4.
    """
    _validate_lte_pusch_dmrs_parameters(
        group_number, sequence_number, allocated_resource_blocks
    )
    var sequence_length = 12 * allocated_resource_blocks
    if allocated_resource_blocks <= 2:
        var phases = _lte_pusch_dmrs_short_phase_row(
            group_number, allocated_resource_blocks
        )
        var short_result = List[Complex64](capacity=sequence_length)
        for index in range(sequence_length):
            var angle = _PI * Float64(phases[index]) / 4.0
            short_result.append(Complex64(cos(angle), sin(angle)))
        return short_result^
    var zc_length = _lte_largest_prime_below(sequence_length)
    var q_bar = Float64(zc_length) * Float64(group_number + 1) / 31.0
    var q = Int(floor(q_bar + 0.5))
    if Int(floor(2.0 * q_bar)) % 2 == 0:
        q += sequence_number
    else:
        q -= sequence_number
    var result = List[Complex64](capacity=sequence_length)
    for index in range(sequence_length):
        var zc_index = index % zc_length
        var angle = (
            -_PI * Float64(q * zc_index * (zc_index + 1)) / Float64(zc_length)
        )
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


def lte_pusch_dmrs_sequence(
    group_number: Int,
    sequence_number: Int,
    allocated_resource_blocks: Int,
    cyclic_shift_index: Int,
) raises -> List[Complex64]:
    """Apply clause 5.5.2.1's ``alpha=2*pi*n_cs/12`` to one DM-RS slot.

    This is the normal-CP, single-layer, direct-parameter reference profile.
    It represents one DM-RS symbol at slot-local ``l=3`` with OCC coefficient
    +1.  DCI/higher-layer resolution of ``n_cs``, hopping, and multi-layer OCC
    selection remain outside this primitive.  As in the base-sequence API,
    one through five allocated RBs require ``v=0`` and six through 110 RBs
    permit ``v`` in ``{0,1}``; the IFDMA/sub-RB sequence lengths from Tables
    5.5.1.2-3 and 5.5.1.2-4 remain outside this profile.
    """
    if cyclic_shift_index < 0 or cyclic_shift_index > 11:
        raise Error("LTE PUSCH DM-RS cyclic shift must be in [0,11]")
    var base = lte_pusch_dmrs_base_sequence(
        group_number, sequence_number, allocated_resource_blocks
    )
    var alpha = 2.0 * _PI * Float64(cyclic_shift_index) / 12.0
    var result = List[Complex64](capacity=len(base))
    for index in range(len(base)):
        var phase = Complex64(
            cos(alpha * Float64(index)), sin(alpha * Float64(index))
        )
        result.append(base[index] * phase)
    return result^


def lte_prach_root_sequence(root_u: Int) raises -> List[Complex64]:
    """Generate clause 5.7.2's 839-chip long PRACH Zadoff--Chu root."""
    if root_u < 1 or root_u >= _LTE_PRACH_LONG_SEQUENCE_LENGTH:
        raise Error("LTE long-PRACH root u must be in [1,838]")
    var result = List[Complex64](capacity=_LTE_PRACH_LONG_SEQUENCE_LENGTH)
    for index in range(_LTE_PRACH_LONG_SEQUENCE_LENGTH):
        var angle = (
            -_PI
            * Float64(root_u * index * (index + 1))
            / Float64(_LTE_PRACH_LONG_SEQUENCE_LENGTH)
        )
        result.append(Complex64(cos(angle), sin(angle)))
    return result^


def lte_prach_unrestricted_cyclic_shift(
    preamble_index: Int, n_cs: Int
) raises -> Int:
    """Return format-0 unrestricted-set ``C_v=v*N_CS`` on one root."""
    if preamble_index < 0:
        raise Error("LTE PRACH preamble index must be non-negative")
    if n_cs < 0 or n_cs >= _LTE_PRACH_LONG_SEQUENCE_LENGTH:
        raise Error("LTE long-PRACH N_CS must be in [0,838]")
    if n_cs == 0:
        if preamble_index != 0:
            raise Error("LTE PRACH N_CS=0 provides one preamble per root")
        return 0
    if preamble_index >= _LTE_PRACH_LONG_SEQUENCE_LENGTH // n_cs:
        raise Error("LTE PRACH preamble index requires the next logical root")
    return preamble_index * n_cs


def lte_prach_format0_sequence(
    root_u: Int, preamble_index: Int, n_cs: Int
) raises -> List[Complex64]:
    """Generate one unrestricted-set LTE format-0 long preamble sequence."""
    var cyclic_shift = lte_prach_unrestricted_cyclic_shift(preamble_index, n_cs)
    var root = lte_prach_root_sequence(root_u)
    var result = List[Complex64](capacity=_LTE_PRACH_LONG_SEQUENCE_LENGTH)
    for index in range(_LTE_PRACH_LONG_SEQUENCE_LENGTH):
        result.append(
            root[(index + cyclic_shift) % _LTE_PRACH_LONG_SEQUENCE_LENGTH]
        )
    return result^


def _validate_lte_prach_sequence(sequence: Span[Complex64, ...]) raises:
    if len(sequence) != _LTE_PRACH_LONG_SEQUENCE_LENGTH:
        raise Error("LTE format-0 PRACH sequence must contain 839 chips")
    for index in range(len(sequence)):
        if not isfinite(sequence[index].re) or not isfinite(sequence[index].im):
            raise Error("LTE PRACH sequence samples must be finite")


def lte_prach_format0_normalized_waveform(
    sequence: Span[Complex64, ...]
) raises -> List[Complex64]:
    """Prepend format 0's CP on a readable one-sample-per-ZC-chip grid.

    TS 36.211 Table 5.7.1-1 gives ``T_CP=3168*T_s`` and
    ``T_SEQ=24576*T_s``.  Rounding that exact ratio on the 839-chip grid gives
    108 CP samples.  This normalized envelope intentionally omits the final
    clause 5.7.3 radio-rate DFT/frequency placement and RF upconversion.
    """
    _validate_lte_prach_sequence(sequence)
    var result = List[Complex64](
        capacity=(
            _LTE_PRACH_FORMAT0_NORMALIZED_CP + _LTE_PRACH_LONG_SEQUENCE_LENGTH
        )
    )
    for index in range(_LTE_PRACH_FORMAT0_NORMALIZED_CP):
        result.append(
            sequence[
                _LTE_PRACH_LONG_SEQUENCE_LENGTH
                - _LTE_PRACH_FORMAT0_NORMALIZED_CP
                + index
            ]
        )
    for index in range(_LTE_PRACH_LONG_SEQUENCE_LENGTH):
        result.append(sequence[index])
    return result^


struct LTEPRACHDetection(ImplicitlyCopyable):
    """Best candidate from the bounded one-root format-0 detector."""

    var preamble_index: Int
    var cyclic_shift: Int
    var metric: Float64

    def __init__(
        out self, preamble_index: Int, cyclic_shift: Int, metric: Float64
    ):
        self.preamble_index = preamble_index
        self.cyclic_shift = cyclic_shift
        self.metric = metric


def lte_detect_prach_format0(
    received: Span[Complex64, ...],
    root_u: Int,
    n_cs: Int,
    preamble_count: Int,
) raises -> LTEPRACHDetection:
    """Exhaustively detect format-0 unrestricted preambles on one root.

    ``received`` may contain either 839 useful samples or the 947-sample
    normalized CP-plus-useful waveform returned by
    ``lte_prach_format0_normalized_waveform``.  The metric is normalized and
    therefore invariant to any finite non-zero complex gain.
    """
    if preamble_count < 1 or preamble_count > 64:
        raise Error("LTE PRACH detector requires 1 to 64 candidates")
    var offset = 0
    if len(received) == (
        _LTE_PRACH_FORMAT0_NORMALIZED_CP + _LTE_PRACH_LONG_SEQUENCE_LENGTH
    ):
        offset = _LTE_PRACH_FORMAT0_NORMALIZED_CP
    elif len(received) != _LTE_PRACH_LONG_SEQUENCE_LENGTH:
        raise Error("LTE PRACH detector expects 839 or 947 samples")
    # Validate the root even if later candidate validation would fail.
    _ = lte_prach_root_sequence(root_u)
    var maximum_component = 0.0
    for index in range(_LTE_PRACH_LONG_SEQUENCE_LENGTH):
        var sample = received[offset + index]
        if not isfinite(sample.re) or not isfinite(sample.im):
            raise Error("LTE PRACH detector samples must be finite")
        maximum_component = max(
            maximum_component, max(abs(sample.re), abs(sample.im))
        )
    var scale = maximum_component if maximum_component > 0.0 else 1.0
    var useful = List[Complex64](capacity=_LTE_PRACH_LONG_SEQUENCE_LENGTH)
    for index in range(_LTE_PRACH_LONG_SEQUENCE_LENGTH):
        useful.append(
            Complex64(
                received[offset + index].re / scale,
                received[offset + index].im / scale,
            )
        )
    var best = LTEPRACHDetection(0, 0, -1.0)
    for candidate in range(preamble_count):
        var shift = lte_prach_unrestricted_cyclic_shift(candidate, n_cs)
        var reference = lte_prach_format0_sequence(root_u, candidate, n_cs)
        var correlation = normalized_correlation_at(
            Span(useful), Span(reference), 0
        )
        var metric = correlation.magnitude_squared()
        if not isfinite(metric):
            raise Error("LTE PRACH correlation metric must remain finite")
        if metric > best.metric:
            best = LTEPRACHDetection(candidate, shift, metric)
    return best


def _lte_validate_siso_grid_resource_blocks(resource_blocks: Int) raises:
    if resource_blocks < 6 or resource_blocks > 110:
        raise Error("LTE SISO resource grid must contain 6 to 110 RBs")


def _lte_validate_finite_grid(values: Span[Complex64, ...]) raises:
    for index in range(len(values)):
        if not isfinite(values[index].re) or not isfinite(values[index].im):
            raise Error("LTE resource-grid values must be finite")


def _lte_pdsch_eligible_count(
    eligible_resource_elements: Span[UInt8, ...]
) raises -> Int:
    var count = 0
    for index in range(len(eligible_resource_elements)):
        if eligible_resource_elements[index] > 1:
            raise Error("LTE PDSCH eligibility mask must be binary")
        count += Int(eligible_resource_elements[index])
    return count


def lte_pdsch_map_siso(
    symbols: Span[Complex64, ...],
    downlink_resource_blocks: Int,
    eligible_resource_elements: Span[UInt8, ...],
) raises -> List[Complex64]:
    """Map SISO PDSCH symbols onto a normal-CP subframe eligibility mask.

    The flattened grid is ``index=l*(12*N_RB)+k``.  Mapping follows increasing
    ``k`` and then ``l`` as in clause 6.3.5.  The mask is deliberately supplied
    by the caller: scheduler/control-region and CRS/PSS/SSS/PBCH/CSI-RS
    reservation decisions are not inferred by this bounded mapper.
    """
    _lte_validate_siso_grid_resource_blocks(downlink_resource_blocks)
    var grid_length = 14 * 12 * downlink_resource_blocks
    if len(eligible_resource_elements) != grid_length:
        raise Error("LTE PDSCH eligibility mask does not match the grid")
    var eligible_count = _lte_pdsch_eligible_count(eligible_resource_elements)
    if len(symbols) != eligible_count:
        raise Error("LTE PDSCH symbol count does not match eligible REs")
    _lte_validate_finite_grid(symbols)
    var grid = List[Complex64](length=grid_length, fill=Complex64(0.0, 0.0))
    var symbol_index = 0
    for resource_index in range(grid_length):
        if eligible_resource_elements[resource_index] == 1:
            grid[resource_index] = symbols[symbol_index]
            symbol_index += 1
    return grid^


def lte_pdsch_extract_siso(
    grid: Span[Complex64, ...],
    downlink_resource_blocks: Int,
    eligible_resource_elements: Span[UInt8, ...],
) raises -> List[Complex64]:
    """Extract the inverse of ``lte_pdsch_map_siso`` in specification order."""
    _lte_validate_siso_grid_resource_blocks(downlink_resource_blocks)
    var grid_length = 14 * 12 * downlink_resource_blocks
    if (
        len(grid) != grid_length
        or len(eligible_resource_elements) != grid_length
    ):
        raise Error("LTE PDSCH grid or eligibility mask has invalid length")
    _lte_validate_finite_grid(grid)
    var eligible_count = _lte_pdsch_eligible_count(eligible_resource_elements)
    var result = List[Complex64](capacity=eligible_count)
    for resource_index in range(grid_length):
        if eligible_resource_elements[resource_index] == 1:
            result.append(grid[resource_index])
    return result^


def _validate_lte_pusch_mapping(
    uplink_resource_blocks: Int,
    first_resource_block: Int,
    allocated_resource_blocks: Int,
) raises:
    _lte_validate_siso_grid_resource_blocks(uplink_resource_blocks)
    if (
        not _lte_valid_transform_allocation(allocated_resource_blocks)
        or allocated_resource_blocks > uplink_resource_blocks
    ):
        raise Error(
            "LTE PUSCH allocation must be a valid 2/3/5-smooth DFT size"
        )
    if (
        first_resource_block < 0
        or first_resource_block
        > uplink_resource_blocks - allocated_resource_blocks
    ):
        raise Error("LTE PUSCH allocation is outside the uplink resource grid")


def lte_pusch_map_siso(
    transformed_symbols: Span[Complex64, ...],
    uplink_resource_blocks: Int,
    first_resource_block: Int,
    allocated_resource_blocks: Int,
) raises -> List[Complex64]:
    """Map a localized normal-CP SISO PUSCH subframe per clause 5.3.4.

    Input consists of twelve contiguous transform-precoded blocks (six data
    symbols per slot).  The flattened 14-symbol grid leaves slot-local symbol
    ``l=3`` empty for PUSCH DM-RS.  Frequency hopping, SRS shortening,
    sub-PRB allocation, scheduler selection, and multiple layers are excluded.
    """
    _validate_lte_pusch_mapping(
        uplink_resource_blocks,
        first_resource_block,
        allocated_resource_blocks,
    )
    var allocation_subcarriers = 12 * allocated_resource_blocks
    var expected_symbols = 12 * allocation_subcarriers
    if len(transformed_symbols) != expected_symbols:
        raise Error("LTE PUSCH requires twelve allocated data-symbol blocks")
    _lte_validate_finite_grid(transformed_symbols)
    var system_subcarriers = 12 * uplink_resource_blocks
    var grid = List[Complex64](
        length=14 * system_subcarriers, fill=Complex64(0.0, 0.0)
    )
    var input_index = 0
    for symbol in range(14):
        if symbol % 7 == 3:
            continue
        var grid_start = symbol * system_subcarriers + 12 * first_resource_block
        for subcarrier in range(allocation_subcarriers):
            grid[grid_start + subcarrier] = transformed_symbols[input_index]
            input_index += 1
    return grid^


def lte_pusch_extract_siso(
    grid: Span[Complex64, ...],
    uplink_resource_blocks: Int,
    first_resource_block: Int,
    allocated_resource_blocks: Int,
) raises -> List[Complex64]:
    """Extract the inverse of the bounded localized SISO PUSCH mapper."""
    _validate_lte_pusch_mapping(
        uplink_resource_blocks,
        first_resource_block,
        allocated_resource_blocks,
    )
    var system_subcarriers = 12 * uplink_resource_blocks
    if len(grid) != 14 * system_subcarriers:
        raise Error("LTE PUSCH resource grid has invalid length")
    _lte_validate_finite_grid(grid)
    var allocation_subcarriers = 12 * allocated_resource_blocks
    var result = List[Complex64](capacity=12 * allocation_subcarriers)
    for symbol in range(14):
        if symbol % 7 == 3:
            continue
        var grid_start = symbol * system_subcarriers + 12 * first_resource_block
        for subcarrier in range(allocation_subcarriers):
            result.append(grid[grid_start + subcarrier])
    return result^
