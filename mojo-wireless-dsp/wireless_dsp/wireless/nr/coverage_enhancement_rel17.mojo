"""Bounded Rel-17 NR coverage-enhancement scheduling arithmetic.

This module implements decoded-configuration algorithms from 3GPP
TS 38.214 V17.16.0 clauses 6.1.2.1 and 6.1.7 for ordinary NR UEs.  It
deliberately remains separate from the Rel-17 RedCap half-duplex profile.

The caller supplies already-decoded TDD/SSB slot eligibility.  RRC ASN.1,
DCI decoding, scheduler policy, RF acquisition, PUSCH/PUCCH waveform
generation, and receiver combining remain outside this bounded module.
"""


comptime NR_COV_ENH_MAPPING_TYPE_A = 0
comptime NR_COV_ENH_MAPPING_TYPE_B = 1
comptime NR_COV_ENH_CP_NORMAL = 0
comptime NR_COV_ENH_CP_EXTENDED = 1
comptime NR_COV_ENH_REPETITION_TYPE_A = 0
comptime NR_COV_ENH_REPETITION_TYPE_B = 1
comptime NR_COV_ENH_SPECTRUM_PAIRED_OR_SUL = 0
comptime NR_COV_ENH_SPECTRUM_UNPAIRED = 1


@fieldwise_init
struct NRCoverageEnhancementTBMSProfile(Copyable, Movable):
    """Validated Rel-17 transport-block-over-multiple-slots geometry."""

    var number_of_slots: Int
    var number_of_repetitions: Int
    var required_slot_count: Int

    def validate(self) raises:
        if (
            not _valid_tbms_slot_count(self.number_of_slots)
            or not _valid_pusch_repetition_count(
                self.number_of_repetitions
            )
            or self.required_slot_count < 1
        ):
            raise Error("invalid Rel-17 TBMS profile")
        var product = (
            Int128(self.number_of_slots)
            * Int128(self.number_of_repetitions)
        )
        if product > 32 or product != Int128(self.required_slot_count):
            raise Error("Rel-17 repetition-capable TBMS requires N*K <= 32")


def _valid_msg3_repetition_count(value: Int) -> Bool:
    return (
        value == 1
        or value == 2
        or value == 3
        or value == 4
        or value == 7
        or value == 8
        or value == 12
        or value == 16
    )


def _valid_pusch_repetition_count(value: Int) -> Bool:
    return (
        _valid_msg3_repetition_count(value)
        or value == 20
        or value == 24
        or value == 28
        or value == 32
    )


def _valid_tbms_slot_count(value: Int) -> Bool:
    return value == 2 or value == 4 or value == 8


def _valid_maximum_bundling_duration(value: Int) -> Bool:
    return (
        value == 2
        or value == 4
        or value == 8
        or value == 16
        or value == 32
    )


def _validate_mapping_type(mapping_type: Int) raises:
    if (
        mapping_type != NR_COV_ENH_MAPPING_TYPE_A
        and mapping_type != NR_COV_ENH_MAPPING_TYPE_B
    ):
        raise Error("invalid PUSCH mapping type")


def _validate_cyclic_prefix(cyclic_prefix: Int) raises:
    if (
        cyclic_prefix != NR_COV_ENH_CP_NORMAL
        and cyclic_prefix != NR_COV_ENH_CP_EXTENDED
    ):
        raise Error("invalid cyclic-prefix profile")


def _validate_repetition_type(repetition_type: Int) raises:
    if (
        repetition_type != NR_COV_ENH_REPETITION_TYPE_A
        and repetition_type != NR_COV_ENH_REPETITION_TYPE_B
    ):
        raise Error("invalid PUSCH repetition type")


def nr_cov_enh_rel17_valid_pusch_allocation(
    mapping_type: Int,
    cyclic_prefix: Int,
    repetition_type: Int,
    start_symbol: Int,
    symbol_length: Int,
) raises -> Bool:
    """Return Table 6.1.2.1-1 validity for a decoded ``S,L`` pair.

    Mapping type A is defined only for repetition type A and starts at symbol
    zero with length 4..14 for normal CP or 4..12 for extended CP.  Mapping
    type B admits the complete published ranges, including nominal type-B
    repetitions crossing a slot boundary.
    """
    _validate_mapping_type(mapping_type)
    _validate_cyclic_prefix(cyclic_prefix)
    _validate_repetition_type(repetition_type)
    if start_symbol < 0 or symbol_length < 1:
        return False

    var symbols_per_slot = (
        14 if cyclic_prefix == NR_COV_ENH_CP_NORMAL else 12
    )
    if mapping_type == NR_COV_ENH_MAPPING_TYPE_A:
        return (
            repetition_type == NR_COV_ENH_REPETITION_TYPE_A
            and start_symbol == 0
            and symbol_length >= 4
            and symbol_length <= symbols_per_slot
        )

    if start_symbol >= symbols_per_slot or symbol_length > symbols_per_slot:
        return False
    var allocation_end = start_symbol + symbol_length
    if repetition_type == NR_COV_ENH_REPETITION_TYPE_A:
        return allocation_end <= symbols_per_slot
    return allocation_end <= (2 * symbols_per_slot - 1)


