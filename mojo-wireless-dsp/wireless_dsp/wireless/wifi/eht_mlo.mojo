"""Bounded deterministic IEEE 802.11be-2024 EHT MLO algorithms.

This CPU-only module implements the TID-To-Link Mapping element payload from
9.4.2.324, the corresponding established-link mapping state calculations in
35.3.7, and the EML timing encodings in Tables 9-417i--9-417m used by the
Clause-35 enhanced multi-link procedures.  The normative publication is IEEE
Std 802.11be-2024, DOI 10.1109/IEEESTD.2024.11090080.

The declared profile has TIDs 0--7, Link IDs 0--14, already-established setup
links, and canonical little-endian element payloads.  The payload starts at the
TID-To-Link Mapping Control field; Element ID, Length, Element ID Extension,
the containing frame, and FCS are deliberately outside this module.  A mapping
update retains a direction/TID entry whose Link Mapping field is absent.  The
default mapping maps every TID to every setup link in the indicated direction.

Association and protected-EHT action exchanges, acceptance/status policy,
advertised-mapping activation scheduling, link setup/removal recovery, link
selection and rate policy, NSTR/STR concurrency, the complete eMLSR/EMLMR
state machine, Block Ack/reordering, security, and power save are outside this
bounded reference.  All outputs are discrete and have exact zero tolerance.
"""


comptime WIFI_EHT_MLO_DIRECTION_DOWNLINK = 0
comptime WIFI_EHT_MLO_DIRECTION_UPLINK = 1
comptime WIFI_EHT_MLO_DIRECTION_BOTH = 2

comptime WIFI_EHT_MLO_TID_COUNT = 8
comptime WIFI_EHT_MLO_MAX_LINKS = 15
comptime WIFI_EHT_MLO_MAX_LINK_ID = 14
comptime WIFI_EHT_MLO_VALID_LINK_BITMAP = 0x7FFF

comptime WIFI_EHT_MLO_EXPECTED_DURATION_MAX = 0xFFFFFF
comptime WIFI_EHT_MLO_MAPPING_SWITCH_TIME_MAX = 0xFFFF
comptime WIFI_EHT_MLO_TU_US = 1024

comptime WIFI_EHT_EML_CAP_EMLSR_SUPPORT = 0x0001
comptime WIFI_EHT_EML_CAP_EMLMR_SUPPORT = 0x0080
comptime WIFI_EHT_EML_CAP_RESERVED_MASK = 0x8700


struct WifiEhtTidToLinkElement(Movable):
    """Normalized mutable TID-To-Link Mapping element payload.

    ``tid_link_bitmaps`` always has eight entries indexed by TID.  An entry is
    zero exactly when its bit is absent from ``tid_presence_bitmap``.  A
    default element has no presence bitmap or per-TID fields.  Every public
    operation revalidates these mutable fields before using them.
    """

    var direction: Int
    var default_link_mapping: Bool
    var mapping_switch_time_present: Bool
    var mapping_switch_time: Int
    var expected_duration_present: Bool
    var expected_duration_tu: Int
    var link_mapping_size_octets: Int
    var tid_presence_bitmap: Int
    var tid_link_bitmaps: List[Int]

    def __init__(
        out self,
        direction: Int,
        default_link_mapping: Bool,
        mapping_switch_time_present: Bool,
        mapping_switch_time: Int,
        expected_duration_present: Bool,
        expected_duration_tu: Int,
        link_mapping_size_octets: Int,
        tid_presence_bitmap: Int,
        var tid_link_bitmaps: List[Int],
    ):
        self.direction = direction
        self.default_link_mapping = default_link_mapping
        self.mapping_switch_time_present = mapping_switch_time_present
        self.mapping_switch_time = mapping_switch_time
        self.expected_duration_present = expected_duration_present
        self.expected_duration_tu = expected_duration_tu
        self.link_mapping_size_octets = link_mapping_size_octets
        self.tid_presence_bitmap = tid_presence_bitmap
        self.tid_link_bitmaps = tid_link_bitmaps ^


