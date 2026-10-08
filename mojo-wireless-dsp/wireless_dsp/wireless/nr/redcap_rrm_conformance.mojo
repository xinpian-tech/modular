"""Bounded Rel-17 RedCap RRM conformance timing verdicts.

3GPP TS 38.533 V17.9.0 (2023-12), clause 4, delegates every
requirement to TS 38.533 Release 18.  This CPU-only module therefore uses the
published Release-18 text in TS 38.533 V18.8.0 (2025-09), clauses 16, 17, and
18, without pretending that the empty Rel-17 clauses contain the test cases.
The official archives and their SHA-256 digests used for transcription are:

* ``38533-h90.zip``:
  ``16e2dd89f03f0e47c1c8622fcb757a0834ab2acd47074a4f6b8d03c70e8ff35a``;
* ``38533-i80.zip``:
  ``a3e801757755759b3bf210f9dbf9aed7769d8f5662b355a8513a5ca3b40b974a``.

The bounded table covers every timed response phase of seven representative
published tests: FR1 intra/inter-frequency cell reselection for one and two
Rx branches (16.1.1.1--16.1.1.4), FR2 intra/inter-frequency cell reselection
for two Rx branches (17.1.1.1--17.1.1.2), and E-UTRA-to-NR-FR1 connection
release with redirection for two Rx branches (18.2.2.1).  Limits are strict,
because each cited test says the response shall be *less than* its limit.

This is a single-iteration decision and finite-state timing reference.  It
does not generate RF, decode RRC, drive TTCN/test equipment, decide whether a
cell is detectable, reproduce statistical confidence stopping, or certify a
UE.  It also does not turn the underlying TS 38.133 timing formulas into a
claim of complete TS 38.533 conformance coverage.  An observation from a
non-target cell remains pending: the cited procedures define success when the
target cell responds before the limit and failure when that limit expires,
not an early terminal failure on an unrelated observation.
"""

from std.math import isfinite


comptime NR_REDCAP_RRM_CONFORMANCE_PROFILE_ORDINARY_NR = 0
comptime NR_REDCAP_RRM_CONFORMANCE_PROFILE_REDCAP_REL17 = 1
comptime NR_REDCAP_RRM_CONFORMANCE_PROFILE_EREDCAP_REL18 = 2

comptime NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR = 0
comptime NR_REDCAP_RRM_CONFORMANCE_SOURCE_EUTRA = 1

comptime NR_REDCAP_RRM_CONFORMANCE_FR1 = 1
comptime NR_REDCAP_RRM_CONFORMANCE_FR2 = 2

comptime NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_NEW = 0
comptime NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_ALREADY_DETECTED = 1
comptime NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_LOWER_PRIORITY = 2
comptime NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_HIGHER_PRIORITY = 3
comptime NR_REDCAP_RRM_CONFORMANCE_EVENT_EUTRA_TO_NR_REDIRECTION = 4

comptime NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1 = 1601111
comptime NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_2 = 1601112
comptime NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_3 = 1601113
comptime NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_4 = 1601114
comptime NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_1 = 1701111
comptime NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_2 = 1701112
comptime NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1 = 1802201

comptime NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING = 0
comptime NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS = 1
comptime NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE = 2

comptime NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE = 0
comptime NR_REDCAP_RRM_CONFORMANCE_STATE_AWAITING_NEXT_PHASE = 1
comptime NR_REDCAP_RRM_CONFORMANCE_STATE_PASSED = 2
comptime NR_REDCAP_RRM_CONFORMANCE_STATE_FAILED = 3


def _validate_rel17_profile(profile: Int) raises:
    if profile != NR_REDCAP_RRM_CONFORMANCE_PROFILE_REDCAP_REL17:
        raise Error("TS 38.533 RedCap conformance API requires Rel-17 RedCap")


def _case_phase_count(test_case: Int, profile: Int) raises -> Int:
    _validate_rel17_profile(profile)
    if (
        test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1
        or test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_2
        or test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_3
        or test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_4
        or test_case == NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_1
        or test_case == NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_2
    ):
        return 2
    if test_case == NR_REDCAP_RRM_CONFORMANCE_TC_18_2_2_1:
        return 1
    raise Error("unsupported bounded TS 38.533 RedCap test case")


