"""Strict evidence for the acquired HE/EHT 20 MHz RU-242 mini-PHY."""

from std.collections import Span
from std.math import isfinite
from std.testing import assert_equal, assert_raises, assert_true, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.channel import apply_cfo
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import complex_divide, ofdm_demodulate
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.wifi.acquisition_chain import (
    WifiAcquisitionChannelConfig,
    wifi_acquisition_apply_channel_20mhz,
    wifi_legacy_signal_tx_20mhz,
    wifi_stf_waveform_20mhz,
)
from wireless_dsp.wireless.wifi.he_eht_acquisition import (
    wifi_he_eht_acquisition_rx_20mhz,
    wifi_he_eht_acquisition_tx_20mhz,
    wifi_he_eht_ltf_fine_cfo_20mhz,
    wifi_he_eht_ltf_fine_timing_20mhz,
    wifi_legacy_ltf_spectrum_20mhz,
    wifi_legacy_ltf_waveform_20mhz,
)
from wireless_dsp.wireless.wifi.preambles import (
    wifi_ltf_spectrum_20mhz,
    wifi_ltf_waveform_20mhz,
)
from wireless_dsp.wireless.wifi.phy_chain import wifi_ldpc_tx_20mhz
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_EHT,
    WIFI_PHY_HE,
    WIFI_PHY_HT,
)


def _assert_checkpoint_metadata(
    metadata: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stages: List[String],
    dtypes: List[String],
    shapes: List[String],
    q_formats: List[String],
    layouts: List[String],
) raises:
    assert_equal(len(metadata), len(stages))
    assert_equal(len(metadata), len(dtypes))
    assert_equal(len(metadata), len(shapes))
    assert_equal(len(metadata), len(q_formats))
    assert_equal(len(metadata), len(layouts))
    for index in range(len(metadata)):
        assert_equal(metadata[index].testcase_id, testcase_id)
        assert_equal(metadata[index].stage, stages[index])
        assert_equal(metadata[index].dtype, dtypes[index])
        assert_equal(metadata[index].shape, shapes[index])
        assert_equal(metadata[index].stride, "1")
        assert_equal(metadata[index].q_format, q_formats[index])
        assert_equal(metadata[index].scale, 1.0)
        assert_equal(metadata[index].version, 1)
        assert_equal(metadata[index].layout, layouts[index])


