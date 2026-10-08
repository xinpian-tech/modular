"""NR numerology, resource-grid, DM-RS estimation, and PDSCH extraction."""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import (
    ls_channel_estimate,
    linear_interpolate_complex,
    zero_forcing_equalize_siso,
)


struct NRNumerology(ImplicitlyCopyable):
    var mu: Int
    var subcarrier_spacing_hz: Int
    var slots_per_subframe: Int
    var slots_per_frame: Int
    var symbols_per_slot: Int

    def __init__(out self, mu: Int, *, extended_cp: Bool = False) raises:
        if mu < 0 or mu > 4:
            raise Error("NR numerology mu must be in [0,4]")
        if extended_cp and mu != 2:
            raise Error("extended CP is standardized only for mu=2")
        self.mu = mu
        self.subcarrier_spacing_hz = 15000 * (1 << mu)
        self.slots_per_subframe = 1 << mu
        self.slots_per_frame = 10 * (1 << mu)
        self.symbols_per_slot = 12 if extended_cp else 14


struct NRResourceGrid(Movable):
    """Row-major [OFDM symbol, subcarrier] complex resource grid."""
    var symbol_count: Int
    var subcarrier_count: Int
    var values: List[Complex64]

    def __init__(out self, symbol_count: Int, subcarrier_count: Int) raises:
        if symbol_count < 1 or subcarrier_count < 1:
            raise Error("resource grid dimensions must be positive")
        if symbol_count > Int.MAX // subcarrier_count:
            raise Error("resource grid dimensions overflow Int")
        self.symbol_count = symbol_count
        self.subcarrier_count = subcarrier_count
        self.values = List[Complex64](
            length=symbol_count * subcarrier_count, fill=Complex64(0.0, 0.0)
        )

    def __getitem__(
        self, symbol: Int, subcarrier: Int
    ) raises -> Complex64:
        if (
            symbol < 0
            or symbol >= self.symbol_count
            or subcarrier < 0
            or subcarrier >= self.subcarrier_count
        ):
            raise Error("resource grid index is out of range")
        return self.values[symbol * self.subcarrier_count + subcarrier]

    def __setitem__(
        mut self, symbol: Int, subcarrier: Int, value: Complex64
    ) raises:
        if (
            symbol < 0
            or symbol >= self.symbol_count
            or subcarrier < 0
            or subcarrier >= self.subcarrier_count
        ):
            raise Error("resource grid index is out of range")
        if not isfinite(value.re) or not isfinite(value.im):
            raise Error("resource grid values must be finite")
        self.values[symbol * self.subcarrier_count + subcarrier] = value


def nr_normal_cp_samples(
    fft_size: Int, symbol_in_slot: Int, mu: Int, *, slot_in_subframe: Int = 0
) raises -> Int:
    """38.211 normal-CP lengths, scaled from the 2048-sample reference FFT."""
    if (
        fft_size < 128 or fft_size % 128 != 0 or symbol_in_slot < 0
        or symbol_in_slot >= 14 or mu < 0 or mu > 4
        or slot_in_subframe < 0 or slot_in_subframe >= (1 << mu)
    ):
        raise Error("invalid FFT size or normal-CP symbol index")
    var base = 144 * fft_size // 2048
    var extension = 16 * (1 << mu) * fft_size // 2048
    # The extra samples occur at the start of each 0.5 ms interval.
    var interval = 7 * (1 << mu)
    var symbol_in_subframe = 14 * slot_in_subframe + symbol_in_slot
    return base + extension if symbol_in_subframe % interval == 0 else base


def nr_pdsch_dmrs_c_init(
    slot: Int, symbol: Int, n_id: Int, n_scid: Int,
) raises -> UInt32:
    """38.211 7.4.1.1.1 PDSCH DM-RS initialization value."""
    if slot < 0 or symbol < 0 or symbol > 13 or n_id < 0 or n_id > 65535 or n_scid < 0 or n_scid > 1:
        raise Error("invalid PDSCH DM-RS initialization fields")
    var modulus = UInt64(1) << 31
    var time_term = (
        UInt64(14) * (UInt64(slot) % modulus)
        + UInt64(symbol + 1)
    ) % modulus
    var value = (
        (((UInt64(1) << 17) * time_term) % modulus)
        * UInt64(2 * n_id + 1)
        + UInt64(2 * n_id + n_scid)
    ) % modulus
    return UInt32(value)


def _validate_comb2_allocation(
    grid: NRResourceGrid,
    symbol: Int,
    first_subcarrier: Int,
    allocation_size: Int,
    dmrs_offset: Int,
) raises:
    if symbol < 0 or symbol >= grid.symbol_count or first_subcarrier < 0:
        raise Error("PDSCH allocation starts outside the resource grid")
    if (
        allocation_size < 2
        or allocation_size > grid.subcarrier_count
        or first_subcarrier > grid.subcarrier_count - allocation_size
    ):
        raise Error("PDSCH allocation exceeds the resource grid")
    if dmrs_offset < 0 or dmrs_offset > 1:
        raise Error("comb-2 DM-RS offset must be zero or one")


