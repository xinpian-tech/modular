"""Per-public-API latency distributions for bounded NR algorithms.

Every kernel-ledger public API has a direct ``@no_inline`` workload, three
untimed warmups, and nine independent samples.  All input construction,
including every ``List`` and input ``Span``, occurs before timing.  A timed
region contains exactly one target call.  Complete owned results are retained
and only O(1) endpoint fingerprints are computed after the timer stops.
"""

from std.benchmark import keep
from std.collections import Span
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr.control import (
    NRPDCCHREGLocation,
    NRPDCCHResourceElement,
    NRPDCCHTransmitBlock,
    NRPDCCHDecodeResult,
    nr_pdcch_encode,
    nr_pdcch_decode,
    nr_dci_crc24c,
    nr_dci_rnti_mask_crc,
    nr_dci_crc24c_attach_mask,
    nr_dci_crc24c_check_masked,
    nr_pdcch_rate_matched_bit_count,
    nr_pdcch_scrambling_c_init,
    nr_pdcch_scramble,
    nr_pdcch_descramble_llrs,
    nr_pdcch_dmrs_c_init,
    nr_pdcch_dmrs,
    nr_pdcch_noninterleaved_regs,
    nr_pdcch_noninterleaved_data_resource_elements,
    nr_pdcch_dmrs_resource_elements,
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
    NRLinearMeasurements,
    nr_reference_signal_received_power,
    nr_ss_rsrp,
    nr_ss_linear_measurements,
    nr_csi_linear_measurements,
    nr_csi_rsrp,
    nr_rssi,
    nr_ss_rsrq,
    nr_csi_rsrq,
    nr_ss_sinr,
    nr_csi_sinr,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _PAYLOAD_BITS = 64
comptime _RNTI = 0x4601
comptime _SCRAMBLING_ID = 321
comptime _FNV_OFFSET = UInt64(14695981039346656037)
comptime _FNV_PRIME = UInt64(1099511628211)


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 8192)) * _FNV_PRIME


def _mix_u64(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * _FNV_PRIME


def _float_token(value: Float64) -> Int:
    return Int((value + 256.0) * 1_000_000.0)


def _require_repeat(first: UInt64, second: UInt64) raises:
    if first != second:
        raise Error("NR specification fixed-input workload is nondeterministic")
    keep(first)
    keep(second)


def _u8_list_fingerprint(values: Span[UInt8, ...]) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, len(values))
    checksum = _mix(checksum, Int(values[0]))
    return _mix(checksum, Int(values[len(values) - 1]))


def _int_list_fingerprint(values: Span[Int, ...]) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, len(values))
    checksum = _mix(checksum, values[0])
    return _mix(checksum, values[len(values) - 1])


def _float_list_fingerprint(values: Span[Float64, ...]) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, len(values))
    checksum = _mix(checksum, _float_token(values[0]))
    return _mix(checksum, _float_token(values[len(values) - 1]))


def _complex_list_fingerprint(values: Span[Complex64, ...]) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, len(values))
    checksum = _mix(checksum, _float_token(values[0].re))
    checksum = _mix(checksum, _float_token(values[0].im))
    checksum = _mix(checksum, _float_token(values[len(values) - 1].re))
    return _mix(checksum, _float_token(values[len(values) - 1].im))


def _reg_list_fingerprint(values: Span[NRPDCCHREGLocation, ...]) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, len(values))
    checksum = _mix(checksum, values[0].reg_index)
    checksum = _mix(checksum, values[0].resource_block)
    checksum = _mix(checksum, values[len(values) - 1].reg_index)
    return _mix(checksum, values[len(values) - 1].resource_block)


def _resource_element_list_fingerprint(
    values: Span[NRPDCCHResourceElement, ...],
) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, len(values))
    checksum = _mix(checksum, values[0].reg_index)
    checksum = _mix(checksum, values[0].subcarrier)
    checksum = _mix(checksum, values[len(values) - 1].reg_index)
    return _mix(checksum, values[len(values) - 1].subcarrier)


def _tx_fingerprint(
    payload: Span[UInt8, ...],
    scrambled: Span[UInt8, ...],
    symbols: Span[Complex64, ...],
) -> UInt64:
    var checksum = _u8_list_fingerprint(payload)
    checksum = _mix_u64(checksum, _u8_list_fingerprint(scrambled))
    return _mix_u64(checksum, _complex_list_fingerprint(symbols))


def _decode_fingerprint(
    payload: Span[UInt8, ...], crc_ok: Bool, recovered_length: Int,
) -> UInt64:
    var checksum = _u8_list_fingerprint(payload)
    checksum = _mix(checksum, Int(crc_ok))
    return _mix(checksum, recovered_length)


