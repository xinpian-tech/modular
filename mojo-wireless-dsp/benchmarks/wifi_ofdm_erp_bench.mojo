"""Attributable CPU timings for bounded Clause-17/18 OFDM APIs.

Each public algorithm is a separate family.  Three warmups are outside the
timer and nine odd samples feed median/p95 reporting.  A fixed salt varies
valid RATE, clause, LENGTH, protection, payload, and fixture choices.  Only
the target API call is timed; complete owned results are kept and consumed
after the timer, while a separate O(1) fingerprint detects endpoint drift.
"""

from std.benchmark import black_box, keep
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
from wireless_dsp.wireless.wifi.ofdm_erp import (
    WIFI_OFDM_CLAUSE_17,
    WIFI_ERP_OFDM_CLAUSE_18,
    WifiOFDMERPConfig,
    WifiOFDMERPTx20MHz,
    WifiOFDMERPRx20MHz,
    wifi_ofdm_erp_rate_profile,
    wifi_ofdm_erp_geometry,
    wifi_ofdm_erp_lsig_bits,
    wifi_erp_protection_decision,
    wifi_ofdm_erp_tx_20mhz,
    wifi_ofdm_erp_rx_20mhz,
)


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _SCALAR_BATCH = 2048
comptime _TX_BATCH = 2
comptime _RX_BATCH = 1


@fieldwise_init
struct _WorkloadMeasurement(Copyable, Movable):
    var elapsed_ns: UInt64
    var full_output_checksum: UInt64
    var fingerprint_checksum: UInt64


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 1)) * UInt64(1099511628211)


def _consume_bits(bits: Span[UInt8, ...], checksum: UInt64) -> UInt64:
    var result = _mix(checksum, len(bits))
    for index in range(len(bits)):
        result = _mix(result, Int(bits[index]) + 3 * index)
    return result


def _consume_floats(values: Span[Float64, ...], checksum: UInt64) -> UInt64:
    var result = _mix(checksum, len(values))
    for index in range(len(values)):
        var classification = 0
        if values[index] < 0.0:
            classification = 1
        elif values[index] > 0.0:
            classification = 2
        result = _mix(result, classification + 5 * index)
    return result


def _consume_complex(values: Span[Complex64, ...], checksum: UInt64) -> UInt64:
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


def _consume_tx(result: WifiOFDMERPTx20MHz) -> UInt64:
    var checksum = UInt64(1469598103934665603)
    checksum = _mix(checksum, result.profile.clause)
    checksum = _mix(checksum, result.profile.rate_mbps)
    checksum = _mix(checksum, result.profile.rate_code_lsb_first)
    checksum = _mix(checksum, result.profile.bits_per_subcarrier)
    checksum = _mix(checksum, result.profile.code_rate_numerator)
    checksum = _mix(checksum, result.profile.code_rate_denominator)
    checksum = _mix(checksum, result.profile.coded_bits_per_symbol)
    checksum = _mix(checksum, result.profile.data_bits_per_symbol)
    checksum = _mix(checksum, result.geometry.psdu_length_octets)
    checksum = _mix(checksum, result.geometry.data_bits_before_pad)
    checksum = _mix(checksum, result.geometry.pad_bits)
    checksum = _mix(checksum, result.geometry.data_symbols)
    checksum = _mix(checksum, result.geometry.ppdu_samples)
    checksum = _mix(checksum, result.geometry.medium_occupancy_samples)
    checksum = _mix(checksum, Int(result.scrambler_seed))
    checksum = _mix(checksum, Int(result.fcs & UInt64(0x7FFFFFFF)))
    checksum = _consume_bits(Span(result.lsig_bits), checksum)
    checksum = _consume_bits(Span(result.lsig_coded_bits), checksum)
    checksum = _consume_bits(Span(result.lsig_interleaved_bits), checksum)
    checksum = _consume_complex(Span(result.lsig_symbols), checksum)
    checksum = _consume_complex(Span(result.lsig_spectrum), checksum)
    checksum = _consume_complex(Span(result.lsig_waveform), checksum)
    checksum = _consume_bits(Span(result.data_field_bits), checksum)
    checksum = _consume_bits(Span(result.scrambled_bits), checksum)
    checksum = _consume_bits(Span(result.mother_bits), checksum)
    checksum = _consume_bits(Span(result.punctured_bits), checksum)
    checksum = _consume_bits(Span(result.interleaved_bits), checksum)
    checksum = _consume_complex(Span(result.qam_symbols), checksum)
    checksum = _consume_complex(Span(result.data_spectra), checksum)
    checksum = _consume_complex(Span(result.data_waveform), checksum)
    checksum = _consume_complex(Span(result.stf_waveform), checksum)
    checksum = _consume_complex(Span(result.ltf_waveform), checksum)
    checksum = _consume_complex(Span(result.ppdu_waveform), checksum)
    return _consume_metadata(result.checkpoint_metadata, checksum)


