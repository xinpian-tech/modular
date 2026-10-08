"""Bluetooth Core 6.3 LE GFSK normative parameter limits.

This deliberately narrow CPU-only module transcribes the complete LE 1M and
LE 2M parameter domain from Vol 6, Part A, Sections 1, 3.1, and 3.1.1 of the
Adopted Core 6.3 artifact.  It represents the mandatory 1 Msym/s row and the
optional 2 Msym/s row, their common BT=0.5 GFSK limits, deviation signs,
modulation-index ranges, frequency-deviation rules, symbol-timing accuracy,
zero-crossing error, and stable-index claim scope.

LE 2M 2BT, Channel Sounding, RF power and spectrum, qualification, discrete
Gaussian filtering, sampling phase, initial phase, transmit waveforms, and
receivers are outside this parameter-only boundary.  In particular, this
module neither implements nor cites the internally conflicting Vol 6, Part H,
Section 3.5.2 reference equation.
"""

from std.collections import Span
from std.math import isfinite


comptime BLUETOOTH_LE_GFSK_PHY_1M = 1
comptime BLUETOOTH_LE_GFSK_PHY_2M = 2


struct BluetoothLEGFSKLimits(ImplicitlyCopyable):
    """One mutable canonical LE 1M or LE 2M GFSK parameter row.

    Modulation-index endpoints and minimum-deviation bounds are inclusive.
    Symbol-timing and zero-crossing bounds are strict, matching "better than"
    and "less than" in the adopted text.  Every public consumer revalidates
    all fields against the factory row so caller mutation cannot alter the
    normative profile.
    """

    var phy: Int
    var support_is_mandatory: Bool
    var symbol_rate_symbols_per_second: Int
    var uncoded_bit_rate_bits_per_second: Int
    var bits_per_symbol: Int
    var bandwidth_bit_period_product: Float64
    var modulation_index_minimum: Float64
    var modulation_index_maximum: Float64
    var stable_modulation_index_minimum: Float64
    var stable_modulation_index_maximum: Float64
    var minimum_frequency_deviation_hz: Int
    var minimum_frequency_deviation_ratio: Float64
    var maximum_absolute_symbol_timing_error_ppm: Float64
    var maximum_absolute_zero_crossing_error_symbol_periods: Float64
    var binary_one_uses_positive_frequency_deviation: Bool
    var binary_zero_uses_negative_frequency_deviation: Bool
    var stable_claim_requires_all_supported_le_transmitter_phys: Bool

    def __init__(
        out self,
        phy: Int,
        support_is_mandatory: Bool,
        symbol_rate_symbols_per_second: Int,
        uncoded_bit_rate_bits_per_second: Int,
        bits_per_symbol: Int,
        bandwidth_bit_period_product: Float64,
        modulation_index_minimum: Float64,
        modulation_index_maximum: Float64,
        stable_modulation_index_minimum: Float64,
        stable_modulation_index_maximum: Float64,
        minimum_frequency_deviation_hz: Int,
        minimum_frequency_deviation_ratio: Float64,
        maximum_absolute_symbol_timing_error_ppm: Float64,
        maximum_absolute_zero_crossing_error_symbol_periods: Float64,
        binary_one_uses_positive_frequency_deviation: Bool,
        binary_zero_uses_negative_frequency_deviation: Bool,
        stable_claim_requires_all_supported_le_transmitter_phys: Bool,
    ):
        self.phy = phy
        self.support_is_mandatory = support_is_mandatory
        self.symbol_rate_symbols_per_second = symbol_rate_symbols_per_second
        self.uncoded_bit_rate_bits_per_second = (
            uncoded_bit_rate_bits_per_second
        )
        self.bits_per_symbol = bits_per_symbol
        self.bandwidth_bit_period_product = bandwidth_bit_period_product
        self.modulation_index_minimum = modulation_index_minimum
        self.modulation_index_maximum = modulation_index_maximum
        self.stable_modulation_index_minimum = (
            stable_modulation_index_minimum
        )
        self.stable_modulation_index_maximum = (
            stable_modulation_index_maximum
        )
        self.minimum_frequency_deviation_hz = minimum_frequency_deviation_hz
        self.minimum_frequency_deviation_ratio = (
            minimum_frequency_deviation_ratio
        )
        self.maximum_absolute_symbol_timing_error_ppm = (
            maximum_absolute_symbol_timing_error_ppm
        )
        self.maximum_absolute_zero_crossing_error_symbol_periods = (
            maximum_absolute_zero_crossing_error_symbol_periods
        )
        self.binary_one_uses_positive_frequency_deviation = (
            binary_one_uses_positive_frequency_deviation
        )
        self.binary_zero_uses_negative_frequency_deviation = (
            binary_zero_uses_negative_frequency_deviation
        )
        self.stable_claim_requires_all_supported_le_transmitter_phys = (
            stable_claim_requires_all_supported_le_transmitter_phys
        )


