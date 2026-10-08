"""Clause vectors and boundary evidence for bounded NR control/measurement APIs.

The fixed CRC, Gold, DM-RS, search-space, REG/CCE, RA-RNTI, timing-advance,
and linear-measurement expectations below are direct hand transcriptions or
independent scalar evaluations of the cited 3GPP equations.  End-to-end DCI
round trips are additional composition evidence and are not treated as the
sole oracle.
"""

from std.collections import Span
from std.math import log
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.control import (
    nr_dci_crc24c,
    nr_dci_crc24c_attach_mask,
    nr_dci_crc24c_check_masked,
    nr_dci_rnti_mask_crc,
    nr_pdcch_rate_matched_bit_count,
    nr_pdcch_scrambling_c_init,
    nr_pdcch_scramble,
    nr_pdcch_descramble_llrs,
    nr_pdcch_dmrs_c_init,
    nr_pdcch_dmrs,
    nr_pdcch_noninterleaved_regs,
    nr_pdcch_noninterleaved_data_resource_elements,
    nr_pdcch_dmrs_resource_elements,
    nr_pdcch_encode,
    nr_pdcch_decode,
)
from wireless_dsp.wireless.nr.procedures import (
    nr_coreset_cce_count,
    nr_uss_search_space_y,
    nr_search_space_candidate_first_cces,
    nr_search_space_candidate_cces,
    nr_ra_rnti,
    nr_timing_advance_absolute_tc,
    nr_timing_advance_delta_tc,
    nr_timing_advance_update_tc,
    nr_pusch_power_dbm,
    nr_pucch_resource_set_index,
    nr_pucch_resource_index,
    nr_pucch_resource_is_within_bwp,
)
from wireless_dsp.wireless.nr.measurements import (
    nr_reference_signal_received_power,
    nr_ss_rsrp,
    nr_csi_rsrp,
    nr_rssi,
    nr_ss_rsrq,
    nr_csi_rsrq,
    nr_ss_sinr,
    nr_csi_sinr,
    nr_ss_linear_measurements,
    nr_csi_linear_measurements,
)


def _assert_close(actual: Float64, expected: Float64, tolerance: Float64) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _dci_payload_vector() -> List[UInt8]:
    return [
        1, 0, 1, 1, 0, 0, 1, 0,
        1, 1, 0, 1, 0, 1, 1, 0,
        0, 1, 1, 1, 0, 0, 0, 1,
        1, 0, 0, 1, 1, 1, 0, 1,
    ]


def test_dci_crc24c_and_rnti_mask_static_clause_vector() raises:
    # Independent bit-serial evaluation of gCRC24C(D)=D24+D23+D21+D20+D17+
    # D15+D13+D12+D8+D4+D2+D+1, MSB first, initial register zero.
    var payload = _dci_payload_vector()
    assert_equal(nr_dci_crc24c(Span(payload)), UInt64(0x8B153E))
    var expected: List[UInt8] = [
        1, 0, 1, 1, 0, 0, 1, 0,
        1, 1, 0, 1, 0, 1, 1, 0,
        0, 1, 1, 1, 0, 0, 0, 1,
        1, 0, 0, 1, 1, 1, 0, 1,
        1, 0, 0, 0, 1, 0, 1, 1,
        0, 0, 0, 0, 0, 1, 1, 1,
        0, 0, 0, 0, 1, 0, 1, 0,
    ]
    var masked = nr_dci_crc24c_attach_mask(Span(payload), 0x1234)
    assert_equal(masked, expected)
    assert_true(nr_dci_crc24c_check_masked(Span(masked), 0x1234))
    var attached = nr_dci_rnti_mask_crc(Span(masked), 0x1234)
    assert_equal(len(attached), 56)
    for index in range(len(payload)):
        assert_equal(attached[index], payload[index])
    assert_true(not nr_dci_crc24c_check_masked(Span(masked), 0x1235))


