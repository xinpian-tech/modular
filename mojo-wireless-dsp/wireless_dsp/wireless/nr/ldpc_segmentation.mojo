"""TS 38.212 NR LDPC code-block segmentation and multi-block plumbing."""

from std.collections import Span
from wireless_dsp.modem.crc import crc_append, crc_bits, crc_check
from .ldpc_profile import NRLDPCProfile
from .ldpc_codec import (
    nr_ldpc_code_block_output_bits,
    nr_ldpc_decode,
    nr_ldpc_encode,
    nr_ldpc_rate_match,
    nr_ldpc_rate_recover,
)


struct NRLDPCSegments(Movable):
    """Flattened encoder inputs and their systematic filler masks."""

    var bits: List[UInt8]
    var null_mask: List[UInt8]
    var code_blocks: Int
    var block_bits: Int

    def __init__(
        out self, var bits: List[UInt8], var null_mask: List[UInt8],
        code_blocks: Int, block_bits: Int,
    ):
        self.bits = bits^
        self.null_mask = null_mask^
        self.code_blocks = code_blocks
        self.block_bits = block_bits


struct NRLDPCEncodedBlocks(Movable):
    """Flattened punctured LDPC codewords and circular-buffer null masks."""

    var bits: List[UInt8]
    var null_mask: List[UInt8]
    var code_blocks: Int
    var block_bits: Int

    def __init__(
        out self, var bits: List[UInt8], var null_mask: List[UInt8],
        code_blocks: Int, block_bits: Int,
    ):
        self.bits = bits^
        self.null_mask = null_mask^
        self.code_blocks = code_blocks
        self.block_bits = block_bits


struct NRLDPCDecodedBlocks(Movable):
    """Flattened decoded encoder inputs with per-block convergence metadata."""

    var bits: List[UInt8]
    var iterations: List[Int]
    var converged: Bool
    var code_blocks: Int
    var block_bits: Int

    def __init__(
        out self, var bits: List[UInt8], var iterations: List[Int],
        converged: Bool, code_blocks: Int, block_bits: Int,
    ):
        self.bits = bits^
        self.iterations = iterations^
        self.converged = converged
        self.code_blocks = code_blocks
        self.block_bits = block_bits


struct NRLDPCDesegmentResult(Movable):
    """Reassembled transport-block-with-CRC and CB-CRC status."""

    var bits: List[UInt8]
    var code_block_crc_ok: Bool

    def __init__(
        out self, var bits: List[UInt8], code_block_crc_ok: Bool
    ):
        self.bits = bits^
        self.code_block_crc_ok = code_block_crc_ok


def nr_ldpc_crc24b(bits: Span[UInt8, ...]) raises -> UInt64:
    """Return the CRC24B remainder used for LDPC code-block segmentation."""
    return crc_bits(bits, width=24, polynomial=UInt64(0x800063))


def nr_ldpc_crc24b_append(bits: Span[UInt8, ...]) raises -> List[UInt8]:
    return crc_append(bits, width=24, polynomial=UInt64(0x800063))


def nr_ldpc_crc24b_check(bits: Span[UInt8, ...]) raises -> Bool:
    return crc_check(bits, width=24, polynomial=UInt64(0x800063))


def nr_ldpc_segment(
    transport_block_with_crc: Span[UInt8, ...], profile: NRLDPCProfile
) raises -> NRLDPCSegments:
    """Segment a TB+CRC, append CB CRC24B, pad, and mark ``<NULL>`` bits."""
    if len(transport_block_with_crc) != profile.transport_block_bits:
        raise Error("transport block length does not match NR LDPC profile")
    for i in range(len(transport_block_with_crc)):
        if transport_block_with_crc[i] > 1:
            raise Error("transport block must contain only zero and one")
    var total = profile.code_blocks * profile.encoder_input_bits
    var result = List[UInt8](length=total, fill=UInt8(0))
    var nulls = List[UInt8](length=total, fill=UInt8(1))
    var source_offset = 0
    for block in range(profile.code_blocks):
        # TS 38.212 pads the final CB payload with zeros before CRC24B.
        var payload = List[UInt8](
            length=profile.code_block_payload_bits, fill=UInt8(0)
        )
        var remaining = len(transport_block_with_crc) - source_offset
        var copied = min(profile.code_block_payload_bits, remaining)
        for i in range(copied):
            payload[i] = transport_block_with_crc[source_offset + i]
        source_offset += copied
        var with_crc = payload^
        if profile.code_block_crc_bits == 24:
            with_crc = nr_ldpc_crc24b_append(Span(with_crc))
        var destination = block * profile.encoder_input_bits
        for i in range(len(with_crc)):
            result[destination + i] = with_crc[i]
            nulls[destination + i] = UInt8(0)
    if source_offset != len(transport_block_with_crc):
        raise Error("NR LDPC segmentation did not consume the transport block")
    return NRLDPCSegments(
        result^, nulls^, profile.code_blocks, profile.encoder_input_bits
    )


