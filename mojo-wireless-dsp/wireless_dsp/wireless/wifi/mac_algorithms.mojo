"""Bounded deterministic IEEE 802.11 MAC arithmetic.

This module implements the CPU-reference arithmetic portions of IEEE Std
802.11-2024: Duration/ID and Sequence Control fields (9.2.4.2/9.2.4.4),
A-MSDU and A-MPDU formats (9.3.2.2/9.7), NAV maintenance (10.3.2.4), DCF
backoff/retry rules (10.3.4.3--10.3.4.4), aggregation (10.11--10.12), EDCA
(10.23.2), and Block Ack receive reordering (10.25.6.6).  Randomness is
deliberately external: callers provide the already drawn integer backoff value
and this module validates it against the current contention window.

The normative publication is IEEE Std 802.11-2024, DOI
10.1109/IEEESTD.2025.10979691.  Carrier sensing, transmission scheduling,
rate-control policy, frame encryption, and full MAC frame serialization are
outside this deterministic arithmetic layer.  All time values use caller-
selected integral units; a single call must use one consistent unit.
"""

from std.collections import Span


comptime WIFI_SEQUENCE_MODULUS = 4096
comptime WIFI_BLOCK_ACK_OLD = 0
comptime WIFI_BLOCK_ACK_IN_WINDOW = 1
comptime WIFI_BLOCK_ACK_ADVANCE_WINDOW = 2

comptime WIFI_AMSDU_SUBFRAME_HEADER_OCTETS = 14
comptime WIFI_AMPDU_DELIMITER_OCTETS = 4
comptime WIFI_AMPDU_DELIMITER_SIGNATURE = 0x4E


def _checked_nonnegative_add(lhs: Int, rhs: Int, label: String) raises -> Int:
    if lhs < 0 or rhs < 0:
        raise Error(label + " operands must be non-negative")
    if lhs > Int.MAX - rhs:
        raise Error(label + " overflows Int")
    return lhs + rhs


def _checked_nonnegative_multiply(
    lhs: Int, rhs: Int, label: String,
) raises -> Int:
    if lhs < 0 or rhs < 0:
        raise Error(label + " operands must be non-negative")
    if lhs != 0 and rhs > Int.MAX // lhs:
        raise Error(label + " overflows Int")
    return lhs * rhs


def _is_binary_power_minus_one(value: Int) -> Bool:
    return value >= 0 and (value & (value + 1)) == 0


struct WifiContentionConfig(ImplicitlyCopyable):
    """DCF/EDCA contention and retry limits for one traffic category.

    Public fields are intentionally inspectable and mutable.  Every public
    algorithm that accepts this record validates it again, so mutation cannot
    bypass the standard-domain and overflow contracts.
    """

    var cw_min: Int
    var cw_max: Int
    var retry_limit: Int

    def __init__(
        out self, cw_min: Int, cw_max: Int, retry_limit: Int,
    ):
        self.cw_min = cw_min
        self.cw_max = cw_max
        self.retry_limit = retry_limit


struct WifiContentionState(ImplicitlyCopyable):
    """Current contention window, retry counter, and discard indication."""

    var contention_window: Int
    var retry_count: Int
    var discarded: Bool

    def __init__(
        out self,
        contention_window: Int,
        retry_count: Int,
        discarded: Bool = False,
    ):
        self.contention_window = contention_window
        self.retry_count = retry_count
        self.discarded = discarded


def _validate_contention_config(config: WifiContentionConfig) raises:
    if (
        config.cw_min < 0
        or config.cw_max < config.cw_min
        or config.cw_max > 32767
        or not _is_binary_power_minus_one(config.cw_min)
        or not _is_binary_power_minus_one(config.cw_max)
        or config.retry_limit < 1
        or config.retry_limit > 255
    ):
        raise Error(
            "contention windows must be 2^n-1 in [0,32767] and retry limit in [1,255]"
        )