struct WifiEhtMloMappingState(Movable):
    """Established per-TID downlink and uplink Link ID bitmaps.

    Both lists have exactly eight nonempty entries and contain only current
    setup links.  The state is mutable for caller convenience, so public state
    operations always revalidate it.
    """

    var downlink_tid_links: List[Int]
    var uplink_tid_links: List[Int]

    def __init__(
        out self,
        var downlink_tid_links: List[Int],
        var uplink_tid_links: List[Int],
    ):
        self.downlink_tid_links = downlink_tid_links ^
        self.uplink_tid_links = uplink_tid_links ^


struct WifiEhtMloTidLinkState(ImplicitlyCopyable):
    """Mapped and currently active eligible links for one TID/direction."""

    var mapped_links_bitmap: Int
    var active_mapped_links_bitmap: Int
    var frame_allowed_on_any_active_link: Bool

    def __init__(
        out self,
        mapped_links_bitmap: Int,
        active_mapped_links_bitmap: Int,
    ):
        self.mapped_links_bitmap = mapped_links_bitmap
        self.active_mapped_links_bitmap = active_mapped_links_bitmap
        self.frame_allowed_on_any_active_link = active_mapped_links_bitmap != 0


struct WifiEhtEmlTiming(ImplicitlyCopyable):
    """Strict decoding of the EML timing-related capability subfields."""

    var emlsr_supported: Bool
    var emlmr_supported: Bool
    var padding_delay_us: Int
    var emlsr_transition_delay_us: Int
    var emlmr_transition_delay_us: Int
    var transition_timeout_us: Int

    def __init__(
        out self,
        emlsr_supported: Bool,
        emlmr_supported: Bool,
        padding_delay_us: Int,
        emlsr_transition_delay_us: Int,
        emlmr_transition_delay_us: Int,
        transition_timeout_us: Int,
    ):
        self.emlsr_supported = emlsr_supported
        self.emlmr_supported = emlmr_supported
        self.padding_delay_us = padding_delay_us
        self.emlsr_transition_delay_us = emlsr_transition_delay_us
        self.emlmr_transition_delay_us = emlmr_transition_delay_us
        self.transition_timeout_us = transition_timeout_us


def _validate_direction(direction: Int, *, allow_both: Bool = True) raises:
    if direction == WIFI_EHT_MLO_DIRECTION_DOWNLINK:
        return
    if direction == WIFI_EHT_MLO_DIRECTION_UPLINK:
        return
    if allow_both and direction == WIFI_EHT_MLO_DIRECTION_BOTH:
        return
    raise Error("EHT MLO direction must be downlink, uplink, or both")


def _validate_link_bitmap(bitmap: Int, *, allow_zero: Bool = False) raises:
    if bitmap < 0 or (bitmap & ~WIFI_EHT_MLO_VALID_LINK_BITMAP) != 0:
        raise Error("EHT MLO link bitmap can contain only Link IDs 0--14")
    if not allow_zero and bitmap == 0:
        raise Error("EHT MLO link bitmap must contain at least one link")


def _validate_setup_links(setup_links_bitmap: Int) raises:
    _validate_link_bitmap(setup_links_bitmap)


