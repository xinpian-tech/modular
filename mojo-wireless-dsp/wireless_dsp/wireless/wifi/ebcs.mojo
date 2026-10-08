"""Bounded IEEE 802.11 EBCS TIM Mode-1 and countdown algorithms.

This scalar CPU reference implements a finite Enhanced Broadcast Services
(EBCS) traffic-indication subset incorporated into IEEE Std 802.11-2024
Clause 34.  It covers only the unambiguous Content-ID-list representation
(Bitmap Mode 1), strict complete-element parsing and serialization, buffered
Content-ID lookup, and the fixed-period EBCS DTIM countdown.  The source
amendment is IEEE Std 802.11bc-2023, 9.4.2.310 and Clause 33; consolidation
into IEEE Std 802.11-2024 renumbers the element to 9.4.2.314.

Mode 1 carries one distinct Content ID per octet, uses Bitmap Offset zero,
and is constructed here only when its octet count is strictly smaller than
the minimal Mode-0 virtual-bitmap span.  Equal-length selection is not
specified and is excluded.  Mode 0 is also excluded because the adopted text
contains an irreconcilable wire-length conflict: approved LB257 CID 2068 says
the Content ID Bitmap length is L-4, where L excludes Element ID and Length,
but adopted 11-22/0089r8 and approved LB1000 CID 5138 say Mode-0 Length is
(N2-N1)+4 even though the carried range N1 through N2 is inclusive.  With
four fixed octets after Length (Extension, Count, Period, Control), those
requirements differ by one.  This module neither guesses nor emits that
conflict domain: mutable Mode-0 content, Mode-0 serialization, and Mode-0
wire input are all rejected.

The sole normative publications are
https://standards.ieee.org/ieee/802.11/10548/ and the published source
amendment https://standards.ieee.org/ieee/802.11bc/7450/ .  The WG and ballot
records below are historical conflict/table cross-checks only; they never
authorize production or substitute for either published standard.
TGbc record: https://mentor.ieee.org/802.11/dcn/22/11-22-0089-08-00bc-resolution-text-for-ebcs-tim-related-comments.docx .
Official LB264 record (including approved CID 2068):
https://mentor.ieee.org/802.11/dcn/22/11-22-0686-16-00bc-lb264-comments-on-p802-11bc-d3-0.xlsx .
The IEEE 802.11 ANA allocation assigns Element ID Extension 112:
https://www.ieee802.org/11/email/stds-802-11-editors/msg00421.html .
The official SA-ballot master records approved CIDs 5138 and 6011; CID 6011
also confirms that Content ID is not set to zero:
https://mentor.ieee.org/802.11/dcn/23/11-23-0081-04-00bc-lb6000-sab-comments-on-p802-11bc-d5-0.xlsx .

Mode 0, equal-size mode selection, empty indication and element-carriage
policy, EBCS Info/Request/Response and ANQP tuples, certificates, signatures,
frame authentication and keys, fragmentation, content policy, traffic
buffering, complete MAC/MLME state, scheduling, PHY, and RF are intentionally
excluded.  This finite element/timing slice therefore does not make the broad
EBCS MAC feature complete.
"""

from std.collections import Span


comptime WIFI_EBCS_TIM_ELEMENT_ID = 255
comptime WIFI_EBCS_TIM_ELEMENT_ID_EXTENSION = 112
comptime WIFI_EBCS_TIM_BITMAP_MODE = 0
comptime WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE = 1
comptime WIFI_EBCS_CONTENT_ID_MIN = 1
comptime WIFI_EBCS_CONTENT_ID_MAX = 255
comptime WIFI_EBCS_CONTENT_ID_COUNT = 255
comptime WIFI_EBCS_TIM_VIRTUAL_BITMAP_OCTETS = 32
comptime WIFI_EBCS_TIM_MIN_CONTENT_OCTETS = 1
comptime WIFI_EBCS_TIM_MAX_CONTENT_OCTETS = 32
comptime WIFI_EBCS_TIM_MIN_STRICT_MODE_ONE_CONTENT_OCTETS = 2
comptime WIFI_EBCS_TIM_MAX_STRICT_MODE_ONE_CONTENT_OCTETS = 31
comptime WIFI_EBCS_TIM_MIN_ELEMENT_OCTETS = 8
comptime WIFI_EBCS_TIM_MAX_ELEMENT_OCTETS = 37


def _validate_dtim_fields(dtim_count: Int, dtim_period: Int) raises:
    if dtim_period < 1 or dtim_period > 255:
        raise Error("EBCS DTIM Period must be in [1,255]")
    if dtim_count < 0 or dtim_count >= dtim_period:
        raise Error("EBCS DTIM Count must be in [0, period-1]")


