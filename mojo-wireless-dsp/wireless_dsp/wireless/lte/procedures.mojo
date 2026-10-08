"""Bounded LTE physical-layer procedures from 3GPP TS 36.213 V18.3.0.

The complete base PDSCH and PUSCH MCS rows are represented, including the
reserved retransmission rows and redundancy-version mappings.  Resource
allocation covers logical type-0 downlink RBG selection and contiguous uplink
RIV encoding/decoding.  The traditional base transport-block-size lookup is
complete for ``I_TBS=0..26/26A`` and ``N_PRB=1..110``.  The larger current
44-row table extends through numeric index 37 and named rows 32A, 33A, 33B,
34A, and 37A; those later rows remain outside this bounded base profile.
Alternate
256/1024-QAM tables, BL/CE procedures, TDD timing, DCI parsing, and scheduling
state machines are also out of scope.
"""


comptime LTE_BASE_TBS_INDEX_MIN = 0
comptime LTE_BASE_TBS_INDEX_MAX = 26
comptime LTE_COMPLETE_TBS_NUMERIC_INDEX_MAX = 37
comptime LTE_BASE_TBS_RESOURCE_BLOCK_MIN = 1
comptime LTE_BASE_TBS_RESOURCE_BLOCK_MAX = 110


struct LTEDownlinkMCSProfile(ImplicitlyCopyable):
    """One non-reserved row of TS 36.213 Table 7.1.7.1-1."""

    var index: Int
    var modulation_order: Int
    var second_slot_modulation_order: Int
    var tbs_index: Int
    var tbs_index_26a_possible: Bool

    def __init__(
        out self,
        index: Int,
        modulation_order: Int,
        second_slot_modulation_order: Int,
        tbs_index: Int,
        tbs_index_26a_possible: Bool,
    ) raises:
        var rows = _lte_downlink_mcs_rows()
        if index < 0 or index >= len(rows[0]):
            raise Error("LTE base downlink MCS index is reserved")
        if (
            modulation_order != rows[0][index]
            or second_slot_modulation_order != rows[1][index]
            or tbs_index != rows[2][index]
            or tbs_index_26a_possible != (index == 28)
        ):
            raise Error("LTE downlink MCS profile does not match the base table")
        self.index = index
        self.modulation_order = modulation_order
        self.second_slot_modulation_order = second_slot_modulation_order
        self.tbs_index = tbs_index
        self.tbs_index_26a_possible = tbs_index_26a_possible

    def validate(self) raises:
        _ = LTEDownlinkMCSProfile(
            self.index,
            self.modulation_order,
            self.second_slot_modulation_order,
            self.tbs_index,
            self.tbs_index_26a_possible,
        )


def _lte_downlink_mcs_rows() -> Tuple[List[Int], List[Int], List[Int]]:
    # Q_m, Q'_m, and the integer part of I_TBS (row 28 is 26/26A).
    return (
        [
            2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
            4, 4, 4, 4, 4, 4, 4,
            6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
        ],
        [
            2, 2, 2, 2, 2,
            4, 4, 4, 4, 4,
            6, 6, 6, 6, 6, 6, 6,
            6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
        ],
        [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            9, 10, 11, 12, 13, 14, 15,
            15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26,
        ],
    )


def lte_downlink_mcs_profile(index: Int) raises -> LTEDownlinkMCSProfile:
    """Look up a complete non-reserved row of base Table 7.1.7.1-1."""
    var rows = _lte_downlink_mcs_rows()
    if index < 0 or index >= len(rows[0]):
        raise Error("LTE base downlink MCS index is reserved")
    var modulation_order = rows[0][index]
    var second_slot_modulation_order = rows[1][index]
    var tbs_index = rows[2][index]
    return LTEDownlinkMCSProfile(
        index,
        modulation_order,
        second_slot_modulation_order,
        tbs_index,
        index == 28,
    )


struct LTEDownlinkMCSEntry(ImplicitlyCopyable):
    """Any base DL table row, including RV-only/reuse rows 29--31.

    A false ``has_new_transport_format`` uses ``tbs_index=-1`` while retaining
    the normative Q_m and Q'_m values that select retransmission modulation.
    """

    var index: Int
    var has_new_transport_format: Bool
    var modulation_order: Int
    var second_slot_modulation_order: Int
    var tbs_index: Int
    var tbs_index_26a_possible: Bool

    def __init__(
        out self,
        index: Int,
        has_new_transport_format: Bool,
        modulation_order: Int,
        second_slot_modulation_order: Int,
        tbs_index: Int,
        tbs_index_26a_possible: Bool,
    ) raises:
        if index < 0 or index > 31:
            raise Error("LTE base downlink MCS index must be in [0,31]")
        var expected_has_format = index <= 28
        var expected_modulation = (
            2 if index == 29 else 4 if index == 30 else 6
        )
        var expected_second_slot_modulation = expected_modulation
        var expected_tbs_index = -1
        if expected_has_format:
            var profile = lte_downlink_mcs_profile(index)
            expected_modulation = profile.modulation_order
            expected_second_slot_modulation = (
                profile.second_slot_modulation_order
            )
            expected_tbs_index = profile.tbs_index
        if (
            has_new_transport_format != expected_has_format
            or modulation_order != expected_modulation
            or second_slot_modulation_order
            != expected_second_slot_modulation
            or tbs_index != expected_tbs_index
            or tbs_index_26a_possible != (index == 28)
        ):
            raise Error("LTE downlink MCS entry does not match the base table")
        self.index = index
        self.has_new_transport_format = has_new_transport_format
        self.modulation_order = modulation_order
        self.second_slot_modulation_order = second_slot_modulation_order
        self.tbs_index = tbs_index
        self.tbs_index_26a_possible = tbs_index_26a_possible

    def validate(self) raises:
        _ = LTEDownlinkMCSEntry(
            self.index,
            self.has_new_transport_format,
            self.modulation_order,
            self.second_slot_modulation_order,
            self.tbs_index,
            self.tbs_index_26a_possible,
        )


def lte_downlink_mcs_entry(index: Int) raises -> LTEDownlinkMCSEntry:
    """Look up any of the 32 base PDSCH MCS table rows."""
    if index < 0 or index > 31:
        raise Error("LTE base downlink MCS index must be in [0,31]")
    if index <= 28:
        var profile = lte_downlink_mcs_profile(index)
        return LTEDownlinkMCSEntry(
            index,
            True,
            profile.modulation_order,
            profile.second_slot_modulation_order,
            profile.tbs_index,
            profile.tbs_index_26a_possible,
        )
    var modulation_order = 2 if index == 29 else 4 if index == 30 else 6
    return LTEDownlinkMCSEntry(
        index, False, modulation_order, modulation_order, -1, False
    )