def _validate_contention_state(
    config: WifiContentionConfig, state: WifiContentionState,
) raises:
    _validate_contention_config(config)
    if (
        state.contention_window < config.cw_min
        or state.contention_window > config.cw_max
        or not _is_binary_power_minus_one(state.contention_window)
        or state.retry_count < 0
        or state.retry_count >= config.retry_limit
    ):
        raise Error("invalid contention/retry state")
    if state.discarded and (
        state.contention_window != config.cw_min or state.retry_count != 0
    ):
        raise Error("a discard indication must carry the reset contention state")


def wifi_aifs_duration(
    sifs_time: Int,
    slot_time: Int,
    aifsn: Int,
    *,
    is_access_point: Bool = False,
) raises -> Int:
    """Return ``SIFS + AIFSN * slotTime`` in caller-selected integral units.

    ``AIFSN=2`` is the DCF DIFS arithmetic.  EDCA supplies the access-category
    AIFSN explicitly.  The four-bit AIFSN domain is 2--15 for a non-AP STA and
    1--15 for an AP; PHY-specific SIFS and slot values remain caller inputs.
    """
    var minimum_aifsn = 1 if is_access_point else 2
    if (
        sifs_time < 0
        or slot_time <= 0
        or aifsn < minimum_aifsn
        or aifsn > 15
    ):
        raise Error("invalid SIFS, slot time, or AIFSN")
    var slots = _checked_nonnegative_multiply(
        slot_time, aifsn, "AIFS slot contribution"
    )
    return _checked_nonnegative_add(sifs_time, slots, "AIFS duration")


def wifi_backoff_select_slots(
    config: WifiContentionConfig,
    state: WifiContentionState,
    random_draw: Int,
) raises -> Int:
    """Validate and return an explicit uniform draw from ``[0, CW]``.

    No pseudo-random generator or scheduling policy is hidden in this API.
    Replays therefore use exactly the same standard backoff state arithmetic.
    """
    _validate_contention_state(config, state)
    if random_draw < 0 or random_draw > state.contention_window:
        raise Error("backoff draw must be in the inclusive current-CW range")
    return random_draw


def wifi_backoff_after_idle_slots(
    current_backoff_slots: Int, elapsed_idle_slots: Int,
) raises -> Int:
    """Apply deterministic idle-slot countdown with saturation at zero."""
    if current_backoff_slots < 0 or elapsed_idle_slots < 0:
        raise Error("backoff and idle-slot counts must be non-negative")
    if elapsed_idle_slots >= current_backoff_slots:
        return 0
    return current_backoff_slots - elapsed_idle_slots


def wifi_retry_contention_after_failure(
    config: WifiContentionConfig, state: WifiContentionState,
) raises -> WifiContentionState:
    """Advance retry/CW state after an unsuccessful transmission attempt.

    Below the retry limit, ``CW`` becomes ``min(2*CW+1, CWmax)``.  Reaching
    the supplied short/long retry limit emits ``discarded=True`` and resets
    both counters for the next MSDU/MPDU.
    """
    _validate_contention_state(config, state)
    var next_retry = state.retry_count + 1
    if next_retry >= config.retry_limit:
        return WifiContentionState(config.cw_min, 0, True)
    # The validated CW maximum is 32767, so this expression cannot overflow.
    var doubled = 2 * state.contention_window + 1
    return WifiContentionState(
        min(doubled, config.cw_max), next_retry, False
    )


def wifi_retry_contention_after_success(
    config: WifiContentionConfig, state: WifiContentionState,
) raises -> WifiContentionState:
    """Reset retry and contention-window state after success."""
    _validate_contention_state(config, state)
    return WifiContentionState(config.cw_min, 0, False)


