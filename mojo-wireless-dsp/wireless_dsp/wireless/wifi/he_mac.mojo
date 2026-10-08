"""Deterministic High Efficiency (HE) MAC reference algorithms.

This CPU-only module implements a bounded subset of IEEE Std 802.11-2024:
the two-NAV rules in 26.2.4, CF-End truncation decisions in 26.2.5, the HE
TXOP_DURATION representation used by those rules, and Trigger-frame User
Info/RU allocation arithmetic from 9.3.1.22 and Tables 9-52--9-53.  The
normative publication is IEEE Std
802.11-2024, DOI 10.1109/IEEESTD.2025.10979691.

Inputs are already classified MAC/PHY metadata.  BSS classification
(26.2.2), frame parsing/FCS, carrier sensing, UORA contention, MU-EDCA,
spatial reuse, RU-tone placement, MCS/DCM/NSS rules, and AP scheduling policy
are outside this module.  All time values are integral microseconds and all
discrete results have exact (zero) tolerance.
"""


comptime WIFI_HE_BSS_INTRA = 0
comptime WIFI_HE_BSS_INTER = 1
comptime WIFI_HE_BSS_UNCLASSIFIED = 2

comptime WIFI_HE_NAV_SOURCE_NONE = -1
comptime WIFI_HE_NAV_UPDATED_NONE = 0
comptime WIFI_HE_NAV_UPDATED_INTRA_BSS = 1
comptime WIFI_HE_NAV_UPDATED_BASIC = 2

comptime WIFI_HE_RU_SEGMENT_PRIMARY_80 = 0
comptime WIFI_HE_RU_SEGMENT_SECONDARY_80 = 1
comptime WIFI_HE_RU_SEGMENT_BOTH_80 = 2

comptime WIFI_HE_TRIGGER_USER_ASSOCIATED_RANDOM_ACCESS = 0
comptime WIFI_HE_TRIGGER_USER_ASSOCIATED = 1
comptime WIFI_HE_TRIGGER_USER_UNASSOCIATED_RANDOM_ACCESS = 2
comptime WIFI_HE_TRIGGER_USER_UNALLOCATED = 3


struct WifiHeMacProfile(ImplicitlyCopyable):
    """Mutable HE capability/profile boundary used by every public API.

    A non-AP HE STA is required by 26.2.4 to maintain two NAVs.  An HE AP can
    set ``maintains_two_nav`` to false because AP two-NAV support is optional,
    but the dual-NAV APIs then reject that profile.  ``ul_bandwidth_mhz`` is
    one of 20, 40, 80, or 160; ``is_80_plus_80`` distinguishes the published
    noncontiguous 160-MHz profile.  Every call revalidates mutable fields.
    """

    var is_access_point: Bool
    var maintains_two_nav: Bool
    var ul_bandwidth_mhz: Int
    var is_80_plus_80: Bool

    def __init__(
        out self,
        is_access_point: Bool,
        maintains_two_nav: Bool,
        ul_bandwidth_mhz: Int,
        is_80_plus_80: Bool = False,
    ):
        self.is_access_point = is_access_point
        self.maintains_two_nav = maintains_two_nav
        self.ul_bandwidth_mhz = ul_bandwidth_mhz
        self.is_80_plus_80 = is_80_plus_80


struct WifiHeDualNavState(ImplicitlyCopyable):
    """Absolute intra-BSS/basic NAV end times and basic-NAV provenance."""

    var intra_bss_nav_end_us: Int
    var basic_nav_end_us: Int
    var basic_nav_source: Int

    def __init__(
        out self,
        intra_bss_nav_end_us: Int = 0,
        basic_nav_end_us: Int = 0,
        basic_nav_source: Int = WIFI_HE_NAV_SOURCE_NONE,
    ):
        self.intra_bss_nav_end_us = intra_bss_nav_end_us
        self.basic_nav_end_us = basic_nav_end_us
        self.basic_nav_source = basic_nav_source


