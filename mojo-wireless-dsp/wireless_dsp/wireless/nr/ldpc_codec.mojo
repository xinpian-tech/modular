"""TS 38.212 NR LDPC encoding, decoding, and rate matching."""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.fec.ldpc import ldpc_decode_min_sum
from .ldpc_tables import nr_base_graph_edges, nr_base_graph_dimensions
from .ldpc_profile import nr_standard_qc_graph


struct NRLDPCDecodeResult(Movable):
    """Decoded systematic bits and convergence metadata."""

    var bits: List[UInt8]
    var full_bits: List[UInt8]
    var iterations: Int
    var converged: Bool

    def __init__(
        out self,
        var bits: List[UInt8],
        var full_bits: List[UInt8],
        iterations: Int,
        converged: Bool,
    ):
        self.bits = bits^
        self.full_bits = full_bits^
        self.iterations = iterations
        self.converged = converged


def _validate_binary(bits: Span[UInt8, ...]) raises:
    for i in range(len(bits)):
        if bits[i] > 1:
            raise Error("NR LDPC input must contain only zero and one")


def nr_ldpc_encode_full(
    information: Span[UInt8, ...], base_graph: Int, lifting_size: Int
) raises -> List[UInt8]:
    """Encode one block and retain the two systematic nodes later punctured.

    ``information`` has length 22*Zc for BG1 or 10*Zc for BG2. Filler
    positions must be supplied as zero; their ``<NULL>`` status is carried by
    the separate rate-matching mask.
    """
    var edges = nr_base_graph_edges(base_graph, lifting_size)
    var k_nodes = edges.information_columns
    if len(information) != k_nodes * lifting_size:
        raise Error("NR LDPC information length does not match base graph and Zc")
    _validate_binary(information)

    var full = List[UInt8](
        length=edges.base_columns * lifting_size, fill=UInt8(0)
    )
    for i in range(len(information)):
        full[i] = information[i]

    # Sum the systematic contribution of the first four check-node rows.
    var first_four_sum = List[UInt8](length=lifting_size, fill=UInt8(0))
    for edge in range(len(edges.edge_rows)):
        var row = edges.edge_rows[edge]
        var column = edges.edge_columns[edge]
        if row < 4 and column < k_nodes:
            var shift = edges.shifts[edge]
            for bit in range(lifting_size):
                first_four_sum[bit] ^= information[
                    column * lifting_size + (bit + shift) % lifting_size
                ]

    # TS 38.212's dual-diagonal high-rate parity structure. The first parity
    # node is a cyclically shifted sum of those four row contributions.
    var p1_shift = -1
    for edge in range(len(edges.edge_rows)):
        if edges.edge_columns[edge] == k_nodes:
            if edges.edge_rows[edge] == 2:
                p1_shift = edges.shifts[edge]
                break
            if edges.edge_rows[edge] == 1:
                p1_shift = edges.shifts[edge]
    if p1_shift < 0:
        raise Error("invalid NR LDPC high-rate parity submatrix")
    for bit in range(lifting_size):
        full[k_nodes * lifting_size + bit] = first_four_sum[
            (bit + lifting_size - p1_shift) % lifting_size
        ]

    # Solve parity nodes p2, p3, and p4 successively. Their diagonal entries
    # are identity circulants in every standardized base graph.
    for parity in range(3):
        var row = parity
        var output_column = k_nodes + parity + 1
        for bit in range(lifting_size):
            var value = UInt8(0)
            for edge in range(len(edges.edge_rows)):
                var column = edges.edge_columns[edge]
                if edges.edge_rows[edge] == row and column < output_column:
                    value ^= full[
                        column * lifting_size
                        + (bit + edges.shifts[edge]) % lifting_size
                    ]
            full[output_column * lifting_size + bit] = value

    # The extended parity region is lower identity after the first four
    # parity nodes, so every remaining node is obtained independently.
    for row in range(4, edges.base_rows):
        var output_column = k_nodes + row
        for bit in range(lifting_size):
            var value = UInt8(0)
            for edge in range(len(edges.edge_rows)):
                var column = edges.edge_columns[edge]
                if edges.edge_rows[edge] == row and column < k_nodes + 4:
                    value ^= full[
                        column * lifting_size
                        + (bit + edges.shifts[edge]) % lifting_size
                    ]
            full[output_column * lifting_size + bit] = value
    return full^


def nr_ldpc_encode(
    information: Span[UInt8, ...], base_graph: Int, lifting_size: Int
) raises -> List[UInt8]:
    """Encode one NR LDPC block and puncture its first two systematic nodes."""
    var full = nr_ldpc_encode_full(information, base_graph, lifting_size)
    var punctured = 2 * lifting_size
    var result = List[UInt8](capacity=len(full) - punctured)
    for i in range(punctured, len(full)):
        result.append(full[i])
    return result^


