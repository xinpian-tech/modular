"""Bounded Rel-16 NR-U channel-access arithmetic for CPU references.

This module implements the finite, decoded-configuration portion of the
PCG-approved ``NR_unlic`` Work Item (UID 820067, WID RP-201834).  The exact
baseline is 3GPP TS 37.213 V16.14.0 clauses 4.1.1, 4.1.4.3, 4.2.1.1 and
4.2.2.3: downlink/uplink channel-access priority-class tables, Type-1 defer
duration, contention-window validation and advancement, explicit backoff
draw/countdown arithmetic, maximum-window reset, and channel-occupancy limits.
The UL priority-3/4 Note-2 extension from 6 ms to 8 ms is represented with
caller-decoded inserted-gap geometry.

Random-number generation, RF energy detection and idle/busy classification,
HARQ feedback interpretation, regulatory policy, traffic-to-priority mapping,
commercial scheduling, waveform generation, and complete channel-access state
machines remain outside this bounded layer.  All timing is integral
microseconds, so non-finite floating-point inputs do not exist at this API
boundary.
"""


comptime NR_U_REL16_DOWNLINK = 0
comptime NR_U_REL16_UPLINK = 1


def _validate_direction_and_priority(
    direction: Int, priority_class: Int,
) raises:
    if direction != NR_U_REL16_DOWNLINK and direction != NR_U_REL16_UPLINK:
        raise Error("NR-U channel-access direction must be downlink or uplink")
    if priority_class < 1 or priority_class > 4:
        raise Error("NR-U channel-access priority class must be in 1..4")


def _expected_defer_slot_count(
    direction: Int, priority_class: Int,
) raises -> Int:
    _validate_direction_and_priority(direction, priority_class)
    if priority_class == 4:
        return 7
    if priority_class == 3:
        return 3
    if direction == NR_U_REL16_UPLINK:
        return 2
    return 1


def _expected_cw_min(priority_class: Int) raises -> Int:
    _validate_direction_and_priority(NR_U_REL16_DOWNLINK, priority_class)
    return 3 if priority_class == 1 else 7 if priority_class == 2 else 15


def _expected_cw_max(direction: Int, priority_class: Int) raises -> Int:
    _validate_direction_and_priority(direction, priority_class)
    if priority_class == 1:
        return 7
    if priority_class == 2:
        return 15
    if direction == NR_U_REL16_DOWNLINK and priority_class == 3:
        return 63
    return 1023


def _expected_maximum_cot_us(
    direction: Int,
    priority_class: Int,
    other_technology_absent: Bool,
) raises -> Int:
    _validate_direction_and_priority(direction, priority_class)
    if direction == NR_U_REL16_DOWNLINK:
        if priority_class == 1:
            return 2000
        if priority_class == 2:
            return 3000
        return 10000 if other_technology_absent else 8000
    if priority_class == 1:
        return 2000
    if priority_class == 2:
        return 4000
    return 10000 if other_technology_absent else 6000


struct NRURel16PriorityClass(Copyable, Movable):
    """One mutable decoded TS 37.213 channel-access priority-class row.

    ``defer_slot_count`` is :math:`m_p`, not the total number of sensing
    slots in ``T_d``.  Public consumers revalidate every field so caller
    mutation cannot escape the exact table profile.
    """

    var direction: Int
    var priority_class: Int
    var other_technology_absent: Bool
    var defer_slot_count: Int
    var cw_min: Int
    var cw_max: Int
    var maximum_channel_occupancy_us: Int

    def __init__(
        out self,
        direction: Int,
        priority_class: Int,
        other_technology_absent: Bool,
        defer_slot_count: Int,
        cw_min: Int,
        cw_max: Int,
        maximum_channel_occupancy_us: Int,
    ) raises:
        self.direction = direction
        self.priority_class = priority_class
        self.other_technology_absent = other_technology_absent
        self.defer_slot_count = defer_slot_count
        self.cw_min = cw_min
        self.cw_max = cw_max
        self.maximum_channel_occupancy_us = maximum_channel_occupancy_us
        self.validate()

    def validate(self) raises:
        """Revalidate this public mutable record against the exact CAPC row."""
        _validate_direction_and_priority(self.direction, self.priority_class)
        if (
            self.defer_slot_count
            != _expected_defer_slot_count(
                self.direction, self.priority_class
            )
            or self.cw_min != _expected_cw_min(self.priority_class)
            or self.cw_max
            != _expected_cw_max(self.direction, self.priority_class)
            or self.maximum_channel_occupancy_us
            != _expected_maximum_cot_us(
                self.direction,
                self.priority_class,
                self.other_technology_absent,
            )
        ):
            raise Error("mutated NR-U priority-class record is not standardized")


