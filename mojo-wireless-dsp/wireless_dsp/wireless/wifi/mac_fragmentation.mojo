"""Base IEEE 802.11 fragmentation and A-MPDU delimiter algorithms.

This CPU-only reference implements the bounded integer portions of IEEE Std
802.11-2024 clauses 9.7.1--9.7.2, 10.4--10.5, and 10.12.7.  It covers the
base individually addressed MSDU/MMPDU fragmentation profile, canonical
ordered reassembly validation, and the non-DMG HT versus VHT-or-later MPDU
delimiter formats.  IEEE Std 802.11be-2024 inherits these delimiter rules for
EHT operation.

The fragmentation threshold is the maximum complete MPDU length.  Callers
supply the constant per-fragment overhead (MAC header, FCS, and any security
expansion), so the planner never guesses a frame-header or cipher profile.
Address/TID tuple lookup, duplicate suppression, retransmission, timers,
buffer ownership, A-MSDU fragmentation, DMG delimiters, scheduling, and RF
carrier sensing are outside this module.

Normative publications:
* IEEE Std 802.11-2024, DOI 10.1109/IEEESTD.2025.10979691.
* IEEE Std 802.11be-2024, official IEEE SA publication 7516.
"""

from std.collections import Span


comptime WIFI_FRAGMENTATION_THRESHOLD_MIN_OCTETS = 256
comptime WIFI_FRAGMENTATION_THRESHOLD_MAX_OCTETS = 2346
comptime WIFI_FRAGMENTATION_MAX_MSDU_OCTETS = 2304
comptime WIFI_FRAGMENTATION_MAX_FRAGMENTS = 16
comptime WIFI_FRAGMENTATION_MIN_OVERHEAD_OCTETS = 28
comptime WIFI_SEQUENCE_NUMBER_MODULUS = 4096

comptime WIFI_AMPDU_DELIMITER_PROFILE_HT = 0
comptime WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER = 1
comptime WIFI_AMPDU_DELIMITER_OCTETS = 4
comptime WIFI_AMPDU_DELIMITER_SIGNATURE = 0x4E
comptime WIFI_AMPDU_HT_MAX_MPDU_OCTETS = 4095
comptime WIFI_AMPDU_EXTENDED_MAX_MPDU_OCTETS = 11454


def _checked_nonnegative_add(lhs: Int, rhs: Int, label: String) raises -> Int:
    if lhs < 0 or rhs < 0:
        raise Error(label + " operands must be non-negative")
    if lhs > Int.MAX - rhs:
        raise Error(label + " overflows Int")
    return lhs + rhs


def _validate_sequence_number(sequence_number: Int) raises:
    if sequence_number < 0 or sequence_number >= WIFI_SEQUENCE_NUMBER_MODULUS:
        raise Error("sequence number must be in [0,4095]")


def _validate_fragmentation_inputs(
    msdu_octets: Int,
    fragmentation_threshold_octets: Int,
    per_fragment_overhead_octets: Int,
    sequence_number: Int,
) raises:
    if msdu_octets < 1 or msdu_octets > WIFI_FRAGMENTATION_MAX_MSDU_OCTETS:
        raise Error("base fragmentation MSDU length must be in [1,2304]")
    if (
        fragmentation_threshold_octets
        < WIFI_FRAGMENTATION_THRESHOLD_MIN_OCTETS
        or fragmentation_threshold_octets
        > WIFI_FRAGMENTATION_THRESHOLD_MAX_OCTETS
    ):
        raise Error("fragmentation threshold must be in [256,2346] octets")
    if (
        per_fragment_overhead_octets
        < WIFI_FRAGMENTATION_MIN_OVERHEAD_OCTETS
        or per_fragment_overhead_octets >= fragmentation_threshold_octets
    ):
        raise Error(
            "per-fragment overhead must be in [28, threshold-1] octets"
        )
    _validate_sequence_number(sequence_number)