def _canonical_gfsk_limits(phy: Int) raises -> BluetoothLEGFSKLimits:
    if phy == BLUETOOTH_LE_GFSK_PHY_1M:
        return BluetoothLEGFSKLimits(
            phy=phy,
            support_is_mandatory=True,
            symbol_rate_symbols_per_second=1_000_000,
            uncoded_bit_rate_bits_per_second=1_000_000,
            bits_per_symbol=1,
            bandwidth_bit_period_product=0.5,
            modulation_index_minimum=0.45,
            modulation_index_maximum=0.55,
            stable_modulation_index_minimum=0.495,
            stable_modulation_index_maximum=0.505,
            minimum_frequency_deviation_hz=185_000,
            minimum_frequency_deviation_ratio=0.8,
            maximum_absolute_symbol_timing_error_ppm=50.0,
            maximum_absolute_zero_crossing_error_symbol_periods=0.125,
            binary_one_uses_positive_frequency_deviation=True,
            binary_zero_uses_negative_frequency_deviation=True,
            stable_claim_requires_all_supported_le_transmitter_phys=True,
        )
    if phy == BLUETOOTH_LE_GFSK_PHY_2M:
        return BluetoothLEGFSKLimits(
            phy=phy,
            support_is_mandatory=False,
            symbol_rate_symbols_per_second=2_000_000,
            uncoded_bit_rate_bits_per_second=2_000_000,
            bits_per_symbol=1,
            bandwidth_bit_period_product=0.5,
            modulation_index_minimum=0.45,
            modulation_index_maximum=0.55,
            stable_modulation_index_minimum=0.495,
            stable_modulation_index_maximum=0.505,
            minimum_frequency_deviation_hz=370_000,
            minimum_frequency_deviation_ratio=0.8,
            maximum_absolute_symbol_timing_error_ppm=50.0,
            maximum_absolute_zero_crossing_error_symbol_periods=0.125,
            binary_one_uses_positive_frequency_deviation=True,
            binary_zero_uses_negative_frequency_deviation=True,
            stable_claim_requires_all_supported_le_transmitter_phys=True,
        )
    raise Error("Bluetooth LE GFSK parameter profile must be LE 1M or LE 2M")


def _validate_gfsk_limits(profile: BluetoothLEGFSKLimits) raises:
    var expected = _canonical_gfsk_limits(profile.phy)
    if (
        profile.phy != expected.phy
        or profile.support_is_mandatory != expected.support_is_mandatory
        or profile.symbol_rate_symbols_per_second
        != expected.symbol_rate_symbols_per_second
        or profile.uncoded_bit_rate_bits_per_second
        != expected.uncoded_bit_rate_bits_per_second
        or profile.bits_per_symbol != expected.bits_per_symbol
        or profile.bandwidth_bit_period_product
        != expected.bandwidth_bit_period_product
        or profile.modulation_index_minimum
        != expected.modulation_index_minimum
        or profile.modulation_index_maximum
        != expected.modulation_index_maximum
        or profile.stable_modulation_index_minimum
        != expected.stable_modulation_index_minimum
        or profile.stable_modulation_index_maximum
        != expected.stable_modulation_index_maximum
        or profile.minimum_frequency_deviation_hz
        != expected.minimum_frequency_deviation_hz
        or profile.minimum_frequency_deviation_ratio
        != expected.minimum_frequency_deviation_ratio
        or profile.maximum_absolute_symbol_timing_error_ppm
        != expected.maximum_absolute_symbol_timing_error_ppm
        or profile.maximum_absolute_zero_crossing_error_symbol_periods
        != expected.maximum_absolute_zero_crossing_error_symbol_periods
        or profile.binary_one_uses_positive_frequency_deviation
        != expected.binary_one_uses_positive_frequency_deviation
        or profile.binary_zero_uses_negative_frequency_deviation
        != expected.binary_zero_uses_negative_frequency_deviation
        or profile.stable_claim_requires_all_supported_le_transmitter_phys
        != expected.stable_claim_requires_all_supported_le_transmitter_phys
    ):
        raise Error(
            "Bluetooth LE GFSK limits do not match a canonical Core 6.3 row"
        )


def bluetooth_le_gfsk_limits(phy: Int) raises -> BluetoothLEGFSKLimits:
    """Return the complete canonical Part-A limit row for LE 1M or LE 2M."""

    return _canonical_gfsk_limits(phy)


