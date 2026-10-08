"""3GPP NR MCS tables and exact transport-block-size determination.

The tables and integer algorithm follow 3GPP TS 38.214 V18.10.0
(2026-07), clauses 5.1.3.1 and 5.1.3.2.  Target code rates are stored as
exact integers scaled by 2048, which represents both integer and half-integer
``R x 1024`` entries without binary floating-point ambiguity.  TBS arithmetic
uses positive integer rationals through the quantization decision; no rounded
Float64 spectral-efficiency value controls a transport-block size.

This module selects modulation/rate and TBS.  It does not infer scheduling,
DM-RS overhead, layer count, or PRB allocation from DCI/RRC: callers supply
those already-decoded quantities explicitly.
"""

from std.collections import Span


comptime NR_MCS_TABLE_QAM64 = 1
comptime NR_MCS_TABLE_QAM256 = 2
comptime NR_MCS_TABLE_QAM64_LOW_SE = 3
comptime NR_MCS_TABLE_QAM1024 = 4


struct NRMCSProfile(ImplicitlyCopyable):
    """One non-reserved row of a TS 38.214 PDSCH/PUSCH MCS table."""

    var table: Int
    var index: Int
    var modulation_order: Int
    var target_code_rate_x2048: Int

    def __init__(
        out self,
        table: Int,
        index: Int,
        modulation_order: Int,
        target_code_rate_x2048: Int,
    ) raises:
        if table < NR_MCS_TABLE_QAM64 or table > NR_MCS_TABLE_QAM1024:
            raise Error("NR MCS table identifier is unsupported")
        if index < 0 or index > 31:
            raise Error("NR MCS index must be in [0,31]")
        if (
            modulation_order != 2
            and modulation_order != 4
            and modulation_order != 6
            and modulation_order != 8
            and modulation_order != 10
        ):
            raise Error("NR MCS modulation order is unsupported")
        if target_code_rate_x2048 < 1 or target_code_rate_x2048 > 2048:
            raise Error("NR MCS target code rate must be in (0,1]")
        var rows = _mcs_rows(table)
        if index >= len(rows[0]):
            raise Error("NR MCS index is reserved for the selected table")
        if (
            modulation_order != rows[0][index]
            or target_code_rate_x2048 != rows[1][index]
        ):
            raise Error("NR MCS profile does not match the selected table row")
        self.table = table
        self.index = index
        self.modulation_order = modulation_order
        self.target_code_rate_x2048 = target_code_rate_x2048

    def validate(self) raises:
        _ = NRMCSProfile(
            self.table,
            self.index,
            self.modulation_order,
            self.target_code_rate_x2048,
        )


struct NRTransportBlockAllocation(ImplicitlyCopyable):
    """Auditable intermediate resource and TBS values for one codeword."""

    var resource_elements_per_prb: Int
    var total_resource_elements: Int
    var information_numerator: Int
    var information_denominator: Int
    var transport_block_size: Int

    def __init__(
        out self,
        resource_elements_per_prb: Int,
        total_resource_elements: Int,
        information_numerator: Int,
        information_denominator: Int,
        transport_block_size: Int,
    ) raises:
        if (
            resource_elements_per_prb < 1
            or resource_elements_per_prb > 156
            or total_resource_elements < resource_elements_per_prb
            or information_numerator < 1
            or information_denominator < 1
            or transport_block_size < 24
            or transport_block_size % 8 != 0
        ):
            raise Error("NR transport-block allocation fields are invalid")
        self.resource_elements_per_prb = resource_elements_per_prb
        self.total_resource_elements = total_resource_elements
        self.information_numerator = information_numerator
        self.information_denominator = information_denominator
        self.transport_block_size = transport_block_size


def _mcs_rows(table: Int) raises -> Tuple[List[Int], List[Int]]:
    if table == NR_MCS_TABLE_QAM64:
        return (
            [
                2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
                4, 4, 4, 4, 4, 4, 4,
                6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
            ],
            [
                240, 314, 386, 502, 616, 758, 898, 1052, 1204, 1358,
                680, 756, 868, 980, 1106, 1232, 1316,
                876, 932, 1034, 1134, 1232, 1332, 1438, 1544, 1644,
                1746, 1820, 1896,
            ],
        )
    if table == NR_MCS_TABLE_QAM256:
        return (
            [
                2, 2, 2, 2, 2,
                4, 4, 4, 4, 4, 4,
                6, 6, 6, 6, 6, 6, 6, 6, 6,
                8, 8, 8, 8, 8, 8, 8, 8,
            ],
            [
                240, 386, 616, 898, 1204,
                756, 868, 980, 1106, 1232, 1316,
                932, 1034, 1134, 1232, 1332, 1438, 1544, 1644, 1746,
                1365, 1422, 1508, 1594, 1682, 1770, 1833, 1896,
            ],
        )
    if table == NR_MCS_TABLE_QAM64_LOW_SE:
        return (
            [
                2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
                4, 4, 4, 4, 4, 4,
                6, 6, 6, 6, 6, 6, 6, 6,
            ],
            [
                60, 80, 100, 128, 156, 198, 240, 314, 386, 502, 616,
                758, 898, 1052, 1204,
                680, 756, 868, 980, 1106, 1232,
                876, 932, 1034, 1134, 1232, 1332, 1438, 1544,
            ],
        )
    if table == NR_MCS_TABLE_QAM1024:
        return (
            [
                2, 2, 2,
                4, 4, 4,
                6, 6, 6, 6, 6, 6, 6, 6, 6,
                8, 8, 8, 8, 8, 8, 8, 8,
                10, 10, 10, 10,
            ],
            [
                240, 386, 898,
                756, 980, 1232,
                932, 1034, 1134, 1232, 1332, 1438, 1544, 1644, 1746,
                1365, 1422, 1508, 1594, 1682, 1770, 1833, 1896,
                1611, 1706, 1801, 1896,
            ],
        )
    raise Error("NR MCS table identifier is unsupported")