struct WifiHeDualNavUpdate(ImplicitlyCopyable):
    """Next dual-NAV state and the NAV selected for an actual update."""

    var state: WifiHeDualNavState
    var updated_nav: Int

    def __init__(
        out self, state: WifiHeDualNavState, updated_nav: Int,
    ):
        self.state = state
        self.updated_nav = updated_nav


struct WifiHeDualNavRemaining(ImplicitlyCopyable):
    """Remaining two-NAV timers and their virtual-carrier-sense result."""

    var intra_bss_us: Int
    var basic_us: Int
    var medium_busy: Bool

    def __init__(
        out self, intra_bss_us: Int, basic_us: Int, medium_busy: Bool,
    ):
        self.intra_bss_us = intra_bss_us
        self.basic_us = basic_us
        self.medium_busy = medium_busy


struct WifiHeCfEndResetDecision(ImplicitlyCopyable):
    """Recommended CF-End reset(s) and the optional reset-both permission."""

    var reset_intra_bss_nav: Bool
    var reset_basic_nav: Bool
    var reset_both_permitted: Bool

    def __init__(
        out self,
        reset_intra_bss_nav: Bool,
        reset_basic_nav: Bool,
        reset_both_permitted: Bool,
    ):
        self.reset_intra_bss_nav = reset_intra_bss_nav
        self.reset_basic_nav = reset_basic_nav
        self.reset_both_permitted = reset_both_permitted


struct WifiHeDualNavReset(ImplicitlyCopyable):
    """State after a selected reset and whether PHY-CCARESET is required."""

    var state: WifiHeDualNavState
    var phy_cca_reset_required: Bool

    def __init__(
        out self,
        state: WifiHeDualNavState,
        phy_cca_reset_required: Bool,
    ):
        self.state = state
        self.phy_cca_reset_required = phy_cca_reset_required


struct WifiHeTxopDuration(ImplicitlyCopyable):
    """Decoded seven-bit HE TXOP_DURATION value."""

    var specified: Bool
    var duration_us: Int

    def __init__(out self, specified: Bool, duration_us: Int):
        self.specified = specified
        self.duration_us = duration_us


struct WifiHeTriggerRuAllocation(ImplicitlyCopyable):
    """Decoded Trigger User Info RU size, one-based index, and 80-MHz segment."""

    var ru_tones: Int
    var ru_index: Int
    var segment_80: Int
    var allocation: Int

    def __init__(
        out self,
        ru_tones: Int,
        ru_index: Int,
        segment_80: Int,
        allocation: Int,
    ):
        self.ru_tones = ru_tones
        self.ru_index = ru_index
        self.segment_80 = segment_80
        self.allocation = allocation


struct WifiHeTriggerUserAllocationPlan(ImplicitlyCopyable):
    """Validated addressed/random-access User Info RU interval."""

    var user_kind: Int
    var first_ru: WifiHeTriggerRuAllocation
    var number_of_rus: Int
    var last_ru_index: Int
    var last_ru_allocation: Int

    def __init__(
        out self,
        user_kind: Int,
        first_ru: WifiHeTriggerRuAllocation,
        number_of_rus: Int,
        last_ru_index: Int,
        last_ru_allocation: Int,
    ):
        self.user_kind = user_kind
        self.first_ru = first_ru
        self.number_of_rus = number_of_rus
        self.last_ru_index = last_ru_index
        self.last_ru_allocation = last_ru_allocation


def _validate_profile(profile: WifiHeMacProfile) raises:
    if (
        profile.ul_bandwidth_mhz != 20
        and profile.ul_bandwidth_mhz != 40
        and profile.ul_bandwidth_mhz != 80
        and profile.ul_bandwidth_mhz != 160
    ):
        raise Error("HE UL bandwidth must be 20, 40, 80, or 160 MHz")
    if profile.is_80_plus_80 and profile.ul_bandwidth_mhz != 160:
        raise Error("80+80 MHz is a noncontiguous 160-MHz HE profile")
    if not profile.is_access_point and not profile.maintains_two_nav:
        raise Error("a non-AP HE STA is required to maintain two NAVs")


