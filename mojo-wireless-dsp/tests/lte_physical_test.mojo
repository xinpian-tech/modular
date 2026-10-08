"""Static, seeded, boundary, and scale tests for the bounded LTE profile."""

from std.collections import Span
from std.math import cos, sin, sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.lte import (
    lte_pusch_dmrs_ifdma_short_base_sequence,
)
from wireless_dsp.wireless.lte.physical import (
    lte_gold_bits,
    lte_pss_root,
    lte_pss,
    lte_sss_indices,
    lte_sss,
    lte_fdd_configuration,
    lte_normal_cp_samples,
    lte_crs_c_init,
    lte_crs_sequence,
    lte_crs_port_mapping,
    lte_pdsch_scrambling_c_init,
    lte_pdsch_scramble,
    lte_sc_fdma_transform_precoding,
    lte_sc_fdma_transform_deprecoding,
    lte_pusch_dmrs_base_sequence,
    lte_pusch_dmrs_sequence,
)
from wireless_dsp.wireless.lte.procedures import (
    lte_downlink_mcs_profile,
    lte_downlink_mcs_entry,
    lte_downlink_redundancy_version,
    lte_uplink_mcs_entry,
    lte_base_tbs_table_bounds,
    lte_base_transport_block_size,
    lte_downlink_transport_block_size,
    lte_downlink_resource_block_group_size,
    lte_downlink_type0_resource_blocks,
    lte_uplink_encode_riv,
    lte_uplink_decode_riv,
)
from wireless_dsp.wireless.lte.measurements import (
    lte_rsrp,
    lte_rssi,
    lte_rsrq,
    lte_rs_sinr_from_powers,
    lte_rs_sinr,
)


comptime _PI = 3.1415926535897932384626433832795


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    _assert_close(actual.re, expected.re, tolerance)
    _assert_close(actual.im, expected.im, tolerance)


def _reference_gold(c_init: UInt32, length: Int) -> List[UInt8]:
    # Independent 31-bit-register transcription, with no sequence buffers.
    var x1 = UInt32(1)
    var x2 = c_init & UInt32(0x7FFFFFFF)
    var result = List[UInt8](capacity=length)
    for index in range(1600 + length):
        var output = UInt8((x1 ^ x2) & UInt32(1))
        var x1_feedback = ((x1 >> 3) ^ x1) & UInt32(1)
        var x2_feedback = ((x2 >> 3) ^ (x2 >> 2) ^ (x2 >> 1) ^ x2) & UInt32(1)
        x1 = (x1 >> 1) | (x1_feedback << 30)
        x2 = (x2 >> 1) | (x2_feedback << 30)
        if index >= 1600:
            result.append(output)
    return result^


def _sss_signature(sequence: List[Float64]) raises -> UInt64:
    assert_equal(len(sequence), 62)
    var signature = UInt64(0)
    for index in range(62):
        assert_true(sequence[index] == -1.0 or sequence[index] == 1.0)
        if sequence[index] < 0.0:
            signature |= UInt64(1) << UInt64(index)
    return signature


def _reference_unitary_dft(
    values: Span[Complex64, ...], inverse: Bool
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(values))
    var direction = 1.0 if inverse else -1.0
    var scale = 1.0 / sqrt(Float64(len(values)))
    for frequency in range(len(values)):
        var accumulator = Complex64(0.0, 0.0)
        for time in range(len(values)):
            var angle = (
                direction
                * 2.0
                * _PI
                * Float64(frequency * time)
                / Float64(len(values))
            )
            var value = Complex64(values[time].re, values[time].im)
            accumulator = accumulator + value * Complex64(
                cos(angle), sin(angle)
            )
        result.append(Complex64(accumulator.re * scale, accumulator.im * scale))
    return result^


