"""Attributable CPU timings for bounded HE/EHT SIGNAL waveforms.

All ten public algorithms are reported independently.  Input fixtures are
prepared outside timed regions, three untimed warmups precede nine retained
samples, and each workload executes a batch of calls.  A fixed salt selects
valid configurations or independent prebuilt observations.  Only the target
API is timed; complete owned results are kept and fully consumed afterward,
with a separate O(1) endpoint fingerprint checksum.
"""

from std.benchmark import black_box, keep
from std.collections import Span
from std.math import abs
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    report_timing_samples,
)
from wireless_dsp.core import Complex64
from wireless_dsp.testing.checkpoint import CheckpointMetadata
from wireless_dsp.wireless.wifi.he_eht_sig_fields import (
    WIFI_HE_EHT_SIG_CODING_BCC,
    WIFI_HE_EHT_SIG_CODING_LDPC,
    WifiEhtUSigSU20Config,
    WifiEhtUSigSU20Fields,
    WifiHeSigASUConfig,
    WifiHeSigASUFields,
)
from wireless_dsp.wireless.wifi.he_eht_sig_waveform import (
    WIFI_EHT_ACQUISITION_SOUNDING_NDP,
    WIFI_EHT_ACQUISITION_SU_DATA,
    WifiEhtSigSU20Config,
    WifiEhtSigSU20Fields,
    WifiEhtSignalDrivenLDPCRx20MHz,
    WifiEhtSUSignalRx20MHz,
    WifiEhtSUSignalTx20MHz,
    WifiEhtUSigWaveformRx20MHz,
    WifiEhtUSigWaveformTx20MHz,
    WifiHeSigAWaveformRx20MHz,
    WifiHeSigAWaveformTx20MHz,
    WifiHeSignalDrivenLDPCRx20MHz,
    WifiSignalDataProfile,
    wifi_eht_sig_su_20_pack,
    wifi_eht_sig_su_20_parse,
    wifi_eht_signal_driven_ldpc_rx_20mhz,
    wifi_eht_su_signal_rx_20mhz,
    wifi_eht_su_signal_tx_20mhz,
    wifi_eht_u_sig_waveform_rx_20mhz,
    wifi_eht_u_sig_waveform_tx_20mhz,
    wifi_he_sig_a_waveform_rx_20mhz,
    wifi_he_sig_a_waveform_tx_20mhz,
    wifi_he_signal_driven_ldpc_rx_20mhz,
)
from wireless_dsp.wireless.wifi.phy_chain import (
    WifiLDPCRx20MHz,
    wifi_ldpc_tx_20mhz,
)
from wireless_dsp.wireless.wifi.preambles import wifi_ltf_waveform_20mhz
from wireless_dsp.wireless.wifi.profiles import WIFI_PHY_EHT, WIFI_PHY_HE


comptime _WARMUPS = 3
comptime _SAMPLES = 9
comptime _FIELD_BATCH = 128
comptime _WAVEFORM_BATCH = 4
comptime _COMBINED_BATCH = 2
comptime _DATA_BATCH = 2
comptime _OFFSET_BASIS = UInt64(1469598103934665603)
comptime _PRIME = UInt64(1099511628211)


@fieldwise_init
struct _WorkloadMeasurement(Copyable, Movable):
    var elapsed_ns: UInt64
    var full_output_checksum: UInt64
    var fingerprint_checksum: UInt64


def _mix(checksum: UInt64, value: Int) -> UInt64:
    return (checksum ^ UInt64(value + 1)) * _PRIME


def _merge(checksum: UInt64, value: UInt64) -> UInt64:
    return (checksum ^ value) * _PRIME


def _record_measurement(
    measurement: _WorkloadMeasurement,
    mut samples: List[UInt64],
    mut full_output_checksum: UInt64,
    mut fingerprint_checksum: UInt64,
):
    samples.append(measurement.elapsed_ns)
    full_output_checksum = _merge(
        full_output_checksum, measurement.full_output_checksum
    )
    fingerprint_checksum = _merge(
        fingerprint_checksum, measurement.fingerprint_checksum
    )
    keep(measurement)


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
        result = _merge(result, UInt64(abs(values[index]) * 1.0e6))
    return result


def _consume_complex(values: Span[Complex64, ...], checksum: UInt64) -> UInt64:
    var result = _mix(checksum, len(values))
    for index in range(len(values)):
        var value = values[index]
        var quadrant = 0
        if value.re < 0.0:
            quadrant += 1
        elif value.re > 0.0:
            quadrant += 2
        if value.im < 0.0:
            quadrant += 4
        elif value.im > 0.0:
            quadrant += 8
        result = _mix(result, quadrant + 17 * index)
        result = _merge(result, UInt64(value.magnitude_squared() * 1.0e9))
    return result