struct WifiFragmentationPlan(Movable):
    """Canonical fragment payload and MPDU geometry for one MSDU/MMPDU.

    ``more_fragments`` uses exact byte flags (zero or one).  Every fragment
    carries the same sequence number; the low four Sequence Control bits are
    the corresponding entries of ``fragment_numbers``.
    """

    var sequence_number: Int
    var payload_capacity_octets: Int
    var payload_offsets: List[Int]
    var payload_octets: List[Int]
    var mpdu_octets: List[Int]
    var fragment_numbers: List[Int]
    var sequence_controls: List[Int]
    var more_fragments: List[UInt8]

    def __init__(
        out self,
        sequence_number: Int,
        payload_capacity_octets: Int,
        var payload_offsets: List[Int],
        var payload_octets: List[Int],
        var mpdu_octets: List[Int],
        var fragment_numbers: List[Int],
        var sequence_controls: List[Int],
        var more_fragments: List[UInt8],
    ):
        self.sequence_number = sequence_number
        self.payload_capacity_octets = payload_capacity_octets
        self.payload_offsets = payload_offsets^
        self.payload_octets = payload_octets^
        self.mpdu_octets = mpdu_octets^
        self.fragment_numbers = fragment_numbers^
        self.sequence_controls = sequence_controls^
        self.more_fragments = more_fragments^


def wifi_fragmentation_plan(
    msdu_octets: Int,
    fragmentation_threshold_octets: Int,
    per_fragment_overhead_octets: Int,
    sequence_number: Int,
    *,
    is_group_addressed: Bool = False,
) raises -> WifiFragmentationPlan:
    """Plan the base clause-10.4 fragmentation of one MSDU or MMPDU.

    The threshold includes all per-fragment overhead.  Non-final payloads use
    the full remaining capacity, the final payload is no larger, fragment
    numbers start at zero, and ``More Fragments`` is one only on non-final
    fragments.  More than 16 fragments is rejected before allocation because
    the Sequence Control Fragment Number field is four bits.  Group-addressed
    traffic is accepted only when no fragmentation is required.
    """
    _validate_fragmentation_inputs(
        msdu_octets,
        fragmentation_threshold_octets,
        per_fragment_overhead_octets,
        sequence_number,
    )
    var payload_capacity = (
        fragmentation_threshold_octets - per_fragment_overhead_octets
    )
    var fragment_count = msdu_octets // payload_capacity
    if msdu_octets % payload_capacity != 0:
        fragment_count += 1
    if fragment_count > WIFI_FRAGMENTATION_MAX_FRAGMENTS:
        raise Error("fragment plan exceeds the four-bit fragment-number space")
    if is_group_addressed and fragment_count != 1:
        raise Error("group-addressed MSDUs/MMPDUs shall not be fragmented")

    var payload_offsets = List[Int](capacity=fragment_count)
    var payloads = List[Int](capacity=fragment_count)
    var mpdus = List[Int](capacity=fragment_count)
    var fragment_numbers = List[Int](capacity=fragment_count)
    var sequence_controls = List[Int](capacity=fragment_count)
    var more_flags = List[UInt8](capacity=fragment_count)
    var offset = 0
    for fragment_number in range(fragment_count):
        var remaining = msdu_octets - offset
        var payload = min(payload_capacity, remaining)
        payload_offsets.append(offset)
        payloads.append(payload)
        mpdus.append(_checked_nonnegative_add(
            payload,
            per_fragment_overhead_octets,
            "fragment MPDU length",
        ))
        fragment_numbers.append(fragment_number)
        sequence_controls.append((sequence_number << 4) | fragment_number)
        more_flags.append(UInt8(
            1 if fragment_number + 1 < fragment_count else 0
        ))
        offset = _checked_nonnegative_add(
            offset, payload, "fragment payload offset"
        )
    return WifiFragmentationPlan(
        sequence_number,
        payload_capacity,
        payload_offsets^,
        payloads^,
        mpdus^,
        fragment_numbers^,
        sequence_controls^,
        more_flags^,
    )


struct WifiReassemblyPlan(Movable):
    """Validated canonical fragment order and payload placement for one MSDU."""

    var sequence_number: Int
    var payload_offsets: List[Int]
    var total_msdu_octets: Int

    def __init__(
        out self,
        sequence_number: Int,
        var payload_offsets: List[Int],
        total_msdu_octets: Int,
    ):
        self.sequence_number = sequence_number
        self.payload_offsets = payload_offsets^
        self.total_msdu_octets = total_msdu_octets