def _lte_pusch_dmrs_short_phase_fixture(
    allocated_resource_blocks: Int,
) raises -> List[Int]:
    # Independently frozen from the official V18.0.2 Tables 5.5.1.2-1/-2;
    # layout is group-major, unlike the production per-group row lookup.
    if allocated_resource_blocks == 1:
        return [
            -1,
            1,
            3,
            -3,
            3,
            3,
            1,
            1,
            3,
            1,
            -3,
            3,  # u=0
            1,
            1,
            3,
            3,
            3,
            -1,
            1,
            -3,
            -3,
            1,
            -3,
            3,  # u=1
            1,
            1,
            -3,
            -3,
            -3,
            -1,
            -3,
            -3,
            1,
            -3,
            1,
            -1,  # u=2
            -1,
            1,
            1,
            1,
            1,
            -1,
            -3,
            -3,
            1,
            -3,
            3,
            -1,  # u=3
            -1,
            3,
            1,
            -1,
            1,
            -1,
            -3,
            -1,
            1,
            -1,
            1,
            3,  # u=4
            1,
            -3,
            3,
            -1,
            -1,
            1,
            1,
            -1,
            -1,
            3,
            -3,
            1,  # u=5
            -1,
            3,
            -3,
            -3,
            -3,
            3,
            1,
            -1,
            3,
            3,
            -3,
            1,  # u=6
            -3,
            -1,
            -1,
            -1,
            1,
            -3,
            3,
            -1,
            1,
            -3,
            3,
            1,  # u=7
            1,
            -3,
            3,
            1,
            -1,
            -1,
            -1,
            1,
            1,
            3,
            -1,
            1,  # u=8
            1,
            -3,
            -1,
            3,
            3,
            -1,
            -3,
            1,
            1,
            1,
            1,
            1,  # u=9
            -1,
            3,
            -1,
            1,
            1,
            -3,
            -3,
            -1,
            -3,
            -3,
            3,
            -1,  # u=10
            3,
            1,
            -1,
            -1,
            3,
            3,
            -3,
            1,
            3,
            1,
            3,
            3,  # u=11
            1,
            -3,
            1,
            1,
            -3,
            1,
            1,
            1,
            -3,
            -3,
            -3,
            1,  # u=12
            3,
            3,
            -3,
            3,
            -3,
            1,
            1,
            3,
            -1,
            -3,
            3,
            3,  # u=13
            -3,
            1,
            -1,
            -3,
            -1,
            3,
            1,
            3,
            3,
            3,
            -1,
            1,  # u=14
            3,
            -1,
            1,
            -3,
            -1,
            -1,
            1,
            1,
            3,
            1,
            -1,
            -3,  # u=15
            1,
            3,
            1,
            -1,
            1,
            3,
            3,
            3,
            -1,
            -1,
            3,
            -1,  # u=16
            -3,
            1,
            1,
            3,
            -3,
            3,
            -3,
            -3,
            3,
            1,
            3,
            -1,  # u=17
            -3,
            3,
            1,
            1,
            -3,
            1,
            -3,
            -3,
            -1,
            -1,
            1,
            -3,  # u=18
            -1,
            3,
            1,
            3,
            1,
            -1,
            -1,
            3,
            -3,
            -1,
            -3,
            -1,  # u=19
            -1,
            -3,
            1,
            1,
            1,
            1,
            3,
            1,
            -1,
            1,
            -3,
            -1,  # u=20
            -1,
            3,
            -1,
            1,
            -3,
            -3,
            -3,
            -3,
            -3,
            1,
            -1,
            -3,  # u=21
            1,
            1,
            -3,
            -3,
            -3,
            -3,
            -1,
            3,
            -3,
            1,
            -3,
            3,  # u=22
            1,
            1,
            -1,
            -3,
            -1,
            -3,
            1,
            -1,
            1,
            3,
            -1,
            1,  # u=23
            1,
            1,
            3,
            1,
            3,
            3,
            -1,
            1,
            -1,
            -3,
            -3,
            1,  # u=24
            1,
            -3,
            3,
            3,
            1,
            3,
            3,
            1,
            -3,
            -1,
            -1,
            3,  # u=25
            1,
            3,
            -3,
            -3,
            3,
            -3,
            1,
            -1,
            -1,
            3,
            -1,
            -3,  # u=26
            -3,
            -1,
            -3,
            -1,
            -3,
            3,
            1,
            -1,
            1,
            3,
            -3,
            -3,  # u=27
            -1,
            3,
            -3,
            3,
            -1,
            3,
            3,
            -3,
            3,
            3,
            -1,
            -1,  # u=28
            3,
            -3,
            -3,
            -1,
            -1,
            -3,
            -1,
            3,
            -3,
            3,
            1,
            -1,  # u=29
        ]
    elif allocated_resource_blocks == 2:
        return [
            -1,
            3,
            1,
            -3,
            3,
            -1,
            1,
            3,
            -3,
            3,
            1,
            3,
            -3,
            3,
            1,
            1,
            -1,
            1,
            3,
            -3,
            3,
            -3,
            -1,
            -3,  # u=0
            -3,
            3,
            -3,
            -3,
            -3,
            1,
            -3,
            -3,
            3,
            -1,
            1,
            1,
            1,
            3,
            1,
            -1,
            3,
            -3,
            -3,
            1,
            3,
            1,
            1,
            -3,  # u=1
            3,
            -1,
            3,
            3,
            1,
            1,
            -3,
            3,
            3,
            3,
            3,
            1,
            -1,
            3,
            -1,
            1,
            1,
            -1,
            -3,
            -1,
            -1,
            1,
            3,
            3,  # u=2
            -1,
            -3,
            1,
            1,
            3,
            -3,
            1,
            1,
            -3,
            -1,
            -1,
            1,
            3,
            1,
            3,
            1,
            -1,
            3,
            1,
            1,
            -3,
            -1,
            -3,
            -1,  # u=3
            -1,
            -1,
            -1,
            -3,
            -3,
            -1,
            1,
            1,
            3,
            3,
            -1,
            3,
            -1,
            1,
            -1,
            -3,
            1,
            -1,
            -3,
            -3,
            1,
            -3,
            -1,
            -1,  # u=4
            -3,
            1,
            1,
            3,
            -1,
            1,
            3,
            1,
            -3,
            1,
            -3,
            1,
            1,
            -1,
            -1,
            3,
            -1,
            -3,
            3,
            -3,
            -3,
            -3,
            1,
            1,  # u=5
            1,
            1,
            -1,
            -1,
            3,
            -3,
            -3,
            3,
            -3,
            1,
            -1,
            -1,
            1,
            -1,
            1,
            1,
            -1,
            -3,
            -1,
            1,
            -1,
            3,
            -1,
            -3,  # u=6
            -3,
            3,
            3,
            -1,
            -1,
            -3,
            -1,
            3,
            1,
            3,
            1,
            3,
            1,
            1,
            -1,
            3,
            1,
            -1,
            1,
            3,
            -3,
            -1,
            -1,
            1,  # u=7
            -3,
            1,
            3,
            -3,
            1,
            -1,
            -3,
            3,
            -3,
            3,
            -1,
            -1,
            -1,
            -1,
            1,
            -3,
            -3,
            -3,
            1,
            -3,
            -3,
            -3,
            1,
            -3,  # u=8
            1,
            1,
            -3,
            3,
            3,
            -1,
            -3,
            -1,
            3,
            -3,
            3,
            3,
            3,
            -1,
            1,
            1,
            -3,
            1,
            -1,
            1,
            1,
            -3,
            1,
            1,  # u=9
            -1,
            1,
            -3,
            -3,
            3,
            -1,
            3,
            -1,
            -1,
            -3,
            -3,
            -3,
            -1,
            -3,
            -3,
            1,
            -1,
            1,
            3,
            3,
            -1,
            1,
            -1,
            3,  # u=10
            1,
            3,
            3,
            -3,
            -3,
            1,
            3,
            1,
            -1,
            -3,
            -3,
            -3,
            3,
            3,
            -3,
            3,
            3,
            -1,
            -3,
            3,
            -1,
            1,
            -3,
            1,  # u=11
            1,
            3,
            3,
            1,
            1,
            1,
            -1,
            -1,
            1,
            -3,
            3,
            -1,
            1,
            1,
            -3,
            3,
            3,
            -1,
            -3,
            3,
            -3,
            -1,
            -3,
            -1,  # u=12
            3,
            -1,
            -1,
            -1,
            -1,
            -3,
            -1,
            3,
            3,
            1,
            -1,
            1,
            3,
            3,
            3,
            -1,
            1,
            1,
            -3,
            1,
            3,
            -1,
            -3,
            3,  # u=13
            -3,
            -3,
            3,
            1,
            3,
            1,
            -3,
            3,
            1,
            3,
            1,
            1,
            3,
            3,
            -1,
            -1,
            -3,
            1,
            -3,
            -1,
            3,
            1,
            1,
            3,  # u=14
            -1,
            -1,
            1,
            -3,
            1,
            3,
            -3,
            1,
            -1,
            -3,
            -1,
            3,
            1,
            3,
            1,
            -1,
            -3,
            -3,
            -1,
            -1,
            -3,
            -3,
            -3,
            -1,  # u=15
            -1,
            -3,
            3,
            -1,
            -1,
            -1,
            -1,
            1,
            1,
            -3,
            3,
            1,
            3,
            3,
            1,
            -1,
            1,
            -3,
            1,
            -3,
            1,
            1,
            -3,
            -1,  # u=16
            1,
            3,
            -1,
            3,
            3,
            -1,
            -3,
            1,
            -1,
            -3,
            3,
            3,
            3,
            -1,
            1,
            1,
            3,
            -1,
            -3,
            -1,
            3,
            -1,
            -1,
            -1,  # u=17
            1,
            1,
            1,
            1,
            1,
            -1,
            3,
            -1,
            -3,
            1,
            1,
            3,
            -3,
            1,
            -3,
            -1,
            1,
            1,
            -3,
            -3,
            3,
            1,
            1,
            -3,  # u=18
            1,
            3,
            3,
            1,
            -1,
            -3,
            3,
            -1,
            3,
            3,
            3,
            -3,
            1,
            -1,
            1,
            -1,
            -3,
            -1,
            1,
            3,
            -1,
            3,
            -3,
            -3,  # u=19
            -1,
            -3,
            3,
            -3,
            -3,
            -3,
            -1,
            -1,
            -3,
            -1,
            -3,
            3,
            1,
            3,
            -3,
            -1,
            3,
            -1,
            1,
            -1,
            3,
            -3,
            1,
            -1,  # u=20
            -3,
            -3,
            1,
            1,
            -1,
            1,
            -1,
            1,
            -1,
            3,
            1,
            -3,
            -1,
            1,
            -1,
            1,
            -1,
            -1,
            3,
            3,
            -3,
            -1,
            1,
            -3,  # u=21
            -3,
            -1,
            -3,
            3,
            1,
            -1,
            -3,
            -1,
            -3,
            -3,
            3,
            -3,
            3,
            -3,
            -1,
            1,
            3,
            1,
            -3,
            1,
            3,
            3,
            -1,
            -3,  # u=22
            -1,
            -1,
            -1,
            -1,
            3,
            3,
            3,
            1,
            3,
            3,
            -3,
            1,
            3,
            -1,
            3,
            -1,
            3,
            3,
            -3,
            3,
            1,
            -1,
            3,
            3,  # u=23
            1,
            -1,
            3,
            3,
            -1,
            -3,
            3,
            -3,
            -1,
            -1,
            3,
            -1,
            3,
            -1,
            -1,
            1,
            1,
            1,
            1,
            -1,
            -1,
            -3,
            -1,
            3,  # u=24
            1,
            -1,
            1,
            -1,
            3,
            -1,
            3,
            1,
            1,
            -1,
            -1,
            -3,
            1,
            1,
            -3,
            1,
            3,
            -3,
            1,
            1,
            -3,
            -3,
            -1,
            -1,  # u=25
            -3,
            -1,
            1,
            3,
            1,
            1,
            -3,
            -1,
            -1,
            -3,
            3,
            -3,
            3,
            1,
            -3,
            3,
            -3,
            1,
            -1,
            1,
            -3,
            1,
            1,
            1,  # u=26
            -1,
            -3,
            3,
            3,
            1,
            1,
            3,
            -1,
            -3,
            -1,
            -1,
            -1,
            3,
            1,
            -3,
            -3,
            -1,
            3,
            -3,
            -1,
            -3,
            -1,
            -3,
            -1,  # u=27
            -1,
            -3,
            -1,
            -1,
            1,
            -3,
            -1,
            -1,
            1,
            -1,
            -3,
            1,
            1,
            -3,
            1,
            -3,
            -3,
            3,
            1,
            1,
            -1,
            3,
            -1,
            -1,  # u=28
            1,
            1,
            -1,
            -1,
            -3,
            -1,
            3,
            -1,
            3,
            -1,
            1,
            3,
            1,
            -1,
            3,
            1,
            3,
            -3,
            -3,
            1,
            -1,
            -1,
            1,
            3,  # u=29
        ]
    raise Error("short DM-RS fixture requires one or two RBs")