def lte_downlink_redundancy_version(rv_value: Int) raises -> Int:
    """Map Table 7.1.7.1-2's logical ``rv`` value to ``rv_idx``."""
    if rv_value == 0:
        return 0
    if rv_value == 1:
        return 2
    if rv_value == 2:
        return 3
    if rv_value == 3:
        return 1
    raise Error("LTE downlink redundancy-version value must be in [0,3]")


struct LTEUplinkMCSEntry(ImplicitlyCopyable):
    """One row of base Table 8.6.1-1, including RV-only rows 29--31.

    ``has_new_transport_format`` is false for rows 29--31.  Their modulation
    order and TBS index are represented as zero and -1 respectively, while the
    normative redundancy-version index remains available.
    """

    var index: Int
    var has_new_transport_format: Bool
    var modulation_order: Int
    var tbs_index: Int
    var redundancy_version: Int

    def __init__(
        out self,
        index: Int,
        has_new_transport_format: Bool,
        modulation_order: Int,
        tbs_index: Int,
        redundancy_version: Int,
    ) raises:
        if index < 0 or index > 31:
            raise Error("LTE base uplink MCS index must be in [0,31]")
        var expected_has_format = index <= 28
        var expected_modulation = _lte_uplink_modulation_order(index)
        var expected_tbs = _lte_uplink_tbs_index(index)
        var expected_rv = 0 if index <= 28 else index - 28
        if (
            has_new_transport_format != expected_has_format
            or modulation_order != expected_modulation
            or tbs_index != expected_tbs
            or redundancy_version != expected_rv
        ):
            raise Error("LTE uplink MCS entry does not match the base table")
        self.index = index
        self.has_new_transport_format = has_new_transport_format
        self.modulation_order = modulation_order
        self.tbs_index = tbs_index
        self.redundancy_version = redundancy_version

    def validate(self) raises:
        _ = LTEUplinkMCSEntry(
            self.index,
            self.has_new_transport_format,
            self.modulation_order,
            self.tbs_index,
            self.redundancy_version,
        )


def _lte_uplink_modulation_order(index: Int) -> Int:
    if index <= 10:
        return 2
    if index <= 20:
        return 4
    if index <= 28:
        return 6
    return 0


def _lte_uplink_tbs_index(index: Int) -> Int:
    if index <= 10:
        return index
    if index <= 20:
        return index - 1
    if index <= 28:
        return index - 2
    return -1


def lte_uplink_mcs_entry(index: Int) raises -> LTEUplinkMCSEntry:
    """Look up any of the 32 base PUSCH MCS/RV table rows."""
    if index < 0 or index > 31:
        raise Error("LTE base uplink MCS index must be in [0,31]")
    return LTEUplinkMCSEntry(
        index,
        index <= 28,
        _lte_uplink_modulation_order(index),
        _lte_uplink_tbs_index(index),
        0 if index <= 28 else index - 28,
    )


