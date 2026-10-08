"""Independent evidence for Bluetooth Core 6.3 LE GFSK parameter limits.

All literals are transcribed from the Adopted Core 6.3 PDF, Vol 6, Part A,
Sections 1, 3.1, and 3.1.1 (official artifact SHA-256
e210fb8f697fca2b970001d35f8c9c7c8f836190550b7fd29d2915a1c8596d60).
The two complete rows and test-local predicates do not call production
factories or wrappers as an oracle.  Vol 6, Part H, Section 3.5.2, LE 2M 2BT,
waveform generation, and receive processing are intentionally absent.
"""

from std.collections import Span
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.bluetooth.gfsk import (
    BLUETOOTH_LE_GFSK_PHY_1M,
    BLUETOOTH_LE_GFSK_PHY_2M,
    BluetoothLEGFSKLimits,
    bluetooth_le_gfsk_limits,
    bluetooth_le_gfsk_modulation_index_is_compliant,
    bluetooth_le_gfsk_frequency_deviation_is_compliant,
    bluetooth_le_gfsk_timing_is_compliant,
    bluetooth_le_gfsk_bit_deviation_sign_is_compliant,
    bluetooth_le_gfsk_stable_claim_is_compliant,
)


def _assert_common_literals(profile: BluetoothLEGFSKLimits) raises:
    assert_equal(profile.bits_per_symbol, 1)
    assert_equal(profile.bandwidth_bit_period_product, 0.5)
    assert_equal(profile.modulation_index_minimum, 0.45)
    assert_equal(profile.modulation_index_maximum, 0.55)
    assert_equal(profile.stable_modulation_index_minimum, 0.495)
    assert_equal(profile.stable_modulation_index_maximum, 0.505)
    assert_equal(profile.minimum_frequency_deviation_ratio, 0.8)
    assert_equal(profile.maximum_absolute_symbol_timing_error_ppm, 50.0)
    assert_equal(
        profile.maximum_absolute_zero_crossing_error_symbol_periods, 0.125
    )
    assert_true(profile.binary_one_uses_positive_frequency_deviation)
    assert_true(profile.binary_zero_uses_negative_frequency_deviation)
    assert_true(profile.stable_claim_requires_all_supported_le_transmitter_phys)


def _assert_all_profile_consumers_reject(
    profile: BluetoothLEGFSKLimits
) raises:
    var stable_flags: List[Bool] = [True]
    with assert_raises():
        _ = bluetooth_le_gfsk_modulation_index_is_compliant(profile, 0.5)
    with assert_raises():
        _ = bluetooth_le_gfsk_frequency_deviation_is_compliant(
            profile, 400_000.0, 400_000.0, 400_000.0
        )
    with assert_raises():
        _ = bluetooth_le_gfsk_timing_is_compliant(profile, 0.0, 0.0)
    with assert_raises():
        _ = bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
            profile, 1, 1.0
        )
    with assert_raises():
        _ = bluetooth_le_gfsk_stable_claim_is_compliant(
            profile, Span(stable_flags), True
        )


def _next(mut state: UInt64) -> UInt64:
    state = state * UInt64(6364136223846793005) + UInt64(1442695040888963407)
    return state


