"""Bounded IEEE 802.11-2024 deterministic MAC state algorithms.

This CPU-only module implements the legacy non-DMG infrastructure
power-save calculations in IEEE Std 802.11-2024, 9.2.4.2, 9.3.1.5,
9.4.2.5.1, and 11.2.3.  The declared TIM profile is one conventional
non-S1G BSSID using Method A and association identifiers 1--2007.  The
declared STA profile is a non-QoS power-save STA without APSD, TWT, MLO,
TIM broadcast, or WNM sleep operation.  The normative publication is IEEE
Std 802.11-2024, DOI 10.1109/IEEESTD.2025.10979691.

The module validates and constructs canonical Partial Virtual Bitmaps,
advances DTIM state, identifies selected beacon TBTTs from an explicit
listen anchor, and exposes the deterministic TIM/PS-Poll decision.  Frame
parsing, TSF synchronization, beacon-loss recovery, channel access, actual
PS-Poll transmission, buffering, delivery ordering, and doze policy in the
presence of other awake causes are outside this normalized boundary.

HE intra-BSS/basic dual-NAV update and reset rules are already implemented
by ``wifi.he_mac`` and are intentionally not duplicated here.  All results
in this module are discrete and therefore have exact (zero) tolerance.
"""


comptime WIFI_TIM_MIN_AID = 1
comptime WIFI_TIM_MAX_AID = 2007
comptime WIFI_TIM_METHOD_A_MAX_OCTETS = 251
comptime WIFI_PS_LISTEN_INTERVAL_MAX = 65535
comptime WIFI_PS_POLL_AID_MASK = 0xC000


struct WifiLegacyPowerSaveProfile(ImplicitlyCopyable):
    """Mutable bounded legacy power-save listening profile.

    ``listen_anchor_tbtt`` is the first selected absolute TBTT index known
    to the caller.  Subsequent ordinary selected beacons are separated by
    ``listen_interval_beacons``.  ``receive_dtims`` models the corresponding
    MLME-POWERMGT request parameter.  Every public operation revalidates all
    fields so post-construction mutation cannot bypass the profile boundary.
    """

    var association_id: Int
    var listen_interval_beacons: Int
    var listen_anchor_tbtt: Int
    var receive_dtims: Bool

    def __init__(
        out self,
        association_id: Int,
        listen_interval_beacons: Int,
        listen_anchor_tbtt: Int,
        receive_dtims: Bool,
    ):
        self.association_id = association_id
        self.listen_interval_beacons = listen_interval_beacons
        self.listen_anchor_tbtt = listen_anchor_tbtt
        self.receive_dtims = receive_dtims


struct WifiTimMethodAElement(Movable):
    """Canonical normalized fields of one non-S1G Method-A TIM element."""

    var dtim_count: Int
    var dtim_period: Int
    var bitmap_control: Int
    var partial_virtual_bitmap: List[UInt8]

    def __init__(
        out self,
        dtim_count: Int,
        dtim_period: Int,
        bitmap_control: Int,
        var partial_virtual_bitmap: List[UInt8],
    ):
        self.dtim_count = dtim_count
        self.dtim_period = dtim_period
        self.bitmap_control = bitmap_control
        self.partial_virtual_bitmap = partial_virtual_bitmap ^


struct WifiTimIndication(ImplicitlyCopyable):
    """Decoded TIM/DTIM state and traffic indications for one AID."""

    var is_dtim: Bool
    var next_dtim_count: Int
    var individually_addressed_buffered: Bool
    var group_addressed_buffered: Bool

    def __init__(
        out self,
        is_dtim: Bool,
        next_dtim_count: Int,
        individually_addressed_buffered: Bool,
        group_addressed_buffered: Bool,
    ):
        self.is_dtim = is_dtim
        self.next_dtim_count = next_dtim_count
        self.individually_addressed_buffered = (
            individually_addressed_buffered
        )
        self.group_addressed_buffered = group_addressed_buffered