def _lte_base_tbs_row(table_row: Int) raises -> List[Int]:
    # Literal transcription of 3GPP TS 36.213 V18.3.0, Table 7.1.7.2.1-1,
    # rows 0..26 and named row 26A.  Official frozen archive:
    # https://www.3gpp.org/ftp/Specs/archive/36_series/36.213/36213-i30.zip
    if table_row == 0:
        return [
            16, 32, 56, 88, 120, 152, 176, 208, 224, 256,
            288, 328, 344, 376, 392, 424, 456, 488, 504, 536,
            568, 600, 616, 648, 680, 712, 744, 776, 776, 808,
            840, 872, 904, 936, 968, 1000, 1032, 1032, 1064, 1096,
            1128, 1160, 1192, 1224, 1256, 1256, 1288, 1320, 1352, 1384,
            1416, 1416, 1480, 1480, 1544, 1544, 1608, 1608, 1608, 1672,
            1672, 1736, 1736, 1800, 1800, 1800, 1864, 1864, 1928, 1928,
            1992, 1992, 2024, 2088, 2088, 2088, 2152, 2152, 2216, 2216,
            2280, 2280, 2280, 2344, 2344, 2408, 2408, 2472, 2472, 2536,
            2536, 2536, 2600, 2600, 2664, 2664, 2728, 2728, 2728, 2792,
            2792, 2856, 2856, 2856, 2984, 2984, 2984, 2984, 2984, 3112,
        ]
    elif table_row == 1:
        return [
            24, 56, 88, 144, 176, 208, 224, 256, 328, 344,
            376, 424, 456, 488, 520, 568, 600, 632, 680, 712,
            744, 776, 808, 872, 904, 936, 968, 1000, 1032, 1064,
            1128, 1160, 1192, 1224, 1256, 1288, 1352, 1384, 1416, 1416,
            1480, 1544, 1544, 1608, 1608, 1672, 1736, 1736, 1800, 1800,
            1864, 1864, 1928, 1992, 1992, 2024, 2088, 2088, 2152, 2152,
            2216, 2280, 2280, 2344, 2344, 2408, 2472, 2472, 2536, 2536,
            2600, 2600, 2664, 2728, 2728, 2792, 2792, 2856, 2856, 2856,
            2984, 2984, 2984, 3112, 3112, 3112, 3240, 3240, 3240, 3240,
            3368, 3368, 3368, 3496, 3496, 3496, 3496, 3624, 3624, 3624,
            3752, 3752, 3752, 3752, 3880, 3880, 3880, 4008, 4008, 4008,
        ]
    elif table_row == 2:
        return [
            32, 72, 144, 176, 208, 256, 296, 328, 376, 424,
            472, 520, 568, 616, 648, 696, 744, 776, 840, 872,
            936, 968, 1000, 1064, 1096, 1160, 1192, 1256, 1288, 1320,
            1384, 1416, 1480, 1544, 1544, 1608, 1672, 1672, 1736, 1800,
            1800, 1864, 1928, 1992, 2024, 2088, 2088, 2152, 2216, 2216,
            2280, 2344, 2344, 2408, 2472, 2536, 2536, 2600, 2664, 2664,
            2728, 2792, 2856, 2856, 2856, 2984, 2984, 3112, 3112, 3112,
            3240, 3240, 3240, 3368, 3368, 3368, 3496, 3496, 3496, 3624,
            3624, 3624, 3752, 3752, 3880, 3880, 3880, 4008, 4008, 4008,
            4136, 4136, 4136, 4264, 4264, 4264, 4392, 4392, 4392, 4584,
            4584, 4584, 4584, 4584, 4776, 4776, 4776, 4776, 4968, 4968,
        ]
    elif table_row == 3:
        return [
            40, 104, 176, 208, 256, 328, 392, 440, 504, 568,
            616, 680, 744, 808, 872, 904, 968, 1032, 1096, 1160,
            1224, 1256, 1320, 1384, 1416, 1480, 1544, 1608, 1672, 1736,
            1800, 1864, 1928, 1992, 2024, 2088, 2152, 2216, 2280, 2344,
            2408, 2472, 2536, 2536, 2600, 2664, 2728, 2792, 2856, 2856,
            2984, 2984, 3112, 3112, 3240, 3240, 3368, 3368, 3496, 3496,
            3624, 3624, 3624, 3752, 3752, 3880, 3880, 4008, 4008, 4136,
            4136, 4264, 4264, 4392, 4392, 4392, 4584, 4584, 4584, 4776,
            4776, 4776, 4776, 4968, 4968, 4968, 5160, 5160, 5160, 5352,
            5352, 5352, 5352, 5544, 5544, 5544, 5736, 5736, 5736, 5736,
            5992, 5992, 5992, 5992, 6200, 6200, 6200, 6200, 6456, 6456,
        ]
    elif table_row == 4:
        return [
            56, 120, 208, 256, 328, 408, 488, 552, 632, 696,
            776, 840, 904, 1000, 1064, 1128, 1192, 1288, 1352, 1416,
            1480, 1544, 1608, 1736, 1800, 1864, 1928, 1992, 2088, 2152,
            2216, 2280, 2344, 2408, 2472, 2600, 2664, 2728, 2792, 2856,
            2984, 2984, 3112, 3112, 3240, 3240, 3368, 3496, 3496, 3624,
            3624, 3752, 3752, 3880, 4008, 4008, 4136, 4136, 4264, 4264,
            4392, 4392, 4584, 4584, 4584, 4776, 4776, 4968, 4968, 4968,
            5160, 5160, 5160, 5352, 5352, 5544, 5544, 5544, 5736, 5736,
            5736, 5992, 5992, 5992, 5992, 6200, 6200, 6200, 6456, 6456,
            6456, 6456, 6712, 6712, 6712, 6968, 6968, 6968, 6968, 7224,
            7224, 7224, 7480, 7480, 7480, 7480, 7736, 7736, 7736, 7992,
        ]
    elif table_row == 5:
        return [
            72, 144, 224, 328, 424, 504, 600, 680, 776, 872,
            968, 1032, 1128, 1224, 1320, 1384, 1480, 1544, 1672, 1736,
            1864, 1928, 2024, 2088, 2216, 2280, 2344, 2472, 2536, 2664,
            2728, 2792, 2856, 2984, 3112, 3112, 3240, 3368, 3496, 3496,
            3624, 3752, 3752, 3880, 4008, 4008, 4136, 4264, 4392, 4392,
            4584, 4584, 4776, 4776, 4776, 4968, 4968, 5160, 5160, 5352,
            5352, 5544, 5544, 5736, 5736, 5736, 5992, 5992, 5992, 6200,
            6200, 6200, 6456, 6456, 6712, 6712, 6712, 6968, 6968, 6968,
            7224, 7224, 7224, 7480, 7480, 7480, 7736, 7736, 7736, 7992,
            7992, 7992, 8248, 8248, 8248, 8504, 8504, 8760, 8760, 8760,
            8760, 9144, 9144, 9144, 9144, 9528, 9528, 9528, 9528, 9528,
        ]
    elif table_row == 6:
        return [
            328, 176, 256, 392, 504, 600, 712, 808, 936, 1032,
            1128, 1224, 1352, 1480, 1544, 1672, 1736, 1864, 1992, 2088,
            2216, 2280, 2408, 2472, 2600, 2728, 2792, 2984, 2984, 3112,
            3240, 3368, 3496, 3496, 3624, 3752, 3880, 4008, 4136, 4136,
            4264, 4392, 4584, 4584, 4776, 4776, 4968, 4968, 5160, 5160,
            5352, 5352, 5544, 5736, 5736, 5992, 5992, 5992, 6200, 6200,
            6456, 6456, 6456, 6712, 6712, 6968, 6968, 6968, 7224, 7224,
            7480, 7480, 7736, 7736, 7736, 7992, 7992, 8248, 8248, 8248,
            8504, 8504, 8760, 8760, 8760, 9144, 9144, 9144, 9144, 9528,
            9528, 9528, 9528, 9912, 9912, 9912, 10296, 10296, 10296, 10296,
            10680, 10680, 10680, 10680, 11064, 11064, 11064, 11448, 11448, 11448,
        ]
    elif table_row == 7:
        return [
            104, 224, 328, 472, 584, 712, 840, 968, 1096, 1224,
            1320, 1480, 1608, 1672, 1800, 1928, 2088, 2216, 2344, 2472,
            2536, 2664, 2792, 2984, 3112, 3240, 3368, 3368, 3496, 3624,
            3752, 3880, 4008, 4136, 4264, 4392, 4584, 4584, 4776, 4968,
            4968, 5160, 5352, 5352, 5544, 5736, 5736, 5992, 5992, 6200,
            6200, 6456, 6456, 6712, 6712, 6712, 6968, 6968, 7224, 7224,
            7480, 7480, 7736, 7736, 7992, 7992, 8248, 8248, 8504, 8504,
            8760, 8760, 8760, 9144, 9144, 9144, 9528, 9528, 9528, 9912,
            9912, 9912, 10296, 10296, 10296, 10680, 10680, 10680, 11064, 11064,
            11064, 11448, 11448, 11448, 11448, 11832, 11832, 11832, 12216, 12216,
            12216, 12576, 12576, 12576, 12960, 12960, 12960, 12960, 13536, 13536,
        ]
    elif table_row == 8:
        return [
            120, 256, 392, 536, 680, 808, 968, 1096, 1256, 1384,
            1544, 1672, 1800, 1928, 2088, 2216, 2344, 2536, 2664, 2792,
            2984, 3112, 3240, 3368, 3496, 3624, 3752, 3880, 4008, 4264,
            4392, 4584, 4584, 4776, 4968, 4968, 5160, 5352, 5544, 5544,
            5736, 5992, 5992, 6200, 6200, 6456, 6456, 6712, 6968, 6968,
            7224, 7224, 7480, 7480, 7736, 7736, 7992, 7992, 8248, 8504,
            8504, 8760, 8760, 9144, 9144, 9144, 9528, 9528, 9528, 9912,
            9912, 9912, 10296, 10296, 10680, 10680, 10680, 11064, 11064, 11064,
            11448, 11448, 11448, 11832, 11832, 12216, 12216, 12216, 12576, 12576,
            12576, 12960, 12960, 12960, 13536, 13536, 13536, 13536, 14112, 14112,
            14112, 14112, 14688, 14688, 14688, 14688, 15264, 15264, 15264, 15264,
        ]
    elif table_row == 9:
        return [
            136, 296, 456, 616, 776, 936, 1096, 1256, 1416, 1544,
            1736, 1864, 2024, 2216, 2344, 2536, 2664, 2856, 2984, 3112,
            3368, 3496, 3624, 3752, 4008, 4136, 4264, 4392, 4584, 4776,
            4968, 5160, 5160, 5352, 5544, 5736, 5736, 5992, 6200, 6200,
            6456, 6712, 6712, 6968, 6968, 7224, 7480, 7480, 7736, 7992,
            7992, 8248, 8248, 8504, 8760, 8760, 9144, 9144, 9144, 9528,
            9528, 9912, 9912, 10296, 10296, 10296, 10680, 10680, 11064, 11064,
            11064, 11448, 11448, 11832, 11832, 11832, 12216, 12216, 12576, 12576,
            12960, 12960, 12960, 13536, 13536, 13536, 13536, 14112, 14112, 14112,
            14112, 14688, 14688, 14688, 15264, 15264, 15264, 15264, 15840, 15840,
            15840, 16416, 16416, 16416, 16416, 16992, 16992, 16992, 16992, 17568,
        ]
    elif table_row == 10:
        return [
            144, 328, 504, 680, 872, 1032, 1224, 1384, 1544, 1736,
            1928, 2088, 2280, 2472, 2664, 2792, 2984, 3112, 3368, 3496,
            3752, 3880, 4008, 4264, 4392, 4584, 4776, 4968, 5160, 5352,
            5544, 5736, 5736, 5992, 6200, 6200, 6456, 6712, 6712, 6968,
            7224, 7480, 7480, 7736, 7992, 7992, 8248, 8504, 8504, 8760,
            9144, 9144, 9144, 9528, 9528, 9912, 9912, 10296, 10296, 10680,
            10680, 11064, 11064, 11448, 11448, 11448, 11832, 11832, 12216, 12216,
            12576, 12576, 12960, 12960, 12960, 13536, 13536, 13536, 14112, 14112,
            14112, 14688, 14688, 14688, 14688, 15264, 15264, 15264, 15840, 15840,
            15840, 16416, 16416, 16416, 16992, 16992, 16992, 16992, 17568, 17568,
            17568, 18336, 18336, 18336, 18336, 18336, 19080, 19080, 19080, 19080,
        ]
    elif table_row == 11:
        return [
            176, 376, 584, 776, 1000, 1192, 1384, 1608, 1800, 2024,
            2216, 2408, 2600, 2792, 2984, 3240, 3496, 3624, 3880, 4008,
            4264, 4392, 4584, 4776, 4968, 5352, 5544, 5736, 5992, 5992,
            6200, 6456, 6712, 6968, 6968, 7224, 7480, 7736, 7736, 7992,
            8248, 8504, 8760, 8760, 9144, 9144, 9528, 9528, 9912, 9912,
            10296, 10680, 10680, 11064, 11064, 11448, 11448, 11832, 11832, 12216,
            12216, 12576, 12576, 12960, 12960, 13536, 13536, 13536, 14112, 14112,
            14112, 14688, 14688, 14688, 15264, 15264, 15840, 15840, 15840, 16416,
            16416, 16416, 16992, 16992, 16992, 17568, 17568, 17568, 18336, 18336,
            18336, 18336, 19080, 19080, 19080, 19080, 19848, 19848, 19848, 19848,
            20616, 20616, 20616, 21384, 21384, 21384, 21384, 22152, 22152, 22152,
        ]
    elif table_row == 12:
        return [
            208, 440, 680, 904, 1128, 1352, 1608, 1800, 2024, 2280,
            2472, 2728, 2984, 3240, 3368, 3624, 3880, 4136, 4392, 4584,
            4776, 4968, 5352, 5544, 5736, 5992, 6200, 6456, 6712, 6712,
            6968, 7224, 7480, 7736, 7992, 8248, 8504, 8760, 8760, 9144,
            9528, 9528, 9912, 9912, 10296, 10680, 10680, 11064, 11064, 11448,
            11832, 11832, 12216, 12216, 12576, 12576, 12960, 12960, 13536, 13536,
            14112, 14112, 14112, 14688, 14688, 15264, 15264, 15264, 15840, 15840,
            16416, 16416, 16416, 16992, 16992, 17568, 17568, 17568, 18336, 18336,
            18336, 19080, 19080, 19080, 19080, 19848, 19848, 19848, 20616, 20616,
            20616, 21384, 21384, 21384, 21384, 22152, 22152, 22152, 22920, 22920,
            22920, 23688, 23688, 23688, 23688, 24496, 24496, 24496, 24496, 25456,
        ]
    elif table_row == 13:
        return [
            224, 488, 744, 1000, 1256, 1544, 1800, 2024, 2280, 2536,
            2856, 3112, 3368, 3624, 3880, 4136, 4392, 4584, 4968, 5160,
            5352, 5736, 5992, 6200, 6456, 6712, 6968, 7224, 7480, 7736,
            7992, 8248, 8504, 8760, 9144, 9144, 9528, 9912, 9912, 10296,
            10680, 10680, 11064, 11448, 11448, 11832, 12216, 12216, 12576, 12960,
            12960, 13536, 13536, 14112, 14112, 14688, 14688, 14688, 15264, 15264,
            15840, 15840, 16416, 16416, 16992, 16992, 16992, 17568, 17568, 18336,
            18336, 18336, 19080, 19080, 19080, 19848, 19848, 19848, 20616, 20616,
            20616, 21384, 21384, 21384, 22152, 22152, 22152, 22920, 22920, 22920,
            23688, 23688, 23688, 24496, 24496, 24496, 25456, 25456, 25456, 25456,
            26416, 26416, 26416, 26416, 27376, 27376, 27376, 27376, 28336, 28336,
        ]
    elif table_row == 14:
        return [
            256, 552, 840, 1128, 1416, 1736, 1992, 2280, 2600, 2856,
            3112, 3496, 3752, 4008, 4264, 4584, 4968, 5160, 5544, 5736,
            5992, 6200, 6456, 6968, 7224, 7480, 7736, 7992, 8248, 8504,
            8760, 9144, 9528, 9912, 9912, 10296, 10680, 11064, 11064, 11448,
            11832, 12216, 12216, 12576, 12960, 12960, 13536, 13536, 14112, 14112,
            14688, 14688, 15264, 15264, 15840, 15840, 16416, 16416, 16992, 16992,
            17568, 17568, 18336, 18336, 18336, 19080, 19080, 19848, 19848, 19848,
            20616, 20616, 20616, 21384, 21384, 22152, 22152, 22152, 22920, 22920,
            22920, 23688, 23688, 24496, 24496, 24496, 25456, 25456, 25456, 25456,
            26416, 26416, 26416, 27376, 27376, 27376, 28336, 28336, 28336, 28336,
            29296, 29296, 29296, 29296, 30576, 30576, 30576, 30576, 31704, 31704,
        ]
    elif table_row == 15:
        return [
            280, 600, 904, 1224, 1544, 1800, 2152, 2472, 2728, 3112,
            3368, 3624, 4008, 4264, 4584, 4968, 5160, 5544, 5736, 6200,
            6456, 6712, 6968, 7224, 7736, 7992, 8248, 8504, 8760, 9144,
            9528, 9912, 10296, 10296, 10680, 11064, 11448, 11832, 11832, 12216,
            12576, 12960, 12960, 13536, 13536, 14112, 14688, 14688, 15264, 15264,
            15840, 15840, 16416, 16416, 16992, 16992, 17568, 17568, 18336, 18336,
            18336, 19080, 19080, 19848, 19848, 20616, 20616, 20616, 21384, 21384,
            22152, 22152, 22152, 22920, 22920, 23688, 23688, 23688, 24496, 24496,
            24496, 25456, 25456, 25456, 26416, 26416, 26416, 27376, 27376, 27376,
            28336, 28336, 28336, 29296, 29296, 29296, 29296, 30576, 30576, 30576,
            30576, 31704, 31704, 31704, 31704, 32856, 32856, 32856, 34008, 34008,
        ]
    elif table_row == 16:
        return [
            328, 632, 968, 1288, 1608, 1928, 2280, 2600, 2984, 3240,
            3624, 3880, 4264, 4584, 4968, 5160, 5544, 5992, 6200, 6456,
            6712, 7224, 7480, 7736, 7992, 8504, 8760, 9144, 9528, 9912,
            9912, 10296, 10680, 11064, 11448, 11832, 12216, 12216, 12576, 12960,
            13536, 13536, 14112, 14112, 14688, 14688, 15264, 15840, 15840, 16416,
            16416, 16992, 16992, 17568, 17568, 18336, 18336, 19080, 19080, 19848,
            19848, 19848, 20616, 20616, 21384, 21384, 22152, 22152, 22152, 22920,
            22920, 23688, 23688, 24496, 24496, 24496, 25456, 25456, 25456, 26416,
            26416, 26416, 27376, 27376, 27376, 28336, 28336, 28336, 29296, 29296,
            29296, 30576, 30576, 30576, 30576, 31704, 31704, 31704, 31704, 32856,
            32856, 32856, 34008, 34008, 34008, 34008, 35160, 35160, 35160, 35160,
        ]
    elif table_row == 17:
        return [
            336, 696, 1064, 1416, 1800, 2152, 2536, 2856, 3240, 3624,
            4008, 4392, 4776, 5160, 5352, 5736, 6200, 6456, 6712, 7224,
            7480, 7992, 8248, 8760, 9144, 9528, 9912, 10296, 10296, 10680,
            11064, 11448, 11832, 12216, 12576, 12960, 13536, 13536, 14112, 14688,
            14688, 15264, 15264, 15840, 16416, 16416, 16992, 17568, 17568, 18336,
            18336, 19080, 19080, 19848, 19848, 20616, 20616, 20616, 21384, 21384,
            22152, 22152, 22920, 22920, 23688, 23688, 24496, 24496, 24496, 25456,
            25456, 26416, 26416, 26416, 27376, 27376, 27376, 28336, 28336, 29296,
            29296, 29296, 30576, 30576, 30576, 30576, 31704, 31704, 31704, 32856,
            32856, 32856, 34008, 34008, 34008, 35160, 35160, 35160, 35160, 36696,
            36696, 36696, 36696, 37888, 37888, 37888, 39232, 39232, 39232, 39232,
        ]
    elif table_row == 18:
        return [
            376, 776, 1160, 1544, 1992, 2344, 2792, 3112, 3624, 4008,
            4392, 4776, 5160, 5544, 5992, 6200, 6712, 7224, 7480, 7992,
            8248, 8760, 9144, 9528, 9912, 10296, 10680, 11064, 11448, 11832,
            12216, 12576, 12960, 13536, 14112, 14112, 14688, 15264, 15264, 15840,
            16416, 16416, 16992, 17568, 17568, 18336, 18336, 19080, 19080, 19848,
            19848, 20616, 21384, 21384, 22152, 22152, 22920, 22920, 23688, 23688,
            24496, 24496, 24496, 25456, 25456, 26416, 26416, 27376, 27376, 27376,
            28336, 28336, 29296, 29296, 29296, 30576, 30576, 30576, 31704, 31704,
            31704, 32856, 32856, 32856, 34008, 34008, 34008, 35160, 35160, 35160,
            36696, 36696, 36696, 37888, 37888, 37888, 37888, 39232, 39232, 39232,
            40576, 40576, 40576, 40576, 42368, 42368, 42368, 42368, 43816, 43816,
        ]
    elif table_row == 19:
        return [
            408, 840, 1288, 1736, 2152, 2600, 2984, 3496, 3880, 4264,
            4776, 5160, 5544, 5992, 6456, 6968, 7224, 7736, 8248, 8504,
            9144, 9528, 9912, 10296, 10680, 11064, 11448, 12216, 12576, 12960,
            13536, 13536, 14112, 14688, 15264, 15264, 15840, 16416, 16992, 16992,
            17568, 18336, 18336, 19080, 19080, 19848, 20616, 20616, 21384, 21384,
            22152, 22152, 22920, 22920, 23688, 24496, 24496, 25456, 25456, 25456,
            26416, 26416, 27376, 27376, 28336, 28336, 29296, 29296, 29296, 30576,
            30576, 30576, 31704, 31704, 32856, 32856, 32856, 34008, 34008, 34008,
            35160, 35160, 35160, 36696, 36696, 36696, 37888, 37888, 37888, 39232,
            39232, 39232, 40576, 40576, 40576, 40576, 42368, 42368, 42368, 43816,
            43816, 43816, 43816, 45352, 45352, 45352, 46888, 46888, 46888, 46888,
        ]
    elif table_row == 20:
        return [
            440, 904, 1384, 1864, 2344, 2792, 3240, 3752, 4136, 4584,
            5160, 5544, 5992, 6456, 6968, 7480, 7992, 8248, 8760, 9144,
            9912, 10296, 10680, 11064, 11448, 12216, 12576, 12960, 13536, 14112,
            14688, 14688, 15264, 15840, 16416, 16992, 16992, 17568, 18336, 18336,
            19080, 19848, 19848, 20616, 20616, 21384, 22152, 22152, 22920, 22920,
            23688, 24496, 24496, 25456, 25456, 26416, 26416, 27376, 27376, 28336,
            28336, 29296, 29296, 29296, 30576, 30576, 31704, 31704, 31704, 32856,
            32856, 34008, 34008, 34008, 35160, 35160, 35160, 36696, 36696, 36696,
            37888, 37888, 39232, 39232, 39232, 40576, 40576, 40576, 42368, 42368,
            42368, 42368, 43816, 43816, 43816, 45352, 45352, 45352, 46888, 46888,
            46888, 46888, 48936, 48936, 48936, 48936, 48936, 51024, 51024, 51024,
        ]
    elif table_row == 21:
        return [
            488, 1000, 1480, 1992, 2472, 2984, 3496, 4008, 4584, 4968,
            5544, 5992, 6456, 6968, 7480, 7992, 8504, 9144, 9528, 9912,
            10680, 11064, 11448, 12216, 12576, 12960, 13536, 14112, 14688, 15264,
            15840, 15840, 16416, 16992, 17568, 18336, 18336, 19080, 19848, 19848,
            20616, 21384, 21384, 22152, 22920, 22920, 23688, 24496, 24496, 25456,
            25456, 26416, 26416, 27376, 27376, 28336, 28336, 29296, 29296, 30576,
            30576, 31704, 31704, 31704, 32856, 32856, 34008, 34008, 35160, 35160,
            35160, 36696, 36696, 36696, 37888, 37888, 39232, 39232, 39232, 40576,
            40576, 40576, 42368, 42368, 42368, 43816, 43816, 43816, 45352, 45352,
            45352, 46888, 46888, 46888, 46888, 48936, 48936, 48936, 48936, 51024,
            51024, 51024, 51024, 52752, 52752, 52752, 52752, 55056, 55056, 55056,
        ]
    elif table_row == 22:
        return [
            520, 1064, 1608, 2152, 2664, 3240, 3752, 4264, 4776, 5352,
            5992, 6456, 6968, 7480, 7992, 8504, 9144, 9528, 10296, 10680,
            11448, 11832, 12576, 12960, 13536, 14112, 14688, 15264, 15840, 16416,
            16992, 16992, 17568, 18336, 19080, 19080, 19848, 20616, 21384, 21384,
            22152, 22920, 22920, 23688, 24496, 24496, 25456, 25456, 26416, 27376,
            27376, 28336, 28336, 29296, 29296, 30576, 30576, 31704, 31704, 32856,
            32856, 34008, 34008, 34008, 35160, 35160, 36696, 36696, 36696, 37888,
            37888, 39232, 39232, 40576, 40576, 40576, 42368, 42368, 42368, 43816,
            43816, 43816, 45352, 45352, 45352, 46888, 46888, 46888, 48936, 48936,
            48936, 48936, 51024, 51024, 51024, 51024, 52752, 52752, 52752, 55056,
            55056, 55056, 55056, 57336, 57336, 57336, 57336, 59256, 59256, 59256,
        ]
    elif table_row == 23:
        return [
            552, 1128, 1736, 2280, 2856, 3496, 4008, 4584, 5160, 5736,
            6200, 6968, 7480, 7992, 8504, 9144, 9912, 10296, 11064, 11448,
            12216, 12576, 12960, 13536, 14112, 14688, 15264, 15840, 16416, 16992,
            17568, 18336, 19080, 19848, 19848, 20616, 21384, 22152, 22152, 22920,
            23688, 24496, 24496, 25456, 25456, 26416, 27376, 27376, 28336, 28336,
            29296, 29296, 30576, 30576, 31704, 31704, 32856, 32856, 34008, 34008,
            35160, 35160, 36696, 36696, 37888, 37888, 37888, 39232, 39232, 40576,
            40576, 40576, 42368, 42368, 43816, 43816, 43816, 45352, 45352, 45352,
            46888, 46888, 46888, 48936, 48936, 48936, 51024, 51024, 51024, 51024,
            52752, 52752, 52752, 55056, 55056, 55056, 55056, 57336, 57336, 57336,
            57336, 59256, 59256, 59256, 59256, 61664, 61664, 61664, 61664, 63776,
        ]
    elif table_row == 24:
        return [
            584, 1192, 1800, 2408, 2984, 3624, 4264, 4968, 5544, 5992,
            6712, 7224, 7992, 8504, 9144, 9912, 10296, 11064, 11448, 12216,
            12960, 13536, 14112, 14688, 15264, 15840, 16416, 16992, 17568, 18336,
            19080, 19848, 19848, 20616, 21384, 22152, 22920, 22920, 23688, 24496,
            25456, 25456, 26416, 26416, 27376, 28336, 28336, 29296, 29296, 30576,
            31704, 31704, 32856, 32856, 34008, 34008, 35160, 35160, 36696, 36696,
            36696, 37888, 37888, 39232, 39232, 40576, 40576, 42368, 42368, 42368,
            43816, 43816, 45352, 45352, 45352, 46888, 46888, 46888, 48936, 48936,
            48936, 51024, 51024, 51024, 52752, 52752, 52752, 52752, 55056, 55056,
            55056, 57336, 57336, 57336, 57336, 59256, 59256, 59256, 61664, 61664,
            61664, 61664, 63776, 63776, 63776, 63776, 66592, 66592, 66592, 66592,
        ]
    elif table_row == 25:
        return [
            616, 1256, 1864, 2536, 3112, 3752, 4392, 5160, 5736, 6200,
            6968, 7480, 8248, 8760, 9528, 10296, 10680, 11448, 12216, 12576,
            13536, 14112, 14688, 15264, 15840, 16416, 16992, 17568, 18336, 19080,
            19848, 20616, 20616, 21384, 22152, 22920, 23688, 24496, 24496, 25456,
            26416, 26416, 27376, 28336, 28336, 29296, 29296, 30576, 31704, 31704,
            32856, 32856, 34008, 34008, 35160, 35160, 36696, 36696, 37888, 37888,
            39232, 39232, 40576, 40576, 40576, 42368, 42368, 43816, 43816, 43816,
            45352, 45352, 46888, 46888, 46888, 48936, 48936, 48936, 51024, 51024,
            51024, 52752, 52752, 52752, 55056, 55056, 55056, 55056, 57336, 57336,
            57336, 59256, 59256, 59256, 61664, 61664, 61664, 61664, 63776, 63776,
            63776, 63776, 66592, 66592, 66592, 66592, 68808, 68808, 68808, 71112,
        ]
    elif table_row == 26:
        return [
            712, 1480, 2216, 2984, 3752, 4392, 5160, 5992, 6712, 7480,
            8248, 8760, 9528, 10296, 11064, 11832, 12576, 13536, 14112, 14688,
            15264, 16416, 16992, 17568, 18336, 19080, 19848, 20616, 21384, 22152,
            22920, 23688, 24496, 25456, 25456, 26416, 27376, 28336, 29296, 29296,
            30576, 30576, 31704, 32856, 32856, 34008, 35160, 35160, 36696, 36696,
            37888, 37888, 39232, 40576, 40576, 40576, 42368, 42368, 43816, 43816,
            45352, 45352, 46888, 46888, 48936, 48936, 48936, 51024, 51024, 52752,
            52752, 52752, 55056, 55056, 55056, 55056, 57336, 57336, 57336, 59256,
            59256, 59256, 61664, 61664, 61664, 63776, 63776, 63776, 66592, 66592,
            66592, 68808, 68808, 68808, 71112, 71112, 71112, 73712, 73712, 75376,
            75376, 75376, 75376, 75376, 75376, 75376, 75376, 75376, 75376, 75376,
        ]
    elif table_row == 27:
        return [
            632, 1288, 1928, 2600, 3240, 3880, 4584, 5160, 5992, 6456,
            7224, 7736, 8504, 9144, 9912, 10296, 11064, 11832, 12576, 12960,
            13536, 14112, 15264, 15840, 16416, 16992, 17568, 18336, 19080, 19848,
            20616, 20616, 21384, 22152, 22920, 23688, 24496, 24496, 25456, 26416,
            26416, 27376, 27376, 29296, 29296, 29296, 30576, 30576, 31704, 32856,
            32856, 34008, 34008, 35160, 36696, 36696, 36696, 37888, 37888, 39232,
            40576, 40576, 40576, 40576, 42368, 42368, 43816, 43816, 45352, 45352,
            45352, 46888, 46888, 48936, 48936, 48936, 51024, 51024, 51024, 52752,
            52752, 52752, 55056, 55056, 55056, 55056, 57336, 57336, 57336, 59256,
            59256, 59256, 59256, 61664, 61664, 61664, 63776, 63776, 63776, 66592,
            66592, 66592, 66592, 68808, 68808, 68808, 71112, 71112, 71112, 71112,
        ]
    raise Error("LTE base TBS table row is out of range")

