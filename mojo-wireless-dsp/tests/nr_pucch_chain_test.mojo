"""End-to-end acceptance tests for the bounded PUCCH format-2 chain."""

from std.collections import Span
from std.math import sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.nr.pucch_chain import (
    NRPUCCHFormat2Config,
    nr_pucch_format2_coded_bit_capacity,
    nr_pucch_format2_bits_checksum,
    nr_pucch_format2_reference_dmrs,
    nr_pucch_format2_waveform_sample_count,
    nr_pucch_format2_grid_to_waveform,
    nr_pucch_format2_waveform_to_grid,
    nr_pucch_format2_encode,
    nr_pucch_format2_flat_channel,
    nr_pucch_format2_descramble_llrs,
    nr_pucch_format2_decode,
)
from wireless_dsp.wireless.nr.uci import NR_UCI_SCHEME_POLAR


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _assert_checkpoint_metadata(
    metadata: List[CheckpointMetadata],
    testcase_id: StringSlice,
    stages: List[String],
    dtypes: List[String],
    shapes: List[String],
    strides: List[String],
    q_formats: List[String],
    layouts: List[String],
) raises:
    assert_equal(len(metadata), len(stages))
    assert_equal(len(metadata), len(dtypes))
    assert_equal(len(metadata), len(shapes))
    assert_equal(len(metadata), len(strides))
    assert_equal(len(metadata), len(q_formats))
    assert_equal(len(metadata), len(layouts))
    for index in range(len(metadata)):
        assert_equal(metadata[index].testcase_id, testcase_id)
        assert_equal(metadata[index].stage, stages[index])
        assert_equal(metadata[index].dtype, dtypes[index])
        assert_equal(metadata[index].shape, shapes[index])
        assert_equal(metadata[index].stride, strides[index])
        assert_equal(metadata[index].q_format, q_formats[index])
        assert_equal(metadata[index].scale, 1.0)
        assert_equal(metadata[index].version, 1)
        assert_equal(metadata[index].layout, layouts[index])


