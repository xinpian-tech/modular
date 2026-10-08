"""CPU timings for the bounded Rel-17 RedCap FR1 20-MHz chains."""

from std.benchmark import keep
from std.collections import Span
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.testing.checkpoint import CheckpointMetadata
from wireless_dsp.wireless.nr.grid import NRResourceGrid
from wireless_dsp.wireless.nr.redcap_chain import (
    NRRedCapRel17FR120MHzChainConfig,
    NRRedCapRel17FR120MHzDownlinkResult,
    NRRedCapRel17FR120MHzUplinkResult,
    nr_redcap_rel17_fr1_20mhz_downlink,
    nr_redcap_rel17_fr1_20mhz_uplink,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _OPERATIONS_PER_SAMPLE = 1


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 1)) * UInt64(1099511628211)


def _consume_bits(bits: Span[UInt8, ...], checksum: UInt64) -> UInt64:
    var result = _mix(checksum, len(bits))
    for index in range(len(bits)):
        result = _mix(result, Int(bits[index]) + 3 * index)
    return result


def _consume_ints(values: Span[Int, ...], checksum: UInt64) -> UInt64:
    var result = _mix(checksum, len(values))
    for index in range(len(values)):
        result = _mix(result, values[index] + 3 * index)
    return result


def _consume_floats(
    values: Span[Float64, ...], checksum: UInt64
) -> UInt64:
    var result = _mix(checksum, len(values))
    for index in range(len(values)):
        var classification = 0
        if values[index] < 0.0:
            classification = 1
        elif values[index] > 0.0:
            classification = 2
        result = _mix(result, classification + 3 * index)
    return result


def _consume_complex(
    values: Span[Complex64, ...], checksum: UInt64
) -> UInt64:
    var result = _mix(checksum, len(values))
    for index in range(len(values)):
        var quadrant = 0
        if values[index].re < 0.0:
            quadrant += 1
        elif values[index].re > 0.0:
            quadrant += 2
        if values[index].im < 0.0:
            quadrant += 4
        elif values[index].im > 0.0:
            quadrant += 8
        result = _mix(result, quadrant + 17 * index)
    return result


def _consume_grid(grid: NRResourceGrid, checksum: UInt64) raises -> UInt64:
    var result = _mix(checksum, grid.symbol_count)
    result = _mix(result, grid.subcarrier_count)
    for symbol in range(grid.symbol_count):
        for subcarrier in range(grid.subcarrier_count):
            var value = grid[symbol, subcarrier]
            var classification = 0
            if value.re < 0.0:
                classification += 1
            elif value.re > 0.0:
                classification += 2
            if value.im < 0.0:
                classification += 4
            elif value.im > 0.0:
                classification += 8
            result = _mix(
                result,
                classification + 17 * (symbol * grid.subcarrier_count + subcarrier),
            )
    return result


def _consume_metadata(
    metadata: List[CheckpointMetadata], checksum: UInt64
) -> UInt64:
    var result = _mix(checksum, len(metadata))
    for index in range(len(metadata)):
        result = _mix(result, metadata[index].testcase_id.byte_length())
        result = _mix(result, metadata[index].stage.byte_length())
        result = _mix(result, metadata[index].dtype.byte_length())
        result = _mix(result, metadata[index].shape.byte_length())
        result = _mix(result, metadata[index].stride.byte_length())
        result = _mix(result, metadata[index].q_format.byte_length())
        result = _mix(result, metadata[index].layout.byte_length())
        result = _mix(result, metadata[index].version + index)
    return result