struct _RowValues(ImplicitlyCopyable):
    var clause_major: Int
    var source_rat: Int
    var target_frequency_range: Int
    var rx_branches: Int
    var phase_count: Int
    var test_period: Int
    var event_kind: Int
    var expected_cell: Int
    var strict_limit_us: Int

    def __init__(
        out self,
        clause_major: Int,
        source_rat: Int,
        target_frequency_range: Int,
        rx_branches: Int,
        phase_count: Int,
        test_period: Int,
        event_kind: Int,
        expected_cell: Int,
        strict_limit_us: Int,
    ):
        self.clause_major = clause_major
        self.source_rat = source_rat
        self.target_frequency_range = target_frequency_range
        self.rx_branches = rx_branches
        self.phase_count = phase_count
        self.test_period = test_period
        self.event_kind = event_kind
        self.expected_cell = expected_cell
        self.strict_limit_us = strict_limit_us


def _row_values(test_case: Int, phase_index: Int, profile: Int) raises -> _RowValues:
    var phase_count = _case_phase_count(test_case, profile)
    if phase_index < 0 or phase_index >= phase_count:
        raise Error("TS 38.533 RedCap test phase index is out of range")

    if test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1 or (
        test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_2
    ):
        var rx = (
            1
            if test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_1
            else 2
        )
        if phase_index == 0:
            return _RowValues(
                16,
                NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR,
                NR_REDCAP_RRM_CONFORMANCE_FR1,
                rx,
                2,
                2,
                NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_NEW,
                2,
                34_000_000,
            )
        return _RowValues(
            16,
            NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR,
            NR_REDCAP_RRM_CONFORMANCE_FR1,
            rx,
            2,
            3,
            NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_ALREADY_DETECTED,
            1,
            8_000_000,
        )

    if test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_3 or (
        test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_4
    ):
        var rx = (
            1
            if test_case == NR_REDCAP_RRM_CONFORMANCE_TC_16_1_1_3
            else 2
        )
        if phase_index == 0:
            return _RowValues(
                16,
                NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR,
                NR_REDCAP_RRM_CONFORMANCE_FR1,
                rx,
                2,
                1,
                NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_LOWER_PRIORITY,
                1,
                8_000_000,
            )
        return _RowValues(
            16,
            NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR,
            NR_REDCAP_RRM_CONFORMANCE_FR1,
            rx,
            2,
            3,
            NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_HIGHER_PRIORITY,
            2,
            68_000_000,
        )

    if test_case == NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_1:
        if phase_index == 0:
            return _RowValues(
                17,
                NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR,
                NR_REDCAP_RRM_CONFORMANCE_FR2,
                2,
                2,
                2,
                NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_NEW,
                2,
                130_000_000,
            )
        return _RowValues(
            17,
            NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR,
            NR_REDCAP_RRM_CONFORMANCE_FR2,
            2,
            2,
            3,
            NR_REDCAP_RRM_CONFORMANCE_EVENT_INTRA_ALREADY_DETECTED,
            1,
            27_000_000,
        )

    if test_case == NR_REDCAP_RRM_CONFORMANCE_TC_17_1_1_2:
        if phase_index == 0:
            return _RowValues(
                17,
                NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR,
                NR_REDCAP_RRM_CONFORMANCE_FR2,
                2,
                2,
                1,
                NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_LOWER_PRIORITY,
                1,
                27_000_000,
            )
        return _RowValues(
            17,
            NR_REDCAP_RRM_CONFORMANCE_SOURCE_NR,
            NR_REDCAP_RRM_CONFORMANCE_FR2,
            2,
            2,
            3,
            NR_REDCAP_RRM_CONFORMANCE_EVENT_INTER_HIGHER_PRIORITY,
            2,
            87_000_000,
        )

    # The case validity and one-phase bound were established above, so this
    # is the literal 18.2.2.1 E-UTRA-to-NR-FR1 redirection row.
    return _RowValues(
        18,
        NR_REDCAP_RRM_CONFORMANCE_SOURCE_EUTRA,
        NR_REDCAP_RRM_CONFORMANCE_FR1,
        2,
        1,
        2,
        NR_REDCAP_RRM_CONFORMANCE_EVENT_EUTRA_TO_NR_REDIRECTION,
        2,
        2_240_000,
    )