def test_pdcch_scrambling_and_dmrs_static_clause_vectors() raises:
    assert_equal(
        nr_pdcch_scrambling_c_init(0x1234, 321), UInt32(0x12340141)
    )
    var zeros = List[UInt8](length=64, fill=UInt8(0))
    var expected_gold: List[UInt8] = [
        0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 0, 0, 1,
        0, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0,
        0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 1, 1,
    ]
    assert_equal(nr_pdcch_scramble(Span(zeros), 0x1234, 321), expected_gold)
    var hard_llrs = List[Float64](capacity=64)
    for bit in expected_gold:
        hard_llrs.append(7.0 if bit == 0 else -7.0)
    var descrambled = nr_pdcch_descramble_llrs(
        Span(hard_llrs), 0x1234, 321
    )
    for value in descrambled:
        assert_equal(value, 7.0)

    # Direct substitution into 2^17*(14*n_slot+l+1)*(2*n_ID+1)+2*n_ID.
    assert_equal(nr_pdcch_dmrs_c_init(7, 2, 321), UInt32(0x7B5E0282))
    var dmrs = nr_pdcch_dmrs(7, 2, 321, 4)
    assert_equal(len(dmrs), 12)
    var expected_bits: List[UInt8] = [
        1, 0, 1, 0, 0, 1, 1, 0,
        0, 1, 0, 1, 1, 0, 0, 1,
        1, 1, 1, 1, 0, 0, 1, 1,
    ]
    var scale = 0.7071067811865475244
    for index in range(12):
        _assert_close(
            dmrs[index].re,
            scale * (1.0 - 2.0 * Float64(expected_bits[2 * index])),
            1.0e-12,
        )
        _assert_close(
            dmrs[index].im,
            scale * (1.0 - 2.0 * Float64(expected_bits[2 * index + 1])),
            1.0e-12,
        )


def test_noninterleaved_coreset_reg_cce_and_re_mapping() raises:
    assert_equal(nr_pdcch_rate_matched_bit_count(2), 216)
    assert_equal(nr_coreset_cce_count(12, 2), 4)
    var regs = nr_pdcch_noninterleaved_regs(
        12, 2, 2, 2, first_symbol=3, first_resource_block=10
    )
    assert_equal(len(regs), 12)
    assert_equal(regs[0].cce_index, 2)
    assert_equal(regs[0].reg_index, 12)
    assert_equal(regs[0].symbol, 3)
    assert_equal(regs[0].resource_block, 16)
    assert_equal(regs[1].symbol, 4)
    assert_equal(regs[1].resource_block, 16)
    assert_equal(regs[6].cce_index, 3)
    assert_equal(regs[11].reg_index, 23)
    assert_equal(regs[11].resource_block, 21)

    var data_res = nr_pdcch_noninterleaved_data_resource_elements(
        12, 2, 2, 2, first_symbol=3, first_resource_block=10
    )
    assert_equal(len(data_res), 108)
    var expected_first_subcarriers: List[Int] = [192, 192, 194, 194, 195, 195, 196, 196]
    for index in range(8):
        assert_equal(data_res[index].subcarrier, expected_first_subcarriers[index])
        assert_equal(data_res[index].reg_index, 12 + index % 2)

    var dmrs_res = nr_pdcch_dmrs_resource_elements(
        12, 2, first_symbol=3, first_resource_block=10
    )
    assert_equal(len(dmrs_res), 72)
    assert_equal(dmrs_res[0].subcarrier, 121)
    assert_equal(dmrs_res[1].subcarrier, 125)
    assert_equal(dmrs_res[2].subcarrier, 129)
    assert_equal(dmrs_res[3].symbol, 3)
    assert_equal(dmrs_res[3].subcarrier, 133)
    assert_equal(dmrs_res[36].symbol, 4)
    assert_equal(dmrs_res[36].subcarrier, 121)