def wifi_reassembly_plan(
    sequence_controls: Span[Int, ...],
    more_fragments: Span[UInt8, ...],
    payload_octets: Span[Int, ...],
    *,
    is_group_addressed: Bool = False,
) raises -> WifiReassemblyPlan:
    """Validate an ordered, duplicate-free base clause-10.5 fragment set.

    The caller groups fragments by transmitter/destination/TID and removes
    duplicate retries before this pure boundary.  This function then requires
    one sequence number, consecutive fragment numbers beginning at zero,
    exact ``More Fragments`` flags, equal non-final payload sizes, a final
    payload no larger than those preceding it, and at most 2304 reassembled
    octets.  Missing, reordered, duplicated, or cross-sequence fragments are
    rejected rather than silently normalized.
    """
    var count = len(sequence_controls)
    if count < 1 or count > WIFI_FRAGMENTATION_MAX_FRAGMENTS:
        raise Error("reassembly needs between one and 16 fragments")
    if len(more_fragments) != count or len(payload_octets) != count:
        raise Error("reassembly fragment arrays must have equal lengths")
    if is_group_addressed and count != 1:
        raise Error("group-addressed MSDUs/MMPDUs shall not be fragmented")

    var first_control = sequence_controls[0]
    if first_control < 0 or first_control > 65535:
        raise Error("Sequence Control must be an unsigned 16-bit value")
    var sequence_number = first_control >> 4
    _validate_sequence_number(sequence_number)
    var nonfinal_payload_octets = 0
    var offsets = List[Int](capacity=count)
    var total = 0
    for index in range(count):
        var control = sequence_controls[index]
        if control < 0 or control > 65535:
            raise Error("Sequence Control must be an unsigned 16-bit value")
        if (control >> 4) != sequence_number:
            raise Error("all reassembly fragments must share one sequence number")
        if (control & 15) != index:
            raise Error("fragment numbers must be consecutive from zero")

        var flag = more_fragments[index]
        if flag != 0 and flag != 1:
            raise Error("More Fragments flags must be zero or one")
        var expected_more = UInt8(1 if index + 1 < count else 0)
        if flag != expected_more:
            raise Error("More Fragments flags do not identify exactly one final fragment")

        var payload = payload_octets[index]
        if payload < 1 or payload > WIFI_FRAGMENTATION_MAX_MSDU_OCTETS:
            raise Error("fragment payload length must be in [1,2304]")
        if count > 1 and index + 1 < count:
            if index == 0:
                nonfinal_payload_octets = payload
            elif payload != nonfinal_payload_octets:
                raise Error("all non-final fragment payloads must have equal length")
        elif count > 1 and payload > nonfinal_payload_octets:
            raise Error("the final fragment payload cannot exceed non-final payloads")

        offsets.append(total)
        total = _checked_nonnegative_add(
            total, payload, "reassembled MSDU length"
        )
        if total > WIFI_FRAGMENTATION_MAX_MSDU_OCTETS:
            raise Error("reassembled base MSDU exceeds 2304 octets")
    return WifiReassemblyPlan(sequence_number, offsets^, total)


struct WifiAMPDUDelimiterFields(ImplicitlyCopyable):
    """Strictly decoded non-DMG MPDU delimiter fields and next-step geometry."""

    var profile: Int
    var first_word: Int
    var mpdu_length_octets: Int
    var eof: Bool
    var crc: Int
    var padding_octets: Int
    var next_delimiter_delta_octets: Int

    def __init__(
        out self,
        profile: Int,
        first_word: Int,
        mpdu_length_octets: Int,
        eof: Bool,
        crc: Int,
        padding_octets: Int,
        next_delimiter_delta_octets: Int,
    ):
        self.profile = profile
        self.first_word = first_word
        self.mpdu_length_octets = mpdu_length_octets
        self.eof = eof
        self.crc = crc
        self.padding_octets = padding_octets
        self.next_delimiter_delta_octets = next_delimiter_delta_octets


def _validate_delimiter_profile(profile: Int) raises:
    if profile != WIFI_AMPDU_DELIMITER_PROFILE_HT and (
        profile != WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER
    ):
        raise Error("non-DMG delimiter profile must be HT or VHT-or-later")


def _validate_delimiter_length(
    mpdu_length_octets: Int, profile: Int, eof: Bool
) raises:
    _validate_delimiter_profile(profile)
    var maximum = (
        WIFI_AMPDU_HT_MAX_MPDU_OCTETS
        if profile == WIFI_AMPDU_DELIMITER_PROFILE_HT
        else WIFI_AMPDU_EXTENDED_MAX_MPDU_OCTETS
    )
    if mpdu_length_octets < 0 or mpdu_length_octets > maximum:
        raise Error("MPDU length exceeds the selected delimiter profile")
    if profile == WIFI_AMPDU_DELIMITER_PROFILE_HT and eof:
        raise Error("HT delimiters reserve the EOF and MPDU-Length-High bits")