def _consume_downlink(
    result: NRRedCapRel17FR120MHzDownlinkResult
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    checksum = _mix(checksum, result.capabilities.rx_branches)
    checksum = _mix(checksum, result.initial_access.dl_bwp.resource_blocks)
    checksum = _consume_ints(Span(result.ra_first_cces), checksum)
    checksum = _consume_complex(Span(result.pss_samples), checksum)
    checksum = _mix(checksum, result.pss_detection.offset)
    checksum = _mix(checksum, result.pss_detection.n_id_2)
    checksum = _consume_complex(Span(result.sss_samples), checksum)
    checksum = _mix(checksum, result.sss_detection.physical_cell_id)
    checksum = _consume_bits(Span(result.mib_bits), checksum)

    checksum = _consume_bits(Span(result.pbch_transmit.payload), checksum)
    checksum = _consume_bits(Span(result.pbch_transmit.interleaved_payload), checksum)
    checksum = _consume_bits(Span(result.pbch_transmit.payload_scrambled), checksum)
    checksum = _consume_bits(Span(result.pbch_transmit.crc_attached), checksum)
    checksum = _consume_bits(Span(result.pbch_transmit.polar_codeword), checksum)
    checksum = _consume_bits(Span(result.pbch_transmit.rate_matched), checksum)
    checksum = _consume_bits(Span(result.pbch_transmit.physical_channel_bits), checksum)
    checksum = _consume_metadata(result.pbch_transmit.checkpoint_metadata, checksum)
    checksum = _consume_floats(Span(result.pbch_llrs), checksum)
    checksum = _consume_bits(Span(result.pbch_decode.mib_bits), checksum)
    checksum = _consume_bits(Span(result.pbch_decode.payload), checksum)
    checksum = _consume_bits(Span(result.pbch_decode.decoded_information), checksum)
    checksum = _consume_metadata(result.pbch_decode.checkpoint_metadata, checksum)

    checksum = _consume_bits(Span(result.dci_payload), checksum)
    checksum = _consume_bits(Span(result.pdcch_transmit.payload), checksum)
    checksum = _consume_bits(Span(result.pdcch_transmit.crc_attached_masked), checksum)
    checksum = _consume_bits(Span(result.pdcch_transmit.input_interleaved), checksum)
    checksum = _consume_bits(Span(result.pdcch_transmit.polar_codeword), checksum)
    checksum = _consume_bits(Span(result.pdcch_transmit.rate_matched), checksum)
    checksum = _consume_bits(Span(result.pdcch_transmit.scrambled), checksum)
    checksum = _consume_complex(Span(result.pdcch_transmit.qpsk_symbols), checksum)
    checksum = _consume_metadata(result.pdcch_transmit.checkpoint_metadata, checksum)
    checksum = _consume_floats(Span(result.pdcch_llrs), checksum)
    checksum = _consume_floats(Span(result.pdcch_decode.physical_descrambled_llrs), checksum)
    checksum = _consume_floats(Span(result.pdcch_decode.rate_recovered_llrs), checksum)
    checksum = _consume_bits(Span(result.pdcch_decode.decoded_masked_information), checksum)
    checksum = _consume_bits(Span(result.pdcch_decode.crc_unmasked_information), checksum)
    checksum = _consume_bits(Span(result.pdcch_decode.payload), checksum)
    checksum = _consume_metadata(result.pdcch_decode.checkpoint_metadata, checksum)

    checksum = _consume_bits(Span(result.pdsch_payload), checksum)
    checksum = _consume_bits(Span(result.pdsch_transmit.transport_block), checksum)
    checksum = _consume_bits(Span(result.pdsch_transmit.encoded_null_mask), checksum)
    checksum = _consume_bits(Span(result.pdsch_transmit.rate_matched_bits), checksum)
    checksum = _consume_bits(Span(result.pdsch_transmit.scrambled_bits), checksum)
    checksum = _consume_complex(Span(result.pdsch_transmit.symbols), checksum)
    checksum = _consume_metadata(result.pdsch_transmit.checkpoint_metadata, checksum)
    checksum = _consume_grid(result.pdsch_grid, checksum)
    checksum = _consume_complex(Span(result.pdsch_waveform), checksum)
    checksum = _consume_complex(Span(result.pdsch_received_waveform), checksum)
    checksum = _consume_bits(Span(result.pdsch_decode.payload), checksum)
    checksum = _consume_bits(Span(result.pdsch_decode.transport_block), checksum)
    checksum = _consume_ints(Span(result.pdsch_decode.iterations), checksum)
    checksum = _consume_complex(Span(result.pdsch_decode.received_data), checksum)
    checksum = _consume_complex(Span(result.pdsch_decode.channel_estimate), checksum)
    checksum = _consume_complex(Span(result.pdsch_decode.equalized_symbols), checksum)
    checksum = _consume_floats(Span(result.pdsch_decode.demapper_llrs), checksum)
    checksum = _consume_floats(Span(result.pdsch_decode.descrambled_llrs), checksum)
    checksum = _consume_floats(Span(result.pdsch_decode.rate_recovered_llrs), checksum)
    checksum = _consume_metadata(result.pdsch_decode.checkpoint_metadata, checksum)
    checksum = _consume_metadata(result.checkpoint_metadata, checksum)
    return _mix(checksum, 1 if result.complete else 0)


def _consume_uplink(
    result: NRRedCapRel17FR120MHzUplinkResult
) raises -> UInt64:
    var checksum = UInt64(1469598103934665603)
    checksum = _mix(checksum, result.capabilities.ul_layers)
    checksum = _mix(checksum, result.initial_access.ul_bwp.resource_blocks)
    checksum = _consume_complex(Span(result.prach.root_sequence), checksum)
    checksum = _consume_complex(Span(result.prach.preamble_sequence), checksum)
    checksum = _consume_complex(Span(result.prach.frequency_sequence), checksum)
    checksum = _consume_complex(Span(result.prach.normalized_waveform), checksum)
    checksum = _consume_complex(Span(result.prach.detector_input), checksum)
    checksum = _mix(checksum, result.prach.detection.preamble_index)
    checksum = _consume_metadata(result.prach.checkpoint_metadata, checksum)

    checksum = _consume_bits(Span(result.pusch_payload), checksum)
    checksum = _consume_bits(Span(result.pusch_transmit.transport_block), checksum)
    checksum = _consume_bits(Span(result.pusch_transmit.encoded_null_mask), checksum)
    checksum = _consume_bits(Span(result.pusch_transmit.rate_matched_bits), checksum)
    checksum = _consume_bits(Span(result.pusch_transmit.scrambled_bits), checksum)
    checksum = _consume_complex(Span(result.pusch_transmit.modulated_symbols), checksum)
    checksum = _consume_complex(Span(result.pusch_transmit.mapped_data_symbols), checksum)
    checksum = _consume_complex(Span(result.pusch_transmit.dmrs), checksum)
    checksum = _consume_grid(result.pusch_transmit.grid, checksum)
    checksum = _consume_complex(Span(result.pusch_transmit.waveform), checksum)
    checksum = _consume_metadata(result.pusch_transmit.checkpoint_metadata, checksum)
    checksum = _consume_complex(Span(result.pusch_received_waveform), checksum)
    checksum = _consume_bits(Span(result.pusch_decode.payload), checksum)
    checksum = _consume_bits(Span(result.pusch_decode.transport_block), checksum)
    checksum = _consume_grid(result.pusch_decode.received_grid, checksum)
    checksum = _consume_complex(Span(result.pusch_decode.channel_estimate), checksum)
    checksum = _consume_complex(Span(result.pusch_decode.equalized_symbols), checksum)
    checksum = _consume_floats(Span(result.pusch_decode.demapper_llrs), checksum)
    checksum = _consume_floats(Span(result.pusch_decode.descrambled_llrs), checksum)
    checksum = _consume_floats(Span(result.pusch_decode.rate_recovered_llrs), checksum)
    checksum = _consume_ints(Span(result.pusch_decode.iterations), checksum)
    checksum = _consume_metadata(result.pusch_decode.checkpoint_metadata, checksum)

    checksum = _consume_bits(Span(result.uci_payload), checksum)
    checksum = _consume_bits(Span(result.pucch_transmit.payload), checksum)
    checksum = _consume_bits(Span(result.pucch_transmit.coded_bits), checksum)
    checksum = _consume_bits(Span(result.pucch_transmit.scrambled_bits), checksum)
    checksum = _consume_complex(Span(result.pucch_transmit.data_symbols), checksum)
    checksum = _consume_complex(Span(result.pucch_transmit.dmrs), checksum)
    checksum = _consume_grid(result.pucch_transmit.grid, checksum)
    checksum = _consume_complex(Span(result.pucch_transmit.waveform), checksum)
    checksum = _consume_metadata(result.pucch_transmit.checkpoint_metadata, checksum)
    checksum = _consume_complex(Span(result.pucch_received_waveform), checksum)
    checksum = _consume_bits(Span(result.pucch_decode.payload), checksum)
    checksum = _consume_grid(result.pucch_decode.grid, checksum)
    checksum = _consume_complex(Span(result.pucch_decode.received_dmrs), checksum)
    checksum = _consume_complex(Span(result.pucch_decode.dmrs_ls_estimates), checksum)
    checksum = _consume_complex(Span(result.pucch_decode.equalized_symbols), checksum)
    checksum = _consume_floats(Span(result.pucch_decode.raw_llrs), checksum)
    checksum = _consume_floats(Span(result.pucch_decode.descrambled_llrs), checksum)
    checksum = _consume_bits(Span(result.pucch_decode.hard_coded_bits), checksum)
    checksum = _consume_metadata(result.pucch_decode.checkpoint_metadata, checksum)
    checksum = _consume_metadata(result.checkpoint_metadata, checksum)
    return _mix(checksum, 1 if result.complete else 0)


def _sample_config(salt: Int) raises -> NRRedCapRel17FR120MHzChainConfig:
    return NRRedCapRel17FR120MHzChainConfig(
        salt % 1008,
        (17 * salt + 31) % 1024,
        salt & 1,
        salt % 8,
        1 + (29 * salt) % 65535,
        salt % 64,
    )


@no_inline
def _nr_redcap_rel17_fr1_20mhz_downlink_workload(
    config: NRRedCapRel17FR120MHzChainConfig,
) raises -> NRRedCapRel17FR120MHzDownlinkResult:
    return nr_redcap_rel17_fr1_20mhz_downlink(
        config, testcase_id="redcap-dl-benchmark"
    )


@no_inline
def _nr_redcap_rel17_fr1_20mhz_uplink_workload(
    config: NRRedCapRel17FR120MHzChainConfig,
) raises -> NRRedCapRel17FR120MHzUplinkResult:
    return nr_redcap_rel17_fr1_20mhz_uplink(
        config, testcase_id="redcap-ul-benchmark"
    )


def _downlink_fingerprint(
    result: NRRedCapRel17FR120MHzDownlinkResult,
) -> UInt64:
    return UInt64(
        result.capabilities.rx_branches
        + result.initial_access.dl_bwp.resource_blocks
        + len(result.ra_first_cces)
        + len(result.pss_samples)
        + len(result.pdsch_waveform)
        + len(result.checkpoint_metadata)
        + (1 if result.complete else 0)
    )


def _uplink_fingerprint(
    result: NRRedCapRel17FR120MHzUplinkResult,
) -> UInt64:
    return UInt64(
        result.capabilities.ul_layers
        + result.initial_access.ul_bwp.resource_blocks
        + len(result.prach.normalized_waveform)
        + len(result.pusch_transmit.waveform)
        + len(result.pucch_transmit.waveform)
        + len(result.checkpoint_metadata)
        + (1 if result.complete else 0)
    )


def main() raises:
    var config = _sample_config(324508639)
    for _ in range(_WARMUPS):
        keep(_nr_redcap_rel17_fr1_20mhz_downlink_workload(config))
        keep(_nr_redcap_rel17_fr1_20mhz_uplink_workload(config))

    var downlink_samples = List[UInt64](capacity=_SAMPLES)
    var uplink_samples = List[UInt64](capacity=_SAMPLES)
    var retained_checksum = UInt64(1469598103934665603)
    for sample in range(_SAMPLES):
        var start = global_perf_counter_ns()
        var downlink = _nr_redcap_rel17_fr1_20mhz_downlink_workload(
            config
        )
        downlink_samples.append(global_perf_counter_ns() - start)
        keep(downlink)
        # Consume every observable field after the timer boundary.  The
        # constant-time fingerprint remains useful as an inexpensive shape
        # guard, but is not sufficient on its own to retain the full result.
        var downlink_checksum = _consume_downlink(downlink)
        downlink_checksum ^= _downlink_fingerprint(downlink)
        downlink_checksum ^= UInt64(sample)
        retained_checksum ^= downlink_checksum
        retained_checksum *= UInt64(1099511628211)
        keep(downlink_checksum)

        start = global_perf_counter_ns()
        var uplink = _nr_redcap_rel17_fr1_20mhz_uplink_workload(config)
        uplink_samples.append(global_perf_counter_ns() - start)
        keep(uplink)
        var uplink_checksum = _consume_uplink(uplink)
        uplink_checksum ^= _uplink_fingerprint(uplink)
        uplink_checksum ^= UInt64(sample)
        retained_checksum ^= uplink_checksum
        retained_checksum *= UInt64(1099511628211)
        keep(uplink_checksum)

    print_benchmark_metadata()
    var alignment_probe = List[Complex64](
        length=64, fill=Complex64(0.0, 0.0)
    )
    print_runtime_buffer_alignment(
        "nr_redcap_chain_complex64_probe",
        Int(alignment_probe.unsafe_ptr()),
        align_of[Complex64](),
    )
    print("nr_redcap_chain_backend: scalar-cpu-reference")
    print("nr_redcap_chain_declared_profile: rel17-fr1-20mhz-30khz-51prb-siso-ul1")
    print("nr_redcap_prach_boundary: normalized-sequence-sample-not-radio-rate")
    report_timing_samples(
        "nr_redcap_rel17_fr1_20mhz_downlink_chain",
        downlink_samples,
        _WARMUPS,
        _OPERATIONS_PER_SAMPLE,
        "complete_bounded_chain",
    )
    report_timing_samples(
        "nr_redcap_rel17_fr1_20mhz_uplink_chain",
        uplink_samples,
        _WARMUPS,
        _OPERATIONS_PER_SAMPLE,
        "complete_bounded_chain",
    )
    keep(retained_checksum)
    print("nr_redcap_chain_retained_checksum:", retained_checksum)