def test_search_space_candidate_static_vectors() raises:
    # Direct clause 10.1 recurrence from Y[-1]=0x1234.
    assert_equal(nr_uss_search_space_y(0x1234, 0), 58573)
    assert_equal(nr_uss_search_space_y(0x1234, 1), 62893)
    assert_equal(nr_uss_search_space_y(0x1234, 2), 15371)
    assert_equal(nr_uss_search_space_y(0x1234, 3), 65237)
    assert_equal(nr_uss_search_space_y(0x1234, 0, coreset_index=1), 2356)
    assert_equal(nr_uss_search_space_y(0x1234, 0, coreset_index=2), 48956)
    assert_equal(
        nr_search_space_candidate_first_cces(
            24, 4, 4, 65237, carrier_indicator=2
        ),
        [4, 8, 16, 20],
    )
    assert_equal(
        nr_search_space_candidate_first_cces(8, 2, 4, 0),
        [0, 2, 4, 6],
    )
    assert_equal(
        nr_search_space_candidate_first_cces(
            24, 4, 2, 0, maximum_candidate_count=4
        ),
        [0, 4],
    )
    assert_equal(
        nr_search_space_candidate_first_cces(3, 2, 1, 0),
        [0],
    )
    assert_equal(
        nr_search_space_candidate_cces(8, 2, 4, 0),
        [0, 1, 2, 3, 4, 5, 6, 7],
    )


def test_stateless_control_procedure_hand_oracles() raises:
    assert_equal(nr_ra_rnti(0, 0, 0, 0), 1)
    assert_equal(nr_ra_rnti(13, 79, 7, 1), 17920)
    assert_equal(nr_ra_rnti(2, 3, 1, 0), 1165)

    assert_equal(nr_timing_advance_absolute_tc(100, 2), 25600)
    assert_equal(nr_timing_advance_delta_tc(31, 0), 0)
    assert_equal(nr_timing_advance_delta_tc(0, 0), -31744)
    assert_equal(nr_timing_advance_delta_tc(63, 0), 32768)
    assert_equal(nr_timing_advance_update_tc(50000, 30, 1), 49488)

    var expected_power = 10.0 * log(40.0) / log(10.0)
    _assert_close(
        nr_pusch_power_dbm(10, 2, -80.0, 0.8, 100.0, 0.0, 0.0, 23.0),
        expected_power,
        1.0e-12,
    )
    assert_equal(
        nr_pusch_power_dbm(10, 2, -80.0, 0.8, 100.0, 0.0, 0.0, 10.0),
        10.0,
    )

    assert_equal(nr_pucch_resource_set_index(2), 0)
    assert_equal(
        nr_pucch_resource_set_index(
            3, set1_max_payload=10, set2_max_payload=100
        ),
        1,
    )
    assert_equal(
        nr_pucch_resource_set_index(
            11, set1_max_payload=10, set2_max_payload=100
        ),
        2,
    )
    assert_equal(
        nr_pucch_resource_set_index(
            101, set1_max_payload=10, set2_max_payload=100
        ),
        3,
    )
    assert_equal(nr_pucch_resource_index(3, 4), 3)
    assert_true(nr_pucch_resource_is_within_bwp(100, 20, 30, 20, 4))
    assert_true(nr_pucch_resource_is_within_bwp(
        100, 20, 30, 45, 4, second_hop_prb=21
    ))
    assert_true(not nr_pucch_resource_is_within_bwp(100, 20, 30, 48, 4))
    assert_true(not nr_pucch_resource_is_within_bwp(
        100, 20, 30, 21, 4, second_hop_prb=49
    ))


