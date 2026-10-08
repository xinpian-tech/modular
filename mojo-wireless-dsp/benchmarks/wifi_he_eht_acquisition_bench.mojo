"""Latency evidence for the acquired HE/EHT RU-242 mini-PHY.

Inputs and seeded RF observations are prepared outside timed regions.  Two
warmups precede seven retained samples.  The benchmark reports median and
nearest-rank p95 for training/acquisition utilities and for HE/EHT TX/RX,
while output-dependent checksums prevent dead-work elimination.
"""

from std.benchmark import keep
from std.collections import Span
from std.sys.info import align_of
from std.time import global_perf_counter_ns
from wireless_dsp.benchmarking import (
    print_benchmark_metadata,
    print_runtime_buffer_alignment,
    report_timing_samples,
)
from wireless_dsp.channel import apply_cfo
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.acquisition_chain import (
    WifiAcquisitionChannelConfig,
    wifi_acquisition_apply_channel_20mhz,
)
from wireless_dsp.wireless.wifi.he_eht_acquisition import (
    WifiHEEHTAcquisitionTx20MHz,
    WifiHEEHTAcquisitionRx20MHz,
    wifi_he_eht_acquisition_rx_20mhz,
    wifi_he_eht_acquisition_tx_20mhz,
    wifi_he_eht_ltf_fine_cfo_20mhz,
    wifi_he_eht_ltf_fine_timing_20mhz,
    wifi_legacy_ltf_spectrum_20mhz,
    wifi_legacy_ltf_waveform_20mhz,
)
from wireless_dsp.wireless.wifi.preambles import wifi_ltf_waveform_20mhz
from wireless_dsp.wireless.wifi.profiles import WIFI_PHY_EHT, WIFI_PHY_HE


comptime _WARMUPS = 3
comptime _REPETITIONS = 9


@no_inline
def _workload_wifi_legacy_ltf_spectrum_20mhz() raises -> List[Complex64]:
    return wifi_legacy_ltf_spectrum_20mhz()


@no_inline
def _workload_wifi_legacy_ltf_waveform_20mhz() raises -> List[Complex64]:
    return wifi_legacy_ltf_waveform_20mhz()


@no_inline
def _workload_wifi_he_eht_ltf_fine_timing_20mhz(
    values: Span[Complex64, ...], family: Int, expected: Int,
) raises -> Int:
    return wifi_he_eht_ltf_fine_timing_20mhz(
        values, family, expected, search_radius=6
    )


@no_inline
def _workload_wifi_he_eht_ltf_fine_cfo_20mhz(
    values: Span[Complex64, ...], timing: Int,
) raises -> Float64:
    return wifi_he_eht_ltf_fine_cfo_20mhz(values, timing)


@no_inline
def _workload_wifi_he_eht_acquisition_tx_20mhz(
    payload: Span[UInt8, ...], family: Int, mcs: Int,
) raises -> WifiHEEHTAcquisitionTx20MHz:
    return wifi_he_eht_acquisition_tx_20mhz(
        payload, family, mcs, symbol_index=5
    )


@no_inline
def _workload_wifi_he_eht_acquisition_rx_20mhz(
    observation: Span[Complex64, ...], family: Int, mcs: Int, octets: Int,
) raises -> WifiHEEHTAcquisitionRx20MHz:
    return wifi_he_eht_acquisition_rx_20mhz(
        observation, family, mcs, octets, symbol_index=5,
        llr_noise_variance=1.0e-8, max_iterations=5,
    )