struct NRURel16ContentionWindowState(Copyable, Movable):
    """Current CW and consecutive uses of ``CWmax`` for ``N_init`` draws."""

    var contention_window: Int
    var consecutive_maximum_draws: Int

    def __init__(
        out self, contention_window: Int, consecutive_maximum_draws: Int,
    ):
        self.contention_window = contention_window
        self.consecutive_maximum_draws = consecutive_maximum_draws

    def validate(self, profile: NRURel16PriorityClass) raises:
        """Revalidate mutable state for the supplied exact priority profile."""
        profile.validate()
        if not nr_u_rel16_contention_window_allowed(
            profile, self.contention_window
        ):
            raise Error("NR-U contention-window state is not an allowed size")
        if (
            self.consecutive_maximum_draws < 0
            or self.consecutive_maximum_draws > 7
            or (
                self.contention_window != profile.cw_max
                and self.consecutive_maximum_draws != 0
            )
        ):
            raise Error("invalid consecutive CWmax draw state")


def nr_u_rel16_priority_class(
    direction: Int,
    priority_class: Int,
    other_technology_absent: Bool = False,
) raises -> NRURel16PriorityClass:
    """Return an exact Rel-16 DL or UL CAPC row.

    ``other_technology_absent`` explicitly selects the alternative p=3/4
    maximum COT defined by the standard.  For DL it represents the caller's
    long-term absence guarantee; for UL it represents presence of the
    ``absenceOfAnyOtherTechnology-r14/r16`` higher-layer parameter.  Neither
    condition is inferred from RF or regulatory state.
    """
    _validate_direction_and_priority(direction, priority_class)
    return NRURel16PriorityClass(
        direction,
        priority_class,
        other_technology_absent,
        _expected_defer_slot_count(direction, priority_class),
        _expected_cw_min(priority_class),
        _expected_cw_max(direction, priority_class),
        _expected_maximum_cot_us(
            direction, priority_class, other_technology_absent
        ),
    )


def nr_u_rel16_defer_duration_us(
    profile: NRURel16PriorityClass,
) raises -> Int:
    """Return ``T_d = 16 + m_p * 9`` integral microseconds."""
    profile.validate()
    return 16 + profile.defer_slot_count * 9


def nr_u_rel16_contention_window_allowed(
    profile: NRURel16PriorityClass, contention_window: Int,
) raises -> Bool:
    """Return whether ``CW`` is one of the row's listed ``2^n-1`` sizes."""
    profile.validate()
    if (
        contention_window < profile.cw_min
        or contention_window > profile.cw_max
    ):
        return False
    return (contention_window & (contention_window + 1)) == 0


def nr_u_rel16_backoff_draw(
    profile: NRURel16PriorityClass,
    contention_window: Int,
    random_draw: Int,
) raises -> Int:
    """Validate and return a caller-supplied ``N_init`` candidate in ``[0,CW]``.

    The API deliberately does not hide a pseudo-random generator, enabling
    deterministic replay.  Uniform generation and distribution validation
    remain caller-owned.
    """
    if not nr_u_rel16_contention_window_allowed(profile, contention_window):
        raise Error("backoff draw requires an allowed contention window")
    if random_draw < 0 or random_draw > contention_window:
        raise Error("NR-U backoff draw must be in the inclusive CW range")
    return random_draw


def nr_u_rel16_backoff_after_decrements(
    profile: NRURel16PriorityClass,
    contention_window: Int,
    initial_backoff: Int,
    decrement_count: Int,
) raises -> Int:
    """Apply explicit Type-1 counter decrements through the zero boundary.

    The caller supplies only decrements already authorized by the clause
    4.1.1/4.2.1.1 sensing procedure.  Busy/idle sensing and the optional
    choice not to decrement remain external.  A count larger than ``N_init``
    is rejected because the procedure no longer decrements after reaching
    zero.
    """
    _ = nr_u_rel16_backoff_draw(
        profile, contention_window, initial_backoff
    )
    if decrement_count < 0:
        raise Error("NR-U backoff decrement count must be nonnegative")
    if decrement_count > initial_backoff:
        raise Error("NR-U backoff cannot decrement after reaching zero")
    return initial_backoff - decrement_count