struct LTETBSTableBounds(ImplicitlyCopyable):
    """Implemented base-table dimensions and larger current-table boundary."""

    var minimum_base_tbs_index: Int
    var maximum_base_numeric_tbs_index: Int
    var base_includes_named_26a: Bool
    var maximum_complete_numeric_tbs_index: Int
    var complete_table_includes_named_alternates: Bool
    var minimum_resource_blocks: Int
    var maximum_resource_blocks: Int
    var base_lookup_implemented: Bool
    var full_lookup_implemented: Bool

    def __init__(out self):
        self.minimum_base_tbs_index = LTE_BASE_TBS_INDEX_MIN
        self.maximum_base_numeric_tbs_index = LTE_BASE_TBS_INDEX_MAX
        self.base_includes_named_26a = True
        self.maximum_complete_numeric_tbs_index = (
            LTE_COMPLETE_TBS_NUMERIC_INDEX_MAX
        )
        self.complete_table_includes_named_alternates = True
        self.minimum_resource_blocks = LTE_BASE_TBS_RESOURCE_BLOCK_MIN
        self.maximum_resource_blocks = LTE_BASE_TBS_RESOURCE_BLOCK_MAX
        self.base_lookup_implemented = True
        self.full_lookup_implemented = False


def lte_base_tbs_table_bounds() -> LTETBSTableBounds:
    """Report the implemented base and explicitly excluded extended boundary."""
    return LTETBSTableBounds()