def _fingerprint_bits(bits: Span[UInt8, ...]) -> UInt64:
    return _mix(
        _mix(_OFFSET_BASIS, len(bits)),
        Int(bits[0]) * 17 + Int(bits[len(bits) - 1]) * 257,
    )


def _fingerprint_complex(values: Span[Complex64, ...]) -> UInt64:
    var code = len(values) * 257
    if values[0].re > 0.0:
        code += 1
    if values[0].im > 0.0:
        code += 2
    if values[len(values) - 1].re > 0.0:
        code += 4
    if values[len(values) - 1].im > 0.0:
        code += 8
    return _mix(_OFFSET_BASIS, code)


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
        result = _merge(result, UInt64(abs(metadata[index].scale) * 1.0e9))
    return result


def _consume_profile(
    profile: WifiSignalDataProfile, checksum: UInt64
) -> UInt64:
    var result = _mix(checksum, profile.family)
    result = _mix(result, profile.bandwidth_mhz)
    result = _mix(result, profile.mcs_index)
    result = _mix(result, profile.coding)
    result = _mix(result, profile.spatial_streams)
    result = _mix(result, 1 if profile.dcm else 0)
    result = _mix(result, profile.bits_per_subcarrier)
    result = _mix(result, profile.code_rate_numerator)
    result = _mix(result, profile.code_rate_denominator)
    return _mix(result, 1 if profile.ldpc_only else 0)


def _consume_he_fields(
    fields: WifiHeSigASUFields, checksum: UInt64
) -> UInt64:
    var result = _mix(checksum, 1 if fields.extended_range else 0)
    result = _mix(result, 1 if fields.beam_change else 0)
    result = _mix(result, 1 if fields.uplink else 0)
    result = _mix(result, fields.mcs_index)
    result = _mix(result, 1 if fields.dcm else 0)
    result = _mix(result, fields.bss_color)
    result = _mix(result, fields.spatial_reuse)
    result = _mix(result, fields.bandwidth_mhz)
    result = _mix(result, fields.gi_ltf_code)
    result = _mix(result, fields.space_time_streams)
    result = _mix(result, fields.txop_code)
    result = _mix(result, fields.coding)
    result = _mix(result, 1 if fields.ldpc_extra_symbol else 0)
    result = _mix(result, 1 if fields.stbc else 0)
    result = _mix(result, 1 if fields.beamformed else 0)
    result = _mix(result, fields.pre_fec_padding_factor)
    result = _mix(result, 1 if fields.pe_disambiguity else 0)
    return _mix(result, fields.crc)


def _consume_u_fields(
    fields: WifiEhtUSigSU20Fields, checksum: UInt64
) -> UInt64:
    var result = _mix(checksum, 1 if fields.uplink else 0)
    result = _mix(result, fields.bss_color)
    result = _mix(result, fields.txop_code)
    result = _mix(result, fields.eht_sig_mcs_code)
    result = _mix(result, fields.eht_sig_symbols)
    return _mix(result, fields.crc)


def _consume_eht_fields(
    fields: WifiEhtSigSU20Fields, checksum: UInt64
) -> UInt64:
    var result = _mix(checksum, fields.spatial_reuse)
    result = _mix(result, fields.gi_ltf_code)
    result = _mix(result, fields.eht_ltf_symbols)
    result = _mix(result, 1 if fields.ldpc_extra_symbol else 0)
    result = _mix(result, fields.pre_fec_padding_factor)
    result = _mix(result, 1 if fields.pe_disambiguity else 0)
    result = _mix(result, fields.sta_id)
    result = _mix(result, fields.mcs_index)
    result = _mix(result, fields.spatial_streams)
    result = _mix(result, 1 if fields.beamformed else 0)
    result = _mix(result, fields.coding)
    return _mix(result, fields.crc)


def _consume_he_tx(result: WifiHeSigAWaveformTx20MHz) -> UInt64:
    var checksum = _mix(_OFFSET_BASIS, 1 if result.extended_range else 0)
    checksum = _consume_bits(Span(result.bits), checksum)
    checksum = _consume_bits(Span(result.coded_bits), checksum)
    checksum = _consume_bits(Span(result.transmitted_bits), checksum)
    checksum = _consume_complex(Span(result.data_symbols), checksum)
    checksum = _consume_complex(Span(result.spectra), checksum)
    checksum = _consume_complex(Span(result.waveform), checksum)
    checksum = _consume_profile(result.data_profile, checksum)
    return _consume_metadata(result.checkpoint_metadata, checksum)