def _lte_pusch_dmrs_ifdma_short_phase_fixture(
    reference_signal_subcarriers: Int,
) raises -> List[Int]:
    # Independent group-major transcription of official V18.0.2 Tables
    # 5.5.1.2-3/-4; production selects one owned row at a time.
    if reference_signal_subcarriers == 6:
        return [
            -1, -3, 3, -3, 3, -3,  # u=0
            -1, 3, -1, 1, 1, 1,  # u=1
            3, -1, -3, -3, 1, 3,  # u=2
            3, -1, -1, 1, -1, -1,  # u=3
            -1, -1, -3, 1, -3, -1,  # u=4
            1, 3, -3, -1, -3, 3,  # u=5
            -3, 3, -1, -1, 1, -3,  # u=6
            -1, -3, -3, 1, 3, 3,  # u=7
            3, -1, -1, 3, 1, 3,  # u=8
            3, -3, 3, 1, -1, 1,  # u=9
            -3, 1, -3, -3, -3, -3,  # u=10
            -3, -3, -3, 1, -3, -3,  # u=11
            3, -3, 1, -1, -3, -3,  # u=12
            3, -3, 3, -1, -1, -3,  # u=13
            3, -1, 1, 3, 3, 1,  # u=14
            -1, 1, -1, -3, 1, 1,  # u=15
            -3, -1, -3, -1, 3, 3,  # u=16
            1, -1, 3, -3, 3, 3,  # u=17
            1, 3, 1, 1, -3, 3,  # u=18
            -1, -3, -1, -1, 3, -3,  # u=19
            3, -1, -3, -1, -1, -3,  # u=20
            3, 1, 3, -3, -3, 1,  # u=21
            1, 3, -1, -1, 1, -1,  # u=22
            -3, 1, -3, 3, 3, 3,  # u=23
            1, 3, -3, 3, -3, 3,  # u=24
            -1, -1, 1, -3, 1, -1,  # u=25
            1, -3, -1, -1, 3, 1,  # u=26
            -3, -1, -1, 3, 1, 1,  # u=27
            -1, 3, -3, -3, -3, 3,  # u=28
            3, 1, -1, 1, 3, 1,  # u=29
        ]
    elif reference_signal_subcarriers == 18:
        return [
            -3, -3, -3, -3, -3, -1, 1, -1, -3, 3, -1, 3, -1, 3, -3, -1, -1, 3,  # u=0
            -3, -3, -3, -3, -3, -1, 1, -1, 1, -3, -3, -3, 1, -1, 3, -3, -3, 1,  # u=1
            -3, -3, -3, -3, -3, -1, 1, 1, 3, -3, 1, 1, -3, 1, -3, 3, 1, -1,  # u=2
            -3, -3, -3, -3, -3, -1, 1, 3, -3, -1, 3, -1, 3, 1, -1, -3, 3, -3,  # u=3
            -3, -3, -3, -3, -3, -1, 3, -3, -1, 1, -1, -3, 3, 3, 1, -3, 1, -1,  # u=4
            -3, -3, -3, -3, -3, 1, -3, -3, -3, -3, 1, 1, 1, -3, 1, 1, -3, -3,  # u=5
            -3, -3, -3, -3, -3, 1, -3, -3, 1, 1, -3, -3, -3, 1, -1, 3, -1, 3,  # u=6
            -3, -3, -3, -3, -3, 1, -3, -1, 3, -1, 3, 3, -1, -1, 1, 3, 3, -1,  # u=7
            -3, -3, -3, -3, -3, 1, -1, -1, -1, -3, 3, -1, 3, -3, 3, -1, 1, 3,  # u=8
            -3, -3, -3, -3, -3, 3, -3, 1, -1, 3, -3, 3, 3, -1, -3, 1, 1, -3,  # u=9
            -3, -3, -3, -3, -3, 3, -1, -3, -3, 1, 1, 3, -3, -1, 3, -1, 3, 1,  # u=10
            -3, -3, -3, -3, -3, 3, 3, -1, -1, -1, 3, 1, -3, 3, -1, 1, -3, 1,  # u=11
            -3, -3, -3, -3, -1, -3, -3, -3, 1, 3, 1, -1, 3, -3, -1, -3, 1, 1,  # u=12
            -3, -3, -3, -3, -1, -3, -3, 1, -1, -1, 3, -3, -3, 1, 3, 1, -3, 1,  # u=13
            -3, -3, -3, -3, -1, -3, -3, 1, 3, -3, -1, 3, 1, 3, -1, 3, -1, -3,  # u=14
            -3, -3, -3, -3, -1, -3, -1, 3, -3, 1, -3, 1, -1, -3, -3, 1, 1, 3,  # u=15
            -3, -3, -3, -3, -1, -1, 3, -3, 3, -1, -3, 1, 1, -1, -3, -1, 3, -3,  # u=16
            -3, -3, -3, -3, -1, -1, 3, -1, -3, 1, 3, -1, -3, -3, 1, 3, -1, 1,  # u=17
            -3, -3, -3, -3, -1, 3, -1, -1, 3, 3, -1, -3, 1, 1, 1, -1, -3, -1,  # u=18
            -3, -3, -3, -3, -1, 3, 1, -3, -1, -3, 3, 1, -1, 3, -1, 1, 3, -1,  # u=19
            -3, -3, -3, -3, 1, -3, -3, 3, 1, 1, -3, -1, 1, 3, 3, -1, 3, -1,  # u=20
            -3, -3, -3, -3, 1, -3, 1, 3, 1, -1, -1, 3, 3, -1, 1, 1, -3, 3,  # u=21
            -3, -3, -3, -3, 1, -3, 3, -3, -1, 3, 1, 1, -1, -1, 3, 3, -1, 3,  # u=22
            -3, -3, -3, -3, 1, -3, 3, -1, 3, -3, -1, -1, -1, 1, -3, -3, 3, 1,  # u=23
            -3, -3, -3, -3, 1, 1, 3, 1, 1, -1, 3, 1, 1, 3, -1, -3, 1, 3,  # u=24
            -3, -3, -3, -3, 1, 3, 3, 3, 1, -3, 1, -3, -3, 3, -3, 1, -1, -3,  # u=25
            -3, -3, -3, -3, 3, 1, 3, 3, -1, 3, -3, -3, -1, 3, -1, -1, -3, 1,  # u=26
            -3, -3, -3, -1, -3, -3, -1, -1, -3, 3, 3, 1, -3, -1, -1, 3, 1, -3,  # u=27
            -3, -3, -3, -1, -3, 1, -1, 1, -3, 3, 1, -3, -1, 1, 3, 1, -1, -1,  # u=28
            -3, -3, -3, -1, -3, 3, 1, 1, -1, -1, 1, 3, 1, -3, 1, -3, -1, 1,  # u=29
        ]
    raise Error("IFDMA short DM-RS fixture requires 6 or 18 subcarriers")