def nr_cov_enh_rel17_msg3_repetition_count(
    codepoint: Int,
    configured_repetitions: Span[Int, ...],
) raises -> Int:
    """Decode Table 6.1.2.1-1A from the two MCS-field MSBs.

    An empty list selects the normative default ``1,2,3,4`` mapping.  A
    configured ``numberOfMsg3-RepetitionsList`` is supplied as exactly four
    decoded ``NumberOfMsg3-Repetitions-r17`` values in codepoint order.
    """
    if codepoint < 0 or codepoint > 3:
        raise Error("Msg3 repetition codepoint must be in 0..3")
    if len(configured_repetitions) == 0:
        return codepoint + 1
    if len(configured_repetitions) != 4:
        raise Error("configured Msg3 repetition list must have four values")
    for index in range(4):
        if not _valid_msg3_repetition_count(configured_repetitions[index]):
            raise Error("configured Msg3 repetition count is not standardized")
    return configured_repetitions[codepoint]


def nr_cov_enh_rel17_tbms_profile(
    number_of_slots_tboms: Int,
    number_of_repetitions: Int = 1,
) raises -> NRCoverageEnhancementTBMSProfile:
    """Return checked ``N``, ``K``, and ``N*K`` TBMS geometry.

    The profile is the Rel-17 repetition-capable branch, for which the UE does
    not expect ``N*K`` larger than 32. ``N`` is one of 2, 4 or 8, while ``K``
    is a standardized ``numberOfRepetitions`` or extended value.
    """
    if (
        not _valid_tbms_slot_count(number_of_slots_tboms)
        or not _valid_pusch_repetition_count(number_of_repetitions)
    ):
        raise Error("invalid Rel-17 TBMS N or K")
    var product = (
        Int128(number_of_slots_tboms) * Int128(number_of_repetitions)
    )
    if product > 32:
        raise Error("Rel-17 repetition-capable TBMS requires N*K <= 32")
    var profile = NRCoverageEnhancementTBMSProfile(
        number_of_slots_tboms,
        number_of_repetitions,
        Int(product),
    )
    profile.validate()
    return profile^


def nr_cov_enh_rel17_select_tbms_slots(
    start_slot: Int,
    slot_eligibility: Span[UInt8, ...],
    profile: NRCoverageEnhancementTBMSProfile,
    spectrum_profile: Int,
) raises -> List[Int]:
    """Select the ``N*K`` slots for a decoded Rel-17 TBMS allocation.

    For paired spectrum or SUL, clause 6.1.2.1 selects consecutive slots and
    the supplied mask must therefore contain at least ``N*K`` entries.  For
    unpaired spectrum, a mask value of one means that the PUSCH symbols do not
    overlap decoded DL or SS/PBCH symbols; zero-valued candidates are skipped.
    The mask is validated even on the paired branch to reject corrupt decoded
    state rather than silently accepting it.
    """
    profile.validate()
    if start_slot < 0:
        raise Error("TBMS start slot must be nonnegative")
    if (
        spectrum_profile != NR_COV_ENH_SPECTRUM_PAIRED_OR_SUL
        and spectrum_profile != NR_COV_ENH_SPECTRUM_UNPAIRED
    ):
        raise Error("invalid spectrum profile")
    if len(slot_eligibility) < profile.required_slot_count:
        raise Error("insufficient TBMS candidate slots")
    if start_slot > Int.MAX - (len(slot_eligibility) - 1):
        raise Error("TBMS candidate slot index overflows Int")
    for index in range(len(slot_eligibility)):
        if slot_eligibility[index] > 1:
            raise Error("TBMS slot eligibility must be binary")

    var selected = List[Int](capacity=profile.required_slot_count)
    for offset in range(len(slot_eligibility)):
        if (
            spectrum_profile == NR_COV_ENH_SPECTRUM_UNPAIRED
            and slot_eligibility[offset] == 0
        ):
            continue
        selected.append(start_slot + offset)
        if len(selected) == profile.required_slot_count:
            return selected^
    raise Error("insufficient eligible TBMS slots")