def _consume_he_rx(result: WifiHeSigAWaveformRx20MHz) -> UInt64:
    var checksum = _consume_he_fields(result.fields, _OFFSET_BASIS)
    checksum = _consume_profile(result.data_profile, checksum)
    checksum = _consume_complex(Span(result.spectra), checksum)
    checksum = _consume_complex(Span(result.channel_estimates), checksum)
    checksum = _consume_complex(Span(result.equalized_data_symbols), checksum)
    checksum = _consume_floats(Span(result.coded_llrs), checksum)
    checksum = _consume_bits(Span(result.hard_coded_bits), checksum)
    checksum = _consume_bits(Span(result.decoded_bits), checksum)
    checksum = _mix(checksum, result.repetition_disagreements)
    return _consume_metadata(result.checkpoint_metadata, checksum)


def _consume_u_tx(result: WifiEhtUSigWaveformTx20MHz) -> UInt64:
    var checksum = _consume_bits(Span(result.bits), _OFFSET_BASIS)
    checksum = _consume_bits(Span(result.coded_bits), checksum)
    checksum = _consume_bits(Span(result.transmitted_bits), checksum)
    checksum = _consume_complex(Span(result.data_symbols), checksum)
    checksum = _consume_complex(Span(result.spectra), checksum)
    checksum = _consume_complex(Span(result.waveform), checksum)
    return _consume_metadata(result.checkpoint_metadata, checksum)


def _consume_u_rx(result: WifiEhtUSigWaveformRx20MHz) -> UInt64:
    var checksum = _mix(_OFFSET_BASIS, result.acquisition_context)
    checksum = _consume_u_fields(result.fields, checksum)
    checksum = _consume_complex(Span(result.spectra), checksum)
    checksum = _consume_complex(Span(result.channel_estimates), checksum)
    checksum = _consume_complex(Span(result.equalized_data_symbols), checksum)
    checksum = _consume_floats(Span(result.coded_llrs), checksum)
    checksum = _consume_bits(Span(result.hard_coded_bits), checksum)
    checksum = _consume_bits(Span(result.decoded_bits), checksum)
    return _consume_metadata(result.checkpoint_metadata, checksum)


def _consume_eht_tx(result: WifiEhtSUSignalTx20MHz) -> UInt64:
    var checksum = _merge(_OFFSET_BASIS, _consume_u_tx(result.u_sig))
    checksum = _consume_bits(Span(result.eht_sig_bits), checksum)
    checksum = _consume_bits(Span(result.eht_sig_coded_bits), checksum)
    checksum = _consume_bits(Span(result.eht_sig_transmitted_bits), checksum)
    checksum = _consume_complex(Span(result.eht_sig_data_symbols), checksum)
    checksum = _consume_complex(Span(result.eht_sig_spectra), checksum)
    checksum = _consume_complex(Span(result.eht_sig_waveform), checksum)
    checksum = _consume_complex(Span(result.waveform), checksum)
    checksum = _consume_profile(result.data_profile, checksum)
    return _consume_metadata(result.checkpoint_metadata, checksum)


def _consume_eht_rx(result: WifiEhtSUSignalRx20MHz) -> UInt64:
    var checksum = _merge(_OFFSET_BASIS, _consume_u_rx(result.u_sig))
    checksum = _consume_eht_fields(result.eht_sig_fields, checksum)
    checksum = _consume_complex(Span(result.eht_sig_spectra), checksum)
    checksum = _consume_complex(
        Span(result.eht_sig_channel_estimates), checksum
    )
    checksum = _consume_complex(
        Span(result.eht_sig_equalized_data_symbols), checksum
    )
    checksum = _consume_floats(Span(result.eht_sig_coded_llrs), checksum)
    checksum = _consume_bits(Span(result.eht_sig_hard_coded_bits), checksum)
    checksum = _consume_bits(Span(result.eht_sig_decoded_bits), checksum)
    checksum = _consume_profile(result.data_profile, checksum)
    return _consume_metadata(result.checkpoint_metadata, checksum)


def _consume_ldpc_rx(result: WifiLDPCRx20MHz) -> UInt64:
    var checksum = _consume_bits(Span(result.payload_bits), _OFFSET_BASIS)
    checksum = _consume_complex(Span(result.corrected_data_symbols), checksum)
    checksum = _consume_floats(Span(result.physical_llrs), checksum)
    checksum = _consume_floats(Span(result.demapped_llrs), checksum)
    checksum = _consume_floats(Span(result.rate_recovered_llrs), checksum)
    checksum = _consume_bits(Span(result.decoded_frame_bits), checksum)
    checksum = _consume_complex(Span(result.channel_estimate), checksum)
    checksum = _consume_complex(Span(result.equalized_spectrum), checksum)
    checksum = _consume_metadata(result.checkpoint_metadata, checksum)
    checksum = _merge(checksum, UInt64(abs(result.common_phase) * 1.0e12))
    checksum = _merge(checksum, UInt64(abs(result.phase_slope) * 1.0e12))
    checksum = _merge(checksum, result.received_fcs)
    checksum = _merge(checksum, result.computed_fcs)
    checksum = _mix(checksum, result.ldpc_block_length)
    checksum = _mix(checksum, 1 if result.ldpc_converged else 0)
    checksum = _mix(checksum, 1 if result.service_ok else 0)
    return _mix(checksum, 1 if result.fcs_ok else 0)