def _validate_element(element: WifiEhtTidToLinkElement) raises:
    _validate_direction(element.direction)
    if (
        element.link_mapping_size_octets != 1
        and element.link_mapping_size_octets != 2
    ):
        raise Error("EHT Link Mapping fields must have one or two octets")
    if (
        element.mapping_switch_time < 0
        or element.mapping_switch_time > WIFI_EHT_MLO_MAPPING_SWITCH_TIME_MAX
    ):
        raise Error("EHT Mapping Switch Time must be a 16-bit value")
    if (
        not element.mapping_switch_time_present
        and element.mapping_switch_time != 0
    ):
        raise Error("absent EHT Mapping Switch Time must be zero")
    if (
        element.expected_duration_tu < 0
        or element.expected_duration_tu
        > WIFI_EHT_MLO_EXPECTED_DURATION_MAX
    ):
        raise Error("EHT Expected Duration must be a 24-bit TU value")
    if (
        not element.expected_duration_present
        and element.expected_duration_tu != 0
    ):
        raise Error("absent EHT Expected Duration must be zero")
    if len(element.tid_link_bitmaps) != WIFI_EHT_MLO_TID_COUNT:
        raise Error("EHT TID-to-link normalization requires eight TIDs")
    if (
        element.tid_presence_bitmap < 0
        or element.tid_presence_bitmap > 0xFF
    ):
        raise Error("EHT Link Mapping Presence Indicator must be one octet")

    if element.default_link_mapping:
        if element.tid_presence_bitmap != 0:
            raise Error("default EHT mapping has no presence indicator")
        for tid in range(WIFI_EHT_MLO_TID_COUNT):
            if element.tid_link_bitmaps[tid] != 0:
                raise Error("default EHT mapping has no per-TID fields")
        return

    if element.tid_presence_bitmap == 0:
        raise Error("non-default EHT mapping must carry at least one TID")
    var maximum = (
        0xFF if element.link_mapping_size_octets == 1 else 0x7FFF
    )
    for tid in range(WIFI_EHT_MLO_TID_COUNT):
        var present = (element.tid_presence_bitmap & (1 << tid)) != 0
        var bitmap = element.tid_link_bitmaps[tid]
        if present:
            if bitmap <= 0 or bitmap > maximum:
                raise Error("EHT Link Mapping must be a nonempty valid bitmap")
        elif bitmap != 0:
            raise Error("absent EHT TID mapping must normalize to zero")


def _validate_mapping_state(
    state: WifiEhtMloMappingState, setup_links_bitmap: Int
) raises:
    _validate_setup_links(setup_links_bitmap)
    if (
        len(state.downlink_tid_links) != WIFI_EHT_MLO_TID_COUNT
        or len(state.uplink_tid_links) != WIFI_EHT_MLO_TID_COUNT
    ):
        raise Error("EHT mapping state requires eight TIDs per direction")
    for tid in range(WIFI_EHT_MLO_TID_COUNT):
        var downlink = state.downlink_tid_links[tid]
        var uplink = state.uplink_tid_links[tid]
        _validate_link_bitmap(downlink)
        _validate_link_bitmap(uplink)
        if (downlink & ~setup_links_bitmap) != 0:
            raise Error("downlink TID mapping contains a non-setup link")
        if (uplink & ~setup_links_bitmap) != 0:
            raise Error("uplink TID mapping contains a non-setup link")


def _copy_int_list(values: List[Int]) -> List[Int]:
    var result = List[Int](capacity=len(values))
    for index in range(len(values)):
        result.append(values[index])
    return result ^


def _append_le16(mut output: List[UInt8], value: Int):
    output.append(UInt8(value & 0xFF))
    output.append(UInt8((value >> 8) & 0xFF))


def _append_le24(mut output: List[UInt8], value: Int):
    output.append(UInt8(value & 0xFF))
    output.append(UInt8((value >> 8) & 0xFF))
    output.append(UInt8((value >> 16) & 0xFF))