def _lte_short_phase_value(phase: Int) raises -> Complex64:
    var scale = 1.0 / sqrt(2.0)
    if phase == -3:
        return Complex64(-scale, -scale)
    if phase == -1:
        return Complex64(scale, -scale)
    if phase == 1:
        return Complex64(scale, scale)
    if phase == 3:
        return Complex64(-scale, scale)
    raise Error("invalid LTE short DM-RS phase")


def _lte_short_phase_checksum(phases: List[Int]) raises -> UInt64:
    var checksum = UInt64(14695981039346656037)
    for phase in phases:
        _ = _lte_short_phase_value(phase)
        checksum = (checksum ^ UInt64((phase + 3) // 2)) * UInt64(1099511628211)
    return checksum


def test_pusch_dmrs_short_phase_tables_full_independent_fixture() raises:
    for allocated_resource_blocks in [1, 2]:
        var sequence_length = 12 * allocated_resource_blocks
        var fixture = _lte_pusch_dmrs_short_phase_fixture(
            allocated_resource_blocks
        )
        assert_equal(len(fixture), 30 * sequence_length)
        var fixture_checksum = _lte_short_phase_checksum(fixture)
        if allocated_resource_blocks == 1:
            assert_equal(fixture_checksum, UInt64(13272371369874862132))
        else:
            assert_equal(fixture_checksum, UInt64(11976707154003258026))

        for group_number in range(30):
            var cyclic_shift_index = (
                7 * group_number + allocated_resource_blocks
            ) % 12
            var alpha = 2.0 * _PI * Float64(cyclic_shift_index) / 12.0
            var base = lte_pusch_dmrs_base_sequence(
                group_number, 0, allocated_resource_blocks
            )
            var shifted = lte_pusch_dmrs_sequence(
                group_number,
                0,
                allocated_resource_blocks,
                cyclic_shift_index,
            )
            assert_equal(len(base), sequence_length)
            assert_equal(len(shifted), sequence_length)
            for index in range(sequence_length):
                var expected = _lte_short_phase_value(
                    fixture[group_number * sequence_length + index]
                )
                _assert_complex_close(base[index], expected, 2.0e-15)
                _assert_close(base[index].magnitude_squared(), 1.0, 3.0e-15)
                var cyclic_phase = Complex64(
                    cos(alpha * Float64(index)),
                    sin(alpha * Float64(index)),
                )
                _assert_complex_close(
                    shifted[index], expected * cyclic_phase, 3.0e-14
                )
                _assert_close(shifted[index].magnitude_squared(), 1.0, 5.0e-14)


def test_pusch_dmrs_ifdma_short_tables_full_independent_fixture() raises:
    for reference_signal_subcarriers in [6, 18]:
        var fixture = _lte_pusch_dmrs_ifdma_short_phase_fixture(
            reference_signal_subcarriers
        )
        assert_equal(len(fixture), 30 * reference_signal_subcarriers)
        var fixture_checksum = _lte_short_phase_checksum(fixture)
        if reference_signal_subcarriers == 6:
            assert_equal(fixture_checksum, UInt64(14680473596852852628))
        else:
            assert_equal(fixture_checksum, UInt64(7616900040079819034))

        for group_number in range(30):
            var base = lte_pusch_dmrs_ifdma_short_base_sequence(
                group_number, reference_signal_subcarriers
            )
            assert_equal(len(base), reference_signal_subcarriers)
            for index in range(reference_signal_subcarriers):
                var expected = _lte_short_phase_value(
                    fixture[
                        group_number * reference_signal_subcarriers + index
                    ]
                )
                _assert_complex_close(base[index], expected, 2.0e-15)
                _assert_close(base[index].magnitude_squared(), 1.0, 3.0e-15)


def test_pusch_dmrs_ifdma_short_owned_results_and_illegal_domain() raises:
    var six = lte_pusch_dmrs_ifdma_short_base_sequence(0, 6)
    var expected_six = _lte_short_phase_value(-1)
    _assert_complex_close(six[0], expected_six, 2.0e-15)
    six[0] = Complex64(101.0, -103.0)
    var replayed_six = lte_pusch_dmrs_ifdma_short_base_sequence(0, 6)
    _assert_complex_close(replayed_six[0], expected_six, 2.0e-15)

    var eighteen = lte_pusch_dmrs_ifdma_short_base_sequence(29, 18)
    var expected_eighteen = _lte_short_phase_value(1)
    _assert_complex_close(eighteen[17], expected_eighteen, 2.0e-15)
    eighteen[17] = Complex64(-107.0, 109.0)
    var replayed_eighteen = lte_pusch_dmrs_ifdma_short_base_sequence(29, 18)
    _assert_complex_close(replayed_eighteen[17], expected_eighteen, 2.0e-15)

    for invalid_group_number in [Int.MIN, -1, 30, Int.MAX]:
        with assert_raises():
            _ = lte_pusch_dmrs_ifdma_short_base_sequence(
                invalid_group_number, 6
            )
        with assert_raises():
            _ = lte_pusch_dmrs_ifdma_short_base_sequence(
                invalid_group_number, 18
            )
    for invalid_length in range(-64, 65):
        if invalid_length != 6 and invalid_length != 18:
            with assert_raises():
                _ = lte_pusch_dmrs_ifdma_short_base_sequence(0, invalid_length)
    for invalid_length in [Int.MIN, Int.MAX, -1024, 65, 110, 111, 1024]:
        with assert_raises():
            _ = lte_pusch_dmrs_ifdma_short_base_sequence(29, invalid_length)


def test_pusch_dmrs_short_phase_mutability_and_int_extremes() raises:
    var expected_base = _lte_short_phase_value(-1)
    var base = lte_pusch_dmrs_base_sequence(0, 0, 1)
    _assert_complex_close(base[0], expected_base, 2.0e-15)
    base[0] = Complex64(99.0, -77.0)
    var replayed_base = lte_pusch_dmrs_base_sequence(0, 0, 1)
    _assert_complex_close(replayed_base[0], expected_base, 2.0e-15)

    var shifted = lte_pusch_dmrs_sequence(29, 0, 2, 11)
    var expected_shifted = _lte_short_phase_value(1)
    _assert_complex_close(shifted[0], expected_shifted, 2.0e-15)
    shifted[0] = Complex64(-101.0, 103.0)
    var replayed_shifted = lte_pusch_dmrs_sequence(29, 0, 2, 11)
    _assert_complex_close(replayed_shifted[0], expected_shifted, 2.0e-15)

    for invalid_group_number in [Int.MIN, -1, 30, Int.MAX]:
        with assert_raises():
            _ = lte_pusch_dmrs_base_sequence(invalid_group_number, 0, 1)
        with assert_raises():
            _ = lte_pusch_dmrs_sequence(invalid_group_number, 0, 2, 0)
    for invalid_sequence_number in [Int.MIN, -1, 1, 2, Int.MAX]:
        with assert_raises():
            _ = lte_pusch_dmrs_base_sequence(0, invalid_sequence_number, 1)
        with assert_raises():
            _ = lte_pusch_dmrs_sequence(0, invalid_sequence_number, 2, 0)
    for invalid_resource_blocks in [Int.MIN, 0, 111, Int.MAX]:
        with assert_raises():
            _ = lte_pusch_dmrs_base_sequence(0, 0, invalid_resource_blocks)
        with assert_raises():
            _ = lte_pusch_dmrs_sequence(0, 0, invalid_resource_blocks, 0)
    for invalid_cyclic_shift in [Int.MIN, -1, 12, Int.MAX]:
        with assert_raises():
            _ = lte_pusch_dmrs_sequence(0, 0, 1, invalid_cyclic_shift)


def test_lte_gold_seeded_independent_oracle_and_boundaries() raises:
    var seeds: List[UInt32] = [0, 1, 8193, 0x1234567, 0x7FFFFFFF]
    for seed in seeds:
        assert_equal(lte_gold_bits(seed, 257), _reference_gold(seed, 257))
    assert_equal(len(lte_gold_bits(UInt32(7), 0)), 0)
    with assert_raises():
        _ = lte_gold_bits(UInt32(0x80000000), 1)
    with assert_raises():
        _ = lte_gold_bits(UInt32(0), -1)
    with assert_raises():
        _ = lte_gold_bits(UInt32(0), Int.MAX)


def test_pss_normative_roots_and_hand_formula() raises:
    assert_equal(lte_pss_root(0), 25)
    assert_equal(lte_pss_root(1), 29)
    assert_equal(lte_pss_root(2), 34)
    for identity in range(3):
        var root = lte_pss_root(identity)
        var sequence = lte_pss(identity)
        assert_equal(len(sequence), 62)
        _assert_complex_close(sequence[0], Complex64(1.0, 0.0), 1.0e-15)
        var angle30 = -_PI * Float64(root * 30 * 31) / 63.0
        _assert_complex_close(
            sequence[30], Complex64(cos(angle30), sin(angle30)), 1.0e-14
        )
        var angle31 = -_PI * Float64(root * 32 * 33) / 63.0
        _assert_complex_close(
            sequence[31], Complex64(cos(angle31), sin(angle31)), 1.0e-14
        )
        for value in sequence:
            _assert_close(value.magnitude_squared(), 1.0, 2.0e-14)
    with assert_raises():
        _ = lte_pss(3)
    for invalid_identity in [Int.MIN, -1, 3, Int.MAX]:
        with assert_raises():
            _ = lte_pss_root(invalid_identity)


def test_sss_static_vectors_indices_and_all_504_identities() raises:
    assert_equal(lte_sss_indices(0), (0, 1))
    assert_equal(lte_sss_indices(34), (4, 6))
    assert_equal(lte_sss_indices(140), (0, 6))
    for n_id_1 in range(168):
        var q_prime = n_id_1 // 30
        var q = (n_id_1 + q_prime * (q_prime + 1) // 2) // 30
        var m_prime = n_id_1 + q * (q + 1) // 2
        assert_equal(
            lte_sss_indices(n_id_1),
            (m_prime % 31, (m_prime % 31 + m_prime // 31 + 1) % 31),
        )
    # Hand-transcribed sign signatures for PCI 0, least-significant bit first.
    assert_equal(_sss_signature(lte_sss(0, 0)), UInt64(0x21D0935BF10BF208))
    assert_equal(_sss_signature(lte_sss(0, 5)), UInt64(0x3C8A487DF29A2148))

    var signatures = List[UInt64](capacity=504)
    for physical_cell_id in range(504):
        var signature = _sss_signature(lte_sss(physical_cell_id, 0))
        for previous in signatures:
            assert_true(signature != previous)
        signatures.append(signature)
        assert_equal(len(lte_sss(physical_cell_id, 5)), 62)
    assert_equal(len(signatures), 504)
    with assert_raises():
        _ = lte_sss(-1, 0)
    with assert_raises():
        _ = lte_sss(504, 0)
    with assert_raises():
        _ = lte_sss(0, 1)
    for invalid_identity in [Int.MIN, -1, 168, Int.MAX]:
        with assert_raises():
            _ = lte_sss_indices(invalid_identity)


def test_fdd_bandwidth_fft_and_normal_cp_profiles() raises:
    var bandwidths = [1400, 3000, 5000, 10000, 15000, 20000]
    var resource_blocks = [6, 15, 25, 50, 75, 100]
    var fft_sizes = [128, 256, 512, 1024, 1536, 2048]
    for index in range(6):
        var configuration = lte_fdd_configuration(bandwidths[index])
        assert_equal(
            configuration.downlink_resource_blocks, resource_blocks[index]
        )
        assert_equal(
            configuration.uplink_resource_blocks, resource_blocks[index]
        )
        assert_equal(configuration.fft_size, fft_sizes[index])
        assert_equal(configuration.sample_rate_hz, 15000 * fft_sizes[index])
        assert_equal(
            lte_normal_cp_samples(configuration, 0),
            fft_sizes[index] * 160 // 2048,
        )
        assert_equal(
            lte_normal_cp_samples(configuration, 1),
            fft_sizes[index] * 144 // 2048,
        )
        assert_equal(
            lte_normal_cp_samples(configuration, 6),
            fft_sizes[index] * 144 // 2048,
        )
    for invalid_bandwidth in [Int.MIN, 7000, Int.MAX]:
        with assert_raises():
            _ = lte_fdd_configuration(invalid_bandwidth)
    var corrupted = lte_fdd_configuration(5000)
    corrupted.fft_size = 256
    with assert_raises():
        _ = lte_normal_cp_samples(corrupted, 0)
    var valid = lte_fdd_configuration(5000)
    for invalid_symbol in [Int.MIN, -1, 7, Int.MAX]:
        with assert_raises():
            _ = lte_normal_cp_samples(valid, invalid_symbol)


def test_crs_initialization_sequence_and_ports_zero_to_three_mapping() raises:
    assert_equal(lte_crs_c_init(0, 0, 0), UInt32(8193))
    for physical_cell_id in range(504):
        for slot in range(20):
            for symbol_in_slot in range(7):
                var expected_c_init = UInt32(
                    1024
                    * (7 * (slot + 1) + symbol_in_slot + 1)
                    * (2 * physical_cell_id + 1)
                    + 2 * physical_cell_id
                    + 1
                )
                assert_equal(
                    lte_crs_c_init(physical_cell_id, slot, symbol_in_slot),
                    expected_c_init,
                )
    var expected_bits = _reference_gold(UInt32(8193), 440)
    var sequence = lte_crs_sequence(0, 0, 0)
    assert_equal(len(sequence), 220)
    var qpsk_scale = 1.0 / sqrt(2.0)
    for index in range(220):
        _assert_complex_close(
            sequence[index],
            Complex64(
                qpsk_scale * (1.0 - 2.0 * Float64(expected_bits[2 * index])),
                qpsk_scale
                * (1.0 - 2.0 * Float64(expected_bits[2 * index + 1])),
            ),
            1.0e-15,
        )

    var port0 = lte_crs_port_mapping(0, 0, 0, 6)
    assert_equal(len(port0), 24)
    assert_equal(port0[0].symbol_in_slot, 0)
    assert_equal(port0[0].subcarrier, 0)
    assert_equal(port0[0].sequence_index, 104)
    assert_equal(port0[11].subcarrier, 66)
    assert_equal(port0[12].symbol_in_slot, 4)
    assert_equal(port0[12].subcarrier, 3)

    var port1 = lte_crs_port_mapping(0, 0, 1, 6)
    assert_equal(port1[0].subcarrier, 3)
    assert_equal(port1[12].subcarrier, 0)
    var port2_even = lte_crs_port_mapping(0, 0, 2, 6)
    var port3_even = lte_crs_port_mapping(0, 0, 3, 6)
    var port2_odd = lte_crs_port_mapping(0, 1, 2, 6)
    var port3_odd = lte_crs_port_mapping(0, 1, 3, 6)
    assert_equal(len(port2_even), 12)
    assert_equal(port2_even[0].symbol_in_slot, 1)
    assert_equal(port2_even[0].subcarrier, 0)
    assert_equal(port3_even[0].subcarrier, 3)
    assert_equal(port2_odd[0].subcarrier, 3)
    assert_equal(port3_odd[0].subcarrier, 0)
    with assert_raises():
        _ = lte_crs_port_mapping(0, 0, 4, 6)
    with assert_raises():
        _ = lte_crs_c_init(-1, 0, 0)
    with assert_raises():
        _ = lte_crs_c_init(504, 0, 0)
    with assert_raises():
        _ = lte_crs_c_init(0, -1, 0)
    with assert_raises():
        _ = lte_crs_c_init(0, 20, 0)
    with assert_raises():
        _ = lte_crs_c_init(0, 0, -1)
    with assert_raises():
        _ = lte_crs_c_init(0, 0, 7)
    with assert_raises():
        _ = lte_crs_c_init(Int.MIN, 0, 0)
    with assert_raises():
        _ = lte_crs_c_init(Int.MAX, 0, 0)
    with assert_raises():
        _ = lte_crs_c_init(0, Int.MIN, 0)
    with assert_raises():
        _ = lte_crs_c_init(0, Int.MAX, 0)
    with assert_raises():
        _ = lte_crs_c_init(0, 0, Int.MIN)
    with assert_raises():
        _ = lte_crs_c_init(0, 0, Int.MAX)


def test_pdsch_scrambling_initialization_and_binary_inverse() raises:
    assert_equal(
        lte_pdsch_scrambling_c_init(0x1234, 1, 7, 321), UInt32(76359489)
    )
    var rntis = [0, 1, 0x1234, 0xFFFF]
    var cell_ids = [0, 1, 321, 503]
    for rnti in rntis:
        for codeword in range(2):
            for slot in range(20):
                for physical_cell_id in cell_ids:
                    assert_equal(
                        lte_pdsch_scrambling_c_init(
                            rnti, codeword, slot, physical_cell_id
                        ),
                        UInt32(
                            rnti * (1 << 14)
                            + codeword * (1 << 13)
                            + (slot // 2) * (1 << 9)
                            + physical_cell_id
                        ),
                    )
    var bits = List[UInt8](capacity=193)
    for index in range(193):
        bits.append(UInt8((index * 7 + index // 5) & 1))
    var scrambled = lte_pdsch_scramble(Span(bits), 0x1234, 1, 7, 321)
    var expected_gold = _reference_gold(UInt32(76359489), len(bits))
    for index in range(len(bits)):
        assert_equal(scrambled[index], bits[index] ^ expected_gold[index])
    var restored = lte_pdsch_scramble(Span(scrambled), 0x1234, 1, 7, 321)
    assert_equal(restored, bits)
    var invalid: List[UInt8] = [0, 2]
    with assert_raises():
        _ = lte_pdsch_scramble(Span(invalid), 1, 0, 0, 0)
    with assert_raises():
        _ = lte_pdsch_scrambling_c_init(-1, 0, 0, 0)
    with assert_raises():
        _ = lte_pdsch_scrambling_c_init(0x10000, 0, 0, 0)
    with assert_raises():
        _ = lte_pdsch_scrambling_c_init(0, -1, 0, 0)
    with assert_raises():
        _ = lte_pdsch_scrambling_c_init(0, 2, 0, 0)
    with assert_raises():
        _ = lte_pdsch_scrambling_c_init(0, 0, -1, 0)
    with assert_raises():
        _ = lte_pdsch_scrambling_c_init(0, 0, 20, 0)
    with assert_raises():
        _ = lte_pdsch_scrambling_c_init(0, 0, 0, -1)
    with assert_raises():
        _ = lte_pdsch_scrambling_c_init(0, 0, 0, 504)


def test_sc_fdma_seeded_differential_energy_roundtrip_and_overflow() raises:
    var state = UInt64(0x4C54453230323608)
    var values = List[Complex64](capacity=24)
    for _ in range(24):
        state = state * UInt64(6364136223846793005) + UInt64(
            1442695040888963407
        )
        var real = (
            Float64(Int((state >> 33) & UInt64(0xFFFF)) - 32768) / 32768.0
        )
        state = state * UInt64(6364136223846793005) + UInt64(
            1442695040888963407
        )
        var imaginary = (
            Float64(Int((state >> 33) & UInt64(0xFFFF)) - 32768) / 32768.0
        )
        values.append(Complex64(real, imaginary))
    var actual = lte_sc_fdma_transform_precoding(Span(values))
    var expected = _reference_unitary_dft(Span(values), False)
    var input_energy = 0.0
    var output_energy = 0.0
    for index in range(24):
        _assert_complex_close(actual[index], expected[index], 2.0e-12)
        input_energy += values[index].magnitude_squared()
        output_energy += actual[index].magnitude_squared()
    _assert_close(output_energy, input_energy, 2.0e-11)
    var restored = lte_sc_fdma_transform_deprecoding(Span(actual))
    var expected_restored = _reference_unitary_dft(Span(actual), True)
    for index in range(24):
        _assert_complex_close(
            restored[index], expected_restored[index], 2.0e-12
        )
        _assert_complex_close(restored[index], values[index], 2.0e-11)

    var eleven = List[Complex64](length=11, fill=Complex64(0.0))
    with assert_raises():
        _ = lte_sc_fdma_transform_precoding(Span(eleven))
    # TS 36.211 clause 5.3.3 only permits transform sizes whose prime factors
    # are 2, 3, and 5.  Seven RBs (84 points) is inside 1..110 but forbidden.
    var seven_resource_blocks = List[Complex64](length=84, fill=Complex64(0.0))
    with assert_raises():
        _ = lte_sc_fdma_transform_precoding(Span(seven_resource_blocks))
    with assert_raises():
        _ = lte_sc_fdma_transform_deprecoding(Span(seven_resource_blocks))
    var nonfinite = List[Complex64](length=12, fill=Complex64(0.0))
    nonfinite[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = lte_sc_fdma_transform_precoding(Span(nonfinite))
    nonfinite[0] = Complex64(inf[DType.float64](), 0.0)
    with assert_raises():
        _ = lte_sc_fdma_transform_deprecoding(Span(nonfinite))
    var overflow = List[Complex64](
        length=12, fill=Complex64(Float64.MAX_FINITE, Float64.MAX_FINITE)
    )
    with assert_raises():
        _ = lte_sc_fdma_transform_precoding(Span(overflow))


def test_complete_base_downlink_and_uplink_mcs_rv_tables() raises:
    var dl_qm = [
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        2,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
    ]
    var dl_qm_prime = [
        2,
        2,
        2,
        2,
        2,
        4,
        4,
        4,
        4,
        4,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
        6,
    ]
    var dl_tbs = [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        15,
        16,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
    ]
    for index in range(29):
        var profile = lte_downlink_mcs_profile(index)
        assert_equal(profile.modulation_order, dl_qm[index])
        assert_equal(profile.second_slot_modulation_order, dl_qm_prime[index])
        assert_equal(profile.tbs_index, dl_tbs[index])
        assert_equal(profile.tbs_index_26a_possible, index == 28)
        profile.validate()
    for index in range(29, 32):
        with assert_raises():
            _ = lte_downlink_mcs_profile(index)
    with assert_raises():
        _ = lte_downlink_mcs_profile(Int.MIN)
    with assert_raises():
        _ = lte_downlink_mcs_profile(Int.MAX)
    for index in range(32):
        var downlink_entry = lte_downlink_mcs_entry(index)
        downlink_entry.validate()
        if index <= 28:
            assert_true(downlink_entry.has_new_transport_format)
            assert_equal(downlink_entry.modulation_order, dl_qm[index])
            assert_equal(downlink_entry.tbs_index, dl_tbs[index])
        else:
            assert_true(not downlink_entry.has_new_transport_format)
            assert_equal(downlink_entry.modulation_order, 2 * (index - 28))
            assert_equal(downlink_entry.tbs_index, -1)
    assert_equal(lte_downlink_redundancy_version(0), 0)
    assert_equal(lte_downlink_redundancy_version(1), 2)
    assert_equal(lte_downlink_redundancy_version(2), 3)
    assert_equal(lte_downlink_redundancy_version(3), 1)

    for index in range(32):
        var entry = lte_uplink_mcs_entry(index)
        entry.validate()
        if index <= 28:
            assert_true(entry.has_new_transport_format)
            assert_equal(entry.redundancy_version, 0)
            if index <= 10:
                assert_equal(entry.modulation_order, 2)
                assert_equal(entry.tbs_index, index)
            elif index <= 20:
                assert_equal(entry.modulation_order, 4)
                assert_equal(entry.tbs_index, index - 1)
            else:
                assert_equal(entry.modulation_order, 6)
                assert_equal(entry.tbs_index, index - 2)
        else:
            assert_true(not entry.has_new_transport_format)
            assert_equal(entry.modulation_order, 0)
            assert_equal(entry.tbs_index, -1)
            assert_equal(entry.redundancy_version, index - 28)
    var bad_dl = lte_downlink_mcs_profile(0)
    bad_dl.tbs_index = 1
    with assert_raises():
        bad_dl.validate()
    var bad_ul = lte_uplink_mcs_entry(0)
    bad_ul.redundancy_version = 1
    with assert_raises():
        bad_ul.validate()


def test_complete_base_tbs_table_checksum_boundaries_and_static_vectors() raises:
    var bounds = lte_base_tbs_table_bounds()
    assert_equal(bounds.minimum_base_tbs_index, 0)
    assert_equal(bounds.maximum_base_numeric_tbs_index, 26)
    assert_true(bounds.base_includes_named_26a)
    assert_equal(bounds.maximum_complete_numeric_tbs_index, 37)
    assert_true(bounds.complete_table_includes_named_alternates)
    assert_equal(bounds.minimum_resource_blocks, 1)
    assert_equal(bounds.maximum_resource_blocks, 110)
    assert_true(bounds.base_lookup_implemented)
    assert_true(not bounds.full_lookup_implemented)

    # External-static FNV checksum over row index followed by all 110 entries
    # for rows 0..26 and named row 26A (represented here by checksum row 27).
    var checksum = UInt64(14695981039346656037)
    for table_row in range(28):
        checksum = (checksum ^ UInt64(table_row)) * UInt64(1099511628211)
        for resource_blocks in range(1, 111):
            var value = lte_base_transport_block_size(
                26 if table_row == 27 else table_row,
                resource_blocks,
                use_index_26a=table_row == 27,
            )
            checksum = (checksum ^ UInt64(value)) * UInt64(1099511628211)
    assert_equal(checksum, UInt64(5448235802748136865))

    # Independently hand-transcribed corner and interior entries from the
    # official V18.3.0 table, including its row-6/N_PRB-1 value.
    assert_equal(lte_base_transport_block_size(0, 1), 16)
    assert_equal(lte_base_transport_block_size(0, 110), 3112)
    assert_equal(lte_base_transport_block_size(6, 1), 328)
    assert_equal(lte_base_transport_block_size(12, 57), 12960)
    assert_equal(lte_base_transport_block_size(20, 73), 34008)
    assert_equal(lte_base_transport_block_size(26, 110), 75376)
    assert_equal(lte_base_transport_block_size(26, 1, use_index_26a=True), 632)
    assert_equal(
        lte_base_transport_block_size(26, 110, use_index_26a=True), 71112
    )
    assert_equal(lte_downlink_transport_block_size(0, 1), 16)
    assert_equal(lte_downlink_transport_block_size(28, 1), 712)
    assert_equal(
        lte_downlink_transport_block_size(28, 1, use_index_26a=True), 632
    )
    with assert_raises():
        _ = lte_base_transport_block_size(-1, 1)
    with assert_raises():
        _ = lte_base_transport_block_size(27, 1)
    with assert_raises():
        _ = lte_base_transport_block_size(0, 0)
    with assert_raises():
        _ = lte_base_transport_block_size(0, 111)
    with assert_raises():
        _ = lte_base_transport_block_size(25, 1, use_index_26a=True)
    with assert_raises():
        _ = lte_downlink_transport_block_size(27, 1, use_index_26a=True)
    with assert_raises():
        _ = lte_downlink_transport_block_size(29, 1)


def test_representative_resource_allocations() raises:
    assert_equal(lte_downlink_resource_block_group_size(6), 1)
    assert_equal(lte_downlink_resource_block_group_size(11), 2)
    assert_equal(lte_downlink_resource_block_group_size(27), 3)
    assert_equal(lte_downlink_resource_block_group_size(64), 4)
    for resource_blocks in range(6, 111):
        var expected_group_size = (
            1 if resource_blocks
            <= 10 else 2 if resource_blocks
            <= 26 else 3 if resource_blocks
            <= 63 else 4
        )
        assert_equal(
            lte_downlink_resource_block_group_size(resource_blocks),
            expected_group_size,
        )
    for invalid_bandwidth in [Int.MIN, 5, 111, Int.MAX]:
        with assert_raises():
            _ = lte_downlink_resource_block_group_size(invalid_bandwidth)
    var selected = lte_downlink_type0_resource_blocks(
        50, UInt32(1) | (UInt32(1) << UInt32(16))
    )
    var expected_selected: List[Int] = [0, 1, 2, 48, 49]
    assert_equal(selected, expected_selected)
    with assert_raises():
        _ = lte_downlink_type0_resource_blocks(50, UInt32(1) << UInt32(17))

    for bandwidth in [6, 25, 50, 100]:
        for length in range(1, bandwidth + 1):
            for first in range(bandwidth - length + 1):
                var riv = lte_uplink_encode_riv(bandwidth, first, length)
                var decoded = lte_uplink_decode_riv(bandwidth, riv)
                assert_equal(decoded.first_resource_block, first)
                assert_equal(decoded.allocated_resource_blocks, length)
                assert_equal(decoded.resource_indication_value, riv)
    with assert_raises():
        _ = lte_uplink_decode_riv(6, 35)


def test_measurement_hand_values_scale_invariance_edges_and_overflow() raises:
    var rs_samples: List[Complex64] = [Complex64(3.0, 4.0), Complex64(0.0, 0.0)]
    _assert_close(lte_rsrp(Span(rs_samples)), 12.5, 1.0e-14)
    var rssi_samples = List[Complex64](length=4, fill=Complex64(1.0, 0.0))
    _assert_close(lte_rssi(Span(rssi_samples), 2), 2.0, 1.0e-14)
    _assert_close(lte_rsrq(1.0, 12.0, 6), 0.5, 1.0e-15)
    _assert_close(lte_rs_sinr_from_powers(4.0, 1.0), 4.0, 1.0e-15)
    var signal = List[Complex64](length=8, fill=Complex64(2.0, 0.0))
    var noise = List[Complex64](length=8, fill=Complex64(1.0, 0.0))
    _assert_close(lte_rs_sinr(Span(signal), Span(noise)), 4.0, 1.0e-14)

    var base_signal: List[Complex64] = [
        Complex64(1.0, 2.0),
        Complex64(-3.0, 1.0),
    ]
    var base_noise: List[Complex64] = [
        Complex64(0.5, -0.5),
        Complex64(1.0, 0.0),
    ]
    var scaled_signal = List[Complex64](capacity=2)
    var scaled_noise = List[Complex64](capacity=2)
    for index in range(2):
        scaled_signal.append(
            Complex64(
                base_signal[index].re * 1.0e100,
                base_signal[index].im * 1.0e100,
            )
        )
        scaled_noise.append(
            Complex64(
                base_noise[index].re * 1.0e100,
                base_noise[index].im * 1.0e100,
            )
        )
    var base_ratio = lte_rs_sinr(Span(base_signal), Span(base_noise))
    var scaled_ratio = lte_rs_sinr(Span(scaled_signal), Span(scaled_noise))
    _assert_close(scaled_ratio, base_ratio, 1.0e-13)
    _assert_close(lte_rsrq(1.0e-300, 2.0e-300, 10), 5.0, 1.0e-14)
    _assert_close(
        lte_rs_sinr_from_powers(Float64.MAX_FINITE, Float64.MAX_FINITE),
        1.0,
        0.0,
    )

    var empty = List[Complex64]()
    with assert_raises():
        _ = lte_rsrp(Span(empty))
    with assert_raises():
        _ = lte_rssi(Span(rssi_samples), 3)
    with assert_raises():
        _ = lte_rsrq(1.0, 0.0, 6)
    with assert_raises():
        _ = lte_rs_sinr_from_powers(1.0, 0.0)
    var maximum = List[Complex64](
        length=1, fill=Complex64(Float64.MAX_FINITE, 0.0)
    )
    with assert_raises():
        _ = lte_rsrp(Span(maximum))

    var one: List[Complex64] = [Complex64(1.0, 0.0)]
    var zero: List[Complex64] = [Complex64(0.0, 0.0)]
    _assert_close(lte_rsrp(Span(zero)), 0.0, 0.0)
    _assert_close(lte_rs_sinr_from_powers(0.0, 1.0), 0.0, 0.0)
    with assert_raises():
        _ = lte_rssi(Span(one), 0)
    with assert_raises():
        _ = lte_rssi(Span(one), Int.MIN)
    with assert_raises():
        _ = lte_rssi(Span(one), Int.MAX)
    with assert_raises():
        _ = lte_rsrq(1.0, 1.0, 0)
    with assert_raises():
        _ = lte_rsrq(1.0, 1.0, 111)
    with assert_raises():
        _ = lte_rsrq(1.0, 1.0, Int.MIN)
    with assert_raises():
        _ = lte_rsrq(1.0, 1.0, Int.MAX)
    with assert_raises():
        _ = lte_rsrq(-1.0, 1.0, 1)
    with assert_raises():
        _ = lte_rsrq(1.0, -1.0, 1)
    with assert_raises():
        _ = lte_rs_sinr_from_powers(-1.0, 1.0)
    with assert_raises():
        _ = lte_rs_sinr_from_powers(1.0, -1.0)
    with assert_raises():
        _ = lte_rs_sinr(Span(one), Span(empty))

    var invalid_scalars: List[Float64] = [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]
    for invalid in invalid_scalars:
        var invalid_observation: List[Complex64] = [Complex64(invalid, 0.0)]
        with assert_raises():
            _ = lte_rsrp(Span(invalid_observation))
        with assert_raises():
            _ = lte_rssi(Span(invalid_observation), 1)
        with assert_raises():
            _ = lte_rsrq(invalid, 1.0, 1)
        with assert_raises():
            _ = lte_rsrq(1.0, invalid, 1)
        with assert_raises():
            _ = lte_rs_sinr_from_powers(invalid, 1.0)
        with assert_raises():
            _ = lte_rs_sinr_from_powers(1.0, invalid)
        with assert_raises():
            _ = lte_rs_sinr(Span(invalid_observation), Span(one))
        with assert_raises():
            _ = lte_rs_sinr(Span(one), Span(invalid_observation))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