struct WifiLegacyPowerSaveDecision(ImplicitlyCopyable):
    """Deterministic legacy PS consequence of one decoded TIM element.

    ``tim_allows_doze`` is conditional on there being no other standard
    reason for the STA to remain awake.  ``ps_poll_trigger_eligible`` reports
    the exact legacy indication; it does not perform channel access or choose
    a transmission time.
    """

    var listen_required: Bool
    var is_dtim: Bool
    var individually_addressed_buffered: Bool
    var group_addressed_buffered: Bool
    var ps_poll_trigger_eligible: Bool
    var delivery_awake_required: Bool
    var tim_allows_doze: Bool

    def __init__(
        out self,
        listen_required: Bool,
        is_dtim: Bool,
        individually_addressed_buffered: Bool,
        group_addressed_buffered: Bool,
        ps_poll_trigger_eligible: Bool,
        delivery_awake_required: Bool,
        tim_allows_doze: Bool,
    ):
        self.listen_required = listen_required
        self.is_dtim = is_dtim
        self.individually_addressed_buffered = (
            individually_addressed_buffered
        )
        self.group_addressed_buffered = group_addressed_buffered
        self.ps_poll_trigger_eligible = ps_poll_trigger_eligible
        self.delivery_awake_required = delivery_awake_required
        self.tim_allows_doze = tim_allows_doze


def _validate_aid(association_id: Int) raises:
    if (
        association_id < WIFI_TIM_MIN_AID
        or association_id > WIFI_TIM_MAX_AID
    ):
        raise Error("association identifier must be in [1,2007]")


def _validate_dtim(dtim_count: Int, dtim_period: Int) raises:
    if dtim_period < 1 or dtim_period > 255:
        raise Error("DTIM Period must be in [1,255]")
    if dtim_count < 0 or dtim_count >= dtim_period:
        raise Error("DTIM Count must be in [0,DTIM Period-1]")


def _validate_profile(profile: WifiLegacyPowerSaveProfile) raises:
    _validate_aid(profile.association_id)
    if (
        profile.listen_interval_beacons < 1
        or profile.listen_interval_beacons > WIFI_PS_LISTEN_INTERVAL_MAX
    ):
        raise Error("legacy PS Listen Interval must be in [1,65535]")
    if profile.listen_anchor_tbtt < 0:
        raise Error("legacy PS listen-anchor TBTT must be non-negative")


def _validate_method_a_bitmap(
    bitmap_control: Int, partial_virtual_bitmap: Span[UInt8, ...]
) raises:
    if bitmap_control < 0 or bitmap_control > 255:
        raise Error("TIM Bitmap Control must be one octet")
    var octet_count = len(partial_virtual_bitmap)
    if octet_count < 1 or octet_count > WIFI_TIM_METHOD_A_MAX_OCTETS:
        raise Error("Method-A Partial Virtual Bitmap must have 1--251 octets")
    var bitmap_offset = bitmap_control & 0xFE
    if bitmap_offset + octet_count > WIFI_TIM_METHOD_A_MAX_OCTETS:
        raise Error("Method-A Partial Virtual Bitmap exceeds AID 2007")

    # AID 0 is carried by Bitmap Control B0 and is never set in the PVB.
    if bitmap_offset == 0 and (Int(partial_virtual_bitmap[0]) & 1) != 0:
        raise Error("Method-A Partial Virtual Bitmap must not encode AID 0")

    var first_nonzero = -1
    var last_nonzero = -1
    for index in range(octet_count):
        if partial_virtual_bitmap[index] != 0:
            if first_nonzero < 0:
                first_nonzero = index
            last_nonzero = index

    if first_nonzero < 0:
        if bitmap_offset != 0 or octet_count != 1:
            raise Error("an empty Method-A bitmap has offset zero and one octet")
        return

    # N1 is the largest even octet index preceding the first set AID bit.
    var first_global_octet = bitmap_offset + first_nonzero
    var canonical_offset = first_global_octet & ~1
    if bitmap_offset != canonical_offset:
        raise Error("noncanonical Method-A leading bitmap octets")
    if last_nonzero != octet_count - 1:
        raise Error("noncanonical Method-A trailing bitmap octets")


def wifi_dtim_count_advance(
    dtim_count: Int, dtim_period: Int, beacon_intervals: Int = 1
) raises -> Int:
    """Advance a DTIM Count by an exact number of beacon intervals.

    A transmitted count descends to zero and then wraps to
    ``dtim_period - 1``.  Reduction before subtraction makes the operation
    safe even when ``beacon_intervals`` is ``Int.MAX``.
    """
    _validate_dtim(dtim_count, dtim_period)
    if beacon_intervals < 0:
        raise Error("beacon-interval advance must be non-negative")
    var reduced = beacon_intervals % dtim_period
    if reduced <= dtim_count:
        return dtim_count - reduced
    return dtim_period - (reduced - dtim_count)