struct NRRedCapRRMConformanceRow(ImplicitlyCopyable):
    """One exact response phase from the bounded TS 38.533 test set."""

    var profile: Int
    var test_case: Int
    var phase_index: Int
    var clause_major: Int
    var source_rat: Int
    var target_frequency_range: Int
    var rx_branches: Int
    var phase_count: Int
    var test_period: Int
    var event_kind: Int
    var expected_cell: Int
    var strict_limit_us: Int

    def __init__(
        out self,
        test_case: Int,
        phase_index: Int,
        *,
        profile: Int = NR_REDCAP_RRM_CONFORMANCE_PROFILE_REDCAP_REL17,
    ) raises:
        var expected = _row_values(test_case, phase_index, profile)
        self.profile = profile
        self.test_case = test_case
        self.phase_index = phase_index
        self.clause_major = expected.clause_major
        self.source_rat = expected.source_rat
        self.target_frequency_range = expected.target_frequency_range
        self.rx_branches = expected.rx_branches
        self.phase_count = expected.phase_count
        self.test_period = expected.test_period
        self.event_kind = expected.event_kind
        self.expected_cell = expected.expected_cell
        self.strict_limit_us = expected.strict_limit_us
        self.validate()

    def validate(self) raises:
        """Re-read the official row and reject every mutated public field."""
        var expected = _row_values(
            self.test_case, self.phase_index, self.profile
        )
        if self.clause_major != expected.clause_major or (
            self.source_rat != expected.source_rat
        ) or (
            self.target_frequency_range != expected.target_frequency_range
        ) or self.rx_branches != expected.rx_branches or (
            self.phase_count != expected.phase_count
        ) or self.test_period != expected.test_period or (
            self.event_kind != expected.event_kind
        ) or self.expected_cell != expected.expected_cell or (
            self.strict_limit_us != expected.strict_limit_us
        ):
            raise Error("mutated TS 38.533 RedCap conformance row")


def nr_redcap_rel17_rrm_conformance_row(
    test_case: Int,
    phase_index: Int,
    *,
    profile: Int = NR_REDCAP_RRM_CONFORMANCE_PROFILE_REDCAP_REL17,
) raises -> NRRedCapRRMConformanceRow:
    """Return one exact phase row from clauses 16.1, 17.1, or 18.2."""
    return NRRedCapRRMConformanceRow(
        test_case, phase_index, profile=profile
    )


def nr_redcap_rel17_rrm_conformance_delay_verdict(
    row: NRRedCapRRMConformanceRow,
    response_seen: Bool,
    observed_cell: Int,
    delay_ms: Float64,
) raises -> Int:
    """Classify one floating-millisecond observation against a strict row.

    This convenience boundary exists for conformance traces whose timestamps
    are decoded as floating milliseconds.  The state-machine API below uses
    integer microseconds for exact endpoint and overflow-safe timer handling.
    """
    row.validate()
    if not isfinite(delay_ms) or delay_ms < 0.0:
        raise Error("TS 38.533 RedCap observation delay must be finite and nonnegative")
    var limit_ms = Float64(row.strict_limit_us) / 1000.0
    if not response_seen:
        if observed_cell != -1:
            raise Error("an absent response cannot name an observed cell")
        return (
            NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE
            if delay_ms >= limit_ms
            else NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING
        )
    if observed_cell != 1 and observed_cell != 2:
        raise Error("observed RedCap conformance cell must be Cell 1 or Cell 2")
    if delay_ms >= limit_ms:
        return NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE
    return (
        NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS
        if observed_cell == row.expected_cell
        else NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING
    )


struct NRRedCapRRMConformanceState(ImplicitlyCopyable):
    """Finite state for sequential response phases of one bounded test case."""

    var profile: Int
    var test_case: Int
    var phase_index: Int
    var phase_count: Int
    var phase_started_us: Int
    var last_update_us: Int
    var state: Int
    var terminal_verdict: Int

    def __init__(
        out self,
        test_case: Int,
        phase_started_us: Int,
        *,
        profile: Int = NR_REDCAP_RRM_CONFORMANCE_PROFILE_REDCAP_REL17,
    ) raises:
        self.profile = profile
        self.test_case = test_case
        self.phase_index = 0
        self.phase_count = _case_phase_count(test_case, profile)
        self.phase_started_us = phase_started_us
        self.last_update_us = phase_started_us
        self.state = NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE
        self.terminal_verdict = NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING
        self.validate()

    def validate(self) raises:
        """Reject mutated profiles, phases, timestamps, or terminal state."""
        var expected_count = _case_phase_count(self.test_case, self.profile)
        if self.phase_count != expected_count:
            raise Error("mutated TS 38.533 RedCap conformance phase count")
        if self.last_update_us < 0:
            raise Error("TS 38.533 RedCap conformance time must be nonnegative")
        if self.state == NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE:
            if self.phase_index < 0 or self.phase_index >= self.phase_count:
                raise Error("active RedCap conformance phase is out of range")
            if self.phase_started_us < 0 or (
                self.last_update_us < self.phase_started_us
            ):
                raise Error("invalid active RedCap conformance time state")
            if self.terminal_verdict != (
                NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING
            ):
                raise Error("active RedCap conformance state has a verdict")
            var active_row = _row_values(
                self.test_case, self.phase_index, self.profile
            )
            if self.last_update_us - self.phase_started_us >= (
                active_row.strict_limit_us
            ):
                raise Error("expired RedCap conformance phase was not settled")
            return
        if self.phase_started_us != -1:
            raise Error("inactive RedCap conformance phase retains a start time")
        if self.state == (
            NR_REDCAP_RRM_CONFORMANCE_STATE_AWAITING_NEXT_PHASE
        ):
            if self.phase_index < 1 or self.phase_index >= self.phase_count or (
                self.terminal_verdict
                != NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING
            ):
                raise Error("invalid pending RedCap conformance phase state")
            _ = _row_values(self.test_case, self.phase_index, self.profile)
            return
        if self.state == NR_REDCAP_RRM_CONFORMANCE_STATE_PASSED:
            if self.phase_index != self.phase_count or (
                self.terminal_verdict
                != NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS
            ):
                raise Error("invalid passed RedCap conformance state")
            return
        if self.state == NR_REDCAP_RRM_CONFORMANCE_STATE_FAILED:
            if self.phase_index < 0 or self.phase_index >= self.phase_count or (
                self.terminal_verdict
                != NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE
            ):
                raise Error("invalid failed RedCap conformance state")
            return
        raise Error("invalid TS 38.533 RedCap conformance state tag")