def test_linear_measurement_hand_oracles() raises:
    var reference: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(0.0, 1.0)
    ]
    var interference: List[Complex64] = [
        Complex64(0.5, 0.0), Complex64(0.0, -0.5)
    ]
    # Two observations, each containing two measured-bandwidth REs:
    # (1^2+2^2 + 3^2+4^2) / 2 = 15.
    var bandwidth: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(2.0, 0.0),
        Complex64(3.0, 0.0), Complex64(4.0, 0.0),
    ]
    assert_equal(nr_reference_signal_received_power(Span(reference)), 1.0)
    assert_equal(nr_ss_rsrp(Span(reference)), 1.0)
    assert_equal(nr_csi_rsrp(Span(reference)), 1.0)
    _assert_close(nr_rssi(Span(bandwidth), 2), 15.0, 1.0e-14)
    _assert_close(nr_ss_rsrq(1.0, 15.0, 12), 0.8, 1.0e-14)
    _assert_close(nr_csi_rsrq(1.0, 15.0, 12), 0.8, 1.0e-14)
    assert_equal(nr_ss_sinr(1.0, 0.25), 4.0)
    assert_equal(nr_csi_sinr(1.0, 0.25), 4.0)
    var ss = nr_ss_linear_measurements(
        Span(reference), Span(bandwidth), Span(interference), 12, 2
    )
    assert_equal(ss.rsrp, 1.0)
    _assert_close(ss.rsrq, 0.8, 1.0e-14)
    assert_equal(ss.sinr, 4.0)
    _assert_close(ss.rssi, 15.0, 1.0e-14)
    var csi = nr_csi_linear_measurements(
        Span(reference), Span(bandwidth), Span(interference), 12, 2
    )
    assert_equal(csi.rsrp, ss.rsrp)
    assert_equal(csi.rsrq, ss.rsrq)
    assert_equal(csi.sinr, ss.sinr)
    assert_equal(csi.rssi, ss.rssi)


