"""Deterministic non-grouped NR PDCCH monitoring arithmetic.

This bounded module implements the periodicity, offset, and duration portion
of 3GPP TS 38.213 V18.8.0 clause 10.1.  The legal decoded configuration is
the base ``SearchSpace.monitoringSlotPeriodicityAndOffset`` CHOICE and
``duration`` field from 3GPP TS 38.331 V18.10.0 clause 6.3.2.

The base ``monitoringSymbolsWithinSlot`` bit string and CORESET-duration
admissibility are also implemented for ordinary, non-grouped search spaces.
``monitoringSlotsWithinSlotGroup-r17``,
``monitoringSlotPeriodicityAndOffset-v1710``, ``duration-r17``, DCI-format
2_0/IAB special interpretations, grouped monitoring, and cross-search-space
collision handling remain outside this subset.  Callers provide the
nonnegative absolute slot ordinal
:math:`n_f N_{slot}^{frame,mu} + n_{s,f}^{mu}`.  Frame/numerology decoding,
ASN.1 lifecycle state, and SFN lifecycle state remain caller-owned.
"""

from std.collections import Span


comptime NR_PDCCH_MONITORING_SL1 = 0
comptime NR_PDCCH_MONITORING_SL2 = 1
comptime NR_PDCCH_MONITORING_SL4 = 2
comptime NR_PDCCH_MONITORING_SL5 = 3
comptime NR_PDCCH_MONITORING_SL8 = 4
comptime NR_PDCCH_MONITORING_SL10 = 5
comptime NR_PDCCH_MONITORING_SL16 = 6
comptime NR_PDCCH_MONITORING_SL20 = 7
comptime NR_PDCCH_MONITORING_SL40 = 8
comptime NR_PDCCH_MONITORING_SL80 = 9
comptime NR_PDCCH_MONITORING_SL160 = 10
comptime NR_PDCCH_MONITORING_SL320 = 11
comptime NR_PDCCH_MONITORING_SL640 = 12
comptime NR_PDCCH_MONITORING_SL1280 = 13
comptime NR_PDCCH_MONITORING_SL2560 = 14


def _is_base_periodicity(periodicity_slots: Int) -> Bool:
    return (
        periodicity_slots == 1
        or periodicity_slots == 2
        or periodicity_slots == 4
        or periodicity_slots == 5
        or periodicity_slots == 8
        or periodicity_slots == 10
        or periodicity_slots == 16
        or periodicity_slots == 20
        or periodicity_slots == 40
        or periodicity_slots == 80
        or periodicity_slots == 160
        or periodicity_slots == 320
        or periodicity_slots == 640
        or periodicity_slots == 1280
        or periodicity_slots == 2560
    )


def _validate_pattern_fields(
    periodicity_slots: Int,
    offset_slots: Int,
    duration_present: Bool,
    duration_slots: Int,
) raises:
    if not _is_base_periodicity(periodicity_slots):
        raise Error("PDCCH monitoring periodicity is not a base SearchSpace choice")
    if offset_slots < 0 or offset_slots >= periodicity_slots:
        raise Error("PDCCH monitoring offset must be in 0..periodicity-1")
    if not duration_present:
        if duration_slots != 1:
            raise Error("absent PDCCH monitoring duration must be normalized to one")
        return
    if duration_slots < 2 or duration_slots > 2559:
        raise Error("present PDCCH monitoring duration must be in 2..2559")
    if duration_slots >= periodicity_slots:
        raise Error("PDCCH monitoring duration must not exceed periodicity-1")


struct NRPDCCHMonitoringPattern(Copyable, Movable):
    """Mutable, decoded base-SearchSpace monitoring-slot pattern.

    Public consumers revalidate every field.  An absent ASN.1 ``duration`` is
    represented only by ``duration_present == False`` and
    ``duration_slots == 1``; ignored or latent caller values are rejected.
    """

    var periodicity_slots: Int
    var offset_slots: Int
    var duration_present: Bool
    var duration_slots: Int

    def __init__(
        out self,
        periodicity_slots: Int,
        offset_slots: Int,
        duration_present: Bool,
        duration_slots: Int,
    ) raises:
        self.periodicity_slots = periodicity_slots
        self.offset_slots = offset_slots
        self.duration_present = duration_present
        self.duration_slots = duration_slots
        self._validate()

    def _validate(self) raises:
        _validate_pattern_fields(
            self.periodicity_slots,
            self.offset_slots,
            self.duration_present,
            self.duration_slots,
        )


def nr_pdcch_monitoring_periodicity(choice_index: Int) raises -> Int:
    """Decode one base SearchSpace periodicity CHOICE alternative.

    ``choice_index`` is the zero-based declaration order from ``sl1`` through
    ``sl2560`` in TS 38.331 clause 6.3.2.  It is a decoded alternative index,
    not an ASN.1 wire encoding.
    """
    if choice_index == NR_PDCCH_MONITORING_SL1:
        return 1
    if choice_index == NR_PDCCH_MONITORING_SL2:
        return 2
    if choice_index == NR_PDCCH_MONITORING_SL4:
        return 4
    if choice_index == NR_PDCCH_MONITORING_SL5:
        return 5
    if choice_index == NR_PDCCH_MONITORING_SL8:
        return 8
    if choice_index == NR_PDCCH_MONITORING_SL10:
        return 10
    if choice_index == NR_PDCCH_MONITORING_SL16:
        return 16
    if choice_index == NR_PDCCH_MONITORING_SL20:
        return 20
    if choice_index == NR_PDCCH_MONITORING_SL40:
        return 40
    if choice_index == NR_PDCCH_MONITORING_SL80:
        return 80
    if choice_index == NR_PDCCH_MONITORING_SL160:
        return 160
    if choice_index == NR_PDCCH_MONITORING_SL320:
        return 320
    if choice_index == NR_PDCCH_MONITORING_SL640:
        return 640
    if choice_index == NR_PDCCH_MONITORING_SL1280:
        return 1280
    if choice_index == NR_PDCCH_MONITORING_SL2560:
        return 2560
    raise Error("PDCCH monitoring periodicity choice index must be in 0..14")