def lte_base_transport_block_size(
    tbs_index: Int,
    resource_blocks: Int,
    *,
    use_index_26a: Bool = False,
) raises -> Int:
    """Look up base Table 7.1.7.2.1-1 rows 0..26 or named row 26A.

    ``use_index_26a`` is only valid with numeric ``tbs_index=26``.  This keeps
    the named normative row distinct instead of silently inventing an integer
    I_TBS value for it.
    """
    if tbs_index < LTE_BASE_TBS_INDEX_MIN or tbs_index > LTE_BASE_TBS_INDEX_MAX:
        raise Error("LTE base TBS index must be in [0,26]")
    if (
        resource_blocks < LTE_BASE_TBS_RESOURCE_BLOCK_MIN
        or resource_blocks > LTE_BASE_TBS_RESOURCE_BLOCK_MAX
    ):
        raise Error("LTE base TBS lookup requires N_PRB in [1,110]")
    if use_index_26a and tbs_index != 26:
        raise Error("LTE named TBS index 26A can only replace numeric index 26")
    var table_row = 27 if use_index_26a else tbs_index
    var row = _lte_base_tbs_row(table_row)
    return row[resource_blocks - 1]


def lte_downlink_transport_block_size(
    mcs_index: Int,
    resource_blocks: Int,
    *,
    use_index_26a: Bool = False,
) raises -> Int:
    """Compose the base downlink MCS row with the complete base TBS lookup."""
    var profile = lte_downlink_mcs_profile(mcs_index)
    if use_index_26a and not profile.tbs_index_26a_possible:
        raise Error("LTE downlink MCS row cannot select named TBS index 26A")
    return lte_base_transport_block_size(
        profile.tbs_index,
        resource_blocks,
        use_index_26a=use_index_26a,
    )