def _payload(length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(UInt8((5 * index + index // 3 + 1) & 1))
    return result^


def _reference_bits_checksum(bits: Span[UInt8, ...]) -> UInt64:
    # Test-local FNV-1a traversal.  It accepts only test-generated binary data
    # and does not call the production checkpoint helper or an encoder.
    var result = UInt64(14695981039346656037)
    for index in range(len(bits)):
        result = (result ^ UInt64(bits[index])) * UInt64(1099511628211)
    return result


def test_format2_geometry_and_checksum_independent_integer_oracles() raises:
    for length in [0, 1, 2, 7, 31, 257]:
        var bits = _payload(length)
        assert_equal(
            nr_pucch_format2_bits_checksum(Span(bits)),
            _reference_bits_checksum(Span(bits)),
        )

    # Independently sum the normal-CP formula for both supported allocation
    # lengths across representative FFT sizes, numerologies, and slot phases.
    for fft_size in [128, 256, 2048]:
        for numerology in [0, 2, 4]:
            for symbol_count in [1, 2]:
                var slot_in_frame = 10 * (1 << numerology) - 1
                var start_symbol = 14 - symbol_count
                var config = NRPUCCHFormat2Config(
                    fft_size,
                    numerology,
                    slot_in_frame,
                    start_symbol,
                    symbol_count,
                    0,
                    73,
                    321,
                    0x1234,
                )
                assert_equal(
                    nr_pucch_format2_coded_bit_capacity(config),
                    16 * symbol_count,
                )
                var slot_in_subframe = (
                    slot_in_frame % (1 << numerology)
                )
                var expected_samples = 0
                for local_symbol in range(symbol_count):
                    var symbol = start_symbol + local_symbol
                    var base = 144 * fft_size // 2048
                    var extension = (
                        16 * (1 << numerology) * fft_size // 2048
                    )
                    var absolute_symbol = (
                        14 * slot_in_subframe + symbol
                    )
                    var cp = (
                        base + extension
                        if absolute_symbol % (7 * (1 << numerology)) == 0
                        else base
                    )
                    expected_samples += fft_size + cp
                assert_equal(
                    nr_pucch_format2_waveform_sample_count(config),
                    expected_samples,
                )


def test_static_dmrs_coding_and_grid_checkpoints() raises:
    """Check independent DM-RS signs and every format-2 RE position."""
    var config = NRPUCCHFormat2Config(
        128, 0, 7, 9, 1, 24, 73, 321, 0x1234
    )
    assert_equal(nr_pucch_format2_coded_bit_capacity(config), 16)
    assert_equal(nr_pucch_format2_waveform_sample_count(config), 137)

    # Independently generated from the x1/x2 recurrences after Nc=1600 for
    # c_init=0x1e880282 (TS 38.211 6.4.1.3.2.1).  These are the four DM-RS
    # values in the one allocated PRB at k=1,4,7,10.
    var dmrs = nr_pucch_format2_reference_dmrs(config)
    var scale = 1.0 / sqrt(2.0)
    var expected_dmrs: List[Complex64] = [
        Complex64(-scale, -scale),
        Complex64(-scale, -scale),
        Complex64(-scale, -scale),
        Complex64(-scale, -scale),
    ]
    assert_equal(len(dmrs), 4)
    for index in range(4):
        _assert_complex_close(dmrs[index], expected_dmrs[index], 1.0e-12)

    var payload: List[UInt8] = [1, 0, 1, 1, 0, 0, 1]
    var transmit = nr_pucch_format2_encode(Span(payload), config)
    assert_equal(transmit.payload, payload)
    assert_equal(len(transmit.coded_bits), 16)
    assert_equal(len(transmit.scrambled_bits), 16)
    assert_equal(len(transmit.data_symbols), 8)
    assert_equal(len(transmit.dmrs), 4)
    assert_equal(len(transmit.waveform), 137)
    var tx_stages: List[String] = [
        "payload",
        "coded-bits",
        "scrambled-bits",
        "data-symbols",
        "dmrs",
        "transmit-grid",
        "waveform",
    ]
    var tx_dtypes: List[String] = [
        "uint8",
        "uint8",
        "uint8",
        "complex64",
        "complex64",
        "complex64",
        "complex64",
    ]
    var tx_shapes: List[String] = [
        "7", "16", "16", "8", "4", "14x128", "137"
    ]
    var tx_strides: List[String] = [
        "1", "1", "1", "1", "1", "128,1", "1"
    ]
    var tx_q_formats: List[String] = [
        "binary-u1",
        "binary-u1",
        "binary-u1",
        "floating",
        "floating",
        "floating",
        "floating",
    ]
    var tx_layouts: List[String] = [
        "bit-per-byte",
        "bit-per-byte",
        "bit-per-byte",
        "iq-interleaved",
        "iq-interleaved",
        "row-major-iq-interleaved",
        "iq-interleaved",
    ]
    _assert_checkpoint_metadata(
        transmit.checkpoint_metadata,
        "nr-pucch-format2-tx",
        tx_stages,
        tx_dtypes,
        tx_shapes,
        tx_strides,
        tx_q_formats,
        tx_layouts,
    )
    assert_equal(transmit.payload_checksum, UInt64(0x1EECD6AC8BCD4751))
    # The two coded-stage checksums are static vector checkpoints; their exact
    # values also prove scrambling did more than preserve the final payload.
    assert_equal(
        transmit.coded_bits_checksum,
        UInt64(0x572B79EC22515421),
    )
    assert_equal(
        transmit.scrambled_bits_checksum,
        UInt64(0xBC446D3C180D9B7D),
    )
    assert_equal(
        nr_pucch_format2_bits_checksum(Span(transmit.coded_bits)),
        transmit.coded_bits_checksum,
    )
    assert_true(
        transmit.coded_bits_checksum != transmit.scrambled_bits_checksum
    )
    assert_true(transmit.grid_energy > 11.999999999)
    assert_true(transmit.grid_energy < 12.000000001)
    assert_true(transmit.waveform_energy > 0.0)
    var direct_waveform = nr_pucch_format2_grid_to_waveform(
        config, transmit.grid
    )
    assert_equal(len(direct_waveform), len(transmit.waveform))
    for index in range(len(direct_waveform)):
        _assert_complex_close(
            direct_waveform[index], transmit.waveform[index], 0.0
        )

    var data_index = 0
    var dmrs_index = 0
    for local_subcarrier in range(12):
        var actual = transmit.grid[9, 24 + local_subcarrier]
        if local_subcarrier % 3 == 1:
            _assert_complex_close(actual, dmrs[dmrs_index], 0.0)
            dmrs_index += 1
        else:
            _assert_complex_close(
                actual, transmit.data_symbols[data_index], 0.0
            )
            data_index += 1
    _assert_complex_close(transmit.grid[9, 23], Complex64(0.0), 0.0)
    _assert_complex_close(transmit.grid[9, 36], Complex64(0.0), 0.0)

    var recovered = nr_pucch_format2_waveform_to_grid(
        config, Span(transmit.waveform)
    )
    for subcarrier in range(128):
        _assert_complex_close(
            recovered[9, subcarrier], transmit.grid[9, subcarrier], 1.0e-10
        )


def test_noiseless_crc6_polar_full_waveform_recovery() raises:
    var config = NRPUCCHFormat2Config(
        128, 1, 13, 3, 2, 48, 617, 50000, 0x7012
    )
    var payload = _payload(12)
    var transmit = nr_pucch_format2_encode(Span(payload), config)
    assert_equal(transmit.uci_scheme, NR_UCI_SCHEME_POLAR)
    assert_equal(len(transmit.coded_bits), 32)
    assert_equal(len(transmit.data_symbols), 16)
    assert_equal(len(transmit.dmrs), 8)
    assert_equal(len(transmit.waveform), 274)

    var gain = Complex64(0.75, -0.35)
    var received = nr_pucch_format2_flat_channel(
        Span(transmit.waveform), gain
    )
    var decoded = nr_pucch_format2_decode(
        Span(received),
        config,
        len(payload),
        0.0,
        testcase_id="nr-pucch-f2-chain-integration",
    )
    assert_equal(decoded.payload, payload)
    assert_true(decoded.crc_ok and decoded.parity_ok)
    assert_equal(decoded.uci_scheme, NR_UCI_SCHEME_POLAR)
    assert_equal(decoded.code_blocks, 1)
    assert_equal(len(decoded.received_dmrs), 8)
    assert_equal(len(decoded.dmrs_ls_estimates), 8)
    assert_equal(len(decoded.raw_llrs), 32)
    assert_equal(len(decoded.descrambled_llrs), 32)
    assert_equal(len(decoded.checkpoint_metadata), 9)
    for index in range(len(decoded.checkpoint_metadata)):
        assert_equal(
            decoded.checkpoint_metadata[index].testcase_id,
            "nr-pucch-f2-chain-integration",
        )
        assert_true(
            decoded.checkpoint_metadata[index].stage.byte_length() > 0
        )
        assert_true(
            decoded.checkpoint_metadata[index].dtype.byte_length() > 0
        )
        assert_true(
            decoded.checkpoint_metadata[index].shape.byte_length() > 0
        )
        assert_true(
            decoded.checkpoint_metadata[index].stride.byte_length() > 0
        )
        assert_true(
            decoded.checkpoint_metadata[index].q_format.byte_length() > 0
        )
        assert_equal(decoded.checkpoint_metadata[index].scale, 1.0)
        assert_equal(decoded.checkpoint_metadata[index].version, 1)
        assert_true(
            decoded.checkpoint_metadata[index].layout.byte_length() > 0
        )
    assert_equal(decoded.checkpoint_metadata[0].stage, "received-grid")
    assert_equal(decoded.checkpoint_metadata[0].dtype, "complex64")
    assert_equal(decoded.checkpoint_metadata[0].shape, "14x128")
    assert_equal(decoded.checkpoint_metadata[0].stride, "128,1")
    assert_equal(decoded.checkpoint_metadata[0].q_format, "floating")
    assert_equal(
        decoded.checkpoint_metadata[0].layout,
        "row-major-iq-interleaved",
    )
    assert_equal(decoded.checkpoint_metadata[1].stage, "received-dmrs")
    assert_equal(decoded.checkpoint_metadata[2].stage, "dmrs-ls-estimates")
    assert_equal(decoded.checkpoint_metadata[3].stage, "channel-estimate")
    assert_equal(decoded.checkpoint_metadata[3].shape, "1")
    assert_equal(decoded.checkpoint_metadata[4].stage, "equalized-symbols")
    assert_equal(decoded.checkpoint_metadata[5].stage, "raw-llrs")
    assert_equal(decoded.checkpoint_metadata[6].stage, "descrambled-llrs")
    assert_equal(decoded.checkpoint_metadata[7].stage, "hard-coded-bits")
    assert_equal(decoded.checkpoint_metadata[8].stage, "payload")
    assert_equal(decoded.checkpoint_metadata[8].dtype, "uint8")
    assert_equal(decoded.checkpoint_metadata[8].q_format, "binary-u1")
    assert_equal(decoded.checkpoint_metadata[8].layout, "bit-per-byte")
    for index in range(1, len(decoded.checkpoint_metadata)):
        assert_equal(decoded.checkpoint_metadata[index].stride, "1")
    assert_equal(decoded.hard_coded_bits, transmit.coded_bits)
    assert_equal(
        decoded.hard_coded_bits_checksum, transmit.coded_bits_checksum
    )
    _assert_complex_close(decoded.channel_estimate, gain, 1.0e-10)
    for index in range(len(transmit.data_symbols)):
        _assert_complex_close(
            decoded.equalized_symbols[index],
            transmit.data_symbols[index],
            1.0e-10,
        )
    assert_true(decoded.decision_directed_evm < 1.0e-10)
    assert_true(decoded.maximum_symbol_error < 1.0e-10)
    assert_equal(decoded.equalized_noise_variance, 1.0e-12)

    # A tiny but finite channel is not singular.  Its raw squared magnitude
    # underflows, so this also locks the scale-safe LS/ZF contract.
    var tiny_gain = Complex64(1.0e-200, -0.5e-200)
    var tiny_received = nr_pucch_format2_flat_channel(
        Span(transmit.waveform), tiny_gain
    )
    var tiny_decoded = nr_pucch_format2_decode(
        Span(tiny_received), config, len(payload), 0.0
    )
    assert_equal(tiny_decoded.payload, payload)
    assert_true(tiny_decoded.crc_ok and tiny_decoded.parity_ok)
    assert_true(
        abs(tiny_decoded.channel_estimate.re / tiny_gain.re - 1.0)
        <= 2.0e-12
    )
    assert_true(
        abs(tiny_decoded.channel_estimate.im / tiny_gain.im - 1.0)
        <= 2.0e-12
    )

    # A tiny channel with enormous input noise has an unrepresentable
    # equalized variance and must be rejected before soft demapping.
    with assert_raises():
        _ = nr_pucch_format2_decode(
            Span(tiny_received), config, len(payload), 1.0e308
        )

    # Conversely, a huge channel and tiny noise produce a variance below the
    # supported LLR floor rather than a negative/garbage ldexp result.
    var huge_gain = Complex64(1.0e150, 0.0)
    var huge_received = nr_pucch_format2_flat_channel(
        Span(transmit.waveform), huge_gain
    )
    var huge_decoded = nr_pucch_format2_decode(
        Span(huge_received), config, len(payload), 1.0e-300
    )
    assert_equal(huge_decoded.equalized_noise_variance, 1.0e-12)
    assert_true(huge_decoded.crc_ok)
    assert_equal(huge_decoded.payload, payload)

    var minimum_noise_decoded = nr_pucch_format2_decode(
        Span(transmit.waveform), config, len(payload), 5.0e-324
    )
    assert_equal(minimum_noise_decoded.equalized_noise_variance, 1.0e-12)
    assert_true(minimum_noise_decoded.crc_ok)


def test_seeded_flat_awgn_recovery_and_quality_checkpoints() raises:
    var config = NRPUCCHFormat2Config(
        256, 2, 31, 10, 2, 120, 77, 4095, 0xACE1
    )
    var payload = _payload(10)
    var transmit = nr_pucch_format2_encode(Span(payload), config)
    var gain = Complex64(0.62, 0.27)
    comptime noise_variance = 1.0e-7
    var received_a = nr_pucch_format2_flat_channel(
        Span(transmit.waveform), gain,
        noise_variance=noise_variance, seed=UInt64(0xD15EA5E),
    )
    var received_b = nr_pucch_format2_flat_channel(
        Span(transmit.waveform), gain,
        noise_variance=noise_variance, seed=UInt64(0xD15EA5E),
    )
    assert_equal(received_a, received_b)
    var decoded = nr_pucch_format2_decode(
        Span(received_a), config, len(payload), noise_variance
    )
    assert_equal(decoded.payload, payload)
    assert_true(decoded.crc_ok and decoded.parity_ok)
    assert_equal(decoded.hard_coded_bits, transmit.coded_bits)
    assert_equal(
        decoded.hard_coded_bits_checksum, transmit.coded_bits_checksum
    )
    _assert_complex_close(decoded.channel_estimate, gain, 0.01)
    assert_true(decoded.equalized_noise_variance > 0.0)
    assert_true(decoded.decision_directed_evm > 0.0)
    assert_true(decoded.decision_directed_evm < 0.05)
    assert_true(decoded.maximum_symbol_error > 0.0)
    assert_true(decoded.maximum_symbol_error < 0.1)


def test_soft_descrambling_signs_are_explicit_checkpoint() raises:
    var llrs: List[Float64] = [1.0, -2.0, 3.0, -4.0, 5.0, -6.0]
    var descrambled = nr_pucch_format2_descramble_llrs(
        Span(llrs), 0x1234, 73
    )
    # Static Gold prefix for c_init=RNTI*2^10+n_ID.
    var expected: List[Float64] = [
        -1.0, 2.0, -3.0, -4.0, 5.0, 6.0,
    ]
    assert_equal(descrambled, expected)


def test_format2_chain_rejects_unsupported_profiles() raises:
    with assert_raises():
        _ = NRPUCCHFormat2Config(
            64, 0, 0, 0, 1, 0, 1, 1, 1
        )
    with assert_raises():
        _ = NRPUCCHFormat2Config(
            128, 0, 0, 0, 3, 0, 1, 1, 1
        )
    with assert_raises():
        _ = NRPUCCHFormat2Config(
            128, 0, 0, 0, 1, 1, 1, 1, 1
        )
    with assert_raises():
        _ = NRPUCCHFormat2Config(
            128, 0, 10, 0, 1, 0, 1, 1, 1
        )

    var config = NRPUCCHFormat2Config(
        128, 0, 0, 0, 1, 0, 1, 1, 1
    )
    var short_payload: List[UInt8] = [0, 1]
    with assert_raises():
        _ = nr_pucch_format2_encode(Span(short_payload), config)
    var wrong_waveform = List[Complex64](length=8, fill=Complex64(0.0))
    with assert_raises():
        _ = nr_pucch_format2_decode(
            Span(wrong_waveform), config, 3, 0.0
        )
    with assert_raises():
        _ = nr_pucch_format2_flat_channel(
            Span(wrong_waveform), Complex64(0.0)
        )
    with assert_raises():
        _ = nr_pucch_format2_flat_channel(
            Span(wrong_waveform), Complex64(1.0), noise_variance=-1.0
        )
    with assert_raises():
        _ = nr_pucch_format2_flat_channel(
            Span(wrong_waveform), Complex64(nan[DType.float64]())
        )
    with assert_raises():
        _ = nr_pucch_format2_flat_channel(
            Span(wrong_waveform),
            Complex64(1.0),
            noise_variance=inf[DType.float64](),
        )
    with assert_raises():
        _ = nr_pucch_format2_decode(
            Span(wrong_waveform),
            config,
            3,
            nan[DType.float64](),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