def _require_two_nav(profile: WifiHeMacProfile) raises:
    _validate_profile(profile)
    if not profile.maintains_two_nav:
        raise Error("this HE AP profile does not enable optional two-NAV operation")


def _validate_classification(classification: Int) raises:
    if (
        classification != WIFI_HE_BSS_INTRA
        and classification != WIFI_HE_BSS_INTER
        and classification != WIFI_HE_BSS_UNCLASSIFIED
    ):
        raise Error("HE PPDU classification must be intra/inter/unclassified")


def _validate_nav_state(state: WifiHeDualNavState) raises:
    if state.intra_bss_nav_end_us < 0 or state.basic_nav_end_us < 0:
        raise Error("HE NAV end times must be non-negative")
    if state.basic_nav_end_us == 0:
        if state.basic_nav_source != WIFI_HE_NAV_SOURCE_NONE:
            raise Error("a zero basic NAV must have no update provenance")
    elif (
        state.basic_nav_source != WIFI_HE_BSS_INTER
        and state.basic_nav_source != WIFI_HE_BSS_UNCLASSIFIED
    ):
        raise Error("a basic NAV source must be inter-BSS or unclassified")


def _copy_nav_state(state: WifiHeDualNavState) -> WifiHeDualNavState:
    return WifiHeDualNavState(
        state.intra_bss_nav_end_us,
        state.basic_nav_end_us,
        state.basic_nav_source,
    )


def _remaining_at(nav_end_us: Int, now_us: Int) -> Int:
    return nav_end_us - now_us if nav_end_us > now_us else 0


def _checked_end_time(base_us: Int, duration_us: Int) raises -> Int:
    var wide = Int128(base_us) + Int128(duration_us)
    if wide > Int128(Int.MAX):
        raise Error("HE NAV end time exceeds Int")
    return Int(wide)


def wifi_he_txop_duration_decode(txop_subfield: Int) raises -> WifiHeTxopDuration:
    """Decode the seven-bit HE-SIG-A TXOP subfield exactly.

    The all-ones value is UNSPECIFIED.  Other values decode to either
    ``8 * B1-B6`` or ``512 + 128 * B1-B6`` microseconds as specified by the
    HE TXOP_DURATION TXVECTOR/RXVECTOR table.
    """
    if txop_subfield < 0 or txop_subfield > 127:
        raise Error("HE TXOP subfield must be seven bits")
    if txop_subfield == 127:
        return WifiHeTxopDuration(False, 0)
    var magnitude = txop_subfield >> 1
    if (txop_subfield & 1) == 0:
        return WifiHeTxopDuration(True, 8 * magnitude)
    return WifiHeTxopDuration(True, 512 + 128 * magnitude)


