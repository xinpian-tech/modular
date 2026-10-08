"""Deterministic NR PDSCH link simulation over a flat channel plus AWGN."""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64
from wireless_dsp.channel.impairments import _add_awgn_with_fingerprint
from wireless_dsp.wireless.nr import (
    NRResourceGrid,
    nr_pdsch_dmrs_c_init,
    nr_pdsch_dmrs,
    nr_map_pdsch_comb2,
    nr_pdsch_encode_transport_block,
    nr_pdsch_decode_grid_comb2,
)
from .link_simulation import (
    PacketLinkResult,
    _TRACE_FNV1A64_OFFSET,
    _trace_fnv1a_byte,
    _trace_fnv1a_bits,
    _trace_fnv1a_int64_be,
)


# Non-normative deterministic CPU-reference work bounds.  These are not
# 3GPP transport-block, rate-matching, or resource-grid limits.
comptime _MAX_NR_LINK_PACKETS = 16
comptime _MAX_NR_LINK_PAYLOAD_BITS = 512
comptime _MAX_NR_LINK_OUTPUT_BITS = 4096


def _nr_next_bit(mut state: UInt64) -> UInt8:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return UInt8((state >> 63) & 1)


def simulate_nr_pdsch_awgn(
    packet_count: Int,
    noise_variance: Float64,
    *,
    seed: UInt64,
    payload_bits: Int = 100,
    output_bits: Int = 480,
    modulation_order: Int = 2,
) raises -> PacketLinkResult:
    """Run a bounded deterministic LDPC/DMRS PDSCH CPU reference chain."""
    if (
        packet_count < 1
        or payload_bits < 1
        or packet_count > _MAX_NR_LINK_PACKETS
        or payload_bits > _MAX_NR_LINK_PAYLOAD_BITS
        or output_bits > _MAX_NR_LINK_OUTPUT_BITS
        or not isfinite(noise_variance)
        or noise_variance < 0.0
    ):
        raise Error("invalid NR link-simulation dimensions")
    if (
        modulation_order != 2
        and modulation_order != 4
        and modulation_order != 6
        and modulation_order != 8
        and modulation_order != 10
    ):
        raise Error("unsupported NR link-simulation modulation order")
    if (
        output_bits < 1
        or output_bits % modulation_order != 0
        or output_bits // modulation_order > Int.MAX // 2
        or packet_count > Int.MAX // payload_bits
        or packet_count > 0xFFFF - 0x1200
    ):
        raise Error("NR rate-matched output must contain complete symbols")
    var data_symbols = output_bits // modulation_order
    var allocation_size = 2 * data_symbols
    var bit_state = seed ^ UInt64(0xA24BAED4963EE407)
    var total_errors = 0
    var failed_packets = 0
    var noise_fingerprint = _TRACE_FNV1A64_OFFSET
    var discrete_fingerprint = _TRACE_FNV1A64_OFFSET
    for packet in range(packet_count):
        var payload = List[UInt8](capacity=payload_bits)
        for _ in range(payload_bits):
            payload.append(_nr_next_bit(bit_state))
        var n_id = 42 + packet % 17
        var rnti = 0x1200 + packet
        var transmit = nr_pdsch_encode_transport_block(
            Span(payload),
            0.5,
            modulation_order,
            packet % 4,
            output_bits,
            rnti,
            0,
            n_id,
        )
        var c_init = nr_pdsch_dmrs_c_init(packet, 2, n_id, 0)
        var dmrs = nr_pdsch_dmrs(c_init, data_symbols)
        var transmit_grid = NRResourceGrid(1, allocation_size)
        nr_map_pdsch_comb2(
            transmit_grid,
            0,
            0,
            allocation_size,
            0,
            Span(transmit.symbols),
            Span(dmrs),
        )
        var samples = List[Complex64](capacity=allocation_size)
        var gain = Complex64(0.9, 0.2)
        for subcarrier in range(allocation_size):
            samples.append(transmit_grid[0, subcarrier] * gain)
        var noisy = _add_awgn_with_fingerprint(
            Span(samples),
            noise_variance,
            noise_fingerprint,
            seed=seed + UInt64(packet) * UInt64(0x9E3779B97F4A7C15),
        )
        var received_grid = NRResourceGrid(1, allocation_size)
        for subcarrier in range(allocation_size):
            received_grid[0, subcarrier] = noisy[subcarrier]
        var decoded = nr_pdsch_decode_grid_comb2(
            received_grid,
            0,
            0,
            allocation_size,
            0,
            Span(dmrs),
            Span(transmit.encoded_null_mask),
            transmit.profile,
            payload_bits,
            modulation_order,
            packet % 4,
            rnti,
            0,
            n_id,
            max(noise_variance, 1.0e-12),
        )
        var packet_failed = not decoded.transport_crc_ok or not decoded.ldpc_converged
        _trace_fnv1a_bits(discrete_fingerprint, Span(payload))
        _trace_fnv1a_bits(
            discrete_fingerprint, Span(transmit.transport_block)
        )
        _trace_fnv1a_bits(
            discrete_fingerprint, Span(transmit.rate_matched_bits)
        )
        _trace_fnv1a_bits(
            discrete_fingerprint, Span(transmit.scrambled_bits)
        )
        _trace_fnv1a_bits(discrete_fingerprint, Span(decoded.payload))
        var packet_bit_errors = 0
        for i in range(payload_bits):
            if decoded.payload[i] != payload[i]:
                total_errors += 1
                packet_bit_errors += 1
                packet_failed = True
        _trace_fnv1a_int64_be(discrete_fingerprint, packet_bit_errors)
        _trace_fnv1a_byte(
            discrete_fingerprint, UInt8(1 if packet_failed else 0)
        )
        if packet_failed:
            failed_packets += 1
    return PacketLinkResult(
        payload_bits * packet_count,
        total_errors,
        packet_count,
        failed_packets,
        noise_fingerprint,
        discrete_fingerprint,
    )
