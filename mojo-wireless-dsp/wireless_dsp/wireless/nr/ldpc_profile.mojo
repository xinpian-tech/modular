"""3GPP TS 38.212 NR LDPC selection, segmentation, and QC expansion."""

from std.collections import Span
from std.math import isfinite
from .ldpc_tables import (
    nr_base_graph_edges,
    nr_lifting_set_index,
)


struct NRLDPCProfile(Movable):
    var base_graph: Int
    var code_blocks: Int
    var code_block_crc_bits: Int
    var lifting_size: Int
    var information_columns: Int
    var code_block_bits: Int
    var transport_crc_bits: Int
    var transport_block_bits: Int
    var segmented_bits: Int
    var code_block_payload_bits: Int
    var code_block_data_bits: Int
    var filler_bits: Int
    var encoder_input_bits: Int
    var encoded_bits: Int
    var lifting_set_index: Int

    def __init__(
        out self, base_graph: Int, code_blocks: Int, code_block_crc_bits: Int,
        lifting_size: Int, information_columns: Int, code_block_bits: Int,
        transport_crc_bits: Int, transport_block_bits: Int,
        segmented_bits: Int, code_block_payload_bits: Int,
        code_block_data_bits: Int, filler_bits: Int,
        encoder_input_bits: Int, encoded_bits: Int,
        lifting_set_index: Int,
    ):
        self.base_graph = base_graph
        self.code_blocks = code_blocks
        self.code_block_crc_bits = code_block_crc_bits
        self.lifting_size = lifting_size
        self.information_columns = information_columns
        self.code_block_bits = code_block_bits
        self.transport_crc_bits = transport_crc_bits
        self.transport_block_bits = transport_block_bits
        self.segmented_bits = segmented_bits
        self.code_block_payload_bits = code_block_payload_bits
        self.code_block_data_bits = code_block_data_bits
        self.filler_bits = filler_bits
        self.encoder_input_bits = encoder_input_bits
        self.encoded_bits = encoded_bits
        self.lifting_set_index = lifting_set_index


struct QCSparseGraph(Movable):
    var row_offsets: List[Int]
    var columns: List[Int]
    var variable_count: Int

    def __init__(
        out self, var row_offsets: List[Int], var columns: List[Int], variable_count: Int
    ):
        self.row_offsets = row_offsets^
        self.columns = columns^
        self.variable_count = variable_count


def nr_select_base_graph(payload_bits: Int, target_code_rate: Float64) raises -> Int:
    """TS 38.212 7.2.2 DL-SCH base graph selection."""
    if (
        payload_bits < 0
        or not isfinite(target_code_rate)
        or target_code_rate <= 0.0
        or target_code_rate > 1.0
    ):
        raise Error("invalid transport block or code rate")
    if payload_bits <= 292 or (payload_bits <= 3824 and target_code_rate <= 0.67) or target_code_rate <= 0.25:
        return 2
    return 1


def _choose_lifting(required: Int) raises -> Int:
    var candidates: List[Int] = [
        2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18,
        20, 22, 24, 26, 28, 30, 32, 36, 40, 44, 48, 52, 56, 60, 64,
        72, 80, 88, 96, 104, 112, 120, 128, 144, 160, 176, 192, 208,
        224, 240, 256, 288, 320, 352, 384,
    ]
    for value in candidates:
        if value >= required:
            return value
    raise Error("NR LDPC lifting requirement exceeds 384")


def nr_ldpc_profile(payload_bits: Int, target_code_rate: Float64) raises -> NRLDPCProfile:
    var base_graph = nr_select_base_graph(payload_bits, target_code_rate)
    var transport_crc = 24 if payload_bits > 3824 else 16
    var b = payload_bits + transport_crc
    var maximum = 8448 if base_graph == 1 else 3840
    var code_blocks = 1
    var code_block_crc = 0
    if b > maximum:
        code_block_crc = 24
        code_blocks = (b + (maximum - code_block_crc) - 1) // (maximum - code_block_crc)
    var b_prime = b + code_blocks * code_block_crc
    var code_block_payload = (b + code_blocks - 1) // code_blocks
    var per_block = (b_prime + code_blocks - 1) // code_blocks
    var information_columns = 22
    if base_graph == 2:
        if b > 640:
            information_columns = 10
        elif b > 560:
            information_columns = 9
        elif b > 192:
            information_columns = 8
        else:
            information_columns = 6
    var lifting = _choose_lifting((per_block + information_columns - 1) // information_columns)
    var encoder_columns = 22 if base_graph == 1 else 10
    var encoder_input = encoder_columns * lifting
    var encoded = (66 if base_graph == 1 else 50) * lifting
    return NRLDPCProfile(
        base_graph, code_blocks, code_block_crc, lifting,
        information_columns, information_columns * lifting,
        transport_crc, b, b_prime, code_block_payload, per_block,
        encoder_input - per_block, encoder_input, encoded,
        nr_lifting_set_index(lifting),
    )


def nr_ldpc_filler_mask(profile: NRLDPCProfile) -> List[UInt8]:
    """Return the TS 38.212 circular-buffer ``<NULL>`` mask for one block."""
    var result = List[UInt8](length=profile.encoded_bits, fill=UInt8(0))
    var punctured = 2 * profile.lifting_size
    for full_index in range(
        profile.code_block_data_bits, profile.encoder_input_bits
    ):
        if full_index >= punctured:
            result[full_index - punctured] = UInt8(1)
    return result^


def nr_qc_expand_edges(
    base_rows: Int, base_columns: Int,
    edge_rows: Span[Int, ...], edge_columns: Span[Int, ...],
    shifts: Span[Int, ...], lifting_size: Int,
) raises -> QCSparseGraph:
    """Expand nonnegative base-graph shifts into a binary QC Tanner graph."""
    if len(edge_rows) != len(edge_columns) or len(shifts) != len(edge_rows):
        raise Error("QC edge arrays must have equal length")
    if base_rows < 1 or base_columns < 1 or nr_lifting_set_index(lifting_size) < 0:
        raise Error("invalid NR QC dimensions or lifting size")
    for edge in range(len(edge_rows)):
        if edge_rows[edge] < 0 or edge_rows[edge] >= base_rows:
            raise Error("QC base row out of range")
        if edge_columns[edge] < 0 or edge_columns[edge] >= base_columns:
            raise Error("QC base column out of range")
        if shifts[edge] < 0:
            raise Error("QC shift must be non-negative")
    var row_offsets = List[Int](capacity=base_rows * lifting_size + 1)
    var columns = List[Int]()
    row_offsets.append(0)
    for base_row in range(base_rows):
        for lifted_row in range(lifting_size):
            for edge in range(len(edge_rows)):
                if edge_rows[edge] == base_row:
                    var lifted_column = (
                        edge_columns[edge] * lifting_size
                        + (lifted_row + shifts[edge]) % lifting_size
                    )
                    columns.append(lifted_column)
            row_offsets.append(len(columns))
    return QCSparseGraph(row_offsets^, columns^, base_columns * lifting_size)


def nr_standard_qc_graph(base_graph: Int, lifting_size: Int) raises -> QCSparseGraph:
    """Expand the complete standardized BG1/BG2 parity-check matrix."""
    var edges = nr_base_graph_edges(base_graph, lifting_size)
    return nr_qc_expand_edges(
        edges.base_rows,
        edges.base_columns,
        Span(edges.edge_rows),
        Span(edges.edge_columns),
        Span(edges.shifts),
        lifting_size,
    )