def wifi_he_txop_duration_encode(
    duration_us: Int, *, unspecified: Bool = False,
) raises -> Int:
    """Encode an HE TXVECTOR TXOP duration, using normative floor quantization.

    ``duration_us`` is in the published 0--8448 microsecond domain.  The
    UNSPECIFIED representation is selected explicitly and requires a zero
    normalized duration so stale data cannot cross the API boundary.
    """
    if unspecified:
        if duration_us != 0:
            raise Error("UNSPECIFIED HE TXOP duration requires zero input")
        return 127
    if duration_us < 0 or duration_us > 8448:
        raise Error("HE TXOP duration must be in [0,8448] us")
    if duration_us < 512:
        return 2 * (duration_us // 8)
    return 1 + 2 * ((duration_us - 512) // 128)


def wifi_he_dual_nav_update_from_frame(
    profile: WifiHeMacProfile,
    state: WifiHeDualNavState,
    ppdu_expected_end_us: Int,
    duration_us: Int,
    classification: Int,
    *,
    receiver_address_is_self: Bool,
    sta_is_txop_holder: Bool,
    solicits_immediate_response: Bool,
    frame_is_trigger: Bool,
) raises -> WifiHeDualNavUpdate:
    """Apply the Clause-26.2.4 frame-duration two-NAV update decision.

    The caller supplies the already determined BSS classification and the
    expected PPDU end.  The intra-BSS three-way RA/TXOP/response exception is
    evaluated exactly; inter-BSS and unclassified frames can update only the
    basic NAV.  Duration/ID parsing is outside this normalized boundary.
    """
    _require_two_nav(profile)
    _validate_nav_state(state)
    _validate_classification(classification)
    if ppdu_expected_end_us < 0 or duration_us < 0 or duration_us > 32767:
        raise Error("invalid HE PPDU end or 15-bit duration information")

    var next = _copy_nav_state(state)
    if classification == WIFI_HE_BSS_INTRA:
        var current = _remaining_at(
            state.intra_bss_nav_end_us, ppdu_expected_end_us
        )
        var addressed_rule = (
            not receiver_address_is_self
            or (
                not sta_is_txop_holder
                and not solicits_immediate_response
            )
            or (not sta_is_txop_holder and frame_is_trigger)
        )
        if duration_us > current and addressed_rule:
            next.intra_bss_nav_end_us = _checked_end_time(
                ppdu_expected_end_us, duration_us
            )
            return WifiHeDualNavUpdate(
                next, WIFI_HE_NAV_UPDATED_INTRA_BSS
            )
        return WifiHeDualNavUpdate(next, WIFI_HE_NAV_UPDATED_NONE)

    var basic_current = _remaining_at(
        state.basic_nav_end_us, ppdu_expected_end_us
    )
    if duration_us > basic_current and not receiver_address_is_self:
        next.basic_nav_end_us = _checked_end_time(
            ppdu_expected_end_us, duration_us
        )
        next.basic_nav_source = classification
        return WifiHeDualNavUpdate(next, WIFI_HE_NAV_UPDATED_BASIC)
    return WifiHeDualNavUpdate(next, WIFI_HE_NAV_UPDATED_NONE)


def wifi_he_dual_nav_update_from_txop_subfield(
    profile: WifiHeMacProfile,
    state: WifiHeDualNavState,
    ppdu_expected_end_us: Int,
    txop_subfield: Int,
    classification: Int,
    *,
    sta_is_txop_holder: Bool,
    ppdu_has_duration_field: Bool,
) raises -> WifiHeDualNavUpdate:
    """Apply the Clause-26.2.4 RXVECTOR TXOP_DURATION update decision.

    UNSPECIFIED TXOP, a PSDU Duration field, and a TXOP-holder intra-BSS STA
    all suppress the corresponding update.  The seven-bit HE-SIG-A value is
    decoded internally so its 0--8448-us profile cannot be bypassed.
    """
    _require_two_nav(profile)
    _validate_nav_state(state)
    _validate_classification(classification)
    if ppdu_expected_end_us < 0:
        raise Error("HE PPDU end time must be non-negative")
    var decoded = wifi_he_txop_duration_decode(txop_subfield)
    if not decoded.specified or ppdu_has_duration_field:
        return WifiHeDualNavUpdate(
            _copy_nav_state(state), WIFI_HE_NAV_UPDATED_NONE
        )

    var next = _copy_nav_state(state)
    if classification == WIFI_HE_BSS_INTRA:
        var current = _remaining_at(
            state.intra_bss_nav_end_us, ppdu_expected_end_us
        )
        if not sta_is_txop_holder and decoded.duration_us > current:
            next.intra_bss_nav_end_us = _checked_end_time(
                ppdu_expected_end_us, decoded.duration_us
            )
            return WifiHeDualNavUpdate(
                next, WIFI_HE_NAV_UPDATED_INTRA_BSS
            )
        return WifiHeDualNavUpdate(next, WIFI_HE_NAV_UPDATED_NONE)

    var basic_current = _remaining_at(
        state.basic_nav_end_us, ppdu_expected_end_us
    )
    if decoded.duration_us > basic_current:
        next.basic_nav_end_us = _checked_end_time(
            ppdu_expected_end_us, decoded.duration_us
        )
        next.basic_nav_source = classification
        return WifiHeDualNavUpdate(next, WIFI_HE_NAV_UPDATED_BASIC)
    return WifiHeDualNavUpdate(next, WIFI_HE_NAV_UPDATED_NONE)


def wifi_he_dual_nav_remaining(
    profile: WifiHeMacProfile, state: WifiHeDualNavState, now_us: Int,
) raises -> WifiHeDualNavRemaining:
    """Return both remaining NAVs and the exact virtual-CS busy decision."""
    _require_two_nav(profile)
    _validate_nav_state(state)
    if now_us < 0:
        raise Error("HE NAV observation time must be non-negative")
    var intra = _remaining_at(state.intra_bss_nav_end_us, now_us)
    var basic = _remaining_at(state.basic_nav_end_us, now_us)
    return WifiHeDualNavRemaining(intra, basic, intra != 0 or basic != 0)


def wifi_he_cf_end_reset_decision(
    profile: WifiHeMacProfile,
    state: WifiHeDualNavState,
    cf_end_ppdu_end_us: Int,
    classification: Int,
) raises -> WifiHeCfEndResetDecision:
    """Return the Clause-26.2.5 CF-End reset recommendation/permission.

    An inter-BSS CF-End recommends basic-NAV reset; an intra-BSS CF-End
    recommends intra-BSS-NAV reset.  For an intra-BSS CF-End, reset of both
    is separately reported as permitted when the active basic NAV most
    recently came from an unclassified PPDU.  No policy chooses that option.
    """
    _require_two_nav(profile)
    _validate_nav_state(state)
    _validate_classification(classification)
    if cf_end_ppdu_end_us < 0:
        raise Error("CF-End PPDU end time must be non-negative")
    if classification == WIFI_HE_BSS_INTER:
        return WifiHeCfEndResetDecision(False, True, False)
    if classification == WIFI_HE_BSS_INTRA:
        var both_permitted = (
            state.basic_nav_source == WIFI_HE_BSS_UNCLASSIFIED
            and state.basic_nav_end_us > cf_end_ppdu_end_us
        )
        return WifiHeCfEndResetDecision(True, False, both_permitted)
    return WifiHeCfEndResetDecision(False, False, False)


def wifi_he_dual_nav_apply_reset(
    profile: WifiHeMacProfile,
    state: WifiHeDualNavState,
    reset_time_us: Int,
    *,
    reset_intra_bss_nav: Bool,
    reset_basic_nav: Bool,
) raises -> WifiHeDualNavReset:
    """Apply an externally authorized reset and decide PHY-CCARESET issuance.

    Clause 26.2.4 requires PHY-CCARESET when both NAV timers are zero after a
    reset.  Selection of a reset is supplied by a specific procedure such as
    CF-End or the RTS/MU-RTS timeout; this function does not invent policy.
    """
    _require_two_nav(profile)
    _validate_nav_state(state)
    if reset_time_us < 0:
        raise Error("HE NAV reset time must be non-negative")
    if not reset_intra_bss_nav and not reset_basic_nav:
        raise Error("at least one HE NAV must be selected for reset")

    var intra = state.intra_bss_nav_end_us
    var basic = state.basic_nav_end_us
    var source = state.basic_nav_source
    if reset_intra_bss_nav or intra <= reset_time_us:
        intra = 0
    if reset_basic_nav or basic <= reset_time_us:
        basic = 0
        source = WIFI_HE_NAV_SOURCE_NONE
    var next = WifiHeDualNavState(intra, basic, source)
    return WifiHeDualNavReset(next, intra == 0 and basic == 0)


def wifi_he_nav_reset_timeout_us(
    sifs_time_us: Int,
    cts_time_us: Int,
    rx_phy_start_delay_us: Int,
    slot_time_us: Int,
) raises -> Int:
    """Return ``2*SIFS + CTS_Time + RxPHYStartDelay + 2*slotTime``.

    This is the exact Clause-26.2.4 RTS/MU-RTS NAV reset observation window.
    Integer overflow is rejected before conversion to the platform ``Int``.
    """
    if (
        sifs_time_us < 0
        or cts_time_us <= 0
        or rx_phy_start_delay_us < 0
        or slot_time_us <= 0
    ):
        raise Error("invalid HE RTS NAV-reset timing parameter")
    var wide = (
        Int128(2) * Int128(sifs_time_us)
        + Int128(cts_time_us)
        + Int128(rx_phy_start_delay_us)
        + Int128(2) * Int128(slot_time_us)
    )
    if wide > Int128(Int.MAX):
        raise Error("HE RTS NAV-reset timeout exceeds Int")
    return Int(wide)


def _maximum_ru_index(
    profile: WifiHeMacProfile, ru_tones: Int,
) raises -> Int:
    var bandwidth = profile.ul_bandwidth_mhz
    if ru_tones == 26:
        return 9 if bandwidth == 20 else (18 if bandwidth == 40 else 37)
    if ru_tones == 52:
        return 4 if bandwidth == 20 else (8 if bandwidth == 40 else 16)
    if ru_tones == 106:
        return 2 if bandwidth == 20 else (4 if bandwidth == 40 else 8)
    if ru_tones == 242:
        return 1 if bandwidth == 20 else (2 if bandwidth == 40 else 4)
    if ru_tones == 484:
        return 1 if bandwidth == 40 else (2 if bandwidth >= 80 else 0)
    if ru_tones == 996:
        return 1 if bandwidth >= 80 else 0
    if ru_tones == 1992:
        return 1 if bandwidth == 160 else 0
    raise Error("unsupported HE Trigger RU size")


def wifi_he_trigger_ru_decode(
    profile: WifiHeMacProfile, allocation: Int,
) raises -> WifiHeTriggerRuAllocation:
    """Decode the eight-bit non-MU-RTS Trigger RU Allocation field.

    B7--B1 select the Table-9-53 RU size/index.  B0 is zero at 20/40/80
    MHz, selects the primary/secondary 80-MHz segment at 160 or 80+80 MHz,
    and is required to be one for the published 2x996-tone special case.
    Reserved and bandwidth-inapplicable encodings are rejected.
    """
    _validate_profile(profile)
    if allocation < 0 or allocation > 255:
        raise Error("HE Trigger RU Allocation must be eight bits")
    var code = allocation >> 1
    var b0 = allocation & 1
    if code > 68:
        raise Error("reserved HE Trigger RU Allocation encoding")
    if profile.ul_bandwidth_mhz < 160 and b0 != 0:
        raise Error("B0 must be zero below 160 MHz")

    if code == 68:
        if profile.ul_bandwidth_mhz != 160 or b0 != 1:
            raise Error("2x996-tone Trigger RU requires 160/80+80 MHz and B0=1")
        return WifiHeTriggerRuAllocation(
            1992, 1, WIFI_HE_RU_SEGMENT_BOTH_80, allocation
        )

    var tones: Int
    var index: Int
    if code <= 36:
        tones = 26
        index = code + 1
    elif code <= 52:
        tones = 52
        index = code - 36
    elif code <= 60:
        tones = 106
        index = code - 52
    elif code <= 64:
        tones = 242
        index = code - 60
    elif code <= 66:
        tones = 484
        index = code - 64
    else:
        tones = 996
        index = 1

    if index > _maximum_ru_index(profile, tones):
        raise Error("HE Trigger RU encoding is invalid for the UL bandwidth")
    var segment = WIFI_HE_RU_SEGMENT_PRIMARY_80
    if profile.ul_bandwidth_mhz == 160 and b0 == 1:
        segment = WIFI_HE_RU_SEGMENT_SECONDARY_80
    return WifiHeTriggerRuAllocation(tones, index, segment, allocation)


def wifi_he_trigger_ru_encode(
    profile: WifiHeMacProfile,
    ru_tones: Int,
    ru_index: Int,
    segment_80: Int = WIFI_HE_RU_SEGMENT_PRIMARY_80,
) raises -> Int:
    """Encode an exact Table-9-53 Trigger RU size/index/segment tuple."""
    _validate_profile(profile)
    var maximum = _maximum_ru_index(profile, ru_tones)
    if ru_index < 1 or ru_index > maximum:
        raise Error("HE Trigger RU index is outside the bandwidth profile")

    if ru_tones == 1992:
        if segment_80 != WIFI_HE_RU_SEGMENT_BOTH_80:
            raise Error("2x996-tone RU must use the both-80-MHz segment tag")
        return 2 * 68 + 1
    if profile.ul_bandwidth_mhz == 160:
        if (
            segment_80 != WIFI_HE_RU_SEGMENT_PRIMARY_80
            and segment_80 != WIFI_HE_RU_SEGMENT_SECONDARY_80
        ):
            raise Error("160/80+80 RU must select one 80-MHz segment")
    elif segment_80 != WIFI_HE_RU_SEGMENT_PRIMARY_80:
        raise Error("HE RU below 160 MHz is in the primary segment")

    var code: Int
    if ru_tones == 26:
        code = ru_index - 1
    elif ru_tones == 52:
        code = 36 + ru_index
    elif ru_tones == 106:
        code = 52 + ru_index
    elif ru_tones == 242:
        code = 60 + ru_index
    elif ru_tones == 484:
        code = 64 + ru_index
    elif ru_tones == 996:
        code = 67
    else:
        raise Error("unsupported HE Trigger RU size")
    var b0 = 1 if segment_80 == WIFI_HE_RU_SEGMENT_SECONDARY_80 else 0
    return 2 * code + b0


def wifi_he_trigger_user_allocation_plan(
    profile: WifiHeMacProfile,
    aid12: Int,
    first_ru_allocation: Int,
    *,
    number_of_ra_ru_field: Int = -1,
) raises -> WifiHeTriggerUserAllocationPlan:
    """Validate one Trigger User Info AID/RU interval without scheduling.

    AID12 values 0 and 2045 select associated/unassociated random access and
    require the five-bit Number Of RA-RU field (encoded count minus one).
    AIDs 1--2007 address one associated STA, while 2046 marks one unallocated
    RU; those normalized forms require ``number_of_ra_ru_field=-1`` because
    their B26--B31 bits are not the RA-RU Information subfield.  Reserved
    AIDs and padding marker 4095 are rejected.  Multiple RA-RUs must remain
    contiguous, equal-sized, and, in this declared bounded profile, within
    one 80-MHz segment; cross-segment RA-RU sequences are not represented.
    """
    _validate_profile(profile)
    var kind: Int
    var count: Int
    if aid12 == 0 or aid12 == 2045:
        if number_of_ra_ru_field < 0 or number_of_ra_ru_field > 31:
            raise Error("random-access User Info requires a five-bit RA-RU count")
        count = number_of_ra_ru_field + 1
        kind = (
            WIFI_HE_TRIGGER_USER_ASSOCIATED_RANDOM_ACCESS
            if aid12 == 0
            else WIFI_HE_TRIGGER_USER_UNASSOCIATED_RANDOM_ACCESS
        )
    elif aid12 >= 1 and aid12 <= 2007:
        if number_of_ra_ru_field != -1:
            raise Error("addressed User Info has SS Allocation, not RA-RU count")
        count = 1
        kind = WIFI_HE_TRIGGER_USER_ASSOCIATED
    elif aid12 == 2046:
        if number_of_ra_ru_field != -1:
            raise Error("unallocated User Info has no RA-RU count")
        count = 1
        kind = WIFI_HE_TRIGGER_USER_UNALLOCATED
    else:
        raise Error("reserved AID12 or padding marker is not a User allocation")

    var first = wifi_he_trigger_ru_decode(profile, first_ru_allocation)
    var maximum = _maximum_ru_index(profile, first.ru_tones)
    if count > maximum - first.ru_index + 1:
        raise Error("contiguous RA-RUs exceed the selected 80-MHz segment")
    var last_index = first.ru_index + count - 1
    var last_allocation = wifi_he_trigger_ru_encode(
        profile, first.ru_tones, last_index, first.segment_80
    )
    return WifiHeTriggerUserAllocationPlan(
        kind, first, count, last_index, last_allocation
    )