def nr_pdcch_monitoring_pattern(
    choice_index: Int,
    offset_slots: Int,
    duration_present: Bool = False,
    duration_slots: Int = 1,
) raises -> NRPDCCHMonitoringPattern:
    """Construct an exact non-grouped base-SearchSpace pattern.

    For ``sl1`` the ASN.1 NULL alternative implies offset zero.  Every other
    offset is in ``0..periodicity-1``.  Present durations are integers in
    ``2..2559`` and no larger than ``periodicity-1``; absence is normalized to
    the clause-defined one-slot duration.
    """
    return NRPDCCHMonitoringPattern(
        nr_pdcch_monitoring_periodicity(choice_index),
        offset_slots,
        duration_present,
        duration_slots,
    )


def nr_pdcch_is_monitoring_slot(
    pattern: NRPDCCHMonitoringPattern, absolute_slot: Int
) raises -> Bool:
    """Return whether ``absolute_slot`` is in the periodic monitoring window.

    The subtraction is performed only after reducing ``absolute_slot`` into
    the finite periodicity domain.  Consequently every nonnegative ``Int``,
    including ``Int.MAX``, is supported without forming ``absolute_slot -
    offset`` or a frame-times-slots product that could overflow.
    """
    pattern._validate()
    if absolute_slot < 0:
        raise Error("PDCCH monitoring absolute slot must be nonnegative")
    var slot_in_period = absolute_slot % pattern.periodicity_slots
    var distance_from_offset = slot_in_period - pattern.offset_slots
    if distance_from_offset < 0:
        distance_from_offset += pattern.periodicity_slots
    return distance_from_offset < pattern.duration_slots


def nr_pdcch_monitoring_first_symbols(
    mask: Int, extended_cp: Bool = False
) raises -> List[Int]:
    """Decode ``monitoringSymbolsWithinSlot`` in OFDM-symbol order.

    TS 38.331 V18.10.0 clause 6.3.2 defines a 14-bit string whose most
    significant (leftmost) bit represents symbol zero.  For extended cyclic
    prefix the last two bits are ignored, so they are accepted but do not
    produce symbol indexes.  The all-zero bit string is syntactically valid
    and returns an empty list.  This function decodes the RRC field only; the
    TS 38.213 CORESET-duration constraints are owned by
    :func:`nr_pdcch_is_monitoring_occasion`.
    """
    if mask < 0 or mask > 0x3FFF:
        raise Error("PDCCH monitoring-symbol mask must be a 14-bit value")
    var symbol_count = 12 if extended_cp else 14
    var result = List[Int](capacity=symbol_count)
    for symbol in range(symbol_count):
        var bit_index = 13 - symbol
        if ((mask >> bit_index) & 1) != 0:
            result.append(symbol)
    return result^


def _validate_monitoring_first_symbols(
    first_symbols: Span[Int, ...],
    coreset_duration_symbols: Int,
    extended_cp: Bool,
) raises:
    if coreset_duration_symbols < 1 or coreset_duration_symbols > 3:
        raise Error("PDCCH CORESET duration must be in [1,3] symbols")
    var symbol_count = 12 if extended_cp else 14
    var previous = -1
    for index in range(len(first_symbols)):
        var symbol = first_symbols[index]
        # This subtraction form validates the half-open interval without
        # forming symbol + duration on an untrusted Int.
        if symbol < 0 or symbol > symbol_count - coreset_duration_symbols:
            raise Error("PDCCH monitoring occasion crosses the slot boundary")
        if index != 0:
            if symbol <= previous:
                raise Error("PDCCH monitoring first symbols must be ordered and unique")
            if symbol - previous < coreset_duration_symbols:
                raise Error("PDCCH monitoring occasions overlap within the CORESET")
        previous = symbol


def nr_pdcch_is_monitoring_occasion(
    pattern: NRPDCCHMonitoringPattern,
    first_symbols: Span[Int, ...],
    coreset_duration_symbols: Int,
    extended_cp: Bool,
    absolute_slot: Int,
    first_symbol: Int,
) raises -> Bool:
    """Return membership of one decoded non-grouped monitoring occasion.

    ``first_symbols`` contains caller-decoded CORESET start symbols, normally
    obtained from :func:`nr_pdcch_monitoring_first_symbols`.  It is rechecked
    for the TS 38.331 V18.10.0 clause-6.3.2 ``ControlResourceSet.duration``
    domain and for strict order, uniqueness, slot containment, and the
    TS 38.213 V18.8.0 clause-10.1 minimum separation of one CORESET duration.
    This API therefore has joint specification ownership.  Empty input is
    valid.  ``first_symbol`` queries an occasion start, not every occupied
    symbol in its half-open ``[start, start + duration)`` interval.
    """
    _validate_monitoring_first_symbols(
        first_symbols, coreset_duration_symbols, extended_cp
    )
    var symbol_count = 12 if extended_cp else 14
    if first_symbol < 0 or first_symbol >= symbol_count:
        raise Error("PDCCH monitoring first-symbol query is outside the slot")
    if not nr_pdcch_is_monitoring_slot(pattern, absolute_slot):
        return False
    for index in range(len(first_symbols)):
        if first_symbols[index] == first_symbol:
            return True
    return False