def wifi_eht_mlo_tid_to_link_encode(
    element: WifiEhtTidToLinkElement,
) raises -> List[UInt8]:
    """Encode one strict 9.4.2.324 element payload in canonical field order.

    The variable-width Control field is followed by Mapping Switch Time,
    Expected Duration, and the present Link Mapping fields, all in the order
    defined by the published element format.  Multioctet integers are least
    significant octet first.
    """
    _validate_element(element)
    var control = element.direction
    if element.default_link_mapping:
        control |= 0x04
    if element.mapping_switch_time_present:
        control |= 0x08
    if element.expected_duration_present:
        control |= 0x10
    if element.link_mapping_size_octets == 1:
        control |= 0x20

    var output = List[UInt8]()
    output.append(UInt8(control))
    if not element.default_link_mapping:
        output.append(UInt8(element.tid_presence_bitmap))
    if element.mapping_switch_time_present:
        _append_le16(output, element.mapping_switch_time)
    if element.expected_duration_present:
        _append_le24(output, element.expected_duration_tu)
    if not element.default_link_mapping:
        for tid in range(WIFI_EHT_MLO_TID_COUNT):
            if (element.tid_presence_bitmap & (1 << tid)) == 0:
                continue
            var bitmap = element.tid_link_bitmaps[tid]
            output.append(UInt8(bitmap & 0xFF))
            if element.link_mapping_size_octets == 2:
                output.append(UInt8((bitmap >> 8) & 0xFF))
    return output ^


def wifi_eht_mlo_tid_to_link_decode(
    payload: Span[UInt8, ...],
) raises -> WifiEhtTidToLinkElement:
    """Decode one exact-length 9.4.2.324 element payload.

    Reserved control values, truncation, trailing octets, zero link mappings,
    and Link ID 15 are rejected.  The result uses eight entries with zeros for
    fields absent under the Link Mapping Presence Indicator.
    """
    if len(payload) < 1:
        raise Error("EHT TID-to-link payload must contain its control field")
    var control = Int(payload[0])
    if (control & 0xC0) != 0:
        raise Error("reserved EHT TID-to-link control bits must be zero")
    var direction = control & 0x03
    _validate_direction(direction)
    var default_mapping = (control & 0x04) != 0
    var switch_present = (control & 0x08) != 0
    var duration_present = (control & 0x10) != 0
    var mapping_size = 1 if (control & 0x20) != 0 else 2
    var position = 1
    var presence = 0
    if not default_mapping:
        if position >= len(payload):
            raise Error("missing EHT Link Mapping Presence Indicator")
        presence = Int(payload[position])
        position += 1

    var switch_time = 0
    if switch_present:
        if position + 2 > len(payload):
            raise Error("truncated EHT Mapping Switch Time")
        switch_time = (
            Int(payload[position]) | (Int(payload[position + 1]) << 8)
        )
        position += 2

    var duration = 0
    if duration_present:
        if position + 3 > len(payload):
            raise Error("truncated EHT Expected Duration")
        duration = (
            Int(payload[position])
            | (Int(payload[position + 1]) << 8)
            | (Int(payload[position + 2]) << 16)
        )
        position += 3

    var mappings = List[Int](length=WIFI_EHT_MLO_TID_COUNT, fill=0)
    if not default_mapping:
        for tid in range(WIFI_EHT_MLO_TID_COUNT):
            if (presence & (1 << tid)) == 0:
                continue
            if position + mapping_size > len(payload):
                raise Error("truncated EHT per-TID Link Mapping")
            var bitmap = Int(payload[position])
            position += 1
            if mapping_size == 2:
                bitmap |= Int(payload[position]) << 8
                position += 1
            mappings[tid] = bitmap
    if position != len(payload):
        raise Error("EHT TID-to-link payload contains trailing octets")

    var result = WifiEhtTidToLinkElement(
        direction,
        default_mapping,
        switch_present,
        switch_time,
        duration_present,
        duration,
        mapping_size,
        presence,
        mappings ^,
    )
    _validate_element(result)
    return result ^


def wifi_eht_mlo_default_mapping_state(
    setup_links_bitmap: Int,
) raises -> WifiEhtMloMappingState:
    """Create the Clause-35 default: every TID on every setup link."""
    _validate_setup_links(setup_links_bitmap)
    return WifiEhtMloMappingState(
        List[Int](
            length=WIFI_EHT_MLO_TID_COUNT, fill=setup_links_bitmap
        ),
        List[Int](
            length=WIFI_EHT_MLO_TID_COUNT, fill=setup_links_bitmap
        ),
    )