def test_complete_two_row_literal_table() raises:
    var one = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    assert_equal(one.phy, BLUETOOTH_LE_GFSK_PHY_1M)
    assert_true(one.support_is_mandatory)
    assert_equal(one.symbol_rate_symbols_per_second, 1_000_000)
    assert_equal(one.uncoded_bit_rate_bits_per_second, 1_000_000)
    assert_equal(one.minimum_frequency_deviation_hz, 185_000)
    _assert_common_literals(one)

    var two = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    assert_equal(two.phy, BLUETOOTH_LE_GFSK_PHY_2M)
    assert_true(not two.support_is_mandatory)
    assert_equal(two.symbol_rate_symbols_per_second, 2_000_000)
    assert_equal(two.uncoded_bit_rate_bits_per_second, 2_000_000)
    assert_equal(two.minimum_frequency_deviation_hz, 370_000)
    _assert_common_literals(two)

    # LE 2M 2BT is a distinct Channel Sounding PHY and is not silently
    # accepted as a third row in this bounded profile.
    for invalid_phy in [0, 3, -1, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_gfsk_limits(invalid_phy)


def test_modulation_index_inclusive_standard_and_stable_endpoints() raises:
    for phy in [BLUETOOTH_LE_GFSK_PHY_1M, BLUETOOTH_LE_GFSK_PHY_2M]:
        var profile = bluetooth_le_gfsk_limits(phy)
        assert_true(
            bluetooth_le_gfsk_modulation_index_is_compliant(profile, 0.45)
        )
        assert_true(
            bluetooth_le_gfsk_modulation_index_is_compliant(profile, 0.55)
        )
        assert_true(not bluetooth_le_gfsk_modulation_index_is_compliant(
            profile, 0.449999999
        ))
        assert_true(not bluetooth_le_gfsk_modulation_index_is_compliant(
            profile, 0.550000001
        ))
        assert_true(bluetooth_le_gfsk_modulation_index_is_compliant(
            profile, 0.495, claims_stable_index=True
        ))
        assert_true(bluetooth_le_gfsk_modulation_index_is_compliant(
            profile, 0.505, claims_stable_index=True
        ))
        assert_true(not bluetooth_le_gfsk_modulation_index_is_compliant(
            profile, 0.494999999, claims_stable_index=True
        ))
        assert_true(not bluetooth_le_gfsk_modulation_index_is_compliant(
            profile, 0.505000001, claims_stable_index=True
        ))


def test_frequency_deviation_ratio_and_absolute_endpoints() raises:
    var one = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    assert_true(bluetooth_le_gfsk_frequency_deviation_is_compliant(
        one, 185_000.0, 250_000.0, 231_250.0
    ))
    assert_true(not bluetooth_le_gfsk_frequency_deviation_is_compliant(
        one, 184_999.0, 250_000.0, 0.0
    ))
    assert_true(not bluetooth_le_gfsk_frequency_deviation_is_compliant(
        one, 250_000.0, 184_999.0, 0.0
    ))
    assert_true(not bluetooth_le_gfsk_frequency_deviation_is_compliant(
        one, 250_000.0, 185_000.0, 231_251.0
    ))

    var two = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    assert_true(bluetooth_le_gfsk_frequency_deviation_is_compliant(
        two, 500_000.0, 370_000.0, 462_500.0
    ))
    assert_true(not bluetooth_le_gfsk_frequency_deviation_is_compliant(
        two, 369_999.0, 500_000.0, 0.0
    ))
    assert_true(not bluetooth_le_gfsk_frequency_deviation_is_compliant(
        two, 500_000.0, 369_999.0, 0.0
    ))
    assert_true(not bluetooth_le_gfsk_frequency_deviation_is_compliant(
        two, 370_000.0, 500_000.0, 462_501.0
    ))

    # Part A supplies minima, not a maximum frequency-deviation bound.
    assert_true(bluetooth_le_gfsk_frequency_deviation_is_compliant(
        two, Float64.MAX_FINITE, Float64.MAX_FINITE, Float64.MAX_FINITE
    ))


def test_strict_timing_endpoints_and_binary_deviation_signs() raises:
    var profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    for timing in [-49.999999, 0.0, 49.999999]:
        for crossing in [-0.124999999, 0.0, 0.124999999]:
            assert_true(bluetooth_le_gfsk_timing_is_compliant(
                profile, timing, crossing
            ))
    for timing in [-50.0, 50.0]:
        assert_true(not bluetooth_le_gfsk_timing_is_compliant(
            profile, timing, 0.0
        ))
    for crossing in [-0.125, 0.125]:
        assert_true(not bluetooth_le_gfsk_timing_is_compliant(
            profile, 0.0, crossing
        ))

    assert_true(bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
        profile, 1, Float64.MAX_FINITE
    ))
    assert_true(bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
        profile, 0, -Float64.MAX_FINITE
    ))
    assert_true(not bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
        profile, 1, -1.0
    ))
    assert_true(not bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
        profile, 0, 1.0
    ))
    assert_true(not bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
        profile, 1, 0.0
    ))
    assert_true(not bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
        profile, 0, -0.0
    ))
    for invalid_bit in [-1, 2, Int.MIN, Int.MAX]:
        with assert_raises():
            _ = bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
                profile, invalid_bit, 1.0
            )