def _consume_he_data(result: WifiHeSignalDrivenLDPCRx20MHz) -> UInt64:
    return _merge(_consume_he_rx(result.signal), _consume_ldpc_rx(result.data))


def _consume_eht_data(result: WifiEhtSignalDrivenLDPCRx20MHz) -> UInt64:
    return _merge(_consume_eht_rx(result.signal), _consume_ldpc_rx(result.data))


def _eht_coding(mcs_index: Int, selector: Int) -> Int:
    if mcs_index >= 10:
        return WIFI_HE_EHT_SIG_CODING_LDPC
    return (
        WIFI_HE_EHT_SIG_CODING_LDPC
        if (selector & 1) != 0
        else WIFI_HE_EHT_SIG_CODING_BCC
    )


@no_inline
def _eht_pack_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        var selector = iteration + salt
        var mcs_index = selector % 14
        var coding = _eht_coding(mcs_index, selector >> 4)
        var config = WifiEhtSigSU20Config(
            black_box(mcs_index),
            sta_id=black_box((selector * 29) % 2046),
            spatial_reuse=black_box(selector & 15),
            gi_ltf_code=black_box((selector >> 4) & 3),
            ldpc_extra_symbol=black_box(
                coding == WIFI_HE_EHT_SIG_CODING_LDPC
                and ((selector >> 6) & 1) != 0
            ),
            pre_fec_padding_factor=black_box((selector >> 7) & 3),
            pe_disambiguity=black_box(((selector >> 9) & 1) != 0),
            beamformed=black_box(((selector >> 10) & 1) != 0),
            coding=black_box(coding),
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var result = wifi_eht_sig_su_20_pack(config)
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _consume_bits(Span(result), full_checksum)
        fingerprint = _merge(
            fingerprint, _fingerprint_bits(Span(result))
        )
        keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _eht_parse_workload(
    iterations: Int,
    salt: Int,
    first: Span[UInt8, ...],
    second: Span[UInt8, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        if ((iteration + salt) & 1) == 0:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_eht_sig_su_20_parse(black_box(first))
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _consume_eht_fields(result, full_checksum)
            fingerprint = _mix(
                fingerprint,
                result.mcs_index * 257 + result.crc + iteration,
            )
            keep(result)
        else:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_eht_sig_su_20_parse(black_box(second))
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _consume_eht_fields(result, full_checksum)
            fingerprint = _mix(
                fingerprint,
                result.mcs_index * 257 + result.crc + iteration,
            )
            keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _he_tx_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        var selector = iteration + salt
        var extended = (selector & 1) != 0
        var mcs_index = selector % (3 if extended else 12)
        var coding = (
            WIFI_HE_EHT_SIG_CODING_LDPC
            if mcs_index >= 10 or ((selector >> 2) & 1) != 0
            else WIFI_HE_EHT_SIG_CODING_BCC
        )
        var config = WifiHeSigASUConfig(
            black_box(mcs_index),
            extended_range=black_box(extended),
            beam_change=black_box(((selector >> 3) & 1) != 0),
            uplink=black_box(((selector >> 4) & 1) != 0),
            bss_color=black_box((selector * 13) & 63),
            spatial_reuse=black_box((selector >> 5) & 15),
            gi_ltf_code=black_box((selector >> 7) & 3),
            txop_code=black_box((selector * 17) & 127),
            coding=black_box(coding),
            ldpc_extra_symbol=black_box(
                coding == WIFI_HE_EHT_SIG_CODING_LDPC
                and ((selector >> 9) & 1) != 0
            ),
            beamformed=black_box(((selector >> 10) & 1) != 0),
            pre_fec_padding_factor=black_box((selector >> 11) & 3),
            pe_disambiguity=black_box(((selector >> 13) & 1) != 0),
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var result = wifi_he_sig_a_waveform_tx_20mhz(config)
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _merge(full_checksum, _consume_he_tx(result))
        fingerprint = _merge(
            fingerprint, _fingerprint_complex(Span(result.waveform))
        )
        keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _he_rx_workload(
    iterations: Int,
    salt: Int,
    su: Span[Complex64, ...],
    er: Span[Complex64, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        if ((iteration + salt) & 1) == 0:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_he_sig_a_waveform_rx_20mhz(black_box(su))
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_he_rx(result)
            )
            fingerprint = _merge(
                fingerprint, _fingerprint_bits(Span(result.decoded_bits))
            )
            keep(result)
        else:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_he_sig_a_waveform_rx_20mhz(
                black_box(er), extended_range=True
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_he_rx(result)
            )
            fingerprint = _merge(
                fingerprint, _fingerprint_bits(Span(result.decoded_bits))
            )
            keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _u_tx_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        var selector = iteration + salt
        var config = WifiEhtUSigSU20Config(
            black_box((selector * 11) & 63),
            uplink=black_box((selector & 1) != 0),
            txop_code=black_box((selector * 19) & 127),
            eht_sig_mcs_code=0,
            eht_sig_symbols=2,
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var result = wifi_eht_u_sig_waveform_tx_20mhz(config)
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _merge(full_checksum, _consume_u_tx(result))
        fingerprint = _merge(
            fingerprint, _fingerprint_complex(Span(result.waveform))
        )
        keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _u_rx_workload(
    iterations: Int,
    salt: Int,
    first: Span[Complex64, ...],
    second: Span[Complex64, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        if ((iteration + salt) & 1) == 0:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_eht_u_sig_waveform_rx_20mhz(
                black_box(first), WIFI_EHT_ACQUISITION_SU_DATA
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_u_rx(result)
            )
            fingerprint = _merge(
                fingerprint, _fingerprint_bits(Span(result.decoded_bits))
            )
            keep(result)
        else:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_eht_u_sig_waveform_rx_20mhz(
                black_box(second), WIFI_EHT_ACQUISITION_SOUNDING_NDP
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_u_rx(result)
            )
            fingerprint = _merge(
                fingerprint, _fingerprint_bits(Span(result.decoded_bits))
            )
            keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _eht_tx_workload(
    iterations: Int, salt: Int, measure: Bool
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        var selector = iteration + salt
        var mcs_index = selector % 14
        var coding = _eht_coding(mcs_index, selector >> 3)
        var u_config = WifiEhtUSigSU20Config(
            black_box((selector * 7) & 63),
            uplink=black_box((selector & 1) != 0),
            txop_code=black_box((selector * 23) & 127),
            eht_sig_mcs_code=0,
            eht_sig_symbols=2,
        )
        var eht_config = WifiEhtSigSU20Config(
            black_box(mcs_index),
            sta_id=black_box((selector * 31) % 2046),
            spatial_reuse=black_box((selector >> 4) & 15),
            gi_ltf_code=black_box((selector >> 8) & 3),
            ldpc_extra_symbol=black_box(
                coding == WIFI_HE_EHT_SIG_CODING_LDPC
                and ((selector >> 10) & 1) != 0
            ),
            pre_fec_padding_factor=black_box((selector >> 11) & 3),
            pe_disambiguity=black_box(((selector >> 13) & 1) != 0),
            beamformed=black_box(((selector >> 14) & 1) != 0),
            coding=black_box(coding),
        )
        var start = UInt64(0)
        if measure:
            start = global_perf_counter_ns()
        var result = wifi_eht_su_signal_tx_20mhz(u_config, eht_config)
        if measure:
            elapsed += global_perf_counter_ns() - start
        full_checksum = _merge(full_checksum, _consume_eht_tx(result))
        fingerprint = _merge(
            fingerprint, _fingerprint_complex(Span(result.waveform))
        )
        keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _eht_rx_workload(
    iterations: Int,
    salt: Int,
    first: Span[Complex64, ...],
    second: Span[Complex64, ...],
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        if ((iteration + salt) & 1) == 0:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_eht_su_signal_rx_20mhz(
                black_box(first), WIFI_EHT_ACQUISITION_SU_DATA
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_eht_rx(result)
            )
            fingerprint = _merge(
                fingerprint,
                _fingerprint_bits(Span(result.eht_sig_decoded_bits)),
            )
            keep(result)
        else:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_eht_su_signal_rx_20mhz(
                black_box(second), WIFI_EHT_ACQUISITION_SU_DATA
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_eht_rx(result)
            )
            fingerprint = _merge(
                fingerprint,
                _fingerprint_bits(Span(result.eht_sig_decoded_bits)),
            )
            keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _he_data_workload(
    iterations: Int,
    salt: Int,
    signal: Span[Complex64, ...],
    data_first: Span[Complex64, ...],
    data_second: Span[Complex64, ...],
    ltf: Span[Complex64, ...],
    payload_bits: Int,
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        var first = ((iteration + salt) & 1) == 0
        if first:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_he_signal_driven_ldpc_rx_20mhz(
                black_box(signal),
                black_box(data_first),
                black_box(ltf),
                payload_bits,
                0.01,
                scrambler_seed=UInt8(0x5D),
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_he_data(result)
            )
            fingerprint = _merge(
                fingerprint,
                _fingerprint_bits(Span(result.data.payload_bits)),
            )
            keep(result)
        else:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_he_signal_driven_ldpc_rx_20mhz(
                black_box(signal),
                black_box(data_second),
                black_box(ltf),
                payload_bits,
                0.01,
                scrambler_seed=UInt8(0x4B),
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_he_data(result)
            )
            fingerprint = _merge(
                fingerprint,
                _fingerprint_bits(Span(result.data.payload_bits)),
            )
            keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


@no_inline
def _eht_data_workload(
    iterations: Int,
    salt: Int,
    signal: Span[Complex64, ...],
    data_first: Span[Complex64, ...],
    data_second: Span[Complex64, ...],
    ltf: Span[Complex64, ...],
    payload_bits: Int,
    measure: Bool,
) raises -> _WorkloadMeasurement:
    var elapsed = UInt64(0)
    var full_checksum = _OFFSET_BASIS
    var fingerprint = _OFFSET_BASIS
    for iteration in range(iterations):
        var first = ((iteration + salt) & 1) == 0
        if first:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_eht_signal_driven_ldpc_rx_20mhz(
                black_box(signal),
                black_box(data_first),
                black_box(ltf),
                payload_bits,
                0.01,
                WIFI_EHT_ACQUISITION_SU_DATA,
                scrambler_seed=UInt8(0x5D),
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_eht_data(result)
            )
            fingerprint = _merge(
                fingerprint,
                _fingerprint_bits(Span(result.data.payload_bits)),
            )
            keep(result)
        else:
            var start = UInt64(0)
            if measure:
                start = global_perf_counter_ns()
            var result = wifi_eht_signal_driven_ldpc_rx_20mhz(
                black_box(signal),
                black_box(data_second),
                black_box(ltf),
                payload_bits,
                0.01,
                WIFI_EHT_ACQUISITION_SU_DATA,
                scrambler_seed=UInt8(0x4B),
            )
            if measure:
                elapsed += global_perf_counter_ns() - start
            full_checksum = _merge(
                full_checksum, _consume_eht_data(result)
            )
            fingerprint = _merge(
                fingerprint,
                _fingerprint_bits(Span(result.data.payload_bits)),
            )
            keep(result)
    return _WorkloadMeasurement(elapsed, full_checksum, fingerprint)


def _payload_bits() -> List[UInt8]:
    var result = List[UInt8](capacity=64)
    for index in range(64):
        result.append(UInt8(((index * 13 + index // 3 + 1) >> 1) & 1))
    return result^


def main() raises:
    var eht_bits_first = wifi_eht_sig_su_20_pack(WifiEhtSigSU20Config(
        13, sta_id=77, spatial_reuse=9,
        coding=WIFI_HE_EHT_SIG_CODING_LDPC,
    ))
    var eht_bits_second = wifi_eht_sig_su_20_pack(WifiEhtSigSU20Config(
        7, sta_id=321, gi_ltf_code=3, beamformed=True,
        coding=WIFI_HE_EHT_SIG_CODING_BCC,
    ))

    var he_su = wifi_he_sig_a_waveform_tx_20mhz(WifiHeSigASUConfig(
        10, bss_color=37, coding=WIFI_HE_EHT_SIG_CODING_LDPC,
    ))
    var he_er = wifi_he_sig_a_waveform_tx_20mhz(WifiHeSigASUConfig(
        2, extended_range=True, bss_color=17,
    ))
    var u_first = wifi_eht_u_sig_waveform_tx_20mhz(
        WifiEhtUSigSU20Config(
            4, txop_code=19, eht_sig_mcs_code=0, eht_sig_symbols=2
        )
    )
    var u_second = wifi_eht_u_sig_waveform_tx_20mhz(
        WifiEhtUSigSU20Config(
            51, uplink=True, txop_code=91,
            eht_sig_mcs_code=0, eht_sig_symbols=2,
        )
    )
    var eht_signal_first = wifi_eht_su_signal_tx_20mhz(
        WifiEhtUSigSU20Config(
            4, txop_code=17, eht_sig_mcs_code=0, eht_sig_symbols=2
        ),
        WifiEhtSigSU20Config(
            13, sta_id=77, coding=WIFI_HE_EHT_SIG_CODING_LDPC
        ),
    )
    var eht_signal_second = wifi_eht_su_signal_tx_20mhz(
        WifiEhtUSigSU20Config(
            41, uplink=True, txop_code=71,
            eht_sig_mcs_code=0, eht_sig_symbols=2,
        ),
        WifiEhtSigSU20Config(
            7, sta_id=321, beamformed=True,
            coding=WIFI_HE_EHT_SIG_CODING_BCC,
        ),
    )

    var payload = _payload_bits()
    var he_data_first = wifi_ldpc_tx_20mhz(
        Span(payload), WIFI_PHY_HE, 10, scrambler_seed=UInt8(0x5D)
    )
    var he_data_second = wifi_ldpc_tx_20mhz(
        Span(payload), WIFI_PHY_HE, 10, scrambler_seed=UInt8(0x4B)
    )
    var eht_data_first = wifi_ldpc_tx_20mhz(
        Span(payload), WIFI_PHY_EHT, 13, scrambler_seed=UInt8(0x5D)
    )
    var eht_data_second = wifi_ldpc_tx_20mhz(
        Span(payload), WIFI_PHY_EHT, 13, scrambler_seed=UInt8(0x4B)
    )
    var he_ltf = wifi_ltf_waveform_20mhz(
        WIFI_PHY_HE, cyclic_prefix_samples=16
    )
    var eht_ltf = wifi_ltf_waveform_20mhz(
        WIFI_PHY_EHT, cyclic_prefix_samples=16
    )

    # Fail before timing when either decoded SIGNAL-to-DATA fixture is invalid.
    var he_check = wifi_he_signal_driven_ldpc_rx_20mhz(
        Span(he_su.waveform),
        Span(he_data_first.waveform),
        Span(he_ltf),
        len(payload),
        0.01,
    )
    var eht_check = wifi_eht_signal_driven_ldpc_rx_20mhz(
        Span(eht_signal_first.waveform),
        Span(eht_data_first.waveform),
        Span(eht_ltf),
        len(payload),
        0.01,
        WIFI_EHT_ACQUISITION_SU_DATA,
    )
    if (
        not he_check.data.fcs_ok
        or not eht_check.data.fcs_ok
        or he_check.data.payload_bits != payload
        or eht_check.data.payload_bits != payload
    ):
        raise Error("SIGNAL-driven benchmark fixture failed its oracle")

    for _ in range(_WARMUPS):
        var salt = 324508639
        keep(_eht_pack_workload(_FIELD_BATCH, salt, False))
        keep(_eht_parse_workload(
            _FIELD_BATCH,
            salt,
            Span(eht_bits_first),
            Span(eht_bits_second),
            False,
        ))
        keep(_he_tx_workload(_WAVEFORM_BATCH, salt, False))
        keep(_he_rx_workload(
            _WAVEFORM_BATCH,
            salt,
            Span(he_su.waveform),
            Span(he_er.waveform),
            False,
        ))
        keep(_u_tx_workload(_WAVEFORM_BATCH, salt, False))
        keep(_u_rx_workload(
            _WAVEFORM_BATCH, salt,
            Span(u_first.waveform), Span(u_second.waveform),
            False,
        ))
        keep(_eht_tx_workload(_COMBINED_BATCH, salt, False))
        keep(_eht_rx_workload(
            _COMBINED_BATCH, salt,
            Span(eht_signal_first.waveform), Span(eht_signal_second.waveform),
            False,
        ))
        keep(_he_data_workload(
            _DATA_BATCH, salt,
            Span(he_su.waveform),
            Span(he_data_first.waveform), Span(he_data_second.waveform),
            Span(he_ltf), len(payload),
            False,
        ))
        keep(_eht_data_workload(
            _DATA_BATCH, salt,
            Span(eht_signal_first.waveform),
            Span(eht_data_first.waveform), Span(eht_data_second.waveform),
            Span(eht_ltf), len(payload),
            False,
        ))

    var pack_samples = List[UInt64](capacity=_SAMPLES)
    var parse_samples = List[UInt64](capacity=_SAMPLES)
    var he_tx_samples = List[UInt64](capacity=_SAMPLES)
    var he_rx_samples = List[UInt64](capacity=_SAMPLES)
    var u_tx_samples = List[UInt64](capacity=_SAMPLES)
    var u_rx_samples = List[UInt64](capacity=_SAMPLES)
    var eht_tx_samples = List[UInt64](capacity=_SAMPLES)
    var eht_rx_samples = List[UInt64](capacity=_SAMPLES)
    var he_data_samples = List[UInt64](capacity=_SAMPLES)
    var eht_data_samples = List[UInt64](capacity=_SAMPLES)
    var full_output_checksum = _OFFSET_BASIS
    var fingerprint_checksum = _OFFSET_BASIS

    for _ in range(_SAMPLES):
        var salt = 324508639
        _record_measurement(
            _eht_pack_workload(_FIELD_BATCH, salt, True),
            pack_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _eht_parse_workload(
                _FIELD_BATCH,
                salt,
                Span(eht_bits_first),
                Span(eht_bits_second),
                True,
            ),
            parse_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _he_tx_workload(_WAVEFORM_BATCH, salt, True),
            he_tx_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _he_rx_workload(
                _WAVEFORM_BATCH,
                salt,
                Span(he_su.waveform),
                Span(he_er.waveform),
                True,
            ),
            he_rx_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _u_tx_workload(_WAVEFORM_BATCH, salt, True),
            u_tx_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _u_rx_workload(
                _WAVEFORM_BATCH,
                salt,
                Span(u_first.waveform),
                Span(u_second.waveform),
                True,
            ),
            u_rx_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _eht_tx_workload(_COMBINED_BATCH, salt, True),
            eht_tx_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _eht_rx_workload(
                _COMBINED_BATCH,
                salt,
                Span(eht_signal_first.waveform),
                Span(eht_signal_second.waveform),
                True,
            ),
            eht_rx_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _he_data_workload(
                _DATA_BATCH,
                salt,
                Span(he_su.waveform),
                Span(he_data_first.waveform),
                Span(he_data_second.waveform),
                Span(he_ltf),
                len(payload),
                True,
            ),
            he_data_samples,
            full_output_checksum,
            fingerprint_checksum,
        )
        _record_measurement(
            _eht_data_workload(
                _DATA_BATCH,
                salt,
                Span(eht_signal_first.waveform),
                Span(eht_data_first.waveform),
                Span(eht_data_second.waveform),
                Span(eht_ltf),
                len(payload),
                True,
            ),
            eht_data_samples,
            full_output_checksum,
            fingerprint_checksum,
        )

    print_benchmark_metadata()
    print("wifi_he_eht_sig_waveform_implementation: scalar-cpu-reference")
    print("wifi_he_eht_sig_waveform_scope: 20mhz-su-er-su-eht-su-context")
    print("wifi_he_eht_sig_waveform_input_variation: fixed-salted")
    print("wifi_he_eht_sig_waveform_timed_scope: target-api-only")
    print("wifi_he_eht_sig_waveform_post_timer_scope: keep-plus-full-output-checksum-plus-o1-fingerprint")
    report_timing_samples(
        "wifi_eht_sig_su_20_pack", pack_samples,
        _WARMUPS, _FIELD_BATCH, "signal_field",
    )
    report_timing_samples(
        "wifi_eht_sig_su_20_parse", parse_samples,
        _WARMUPS, _FIELD_BATCH, "signal_field",
    )
    report_timing_samples(
        "wifi_he_sig_a_waveform_tx_20mhz", he_tx_samples,
        _WARMUPS, _WAVEFORM_BATCH, "waveform",
    )
    report_timing_samples(
        "wifi_he_sig_a_waveform_rx_20mhz", he_rx_samples,
        _WARMUPS, _WAVEFORM_BATCH, "waveform",
    )
    report_timing_samples(
        "wifi_eht_u_sig_waveform_tx_20mhz", u_tx_samples,
        _WARMUPS, _WAVEFORM_BATCH, "waveform",
    )
    report_timing_samples(
        "wifi_eht_u_sig_waveform_rx_20mhz", u_rx_samples,
        _WARMUPS, _WAVEFORM_BATCH, "waveform",
    )
    report_timing_samples(
        "wifi_eht_su_signal_tx_20mhz", eht_tx_samples,
        _WARMUPS, _COMBINED_BATCH, "signal_slice",
    )
    report_timing_samples(
        "wifi_eht_su_signal_rx_20mhz", eht_rx_samples,
        _WARMUPS, _COMBINED_BATCH, "signal_slice",
    )
    report_timing_samples(
        "wifi_he_signal_driven_ldpc_rx_20mhz", he_data_samples,
        _WARMUPS, _DATA_BATCH, "signal_driven_data",
    )
    report_timing_samples(
        "wifi_eht_signal_driven_ldpc_rx_20mhz", eht_data_samples,
        _WARMUPS, _DATA_BATCH, "signal_driven_data",
    )
    keep(full_output_checksum)
    keep(fingerprint_checksum)
    print(
        "wifi_he_eht_sig_waveform_full_output_checksum:",
        full_output_checksum,
    )
    print(
        "wifi_he_eht_sig_waveform_fingerprint_checksum:",
        fingerprint_checksum,
    )