def wifi_eht_mlo_apply_tid_to_link_element(
    state: WifiEhtMloMappingState,
    element: WifiEhtTidToLinkElement,
    setup_links_bitmap: Int,
) raises -> WifiEhtMloMappingState:
    """Apply an accepted mapping element to established directional state.

    A present per-TID field replaces that TID in the indicated direction(s);
    an absent field retains the established entry.  A default element replaces
    every TID in its indicated direction(s) with all setup links.  The complete
    result must still map every TID to at least one setup link.
    """
    _validate_mapping_state(state, setup_links_bitmap)
    _validate_element(element)
    var downlink = _copy_int_list(state.downlink_tid_links)
    var uplink = _copy_int_list(state.uplink_tid_links)
    for tid in range(WIFI_EHT_MLO_TID_COUNT):
        var update = element.default_link_mapping or (
            (element.tid_presence_bitmap & (1 << tid)) != 0
        )
        if not update:
            continue
        var bitmap = (
            setup_links_bitmap
            if element.default_link_mapping
            else element.tid_link_bitmaps[tid]
        )
        if (bitmap & ~setup_links_bitmap) != 0:
            raise Error("EHT update maps a TID to a non-setup link")
        if (
            element.direction == WIFI_EHT_MLO_DIRECTION_DOWNLINK
            or element.direction == WIFI_EHT_MLO_DIRECTION_BOTH
        ):
            downlink[tid] = bitmap
        if (
            element.direction == WIFI_EHT_MLO_DIRECTION_UPLINK
            or element.direction == WIFI_EHT_MLO_DIRECTION_BOTH
        ):
            uplink[tid] = bitmap

    var result = WifiEhtMloMappingState(downlink ^, uplink ^)
    _validate_mapping_state(result, setup_links_bitmap)
    return result ^


def wifi_eht_mlo_tid_link_state(
    state: WifiEhtMloMappingState,
    setup_links_bitmap: Int,
    active_links_bitmap: Int,
    tid: Int,
    direction: Int,
) raises -> WifiEhtMloTidLinkState:
    """Resolve mapped and active eligible links without choosing a link.

    ``active_links_bitmap`` is caller-classified instantaneous link state and
    may be empty.  Link scheduling among the returned eligible set is policy
    and is intentionally not performed here.
    """
    _validate_mapping_state(state, setup_links_bitmap)
    _validate_link_bitmap(active_links_bitmap, allow_zero=True)
    if (active_links_bitmap & ~setup_links_bitmap) != 0:
        raise Error("active EHT links must be a subset of setup links")
    if tid < 0 or tid >= WIFI_EHT_MLO_TID_COUNT:
        raise Error("EHT QoS TID must be in [0,7]")
    _validate_direction(direction, allow_both=False)
    var mapped = (
        state.downlink_tid_links[tid]
        if direction == WIFI_EHT_MLO_DIRECTION_DOWNLINK
        else state.uplink_tid_links[tid]
    )
    return WifiEhtMloTidLinkState(mapped, mapped & active_links_bitmap)


def wifi_eht_mlo_enabled_links(
    state: WifiEhtMloMappingState,
    setup_links_bitmap: Int,
    direction: Int = WIFI_EHT_MLO_DIRECTION_BOTH,
) raises -> Int:
    """Return the union of mapped setup links in selected direction(s).

    This is a projection over caller-supplied setup state.  It does not
    classify instantaneous active links or select a link for scheduling.
    """
    _validate_mapping_state(state, setup_links_bitmap)
    _validate_direction(direction)
    var enabled = 0
    for tid in range(WIFI_EHT_MLO_TID_COUNT):
        if (
            direction == WIFI_EHT_MLO_DIRECTION_DOWNLINK
            or direction == WIFI_EHT_MLO_DIRECTION_BOTH
        ):
            enabled |= state.downlink_tid_links[tid]
        if (
            direction == WIFI_EHT_MLO_DIRECTION_UPLINK
            or direction == WIFI_EHT_MLO_DIRECTION_BOTH
        ):
            enabled |= state.uplink_tid_links[tid]
    return enabled