def wifi_tim_method_a_encode(
    buffered_association_ids: Span[Int, ...],
    dtim_count: Int,
    dtim_period: Int,
    *,
    group_addressed_buffered: Bool = False,
) raises -> WifiTimMethodAElement:
    """Construct the canonical single-BSSID non-S1G Method-A TIM fields.

    The returned Partial Virtual Bitmap is the minimal octet interval from
    even ``N1`` through the last nonzero octet.  Duplicate AIDs are harmless
    because the normative traffic indication is a bitmap.  Group-addressed
    traffic can be indicated only in a DTIM.
    """
    _validate_dtim(dtim_count, dtim_period)
    if group_addressed_buffered and dtim_count != 0:
        raise Error("group-addressed TIM indication requires a DTIM")

    var first_octet = WIFI_TIM_METHOD_A_MAX_OCTETS
    var last_octet = -1
    for index in range(len(buffered_association_ids)):
        var association_id = buffered_association_ids[index]
        _validate_aid(association_id)
        var octet = association_id // 8
        if octet < first_octet:
            first_octet = octet
        if octet > last_octet:
            last_octet = octet

    var bitmap_control = 1 if group_addressed_buffered else 0
    if last_octet < 0:
        return WifiTimMethodAElement(
            dtim_count,
            dtim_period,
            bitmap_control,
            List[UInt8](length=1, fill=UInt8(0)),
        )

    var bitmap_offset = first_octet & ~1
    var partial = List[UInt8](
        length=last_octet - bitmap_offset + 1, fill=UInt8(0)
    )
    for index in range(len(buffered_association_ids)):
        var association_id = buffered_association_ids[index]
        var local_octet = association_id // 8 - bitmap_offset
        var bit = association_id & 7
        partial[local_octet] = UInt8(
            Int(partial[local_octet]) | (1 << bit)
        )
    bitmap_control |= bitmap_offset
    return WifiTimMethodAElement(
        dtim_count, dtim_period, bitmap_control, partial ^
    )


def wifi_tim_aid_buffered(
    bitmap_control: Int,
    partial_virtual_bitmap: Span[UInt8, ...],
    association_id: Int,
) raises -> Bool:
    """Return the exact Method-A traffic-indication bit for one AID."""
    _validate_aid(association_id)
    _validate_method_a_bitmap(bitmap_control, partial_virtual_bitmap)
    var bitmap_offset = bitmap_control & 0xFE
    var global_octet = association_id // 8
    if global_octet < bitmap_offset:
        return False
    var local_octet = global_octet - bitmap_offset
    if local_octet >= len(partial_virtual_bitmap):
        return False
    return (
        Int(partial_virtual_bitmap[local_octet])
        & (1 << (association_id & 7))
    ) != 0


def wifi_tim_indication(
    dtim_count: Int,
    dtim_period: Int,
    bitmap_control: Int,
    partial_virtual_bitmap: Span[UInt8, ...],
    association_id: Int,
) raises -> WifiTimIndication:
    """Decode one strict Method-A TIM into individual and group indications."""
    _validate_dtim(dtim_count, dtim_period)
    if (bitmap_control & 1) != 0 and dtim_count != 0:
        raise Error("group-addressed traffic can be indicated only in a DTIM")
    var individual = wifi_tim_aid_buffered(
        bitmap_control, partial_virtual_bitmap, association_id
    )
    var group = dtim_count == 0 and (bitmap_control & 1) != 0
    return WifiTimIndication(
        dtim_count == 0,
        wifi_dtim_count_advance(dtim_count, dtim_period),
        individual,
        group,
    )