def wifi_ampdu_delimiter_crc8(octet0: Int, octet1: Int) raises -> Int:
    """Return the exact delimiter CRC over the first 16 transmitted bits.

    IEEE 802.11 uses polynomial ``x^8 + x^2 + x + 1``, an all-ones preset,
    least-significant-bit-first processing within each octet, and the ones'
    complement of the final remainder.  The result is an unsigned octet.
    """
    if octet0 < 0 or octet0 > 255 or octet1 < 0 or octet1 > 255:
        raise Error("delimiter CRC inputs must be unsigned octets")
    var remainder = 0xFF
    var current = octet0
    for _ in range(8):
        var feedback = (remainder ^ current) & 1
        remainder >>= 1
        if feedback != 0:
            # 0xE0 is the reflected representation of polynomial 0x07.
            remainder ^= 0xE0
        current >>= 1
    current = octet1
    for _ in range(8):
        var feedback = (remainder ^ current) & 1
        remainder >>= 1
        if feedback != 0:
            remainder ^= 0xE0
        current >>= 1
    return remainder ^ 0xFF


def wifi_ampdu_delimiter_serialize(
    mpdu_length_octets: Int,
    *,
    eof: Bool = False,
    profile: Int = WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER,
) raises -> List[UInt8]:
    """Serialize one strict four-octet non-DMG MPDU delimiter.

    HT uses the 12-bit MPDU Length Low field and requires the other four low
    bits to be zero.  VHT, S1G, HE, and EHT use B0 for EOF, reserve B1, and
    use B2--B3 plus B4--B15 for the 14-bit length.  ``eof=True`` with zero
    length represents an EOF-padding delimiter; nonzero EOF is permitted for
    a single-MPDU context, whose aggregate-context validation belongs to the
    caller.  Octets are returned in transmission order.
    """
    _validate_delimiter_length(mpdu_length_octets, profile, eof)
    var first_word = (mpdu_length_octets & 0xFFF) << 4
    if profile == WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER:
        first_word |= ((mpdu_length_octets >> 12) & 3) << 2
        if eof:
            first_word |= 1
    var octet0 = first_word & 0xFF
    var octet1 = (first_word >> 8) & 0xFF
    var crc = wifi_ampdu_delimiter_crc8(octet0, octet1)
    return [
        UInt8(octet0),
        UInt8(octet1),
        UInt8(crc),
        UInt8(WIFI_AMPDU_DELIMITER_SIGNATURE),
    ]


def wifi_ampdu_delimiter_parse(
    delimiter: Span[UInt8, ...],
    *,
    profile: Int = WIFI_AMPDU_DELIMITER_PROFILE_VHT_OR_LATER,
) raises -> WifiAMPDUDelimiterFields:
    """Strictly parse and validate one four-octet non-DMG MPDU delimiter.

    Length, profile-reserved bits, signature, and CRC are all checked.  The
    returned padding and next-delimiter delta describe the standard four-octet
    alignment after a non-null MPDU; aggregate-end and resynchronization policy
    remain caller decisions.
    """
    _validate_delimiter_profile(profile)
    if len(delimiter) != WIFI_AMPDU_DELIMITER_OCTETS:
        raise Error("an MPDU delimiter must contain exactly four octets")
    var octet0 = Int(delimiter[0])
    var octet1 = Int(delimiter[1])
    var observed_crc = Int(delimiter[2])
    if Int(delimiter[3]) != WIFI_AMPDU_DELIMITER_SIGNATURE:
        raise Error("invalid MPDU delimiter signature")
    if wifi_ampdu_delimiter_crc8(octet0, octet1) != observed_crc:
        raise Error("invalid MPDU delimiter CRC")

    var first_word = octet0 | (octet1 << 8)
    if (first_word & 2) != 0:
        raise Error("the non-DMG MPDU delimiter reserved bit must be zero")
    var eof = (first_word & 1) != 0
    var mpdu_length = (first_word >> 4) & 0xFFF
    if profile == WIFI_AMPDU_DELIMITER_PROFILE_HT:
        if (first_word & 0xD) != 0:
            raise Error("HT delimiter reserved bits must all be zero")
    else:
        mpdu_length |= ((first_word >> 2) & 3) << 12
    _validate_delimiter_length(mpdu_length, profile, eof)

    var padding = (4 - mpdu_length % 4) % 4
    var next_delta = _checked_nonnegative_add(
        WIFI_AMPDU_DELIMITER_OCTETS,
        mpdu_length,
        "A-MPDU subframe length",
    )
    next_delta = _checked_nonnegative_add(
        next_delta, padding, "A-MPDU subframe padding"
    )
    return WifiAMPDUDelimiterFields(
        profile,
        first_word,
        mpdu_length,
        eof,
        observed_crc,
        padding,
        next_delta,
    )