def test_pdcch_seeded_roundtrip_and_checkpoints() raises:
    var state = UInt64(0x5EED382122112026)
    for payload_size, aggregation_level in [(24, 1), (64, 1), (100, 2), (140, 4)]:
        var payload = List[UInt8](capacity=payload_size)
        for _ in range(payload_size):
            state = (
                state * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            payload.append(UInt8((state >> UInt64(63)) & UInt64(1)))
        var encoded = nr_pdcch_encode(
            Span(payload), 0x4601, 321, aggregation_level,
            testcase_id="nr-pdcch-seeded-tx",
        )
        var e = nr_pdcch_rate_matched_bit_count(aggregation_level)
        assert_equal(len(encoded.crc_attached_masked), payload_size + 24)
        assert_equal(len(encoded.rate_matched), e)
        assert_equal(len(encoded.scrambled), e)
        assert_equal(len(encoded.qpsk_symbols), e // 2)
        assert_equal(len(encoded.checkpoint_metadata), 7)
        assert_equal(encoded.checkpoint_metadata[0].stage, "dci-payload")
        assert_equal(encoded.checkpoint_metadata[6].stage, "qpsk-symbols")
        assert_equal(encoded.checkpoint_metadata[0].testcase_id, "nr-pdcch-seeded-tx")

        var llrs = List[Float64](capacity=e)
        for index in range(e):
            var magnitude = 48.0 + Float64((index % 7) - 3) * 0.125
            llrs.append(magnitude if encoded.scrambled[index] == 0 else -magnitude)
        var decoded = nr_pdcch_decode(
            Span(llrs), payload_size, 0x4601, 321, aggregation_level,
            testcase_id="nr-pdcch-seeded-rx",
        )
        assert_true(decoded.crc_ok)
        assert_equal(decoded.payload, payload)
        assert_equal(len(decoded.decoded_masked_information), payload_size + 24)
        assert_equal(len(decoded.checkpoint_metadata), 7)
        assert_equal(
            decoded.checkpoint_metadata[2].stage,
            "polar-rate-recovered-llrs",
        )
        assert_equal(decoded.checkpoint_metadata[6].layout, "scalar")


def test_public_boundaries_finite_overflow_and_invalid_profiles() raises:
    with assert_raises():
        _ = nr_dci_crc24c(Span(List[UInt8]()))
    with assert_raises():
        _ = nr_dci_rnti_mask_crc(Span(List[UInt8](length=24, fill=UInt8(0))), 1)
    with assert_raises():
        _ = nr_dci_crc24c_attach_mask(Span(List[UInt8]()), 1)
    with assert_raises():
        _ = nr_dci_crc24c_check_masked(Span(List[UInt8](length=24, fill=UInt8(0))), 1)
    with assert_raises():
        _ = nr_pdcch_rate_matched_bit_count(3)
    with assert_raises():
        _ = nr_pdcch_scrambling_c_init(-1, 0)
    var invalid_bits: List[UInt8] = [2]
    with assert_raises():
        _ = nr_pdcch_scramble(Span(invalid_bits), 1, 0)
    with assert_raises():
        _ = nr_pdcch_dmrs_c_init(0, 14, 0)
    with assert_raises():
        _ = nr_pdcch_dmrs(0, 0, 0, 276)
    with assert_raises():
        _ = nr_pdcch_encode(Span(List[UInt8](length=85, fill=UInt8(0))), 1, 0, 1)
    with assert_raises():
        _ = nr_pdcch_noninterleaved_regs(7, 1, 0, 1)
    with assert_raises():
        _ = nr_pdcch_noninterleaved_data_resource_elements(7, 1, 0, 1)
    with assert_raises():
        _ = nr_pdcch_dmrs_resource_elements(7, 1)
    var too_short_llrs = List[Float64](length=107, fill=1.0)
    with assert_raises():
        _ = nr_pdcch_decode(Span(too_short_llrs), 32, 1, 0, 1)
    with assert_raises():
        _ = nr_coreset_cce_count(7, 1)
    with assert_raises():
        _ = nr_uss_search_space_y(0, 0)
    with assert_raises():
        _ = nr_search_space_candidate_first_cces(4, 8, 1, 0)
    with assert_raises():
        _ = nr_search_space_candidate_cces(4, 8, 1, 0)
    with assert_raises():
        _ = nr_ra_rnti(14, 0, 0, 0)
    with assert_raises():
        _ = nr_timing_advance_absolute_tc(3847, 0)
    with assert_raises():
        _ = nr_timing_advance_delta_tc(64, 0)
    with assert_raises():
        _ = nr_timing_advance_update_tc(Int.MAX, 63, 0)
    with assert_raises():
        _ = nr_timing_advance_update_tc(Int.MIN, 0, 0)
    with assert_raises():
        _ = nr_pucch_resource_index(4, 4)
    with assert_raises():
        _ = nr_pucch_resource_set_index(1707)
    with assert_raises():
        _ = nr_pucch_resource_is_within_bwp(100, 90, 20, 90, 1)

    var invalid_llrs: List[Float64] = [nan[DType.float64](), 1.0]
    with assert_raises():
        _ = nr_pdcch_descramble_llrs(Span(invalid_llrs), 1, 0)
    invalid_llrs[0] = inf[DType.float64]()
    with assert_raises():
        _ = nr_pdcch_descramble_llrs(Span(invalid_llrs), 1, 0)
    with assert_raises():
        _ = nr_pusch_power_dbm(1, 0, 0.0, 1.0, inf[DType.float64](), 0.0, 0.0, 23.0)

    var maximum_sample: List[Complex64] = [
        Complex64(Float64.MAX_FINITE, 0.0)
    ]
    with assert_raises():
        _ = nr_reference_signal_received_power(Span(List[Complex64]()))
    with assert_raises():
        _ = nr_ss_rsrp(Span(maximum_sample))
    with assert_raises():
        _ = nr_csi_rsrp(Span(List[Complex64]()))
    with assert_raises():
        _ = nr_rssi(Span(maximum_sample), 0)
    var finite_large: List[Complex64] = [Complex64(1.0e154, 0.0)]
    _assert_close(nr_ss_rsrp(Span(finite_large)) / 1.0e308, 1.0, 1.0e-15)
    with assert_raises():
        _ = nr_ss_rsrq(1.0, 0.0, 1)
    with assert_raises():
        _ = nr_csi_rsrq(1.0, 0.0, 1)
    with assert_raises():
        _ = nr_ss_sinr(1.0, 0.0)
    with assert_raises():
        _ = nr_csi_sinr(1.0, 0.0)
    var one_sample: List[Complex64] = [Complex64(1.0, 0.0)]
    var one_bandwidth: List[Complex64] = [Complex64(1.0, 0.0)]
    var two_samples: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(1.0, 0.0)
    ]
    with assert_raises():
        _ = nr_ss_linear_measurements(
            Span(one_sample), Span(one_bandwidth), Span(two_samples), 1, 1
        )
    with assert_raises():
        _ = nr_csi_linear_measurements(
            Span(one_sample), Span(one_bandwidth), Span(two_samples), 1, 1
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
