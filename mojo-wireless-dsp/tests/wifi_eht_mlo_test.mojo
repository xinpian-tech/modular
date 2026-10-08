"""Independent exact evidence for bounded IEEE 802.11be-2024 EHT MLO.

The byte oracles are a direct scalar transcription of 9.4.2.324 rather than a
production round trip.  State oracles separately update two eight-entry
direction matrices according to Clause 35.3.7.  Tables 9-417i--9-417m are
exhausted over every encoded support/code combination.  All checks are
integral and therefore use exact zero tolerance.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.wifi.eht_mlo import (
    WIFI_EHT_MLO_DIRECTION_DOWNLINK,
    WIFI_EHT_MLO_DIRECTION_UPLINK,
    WIFI_EHT_MLO_DIRECTION_BOTH,
    WIFI_EHT_MLO_TID_COUNT,
    WIFI_EHT_MLO_VALID_LINK_BITMAP,
    WIFI_EHT_MLO_EXPECTED_DURATION_MAX,
    WIFI_EHT_MLO_TU_US,
    WifiEhtTidToLinkElement,
    WifiEhtMloMappingState,
    wifi_eht_mlo_tid_to_link_encode,
    wifi_eht_mlo_tid_to_link_decode,
    wifi_eht_mlo_default_mapping_state,
    wifi_eht_mlo_apply_tid_to_link_element,
    wifi_eht_mlo_tid_link_state,
    wifi_eht_mlo_enabled_links,
    wifi_eht_mlo_eml_timing_decode,
    wifi_eht_mlo_mapping_switch_time_field,
    wifi_eht_mlo_expected_duration_field,
    wifi_eht_mlo_expected_duration_us,
)


def _zero_maps() -> List[Int]:
    return List[Int](length=WIFI_EHT_MLO_TID_COUNT, fill=0)


def _element(
    direction: Int,
    default_mapping: Bool,
    switch_present: Bool,
    switch_time: Int,
    duration_present: Bool,
    duration_tu: Int,
    mapping_size: Int,
    presence: Int,
    var maps: List[Int],
) -> WifiEhtTidToLinkElement:
    return WifiEhtTidToLinkElement(
        direction,
        default_mapping,
        switch_present,
        switch_time,
        duration_present,
        duration_tu,
        mapping_size,
        presence,
        maps ^,
    )


def _oracle_append_le16(mut output: List[UInt8], value: Int):
    output.append(UInt8(value % 256))
    output.append(UInt8((value // 256) % 256))


def _oracle_append_le24(mut output: List[UInt8], value: Int):
    output.append(UInt8(value % 256))
    output.append(UInt8((value // 256) % 256))
    output.append(UInt8((value // 65536) % 256))


def _oracle_payload(
    direction: Int,
    default_mapping: Bool,
    switch_present: Bool,
    switch_time: Int,
    duration_present: Bool,
    duration_tu: Int,
    mapping_size: Int,
    presence: Int,
    maps: List[Int],
) -> List[UInt8]:
    # Independent arithmetic form: use addition and division, not production
    # masks/shifts, and spell the normative field order directly.
    var control = direction
    control += 4 if default_mapping else 0
    control += 8 if switch_present else 0
    control += 16 if duration_present else 0
    control += 32 if mapping_size == 1 else 0
    var output = List[UInt8]()
    output.append(UInt8(control))
    if not default_mapping:
        output.append(UInt8(presence))
    if switch_present:
        _oracle_append_le16(output, switch_time)
    if duration_present:
        _oracle_append_le24(output, duration_tu)
    if not default_mapping:
        for tid in range(WIFI_EHT_MLO_TID_COUNT):
            if ((presence // (1 << tid)) % 2) == 0:
                continue
            output.append(UInt8(maps[tid] % 256))
            if mapping_size == 2:
                output.append(UInt8((maps[tid] // 256) % 256))
    return output ^


def _assert_bytes_equal(
    actual: List[UInt8], expected: List[UInt8]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(expected)):
        assert_equal(actual[index], expected[index])


def _copy(values: List[Int]) -> List[Int]:
    var result = List[Int](capacity=len(values))
    for index in range(len(values)):
        result.append(values[index])
    return result ^


def _next_seed(seed: UInt64) -> UInt64:
    return (
        seed * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    )


def _nonempty_subset(bits: Int, selector: Int) -> Int:
    var result = bits & selector
    if result != 0:
        return result
    for bit in range(15):
        if (bits & (1 << bit)) != 0:
            return 1 << bit
    return 0


def test_published_element_static_byte_vectors() raises:
    var maps = _zero_maps()
    maps[0] = 0x01
    maps[2] = 0x80
    maps[7] = 0x55
    var element = _element(
        WIFI_EHT_MLO_DIRECTION_BOTH,
        False,
        True,
        0x1234,
        True,
        0x010203,
        1,
        0x85,
        maps ^,
    )
    var encoded = wifi_eht_mlo_tid_to_link_encode(element)
    var expected: List[UInt8] = [
        0x3A, 0x85, 0x34, 0x12, 0x03, 0x02, 0x01, 0x01, 0x80, 0x55
    ]
    _assert_bytes_equal(encoded, expected)
    var decoded = wifi_eht_mlo_tid_to_link_decode(Span(encoded))
    assert_equal(decoded.direction, WIFI_EHT_MLO_DIRECTION_BOTH)
    assert_equal(decoded.default_link_mapping, False)
    assert_true(decoded.mapping_switch_time_present)
    assert_true(decoded.expected_duration_present)
    assert_equal(decoded.tid_presence_bitmap, 0x85)
    assert_equal(decoded.mapping_switch_time, 0x1234)
    assert_equal(decoded.expected_duration_tu, 0x010203)
    assert_equal(decoded.link_mapping_size_octets, 1)
    assert_equal(decoded.tid_link_bitmaps[0], 0x01)
    assert_equal(decoded.tid_link_bitmaps[2], 0x80)
    assert_equal(decoded.tid_link_bitmaps[7], 0x55)

    maps = _zero_maps()
    maps[0] = 0x0003
    maps[1] = 0x4000
    element = _element(
        WIFI_EHT_MLO_DIRECTION_UPLINK,
        False,
        False,
        0,
        False,
        0,
        2,
        0x03,
        maps ^,
    )
    encoded = wifi_eht_mlo_tid_to_link_encode(element)
    expected = [0x01, 0x03, 0x03, 0x00, 0x00, 0x40]
    _assert_bytes_equal(encoded, expected)

    element = _element(
        WIFI_EHT_MLO_DIRECTION_DOWNLINK,
        True,
        False,
        0,
        False,
        0,
        2,
        0,
        _zero_maps(),
    )
    encoded = wifi_eht_mlo_tid_to_link_encode(element)
    expected = [0x04]
    _assert_bytes_equal(encoded, expected)


def test_exhaustive_control_presence_and_independent_wire_oracle() raises:
    for direction in range(3):
        for mapping_size in range(1, 3):
            for switch_present_int in range(2):
                for duration_present_int in range(2):
                    var switch_present = switch_present_int == 1
                    var duration_present = duration_present_int == 1
                    var switch_time = 0xA50F if switch_present else 0
                    var duration = 0x5A1234 if duration_present else 0
                    var default_element = _element(
                        direction,
                        True,
                        switch_present,
                        switch_time,
                        duration_present,
                        duration,
                        mapping_size,
                        0,
                        _zero_maps(),
                    )
                    var actual = wifi_eht_mlo_tid_to_link_encode(
                        default_element
                    )
                    var expected = _oracle_payload(
                        direction,
                        True,
                        switch_present,
                        switch_time,
                        duration_present,
                        duration,
                        mapping_size,
                        0,
                        _zero_maps(),
                    )
                    _assert_bytes_equal(actual, expected)
                    var parsed = wifi_eht_mlo_tid_to_link_decode(Span(actual))
                    assert_equal(parsed.direction, direction)
                    assert_true(parsed.default_link_mapping)
                    assert_equal(
                        parsed.mapping_switch_time_present, switch_present
                    )
                    assert_equal(parsed.mapping_switch_time, switch_time)
                    assert_equal(
                        parsed.expected_duration_present, duration_present
                    )
                    assert_equal(parsed.expected_duration_tu, duration)
                    assert_equal(
                        parsed.link_mapping_size_octets, mapping_size
                    )
                    assert_equal(parsed.tid_presence_bitmap, 0)
                    for tid in range(WIFI_EHT_MLO_TID_COUNT):
                        assert_equal(parsed.tid_link_bitmaps[tid], 0)

            for presence in range(1, 256):
                var maps = _zero_maps()
                for tid in range(WIFI_EHT_MLO_TID_COUNT):
                    if (presence & (1 << tid)) == 0:
                        continue
                    maps[tid] = (
                        1 << (tid % 8)
                        if mapping_size == 1
                        else 1 << ((2 * tid + direction) % 15)
                    )
                var switch_present = (presence & 1) != 0
                var duration_present = (presence & 2) != 0
                var switch_time = (257 * presence + direction) & 0xFFFF
                var duration = (
                    (65537 * presence + mapping_size) & 0xFFFFFF
                )
                var element = _element(
                    direction,
                    False,
                    switch_present,
                    switch_time if switch_present else 0,
                    duration_present,
                    duration if duration_present else 0,
                    mapping_size,
                    presence,
                    maps ^,
                )
                var actual = wifi_eht_mlo_tid_to_link_encode(element)
                var expected = _oracle_payload(
                    direction,
                    False,
                    switch_present,
                    switch_time if switch_present else 0,
                    duration_present,
                    duration if duration_present else 0,
                    mapping_size,
                    presence,
                    element.tid_link_bitmaps,
                )
                _assert_bytes_equal(actual, expected)
                var parsed = wifi_eht_mlo_tid_to_link_decode(Span(actual))
                assert_equal(parsed.direction, direction)
                assert_equal(parsed.default_link_mapping, False)
                assert_equal(
                    parsed.mapping_switch_time_present, switch_present
                )
                assert_equal(
                    parsed.mapping_switch_time,
                    switch_time if switch_present else 0,
                )
                assert_equal(
                    parsed.expected_duration_present, duration_present
                )
                assert_equal(
                    parsed.expected_duration_tu,
                    duration if duration_present else 0,
                )
                assert_equal(parsed.link_mapping_size_octets, mapping_size)
                assert_equal(parsed.tid_presence_bitmap, presence)
                for tid in range(WIFI_EHT_MLO_TID_COUNT):
                    assert_equal(
                        parsed.tid_link_bitmaps[tid],
                        element.tid_link_bitmaps[tid],
                    )


def test_default_incremental_directional_state_and_link_sets() raises:
    var setup = 0x25  # Link IDs 0, 2, and 5.
    var state = wifi_eht_mlo_default_mapping_state(setup)
    for tid in range(WIFI_EHT_MLO_TID_COUNT):
        assert_equal(state.downlink_tid_links[tid], setup)
        assert_equal(state.uplink_tid_links[tid], setup)

    var maps = _zero_maps()
    maps[0] = 0x04
    maps[3] = 0x20
    var down_update = _element(
        WIFI_EHT_MLO_DIRECTION_DOWNLINK,
        False,
        False,
        0,
        False,
        0,
        2,
        0x09,
        maps ^,
    )
    var changed = wifi_eht_mlo_apply_tid_to_link_element(
        state, down_update, setup
    )
    assert_equal(changed.downlink_tid_links[0], 0x04)
    assert_equal(changed.downlink_tid_links[3], 0x20)
    assert_equal(changed.downlink_tid_links[1], setup)
    for tid in range(WIFI_EHT_MLO_TID_COUNT):
        assert_equal(changed.uplink_tid_links[tid], setup)

    var link_state = wifi_eht_mlo_tid_link_state(
        changed,
        setup,
        0x24,
        0,
        WIFI_EHT_MLO_DIRECTION_DOWNLINK,
    )
    assert_equal(link_state.mapped_links_bitmap, 0x04)
    assert_equal(link_state.active_mapped_links_bitmap, 0x04)
    assert_true(link_state.frame_allowed_on_any_active_link)
    link_state = wifi_eht_mlo_tid_link_state(
        changed,
        setup,
        0x20,
        0,
        WIFI_EHT_MLO_DIRECTION_DOWNLINK,
    )
    assert_equal(link_state.active_mapped_links_bitmap, 0)
    assert_true(not link_state.frame_allowed_on_any_active_link)
    assert_equal(
        wifi_eht_mlo_enabled_links(
            changed, setup, WIFI_EHT_MLO_DIRECTION_DOWNLINK
        ),
        setup,
    )

    var default_up = _element(
        WIFI_EHT_MLO_DIRECTION_UPLINK,
        True,
        False,
        0,
        False,
        0,
        2,
        0,
        _zero_maps(),
    )
    var reset_up = wifi_eht_mlo_apply_tid_to_link_element(
        changed, default_up, setup
    )
    for tid in range(WIFI_EHT_MLO_TID_COUNT):
        assert_equal(reset_up.uplink_tid_links[tid], setup)
    assert_equal(reset_up.downlink_tid_links[0], 0x04)


def test_seeded_mapping_state_matches_independent_matrix_oracle() raises:
    var seed = UInt64(0xBE202435A3A7)
    for sample_index in range(1024):
        seed = _next_seed(seed)
        var setup = Int(seed & UInt64(WIFI_EHT_MLO_VALID_LINK_BITMAP))
        if setup == 0:
            setup = 1 << (sample_index % 15)
        var default_state = wifi_eht_mlo_default_mapping_state(setup)
        for tid in range(8):
            assert_equal(default_state.downlink_tid_links[tid], setup)
            assert_equal(default_state.uplink_tid_links[tid], setup)
        var down = List[Int](capacity=8)
        var up = List[Int](capacity=8)
        for _ in range(8):
            seed = _next_seed(seed)
            down.append(_nonempty_subset(setup, Int(seed)))
            seed = _next_seed(seed)
            up.append(_nonempty_subset(setup, Int(seed)))
        var expected_down = _copy(down)
        var expected_up = _copy(up)
        var state = WifiEhtMloMappingState(down ^, up ^)

        seed = _next_seed(seed)
        var direction = Int(seed % UInt64(3))
        seed = _next_seed(seed)
        var presence = Int(seed & UInt64(0xFF))
        if presence == 0:
            presence = 1 << (sample_index % 8)
        var maps = _zero_maps()
        for tid in range(8):
            if (presence & (1 << tid)) == 0:
                continue
            seed = _next_seed(seed)
            maps[tid] = _nonempty_subset(setup, Int(seed))
            if (
                direction == WIFI_EHT_MLO_DIRECTION_DOWNLINK
                or direction == WIFI_EHT_MLO_DIRECTION_BOTH
            ):
                expected_down[tid] = maps[tid]
            if (
                direction == WIFI_EHT_MLO_DIRECTION_UPLINK
                or direction == WIFI_EHT_MLO_DIRECTION_BOTH
            ):
                expected_up[tid] = maps[tid]
        var element = _element(
            direction,
            False,
            False,
            0,
            False,
            0,
            2,
            presence,
            maps ^,
        )
        var actual = wifi_eht_mlo_apply_tid_to_link_element(
            state, element, setup
        )
        var expected_enabled_downlink = 0
        for tid in range(8):
            assert_equal(actual.downlink_tid_links[tid], expected_down[tid])
            assert_equal(actual.uplink_tid_links[tid], expected_up[tid])
            expected_enabled_downlink |= expected_down[tid]
            var active = setup & (0x5555 if (tid & 1) == 0 else 0x2AAA)
            var decision = wifi_eht_mlo_tid_link_state(
                actual,
                setup,
                active,
                tid,
                WIFI_EHT_MLO_DIRECTION_DOWNLINK,
            )
            assert_equal(
                decision.active_mapped_links_bitmap,
                expected_down[tid] & active,
            )
        assert_equal(
            wifi_eht_mlo_enabled_links(
                actual, setup, WIFI_EHT_MLO_DIRECTION_DOWNLINK
            ),
            expected_enabled_downlink,
        )


def test_all_eml_timing_codes_against_independent_tables() raises:
    # Literal transcriptions of Tables 9-417i through 9-417m.  Keeping these
    # values tabular makes the oracle independent of the production shifts.
    var padding_table: List[Int] = [0, 32, 64, 128, 256]
    var emlsr_transition_table: List[Int] = [0, 16, 32, 64, 128, 256]
    var emlmr_transition_table: List[Int] = [0, 32, 64, 128, 256]
    var timeout_table: List[Int] = [
        0, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536
    ]
    for emlsr_int in range(2):
        for emlmr_int in range(2):
            var emlsr = emlsr_int == 1
            var emlmr = emlmr_int == 1
            for padding_code in range(8):
                for transition_code in range(8):
                    for timeout_code in range(16):
                        var field = (
                            emlsr_int
                            | (padding_code << 1)
                            | (transition_code << 4)
                            | (emlmr_int << 7)
                            | (timeout_code << 11)
                        )
                        var valid = padding_code <= 4 and timeout_code <= 10
                        if emlsr:
                            valid = valid and transition_code <= 5
                        if emlmr:
                            valid = valid and transition_code <= 4
                        if not emlsr and not emlmr:
                            valid = valid and padding_code == 0
                            valid = valid and transition_code == 0
                            valid = valid and timeout_code == 0
                        if not valid:
                            with assert_raises():
                                _ = wifi_eht_mlo_eml_timing_decode(field)
                            continue
                        var timing = wifi_eht_mlo_eml_timing_decode(field)
                        var expected_padding = (
                            padding_table[padding_code]
                            if emlsr or emlmr
                            else 0
                        )
                        var expected_emlsr = (
                            emlsr_transition_table[transition_code]
                            if emlsr
                            else 0
                        )
                        var expected_emlmr = (
                            emlmr_transition_table[transition_code]
                            if emlmr
                            else 0
                        )
                        var expected_timeout = timeout_table[timeout_code]
                        assert_equal(timing.emlsr_supported, emlsr)
                        assert_equal(timing.emlmr_supported, emlmr)
                        assert_equal(timing.padding_delay_us, expected_padding)
                        assert_equal(
                            timing.emlsr_transition_delay_us, expected_emlsr
                        )
                        assert_equal(
                            timing.emlmr_transition_delay_us, expected_emlmr
                        )
                        assert_equal(
                            timing.transition_timeout_us, expected_timeout
                        )

    var emlsr_max = wifi_eht_mlo_eml_timing_decode(0x5059)
    assert_equal(emlsr_max.padding_delay_us, 256)
    assert_equal(emlsr_max.emlsr_transition_delay_us, 256)
    assert_equal(emlsr_max.transition_timeout_us, 65536)
    var both = wifi_eht_mlo_eml_timing_decode(0x20C7)
    assert_equal(both.padding_delay_us, 128)
    assert_equal(both.emlsr_transition_delay_us, 128)
    assert_equal(both.emlmr_transition_delay_us, 256)
    assert_equal(both.transition_timeout_us, 1024)


def test_tsf_duration_arithmetic_boundaries_and_seeded_properties() raises:
    assert_equal(wifi_eht_mlo_mapping_switch_time_field(UInt64(0)), 0)
    assert_equal(wifi_eht_mlo_mapping_switch_time_field(UInt64(1023)), 0)
    assert_equal(wifi_eht_mlo_mapping_switch_time_field(UInt64(1024)), 1)
    assert_equal(
        wifi_eht_mlo_mapping_switch_time_field(UInt64(65536 * 1024)), 0
    )
    assert_equal(
        wifi_eht_mlo_mapping_switch_time_field(UInt64(1) << 63), 0
    )
    assert_equal(
        wifi_eht_mlo_mapping_switch_time_field(UInt64.MAX),
        Int((UInt64.MAX // UInt64(1024)) & UInt64(0xFFFF)),
    )
    assert_equal(wifi_eht_mlo_expected_duration_field(0), 0)
    assert_equal(wifi_eht_mlo_expected_duration_field(1024), 1)
    assert_equal(wifi_eht_mlo_expected_duration_us(1), 1024)
    var maximum_us = WIFI_EHT_MLO_EXPECTED_DURATION_MAX * WIFI_EHT_MLO_TU_US
    assert_equal(
        wifi_eht_mlo_expected_duration_field(maximum_us),
        WIFI_EHT_MLO_EXPECTED_DURATION_MAX,
    )
    assert_equal(
        wifi_eht_mlo_expected_duration_us(
            WIFI_EHT_MLO_EXPECTED_DURATION_MAX
        ),
        maximum_us,
    )

    var seed = UInt64(0x9E3779B97F4A7C15)
    for _ in range(4096):
        seed = _next_seed(seed)
        var tsf = seed
        assert_equal(
            wifi_eht_mlo_mapping_switch_time_field(tsf),
            Int((tsf // UInt64(1024)) & UInt64(0xFFFF)),
        )
        seed = _next_seed(seed)
        var duration_tu = Int(seed & UInt64(0xFFFFFF))
        var duration_us = duration_tu * 1024
        assert_equal(
            wifi_eht_mlo_expected_duration_field(duration_us), duration_tu
        )
        assert_equal(
            wifi_eht_mlo_expected_duration_us(duration_tu), duration_us
        )


def test_invalid_mutable_overflow_reserved_and_length_edges() raises:
    var maps = _zero_maps()
    maps[0] = 1
    var element = _element(
        WIFI_EHT_MLO_DIRECTION_DOWNLINK,
        False,
        False,
        0,
        False,
        0,
        2,
        1,
        maps ^,
    )
    element.direction = 3
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_encode(element)
    element.direction = WIFI_EHT_MLO_DIRECTION_DOWNLINK
    element.tid_link_bitmaps[0] = 0
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_encode(element)
    element.tid_link_bitmaps[0] = 0x8000
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_encode(element)
    element.tid_link_bitmaps[0] = 1
    element.link_mapping_size_octets = 3
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_encode(element)
    element.link_mapping_size_octets = 2
    element.mapping_switch_time = 1
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_encode(element)
    element.mapping_switch_time = 0
    element.expected_duration_tu = 1
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_encode(element)

    var short_maps = List[Int](length=7, fill=0)
    var short_element = _element(
        WIFI_EHT_MLO_DIRECTION_DOWNLINK,
        False,
        False,
        0,
        False,
        0,
        2,
        1,
        short_maps ^,
    )
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_encode(short_element)
    maps = _zero_maps()
    maps[0] = 0x100
    var oversized_one_octet = _element(
        WIFI_EHT_MLO_DIRECTION_DOWNLINK,
        False,
        False,
        0,
        False,
        0,
        1,
        1,
        maps ^,
    )
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_encode(oversized_one_octet)

    var reserved: List[UInt8] = [0xC4]
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_decode(Span(reserved))
    var direction_reserved: List[UInt8] = [0x07]
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_decode(Span(direction_reserved))
    var missing_presence: List[UInt8] = [0x00]
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_decode(Span(missing_presence))
    var truncated_switch: List[UInt8] = [0x0C, 0x01]
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_decode(Span(truncated_switch))
    var zero_mapping: List[UInt8] = [0x00, 0x01, 0x00, 0x00]
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_decode(Span(zero_mapping))
    var link15_mapping: List[UInt8] = [0x00, 0x01, 0x00, 0x80]
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_decode(Span(link15_mapping))
    var trailing: List[UInt8] = [0x04, 0x00]
    with assert_raises():
        _ = wifi_eht_mlo_tid_to_link_decode(Span(trailing))

    var state = wifi_eht_mlo_default_mapping_state(0x03)
    state.downlink_tid_links[0] = 0
    with assert_raises():
        _ = wifi_eht_mlo_apply_tid_to_link_element(state, element, 0x03)
    with assert_raises():
        _ = wifi_eht_mlo_enabled_links(state, 0x03)
    state.downlink_tid_links[0] = 0x04
    with assert_raises():
        _ = wifi_eht_mlo_enabled_links(state, 0x03)
    state.downlink_tid_links[0] = 0x03
    with assert_raises():
        _ = wifi_eht_mlo_tid_link_state(
            state, 0x03, 0x04, 0, WIFI_EHT_MLO_DIRECTION_DOWNLINK
        )
    with assert_raises():
        _ = wifi_eht_mlo_tid_link_state(
            state, 0x03, 0x03, 8, WIFI_EHT_MLO_DIRECTION_DOWNLINK
        )
    with assert_raises():
        _ = wifi_eht_mlo_tid_link_state(
            state, 0x03, 0x03, 0, WIFI_EHT_MLO_DIRECTION_BOTH
        )
    var short_state = WifiEhtMloMappingState(
        List[Int](length=7, fill=1), List[Int](length=8, fill=1)
    )
    with assert_raises():
        _ = wifi_eht_mlo_enabled_links(short_state, 0x03)

    with assert_raises():
        _ = wifi_eht_mlo_default_mapping_state(0)
    with assert_raises():
        _ = wifi_eht_mlo_default_mapping_state(0x8000)
    with assert_raises():
        _ = wifi_eht_mlo_expected_duration_field(1)
    with assert_raises():
        _ = wifi_eht_mlo_expected_duration_field(Int.MAX)
    with assert_raises():
        _ = wifi_eht_mlo_expected_duration_us(-1)
    with assert_raises():
        _ = wifi_eht_mlo_expected_duration_us(0x1000000)
    with assert_raises():
        _ = wifi_eht_mlo_eml_timing_decode(-1)
    with assert_raises():
        _ = wifi_eht_mlo_eml_timing_decode(0x10000)
    with assert_raises():
        _ = wifi_eht_mlo_eml_timing_decode(0x0100)
    with assert_raises():
        _ = wifi_eht_mlo_eml_timing_decode(0x0200)
    with assert_raises():
        _ = wifi_eht_mlo_eml_timing_decode(0x0400)
    with assert_raises():
        _ = wifi_eht_mlo_eml_timing_decode(0x8000)
    with assert_raises():
        _ = wifi_eht_mlo_eml_timing_decode(0x000A)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