def wifi_nav_update_end(
    current_nav_end: Int, received_frame_start: Int, duration: Int,
) raises -> Int:
    """Update the NAV end time from a normalized Duration value.

    The Duration/ID field must already have been classified as a duration;
    PS-Poll AID and reserved encodings are not accepted by this normalized
    arithmetic boundary.  Duration values use the 15-bit nonnegative domain.
    """
    if (
        current_nav_end < 0
        or received_frame_start < 0
        or duration < 0
        or duration > 32767
    ):
        raise Error("invalid NAV time or normalized Duration value")
    var candidate = _checked_nonnegative_add(
        received_frame_start, duration, "NAV end time"
    )
    return max(current_nav_end, candidate)


def wifi_nav_remaining(now: Int, nav_end: Int) raises -> Int:
    """Return the nonnegative NAV interval remaining at ``now``."""
    if now < 0 or nav_end < 0:
        raise Error("NAV time values must be non-negative")
    if nav_end <= now:
        return 0
    return nav_end - now


struct WifiSequenceControlFields(ImplicitlyCopyable):
    """The 12-bit Sequence Number and four-bit Fragment Number fields."""

    var sequence_number: Int
    var fragment_number: Int

    def __init__(out self, sequence_number: Int, fragment_number: Int):
        self.sequence_number = sequence_number
        self.fragment_number = fragment_number


def _validate_sequence_number(sequence_number: Int) raises:
    if sequence_number < 0 or sequence_number >= WIFI_SEQUENCE_MODULUS:
        raise Error("sequence number must be in [0,4095]")


def wifi_sequence_control_pack(
    sequence_number: Int, fragment_number: Int,
) raises -> Int:
    """Pack the 12-bit sequence and four-bit fragment fields into 16 bits."""
    _validate_sequence_number(sequence_number)
    if fragment_number < 0 or fragment_number > 15:
        raise Error("fragment number must be in [0,15]")
    return (sequence_number << 4) | fragment_number


def wifi_sequence_control_unpack(control: Int) raises -> WifiSequenceControlFields:
    """Parse a complete unsigned 16-bit Sequence Control field."""
    if control < 0 or control > 65535:
        raise Error("Sequence Control must be an unsigned 16-bit value")
    return WifiSequenceControlFields(control >> 4, control & 15)


def wifi_sequence_number_add(sequence_number: Int, delta: Int) raises -> Int:
    """Add a nonnegative delta in the modulo-4096 sequence space."""
    _validate_sequence_number(sequence_number)
    if delta < 0:
        raise Error("sequence-number delta must be non-negative")
    return (sequence_number + delta % WIFI_SEQUENCE_MODULUS) % WIFI_SEQUENCE_MODULUS


def wifi_sequence_number_distance(
    window_start: Int, sequence_number: Int,
) raises -> Int:
    """Return forward modulo-4096 distance from ``window_start``."""
    _validate_sequence_number(window_start)
    _validate_sequence_number(sequence_number)
    return (
        sequence_number - window_start + WIFI_SEQUENCE_MODULUS
    ) % WIFI_SEQUENCE_MODULUS


struct WifiBlockAckReorderPlan(ImplicitlyCopyable):
    """One exact Block Ack receive-window classification and placement."""

    var action: Int
    var previous_window_start: Int
    var next_window_start: Int
    var buffer_index: Int

    def __init__(
        out self,
        action: Int,
        previous_window_start: Int,
        next_window_start: Int,
        buffer_index: Int,
    ):
        self.action = action
        self.previous_window_start = previous_window_start
        self.next_window_start = next_window_start
        self.buffer_index = buffer_index