def _validate_mode_one_content(
    bitmap_mode: Int,
    bitmap_offset: Int,
    content_id_bitmap: Span[UInt8, ...],
) raises:
    if bitmap_mode != WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE:
        raise Error("EBCS TIM Mode 0 is excluded by its Length conflict")
    if bitmap_offset != 0:
        raise Error("EBCS TIM Mode 1 requires Bitmap Offset zero")

    var content_octets = len(content_id_bitmap)
    if (
        content_octets < WIFI_EBCS_TIM_MIN_CONTENT_OCTETS
        or content_octets > WIFI_EBCS_TIM_MAX_CONTENT_OCTETS
    ):
        raise Error("EBCS TIM Mode 1 must contain 1-32 Content IDs")

    var seen = List[UInt8](length=256, fill=UInt8(0))
    var first_octet = 31
    var last_octet = 0
    for index in range(content_octets):
        var content_id = Int(content_id_bitmap[index])
        if (
            content_id < WIFI_EBCS_CONTENT_ID_MIN
            or content_id > WIFI_EBCS_CONTENT_ID_MAX
        ):
            raise Error("EBCS Content ID must be in [1,255]")
        if seen[content_id] != 0:
            raise Error("EBCS TIM Mode 1 Content IDs must be unique")
        seen[content_id] = 1
        var octet_index = content_id // 8
        if octet_index < first_octet:
            first_octet = octet_index
        if octet_index > last_octet:
            last_octet = octet_index

    var bitmap_span_octets = last_octet - first_octet + 1
    if content_octets >= bitmap_span_octets:
        raise Error("EBCS TIM Mode 1 must be strictly shorter than Mode 0")


struct WifiEBCSTIMConfig(ImplicitlyCopyable):
    """Mutable fixed-period EBCS DTIM Count and Period fields."""

    var dtim_count: Int
    var dtim_period: Int

    def __init__(out self, dtim_count: Int, dtim_period: Int) raises:
        self.dtim_count = dtim_count
        self.dtim_period = dtim_period
        self.validate()

    def validate(self) raises:
        """Revalidate both mutable one-octet timing fields and their relation."""
        _validate_dtim_fields(self.dtim_count, self.dtim_period)


struct WifiEBCSTIMContent(Movable):
    """Owned, strictly-shorter Mode-1 Content ID list representation."""

    var bitmap_mode: Int
    var bitmap_offset: Int
    var content_id_bitmap: List[UInt8]

    def __init__(
        out self,
        bitmap_mode: Int,
        bitmap_offset: Int,
        var content_id_bitmap: List[UInt8],
    ) raises:
        self.bitmap_mode = bitmap_mode
        self.bitmap_offset = bitmap_offset
        self.content_id_bitmap = content_id_bitmap^
        self.validate()

    def validate(self) raises:
        """Revalidate mode, offset, length, uniqueness, and strict size win."""
        _validate_mode_one_content(
            self.bitmap_mode,
            self.bitmap_offset,
            Span(self.content_id_bitmap),
        )


struct WifiEBCSTIMElement(Movable):
    """Strictly parsed complete EBCS TIM Mode-1 extension element."""

    var dtim_count: Int
    var dtim_period: Int
    var bitmap_mode: Int
    var bitmap_offset: Int
    var content_id_bitmap: List[UInt8]

    def __init__(
        out self,
        dtim_count: Int,
        dtim_period: Int,
        bitmap_mode: Int,
        bitmap_offset: Int,
        var content_id_bitmap: List[UInt8],
    ) raises:
        self.dtim_count = dtim_count
        self.dtim_period = dtim_period
        self.bitmap_mode = bitmap_mode
        self.bitmap_offset = bitmap_offset
        self.content_id_bitmap = content_id_bitmap^
        self.validate()

    def validate(self) raises:
        """Revalidate every mutable decoded timing and Mode-1 field."""
        _validate_dtim_fields(self.dtim_count, self.dtim_period)
        _validate_mode_one_content(
            self.bitmap_mode,
            self.bitmap_offset,
            Span(self.content_id_bitmap),
        )