def nr_ldpc_desegment(
    decoded_blocks: Span[UInt8, ...], profile: NRLDPCProfile
) raises -> NRLDPCDesegmentResult:
    """Check/remove CB CRC24B and reassemble the TB+CRC bit sequence."""
    if len(decoded_blocks) != profile.code_blocks * profile.encoder_input_bits:
        raise Error("decoded NR LDPC blocks have invalid dimensions")
    var result = List[UInt8](capacity=profile.transport_block_bits)
    var all_crc_ok = True
    for block in range(profile.code_blocks):
        var source = block * profile.encoder_input_bits
        var block_data = List[UInt8](capacity=profile.code_block_data_bits)
        for i in range(profile.code_block_data_bits):
            var value = decoded_blocks[source + i]
            if value > 1:
                raise Error("decoded block must contain only zero and one")
            block_data.append(value)
        if profile.code_block_crc_bits == 24:
            if not nr_ldpc_crc24b_check(Span(block_data)):
                all_crc_ok = False
        for i in range(profile.code_block_payload_bits):
            if len(result) < profile.transport_block_bits:
                result.append(block_data[i])
    return NRLDPCDesegmentResult(result^, all_crc_ok)


def nr_ldpc_encode_code_blocks(
    segments: NRLDPCSegments, profile: NRLDPCProfile
) raises -> NRLDPCEncodedBlocks:
    """Encode and puncture every flattened code block, preserving nulls."""
    if segments.code_blocks != profile.code_blocks:
        raise Error("segment count does not match NR LDPC profile")
    if segments.block_bits != profile.encoder_input_bits:
        raise Error("segment length does not match NR LDPC profile")
    if len(segments.bits) != profile.code_blocks * profile.encoder_input_bits:
        raise Error("invalid flattened NR LDPC segments")
    if len(segments.null_mask) != len(segments.bits):
        raise Error("invalid systematic null mask")
    var result = List[UInt8](capacity=profile.code_blocks * profile.encoded_bits)
    var nulls = List[UInt8](
        length=profile.code_blocks * profile.encoded_bits, fill=UInt8(0)
    )
    var punctured = 2 * profile.lifting_size
    for block in range(profile.code_blocks):
        var information = List[UInt8](capacity=profile.encoder_input_bits)
        var source = block * profile.encoder_input_bits
        for i in range(profile.encoder_input_bits):
            information.append(segments.bits[source + i])
        var encoded = nr_ldpc_encode(
            Span(information), profile.base_graph, profile.lifting_size
        )
        for value in encoded:
            result.append(value)
        var mask_offset = block * profile.encoded_bits
        for i in range(profile.encoded_bits):
            var full_index = i + punctured
            if full_index < profile.encoder_input_bits:
                nulls[mask_offset + i] = segments.null_mask[
                    source + full_index
                ]
    return NRLDPCEncodedBlocks(
        result^, nulls^, profile.code_blocks, profile.encoded_bits
    )