def nr_mcs_profile(table: Int, index: Int) raises -> NRMCSProfile:
    """Return one exact non-reserved MCS row; reserved indices are rejected."""
    var rows = _mcs_rows(table)
    if index < 0 or index >= len(rows[0]):
        raise Error("NR MCS index is reserved for the selected table")
    var modulation_order = rows[0][index]
    var target_code_rate_x2048 = rows[1][index]
    return NRMCSProfile(
        table, index, modulation_order, target_code_rate_x2048
    )


def nr_mcs_target_code_rate(profile: NRMCSProfile) raises -> Float64:
    """Return ``R`` as a convenience view; exact decisions use x2048."""
    profile.validate()
    return Float64(profile.target_code_rate_x2048) / 2048.0


def nr_mcs_spectral_efficiency(profile: NRMCSProfile) raises -> Float64:
    """Return the exact table product ``Qm * R`` as a Float64 view."""
    profile.validate()
    return (
        Float64(profile.modulation_order)
        * Float64(profile.target_code_rate_x2048)
        / 2048.0
    )


def nr_pdsch_resource_elements_per_prb(
    symbol_count: Int,
    dmrs_re_per_prb: Int,
    overhead_re_per_prb: Int = 0,
) raises -> Int:
    """Compute ``N'_RE`` and apply the TS 38.214 cap of 156 RE/PRB."""
    if symbol_count < 1 or symbol_count > 14:
        raise Error("NR PDSCH symbol count must be in [1,14]")
    if (
        overhead_re_per_prb != 0
        and overhead_re_per_prb != 6
        and overhead_re_per_prb != 12
        and overhead_re_per_prb != 18
    ):
        raise Error("NR PDSCH xOverhead must be 0, 6, 12, or 18")
    if dmrs_re_per_prb < 0:
        raise Error("NR PDSCH DM-RS RE count must be non-negative")
    var available = 12 * symbol_count - dmrs_re_per_prb - overhead_re_per_prb
    if available < 1:
        raise Error("NR PDSCH allocation has no data resource elements")
    return min(156, available)


def _floor_log2_ratio(numerator: Int, denominator: Int) raises -> Int:
    if numerator < 1 or denominator < 1:
        raise Error("positive rational is required for NR TBS logarithm")
    if numerator >= denominator:
        var exponent = 0
        var threshold = denominator
        while threshold <= numerator // 2:
            threshold *= 2
            exponent += 1
        return exponent
    var exponent = -1
    var scaled_numerator = numerator * 2
    while scaled_numerator < denominator:
        scaled_numerator *= 2
        exponent -= 1
    return exponent


def _ceil_div(numerator: Int, denominator: Int) raises -> Int:
    if numerator < 0 or denominator < 1:
        raise Error("invalid non-negative ceiling division")
    return numerator // denominator + (1 if numerator % denominator != 0 else 0)


def _round_ratio_ties_up(numerator: Int, denominator: Int) raises -> Int:
    if numerator < 0 or denominator < 1:
        raise Error("invalid non-negative rounded division")
    var quotient = numerator // denominator
    var remainder = numerator % denominator
    var half_ceiling = denominator // 2 + denominator % 2
    return quotient + (1 if remainder >= half_ceiling else 0)


def _canonical_tb_scaling_denominator(
    numerator: Int, denominator: Int
) raises -> Int:
    """Return the canonical denominator for TS 38.214 Table 5.1.3.2-2."""
    if numerator < 1 or denominator < 1:
        raise Error("NR TBS scaling numerator and denominator must be positive")
    if numerator == denominator:
        return 1
    if denominator % 2 == 0 and numerator == denominator // 2:
        return 2
    if denominator % 4 == 0 and numerator == denominator // 4:
        return 4
    raise Error("NR TBS scaling must be exactly 1, 1/2, or 1/4")