def nr_cov_enh_rel17_pusch_nominal_tdw_length_slots(
    configured_window_length: Int,
    maximum_duration: Int,
    first_selected_slot: Int,
    last_selected_slot: Int,
) raises -> Int:
    """Return the clause-6.1.7 nominal PUSCH TDW length in slots.

    A configured length in 2..32 takes precedence, must not exceed the decoded
    standardized maximum capability, and zero denotes absence. The absent
    branch yields ``min(maxDurationDMRS-Bundling, M)``, where ``M`` is the
    inclusive consecutive-slot span from first to last selected transmission.
    """
    if (
        configured_window_length < 0
        or not _valid_maximum_bundling_duration(maximum_duration)
        or first_selected_slot < 0
        or last_selected_slot < first_selected_slot
    ):
        raise Error("invalid nominal TDW geometry")
    if configured_window_length > 0:
        if (
            configured_window_length < 2
            or configured_window_length > 32
            or configured_window_length > maximum_duration
        ):
            raise Error("configured nominal TDW exceeds its legal capability")
        return configured_window_length
    var span = Int128(last_selected_slot) - Int128(first_selected_slot) + 1
    if span > Int128(Int.MAX):
        raise Error("nominal TDW span overflows Int")
    var span_int = Int(span)
    return maximum_duration if maximum_duration < span_int else span_int


def nr_cov_enh_rel17_pusch_nominal_tdw_ids(
    selected_slots: Span[Int, ...],
    nominal_window_length: Int,
) raises -> List[Int]:
    """Assign selected PUSCH slots to nominal TDWs from clause 6.1.7.

    The first window starts at the first selected slot.  Every later window
    starts at the first selected slot after the previous fixed-duration
    window, which is the rule used with available-slot counting and TBMS.
    """
    if (
        len(selected_slots) == 0
        or nominal_window_length < 1
        or nominal_window_length > 32
    ):
        raise Error("nominal TDW assignment needs slots and length 1..32")
    if selected_slots[0] < 0:
        raise Error("selected slots must be nonnegative")
    for index in range(1, len(selected_slots)):
        if selected_slots[index] <= selected_slots[index - 1]:
            raise Error("selected slots must be strictly increasing")

    var ids = List[Int](capacity=len(selected_slots))
    var window_id = 0
    var window_end = (
        Int128(selected_slots[0]) + Int128(nominal_window_length)
    )
    if window_end > Int128(Int.MAX) + 1:
        raise Error("nominal TDW end overflows Int domain")
    for index in range(len(selected_slots)):
        var slot = selected_slots[index]
        if Int128(slot) >= window_end:
            window_id += 1
            window_end = Int128(slot) + Int128(nominal_window_length)
            if window_end > Int128(Int.MAX) + 1:
                raise Error("nominal TDW end overflows Int domain")
        ids.append(window_id)
    return ids^


def nr_cov_enh_rel17_dmrs_bundling_gap_event(
    cyclic_prefix: Int,
    gap_symbols: Int,
    supports_non_back_to_back_tx: Bool,
    other_uplink_scheduled_in_gap: Bool,
) raises -> Bool:
    """Classify the clause-6.1.7 gap events that break an actual TDW.

    Without the non-back-to-back capability every nonzero gap is an event.
    With the capability, a gap exceeding 13 normal-CP or 11 extended-CP
    symbols is an event.  Scheduling another uplink transmission in a gap no
    larger than 13 symbols is independently an event.
    """
    _validate_cyclic_prefix(cyclic_prefix)
    if gap_symbols < 0:
        raise Error("DM-RS bundling gap cannot be negative")
    if gap_symbols == 0 and other_uplink_scheduled_in_gap:
        raise Error("a zero-symbol gap cannot contain another uplink")
    var capability_limit = (
        13 if cyclic_prefix == NR_COV_ENH_CP_NORMAL else 11
    )
    if supports_non_back_to_back_tx:
        if gap_symbols > capability_limit:
            return True
    elif gap_symbols != 0:
        return True
    return other_uplink_scheduled_in_gap and gap_symbols <= 13