def nr_redcap_rel17_rrm_conformance_update(
    mut state: NRRedCapRRMConformanceState,
    current_time_us: Int,
    response_seen: Bool,
    observed_cell: Int,
) raises -> Int:
    """Advance an active phase and return its exact single-iteration verdict.

    A response at exactly ``strict_limit_us`` is late.  Timer elapsed time is
    computed as ``current - start`` only after both are validated nonnegative
    and ordered, avoiding addition at ``Int.MAX`` and silent overflow.
    """
    state.validate()
    if state.state != NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE:
        raise Error("only an active RedCap conformance phase can be updated")
    if current_time_us < state.last_update_us:
        raise Error("RedCap conformance updates must be time ordered")
    if not response_seen and observed_cell != -1:
        raise Error("an absent response cannot name an observed cell")
    if response_seen and observed_cell != 1 and observed_cell != 2:
        raise Error("observed RedCap conformance cell must be Cell 1 or Cell 2")

    var next = state
    var row = nr_redcap_rel17_rrm_conformance_row(
        next.test_case, next.phase_index, profile=next.profile
    )
    var elapsed_us = current_time_us - next.phase_started_us
    var verdict = NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING
    if elapsed_us >= row.strict_limit_us:
        verdict = NR_REDCAP_RRM_CONFORMANCE_VERDICT_FAIL_LATE
    elif response_seen and observed_cell == row.expected_cell:
        verdict = NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS

    next.last_update_us = current_time_us
    if verdict == NR_REDCAP_RRM_CONFORMANCE_VERDICT_PASS:
        next.phase_index += 1
        next.phase_started_us = -1
        if next.phase_index == next.phase_count:
            next.state = NR_REDCAP_RRM_CONFORMANCE_STATE_PASSED
            next.terminal_verdict = verdict
        else:
            next.state = (
                NR_REDCAP_RRM_CONFORMANCE_STATE_AWAITING_NEXT_PHASE
            )
    elif verdict != NR_REDCAP_RRM_CONFORMANCE_VERDICT_PENDING:
        next.phase_started_us = -1
        next.state = NR_REDCAP_RRM_CONFORMANCE_STATE_FAILED
        next.terminal_verdict = verdict
    next.validate()
    state = next
    return verdict


def nr_redcap_rel17_rrm_conformance_start_next_phase(
    mut state: NRRedCapRRMConformanceState, phase_started_us: Int
) raises -> Int:
    """Bind the externally observed next T3 boundary and activate it.

    Every two-phase case in this bounded table moves from a T1 or T2 response
    phase to T3.  Broader TS 38.533 phase binding is not claimed.
    """
    state.validate()
    if state.state != (
        NR_REDCAP_RRM_CONFORMANCE_STATE_AWAITING_NEXT_PHASE
    ):
        raise Error("RedCap conformance state is not awaiting another phase")
    if phase_started_us < state.last_update_us:
        raise Error("next RedCap conformance phase cannot start in the past")
    var next = state
    next.phase_started_us = phase_started_us
    next.last_update_us = phase_started_us
    next.state = NR_REDCAP_RRM_CONFORMANCE_STATE_ACTIVE
    next.validate()
    state = next
    return state.state