def wifi_legacy_ps_listen_required(
    profile: WifiLegacyPowerSaveProfile,
    tbtt_index: Int,
    dtim_count: Int,
    dtim_period: Int,
) raises -> Bool:
    """Return whether this TBTT is selected by ListenInterval/ReceiveDTIMs.

    The explicit anchor removes implementation policy from the calculation.
    A profile with ``receive_dtims`` set also selects every TBTT whose TIM has
    DTIM Count zero.
    """
    _validate_profile(profile)
    _validate_dtim(dtim_count, dtim_period)
    if tbtt_index < 0:
        raise Error("TBTT index must be non-negative")
    if profile.receive_dtims and dtim_count == 0:
        return True
    if tbtt_index < profile.listen_anchor_tbtt:
        return False
    return (
        (tbtt_index - profile.listen_anchor_tbtt)
        % profile.listen_interval_beacons
    ) == 0


def wifi_legacy_ps_next_listen_tbtt(
    profile: WifiLegacyPowerSaveProfile,
    current_tbtt_index: Int,
    current_dtim_count: Int,
    dtim_period: Int,
) raises -> Int:
    """Return the first selected TBTT at or after ``current_tbtt_index``.

    Both the periodic listen sequence and, when enabled, the next DTIM are
    evaluated in ``Int128``.  A result outside the platform ``Int`` domain is
    rejected instead of wrapping.
    """
    _validate_profile(profile)
    _validate_dtim(current_dtim_count, dtim_period)
    if current_tbtt_index < 0:
        raise Error("current TBTT index must be non-negative")

    var periodic = Int128(profile.listen_anchor_tbtt)
    if current_tbtt_index > profile.listen_anchor_tbtt:
        var delta = current_tbtt_index - profile.listen_anchor_tbtt
        var quotient = delta // profile.listen_interval_beacons
        if delta % profile.listen_interval_beacons != 0:
            quotient += 1
        periodic = (
            Int128(profile.listen_anchor_tbtt)
            + Int128(quotient) * Int128(profile.listen_interval_beacons)
        )

    var selected = periodic
    if profile.receive_dtims:
        var next_dtim = (
            Int128(current_tbtt_index) + Int128(current_dtim_count)
        )
        if next_dtim < selected:
            selected = next_dtim
    if selected > Int128(Int.MAX):
        raise Error("next legacy PS listen TBTT exceeds Int")
    return Int(selected)


def wifi_ps_poll_duration_id_encode(association_id: Int) raises -> Int:
    """Encode the PS-Poll Duration/ID field with its two leading one bits."""
    _validate_aid(association_id)
    return WIFI_PS_POLL_AID_MASK | association_id


def wifi_ps_poll_duration_id_decode(duration_id: Int) raises -> Int:
    """Decode a canonical PS-Poll Duration/ID field to association ID."""
    if duration_id < 0 or duration_id > 65535:
        raise Error("PS-Poll Duration/ID must be an unsigned 16-bit value")
    if (duration_id & WIFI_PS_POLL_AID_MASK) != WIFI_PS_POLL_AID_MASK:
        raise Error("PS-Poll Duration/ID must set both leading bits")
    var association_id = duration_id & 0x3FFF
    _validate_aid(association_id)
    return association_id


def wifi_legacy_ps_tim_decision(
    profile: WifiLegacyPowerSaveProfile,
    tbtt_index: Int,
    dtim_count: Int,
    dtim_period: Int,
    bitmap_control: Int,
    partial_virtual_bitmap: Span[UInt8, ...],
) raises -> WifiLegacyPowerSaveDecision:
    """Compose strict TIM parsing with the bounded legacy PS state decision.

    An individual traffic indication makes the legacy non-QoS STA eligible
    to trigger retrieval with PS-Poll.  A group indication at a DTIM or an
    individual indication requires continued awake delivery processing.  If
    neither is present, this TIM itself permits doze; other awake causes are
    deliberately not modeled.
    """
    _validate_profile(profile)
    var indication = wifi_tim_indication(
        dtim_count,
        dtim_period,
        bitmap_control,
        partial_virtual_bitmap,
        profile.association_id,
    )
    var listen = wifi_legacy_ps_listen_required(
        profile, tbtt_index, dtim_count, dtim_period
    )
    var awake = (
        indication.individually_addressed_buffered
        or indication.group_addressed_buffered
    )
    return WifiLegacyPowerSaveDecision(
        listen,
        indication.is_dtim,
        indication.individually_addressed_buffered,
        indication.group_addressed_buffered,
        indication.individually_addressed_buffered,
        awake,
        not awake,
    )