def nr_ldpc_rate_match_code_blocks(
    encoded_blocks: NRLDPCEncodedBlocks, profile: NRLDPCProfile,
    redundancy_version: Int, total_output_bits: Int,
    modulation_order: Int, layers: Int, circular_buffer_bits: Int = 0,
) raises -> List[UInt8]:
    """Rate-match and concatenate every LDPC block of a transport block."""
    if encoded_blocks.code_blocks != profile.code_blocks:
        raise Error("encoded block count does not match NR LDPC profile")
    if encoded_blocks.block_bits != profile.encoded_bits:
        raise Error("encoded block size does not match NR LDPC profile")
    var result = List[UInt8](capacity=total_output_bits)
    for block in range(profile.code_blocks):
        var encoded = List[UInt8](capacity=profile.encoded_bits)
        var nulls = List[UInt8](capacity=profile.encoded_bits)
        var source = block * profile.encoded_bits
        for i in range(profile.encoded_bits):
            encoded.append(encoded_blocks.bits[source + i])
            nulls.append(encoded_blocks.null_mask[source + i])
        var output_bits = nr_ldpc_code_block_output_bits(
            total_output_bits, modulation_order, layers,
            profile.code_blocks, block,
        )
        var matched = nr_ldpc_rate_match(
            Span(encoded), Span(nulls), profile.base_graph,
            profile.lifting_size, redundancy_version, output_bits,
            modulation_order, circular_buffer_bits,
        )
        for value in matched:
            result.append(value)
    return result^


def nr_ldpc_rate_recover_code_blocks(
    received: Span[Float64, ...], encoded_null_mask: Span[UInt8, ...],
    profile: NRLDPCProfile, redundancy_version: Int,
    modulation_order: Int, layers: Int, circular_buffer_bits: Int = 0,
    filler_llr: Float64 = 50.0,
) raises -> List[Float64]:
    """Deconcatenate and rate-recover all LDPC code blocks."""
    if len(encoded_null_mask) != profile.code_blocks * profile.encoded_bits:
        raise Error("encoded null mask has invalid dimensions")
    var result = List[Float64](
        capacity=profile.code_blocks * profile.encoded_bits
    )
    var received_offset = 0
    for block in range(profile.code_blocks):
        var output_bits = nr_ldpc_code_block_output_bits(
            len(received), modulation_order, layers,
            profile.code_blocks, block,
        )
        var block_llrs = List[Float64](capacity=output_bits)
        for i in range(output_bits):
            block_llrs.append(received[received_offset + i])
        received_offset += output_bits
        var nulls = List[UInt8](capacity=profile.encoded_bits)
        var mask_offset = block * profile.encoded_bits
        for i in range(profile.encoded_bits):
            nulls.append(encoded_null_mask[mask_offset + i])
        var recovered = nr_ldpc_rate_recover(
            Span(block_llrs), Span(nulls), profile.base_graph,
            profile.lifting_size, redundancy_version, modulation_order,
            circular_buffer_bits, filler_llr,
        )
        for value in recovered:
            result.append(value)
    return result^


def nr_ldpc_decode_code_blocks(
    recovered_llrs: Span[Float64, ...], encoded_null_mask: Span[UInt8, ...],
    profile: NRLDPCProfile, *, max_iterations: Int = 20,
    normalization: Float64 = 0.75, offset: Float64 = 0.0,
    clip: Float64 = 50.0,
) raises -> NRLDPCDecodedBlocks:
    """Decode every rate-recovered block and concatenate encoder inputs."""
    var expected = profile.code_blocks * profile.encoded_bits
    if len(recovered_llrs) != expected or len(encoded_null_mask) != expected:
        raise Error("flattened decoder inputs have invalid dimensions")
    var bits = List[UInt8](
        capacity=profile.code_blocks * profile.encoder_input_bits
    )
    var iterations = List[Int](capacity=profile.code_blocks)
    var all_converged = True
    for block in range(profile.code_blocks):
        var llrs = List[Float64](capacity=profile.encoded_bits)
        var nulls = List[UInt8](capacity=profile.encoded_bits)
        var source = block * profile.encoded_bits
        for i in range(profile.encoded_bits):
            llrs.append(recovered_llrs[source + i])
            nulls.append(encoded_null_mask[source + i])
        var decoded = nr_ldpc_decode(
            Span(llrs), Span(nulls), profile.base_graph,
            profile.lifting_size, max_iterations=max_iterations,
            normalization=normalization, offset=offset, clip=clip,
        )
        for value in decoded.bits:
            bits.append(value)
        iterations.append(decoded.iterations)
        all_converged = all_converged and decoded.converged
    return NRLDPCDecodedBlocks(
        bits^, iterations^, all_converged,
        profile.code_blocks, profile.encoder_input_bits,
    )