def lte_downlink_resource_block_group_size(
    downlink_resource_blocks: Int
) raises -> Int:
    """Return type-0 resource-block-group size ``P`` from clause 7.1.6.1."""
    if downlink_resource_blocks < 6 or downlink_resource_blocks > 110:
        raise Error("LTE downlink bandwidth must contain 6 to 110 resource blocks")
    if downlink_resource_blocks <= 10:
        return 1
    if downlink_resource_blocks <= 26:
        return 2
    if downlink_resource_blocks <= 63:
        return 3
    return 4


def lte_downlink_type0_resource_blocks(
    downlink_resource_blocks: Int, logical_rbg_bitmap: UInt32
) raises -> List[Int]:
    """Expand a logical type-0 RBG bitmap into physical RB indices.

    Bit zero denotes logical RBG zero.  This CPU-facing representation avoids
    claiming to parse the MSB-packed DCI wire field.
    """
    var group_size = lte_downlink_resource_block_group_size(
        downlink_resource_blocks
    )
    var group_count = (
        downlink_resource_blocks // group_size
        + (1 if downlink_resource_blocks % group_size != 0 else 0)
    )
    if group_count < 32 and (logical_rbg_bitmap >> UInt32(group_count)) != 0:
        raise Error("LTE type-0 bitmap selects a non-existent resource-block group")
    var result = List[Int]()
    for group in range(group_count):
        if ((logical_rbg_bitmap >> UInt32(group)) & UInt32(1)) == 0:
            continue
        var first_resource_block = group * group_size
        var group_end = min(
            downlink_resource_blocks, first_resource_block + group_size
        )
        for resource_block in range(first_resource_block, group_end):
            result.append(resource_block)
    return result^