def _payload_octets(octets: Int, salt: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=8 * octets)
    for i in range(8 * octets):
        result.append(UInt8((13 * i + i // 5 + salt) & 1))
    return result^


def _flat_fading_oracle(
    transmitted: Span[Complex64, ...], faded: Span[Complex64, ...]
) raises -> Complex64:
    """Recover the channel coefficient independently from retained TX/RF data."""
    if len(transmitted) != len(faded):
        raise Error("oracle vectors must have equal length")
    for i in range(len(transmitted)):
        var tx = Complex64(transmitted[i].re, transmitted[i].im)
        var rf = Complex64(faded[i].re, faded[i].im)
        if tx.magnitude_squared() > 1.0e-12:
            return complex_divide(rf, tx)
    raise Error("oracle requires a nonzero transmitted sample")


def _assert_channel_matches(
    estimate: Span[Complex64, ...],
    known_spectrum: Span[Complex64, ...],
    expected: Complex64,
    tolerance: Float64,
) raises:
    var checked = 0
    for i in range(len(estimate)):
        var known = Complex64(known_spectrum[i].re, known_spectrum[i].im)
        if known.magnitude_squared() > 0.0:
            assert_true(abs(estimate[i].re - expected.re) < tolerance)
            assert_true(abs(estimate[i].im - expected.im) < tolerance)
            checked += 1
    assert_true(checked > 0)


def test_legacy_l_ltf_static_spectrum_gi2_and_two_repetitions() raises:
    """Published legacy tones and exact GI2/repetition geometry are static oracles."""
    var spectrum = wifi_legacy_ltf_spectrum_20mhz()
    var repeated_spectrum = wifi_legacy_ltf_spectrum_20mhz()
    assert_equal(spectrum, repeated_spectrum)
    assert_equal(len(spectrum), 64)
    assert_equal(spectrum[64 - 28], Complex64(0.0, 0.0))
    assert_equal(spectrum[64 - 27], Complex64(0.0, 0.0))
    assert_equal(spectrum[27], Complex64(0.0, 0.0))
    assert_equal(spectrum[28], Complex64(0.0, 0.0))
    assert_equal(spectrum[0], Complex64(0.0, 0.0))
    assert_equal(spectrum[64 - 26], Complex64(1.0, 0.0))
    assert_equal(spectrum[64 - 25], Complex64(1.0, 0.0))
    assert_equal(spectrum[64 - 24], Complex64(-1.0, 0.0))
    assert_equal(spectrum[26], Complex64(1.0, 0.0))
    var occupied = 0
    for value in spectrum:
        if value.magnitude_squared() > 0.0:
            occupied += 1
    assert_equal(occupied, 52)

    var waveform = wifi_legacy_ltf_waveform_20mhz()
    assert_equal(waveform, wifi_legacy_ltf_waveform_20mhz())
    assert_equal(len(waveform), 160)
    for i in range(32):
        assert_equal(waveform[i], waveform[64 + i])
    for i in range(64):
        assert_equal(waveform[32 + i], waveform[96 + i])
    var recovered = ofdm_demodulate(Span(waveform)[32:96], 64, 0)
    for i in range(64):
        assert_true(abs(recovered[i].re - spectrum[i].re) < 1.0e-12)
        assert_true(abs(recovered[i].im - spectrum[i].im) < 1.0e-12)


def test_tx_geometry_profile_property_and_determinism() raises:
    """Both permitted profiles have one RU-242 DATA symbol and stable offsets."""
    for family, mcs_index, octets, bpsc in [
        (WIFI_PHY_HE, 10, 205, 10),
        (WIFI_PHY_EHT, 13, 264, 12),
    ]:
        var payload = _payload_octets(octets, family + 11)
        var first = wifi_he_eht_acquisition_tx_20mhz(
            Span(payload), family, mcs_index, symbol_index=5
        )
        var second = wifi_he_eht_acquisition_tx_20mhz(
            Span(payload), family, mcs_index, symbol_index=5
        )
        assert_equal(first.family, family)
        assert_equal(first.mcs_index, mcs_index)
        assert_equal(first.legacy_ltf_offset, 160)
        assert_equal(first.signal_offset, 320)
        assert_equal(first.he_eht_ltf_offset, 400)
        assert_equal(first.data_offset, 672)
        assert_equal(len(first.legacy_stf_waveform), 160)
        assert_equal(len(first.legacy_ltf_waveform), 160)
        assert_equal(len(first.signal.waveform), 80)
        assert_equal(len(first.he_eht_ltf_waveform), 272)
        assert_equal(len(first.data.waveform), 272)
        assert_equal(len(first.packet_waveform), 944)
        assert_equal(first.signal.length_octets, octets + 4)
        assert_equal(len(first.data.qam_symbols), 234)
        assert_equal(len(first.data.tone_mapped_bits), 234 * bpsc)
        var tx_stages: List[String] = [
            "legacy-ltf-spectrum",
            "legacy-stf-waveform",
            "legacy-ltf-waveform",
            "he-eht-ltf-waveform",
            "packet-waveform",
        ]
        var tx_dtypes: List[String] = [
            "complex64", "complex64", "complex64", "complex64", "complex64"
        ]
        var tx_shapes: List[String] = ["64", "160", "160", "272", "944"]
        var tx_q_formats: List[String] = [
            "floating", "floating", "floating", "floating", "floating"
        ]
        var tx_layouts: List[String] = [
            "iq-interleaved",
            "iq-interleaved",
            "iq-interleaved",
            "iq-interleaved",
            "iq-interleaved",
        ]
        _assert_checkpoint_metadata(
            first.checkpoint_metadata,
            "wifi-he-eht-acquisition-tx-20mhz",
            tx_stages,
            tx_dtypes,
            tx_shapes,
            tx_q_formats,
            tx_layouts,
        )
        assert_equal(len(first.signal.checkpoint_metadata), 6)
        for index in range(len(first.signal.checkpoint_metadata)):
            assert_equal(
                first.signal.checkpoint_metadata[index].testcase_id,
                "wifi-he-eht-acquisition-tx-20mhz",
            )
        assert_equal(len(first.data.checkpoint_metadata), 9)
        for index in range(len(first.data.checkpoint_metadata)):
            assert_equal(
                first.data.checkpoint_metadata[index].testcase_id,
                "wifi-he-eht-acquisition-tx-20mhz",
            )
        assert_equal(first.packet_waveform, second.packet_waveform)
        assert_equal(first.data.frame_bits, second.data.frame_bits)
        assert_equal(first.data.fcs, second.data.fcs)

        # Independent public-component recomposition pins every TX boundary.
        var direct_stf = wifi_stf_waveform_20mhz()
        var direct_legacy_ltf = wifi_legacy_ltf_waveform_20mhz()
        var direct_signal = wifi_legacy_signal_tx_20mhz(octets + 4)
        var direct_he_eht_ltf = wifi_ltf_waveform_20mhz(family)
        var direct_data = wifi_ldpc_tx_20mhz(
            Span(payload), family, mcs_index, symbol_index=5
        )
        for i in range(160):
            assert_equal(first.packet_waveform[i], direct_stf[i])
            assert_equal(
                first.packet_waveform[first.legacy_ltf_offset + i],
                direct_legacy_ltf[i],
            )
        for i in range(80):
            assert_equal(
                first.packet_waveform[first.signal_offset + i],
                direct_signal.waveform[i],
            )
        for i in range(272):
            assert_equal(
                first.packet_waveform[first.he_eht_ltf_offset + i],
                direct_he_eht_ltf[i],
            )
            assert_equal(
                first.packet_waveform[first.data_offset + i],
                direct_data.waveform[i],
            )
        assert_equal(first.data.rate_matched_bits, direct_data.rate_matched_bits)

        # Independently parse the L-SIG bit layout and even parity.
        assert_equal(first.signal.bits[4], UInt8(0))
        var decoded_length = 0
        for i in range(12):
            decoded_length |= Int(first.signal.bits[5 + i]) << i
        assert_equal(decoded_length, octets + 4)
        var parity = UInt8(0)
        for i in range(18):
            parity ^= first.signal.bits[i]
        assert_equal(parity, UInt8(0))
        for i in range(18, 24):
            assert_equal(first.signal.bits[i], UInt8(0))


def test_he_eht_ltf_timing_and_cfo_analytic_oracles() raises:
    """Injected integer delay and phase slope pin timing/CFO with tight tolerance."""
    for family, delay, cfo in [
        (WIFI_PHY_HE, 9, 0.001125),
        (WIFI_PHY_EHT, 13, -0.001375),
    ]:
        var ltf = wifi_ltf_waveform_20mhz(family)
        var padded = List[Complex64](capacity=delay + len(ltf) + 7)
        for _ in range(delay):
            padded.append(Complex64(0.0, 0.0))
        for sample in ltf:
            padded.append(sample)
        for _ in range(7):
            padded.append(Complex64(0.0, 0.0))
        var shifted = apply_cfo(Span(padded), cfo)
        var timing = wifi_he_eht_ltf_fine_timing_20mhz(
            Span(shifted), family, delay + 3, search_radius=8
        )
        assert_equal(timing, delay)
        var estimate = wifi_he_eht_ltf_fine_cfo_20mhz(
            Span(shifted), timing
        )
        assert_true(abs(estimate - cfo) < 1.0e-12)
        assert_equal(
            wifi_he_eht_ltf_fine_timing_20mhz(
                Span(shifted), family, delay + 3, search_radius=8
            ),
            timing,
        )
        assert_equal(
            wifi_he_eht_ltf_fine_cfo_20mhz(Span(shifted), timing),
            estimate,
        )


def _assert_acquired_link(
    family: Int,
    mcs_index: Int,
    octets: Int,
    timing_offset: Int,
    cfo: Float64,
    seed: UInt64,
) raises:
    var payload = _payload_octets(octets, family + 37)
    var tx = wifi_he_eht_acquisition_tx_20mhz(
        Span(payload), family, mcs_index, symbol_index=5
    )
    var channel = wifi_acquisition_apply_channel_20mhz(
        Span(tx.packet_waveform),
        WifiAcquisitionChannelConfig(
            timing_offset=timing_offset,
            normalized_cfo=cfo,
            noise_variance=1.0e-12,
            rician_k_factor=80.0,
            seed=seed,
        ),
    )
    var channel_oracle = _flat_fading_oracle(
        Span(tx.packet_waveform), Span(channel.faded_waveform)
    )
    var rx = wifi_he_eht_acquisition_rx_20mhz(
        Span(channel.observation),
        family,
        mcs_index,
        len(payload),
        symbol_index=5,
        detection_threshold=0.82,
        llr_noise_variance=1.0e-8,
        max_iterations=10,
        testcase_id="wifi-he-eht-acquired-link",
    )
    var replay = wifi_he_eht_acquisition_rx_20mhz(
        Span(channel.observation),
        family,
        mcs_index,
        len(payload),
        symbol_index=5,
        detection_threshold=0.82,
        llr_noise_variance=1.0e-8,
        max_iterations=10,
        testcase_id="wifi-he-eht-acquired-link",
    )
    assert_equal(rx.packet_start, replay.packet_start)
    assert_equal(rx.coarse_cfo, replay.coarse_cfo)
    assert_equal(rx.fine_cfo, replay.fine_cfo)
    assert_equal(rx.signal_decoded_bits, replay.signal_decoded_bits)
    assert_equal(rx.he_eht_channel_estimate, replay.he_eht_channel_estimate)
    assert_equal(rx.data.rate_recovered_llrs, replay.data.rate_recovered_llrs)
    assert_equal(rx.data.payload_bits, replay.data.payload_bits)
    assert_true(abs(rx.packet_start - timing_offset) <= 2)
    assert_true(rx.stf_metric >= 0.82)
    assert_true(abs(rx.coarse_cfo - cfo) < 2.0e-5)
    assert_true(abs(rx.fine_cfo) < 2.0e-5)
    assert_true(abs(rx.coarse_cfo + rx.fine_cfo - cfo) < 3.0e-6)
    assert_equal(rx.legacy_ltf_start, timing_offset + 160)
    assert_equal(rx.signal_start, timing_offset + 320)
    assert_equal(rx.he_eht_ltf_start, timing_offset + 400)
    assert_equal(rx.data_start, timing_offset + 672)
    assert_true(rx.he_eht_ltf_metric > 0.999)
    assert_equal(rx.signal_decoded_bits, tx.signal.bits)
    assert_equal(rx.signal_length_octets, octets + 4)
    assert_true(rx.signal_reserved_ok)
    assert_true(rx.signal_parity_ok)
    assert_true(rx.signal_tail_ok)
    assert_true(rx.signal_rate_ok)
    assert_true(rx.signal_length_ok)
    assert_true(rx.signal_ok)
    assert_equal(len(rx.legacy_channel_estimate), 64)
    assert_equal(len(rx.he_eht_channel_estimate), 256)
    var known_legacy = wifi_legacy_ltf_spectrum_20mhz()
    var known_he_eht = wifi_ltf_spectrum_20mhz(family)
    _assert_channel_matches(
        Span(rx.legacy_channel_estimate),
        Span(known_legacy),
        channel_oracle,
        2.0e-3,
    )
    _assert_channel_matches(
        Span(rx.he_eht_channel_estimate),
        Span(known_he_eht),
        channel_oracle,
        2.0e-3,
    )
    assert_true(rx.data.ldpc_converged)
    assert_true(rx.data.service_ok)
    assert_true(rx.data.fcs_ok)
    assert_equal(rx.data.received_fcs, tx.data.fcs)
    assert_equal(rx.data.computed_fcs, tx.data.fcs)
    assert_equal(rx.data.payload_bits, payload)
    assert_true(isfinite(rx.data.common_phase))
    assert_true(isfinite(rx.data.phase_slope))
    assert_equal(len(rx.data.checkpoint_metadata), 16)
    for index in range(len(rx.data.checkpoint_metadata)):
        assert_equal(
            rx.data.checkpoint_metadata[index].testcase_id,
            "wifi-he-eht-acquired-link",
        )
    assert_equal(len(rx.checkpoint_metadata), 16)
    for index in range(len(rx.checkpoint_metadata)):
        assert_equal(
            rx.checkpoint_metadata[index].testcase_id,
            "wifi-he-eht-acquired-link",
        )
        assert_true(rx.checkpoint_metadata[index].stage.byte_length() > 0)
        assert_true(rx.checkpoint_metadata[index].dtype.byte_length() > 0)
        assert_true(rx.checkpoint_metadata[index].shape.byte_length() > 0)
        assert_equal(rx.checkpoint_metadata[index].stride, "1")
        assert_equal(rx.checkpoint_metadata[index].scale, 1.0)
        assert_equal(rx.checkpoint_metadata[index].version, 1)
        assert_true(rx.checkpoint_metadata[index].q_format.byte_length() > 0)
        assert_true(rx.checkpoint_metadata[index].layout.byte_length() > 0)
    assert_equal(
        rx.checkpoint_metadata[0].stage, "coarse-cfo-corrected-samples"
    )
    assert_equal(rx.checkpoint_metadata[7].stage, "he-eht-ltf-samples")
    assert_equal(rx.checkpoint_metadata[8].shape, "256")
    assert_equal(rx.checkpoint_metadata[15].stage, "ldpc-rate-recovered-llrs")


def test_he_mcs10_acquired_ru242_ldpc_fcs() raises:
    _assert_acquired_link(
        WIFI_PHY_HE,
        10,
        205,
        11,
        0.00125,
        UInt64(0x48E1024),
    )


def test_eht_mcs13_acquired_ru242_ldpc_fcs() raises:
    _assert_acquired_link(
        WIFI_PHY_EHT,
        13,
        264,
        7,
        -0.0015,
        UInt64(0xE4714096),
    )


def test_legacy_l_sig_length_validation_gates_ldpc_decode() raises:
    """A valid but wrong L-SIG LENGTH is rejected before DATA LDPC work."""
    var payload = _payload_octets(205, 91)
    var tx = wifi_he_eht_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_HE, 10
    )
    var wrong = wifi_legacy_signal_tx_20mhz(
        tx.signal.length_octets + 1
    )
    var packet = tx.packet_waveform.copy()
    for i in range(len(wrong.waveform)):
        packet[tx.signal_offset + i] = wrong.waveform[i]
    with assert_raises():
        _ = wifi_he_eht_acquisition_rx_20mhz(
            Span(packet), WIFI_PHY_HE, 10, len(payload)
        )


def test_legacy_ltf_average_is_stable_at_extreme_common_gain() raises:
    """Two finite L-LTF spectra must not overflow while being averaged."""
    var payload = _payload_octets(205, 48)
    var tx = wifi_he_eht_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_HE, 10, symbol_index=5
    )
    var observation = tx.packet_waveform.copy()
    var gain = 9.0e307
    for index in range(len(observation)):
        observation[index] = Complex64(
            observation[index].re * gain,
            observation[index].im * gain,
        )
        assert_true(isfinite(observation[index].re))
        assert_true(isfinite(observation[index].im))
    var rx = wifi_he_eht_acquisition_rx_20mhz(
        Span(observation),
        WIFI_PHY_HE,
        10,
        len(payload),
        symbol_index=5,
        llr_noise_variance=1.0e-8,
        max_iterations=10,
    )
    assert_true(rx.signal_ok)
    assert_true(rx.data.fcs_ok)
    assert_equal(rx.data.payload_bits, payload)
    for value in rx.legacy_channel_estimate:
        assert_true(isfinite(value.re))
        assert_true(isfinite(value.im))


def test_acquired_he_eht_edges_and_nonfinite_inputs() raises:
    var payload = _payload_octets(205, 17)
    with assert_raises():
        _ = wifi_he_eht_acquisition_tx_20mhz(
            Span(payload), WIFI_PHY_HT, 10
        )
    with assert_raises():
        _ = wifi_he_eht_acquisition_tx_20mhz(
            Span(payload), WIFI_PHY_HE, 9
        )
    var non_octet: List[UInt8] = [0, 1, 0]
    with assert_raises():
        _ = wifi_he_eht_acquisition_tx_20mhz(
            Span(non_octet), WIFI_PHY_HE, 10
        )

    var ltf = wifi_ltf_waveform_20mhz(WIFI_PHY_HE)
    with assert_raises():
        _ = wifi_he_eht_ltf_fine_timing_20mhz(
            Span(ltf), WIFI_PHY_HT, 0
        )
    with assert_raises():
        _ = wifi_he_eht_ltf_fine_timing_20mhz(
            Span(ltf), WIFI_PHY_HE, 0, search_radius=-1
        )
    var short: List[Complex64] = [Complex64(1.0, 0.0)]
    with assert_raises():
        _ = wifi_he_eht_ltf_fine_cfo_20mhz(Span(short), 0)
    var nonfinite_ltf = ltf.copy()
    nonfinite_ltf[7] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_he_eht_ltf_fine_timing_20mhz(
            Span(nonfinite_ltf), WIFI_PHY_HE, 0
        )
    nonfinite_ltf = ltf.copy()
    nonfinite_ltf[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_he_eht_ltf_fine_cfo_20mhz(Span(nonfinite_ltf), 0)

    var empty = List[Complex64]()
    with assert_raises():
        _ = wifi_he_eht_acquisition_rx_20mhz(
            Span(empty), WIFI_PHY_HE, 10, len(payload)
        )
    with assert_raises():
        _ = wifi_he_eht_acquisition_rx_20mhz(
            Span(empty),
            WIFI_PHY_HE,
            10,
            len(payload),
            detection_threshold=nan[DType.float64](),
        )
    with assert_raises():
        _ = wifi_he_eht_acquisition_rx_20mhz(
            Span(empty),
            WIFI_PHY_HE,
            10,
            len(payload),
            llr_noise_variance=inf[DType.float64](),
        )
    var nonfinite: List[Complex64] = [
        Complex64(nan[DType.float64](), 0.0)
    ]
    with assert_raises():
        _ = wifi_he_eht_acquisition_rx_20mhz(
            Span(nonfinite), WIFI_PHY_HE, 10, len(payload)
        )
    var tx = wifi_he_eht_acquisition_tx_20mhz(
        Span(payload), WIFI_PHY_HE, 10
    )
    with assert_raises():
        _ = wifi_he_eht_acquisition_rx_20mhz(
            Span(tx.packet_waveform),
            WIFI_PHY_HE,
            10,
            len(payload),
            max_iterations=0,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