def _measurement_fingerprint(value: NRLinearMeasurements) -> UInt64:
    var checksum = _mix(_FNV_OFFSET, _float_token(value.rsrp))
    checksum = _mix(checksum, _float_token(value.rsrq))
    checksum = _mix(checksum, _float_token(value.sinr))
    return _mix(checksum, _float_token(value.rssi))


def _payload() -> List[UInt8]:
    var state = UInt64(0x5EED38212213215)
    var result = List[UInt8](capacity=_PAYLOAD_BITS)
    for _ in range(_PAYLOAD_BITS):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        result.append(UInt8((state >> UInt64(63)) & UInt64(1)))
    return result^


def _hard_llrs(bits: Span[UInt8, ...]) -> List[Float64]:
    var result = List[Float64](capacity=len(bits))
    for index in range(len(bits)):
        result.append(48.0 if bits[index] == 0 else -48.0)
    return result^


@no_inline
def _nr_dci_crc24c_workload(
    bits: Span[UInt8, ...],
) raises -> UInt64:
    return nr_dci_crc24c(bits)


@no_inline
def _nr_dci_rnti_mask_crc_workload(
    crc_attached: Span[UInt8, ...],
) raises -> List[UInt8]:
    return nr_dci_rnti_mask_crc(crc_attached, _RNTI)


@no_inline
def _nr_dci_crc24c_attach_mask_workload(
    payload: Span[UInt8, ...],
) raises -> List[UInt8]:
    return nr_dci_crc24c_attach_mask(payload, _RNTI)


@no_inline
def _nr_dci_crc24c_check_masked_workload(
    crc_attached_masked: Span[UInt8, ...],
) raises -> Bool:
    return nr_dci_crc24c_check_masked(crc_attached_masked, _RNTI)


@no_inline
def _nr_pdcch_scrambling_c_init_workload() raises -> UInt32:
    return nr_pdcch_scrambling_c_init(_RNTI, _SCRAMBLING_ID)


@no_inline
def _nr_pdcch_scramble_workload(
    bits: Span[UInt8, ...],
) raises -> List[UInt8]:
    return nr_pdcch_scramble(bits, _RNTI, _SCRAMBLING_ID)


@no_inline
def _nr_pdcch_descramble_llrs_workload(
    llrs: Span[Float64, ...],
) raises -> List[Float64]:
    return nr_pdcch_descramble_llrs(llrs, _RNTI, _SCRAMBLING_ID)


@no_inline
def _nr_pdcch_dmrs_c_init_workload() raises -> UInt32:
    return nr_pdcch_dmrs_c_init(7, 2, _SCRAMBLING_ID)


@no_inline
def _nr_pdcch_dmrs_workload() raises -> List[Complex64]:
    return nr_pdcch_dmrs(7, 2, _SCRAMBLING_ID, 6)


@no_inline
def _nr_pdcch_rate_matched_bit_count_workload() raises -> Int:
    return nr_pdcch_rate_matched_bit_count(2)


@no_inline
def _nr_pdcch_noninterleaved_regs_workload(
) raises -> List[NRPDCCHREGLocation]:
    return nr_pdcch_noninterleaved_regs(12, 2, 0, 2)


@no_inline
def _nr_pdcch_noninterleaved_data_resource_elements_workload(
) raises -> List[NRPDCCHResourceElement]:
    return nr_pdcch_noninterleaved_data_resource_elements(12, 2, 0, 2)


@no_inline
def _nr_pdcch_dmrs_resource_elements_workload(
) raises -> List[NRPDCCHResourceElement]:
    return nr_pdcch_dmrs_resource_elements(12, 2)


@no_inline
def _nr_pdcch_encode_workload(
    payload: Span[UInt8, ...],
) raises -> NRPDCCHTransmitBlock:
    return nr_pdcch_encode(payload, _RNTI, _SCRAMBLING_ID, 1)


@no_inline
def _nr_pdcch_decode_workload(
    llrs: Span[Float64, ...],
) raises -> NRPDCCHDecodeResult:
    return nr_pdcch_decode(
        llrs, _PAYLOAD_BITS, _RNTI, _SCRAMBLING_ID, 1
    )


@no_inline
def _nr_coreset_cce_count_workload() raises -> Int:
    return nr_coreset_cce_count(48, 3)


@no_inline
def _nr_uss_search_space_y_workload() raises -> Int:
    return nr_uss_search_space_y(_RNTI, 1024)


@no_inline
def _nr_search_space_candidate_first_cces_workload(
    y: Int,
) raises -> List[Int]:
    return nr_search_space_candidate_first_cces(
        24, 4, 4, y, carrier_indicator=1
    )


@no_inline
def _nr_search_space_candidate_cces_workload(
    y: Int,
) raises -> List[Int]:
    return nr_search_space_candidate_cces(24, 4, 4, y)


@no_inline
def _nr_ra_rnti_workload() raises -> Int:
    return nr_ra_rnti(2, 3, 1, 0)