def _payload_octets(octets: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * octets)
    for i in range(8 * octets):
        result.append(UInt8((17 * i + i // 7 + salt) & 1))
    return result^


def _complex_content_checksum(values: Span[Complex64, ...]) -> UInt64:
    var first = values[0]
    var last = values[len(values) - 1]
    return (
        UInt64(len(values))
        ^ UInt64(first.magnitude_squared() * 1.0e9)
        ^ (UInt64(last.magnitude_squared() * 1.0e9) << 17)
    )


def _shifted_ltf(family: Int, delay: Int, cfo: Float64) raises -> List[Complex64]:
    var ltf = wifi_ltf_waveform_20mhz(family)
    var padded = List[Complex64](capacity=delay + len(ltf) + 5)
    for _ in range(delay):
        padded.append(Complex64(0.0, 0.0))
    for sample in ltf:
        padded.append(sample)
    for _ in range(5):
        padded.append(Complex64(0.0, 0.0))
    return apply_cfo(Span(padded), cfo)


def _utility_workload() raises -> UInt64:
    """Untimed aggregate sanity check; reported families remain isolated."""
    var legacy_spectrum = _workload_wifi_legacy_ltf_spectrum_20mhz()
    var legacy_waveform = _workload_wifi_legacy_ltf_waveform_20mhz()
    var checksum = _complex_content_checksum(Span(legacy_spectrum))
    checksum ^= _complex_content_checksum(Span(legacy_waveform))
    for family, delay, cfo in [
        (WIFI_PHY_HE, 9, 0.001125),
        (WIFI_PHY_EHT, 13, -0.001375),
    ]:
        var shifted = _shifted_ltf(family, delay, cfo)
        var timing = _workload_wifi_he_eht_ltf_fine_timing_20mhz(
            Span(shifted), family, delay + 2
        )
        var estimate = _workload_wifi_he_eht_ltf_fine_cfo_20mhz(
            Span(shifted), timing
        )
        if abs(estimate - cfo) > 1.0e-12:
            raise Error("benchmark LTF CFO workload failed its oracle")
        keep(legacy_spectrum)
        keep(legacy_waveform)
        keep(shifted)
        checksum ^= UInt64(timing)
        checksum ^= UInt64(abs(estimate) * 1.0e15)
        checksum *= UInt64(1099511628211)
    return checksum


def main() raises:
    var he_payload = _payload_octets(205, 31)
    var eht_payload = _payload_octets(264, 47)
    var he_reference = _workload_wifi_he_eht_acquisition_tx_20mhz(Span(he_payload), WIFI_PHY_HE, 10)
    var eht_reference = _workload_wifi_he_eht_acquisition_tx_20mhz(Span(eht_payload), WIFI_PHY_EHT, 13)
    var he_channel = wifi_acquisition_apply_channel_20mhz(
        Span(he_reference.packet_waveform),
        WifiAcquisitionChannelConfig(
            timing_offset=11,
            normalized_cfo=0.00125,
            noise_variance=0.0,
            rician_k_factor=80.0,
            seed=UInt64(0xBEEFC0DE),
        ),
    )
    var eht_channel = wifi_acquisition_apply_channel_20mhz(
        Span(eht_reference.packet_waveform),
        WifiAcquisitionChannelConfig(
            timing_offset=7,
            normalized_cfo=-0.0015,
            noise_variance=0.0,
            rician_k_factor=80.0,
            seed=UInt64(0xE471BEEF),
        ),
    )
    var he_shifted_ltf = _shifted_ltf(WIFI_PHY_HE, 9, 0.001125)
    var eht_shifted_ltf = _shifted_ltf(WIFI_PHY_EHT, 13, -0.001375)
    var he_timing_fixture = _workload_wifi_he_eht_ltf_fine_timing_20mhz(
        Span(he_shifted_ltf), WIFI_PHY_HE, 11
    )

    # Validate retained workloads before collecting latency samples.
    var he_check = _workload_wifi_he_eht_acquisition_rx_20mhz(
        Span(he_channel.observation),
        WIFI_PHY_HE,
        10,
        len(he_payload),
    )
    var eht_check = _workload_wifi_he_eht_acquisition_rx_20mhz(
        Span(eht_channel.observation),
        WIFI_PHY_EHT,
        13,
        len(eht_payload),
    )
    if (
        he_check.data.payload_bits != he_payload
        or eht_check.data.payload_bits != eht_payload
        or not he_check.data.fcs_ok
        or not eht_check.data.fcs_ok
    ):
        raise Error("acquired HE/EHT benchmark workload failed round trip")

    keep(_utility_workload())
    for _ in range(_WARMUPS):
        keep(_workload_wifi_legacy_ltf_spectrum_20mhz())
        keep(_workload_wifi_legacy_ltf_waveform_20mhz())
        var he_timing = _workload_wifi_he_eht_ltf_fine_timing_20mhz(
            Span(he_shifted_ltf), WIFI_PHY_HE, 11
        )
        keep(_workload_wifi_he_eht_ltf_fine_cfo_20mhz(
            Span(he_shifted_ltf), he_timing
        ))
        var eht_timing = _workload_wifi_he_eht_ltf_fine_timing_20mhz(
            Span(eht_shifted_ltf), WIFI_PHY_EHT, 15
        )
        keep(_workload_wifi_he_eht_ltf_fine_cfo_20mhz(
            Span(eht_shifted_ltf), eht_timing
        ))
        keep(
            _workload_wifi_he_eht_acquisition_tx_20mhz(
                Span(he_payload), WIFI_PHY_HE, 10
            )
        )
        keep(
            _workload_wifi_he_eht_acquisition_tx_20mhz(
                Span(eht_payload), WIFI_PHY_EHT, 13
            )
        )
        keep(
            _workload_wifi_he_eht_acquisition_rx_20mhz(
                Span(he_channel.observation),
                WIFI_PHY_HE,
                10,
                len(he_payload),
            )
        )
        keep(
            _workload_wifi_he_eht_acquisition_rx_20mhz(
                Span(eht_channel.observation),
                WIFI_PHY_EHT,
                13,
                len(eht_payload),
            )
        )

    var legacy_spectrum_samples = List[UInt64](capacity=_REPETITIONS)
    var legacy_waveform_samples = List[UInt64](capacity=_REPETITIONS)
    var timing_samples = List[UInt64](capacity=_REPETITIONS)
    var cfo_samples = List[UInt64](capacity=_REPETITIONS)
    var he_tx_samples = List[UInt64](capacity=_REPETITIONS)
    var he_rx_samples = List[UInt64](capacity=_REPETITIONS)
    var legacy_spectrum_checksum = UInt64(0)
    var legacy_waveform_checksum = UInt64(0)
    var timing_checksum = UInt64(0)
    var cfo_checksum = UInt64(0)
    var he_tx_checksum = UInt64(0)
    var he_rx_checksum = UInt64(0)
    for _ in range(_REPETITIONS):
        var start = global_perf_counter_ns()
        var legacy_spectrum = _workload_wifi_legacy_ltf_spectrum_20mhz()
        legacy_spectrum_samples.append(global_perf_counter_ns() - start)
        keep(legacy_spectrum)
        legacy_spectrum_checksum ^= _complex_content_checksum(Span(legacy_spectrum))

        start = global_perf_counter_ns()
        var legacy_waveform = _workload_wifi_legacy_ltf_waveform_20mhz()
        legacy_waveform_samples.append(global_perf_counter_ns() - start)
        keep(legacy_waveform)
        legacy_waveform_checksum ^= _complex_content_checksum(Span(legacy_waveform))

        start = global_perf_counter_ns()
        var he_timing = _workload_wifi_he_eht_ltf_fine_timing_20mhz(
            Span(he_shifted_ltf), WIFI_PHY_HE, 11
        )
        timing_samples.append(global_perf_counter_ns() - start)
        keep(he_timing)
        timing_checksum ^= UInt64(he_timing)

        start = global_perf_counter_ns()
        var he_cfo = _workload_wifi_he_eht_ltf_fine_cfo_20mhz(
            Span(he_shifted_ltf), he_timing_fixture
        )
        cfo_samples.append(global_perf_counter_ns() - start)
        keep(he_cfo)
        cfo_checksum ^= UInt64(abs(he_cfo) * 1.0e15)

        start = global_perf_counter_ns()
        var he_tx = _workload_wifi_he_eht_acquisition_tx_20mhz(
            Span(he_payload), WIFI_PHY_HE, 10
        )
        he_tx_samples.append(global_perf_counter_ns() - start)
        he_tx_checksum ^= (
            he_tx.data.fcs
            ^ _complex_content_checksum(Span(he_tx.packet_waveform))
        )
        keep(he_tx)

        start = global_perf_counter_ns()
        var he_rx = _workload_wifi_he_eht_acquisition_rx_20mhz(
            Span(he_channel.observation),
            WIFI_PHY_HE,
            10,
            len(he_payload),
        )
        he_rx_samples.append(global_perf_counter_ns() - start)
        he_rx_checksum ^= UInt64(he_rx.data_start) ^ UInt64(len(he_rx.data.payload_bits))
        keep(he_rx)

    print_benchmark_metadata()
    print_runtime_buffer_alignment(
        "wifi_he_payload_bits",
        Int(he_payload.unsafe_ptr()),
        align_of[UInt8](),
    )
    print_runtime_buffer_alignment(
        "wifi_he_channel_observation",
        Int(he_channel.observation.unsafe_ptr()),
        align_of[Complex64](),
    )
    report_timing_samples(
        "wifi_legacy_ltf_spectrum_20mhz",
        legacy_spectrum_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_legacy_ltf_waveform_20mhz",
        legacy_waveform_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_he_eht_ltf_fine_timing_20mhz",
        timing_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_he_eht_ltf_fine_cfo_20mhz",
        cfo_samples,
        _WARMUPS,
        1,
        "api_call",
    )
    report_timing_samples(
        "wifi_he_mcs10_tx_frame", he_tx_samples, _WARMUPS, 1,
        "he_tx_frame",
    )
    report_timing_samples(
        "wifi_he_mcs10_rx_frame", he_rx_samples, _WARMUPS, 1,
        "he_rx_frame",
    )
    keep(legacy_spectrum_checksum)
    keep(legacy_waveform_checksum)
    keep(timing_checksum)
    keep(cfo_checksum)
    keep(he_tx_checksum)
    keep(he_rx_checksum)
    print("wifi_legacy_ltf_spectrum_retained_checksum:", legacy_spectrum_checksum)
    print("wifi_legacy_ltf_waveform_retained_checksum:", legacy_waveform_checksum)
    print("wifi_he_eht_ltf_timing_retained_checksum:", timing_checksum)
    print("wifi_he_eht_ltf_cfo_retained_checksum:", cfo_checksum)
    print("wifi_he_mcs10_tx_retained_checksum:", he_tx_checksum)
    print("wifi_he_mcs10_rx_retained_checksum:", he_rx_checksum)