def test_stable_claim_requires_every_supported_transmitter_phy() raises:
    var profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    var all_stable: List[Bool] = [True, True, True]
    var one_standard: List[Bool] = [True, False, True]
    var empty = List[Bool]()
    assert_true(bluetooth_le_gfsk_stable_claim_is_compliant(
        profile, Span(all_stable), True
    ))
    assert_true(not bluetooth_le_gfsk_stable_claim_is_compliant(
        profile, Span(one_standard), True
    ))
    assert_true(bluetooth_le_gfsk_stable_claim_is_compliant(
        profile, Span(one_standard), False
    ))
    with assert_raises():
        _ = bluetooth_le_gfsk_stable_claim_is_compliant(
            profile, Span(empty), True
        )

    # The borrowed list is observed afresh on every call.
    all_stable[1] = False
    assert_true(not bluetooth_le_gfsk_stable_claim_is_compliant(
        profile, Span(all_stable), True
    ))


def test_seeded_predicates_against_independent_literal_oracles() raises:
    var one = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    var two = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    var state = UInt64(0x63A31F5C0FFEE123)
    for case_index in range(512):
        var profile = one if case_index % 2 == 0 else two
        var minimum_hz = 185_000.0 if case_index % 2 == 0 else 370_000.0
        var modulation_index = (
            0.4 + Float64(_next(state) % UInt64(200_001)) / 1_000_000.0
        )
        var stable = (_next(state) & UInt64(1)) != 0
        var expected_modulation = (
            modulation_index >= (0.495 if stable else 0.45)
            and modulation_index <= (0.505 if stable else 0.55)
        )
        assert_equal(
            bluetooth_le_gfsk_modulation_index_is_compliant(
                profile,
                modulation_index,
                claims_stable_index=stable,
            ),
            expected_modulation,
        )

        var positive_deviation_1010 = Float64(
            _next(state) % UInt64(600_001)
        )
        var negative_deviation_1010 = Float64(
            _next(state) % UInt64(600_001)
        )
        var deviation_00001111 = Float64(
            _next(state) % UInt64(600_001)
        )
        var minimum_deviation_1010 = min(
            positive_deviation_1010, negative_deviation_1010
        )
        var expected_deviation = (
            minimum_deviation_1010 >= minimum_hz
            and minimum_deviation_1010 >= 0.8 * deviation_00001111
        )
        assert_equal(
            bluetooth_le_gfsk_frequency_deviation_is_compliant(
                profile,
                positive_deviation_1010,
                negative_deviation_1010,
                deviation_00001111,
            ),
            expected_deviation,
        )

        var timing = (
            Float64(Int(_next(state) % UInt64(120_001)) - 60_000)
            / 1_000.0
        )
        var crossing = (
            Float64(Int(_next(state) % UInt64(300_001)) - 150_000)
            / 1_000_000.0
        )
        assert_equal(
            bluetooth_le_gfsk_timing_is_compliant(
                profile, timing, crossing
            ),
            abs(timing) < 50.0 and abs(crossing) < 0.125,
        )

        var bit = case_index & 1
        var signed_deviation = Float64(
            Int(_next(state) % UInt64(2_000_001)) - 1_000_000
        )
        var expected_sign = (
            signed_deviation > 0.0 if bit == 1 else signed_deviation < 0.0
        )
        assert_equal(
            bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
                profile, bit, signed_deviation
            ),
            expected_sign,
        )