def nr_map_pdsch_comb2(
    mut grid: NRResourceGrid, symbol: Int, first_subcarrier: Int,
    allocation_size: Int, dmrs_offset: Int,
    data: Span[Complex64, ...], dmrs: Span[Complex64, ...],
) raises:
    """Map one configuration-type-1 DM-RS symbol (comb 2, one CDM port)."""
    _validate_comb2_allocation(
        grid, symbol, first_subcarrier, allocation_size, dmrs_offset
    )
    var pilot_count = (allocation_size + 1 - dmrs_offset) // 2
    if len(dmrs) != pilot_count or len(data) != allocation_size - pilot_count:
        raise Error("PDSCH data or DM-RS count does not match allocation")
    for index in range(len(data)):
        if not isfinite(data[index].re) or not isfinite(data[index].im):
            raise Error("PDSCH data values must be finite")
    for index in range(len(dmrs)):
        if not isfinite(dmrs[index].re) or not isfinite(dmrs[index].im):
            raise Error("PDSCH DM-RS values must be finite")
    var data_index = 0
    var pilot_index = 0
    for local in range(allocation_size):
        if local % 2 == dmrs_offset:
            grid[symbol, first_subcarrier + local] = Complex64(
                dmrs[pilot_index].re, dmrs[pilot_index].im
            )
            pilot_index += 1
        else:
            grid[symbol, first_subcarrier + local] = Complex64(
                data[data_index].re, data[data_index].im
            )
            data_index += 1


def nr_extract_pdsch_comb2(
    grid: NRResourceGrid, symbol: Int, first_subcarrier: Int,
    allocation_size: Int, dmrs_offset: Int,
) raises -> List[Complex64]:
    _validate_comb2_allocation(
        grid, symbol, first_subcarrier, allocation_size, dmrs_offset
    )
    var result = List[Complex64]()
    for local in range(allocation_size):
        if local % 2 != dmrs_offset:
            var value = grid[symbol, first_subcarrier + local]
            if not isfinite(value.re) or not isfinite(value.im):
                raise Error("PDSCH grid values must be finite")
            result.append(value)
    return result^


def nr_extract_dmrs_comb2(
    grid: NRResourceGrid, symbol: Int, first_subcarrier: Int,
    allocation_size: Int, dmrs_offset: Int,
) raises -> List[Complex64]:
    _validate_comb2_allocation(
        grid, symbol, first_subcarrier, allocation_size, dmrs_offset
    )
    var result = List[Complex64]()
    for local in range(allocation_size):
        if local % 2 == dmrs_offset:
            var value = grid[symbol, first_subcarrier + local]
            if not isfinite(value.re) or not isfinite(value.im):
                raise Error("PDSCH grid values must be finite")
            result.append(value)
    return result^


def nr_ls_channel_estimate_comb2(
    received_dmrs: Span[Complex64, ...], known_dmrs: Span[Complex64, ...],
    allocation_size: Int, dmrs_offset: Int,
) raises -> List[Complex64]:
    """LS at comb-2 pilots followed by linear frequency interpolation."""
    if (
        len(received_dmrs) != len(known_dmrs) or len(known_dmrs) == 0
        or allocation_size < 2 or dmrs_offset < 0 or dmrs_offset > 1
    ):
        raise Error("DM-RS observations and references must match")
    var expected_pilots = (allocation_size + 1 - dmrs_offset) // 2
    if len(known_dmrs) != expected_pilots:
        raise Error("DM-RS count does not match the comb-2 allocation")
    var pilots = ls_channel_estimate(received_dmrs, known_dmrs)
    var positions = List[Int](capacity=len(pilots))
    for i in range(len(known_dmrs)):
        positions.append(dmrs_offset + 2 * i)
    return linear_interpolate_complex(Span(pilots), Span(positions), allocation_size)


def nr_equalize_pdsch_comb2(
    data: Span[Complex64, ...], channel: Span[Complex64, ...], dmrs_offset: Int,
) raises -> List[Complex64]:
    if dmrs_offset < 0 or dmrs_offset > 1:
        raise Error("comb-2 DM-RS offset must be zero or one")
    var expected_data = len(channel) - (len(channel) + 1 - dmrs_offset) // 2
    if len(data) != expected_data:
        raise Error("data and channel estimate dimensions do not match")
    var data_channels = List[Complex64](capacity=len(data))
    for local in range(len(channel)):
        if local % 2 != dmrs_offset:
            data_channels.append(Complex64(channel[local].re, channel[local].im))
    return zero_forcing_equalize_siso(data, Span(data_channels))


def nr_map_ssb_synchronization(
    mut grid: NRResourceGrid, first_subcarrier: Int,
    pss: Span[Float64, ...], sss: Span[Float64, ...],
) raises:
    """Map PSS to symbol 0 and SSS to symbol 2, SSB subcarriers 56..182."""
    if (
        grid.symbol_count < 4
        or first_subcarrier < 0
        or grid.subcarrier_count < 240
        or first_subcarrier > grid.subcarrier_count - 240
    ):
        raise Error("SS/PBCH block does not fit in resource grid")
    if len(pss) != 127 or len(sss) != 127:
        raise Error("PSS and SSS must each contain 127 symbols")
    for i in range(127):
        if not isfinite(pss[i]) or not isfinite(sss[i]):
            raise Error("PSS and SSS values must be finite")
        grid[0, first_subcarrier + 56 + i] = Complex64(pss[i], 0.0)
        grid[2, first_subcarrier + 56 + i] = Complex64(sss[i], 0.0)