def bluetooth_le_gfsk_modulation_index_is_compliant(
    profile: BluetoothLEGFSKLimits,
    modulation_index: Float64,
    *,
    claims_stable_index: Bool = False,
) raises -> Bool:
    """Test the inclusive standard or stable modulation-index interval."""

    _validate_gfsk_limits(profile)
    if not isfinite(modulation_index):
        raise Error("Bluetooth LE GFSK modulation index must be finite")
    if claims_stable_index:
        return (
            modulation_index >= profile.stable_modulation_index_minimum
            and modulation_index <= profile.stable_modulation_index_maximum
        )
    return (
        modulation_index >= profile.modulation_index_minimum
        and modulation_index <= profile.modulation_index_maximum
    )


def bluetooth_le_gfsk_frequency_deviation_is_compliant(
    profile: BluetoothLEGFSKLimits,
    positive_1010_deviation_magnitude_hz: Float64,
    negative_1010_deviation_magnitude_hz: Float64,
    deviation_00001111_hz: Float64,
) raises -> Bool:
    """Test both inclusive Part-A minimum-deviation requirements.

    All inputs are non-negative frequency-deviation magnitudes.  The function
    computes ``Fmin = min(|Fmin+|, |Fmin-|)`` from the first two 1010 values;
    the third is the deviation with respect to the transmit frequency for
    00001111.
    """

    _validate_gfsk_limits(profile)
    if (
        not isfinite(positive_1010_deviation_magnitude_hz)
        or not isfinite(negative_1010_deviation_magnitude_hz)
        or not isfinite(deviation_00001111_hz)
        or positive_1010_deviation_magnitude_hz < 0.0
        or negative_1010_deviation_magnitude_hz < 0.0
        or deviation_00001111_hz < 0.0
    ):
        raise Error(
            "Bluetooth LE GFSK frequency-deviation magnitudes must be finite "
            "and non-negative"
        )
    var minimum_1010_deviation_hz = min(
        positive_1010_deviation_magnitude_hz,
        negative_1010_deviation_magnitude_hz,
    )
    return (
        minimum_1010_deviation_hz
        >= Float64(profile.minimum_frequency_deviation_hz)
        and minimum_1010_deviation_hz
        >= profile.minimum_frequency_deviation_ratio
        * deviation_00001111_hz
    )


def bluetooth_le_gfsk_timing_is_compliant(
    profile: BluetoothLEGFSKLimits,
    symbol_timing_error_ppm: Float64,
    zero_crossing_error_symbol_periods: Float64,
) raises -> Bool:
    """Test the strict symbol-timing and zero-crossing error limits."""

    _validate_gfsk_limits(profile)
    if (
        not isfinite(symbol_timing_error_ppm)
        or not isfinite(zero_crossing_error_symbol_periods)
    ):
        raise Error("Bluetooth LE GFSK timing errors must be finite")
    return (
        abs(symbol_timing_error_ppm)
        < profile.maximum_absolute_symbol_timing_error_ppm
        and abs(zero_crossing_error_symbol_periods)
        < profile.maximum_absolute_zero_crossing_error_symbol_periods
    )


def bluetooth_le_gfsk_bit_deviation_sign_is_compliant(
    profile: BluetoothLEGFSKLimits,
    bit: Int,
    frequency_deviation_hz: Float64,
) raises -> Bool:
    """Test the normative binary-one positive/binary-zero negative mapping."""

    _validate_gfsk_limits(profile)
    if bit != 0 and bit != 1:
        raise Error("Bluetooth LE GFSK bit must be zero or one")
    if not isfinite(frequency_deviation_hz):
        raise Error("Bluetooth LE GFSK frequency deviation must be finite")
    if bit == 1:
        return frequency_deviation_hz > 0.0
    return frequency_deviation_hz < 0.0


def bluetooth_le_gfsk_stable_claim_is_compliant(
    profile: BluetoothLEGFSKLimits,
    supported_transmitter_phy_has_stable_index: Span[Bool, ...],
    claims_stable_index: Bool,
) raises -> Bool:
    """Enforce that a stable-index claim applies to every supported TX PHY.

    The caller supplies one Boolean for each LE transmitter PHY it supports;
    this parameter-only API deliberately does not model those PHYs or Channel
    Sounding.  A non-empty list prevents a vacuous transmitter claim.
    """

    _validate_gfsk_limits(profile)
    if len(supported_transmitter_phy_has_stable_index) == 0:
        raise Error(
            "Bluetooth LE stable-index claim requires a supported transmitter PHY"
        )
    if not claims_stable_index:
        return True
    for index in range(len(supported_transmitter_phy_has_stable_index)):
        if not supported_transmitter_phy_has_stable_index[index]:
            return False
    return True