def test_every_mutable_profile_field_is_canonically_revalidated() raises:
    var profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.phy = BLUETOOTH_LE_GFSK_PHY_2M
    _assert_all_profile_consumers_reject(profile)

    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.support_is_mandatory = False
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.symbol_rate_symbols_per_second += 1
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.uncoded_bit_rate_bits_per_second += 1
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.bits_per_symbol = 2
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.bandwidth_bit_period_product = 0.500001
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.modulation_index_minimum = 0.450001
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.modulation_index_maximum = 0.549999
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.stable_modulation_index_minimum = 0.495001
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.stable_modulation_index_maximum = 0.504999
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.minimum_frequency_deviation_hz += 1
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.minimum_frequency_deviation_ratio = 0.800001
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.maximum_absolute_symbol_timing_error_ppm = 49.999
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.maximum_absolute_zero_crossing_error_symbol_periods = 0.124
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.binary_one_uses_positive_frequency_deviation = False
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.binary_zero_uses_negative_frequency_deviation = False
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_1M)
    profile.stable_claim_requires_all_supported_le_transmitter_phys = False
    _assert_all_profile_consumers_reject(profile)


def test_nan_inf_and_finite_extrema_are_controlled() raises:
    var profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    for invalid in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        with assert_raises():
            _ = bluetooth_le_gfsk_modulation_index_is_compliant(
                profile, invalid
            )
        with assert_raises():
            _ = bluetooth_le_gfsk_frequency_deviation_is_compliant(
                profile, invalid, 400_000.0, 1.0
            )
        with assert_raises():
            _ = bluetooth_le_gfsk_frequency_deviation_is_compliant(
                profile, 400_000.0, invalid, 1.0
            )
        with assert_raises():
            _ = bluetooth_le_gfsk_frequency_deviation_is_compliant(
                profile, 400_000.0, 400_000.0, invalid
            )
        with assert_raises():
            _ = bluetooth_le_gfsk_timing_is_compliant(
                profile, invalid, 0.0
            )
        with assert_raises():
            _ = bluetooth_le_gfsk_timing_is_compliant(
                profile, 0.0, invalid
            )
        with assert_raises():
            _ = bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
                profile, 1, invalid
            )

    for negative_magnitude in [-1.0, -Float64.MAX_FINITE]:
        with assert_raises():
            _ = bluetooth_le_gfsk_frequency_deviation_is_compliant(
                profile, negative_magnitude, 400_000.0, 1.0
            )
        with assert_raises():
            _ = bluetooth_le_gfsk_frequency_deviation_is_compliant(
                profile, 400_000.0, negative_magnitude, 1.0
            )
        with assert_raises():
            _ = bluetooth_le_gfsk_frequency_deviation_is_compliant(
                profile, 400_000.0, 400_000.0, negative_magnitude
            )
    assert_true(not bluetooth_le_gfsk_modulation_index_is_compliant(
        profile, Float64.MAX_FINITE
    ))
    assert_true(not bluetooth_le_gfsk_timing_is_compliant(
        profile, Float64.MAX_FINITE, 0.0
    ))

    for extreme in [Int.MIN, Int.MAX]:
        profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
        profile.symbol_rate_symbols_per_second = extreme
        _assert_all_profile_consumers_reject(profile)
        profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
        profile.uncoded_bit_rate_bits_per_second = extreme
        _assert_all_profile_consumers_reject(profile)
        profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
        profile.bits_per_symbol = extreme
        _assert_all_profile_consumers_reject(profile)
        profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
        profile.minimum_frequency_deviation_hz = extreme
        _assert_all_profile_consumers_reject(profile)

    # NaN/Inf in mutable profile fields must not bypass exact canonicality.
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    profile.bandwidth_bit_period_product = nan[DType.float64]()
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    profile.modulation_index_minimum = inf[DType.float64]()
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    profile.modulation_index_maximum = nan[DType.float64]()
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    profile.stable_modulation_index_minimum = inf[DType.float64]()
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    profile.stable_modulation_index_maximum = nan[DType.float64]()
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    profile.minimum_frequency_deviation_ratio = inf[DType.float64]()
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    profile.maximum_absolute_symbol_timing_error_ppm = nan[DType.float64]()
    _assert_all_profile_consumers_reject(profile)
    profile = bluetooth_le_gfsk_limits(BLUETOOTH_LE_GFSK_PHY_2M)
    profile.maximum_absolute_zero_crossing_error_symbol_periods = (
        inf[DType.float64]()
    )
    _assert_all_profile_consumers_reject(profile)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
