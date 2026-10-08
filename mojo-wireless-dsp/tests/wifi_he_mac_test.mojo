"""Independent exact evidence for the bounded IEEE 802.11-2024 HE MAC.

Hand-evaluated Clause-26 vectors, an exhaustive independent transcription of
Trigger Table 9-53, and seeded scalar state-machine oracles are used.  A
production encoder/decoder round trip is only supplementary evidence.  Every
result is integral, so tolerance is exactly zero.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.wireless.wifi.he_mac import (
    WIFI_HE_BSS_INTRA,
    WIFI_HE_BSS_INTER,
    WIFI_HE_BSS_UNCLASSIFIED,
    WIFI_HE_NAV_SOURCE_NONE,
    WIFI_HE_NAV_UPDATED_NONE,
    WIFI_HE_NAV_UPDATED_INTRA_BSS,
    WIFI_HE_NAV_UPDATED_BASIC,
    WIFI_HE_RU_SEGMENT_PRIMARY_80,
    WIFI_HE_RU_SEGMENT_SECONDARY_80,
    WIFI_HE_RU_SEGMENT_BOTH_80,
    WIFI_HE_TRIGGER_USER_ASSOCIATED_RANDOM_ACCESS,
    WIFI_HE_TRIGGER_USER_ASSOCIATED,
    WIFI_HE_TRIGGER_USER_UNASSOCIATED_RANDOM_ACCESS,
    WIFI_HE_TRIGGER_USER_UNALLOCATED,
    WifiHeMacProfile,
    WifiHeDualNavState,
    wifi_he_txop_duration_decode,
    wifi_he_txop_duration_encode,
    wifi_he_dual_nav_update_from_frame,
    wifi_he_dual_nav_update_from_txop_subfield,
    wifi_he_dual_nav_remaining,
    wifi_he_cf_end_reset_decision,
    wifi_he_dual_nav_apply_reset,
    wifi_he_nav_reset_timeout_us,
    wifi_he_trigger_ru_decode,
    wifi_he_trigger_ru_encode,
    wifi_he_trigger_user_allocation_plan,
)


def _oracle_ru_valid(bandwidth_mhz: Int, allocation: Int) -> Bool:
    if allocation < 0 or allocation > 255:
        return False
    var code = allocation // 2
    var b0 = allocation % 2
    if bandwidth_mhz == 20:
        return b0 == 0 and (
            code <= 8
            or (code >= 37 and code <= 40)
            or (code >= 53 and code <= 54)
            or code == 61
        )
    if bandwidth_mhz == 40:
        return b0 == 0 and (
            code <= 17
            or (code >= 37 and code <= 44)
            or (code >= 53 and code <= 56)
            or (code >= 61 and code <= 62)
            or code == 65
        )
    if bandwidth_mhz == 80:
        return b0 == 0 and code <= 67
    if bandwidth_mhz == 160:
        return code <= 67 or (code == 68 and b0 == 1)
    return False


def _oracle_ru_tones(code: Int) -> Int:
    if code <= 36:
        return 26
    if code <= 52:
        return 52
    if code <= 60:
        return 106
    if code <= 64:
        return 242
    if code <= 66:
        return 484
    if code == 67:
        return 996
    return 1992


def _oracle_ru_index(code: Int) -> Int:
    if code <= 36:
        return code + 1
    if code <= 52:
        return code - 36
    if code <= 60:
        return code - 52
    if code <= 64:
        return code - 60
    if code <= 66:
        return code - 64
    return 1


def _oracle_ru_segment(bandwidth_mhz: Int, allocation: Int) -> Int:
    var code = allocation // 2
    if code == 68:
        return WIFI_HE_RU_SEGMENT_BOTH_80
    if bandwidth_mhz == 160 and allocation % 2 == 1:
        return WIFI_HE_RU_SEGMENT_SECONDARY_80
    return WIFI_HE_RU_SEGMENT_PRIMARY_80


def test_he_dual_nav_and_txop_static_vectors() raises:
    var profile = WifiHeMacProfile(False, True, 80)
    var empty = WifiHeDualNavState()
    var intra = wifi_he_dual_nav_update_from_frame(
        profile,
        empty,
        1000,
        200,
        WIFI_HE_BSS_INTRA,
        receiver_address_is_self=False,
        sta_is_txop_holder=False,
        solicits_immediate_response=False,
        frame_is_trigger=False,
    )
    assert_equal(intra.updated_nav, WIFI_HE_NAV_UPDATED_INTRA_BSS)
    assert_equal(intra.state.intra_bss_nav_end_us, 1200)
    assert_equal(intra.state.basic_nav_end_us, 0)

    # Addressed to a TXOP holder: none of the three intra-BSS exceptions.
    var suppressed = wifi_he_dual_nav_update_from_frame(
        profile,
        intra.state,
        1000,
        300,
        WIFI_HE_BSS_INTRA,
        receiver_address_is_self=True,
        sta_is_txop_holder=True,
        solicits_immediate_response=True,
        frame_is_trigger=True,
    )
    assert_equal(suppressed.updated_nav, WIFI_HE_NAV_UPDATED_NONE)
    assert_equal(suppressed.state.intra_bss_nav_end_us, 1200)

    # A Trigger addressed to a non-holder takes the explicit third exception.
    var trigger = wifi_he_dual_nav_update_from_frame(
        profile,
        intra.state,
        1000,
        300,
        WIFI_HE_BSS_INTRA,
        receiver_address_is_self=True,
        sta_is_txop_holder=False,
        solicits_immediate_response=True,
        frame_is_trigger=True,
    )
    assert_equal(trigger.updated_nav, WIFI_HE_NAV_UPDATED_INTRA_BSS)
    assert_equal(trigger.state.intra_bss_nav_end_us, 1300)

    var basic = wifi_he_dual_nav_update_from_frame(
        profile,
        trigger.state,
        1000,
        350,
        WIFI_HE_BSS_UNCLASSIFIED,
        receiver_address_is_self=False,
        sta_is_txop_holder=False,
        solicits_immediate_response=False,
        frame_is_trigger=False,
    )
    assert_equal(basic.updated_nav, WIFI_HE_NAV_UPDATED_BASIC)
    assert_equal(basic.state.basic_nav_end_us, 1350)
    assert_equal(basic.state.basic_nav_source, WIFI_HE_BSS_UNCLASSIFIED)

    var remaining = wifi_he_dual_nav_remaining(profile, basic.state, 1100)
    assert_equal(remaining.intra_bss_us, 200)
    assert_equal(remaining.basic_us, 250)
    assert_true(remaining.medium_busy)
    var expired = wifi_he_dual_nav_remaining(profile, basic.state, 1400)
    assert_equal(expired.intra_bss_us, 0)
    assert_equal(expired.basic_us, 0)
    assert_true(not expired.medium_busy)

    var decision = wifi_he_cf_end_reset_decision(
        profile, basic.state, 1100, WIFI_HE_BSS_INTRA
    )
    assert_true(decision.reset_intra_bss_nav)
    assert_true(not decision.reset_basic_nav)
    assert_true(decision.reset_both_permitted)
    var reset = wifi_he_dual_nav_apply_reset(
        profile,
        basic.state,
        1100,
        reset_intra_bss_nav=True,
        reset_basic_nav=True,
    )
    assert_equal(reset.state.intra_bss_nav_end_us, 0)
    assert_equal(reset.state.basic_nav_end_us, 0)
    assert_equal(reset.state.basic_nav_source, WIFI_HE_NAV_SOURCE_NONE)
    assert_true(reset.phy_cca_reset_required)
    assert_equal(wifi_he_nav_reset_timeout_us(16, 44, 4, 9), 98)

    assert_equal(wifi_he_txop_duration_encode(0), 0)
    assert_equal(wifi_he_txop_duration_encode(511), 126)
    assert_equal(wifi_he_txop_duration_encode(512), 1)
    assert_equal(wifi_he_txop_duration_encode(8448), 125)
    assert_equal(wifi_he_txop_duration_encode(0, unspecified=True), 127)
    var quantized = wifi_he_txop_duration_decode(126)
    assert_true(quantized.specified)
    assert_equal(quantized.duration_us, 504)
    var unspecified = wifi_he_txop_duration_decode(127)
    assert_true(not unspecified.specified)
    assert_equal(unspecified.duration_us, 0)

    # Field 3 is B0=1, B1-B6=1, hence 512 + 128 = 640 us.
    var txop = wifi_he_dual_nav_update_from_txop_subfield(
        profile,
        empty,
        1000,
        3,
        WIFI_HE_BSS_INTER,
        sta_is_txop_holder=True,
        ppdu_has_duration_field=False,
    )
    assert_equal(txop.updated_nav, WIFI_HE_NAV_UPDATED_BASIC)
    assert_equal(txop.state.basic_nav_end_us, 1640)
    assert_equal(txop.state.basic_nav_source, WIFI_HE_BSS_INTER)
    var duration_wins = wifi_he_dual_nav_update_from_txop_subfield(
        profile,
        txop.state,
        1000,
        125,
        WIFI_HE_BSS_INTER,
        sta_is_txop_holder=False,
        ppdu_has_duration_field=True,
    )
    assert_equal(duration_wins.updated_nav, WIFI_HE_NAV_UPDATED_NONE)
    assert_equal(duration_wins.state.basic_nav_end_us, 1640)


def test_he_trigger_user_ru_static_vectors() raises:
    var p20 = WifiHeMacProfile(True, False, 20)
    var p40 = WifiHeMacProfile(True, False, 40)
    var p80 = WifiHeMacProfile(True, False, 80)
    var p160 = WifiHeMacProfile(True, False, 160)
    var p8080 = WifiHeMacProfile(True, False, 160, True)

    var ru = wifi_he_trigger_ru_decode(p20, 0)
    assert_equal(ru.ru_tones, 26)
    assert_equal(ru.ru_index, 1)
    ru = wifi_he_trigger_ru_decode(p20, 16)
    assert_equal(ru.ru_tones, 26)
    assert_equal(ru.ru_index, 9)
    ru = wifi_he_trigger_ru_decode(p20, 80)
    assert_equal(ru.ru_tones, 52)
    assert_equal(ru.ru_index, 4)
    ru = wifi_he_trigger_ru_decode(p20, 108)
    assert_equal(ru.ru_tones, 106)
    assert_equal(ru.ru_index, 2)
    ru = wifi_he_trigger_ru_decode(p20, 122)
    assert_equal(ru.ru_tones, 242)
    assert_equal(ru.ru_index, 1)

    ru = wifi_he_trigger_ru_decode(p40, 34)
    assert_equal(ru.ru_tones, 26)
    assert_equal(ru.ru_index, 18)
    ru = wifi_he_trigger_ru_decode(p40, 130)
    assert_equal(ru.ru_tones, 484)
    assert_equal(ru.ru_index, 1)

    ru = wifi_he_trigger_ru_decode(p80, 72)
    assert_equal(ru.ru_tones, 26)
    assert_equal(ru.ru_index, 37)
    ru = wifi_he_trigger_ru_decode(p80, 132)
    assert_equal(ru.ru_tones, 484)
    assert_equal(ru.ru_index, 2)
    ru = wifi_he_trigger_ru_decode(p80, 134)
    assert_equal(ru.ru_tones, 996)
    assert_equal(ru.ru_index, 1)

    ru = wifi_he_trigger_ru_decode(p160, 1)
    assert_equal(ru.ru_tones, 26)
    assert_equal(ru.ru_index, 1)
    assert_equal(ru.segment_80, WIFI_HE_RU_SEGMENT_SECONDARY_80)
    ru = wifi_he_trigger_ru_decode(p8080, 137)
    assert_equal(ru.ru_tones, 1992)
    assert_equal(ru.ru_index, 1)
    assert_equal(ru.segment_80, WIFI_HE_RU_SEGMENT_BOTH_80)

    assert_equal(wifi_he_trigger_ru_encode(p20, 52, 4), 80)
    assert_equal(wifi_he_trigger_ru_encode(p40, 484, 1), 130)
    assert_equal(wifi_he_trigger_ru_encode(p80, 996, 1), 134)
    assert_equal(
        wifi_he_trigger_ru_encode(
            p160, 26, 37, WIFI_HE_RU_SEGMENT_SECONDARY_80
        ),
        73,
    )
    assert_equal(
        wifi_he_trigger_ru_encode(
            p8080, 1992, 1, WIFI_HE_RU_SEGMENT_BOTH_80
        ),
        137,
    )

    var associated_ra = wifi_he_trigger_user_allocation_plan(
        p20, 0, 74, number_of_ra_ru_field=3
    )
    assert_equal(
        associated_ra.user_kind,
        WIFI_HE_TRIGGER_USER_ASSOCIATED_RANDOM_ACCESS,
    )
    assert_equal(associated_ra.first_ru.ru_tones, 52)
    assert_equal(associated_ra.first_ru.ru_index, 1)
    assert_equal(associated_ra.number_of_rus, 4)
    assert_equal(associated_ra.last_ru_index, 4)
    assert_equal(associated_ra.last_ru_allocation, 80)
    var addressed = wifi_he_trigger_user_allocation_plan(p80, 123, 134)
    assert_equal(addressed.user_kind, WIFI_HE_TRIGGER_USER_ASSOCIATED)
    assert_equal(addressed.number_of_rus, 1)
    var unassociated_ra = wifi_he_trigger_user_allocation_plan(
        p40, 2045, 0, number_of_ra_ru_field=4
    )
    assert_equal(
        unassociated_ra.user_kind,
        WIFI_HE_TRIGGER_USER_UNASSOCIATED_RANDOM_ACCESS,
    )
    assert_equal(unassociated_ra.number_of_rus, 5)
    var unallocated = wifi_he_trigger_user_allocation_plan(p80, 2046, 134)
    assert_equal(
        unallocated.user_kind, WIFI_HE_TRIGGER_USER_UNALLOCATED
    )


def test_he_mac_edges_overflow_and_mutable_profile_revalidation() raises:
    var profile = WifiHeMacProfile(False, True, 80)
    var state = WifiHeDualNavState()
    profile.maintains_two_nav = False
    with assert_raises():
        _ = wifi_he_dual_nav_remaining(profile, state, 0)
    with assert_raises():
        _ = wifi_he_trigger_ru_decode(profile, 0)
    profile.maintains_two_nav = True
    profile.ul_bandwidth_mhz = 30
    with assert_raises():
        _ = wifi_he_trigger_ru_decode(profile, 0)
    profile.ul_bandwidth_mhz = 80
    profile.is_80_plus_80 = True
    with assert_raises():
        _ = wifi_he_trigger_ru_decode(profile, 0)

    var ap_single_nav = WifiHeMacProfile(True, False, 80)
    assert_equal(wifi_he_trigger_ru_decode(ap_single_nav, 0).ru_index, 1)
    with assert_raises():
        _ = wifi_he_dual_nav_remaining(ap_single_nav, state, 0)
    var bad_state = WifiHeDualNavState(0, 1, WIFI_HE_NAV_SOURCE_NONE)
    with assert_raises():
        _ = wifi_he_dual_nav_remaining(
            WifiHeMacProfile(False, True, 80), bad_state, 0
        )
    with assert_raises():
        _ = wifi_he_dual_nav_update_from_frame(
            WifiHeMacProfile(False, True, 80),
            state,
            0,
            1,
            9,
            receiver_address_is_self=False,
            sta_is_txop_holder=False,
            solicits_immediate_response=False,
            frame_is_trigger=False,
        )
    with assert_raises():
        _ = wifi_he_dual_nav_update_from_frame(
            WifiHeMacProfile(False, True, 80),
            state,
            Int.MAX,
            1,
            WIFI_HE_BSS_INTRA,
            receiver_address_is_self=False,
            sta_is_txop_holder=False,
            solicits_immediate_response=False,
            frame_is_trigger=False,
        )
    with assert_raises():
        _ = wifi_he_dual_nav_update_from_frame(
            WifiHeMacProfile(False, True, 80),
            state,
            0,
            32768,
            WIFI_HE_BSS_INTRA,
            receiver_address_is_self=False,
            sta_is_txop_holder=False,
            solicits_immediate_response=False,
            frame_is_trigger=False,
        )
    with assert_raises():
        _ = wifi_he_dual_nav_apply_reset(
            WifiHeMacProfile(False, True, 80),
            state,
            0,
            reset_intra_bss_nav=False,
            reset_basic_nav=False,
        )
    with assert_raises():
        _ = wifi_he_dual_nav_remaining(
            WifiHeMacProfile(False, True, 80), state, -1
        )
    with assert_raises():
        _ = wifi_he_dual_nav_update_from_txop_subfield(
            WifiHeMacProfile(False, True, 80),
            state,
            Int.MAX,
            1,
            WIFI_HE_BSS_INTER,
            sta_is_txop_holder=False,
            ppdu_has_duration_field=False,
        )
    with assert_raises():
        _ = wifi_he_cf_end_reset_decision(
            WifiHeMacProfile(False, True, 80),
            state,
            -1,
            WIFI_HE_BSS_INTRA,
        )
    with assert_raises():
        _ = wifi_he_dual_nav_apply_reset(
            WifiHeMacProfile(False, True, 80),
            state,
            -1,
            reset_intra_bss_nav=True,
            reset_basic_nav=False,
        )
    with assert_raises():
        _ = wifi_he_nav_reset_timeout_us(Int.MAX, 1, 0, 1)
    with assert_raises():
        _ = wifi_he_nav_reset_timeout_us(16, 0, 4, 9)

    with assert_raises():
        _ = wifi_he_txop_duration_decode(-1)
    with assert_raises():
        _ = wifi_he_txop_duration_decode(128)
    with assert_raises():
        _ = wifi_he_txop_duration_encode(8449)
    with assert_raises():
        _ = wifi_he_txop_duration_encode(1, unspecified=True)

    var p20 = WifiHeMacProfile(True, False, 20)
    var p80 = WifiHeMacProfile(True, False, 80)
    var p160 = WifiHeMacProfile(True, False, 160)
    with assert_raises():
        _ = wifi_he_trigger_ru_decode(p20, 1)
    with assert_raises():
        _ = wifi_he_trigger_ru_decode(p20, 18)
    with assert_raises():
        _ = wifi_he_trigger_ru_decode(p80, 136)
    with assert_raises():
        _ = wifi_he_trigger_ru_decode(p160, 136)
    with assert_raises():
        _ = wifi_he_trigger_ru_decode(p160, 138)
    with assert_raises():
        _ = wifi_he_trigger_ru_encode(p20, 484, 1)
    with assert_raises():
        _ = wifi_he_trigger_ru_encode(
            p160, 996, 1, WIFI_HE_RU_SEGMENT_BOTH_80
        )
    with assert_raises():
        _ = wifi_he_trigger_ru_encode(p80, 52, 0)
    with assert_raises():
        _ = wifi_he_trigger_user_allocation_plan(
            p20, 2008, 0, number_of_ra_ru_field=0
        )
    with assert_raises():
        _ = wifi_he_trigger_user_allocation_plan(p20, 4095, 0)
    with assert_raises():
        _ = wifi_he_trigger_user_allocation_plan(
            p20, 1, 0, number_of_ra_ru_field=0
        )
    with assert_raises():
        _ = wifi_he_trigger_user_allocation_plan(
            p20, 0, 16, number_of_ra_ru_field=1
        )
    with assert_raises():
        _ = wifi_he_trigger_user_allocation_plan(
            p20, 0, 0, number_of_ra_ru_field=32
        )


def test_seeded_he_mac_state_and_allocation_properties() raises:
    var profile = WifiHeMacProfile(False, True, 80)
    var ru_profile = WifiHeMacProfile(True, False, 80)
    var seed = UInt64(0x11A82024D001C0DE)
    for iteration in range(257):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var ppdu_end = 1000 + Int((seed >> 8) % UInt64(10000))
        var current_remaining = Int((seed >> 24) % UInt64(512))
        var duration = Int((seed >> 36) % UInt64(512))
        var state = WifiHeDualNavState(
            ppdu_end + current_remaining, 0, WIFI_HE_NAV_SOURCE_NONE
        )
        var result = wifi_he_dual_nav_update_from_frame(
            profile,
            state,
            ppdu_end,
            duration,
            WIFI_HE_BSS_INTRA,
            receiver_address_is_self=False,
            sta_is_txop_holder=(iteration & 1) == 0,
            solicits_immediate_response=(iteration & 2) == 0,
            frame_is_trigger=(iteration & 4) == 0,
        )
        if duration > current_remaining:
            assert_equal(
                result.updated_nav, WIFI_HE_NAV_UPDATED_INTRA_BSS
            )
            assert_equal(
                result.state.intra_bss_nav_end_us, ppdu_end + duration
            )
        else:
            assert_equal(result.updated_nav, WIFI_HE_NAV_UPDATED_NONE)
            assert_equal(
                result.state.intra_bss_nav_end_us,
                ppdu_end + current_remaining,
            )
        var remaining = wifi_he_dual_nav_remaining(
            profile, state, ppdu_end
        )
        assert_equal(remaining.intra_bss_us, current_remaining)
        assert_equal(remaining.basic_us, 0)
        assert_equal(remaining.medium_busy, current_remaining != 0)

        var field = Int(seed & UInt64(127))
        var decoded = wifi_he_txop_duration_decode(field)
        if field == 127:
            assert_true(not decoded.specified)
            assert_equal(decoded.duration_us, 0)
        elif field % 2 == 0:
            assert_true(decoded.specified)
            assert_equal(decoded.duration_us, 8 * (field // 2))
        else:
            assert_true(decoded.specified)
            assert_equal(decoded.duration_us, 512 + 128 * (field // 2))
        var normalized_duration = Int((seed >> 7) % UInt64(8449))
        var encoded_duration = wifi_he_txop_duration_encode(
            normalized_duration
        )
        var expected_field: Int
        if normalized_duration < 512:
            expected_field = 2 * (normalized_duration // 8)
        else:
            expected_field = 1 + 2 * ((normalized_duration - 512) // 128)
        assert_equal(encoded_duration, expected_field)

        var txop = wifi_he_dual_nav_update_from_txop_subfield(
            profile,
            WifiHeDualNavState(),
            ppdu_end,
            field,
            WIFI_HE_BSS_INTER,
            sta_is_txop_holder=(iteration & 1) == 0,
            ppdu_has_duration_field=False,
        )
        if decoded.specified and decoded.duration_us > 0:
            assert_equal(txop.updated_nav, WIFI_HE_NAV_UPDATED_BASIC)
            assert_equal(
                txop.state.basic_nav_end_us,
                ppdu_end + decoded.duration_us,
            )
        else:
            assert_equal(txop.updated_nav, WIFI_HE_NAV_UPDATED_NONE)

        var reset_source = WifiHeDualNavState(
            ppdu_end + 20,
            ppdu_end + 30,
            WIFI_HE_BSS_UNCLASSIFIED,
        )
        var cf_classification = iteration % 3
        var cf = wifi_he_cf_end_reset_decision(
            profile, reset_source, ppdu_end, cf_classification
        )
        assert_equal(
            cf.reset_intra_bss_nav,
            cf_classification == WIFI_HE_BSS_INTRA,
        )
        assert_equal(
            cf.reset_basic_nav,
            cf_classification == WIFI_HE_BSS_INTER,
        )
        assert_equal(
            cf.reset_both_permitted,
            cf_classification == WIFI_HE_BSS_INTRA,
        )
        var reset_intra = (iteration & 1) == 0
        var reset = wifi_he_dual_nav_apply_reset(
            profile,
            reset_source,
            ppdu_end,
            reset_intra_bss_nav=reset_intra,
            reset_basic_nav=not reset_intra,
        )
        assert_equal(
            reset.state.intra_bss_nav_end_us,
            0 if reset_intra else ppdu_end + 20,
        )
        assert_equal(
            reset.state.basic_nav_end_us,
            ppdu_end + 30 if reset_intra else 0,
        )
        assert_true(not reset.phy_cca_reset_required)

        var sifs = 1 + Int((seed >> 4) % UInt64(31))
        var cts = 1 + Int((seed >> 12) % UInt64(127))
        var rx_delay = Int((seed >> 20) % UInt64(31))
        var slot = 1 + Int((seed >> 28) % UInt64(31))
        assert_equal(
            wifi_he_nav_reset_timeout_us(sifs, cts, rx_delay, slot),
            2 * sifs + cts + rx_delay + 2 * slot,
        )

        var tones: Int
        var maximum: Int
        var base: Int
        var selector = iteration % 6
        if selector == 0:
            tones, maximum, base = 26, 37, -1
        elif selector == 1:
            tones, maximum, base = 52, 16, 36
        elif selector == 2:
            tones, maximum, base = 106, 8, 52
        elif selector == 3:
            tones, maximum, base = 242, 4, 60
        elif selector == 4:
            tones, maximum, base = 484, 2, 64
        else:
            tones, maximum, base = 996, 1, 66
        var index = 1 + Int((seed >> 12) % UInt64(maximum))
        var expected_code = base + index
        var allocation = wifi_he_trigger_ru_encode(
            profile, tones, index
        )
        assert_equal(allocation, 2 * expected_code)
        var decoded_ru = wifi_he_trigger_ru_decode(profile, allocation)
        assert_equal(decoded_ru.ru_tones, tones)
        assert_equal(decoded_ru.ru_index, index)

        var count_field = Int((seed >> 44) & UInt64(31))
        var user = wifi_he_trigger_user_allocation_plan(
            ru_profile, 0, 0, number_of_ra_ru_field=count_field
        )
        assert_equal(user.number_of_rus, count_field + 1)
        assert_equal(user.last_ru_index, count_field + 1)
        assert_equal(user.last_ru_allocation, 2 * count_field)


def test_independent_trigger_table_and_nav_oracles_exact_tolerance() raises:
    # Full 8-bit-field oracle: discrete tolerance_mode=exact, tolerance=0.
    var bandwidths: List[Int] = [20, 40, 80, 160]
    for bandwidth in bandwidths:
        var profile = WifiHeMacProfile(True, False, bandwidth)
        for allocation in range(256):
            if _oracle_ru_valid(bandwidth, allocation):
                var decoded = wifi_he_trigger_ru_decode(
                    profile, allocation
                )
                var code = allocation // 2
                assert_equal(decoded.ru_tones, _oracle_ru_tones(code))
                assert_equal(decoded.ru_index, _oracle_ru_index(code))
                assert_equal(
                    decoded.segment_80,
                    _oracle_ru_segment(bandwidth, allocation),
                )
                assert_equal(
                    wifi_he_trigger_ru_encode(
                        profile,
                        _oracle_ru_tones(code),
                        _oracle_ru_index(code),
                        _oracle_ru_segment(bandwidth, allocation),
                    ),
                    allocation,
                )
            else:
                with assert_raises():
                    _ = wifi_he_trigger_ru_decode(profile, allocation)

    # Exhaustive independent transcription of the seven-bit TXOP table.
    for field in range(128):
        var decoded = wifi_he_txop_duration_decode(field)
        if field == 127:
            assert_true(not decoded.specified)
            assert_equal(decoded.duration_us, 0)
        elif field % 2 == 0:
            assert_true(decoded.specified)
            assert_equal(decoded.duration_us, 8 * (field // 2))
        else:
            assert_true(decoded.specified)
            assert_equal(decoded.duration_us, 512 + 128 * (field // 2))

    for duration in range(8449):
        var expected: Int
        if duration < 512:
            expected = 2 * (duration // 8)
        else:
            expected = 1 + 2 * ((duration - 512) // 128)
        assert_equal(wifi_he_txop_duration_encode(duration), expected)

    # Scalar oracle for addressed/basic NAV comparisons at the PPDU end.
    var profile = WifiHeMacProfile(False, True, 80)
    for classification in range(3):
        for duration in range(5):
            var state = WifiHeDualNavState(
                102, 103, WIFI_HE_BSS_INTER
            )
            var result = wifi_he_dual_nav_update_from_frame(
                profile,
                state,
                100,
                duration,
                classification,
                receiver_address_is_self=False,
                sta_is_txop_holder=True,
                solicits_immediate_response=True,
                frame_is_trigger=False,
            )
            if classification == WIFI_HE_BSS_INTRA:
                var expected = 100 + duration if duration > 2 else 102
                assert_equal(result.state.intra_bss_nav_end_us, expected)
                assert_equal(result.state.basic_nav_end_us, 103)
            else:
                var expected = 100 + duration if duration > 3 else 103
                assert_equal(result.state.basic_nav_end_us, expected)
                assert_equal(result.state.intra_bss_nav_end_us, 102)

    var active = WifiHeDualNavState(150, 175, WIFI_HE_BSS_UNCLASSIFIED)
    var remaining = wifi_he_dual_nav_remaining(profile, active, 125)
    assert_equal(remaining.intra_bss_us, 25)
    assert_equal(remaining.basic_us, 50)
    assert_true(remaining.medium_busy)
    var cf = wifi_he_cf_end_reset_decision(
        profile, active, 125, WIFI_HE_BSS_INTRA
    )
    assert_true(cf.reset_intra_bss_nav)
    assert_true(not cf.reset_basic_nav)
    assert_true(cf.reset_both_permitted)
    var reset = wifi_he_dual_nav_apply_reset(
        profile,
        active,
        125,
        reset_intra_bss_nav=True,
        reset_basic_nav=True,
    )
    assert_equal(reset.state.intra_bss_nav_end_us, 0)
    assert_equal(reset.state.basic_nav_end_us, 0)
    assert_true(reset.phy_cca_reset_required)
    assert_equal(wifi_he_nav_reset_timeout_us(10, 20, 3, 4), 51)

    for field in range(128):
        var decoded = wifi_he_txop_duration_decode(field)
        var update = wifi_he_dual_nav_update_from_txop_subfield(
            profile,
            WifiHeDualNavState(),
            100,
            field,
            WIFI_HE_BSS_INTER,
            sta_is_txop_holder=False,
            ppdu_has_duration_field=False,
        )
        var expected_end = (
            100 + decoded.duration_us
            if decoded.specified and decoded.duration_us > 0
            else 0
        )
        assert_equal(update.state.basic_nav_end_us, expected_end)

    var p80 = WifiHeMacProfile(True, False, 80)
    for count_field in range(32):
        var plan = wifi_he_trigger_user_allocation_plan(
            p80, 0, 0, number_of_ra_ru_field=count_field
        )
        assert_equal(plan.number_of_rus, count_field + 1)
        assert_equal(plan.last_ru_index, count_field + 1)
        assert_equal(plan.last_ru_allocation, 2 * count_field)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