struct LTEUplinkContiguousAllocation(ImplicitlyCopyable):
    """One decoded contiguous uplink resource allocation."""

    var uplink_resource_blocks: Int
    var first_resource_block: Int
    var allocated_resource_blocks: Int
    var resource_indication_value: Int

    def __init__(
        out self,
        uplink_resource_blocks: Int,
        first_resource_block: Int,
        allocated_resource_blocks: Int,
        resource_indication_value: Int,
    ) raises:
        if uplink_resource_blocks < 6 or uplink_resource_blocks > 110:
            raise Error("LTE uplink bandwidth must contain 6 to 110 resource blocks")
        if (
            allocated_resource_blocks < 1
            or allocated_resource_blocks > uplink_resource_blocks
            or first_resource_block < 0
            or first_resource_block > uplink_resource_blocks - allocated_resource_blocks
        ):
            raise Error("LTE contiguous uplink allocation is outside the bandwidth")
        var expected_riv = lte_uplink_encode_riv(
            uplink_resource_blocks,
            first_resource_block,
            allocated_resource_blocks,
        )
        if resource_indication_value != expected_riv:
            raise Error("LTE uplink allocation RIV is inconsistent")
        self.uplink_resource_blocks = uplink_resource_blocks
        self.first_resource_block = first_resource_block
        self.allocated_resource_blocks = allocated_resource_blocks
        self.resource_indication_value = resource_indication_value