@no_inline
def _nr_timing_advance_absolute_tc_workload() raises -> Int:
    return nr_timing_advance_absolute_tc(100, 2)


@no_inline
def _nr_timing_advance_delta_tc_workload() raises -> Int:
    return nr_timing_advance_delta_tc(30, 1)


@no_inline
def _nr_timing_advance_update_tc_workload() raises -> Int:
    return nr_timing_advance_update_tc(50000, 30, 1)


@no_inline
def _nr_pucch_resource_set_index_workload() raises -> Int:
    return nr_pucch_resource_set_index(
        48, set1_max_payload=64, set2_max_payload=512
    )


@no_inline
def _nr_pucch_resource_index_workload() raises -> Int:
    return nr_pucch_resource_index(3, 4)


@no_inline
def _nr_pucch_resource_is_within_bwp_workload() raises -> Bool:
    return nr_pucch_resource_is_within_bwp(
        100, 20, 30, 24, 4, second_hop_prb=40
    )


@no_inline
def _nr_pusch_power_dbm_workload() raises -> Float64:
    return nr_pusch_power_dbm(
        10, 2, -80.0, 0.8, 100.0, 0.0, 0.0, 23.0
    )


@no_inline
def _nr_reference_signal_received_power_workload(
    reference: Span[Complex64, ...],
) raises -> Float64:
    return nr_reference_signal_received_power(reference)


@no_inline
def _nr_ss_rsrp_workload(
    reference: Span[Complex64, ...],
) raises -> Float64:
    return nr_ss_rsrp(reference)


@no_inline
def _nr_csi_rsrp_workload(
    reference: Span[Complex64, ...],
) raises -> Float64:
    return nr_csi_rsrp(reference)


@no_inline
def _nr_rssi_workload(
    bandwidth: Span[Complex64, ...],
) raises -> Float64:
    return nr_rssi(bandwidth, 2)


@no_inline
def _nr_ss_rsrq_workload(rsrp: Float64, rssi: Float64) raises -> Float64:
    return nr_ss_rsrq(rsrp, rssi, 12)


@no_inline
def _nr_csi_rsrq_workload(rsrp: Float64, rssi: Float64) raises -> Float64:
    return nr_csi_rsrq(rsrp, rssi, 12)


@no_inline
def _nr_ss_sinr_workload(rsrp: Float64) raises -> Float64:
    return nr_ss_sinr(rsrp, 0.25)


@no_inline
def _nr_csi_sinr_workload(rsrp: Float64) raises -> Float64:
    return nr_csi_sinr(rsrp, 0.25)


@no_inline
def _nr_ss_linear_measurements_workload(
    reference: Span[Complex64, ...],
    bandwidth: Span[Complex64, ...],
    interference: Span[Complex64, ...],
) raises -> NRLinearMeasurements:
    return nr_ss_linear_measurements(
        reference, bandwidth, interference, 12, 2
    )


@no_inline
def _nr_csi_linear_measurements_workload(
    reference: Span[Complex64, ...],
    bandwidth: Span[Complex64, ...],
    interference: Span[Complex64, ...],
) raises -> NRLinearMeasurements:
    return nr_csi_linear_measurements(
        reference, bandwidth, interference, 12, 2
    )