def _consume_rx(result: WifiOFDMERPRx20MHz) -> UInt64:
    var checksum = UInt64(1469598103934665603)
    checksum = _mix(checksum, result.profile.clause)
    checksum = _mix(checksum, result.profile.rate_mbps)
    checksum = _mix(checksum, result.geometry.data_symbols)
    checksum = _mix(checksum, result.geometry.ppdu_samples)
    checksum = _mix(checksum, result.geometry.signal_extension_samples)
    checksum = _mix(checksum, Int(result.scrambler_seed))
    checksum = _consume_complex(Span(result.channel_estimate), checksum)
    checksum = _consume_complex(Span(result.lsig_equalized_symbols), checksum)
    checksum = _consume_bits(Span(result.lsig_demapped_bits), checksum)
    checksum = _consume_bits(Span(result.lsig_deinterleaved_bits), checksum)
    checksum = _consume_bits(Span(result.lsig_decoded_bits), checksum)
    checksum = _consume_complex(Span(result.equalized_data_symbols), checksum)
    checksum = _consume_bits(Span(result.demapped_bits), checksum)
    checksum = _consume_bits(Span(result.deinterleaved_bits), checksum)
    checksum = _consume_floats(Span(result.depunctured_llrs), checksum)
    checksum = _consume_bits(Span(result.decoded_scrambled_bits), checksum)
    checksum = _consume_bits(Span(result.descrambled_bits), checksum)
    checksum = _consume_bits(Span(result.mpdu_bits_without_fcs), checksum)
    checksum = _mix(checksum, Int(result.received_fcs & UInt64(0x7FFFFFFF)))
    checksum = _mix(checksum, Int(result.computed_fcs & UInt64(0x7FFFFFFF)))
    checksum = _mix(checksum, 1 if result.service_ok else 0)
    checksum = _mix(checksum, 1 if result.tail_ok else 0)
    checksum = _mix(checksum, 1 if result.fcs_ok else 0)
    return _consume_metadata(result.checkpoint_metadata, checksum)


def _rate(selector: Int) -> Int:
    var rates: List[Int] = [6, 9, 12, 18, 24, 36, 48, 54]
    return rates[selector & 7]


def _clause(selector: Int) -> Int:
    return (
        WIFI_ERP_OFDM_CLAUSE_18
        if (selector & 8) != 0
        else WIFI_OFDM_CLAUSE_17
    )