def wifi_ebcs_tim_content_id_list_from_ids(
    content_ids: Span[Int, ...],
) raises -> WifiEBCSTIMContent:
    """Build Mode 1 only when its list is strictly shorter than Mode 0.

    ``content_ids`` is a nonempty set expressed in caller order.  Every value
    must be in [1,255], unique, and the list may contain at most 32 entries.
    Caller order is preserved.  Inputs in the Mode-0 or equal-size conflict
    domain are rejected rather than assigned a guessed wire representation.
    """
    var buffered_count = len(content_ids)
    if (
        buffered_count < WIFI_EBCS_TIM_MIN_CONTENT_OCTETS
        or buffered_count > WIFI_EBCS_TIM_MAX_CONTENT_OCTETS
    ):
        raise Error("EBCS TIM Mode 1 requires 1-32 Content IDs")

    var seen = List[UInt8](length=256, fill=UInt8(0))
    var id_list = List[UInt8](capacity=buffered_count)
    for index in range(buffered_count):
        var content_id = content_ids[index]
        if (
            content_id < WIFI_EBCS_CONTENT_ID_MIN
            or content_id > WIFI_EBCS_CONTENT_ID_MAX
        ):
            raise Error("EBCS Content ID must be in [1,255]")
        if seen[content_id] != 0:
            raise Error("EBCS buffered Content IDs must be unique")
        seen[content_id] = 1
        id_list.append(UInt8(content_id))

    return WifiEBCSTIMContent(
        WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE, 0, id_list^
    )


def wifi_ebcs_dtim_next_count(config: WifiEBCSTIMConfig) raises -> Int:
    """Advance one consecutive Beacon interval in a fixed EBCS DTIM period.

    Count zero denotes the current EBCS DTIM.  Its successor reloads to
    ``period - 1``; every other count decrements by one.  Beacon omission and
    period reconfiguration are caller-owned MAC state transitions.
    """
    config.validate()
    if config.dtim_count == 0:
        return config.dtim_period - 1
    return config.dtim_count - 1


def wifi_ebcs_tim_element_serialize_mode_one(
    config: WifiEBCSTIMConfig, content: WifiEBCSTIMContent
) raises -> List[UInt8]:
    """Serialize one complete, nonextensible Mode-1 EBCS TIM element."""
    config.validate()
    content.validate()
    var content_octets = len(content.content_id_bitmap)
    var element_length = 4 + content_octets
    var result = List[UInt8](capacity=6 + content_octets)
    result.append(UInt8(WIFI_EBCS_TIM_ELEMENT_ID))
    result.append(UInt8(element_length))
    result.append(UInt8(WIFI_EBCS_TIM_ELEMENT_ID_EXTENSION))
    result.append(UInt8(config.dtim_count))
    result.append(UInt8(config.dtim_period))
    result.append(UInt8(WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE))
    for content_id in content.content_id_bitmap:
        result.append(content_id)
    return result^


def wifi_ebcs_tim_element_parse_mode_one(
    element: Span[UInt8, ...],
) raises -> WifiEBCSTIMElement:
    """Parse a complete Mode-1 element; explicitly reject Mode-0 input."""
    var element_octets = len(element)
    if (
        element_octets < WIFI_EBCS_TIM_MIN_ELEMENT_OCTETS
        or element_octets > WIFI_EBCS_TIM_MAX_ELEMENT_OCTETS
    ):
        raise Error("EBCS TIM Mode-1 element must contain 8-37 octets")
    if Int(element[0]) != WIFI_EBCS_TIM_ELEMENT_ID:
        raise Error("EBCS TIM Element ID must be 255")
    if Int(element[1]) != element_octets - 2:
        raise Error("EBCS TIM Length does not match the element")
    if Int(element[2]) != WIFI_EBCS_TIM_ELEMENT_ID_EXTENSION:
        raise Error("EBCS TIM Element ID Extension must be 112")

    var control = Int(element[5])
    if (control & 0xC0) != 0:
        raise Error("EBCS TIM Content ID Bitmap Control has reserved bits")
    var bitmap_mode = control & 1
    var bitmap_offset = (control >> 1) & 0x1F
    if bitmap_mode != WIFI_EBCS_TIM_CONTENT_ID_LIST_MODE:
        raise Error("EBCS TIM Mode-0 wire input is excluded")
    if bitmap_offset != 0:
        raise Error("EBCS TIM Mode 1 requires Bitmap Offset zero")

    var content = List[UInt8](capacity=element_octets - 6)
    for index in range(6, element_octets):
        content.append(element[index])
    return WifiEBCSTIMElement(
        Int(element[3]),
        Int(element[4]),
        bitmap_mode,
        bitmap_offset,
        content^,
    )


def wifi_ebcs_tim_mode_one_content_id_buffered(
    element: WifiEBCSTIMElement, content_id: Int
) raises -> Bool:
    """Return whether a strictly decoded Mode-1 element lists a Content ID."""
    element.validate()
    if (
        content_id < WIFI_EBCS_CONTENT_ID_MIN
        or content_id > WIFI_EBCS_CONTENT_ID_MAX
    ):
        raise Error("EBCS Content ID must be in [1,255]")
    for value in element.content_id_bitmap:
        if Int(value) == content_id:
            return True
    return False