def _fixed_input_checksum(
    payload: Span[UInt8, ...],
    masked: Span[UInt8, ...],
    scrambled_llrs: Span[Float64, ...],
    decode_llrs: Span[Float64, ...],
    reference: Span[Complex64, ...],
    bandwidth: Span[Complex64, ...],
    interference: Span[Complex64, ...],
    y: Int,
    ss_rsrp: Float64,
    csi_rsrp: Float64,
    rssi: Float64,
) raises -> UInt64:
    var checksum = _FNV_OFFSET

    var crc = _nr_dci_crc24c_workload(payload)
    checksum = _mix_u64(checksum, crc)
    keep(crc)

    var unmasked = _nr_dci_rnti_mask_crc_workload(masked)
    checksum = _mix_u64(checksum, _u8_list_fingerprint(Span(unmasked)))
    keep(unmasked)

    var attached = _nr_dci_crc24c_attach_mask_workload(payload)
    checksum = _mix_u64(checksum, _u8_list_fingerprint(Span(attached)))
    keep(attached)

    var crc_ok = _nr_dci_crc24c_check_masked_workload(masked)
    checksum = _mix(checksum, Int(crc_ok))
    keep(crc_ok)

    var scrambling_init = _nr_pdcch_scrambling_c_init_workload()
    checksum = _mix_u64(checksum, UInt64(scrambling_init))
    keep(scrambling_init)

    var scrambled = _nr_pdcch_scramble_workload(masked)
    checksum = _mix_u64(checksum, _u8_list_fingerprint(Span(scrambled)))
    keep(scrambled)

    var descrambled = _nr_pdcch_descramble_llrs_workload(scrambled_llrs)
    checksum = _mix_u64(
        checksum, _float_list_fingerprint(Span(descrambled))
    )
    keep(descrambled)

    var dmrs_init = _nr_pdcch_dmrs_c_init_workload()
    checksum = _mix_u64(checksum, UInt64(dmrs_init))
    keep(dmrs_init)

    var dmrs = _nr_pdcch_dmrs_workload()
    checksum = _mix_u64(checksum, _complex_list_fingerprint(Span(dmrs)))
    keep(dmrs)

    var matched_count = _nr_pdcch_rate_matched_bit_count_workload()
    checksum = _mix(checksum, matched_count)
    keep(matched_count)

    var regs = _nr_pdcch_noninterleaved_regs_workload()
    checksum = _mix_u64(checksum, _reg_list_fingerprint(Span(regs)))
    keep(regs)

    var data_res = _nr_pdcch_noninterleaved_data_resource_elements_workload()
    checksum = _mix_u64(
        checksum, _resource_element_list_fingerprint(Span(data_res))
    )
    keep(data_res)

    var dmrs_res = _nr_pdcch_dmrs_resource_elements_workload()
    checksum = _mix_u64(
        checksum, _resource_element_list_fingerprint(Span(dmrs_res))
    )
    keep(dmrs_res)

    var encoded = _nr_pdcch_encode_workload(payload)
    checksum = _mix_u64(
        checksum,
        _tx_fingerprint(
            Span(encoded.payload),
            Span(encoded.scrambled),
            Span(encoded.qpsk_symbols),
        ),
    )
    keep(encoded)

    var decoded = _nr_pdcch_decode_workload(decode_llrs)
    checksum = _mix_u64(
        checksum,
        _decode_fingerprint(
            Span(decoded.payload),
            decoded.crc_ok,
            len(decoded.rate_recovered_llrs),
        ),
    )
    keep(decoded)

    var cce_count = _nr_coreset_cce_count_workload()
    checksum = _mix(checksum, cce_count)
    keep(cce_count)

    var search_y = _nr_uss_search_space_y_workload()
    checksum = _mix(checksum, search_y)
    keep(search_y)

    var first_cces = _nr_search_space_candidate_first_cces_workload(y)
    checksum = _mix_u64(
        checksum, _int_list_fingerprint(Span(first_cces))
    )
    keep(first_cces)

    var candidate_cces = _nr_search_space_candidate_cces_workload(y)
    checksum = _mix_u64(
        checksum, _int_list_fingerprint(Span(candidate_cces))
    )
    keep(candidate_cces)

    var ra_rnti = _nr_ra_rnti_workload()
    checksum = _mix(checksum, ra_rnti)
    keep(ra_rnti)

    var absolute_timing = _nr_timing_advance_absolute_tc_workload()
    checksum = _mix(checksum, absolute_timing)
    keep(absolute_timing)

    var timing_delta = _nr_timing_advance_delta_tc_workload()
    checksum = _mix(checksum, timing_delta)
    keep(timing_delta)

    var timing_update = _nr_timing_advance_update_tc_workload()
    checksum = _mix(checksum, timing_update)
    keep(timing_update)

    var resource_set = _nr_pucch_resource_set_index_workload()
    checksum = _mix(checksum, resource_set)
    keep(resource_set)

    var resource_index = _nr_pucch_resource_index_workload()
    checksum = _mix(checksum, resource_index)
    keep(resource_index)

    var within_bwp = _nr_pucch_resource_is_within_bwp_workload()
    checksum = _mix(checksum, Int(within_bwp))
    keep(within_bwp)

    var power = _nr_pusch_power_dbm_workload()
    checksum = _mix(checksum, _float_token(power))
    keep(power)

    var reference_power = _nr_reference_signal_received_power_workload(
        reference
    )
    checksum = _mix(checksum, _float_token(reference_power))
    keep(reference_power)

    var direct_ss_rsrp = _nr_ss_rsrp_workload(reference)
    checksum = _mix(checksum, _float_token(direct_ss_rsrp))
    keep(direct_ss_rsrp)

    var direct_csi_rsrp = _nr_csi_rsrp_workload(reference)
    checksum = _mix(checksum, _float_token(direct_csi_rsrp))
    keep(direct_csi_rsrp)

    var direct_rssi = _nr_rssi_workload(bandwidth)
    checksum = _mix(checksum, _float_token(direct_rssi))
    keep(direct_rssi)

    var ss_rsrq = _nr_ss_rsrq_workload(ss_rsrp, rssi)
    checksum = _mix(checksum, _float_token(ss_rsrq))
    keep(ss_rsrq)

    var csi_rsrq = _nr_csi_rsrq_workload(csi_rsrp, rssi)
    checksum = _mix(checksum, _float_token(csi_rsrq))
    keep(csi_rsrq)

    var ss_sinr = _nr_ss_sinr_workload(ss_rsrp)
    checksum = _mix(checksum, _float_token(ss_sinr))
    keep(ss_sinr)

    var csi_sinr = _nr_csi_sinr_workload(csi_rsrp)
    checksum = _mix(checksum, _float_token(csi_sinr))
    keep(csi_sinr)

    var ss_measurements = _nr_ss_linear_measurements_workload(
        reference, bandwidth, interference
    )
    checksum = _mix_u64(
        checksum, _measurement_fingerprint(ss_measurements)
    )
    keep(ss_measurements)

    var csi_measurements = _nr_csi_linear_measurements_workload(
        reference, bandwidth, interference
    )
    checksum = _mix_u64(
        checksum, _measurement_fingerprint(csi_measurements)
    )
    keep(csi_measurements)
    return checksum