def nr_u_rel16_next_higher_contention_window(
    profile: NRURel16PriorityClass, current_window: Int,
) raises -> Int:
    """Return the next listed CW size, saturating exactly at ``CWmax``."""
    if not nr_u_rel16_contention_window_allowed(profile, current_window):
        raise Error("current NR-U contention window is not allowed")
    if current_window == profile.cw_max:
        return current_window
    # The exact tables cap CW at 1023, so 2*CW+1 cannot overflow Int.
    return 2 * current_window + 1


def nr_u_rel16_record_contention_window_draw(
    profile: NRURel16PriorityClass,
    state: NRURel16ContentionWindowState,
    maximum_draw_reset_count: Int,
) raises -> NRURel16ContentionWindowState:
    """Record one ``N_init`` generation and apply the normative CWmax reset.

    ``maximum_draw_reset_count`` is the independently selected ``K`` in 1..8.
    A draw below CWmax breaks the consecutive-CWmax streak.  The K-th
    consecutive draw at CWmax resets only this priority class to CWmin.
    """
    state.validate(profile)
    if maximum_draw_reset_count < 1 or maximum_draw_reset_count > 8:
        raise Error("NR-U maximum-CW reset count K must be in 1..8")
    if (
        state.contention_window == profile.cw_max
        and state.consecutive_maximum_draws >= maximum_draw_reset_count
    ):
        raise Error("NR-U consecutive CWmax state must be smaller than K")
    if state.contention_window != profile.cw_max:
        return NRURel16ContentionWindowState(state.contention_window, 0)
    var next_count = state.consecutive_maximum_draws + 1
    if next_count >= maximum_draw_reset_count:
        return NRURel16ContentionWindowState(profile.cw_min, 0)
    return NRURel16ContentionWindowState(profile.cw_max, next_count)


def nr_u_rel16_channel_occupancy_allowed(
    profile: NRURel16PriorityClass,
    occupancy_duration_us: Int,
    first_inserted_gap_start_us: Int = -1,
    minimum_inserted_gap_duration_us: Int = 0,
) raises -> Bool:
    """Return whether decoded Type-1 COT geometry satisfies the CAPC row.

    Only the default ``(-1, 0)`` gap arguments apply to the ordinary table
    maximum.  For UL priority classes 3 and 4 whose table maximum is 6 ms,
    Note 2 permits an aggregate interval strictly above 6 ms and up to 8 ms
    when one or more gaps are inserted.  The caller supplies the first gap
    start and the minimum duration across all inserted gaps; every gap must be
    at least 100 us, and the first gap must begin no later than 6 ms into the
    interval.  The aggregate interval here includes the inserted gaps.  RF
    sensing and gap discovery remain external.
    """
    profile.validate()
    if occupancy_duration_us < 0:
        raise Error("NR-U channel occupancy duration must be nonnegative")
    if first_inserted_gap_start_us < -1:
        raise Error("NR-U inserted-gap start must be -1 or nonnegative")
    if minimum_inserted_gap_duration_us < 0:
        raise Error("NR-U inserted-gap duration must be nonnegative")
    if first_inserted_gap_start_us == -1:
        if minimum_inserted_gap_duration_us != 0:
            raise Error("NR-U gap duration requires a declared gap start")
        return occupancy_duration_us <= profile.maximum_channel_occupancy_us
    if minimum_inserted_gap_duration_us == 0:
        raise Error("NR-U declared gap requires a positive duration")
    if occupancy_duration_us <= profile.maximum_channel_occupancy_us:
        # Non-default gap geometry belongs exclusively to the Note-2 extension
        # below.  Accepting it here would silently apply that bounded helper to
        # DL, p=1/2, absence-profile, or non-extended nominal occupancies.
        return False
    if (
        profile.direction != NR_U_REL16_UPLINK
        or profile.priority_class < 3
        or profile.other_technology_absent
        or profile.maximum_channel_occupancy_us != 6000
        or occupancy_duration_us > 8000
        or first_inserted_gap_start_us > 6000
        or minimum_inserted_gap_duration_us < 100
        or first_inserted_gap_start_us >= occupancy_duration_us
    ):
        return False
    return (
        minimum_inserted_gap_duration_us
        < occupancy_duration_us - first_inserted_gap_start_us
    )