def nr_ldpc_syndrome_ok(
    full_codeword: Span[UInt8, ...], base_graph: Int, lifting_size: Int
) raises -> Bool:
    """Evaluate the complete lifted BG1/BG2 parity-check matrix."""
    var edges = nr_base_graph_edges(base_graph, lifting_size)
    if len(full_codeword) != edges.base_columns * lifting_size:
        raise Error("full NR LDPC codeword has invalid length")
    _validate_binary(full_codeword)
    var syndrome = List[UInt8](
        length=edges.base_rows * lifting_size, fill=UInt8(0)
    )
    for edge in range(len(edges.edge_rows)):
        var row = edges.edge_rows[edge]
        var column = edges.edge_columns[edge]
        var shift = edges.shifts[edge]
        for bit in range(lifting_size):
            syndrome[row * lifting_size + bit] ^= full_codeword[
                column * lifting_size + (bit + shift) % lifting_size
            ]
    for i in range(len(syndrome)):
        if syndrome[i] != 0:
            return False
    return True


def nr_ldpc_k0(
    base_graph: Int, lifting_size: Int, redundancy_version: Int,
    circular_buffer_bits: Int = 0,
) raises -> Int:
    """Return the TS 38.212 5.4.2.1 circular-buffer start index."""
    var dimensions = nr_base_graph_dimensions(base_graph)
    var encoded_bits = (dimensions[1] - 2) * lifting_size
    var n_cb = encoded_bits if circular_buffer_bits == 0 else circular_buffer_bits
    if n_cb < 1 or n_cb > encoded_bits:
        raise Error("invalid NR LDPC circular-buffer length")
    if redundancy_version < 0 or redundancy_version > 3:
        raise Error("redundancy version must be in [0, 3]")
    if redundancy_version == 0:
        return 0
    var coefficient: Int
    if base_graph == 1:
        coefficient = [0, 17, 33, 56][redundancy_version]
    else:
        coefficient = [0, 13, 25, 43][redundancy_version]
    return (coefficient * n_cb // encoded_bits) * lifting_size


def nr_ldpc_rate_match(
    encoded: Span[UInt8, ...], null_mask: Span[UInt8, ...],
    base_graph: Int, lifting_size: Int, redundancy_version: Int,
    output_bits: Int, modulation_order: Int,
    circular_buffer_bits: Int = 0,
) raises -> List[UInt8]:
    """Perform circular selection and modulation bit interleaving for one CB."""
    var dimensions = nr_base_graph_dimensions(base_graph)
    var expected = (dimensions[1] - 2) * lifting_size
    if len(encoded) != expected or len(null_mask) != expected:
        raise Error("NR LDPC rate-matching input has invalid length")
    if output_bits < 0 or modulation_order < 1:
        raise Error("invalid NR LDPC rate-matching dimensions")
    if output_bits % modulation_order != 0:
        raise Error("rate-matched length must be divisible by modulation order")
    _validate_binary(encoded)
    _validate_binary(null_mask)
    var n_cb = expected if circular_buffer_bits == 0 else circular_buffer_bits
    var k0 = nr_ldpc_k0(
        base_graph, lifting_size, redundancy_version, n_cb
    )
    var usable = 0
    for i in range(n_cb):
        if null_mask[i] == 0:
            usable += 1
    if output_bits > 0 and usable == 0:
        raise Error("NR LDPC circular buffer contains only filler")

    var selected = List[UInt8](capacity=output_bits)
    var position = k0
    while len(selected) < output_bits:
        if null_mask[position] == 0:
            selected.append(encoded[position])
        position = (position + 1) % n_cb

    var symbols = output_bits // modulation_order
    var interleaved = List[UInt8](capacity=output_bits)
    for symbol in range(symbols):
        for bit_plane in range(modulation_order):
            interleaved.append(selected[bit_plane * symbols + symbol])
    return interleaved^


def nr_ldpc_rate_recover(
    received: Span[Float64, ...], null_mask: Span[UInt8, ...],
    base_graph: Int, lifting_size: Int, redundancy_version: Int,
    modulation_order: Int, circular_buffer_bits: Int = 0,
    filler_llr: Float64 = 50.0,
) raises -> List[Float64]:
    """Undo bit interleaving/selection and combine repeated soft bits."""
    var dimensions = nr_base_graph_dimensions(base_graph)
    var expected = (dimensions[1] - 2) * lifting_size
    if len(null_mask) != expected or modulation_order < 1:
        raise Error("invalid NR LDPC rate-recovery configuration")
    if (
        len(received) % modulation_order != 0
        or not isfinite(filler_llr)
        or filler_llr <= 0.0
    ):
        raise Error("invalid NR LDPC soft-input dimensions")
    _validate_binary(null_mask)
    for i in range(len(received)):
        if not isfinite(received[i]):
            raise Error("NR LDPC received LLRs must be finite")
    var n_cb = expected if circular_buffer_bits == 0 else circular_buffer_bits
    var k0 = nr_ldpc_k0(
        base_graph, lifting_size, redundancy_version, n_cb
    )
    var symbols = len(received) // modulation_order
    var selected = List[Float64](length=len(received), fill=0.0)
    for bit_plane in range(modulation_order):
        for symbol in range(symbols):
            selected[bit_plane * symbols + symbol] = received[
                symbol * modulation_order + bit_plane
            ]

    var result = List[Float64](length=expected, fill=0.0)
    for i in range(n_cb, expected):
        result[i] = 0.0
    var position = k0
    for value in selected:
        var searched = 0
        while null_mask[position] != 0:
            position = (position + 1) % n_cb
            searched += 1
            if searched >= n_cb:
                raise Error("NR LDPC circular buffer contains only filler")
        result[position] += value
        if not isfinite(result[position]):
            raise Error("NR LDPC rate-recovery accumulation must remain finite")
        position = (position + 1) % n_cb
    for i in range(n_cb):
        if null_mask[i] != 0:
            result[i] = filler_llr
    return result^


def nr_ldpc_code_block_output_bits(
    total_output_bits: Int, modulation_order: Int, layers: Int,
    code_blocks: Int, code_block_index: Int,
) raises -> Int:
    """Distribute transport-block output bits across code blocks (5.4.2.1)."""
    if total_output_bits < 0 or modulation_order < 1 or layers < 1:
        raise Error("invalid transport-block rate-matching dimensions")
    if code_blocks < 1 or code_block_index < 0 or code_block_index >= code_blocks:
        raise Error("invalid code-block index")
    if modulation_order > Int.MAX // layers:
        raise Error("Qm times layers overflows Int")
    var quantum = modulation_order * layers
    if total_output_bits % quantum != 0:
        raise Error("total output length must be divisible by Qm times layers")
    var units = total_output_bits // quantum
    var low = units // code_blocks
    var high_blocks = units % code_blocks
    if code_block_index < code_blocks - high_blocks:
        return quantum * low
    return quantum * (low + 1)


def nr_ldpc_decode(
    recovered_llrs: Span[Float64, ...], null_mask: Span[UInt8, ...],
    base_graph: Int, lifting_size: Int, *, max_iterations: Int = 20,
    normalization: Float64 = 0.75, offset: Float64 = 0.0,
    clip: Float64 = 50.0,
) raises -> NRLDPCDecodeResult:
    """Decode one rate-recovered NR code block with normalized min-sum."""
    var dimensions = nr_base_graph_dimensions(base_graph)
    var expected = (dimensions[1] - 2) * lifting_size
    if len(recovered_llrs) != expected or len(null_mask) != expected:
        raise Error("NR LDPC decoder input has invalid length")
    _validate_binary(null_mask)
    if (
        max_iterations < 1
        or not isfinite(normalization)
        or normalization <= 0.0
        or normalization > 1.0
        or not isfinite(offset)
        or offset < 0.0
        or not isfinite(clip)
        or clip <= 0.0
    ):
        raise Error("invalid NR LDPC decoder numeric configuration")
    for i in range(expected):
        if not isfinite(recovered_llrs[i]):
            raise Error("NR LDPC decoder LLRs must be finite")

    var full_llrs = List[Float64](
        length=dimensions[1] * lifting_size, fill=0.0
    )
    var punctured = 2 * lifting_size
    for i in range(expected):
        full_llrs[punctured + i] = (
            clip if null_mask[i] != 0 else recovered_llrs[i]
        )
    var graph = nr_standard_qc_graph(base_graph, lifting_size)
    var decoded = ldpc_decode_min_sum(
        Span(full_llrs), Span(graph.row_offsets), Span(graph.columns),
        max_iterations=max_iterations,
        normalization=normalization,
        offset=offset,
        clip=clip,
    )
    var information_length = dimensions[2] * lifting_size
    var information = List[UInt8](capacity=information_length)
    for i in range(information_length):
        information.append(decoded.bits[i])
    var iterations = decoded.iterations
    var converged = decoded.converged
    var full_bits = decoded.bits.copy()
    return NRLDPCDecodeResult(
        information^, full_bits^, iterations, converged
    )