def main() raises:
    # Construct every owned input and every borrowed input view once, before
    # the fixed-input replay, warmup, and sampled timing phases.
    var payload = _payload()
    var payload_span = Span(payload)
    var masked = nr_dci_crc24c_attach_mask(payload_span, _RNTI)
    var masked_span = Span(masked)
    var scrambled_fixture = nr_pdcch_scramble(
        masked_span, _RNTI, _SCRAMBLING_ID
    )
    var scrambled_llrs = _hard_llrs(Span(scrambled_fixture))
    var scrambled_llrs_span = Span(scrambled_llrs)

    var validation_tx = nr_pdcch_encode(
        payload_span, _RNTI, _SCRAMBLING_ID, 1
    )
    var decode_llrs = _hard_llrs(Span(validation_tx.scrambled))
    var decode_llrs_span = Span(decode_llrs)
    var validation_rx = nr_pdcch_decode(
        decode_llrs_span, _PAYLOAD_BITS, _RNTI, _SCRAMBLING_ID, 1
    )
    if not validation_rx.crc_ok or validation_rx.payload != payload:
        raise Error("NR PDCCH benchmark fixture failed validation")

    var reference: List[Complex64] = [
        Complex64(1.0, 0.0), Complex64(0.0, 1.0)
    ]
    var interference: List[Complex64] = [
        Complex64(0.5, 0.0), Complex64(0.0, -0.5)
    ]
    var bandwidth: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(2.0, 0.0),
        Complex64(3.0, 0.0),
        Complex64(4.0, 0.0),
    ]
    var reference_span = Span(reference)
    var interference_span = Span(interference)
    var bandwidth_span = Span(bandwidth)
    var y = nr_uss_search_space_y(_RNTI, 1024)
    var ss_rsrp_fixture = nr_ss_rsrp(reference_span)
    var csi_rsrp_fixture = nr_csi_rsrp(reference_span)
    var rssi_fixture = nr_rssi(bandwidth_span, 2)

    var first_checksum = _fixed_input_checksum(
        payload_span,
        masked_span,
        scrambled_llrs_span,
        decode_llrs_span,
        reference_span,
        bandwidth_span,
        interference_span,
        y,
        ss_rsrp_fixture,
        csi_rsrp_fixture,
        rssi_fixture,
    )
    var second_checksum = _fixed_input_checksum(
        payload_span,
        masked_span,
        scrambled_llrs_span,
        decode_llrs_span,
        reference_span,
        bandwidth_span,
        interference_span,
        y,
        ss_rsrp_fixture,
        csi_rsrp_fixture,
        rssi_fixture,
    )
    _require_repeat(first_checksum, second_checksum)

    for _ in range(_WARMUPS):
        keep(_nr_dci_crc24c_workload(payload_span))
        keep(_nr_dci_rnti_mask_crc_workload(masked_span))
        keep(_nr_dci_crc24c_attach_mask_workload(payload_span))
        keep(_nr_dci_crc24c_check_masked_workload(masked_span))
        keep(_nr_pdcch_scrambling_c_init_workload())
        keep(_nr_pdcch_scramble_workload(masked_span))
        keep(_nr_pdcch_descramble_llrs_workload(scrambled_llrs_span))
        keep(_nr_pdcch_dmrs_c_init_workload())
        keep(_nr_pdcch_dmrs_workload())
        keep(_nr_pdcch_rate_matched_bit_count_workload())
        keep(_nr_pdcch_noninterleaved_regs_workload())
        keep(_nr_pdcch_noninterleaved_data_resource_elements_workload())
        keep(_nr_pdcch_dmrs_resource_elements_workload())
        keep(_nr_pdcch_encode_workload(payload_span))
        keep(_nr_pdcch_decode_workload(decode_llrs_span))
        keep(_nr_coreset_cce_count_workload())
        keep(_nr_uss_search_space_y_workload())
        keep(_nr_search_space_candidate_first_cces_workload(y))
        keep(_nr_search_space_candidate_cces_workload(y))
        keep(_nr_ra_rnti_workload())
        keep(_nr_timing_advance_absolute_tc_workload())
        keep(_nr_timing_advance_delta_tc_workload())
        keep(_nr_timing_advance_update_tc_workload())
        keep(_nr_pucch_resource_set_index_workload())
        keep(_nr_pucch_resource_index_workload())
        keep(_nr_pucch_resource_is_within_bwp_workload())
        keep(_nr_pusch_power_dbm_workload())
        keep(_nr_reference_signal_received_power_workload(reference_span))
        keep(_nr_ss_rsrp_workload(reference_span))
        keep(_nr_csi_rsrp_workload(reference_span))
        keep(_nr_rssi_workload(bandwidth_span))
        keep(_nr_ss_rsrq_workload(ss_rsrp_fixture, rssi_fixture))
        keep(_nr_csi_rsrq_workload(csi_rsrp_fixture, rssi_fixture))
        keep(_nr_ss_sinr_workload(ss_rsrp_fixture))
        keep(_nr_csi_sinr_workload(csi_rsrp_fixture))
        keep(_nr_ss_linear_measurements_workload(
            reference_span, bandwidth_span, interference_span
        ))
        keep(_nr_csi_linear_measurements_workload(
            reference_span, bandwidth_span, interference_span
        ))

    var dci_crc24c_samples = List[UInt64](capacity=_SAMPLES)
    var dci_rnti_mask_samples = List[UInt64](capacity=_SAMPLES)
    var dci_attach_samples = List[UInt64](capacity=_SAMPLES)
    var dci_check_samples = List[UInt64](capacity=_SAMPLES)
    var scrambling_init_samples = List[UInt64](capacity=_SAMPLES)
    var scramble_samples = List[UInt64](capacity=_SAMPLES)
    var descramble_samples = List[UInt64](capacity=_SAMPLES)
    var dmrs_init_samples = List[UInt64](capacity=_SAMPLES)
    var dmrs_samples = List[UInt64](capacity=_SAMPLES)
    var rate_matched_count_samples = List[UInt64](capacity=_SAMPLES)
    var regs_samples = List[UInt64](capacity=_SAMPLES)
    var data_res_samples = List[UInt64](capacity=_SAMPLES)
    var dmrs_res_samples = List[UInt64](capacity=_SAMPLES)
    var encode_samples = List[UInt64](capacity=_SAMPLES)
    var decode_samples = List[UInt64](capacity=_SAMPLES)
    var cce_count_samples = List[UInt64](capacity=_SAMPLES)
    var uss_y_samples = List[UInt64](capacity=_SAMPLES)
    var first_cces_samples = List[UInt64](capacity=_SAMPLES)
    var candidate_cces_samples = List[UInt64](capacity=_SAMPLES)
    var ra_rnti_samples = List[UInt64](capacity=_SAMPLES)
    var timing_absolute_samples = List[UInt64](capacity=_SAMPLES)
    var timing_delta_samples = List[UInt64](capacity=_SAMPLES)
    var timing_update_samples = List[UInt64](capacity=_SAMPLES)
    var resource_set_samples = List[UInt64](capacity=_SAMPLES)
    var resource_index_samples = List[UInt64](capacity=_SAMPLES)
    var within_bwp_samples = List[UInt64](capacity=_SAMPLES)
    var pusch_power_samples = List[UInt64](capacity=_SAMPLES)
    var reference_power_samples = List[UInt64](capacity=_SAMPLES)
    var ss_rsrp_samples = List[UInt64](capacity=_SAMPLES)
    var csi_rsrp_samples = List[UInt64](capacity=_SAMPLES)
    var rssi_samples = List[UInt64](capacity=_SAMPLES)
    var ss_rsrq_samples = List[UInt64](capacity=_SAMPLES)
    var csi_rsrq_samples = List[UInt64](capacity=_SAMPLES)
    var ss_sinr_samples = List[UInt64](capacity=_SAMPLES)
    var csi_sinr_samples = List[UInt64](capacity=_SAMPLES)
    var ss_measurement_samples = List[UInt64](capacity=_SAMPLES)
    var csi_measurement_samples = List[UInt64](capacity=_SAMPLES)
    var checksum = first_checksum

    for _ in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var crc = _nr_dci_crc24c_workload(payload_span)
        dci_crc24c_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(checksum, crc)
        keep(crc)

        start = global_perf_counter_ns()
        var unmasked = _nr_dci_rnti_mask_crc_workload(masked_span)
        dci_rnti_mask_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _u8_list_fingerprint(Span(unmasked))
        )
        keep(unmasked)

        start = global_perf_counter_ns()
        var attached = _nr_dci_crc24c_attach_mask_workload(payload_span)
        dci_attach_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _u8_list_fingerprint(Span(attached))
        )
        keep(attached)

        start = global_perf_counter_ns()
        var crc_ok = _nr_dci_crc24c_check_masked_workload(masked_span)
        dci_check_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(crc_ok))
        keep(crc_ok)

        start = global_perf_counter_ns()
        var scrambling_init = _nr_pdcch_scrambling_c_init_workload()
        scrambling_init_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(checksum, UInt64(scrambling_init))
        keep(scrambling_init)

        start = global_perf_counter_ns()
        var scrambled = _nr_pdcch_scramble_workload(masked_span)
        scramble_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _u8_list_fingerprint(Span(scrambled))
        )
        keep(scrambled)

        start = global_perf_counter_ns()
        var descrambled = _nr_pdcch_descramble_llrs_workload(
            scrambled_llrs_span
        )
        descramble_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _float_list_fingerprint(Span(descrambled))
        )
        keep(descrambled)

        start = global_perf_counter_ns()
        var dmrs_init = _nr_pdcch_dmrs_c_init_workload()
        dmrs_init_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(checksum, UInt64(dmrs_init))
        keep(dmrs_init)

        start = global_perf_counter_ns()
        var dmrs = _nr_pdcch_dmrs_workload()
        dmrs_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _complex_list_fingerprint(Span(dmrs))
        )
        keep(dmrs)

        start = global_perf_counter_ns()
        var matched_count = _nr_pdcch_rate_matched_bit_count_workload()
        rate_matched_count_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, matched_count)
        keep(matched_count)

        start = global_perf_counter_ns()
        var regs = _nr_pdcch_noninterleaved_regs_workload()
        regs_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(checksum, _reg_list_fingerprint(Span(regs)))
        keep(regs)

        start = global_perf_counter_ns()
        var data_res = _nr_pdcch_noninterleaved_data_resource_elements_workload()
        data_res_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _resource_element_list_fingerprint(Span(data_res))
        )
        keep(data_res)

        start = global_perf_counter_ns()
        var dmrs_res = _nr_pdcch_dmrs_resource_elements_workload()
        dmrs_res_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _resource_element_list_fingerprint(Span(dmrs_res))
        )
        keep(dmrs_res)

        start = global_perf_counter_ns()
        var encoded = _nr_pdcch_encode_workload(payload_span)
        encode_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum,
            _tx_fingerprint(
                Span(encoded.payload),
                Span(encoded.scrambled),
                Span(encoded.qpsk_symbols),
            ),
        )
        keep(encoded)

        start = global_perf_counter_ns()
        var decoded = _nr_pdcch_decode_workload(decode_llrs_span)
        decode_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum,
            _decode_fingerprint(
                Span(decoded.payload),
                decoded.crc_ok,
                len(decoded.rate_recovered_llrs),
            ),
        )
        keep(decoded)

        start = global_perf_counter_ns()
        var cce_count = _nr_coreset_cce_count_workload()
        cce_count_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, cce_count)
        keep(cce_count)

        start = global_perf_counter_ns()
        var search_y = _nr_uss_search_space_y_workload()
        uss_y_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, search_y)
        keep(search_y)

        start = global_perf_counter_ns()
        var first_cces = _nr_search_space_candidate_first_cces_workload(y)
        first_cces_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _int_list_fingerprint(Span(first_cces))
        )
        keep(first_cces)

        start = global_perf_counter_ns()
        var candidate_cces = _nr_search_space_candidate_cces_workload(y)
        candidate_cces_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _int_list_fingerprint(Span(candidate_cces))
        )
        keep(candidate_cces)

        start = global_perf_counter_ns()
        var ra_rnti = _nr_ra_rnti_workload()
        ra_rnti_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, ra_rnti)
        keep(ra_rnti)

        start = global_perf_counter_ns()
        var absolute_timing = _nr_timing_advance_absolute_tc_workload()
        timing_absolute_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, absolute_timing)
        keep(absolute_timing)

        start = global_perf_counter_ns()
        var timing_delta = _nr_timing_advance_delta_tc_workload()
        timing_delta_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, timing_delta)
        keep(timing_delta)

        start = global_perf_counter_ns()
        var timing_update = _nr_timing_advance_update_tc_workload()
        timing_update_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, timing_update)
        keep(timing_update)

        start = global_perf_counter_ns()
        var resource_set = _nr_pucch_resource_set_index_workload()
        resource_set_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, resource_set)
        keep(resource_set)

        start = global_perf_counter_ns()
        var resource_index = _nr_pucch_resource_index_workload()
        resource_index_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, resource_index)
        keep(resource_index)

        start = global_perf_counter_ns()
        var within_bwp = _nr_pucch_resource_is_within_bwp_workload()
        within_bwp_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, Int(within_bwp))
        keep(within_bwp)

        start = global_perf_counter_ns()
        var power = _nr_pusch_power_dbm_workload()
        pusch_power_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, _float_token(power))
        keep(power)

        start = global_perf_counter_ns()
        var reference_power = _nr_reference_signal_received_power_workload(
            reference_span
        )
        reference_power_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, _float_token(reference_power))
        keep(reference_power)

        start = global_perf_counter_ns()
        var direct_ss_rsrp = _nr_ss_rsrp_workload(reference_span)
        ss_rsrp_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, _float_token(direct_ss_rsrp))
        keep(direct_ss_rsrp)

        start = global_perf_counter_ns()
        var direct_csi_rsrp = _nr_csi_rsrp_workload(reference_span)
        csi_rsrp_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, _float_token(direct_csi_rsrp))
        keep(direct_csi_rsrp)

        start = global_perf_counter_ns()
        var direct_rssi = _nr_rssi_workload(bandwidth_span)
        rssi_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, _float_token(direct_rssi))
        keep(direct_rssi)

        start = global_perf_counter_ns()
        var ss_rsrq = _nr_ss_rsrq_workload(
            ss_rsrp_fixture, rssi_fixture
        )
        ss_rsrq_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, _float_token(ss_rsrq))
        keep(ss_rsrq)

        start = global_perf_counter_ns()
        var csi_rsrq = _nr_csi_rsrq_workload(
            csi_rsrp_fixture, rssi_fixture
        )
        csi_rsrq_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, _float_token(csi_rsrq))
        keep(csi_rsrq)

        start = global_perf_counter_ns()
        var ss_sinr = _nr_ss_sinr_workload(ss_rsrp_fixture)
        ss_sinr_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, _float_token(ss_sinr))
        keep(ss_sinr)

        start = global_perf_counter_ns()
        var csi_sinr = _nr_csi_sinr_workload(csi_rsrp_fixture)
        csi_sinr_samples.append(global_perf_counter_ns() - start)
        checksum = _mix(checksum, _float_token(csi_sinr))
        keep(csi_sinr)

        start = global_perf_counter_ns()
        var ss_measurements = _nr_ss_linear_measurements_workload(
            reference_span, bandwidth_span, interference_span
        )
        ss_measurement_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _measurement_fingerprint(ss_measurements)
        )
        keep(ss_measurements)

        start = global_perf_counter_ns()
        var csi_measurements = _nr_csi_linear_measurements_workload(
            reference_span, bandwidth_span, interference_span
        )
        csi_measurement_samples.append(global_perf_counter_ns() - start)
        checksum = _mix_u64(
            checksum, _measurement_fingerprint(csi_measurements)
        )
        keep(csi_measurements)

    print_benchmark_metadata()
    print("nr_specification_scope: bounded-dci-pdcch-control-measurements")
    print("nr_specification_backend: scalar-cpu-reference")
    print("nr_specification_timing_scope: target-call-only")
    report_timing_samples("nr_dci_crc24c", dci_crc24c_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_dci_rnti_mask_crc", dci_rnti_mask_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_dci_crc24c_attach_mask", dci_attach_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_dci_crc24c_check_masked", dci_check_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_scrambling_c_init", scrambling_init_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_scramble", scramble_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_descramble_llrs", descramble_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_dmrs_c_init", dmrs_init_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_dmrs", dmrs_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_rate_matched_bit_count", rate_matched_count_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_noninterleaved_regs", regs_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_noninterleaved_data_resource_elements", data_res_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_dmrs_resource_elements", dmrs_res_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_encode", encode_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pdcch_decode", decode_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_coreset_cce_count", cce_count_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_uss_search_space_y", uss_y_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_search_space_candidate_first_cces", first_cces_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_search_space_candidate_cces", candidate_cces_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_ra_rnti", ra_rnti_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_timing_advance_absolute_tc", timing_absolute_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_timing_advance_delta_tc", timing_delta_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_timing_advance_update_tc", timing_update_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pucch_resource_set_index", resource_set_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pucch_resource_index", resource_index_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pucch_resource_is_within_bwp", within_bwp_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_pusch_power_dbm", pusch_power_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_reference_signal_received_power", reference_power_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_ss_rsrp", ss_rsrp_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_csi_rsrp", csi_rsrp_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_rssi", rssi_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_ss_rsrq", ss_rsrq_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_csi_rsrq", csi_rsrq_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_ss_sinr", ss_sinr_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_csi_sinr", csi_sinr_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_ss_linear_measurements", ss_measurement_samples, _WARMUPS, 1, "call")
    report_timing_samples("nr_csi_linear_measurements", csi_measurement_samples, _WARMUPS, 1, "call")
    keep(validation_tx)
    keep(validation_rx)
    keep(checksum)
    print("nr_specification_checksum:", checksum)