def wifi_block_ack_reorder_plan(
    window_start: Int, window_size: Int, sequence_number: Int,
) raises -> WifiBlockAckReorderPlan:
    """Classify an MPDU and plan the Block Ack reorder-window update.

    Window sizes 1--1024 cover the base, compressed, and extended Block Ack
    receive-buffer profiles while remaining below half of the 4096-element
    serial-number space.  Forward distances greater than or equal to half the
    sequence space are classified as old.
    """
    _validate_sequence_number(window_start)
    _validate_sequence_number(sequence_number)
    if window_size < 1 or window_size > 1024:
        raise Error("Block Ack window size must be in [1,1024]")
    var distance = wifi_sequence_number_distance(
        window_start, sequence_number
    )
    if distance < window_size:
        return WifiBlockAckReorderPlan(
            WIFI_BLOCK_ACK_IN_WINDOW,
            window_start,
            window_start,
            distance,
        )
    if distance < WIFI_SEQUENCE_MODULUS // 2:
        var next_start = (
            sequence_number
            + WIFI_SEQUENCE_MODULUS
            - (window_size - 1)
        ) % WIFI_SEQUENCE_MODULUS
        return WifiBlockAckReorderPlan(
            WIFI_BLOCK_ACK_ADVANCE_WINDOW,
            window_start,
            next_start,
            window_size - 1,
        )
    return WifiBlockAckReorderPlan(
        WIFI_BLOCK_ACK_OLD,
        window_start,
        window_start,
        -1,
    )


struct WifiAMSDUPlan(Movable):
    """Offsets, non-final padding, and total length for one A-MSDU."""

    var subframe_header_offsets: List[Int]
    var msdu_offsets: List[Int]
    var padding_octets: List[Int]
    var total_octets: Int

    def __init__(
        out self,
        var subframe_header_offsets: List[Int],
        var msdu_offsets: List[Int],
        var padding_octets: List[Int],
        total_octets: Int,
    ):
        self.subframe_header_offsets = subframe_header_offsets^
        self.msdu_offsets = msdu_offsets^
        self.padding_octets = padding_octets^
        self.total_octets = total_octets


def _validate_maximum_amsdu_octets(maximum_amsdu_octets: Int) raises:
    if (
        maximum_amsdu_octets != 3839
        and maximum_amsdu_octets != 7935
        and maximum_amsdu_octets != 11454
    ):
        raise Error("maximum A-MSDU length must be 3839, 7935, or 11454 octets")


def wifi_amsdu_plan(
    msdu_lengths: Span[Int, ...], maximum_amsdu_octets: Int,
) raises -> WifiAMSDUPlan:
    """Plan the 14-octet headers and 0--3 octet non-final A-MSDU pads.

    Each MSDU length uses the standard 0--2304-octet field domain.  Padding
    makes every non-final subframe a multiple of four octets; the last
    subframe has no aggregate padding.
    """
    _validate_maximum_amsdu_octets(maximum_amsdu_octets)
    if len(msdu_lengths) == 0:
        raise Error("an A-MSDU plan needs at least one subframe")
    var header_offsets = List[Int](capacity=len(msdu_lengths))
    var msdu_offsets = List[Int](capacity=len(msdu_lengths))
    var padding_octets = List[Int](capacity=len(msdu_lengths))
    var total = 0
    for index in range(len(msdu_lengths)):
        var msdu_length = msdu_lengths[index]
        if msdu_length < 0 or msdu_length > 2304:
            raise Error("A-MSDU subframe length must be in [0,2304]")
        header_offsets.append(total)
        msdu_offsets.append(
            _checked_nonnegative_add(
                total,
                WIFI_AMSDU_SUBFRAME_HEADER_OCTETS,
                "A-MSDU payload offset",
            )
        )
        var subframe_octets = _checked_nonnegative_add(
            WIFI_AMSDU_SUBFRAME_HEADER_OCTETS,
            msdu_length,
            "A-MSDU subframe length",
        )
        var padding = 0
        if index + 1 != len(msdu_lengths):
            padding = (4 - subframe_octets % 4) % 4
        total = _checked_nonnegative_add(
            total, subframe_octets, "A-MSDU aggregate length"
        )
        total = _checked_nonnegative_add(
            total, padding, "A-MSDU aggregate padding"
        )
        if total > maximum_amsdu_octets:
            raise Error("A-MSDU plan exceeds the declared maximum length")
        padding_octets.append(padding)
    return WifiAMSDUPlan(
        header_offsets^, msdu_offsets^, padding_octets^, total
    )