@no_inline
def _profile_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var config = WifiOFDMERPConfig(
            _clause(selector),
            _rate(selector),
            scrambler_seed=UInt8(1 + (selector % 127)),
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var profile = wifi_ofdm_erp_rate_profile(WifiOFDMERPConfig(
            black_box(config.clause),
            black_box(config.rate_mbps),
            scrambler_seed=config.scrambler_seed,
        ))
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, profile.rate_code_lsb_first)
        full_checksum = _mix(full_checksum, profile.bits_per_subcarrier)
        full_checksum = _mix(full_checksum, profile.code_rate_numerator)
        full_checksum = _mix(full_checksum, profile.code_rate_denominator)
        full_checksum = _mix(full_checksum, profile.coded_bits_per_symbol)
        full_checksum = _mix(full_checksum, profile.data_bits_per_symbol)
        full_checksum = _mix(
            full_checksum, profile.signal_extension_samples + iteration
        )
        fingerprint = _mix(
            fingerprint,
            profile.rate_code_lsb_first * 257
            + profile.data_bits_per_symbol
            + iteration,
        )
        keep(profile)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _geometry_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var config = WifiOFDMERPConfig(
            _clause(selector), _rate(selector)
        )
        var length = (selector * 37) & 4095
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var geometry = wifi_ofdm_erp_geometry(
            config,
            black_box(length),
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(full_checksum, geometry.psdu_length_octets)
        full_checksum = _mix(full_checksum, geometry.data_bits_before_pad)
        full_checksum = _mix(full_checksum, geometry.pad_bits)
        full_checksum = _mix(full_checksum, geometry.data_symbols)
        full_checksum = _mix(full_checksum, geometry.ppdu_samples)
        full_checksum = _mix(full_checksum, geometry.signal_extension_samples)
        full_checksum = _mix(
            full_checksum, geometry.medium_occupancy_samples + iteration
        )
        fingerprint = _mix(
            fingerprint,
            geometry.psdu_length_octets * 257
            + geometry.medium_occupancy_samples
            + iteration,
        )
        keep(geometry)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _lsig_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var config = WifiOFDMERPConfig(
            _clause(selector), _rate(selector)
        )
        var length = (selector * 53) & 4095
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var bits = wifi_ofdm_erp_lsig_bits(
            config,
            black_box(length),
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _consume_bits(Span(bits), full_checksum)
        fingerprint = _mix(
            fingerprint,
            len(bits) * 257 + Int(bits[0]) * 17 + Int(bits[len(bits) - 1]),
        )
        keep(bits)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _protection_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var non_erp = (selector & 1) != 0
        var use_protection = non_erp or (selector & 2) != 0
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var decision = wifi_erp_protection_decision(
            black_box(non_erp), black_box(use_protection)
        )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _mix(
            full_checksum, 1 if decision.non_erp_sta_associated else 0
        )
        full_checksum = _mix(
            full_checksum, 1 if decision.use_protection else 0
        )
        full_checksum = _mix(
            full_checksum,
            1 if decision.protect_erp_ofdm_exchange else 0,
        )
        full_checksum = _mix(
            full_checksum, decision.signal_extension_samples + iteration
        )
        fingerprint = _mix(
            fingerprint,
            (1 if decision.protect_erp_ofdm_exchange else 0) * 257
            + decision.signal_extension_samples
            + iteration,
        )
        keep(decision)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _tx_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var selector = iteration + salt
        var config = WifiOFDMERPConfig(
            _clause(selector),
            _rate(selector),
            scrambler_seed=UInt8(1 + (selector % 127)),
        )
        var result: WifiOFDMERPTx20MHz
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if (selector & 1) == 0:
            result = wifi_ofdm_erp_tx_20mhz(black_box(first), config)
        else:
            result = wifi_ofdm_erp_tx_20mhz(black_box(second), config)
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum ^= _consume_tx(result)
        fingerprint = _mix(
            fingerprint,
            len(result.ppdu_waveform) * 257
            + Int(result.lsig_bits[0]) * 17
            + Int(result.lsig_bits[len(result.lsig_bits) - 1])
            + iteration,
        )
        keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _rx_workload(
    iterations: Int,
    salt: Int,
    first: Span[Complex64, ...],
    second: Span[Complex64, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = UInt64(1469598103934665603)
    var fingerprint = UInt64(1469598103934665603)
    for iteration in range(iterations):
        var result: WifiOFDMERPRx20MHz
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        if ((iteration + salt) & 1) == 0:
            result = wifi_ofdm_erp_rx_20mhz(
                black_box(first), WIFI_OFDM_CLAUSE_17
            )
        else:
            result = wifi_ofdm_erp_rx_20mhz(
                black_box(second), WIFI_ERP_OFDM_CLAUSE_18
            )
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum ^= _consume_rx(result)
        fingerprint = _mix(
            fingerprint,
            len(result.mpdu_bits_without_fcs) * 257
            + Int(result.mpdu_bits_without_fcs[0]) * 17
            + Int(
                result.mpdu_bits_without_fcs[
                    len(result.mpdu_bits_without_fcs) - 1
                ]
            )
            + iteration,
        )
        keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


def _payload(octets: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * octets)
    for index in range(8 * octets):
        result.append(UInt8((17 * index + index // 3 + salt) & 1))
    return result^


def main() raises:
    var first = _payload(8, 1)
    var second = _payload(13, 7)
    var first_tx = wifi_ofdm_erp_tx_20mhz(
        Span(first),
        WifiOFDMERPConfig(
            WIFI_OFDM_CLAUSE_17, 24, scrambler_seed=UInt8(0x35)
        ),
    )
    var second_tx = wifi_ofdm_erp_tx_20mhz(
        Span(second),
        WifiOFDMERPConfig(
            WIFI_ERP_OFDM_CLAUSE_18, 36, scrambler_seed=UInt8(0x5D)
        ),
    )
    var first_waveform = first_tx.ppdu_waveform.copy()
    var second_waveform = second_tx.ppdu_waveform.copy()

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_profile_workload(_SCALAR_BATCH, salt, False))
        keep(_geometry_workload(_SCALAR_BATCH, salt, False))
        keep(_lsig_workload(_SCALAR_BATCH, salt, False))
        keep(_protection_workload(_SCALAR_BATCH, salt, False))
        keep(
            _tx_workload(
                _TX_BATCH, salt, Span(first), Span(second), False
            )
        )
        keep(_rx_workload(
            _RX_BATCH,
            salt,
            Span(first_waveform),
            Span(second_waveform),
            False,
        ))

    var profile_samples = List[UInt64](capacity=_SAMPLES)
    var geometry_samples = List[UInt64](capacity=_SAMPLES)
    var lsig_samples = List[UInt64](capacity=_SAMPLES)
    var protection_samples = List[UInt64](capacity=_SAMPLES)
    var tx_samples = List[UInt64](capacity=_SAMPLES)
    var rx_samples = List[UInt64](capacity=_SAMPLES)
    var full_output_checksum = UInt64(1469598103934665603)
    var fingerprint_checksum = UInt64(1469598103934665603)
    for _ in range(_SAMPLES):
        var salt = 324508639
        var value = _profile_workload(_SCALAR_BATCH, salt, True)
        profile_samples.append(value.elapsed_ns)
        full_output_checksum = _mix(
            full_output_checksum,
            Int(value.full_output_checksum & UInt64(Int.MAX)),
        )
        fingerprint_checksum = _mix(
            fingerprint_checksum,
            Int(value.fingerprint_checksum & UInt64(Int.MAX)),
        )
        keep(value)

        value = _geometry_workload(_SCALAR_BATCH, salt, True)
        geometry_samples.append(value.elapsed_ns)
        full_output_checksum = _mix(
            full_output_checksum,
            Int(value.full_output_checksum & UInt64(Int.MAX)),
        )
        fingerprint_checksum = _mix(
            fingerprint_checksum,
            Int(value.fingerprint_checksum & UInt64(Int.MAX)),
        )
        keep(value)

        value = _lsig_workload(_SCALAR_BATCH, salt, True)
        lsig_samples.append(value.elapsed_ns)
        full_output_checksum = _mix(
            full_output_checksum,
            Int(value.full_output_checksum & UInt64(Int.MAX)),
        )
        fingerprint_checksum = _mix(
            fingerprint_checksum,
            Int(value.fingerprint_checksum & UInt64(Int.MAX)),
        )
        keep(value)

        value = _protection_workload(_SCALAR_BATCH, salt, True)
        protection_samples.append(value.elapsed_ns)
        full_output_checksum = _mix(
            full_output_checksum,
            Int(value.full_output_checksum & UInt64(Int.MAX)),
        )
        fingerprint_checksum = _mix(
            fingerprint_checksum,
            Int(value.fingerprint_checksum & UInt64(Int.MAX)),
        )
        keep(value)

        value = _tx_workload(
            _TX_BATCH, salt, Span(first), Span(second), True
        )
        tx_samples.append(value.elapsed_ns)
        full_output_checksum = _mix(
            full_output_checksum,
            Int(value.full_output_checksum & UInt64(Int.MAX)),
        )
        fingerprint_checksum = _mix(
            fingerprint_checksum,
            Int(value.fingerprint_checksum & UInt64(Int.MAX)),
        )
        keep(value)

        value = _rx_workload(
            _RX_BATCH,
            salt,
            Span(first_waveform),
            Span(second_waveform),
            True,
        )
        rx_samples.append(value.elapsed_ns)
        full_output_checksum = _mix(
            full_output_checksum,
            Int(value.full_output_checksum & UInt64(Int.MAX)),
        )
        fingerprint_checksum = _mix(
            fingerprint_checksum,
            Int(value.fingerprint_checksum & UInt64(Int.MAX)),
        )
        keep(value)

    print_benchmark_metadata()
    print_runtime_buffer_alignment(
        "wifi_ofdm_erp_payload_bits",
        Int(first.unsafe_ptr()),
        align_of[UInt8](),
    )
    print("wifi_ofdm_erp_implementation: scalar-cpu-golden-reference")
    print("wifi_ofdm_erp_scope: 20mhz-siso-known-timing-clause17-18")
    print("wifi_ofdm_erp_input_variation: fixed-salted")
    print("wifi_ofdm_erp_timed_scope: target-api-only")
    print("wifi_ofdm_erp_post_timer_scope: keep-plus-full-output-checksum-plus-o1-fingerprint")
    report_timing_samples(
        "wifi_ofdm_erp_rate_profile",
        profile_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "profile_query",
    )
    report_timing_samples(
        "wifi_ofdm_erp_geometry",
        geometry_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "geometry_query",
    )
    report_timing_samples(
        "wifi_ofdm_erp_lsig_bits",
        lsig_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "lsig_field",
    )
    report_timing_samples(
        "wifi_erp_protection_decision",
        protection_samples,
        _WARMUPS,
        _SCALAR_BATCH,
        "decision",
    )
    report_timing_samples(
        "wifi_ofdm_erp_tx_20mhz",
        tx_samples,
        _WARMUPS,
        _TX_BATCH,
        "ppdu",
    )
    report_timing_samples(
        "wifi_ofdm_erp_rx_20mhz",
        rx_samples,
        _WARMUPS,
        _RX_BATCH,
        "ppdu",
    )
    keep(full_output_checksum)
    keep(fingerprint_checksum)
    print("wifi_ofdm_erp_full_output_checksum:", full_output_checksum)
    print("wifi_ofdm_erp_fingerprint_checksum:", fingerprint_checksum)