def lte_uplink_encode_riv(
    uplink_resource_blocks: Int,
    first_resource_block: Int,
    allocated_resource_blocks: Int,
) raises -> Int:
    """Encode the contiguous type-2 uplink allocation of clause 8.1."""
    if uplink_resource_blocks < 6 or uplink_resource_blocks > 110:
        raise Error("LTE uplink bandwidth must contain 6 to 110 resource blocks")
    if (
        allocated_resource_blocks < 1
        or allocated_resource_blocks > uplink_resource_blocks
        or first_resource_block < 0
        or first_resource_block > uplink_resource_blocks - allocated_resource_blocks
    ):
        raise Error("LTE contiguous uplink allocation is outside the bandwidth")
    if allocated_resource_blocks - 1 <= uplink_resource_blocks // 2:
        return (
            uplink_resource_blocks * (allocated_resource_blocks - 1)
            + first_resource_block
        )
    return (
        uplink_resource_blocks
        * (uplink_resource_blocks - allocated_resource_blocks + 1)
        + uplink_resource_blocks
        - 1
        - first_resource_block
    )


def lte_uplink_decode_riv(
    uplink_resource_blocks: Int, resource_indication_value: Int
) raises -> LTEUplinkContiguousAllocation:
    """Decode and canonicalize one contiguous type-2 uplink RIV."""
    if uplink_resource_blocks < 6 or uplink_resource_blocks > 110:
        raise Error("LTE uplink bandwidth must contain 6 to 110 resource blocks")
    if (
        resource_indication_value < 0
        or resource_indication_value >= uplink_resource_blocks * uplink_resource_blocks
    ):
        raise Error("LTE uplink resource indication value is out of range")
    var quotient = resource_indication_value // uplink_resource_blocks
    var remainder = resource_indication_value % uplink_resource_blocks
    var allocated_resource_blocks = quotient + 1
    var first_resource_block = remainder
    if allocated_resource_blocks > uplink_resource_blocks - first_resource_block:
        allocated_resource_blocks = uplink_resource_blocks - quotient + 1
        first_resource_block = uplink_resource_blocks - 1 - remainder
    if (
        allocated_resource_blocks < 1
        or allocated_resource_blocks > uplink_resource_blocks
        or first_resource_block < 0
        or first_resource_block > uplink_resource_blocks - allocated_resource_blocks
    ):
        raise Error("LTE uplink resource indication value is not canonical")
    return LTEUplinkContiguousAllocation(
        uplink_resource_blocks,
        first_resource_block,
        allocated_resource_blocks,
        resource_indication_value,
    )