struct WifiAMPDUPlan(Movable):
    """Delimiter offsets/length fields, pads, and total A-MPDU length."""

    var delimiter_offsets: List[Int]
    var mpdu_offsets: List[Int]
    var padding_octets: List[Int]
    var delimiter_length_low_12: List[Int]
    var delimiter_length_high_2: List[Int]
    var maximum_octets: Int
    var total_octets: Int

    def __init__(
        out self,
        var delimiter_offsets: List[Int],
        var mpdu_offsets: List[Int],
        var padding_octets: List[Int],
        var delimiter_length_low_12: List[Int],
        var delimiter_length_high_2: List[Int],
        maximum_octets: Int,
        total_octets: Int,
    ):
        self.delimiter_offsets = delimiter_offsets^
        self.mpdu_offsets = mpdu_offsets^
        self.padding_octets = padding_octets^
        self.delimiter_length_low_12 = delimiter_length_low_12^
        self.delimiter_length_high_2 = delimiter_length_high_2^
        self.maximum_octets = maximum_octets
        self.total_octets = total_octets


def wifi_ampdu_maximum_octets(maximum_length_exponent: Int) raises -> Int:
    """Return ``2^(13 + exponent) - 1`` for exponent values 0--7."""
    if maximum_length_exponent < 0 or maximum_length_exponent > 7:
        raise Error("maximum A-MPDU length exponent must be in [0,7]")
    return (1 << (13 + maximum_length_exponent)) - 1


def wifi_ampdu_plan(
    mpdu_lengths: Span[Int, ...], maximum_length_exponent: Int,
) raises -> WifiAMPDUPlan:
    """Plan non-null A-MPDU delimiters, length fields, padding, and offsets.

    Each planned MPDU is 1--11454 octets.  The four-octet delimiter and 0--3
    octets of non-final padding are included in ``total_octets``.  The low 12
    and high two MPDU-length bits are exposed for independent delimiter
    serialization; delimiter CRC calculation and EOF/null padding delimiters
    remain outside this non-null aggregate planner.
    """
    var maximum_octets = wifi_ampdu_maximum_octets(maximum_length_exponent)
    if len(mpdu_lengths) == 0:
        raise Error("an A-MPDU plan needs at least one non-null MPDU")
    var delimiter_offsets = List[Int](capacity=len(mpdu_lengths))
    var mpdu_offsets = List[Int](capacity=len(mpdu_lengths))
    var padding_octets = List[Int](capacity=len(mpdu_lengths))
    var length_low = List[Int](capacity=len(mpdu_lengths))
    var length_high = List[Int](capacity=len(mpdu_lengths))
    var total = 0
    for index in range(len(mpdu_lengths)):
        var mpdu_length = mpdu_lengths[index]
        if mpdu_length < 1 or mpdu_length > 11454:
            raise Error("planned MPDU length must be in [1,11454]")
        delimiter_offsets.append(total)
        mpdu_offsets.append(
            _checked_nonnegative_add(
                total,
                WIFI_AMPDU_DELIMITER_OCTETS,
                "A-MPDU payload offset",
            )
        )
        length_low.append(mpdu_length & 0xFFF)
        length_high.append((mpdu_length >> 12) & 3)
        var subframe_octets = _checked_nonnegative_add(
            WIFI_AMPDU_DELIMITER_OCTETS,
            mpdu_length,
            "A-MPDU subframe length",
        )
        var padding = 0
        if index + 1 != len(mpdu_lengths):
            padding = (4 - mpdu_length % 4) % 4
        total = _checked_nonnegative_add(
            total, subframe_octets, "A-MPDU aggregate length"
        )
        total = _checked_nonnegative_add(
            total, padding, "A-MPDU aggregate padding"
        )
        if total > maximum_octets:
            raise Error("A-MPDU plan exceeds the exponent-derived maximum")
        padding_octets.append(padding)
    return WifiAMPDUPlan(
        delimiter_offsets^,
        mpdu_offsets^,
        padding_octets^,
        length_low^,
        length_high^,
        maximum_octets,
        total,
    )