def _small_tbs_values() -> List[Int]:
    return [
        24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 120,
        128, 136, 144, 152, 160, 168, 176, 184, 192, 208, 224, 240,
        256, 272, 288, 304, 320, 336, 352, 368, 384, 408, 432, 456,
        480, 504, 528, 552, 576, 608, 640, 672, 704, 736, 768, 808,
        848, 888, 928, 984, 1032, 1064, 1128, 1160, 1192, 1224,
        1256, 1288, 1320, 1352, 1416, 1480, 1544, 1608, 1672, 1736,
        1800, 1864, 1928, 2024, 2088, 2152, 2216, 2280, 2408, 2472,
        2536, 2600, 2664, 2728, 2792, 2856, 2976, 3104, 3240, 3368,
        3496, 3624, 3752, 3824,
    ]


def _transport_block_size_from_ratio(
    information_numerator: Int,
    information_denominator: Int,
    target_code_rate_x2048: Int,
) raises -> Int:
    if information_numerator < 1 or information_denominator < 1:
        raise Error("NR TBS information-bit rational must be positive")
    if information_numerator <= 3824 * information_denominator:
        var log2_information = _floor_log2_ratio(
            information_numerator, information_denominator
        )
        var exponent = max(3, log2_information - 6)
        var quantum = Int(1) << exponent
        var quantized = quantum * (
            information_numerator // (information_denominator * quantum)
        )
        quantized = max(24, quantized)
        var values = _small_tbs_values()
        for value in values:
            if value >= quantized:
                return value
        raise Error("small NR TBS quantization exceeds the normative table")

    var shifted_numerator = (
        information_numerator - 24 * information_denominator
    )
    var exponent = max(
        0,
        _floor_log2_ratio(shifted_numerator, information_denominator) - 5,
    )
    var quantum = Int(1) << exponent
    var rounded = _round_ratio_ties_up(
        shifted_numerator, information_denominator * quantum
    )
    var quantized = max(3840, quantum * rounded)
    if target_code_rate_x2048 <= 512:
        var code_blocks = _ceil_div(quantized + 24, 3816)
        return (
            8 * code_blocks
            * _ceil_div(quantized + 24, 8 * code_blocks)
            - 24
        )
    if quantized > 8424:
        var code_blocks = _ceil_div(quantized + 24, 8424)
        return (
            8 * code_blocks
            * _ceil_div(quantized + 24, 8 * code_blocks)
            - 24
        )
    return 8 * _ceil_div(quantized + 24, 8) - 24


def nr_transport_block_size(
    total_resource_elements: Int,
    profile: NRMCSProfile,
    layers: Int,
    *,
    tb_scaling_numerator: Int = 1,
    tb_scaling_denominator: Int = 1,
) raises -> Int:
    """Determine one TBS using exact positive rational ``N_info``.

    ``tb_scaling_numerator / tb_scaling_denominator`` is explicit so the
    normative DCI factors 1, 1/2, and 1/4 can be represented without
    Float64.  Equivalent unreduced ratios are accepted and canonicalized.
    """
    profile.validate()
    if total_resource_elements < 1 or total_resource_elements > 275 * 156:
        raise Error("NR total scheduled resource elements are out of range")
    if layers < 1 or layers > 8:
        raise Error("NR transmission layers must be in [1,8]")
    var scaling_denominator = _canonical_tb_scaling_denominator(
        tb_scaling_numerator, tb_scaling_denominator
    )
    var information_numerator = (
        total_resource_elements
        * profile.modulation_order
        * layers
        * profile.target_code_rate_x2048
    )
    var information_denominator = 2048 * scaling_denominator
    return _transport_block_size_from_ratio(
        information_numerator,
        information_denominator,
        profile.target_code_rate_x2048,
    )


def nr_transport_block_allocation(
    scheduled_prbs: Int,
    symbol_count: Int,
    dmrs_re_per_prb: Int,
    overhead_re_per_prb: Int,
    profile: NRMCSProfile,
    layers: Int,
    *,
    tb_scaling_numerator: Int = 1,
    tb_scaling_denominator: Int = 1,
) raises -> NRTransportBlockAllocation:
    """Compose RE accounting, exact ``N_info``, and one-codeword TBS."""
    if scheduled_prbs < 1 or scheduled_prbs > 275:
        raise Error("NR scheduled PRBs must be in [1,275]")
    profile.validate()
    var per_prb = nr_pdsch_resource_elements_per_prb(
        symbol_count, dmrs_re_per_prb, overhead_re_per_prb
    )
    var total = per_prb * scheduled_prbs
    if layers < 1 or layers > 8:
        raise Error("NR transmission layers must be in [1,8]")
    var scaling_denominator = _canonical_tb_scaling_denominator(
        tb_scaling_numerator, tb_scaling_denominator
    )
    var numerator = (
        total
        * profile.modulation_order
        * layers
        * profile.target_code_rate_x2048
    )
    var denominator = 2048 * scaling_denominator
    return NRTransportBlockAllocation(
        per_prb,
        total,
        numerator,
        denominator,
        _transport_block_size_from_ratio(
            numerator, denominator, profile.target_code_rate_x2048
        ),
    )