def wifi_eht_mlo_eml_timing_decode(
    eml_capabilities: Int,
) raises -> WifiEhtEmlTiming:
    """Decode strict EML timing tables from a 16-bit capability field.

    Padding codes 0--4, EMLSR transition codes 0--5, EMLMR transition codes
    0--4, and timeout codes 0--10 are the published values.  Reserved bits and
    codes are rejected instead of being silently interpreted as zero.
    """
    if eml_capabilities < 0 or eml_capabilities > 0xFFFF:
        raise Error("EHT EML Capabilities must be a 16-bit value")
    if (eml_capabilities & WIFI_EHT_EML_CAP_RESERVED_MASK) != 0:
        raise Error("reserved EHT EML capability bits must be zero")
    var emlsr = (eml_capabilities & WIFI_EHT_EML_CAP_EMLSR_SUPPORT) != 0
    var emlmr = (eml_capabilities & WIFI_EHT_EML_CAP_EMLMR_SUPPORT) != 0
    var padding_code = (eml_capabilities >> 1) & 0x07
    var transition_code = (eml_capabilities >> 4) & 0x07
    var timeout_code = (eml_capabilities >> 11) & 0x0F
    if padding_code > 4:
        raise Error("reserved EHT EML Padding Delay code")
    if emlsr and transition_code > 5:
        raise Error("reserved EHT EMLSR Transition Delay code")
    if emlmr and transition_code > 4:
        raise Error("reserved EHT EMLMR Transition Delay code")
    if not emlsr and not emlmr:
        if padding_code != 0 or transition_code != 0 or timeout_code != 0:
            raise Error("timing codes require EMLSR or EMLMR support")
    if timeout_code > 10:
        raise Error("reserved EHT EML Transition Timeout code")

    var padding = 0
    if (emlsr or emlmr) and padding_code > 0:
        padding = 32 * (1 << (padding_code - 1))
    var emlsr_transition = 0
    if emlsr and transition_code > 0:
        emlsr_transition = 16 * (1 << (transition_code - 1))
    var emlmr_transition = 0
    if emlmr and transition_code > 0:
        emlmr_transition = 32 * (1 << (transition_code - 1))
    var timeout = 0
    if timeout_code > 0:
        timeout = 128 * (1 << (timeout_code - 1))
    return WifiEhtEmlTiming(
        emlsr,
        emlmr,
        padding,
        emlsr_transition,
        emlmr_transition,
        timeout,
    )


def wifi_eht_mlo_mapping_switch_time_field(tsf_us: UInt64) raises -> Int:
    """Return TSF bits B10--B25 across the full unsigned 64-bit TSF domain."""
    return Int(
        (tsf_us // UInt64(WIFI_EHT_MLO_TU_US)) & UInt64(0xFFFF)
    )


def wifi_eht_mlo_expected_duration_field(duration_us: Int) raises -> Int:
    """Encode an exactly TU-aligned duration into the 24-bit field."""
    if duration_us < 0:
        raise Error("EHT Expected Duration must be non-negative")
    if duration_us % WIFI_EHT_MLO_TU_US != 0:
        raise Error("EHT Expected Duration must be an integral number of TUs")
    var duration_tu = duration_us // WIFI_EHT_MLO_TU_US
    if duration_tu > WIFI_EHT_MLO_EXPECTED_DURATION_MAX:
        raise Error("EHT Expected Duration exceeds its 24-bit field")
    return duration_tu


def wifi_eht_mlo_expected_duration_us(expected_duration_tu: Int) raises -> Int:
    """Decode the 24-bit Expected Duration field from TUs to microseconds."""
    if (
        expected_duration_tu < 0
        or expected_duration_tu > WIFI_EHT_MLO_EXPECTED_DURATION_MAX
    ):
        raise Error("EHT Expected Duration must be a 24-bit TU value")
    return expected_duration_tu * WIFI_EHT_MLO_TU_US
