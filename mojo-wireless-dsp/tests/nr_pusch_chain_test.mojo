from std.collections import Span
from std.math import sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.nr.uplink import (
    nr_pusch_scramble,
    nr_pusch_dmrs_c_init,
)
from wireless_dsp.wireless.nr.ldpc_profile import nr_ldpc_profile
from wireless_dsp.wireless.nr.pusch_chain import (
    NRPUSCHConfig,
    nr_pusch_allocation_subcarriers,
    nr_pusch_data_re_count,
    nr_pusch_coded_bit_capacity,
    nr_pusch_reference_dmrs,
    nr_map_pusch_single_layer,
    nr_pusch_grid_to_waveform,
    nr_pusch_waveform_to_grid,
    nr_pusch_encode_transport_block,
    nr_pusch_decode_waveform,
)


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def _payload(length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for i in range(length):
        result.append(UInt8((11 * i + i // 3 + 1) & 1))
    return result^


def _apply_flat_channel(
    samples: Span[Complex64, ...], gain: Complex64
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(samples))
    for i in range(len(samples)):
        var sample = Complex64(samples[i].re, samples[i].im)
        result.append(sample * gain)
    return result^


def _length_text(length: Int) -> String:
    var result = String()
    result.write(length)
    return result^


def _matrix_shape(rows: Int, columns: Int) -> String:
    var result = String()
    result.write(rows, "x", columns)
    return result^


def _matrix_stride(columns: Int) -> String:
    var result = String()
    result.write(columns, ",1")
    return result^


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
        assert_equal(metadata[index].layout, layouts[index])
        assert_equal(metadata[index].scale, 1.0)
        assert_equal(metadata[index].version, 1)


def test_static_gold_and_cp_ofdm_dmrs_vectors() raises:
    """Independent bit/sign vectors generated from 38.211 recurrences."""
    var zero = List[UInt8](length=32, fill=UInt8(0))
    var gold = nr_pusch_scramble(Span(zero), 0x1234, 0, 17)
    var expected_gold: List[UInt8] = [
        0, 0, 1, 0, 1, 0, 1, 0,
        0, 0, 1, 1, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 0, 0, 0,
        0, 1, 1, 1, 0, 1, 0, 1,
    ]
    assert_equal(gold, expected_gold)

    var config = NRPUSCHConfig(
        64, 8, 5, 2, 8, 2, 3, 17, 1, 0x1234
    )
    assert_equal(nr_pusch_dmrs_c_init(3, 2, 17, 1), UInt32(206438435))
    var dmrs = nr_pusch_reference_dmrs(config)
    var signs_i: List[Int] = [1, -1, 1, 1, -1, 1, -1, 1]
    var signs_q: List[Int] = [-1, 1, -1, -1, 1, 1, -1, -1]
    var scale = 1.0 / sqrt(2.0)
    for i in range(8):
        _assert_complex_close(
            dmrs[i],
            Complex64(Float64(signs_i[i]) * scale, Float64(signs_q[i]) * scale),
            1.0e-12,
        )


def test_static_transform_precoded_dmrs_and_grid_checkpoints() raises:
    # N_ID=30 selects group u=0, v=0.  These signs come directly from the
    # first row of TS 38.211 Table 5.2.2.2-1 (M_ZC=6).
    var config = NRPUSCHConfig(
        32, 4, 3, 1, 4, 1, 0, 30, 0, 0x44,
        transform_precoding=True,
    )
    var dmrs = nr_pusch_reference_dmrs(config)
    var phi: List[Int] = [-3, -1, 3, 3, -1, -3]
    var scale = 1.0 / sqrt(2.0)
    for i in range(6):
        var p = phi[i]
        var expected: Complex64
        if p == 1:
            expected = Complex64(scale, scale)
        elif p == 3:
            expected = Complex64(-scale, scale)
        elif p == -1:
            expected = Complex64(scale, -scale)
        else:
            expected = Complex64(-scale, -scale)
        _assert_complex_close(dmrs[i], expected, 1.0e-12)

    var data = List[Complex64](capacity=24)
    for i in range(24):
        data.append(Complex64(Float64(i + 1), -Float64(i + 1)))
    var grid = nr_map_pusch_single_layer(config, Span(data), Span(dmrs))
    _assert_complex_close(grid[0, 4], data[0], 0.0)
    _assert_complex_close(grid[0, 15], data[11], 0.0)
    _assert_complex_close(grid[1, 4], dmrs[0], 0.0)
    _assert_complex_close(grid[1, 14], dmrs[5], 0.0)
    _assert_complex_close(grid[1, 15], Complex64(0.0), 0.0)
    _assert_complex_close(grid[2, 4], data[12], 0.0)
    _assert_complex_close(grid[2, 15], data[23], 0.0)
    _assert_complex_close(grid[0, 3], Complex64(0.0), 0.0)

    var waveform = nr_pusch_grid_to_waveform(config, grid)
    var recovered = nr_pusch_waveform_to_grid(config, Span(waveform))
    for symbol in range(config.symbol_count):
        for subcarrier in range(config.fft_size):
            _assert_complex_close(
                recovered[symbol, subcarrier], grid[symbol, subcarrier], 1.0e-10
            )


def test_pusch_geometry_exact_integer_oracles() raises:
    # This is a direct accounting oracle, separate from every encoder/decoder
    # chain: one complete DM-RS row is removed and Qm scales the remaining RE.
    for symbol_count in [2, 3, 5, 14]:
        for resource_blocks in [1, 2, 4, 8]:
            var config = NRPUSCHConfig(
                128,
                8,
                symbol_count,
                0,
                0,
                resource_blocks,
                0,
                1,
                0,
                1,
            )
            var allocation_subcarriers = 12 * resource_blocks
            var data_re = (symbol_count - 1) * allocation_subcarriers
            assert_equal(
                nr_pusch_allocation_subcarriers(config),
                allocation_subcarriers,
            )
            assert_equal(nr_pusch_data_re_count(config), data_re)
            for modulation_order in [2, 4, 6, 8, 10]:
                assert_equal(
                    nr_pusch_coded_bit_capacity(
                        config, modulation_order
                    ),
                    data_re * modulation_order,
                )


def test_complete_cp_ofdm_pusch_qpsk_rv0_waveform() raises:
    comptime payload_bits = 80
    comptime modulation_order = 2
    comptime redundancy_version = 0
    var config = NRPUSCHConfig(
        64, 8, 14, 2, 4, 4, 3, 42, 0, 0x1234
    )
    assert_equal(nr_pusch_allocation_subcarriers(config), 48)
    assert_equal(nr_pusch_data_re_count(config), 624)
    assert_equal(nr_pusch_coded_bit_capacity(config, modulation_order), 1248)
    var payload = _payload(payload_bits)
    var transmit = nr_pusch_encode_transport_block(
        Span(payload), 0.5, modulation_order, redundancy_version, config
    )
    assert_equal(len(transmit.rate_matched_bits), 1248)
    assert_equal(len(transmit.scrambled_bits), 1248)
    assert_equal(len(transmit.modulated_symbols), 624)
    assert_equal(len(transmit.mapped_data_symbols), 624)
    assert_equal(len(transmit.dmrs), 24)
    assert_equal(len(transmit.waveform), 14 * 72)
    var tx_stages: List[String] = [
        "payload-input",
        "transport-block-with-crc",
        "encoded-null-mask",
        "rate-matched-bits",
        "scrambled-bits",
        "modulated-symbols",
        "mapped-data-symbols",
        "dmrs",
        "resource-grid",
        "waveform",
    ]
    var tx_dtypes: List[String] = [
        "uint8", "uint8", "uint8", "uint8", "uint8",
        "complex64", "complex64", "complex64", "complex64", "complex64",
    ]
    var tx_shapes: List[String] = [
        _length_text(len(payload)),
        _length_text(len(transmit.transport_block)),
        _length_text(len(transmit.encoded_null_mask)),
        _length_text(len(transmit.rate_matched_bits)),
        _length_text(len(transmit.scrambled_bits)),
        _length_text(len(transmit.modulated_symbols)),
        _length_text(len(transmit.mapped_data_symbols)),
        _length_text(len(transmit.dmrs)),
        _matrix_shape(config.symbol_count, config.fft_size),
        _length_text(len(transmit.waveform)),
    ]
    var tx_strides: List[String] = [
        "1", "1", "1", "1", "1", "1", "1", "1",
        _matrix_stride(config.fft_size),
        "1",
    ]
    var tx_q_formats: List[String] = [
        "binary-u1", "binary-u1", "binary-u1", "binary-u1", "binary-u1",
        "floating", "floating", "floating", "floating", "floating",
    ]
    var tx_layouts: List[String] = [
        "bit-per-byte", "bit-per-byte", "bit-per-byte", "bit-per-byte",
        "bit-per-byte", "iq-interleaved", "iq-interleaved",
        "iq-interleaved", "row-major-iq-interleaved", "iq-interleaved",
    ]
    _assert_checkpoint_metadata(
        transmit.checkpoint_metadata,
        "nr-pusch-tx",
        tx_stages,
        tx_dtypes,
        tx_shapes,
        tx_strides,
        tx_q_formats,
        tx_layouts,
    )

    var gain = Complex64(0.8, 0.3)
    var received = _apply_flat_channel(Span(transmit.waveform), gain)
    var decoded = nr_pusch_decode_waveform(
        Span(received),
        config,
        Span(transmit.encoded_null_mask),
        transmit.profile,
        payload_bits,
        modulation_order,
        redundancy_version,
        0.01,
    )
    assert_true(decoded.ldpc_converged)
    assert_true(decoded.code_block_crc_ok)
    assert_true(decoded.transport_crc_ok)
    assert_equal(decoded.payload, payload)
    var rx_stages: List[String] = [
        "received-waveform",
        "received-grid",
        "channel-estimate",
        "equalized-symbols",
        "demapper-llrs",
        "descrambled-llrs",
        "rate-recovered-llrs",
        "ldpc-iterations",
        "decoded-transport-block",
        "decoded-payload",
        "transport-crc-ok",
        "code-block-crc-ok",
        "ldpc-converged",
    ]
    var rx_dtypes: List[String] = [
        "complex64", "complex64", "complex64", "complex64",
        "float64", "float64", "float64", "int", "uint8", "uint8",
        "bool", "bool", "bool",
    ]
    var rx_shapes: List[String] = [
        _length_text(len(received)),
        _matrix_shape(
            decoded.received_grid.symbol_count,
            decoded.received_grid.subcarrier_count,
        ),
        _length_text(len(decoded.channel_estimate)),
        _length_text(len(decoded.equalized_symbols)),
        _length_text(len(decoded.demapper_llrs)),
        _length_text(len(decoded.descrambled_llrs)),
        _length_text(len(decoded.rate_recovered_llrs)),
        _length_text(len(decoded.iterations)),
        _length_text(len(decoded.transport_block)),
        _length_text(len(decoded.payload)),
        "1", "1", "1",
    ]
    var rx_strides: List[String] = [
        "1", _matrix_stride(config.fft_size),
        "1", "1", "1", "1", "1", "1", "1", "1", "1", "1", "1",
    ]
    var rx_q_formats: List[String] = [
        "floating", "floating", "floating", "floating", "floating",
        "floating", "floating", "integer", "binary-u1", "binary-u1",
        "boolean", "boolean", "boolean",
    ]
    var rx_layouts: List[String] = [
        "iq-interleaved", "row-major-iq-interleaved", "iq-interleaved",
        "iq-interleaved", "linear", "linear", "linear", "linear",
        "bit-per-byte", "bit-per-byte", "scalar", "scalar", "scalar",
    ]
    _assert_checkpoint_metadata(
        decoded.checkpoint_metadata,
        "nr-pusch-rx",
        rx_stages,
        rx_dtypes,
        rx_shapes,
        rx_strides,
        rx_q_formats,
        rx_layouts,
    )
    assert_equal(decoded.received_grid.symbol_count, config.symbol_count)
    assert_equal(decoded.received_grid.subcarrier_count, config.fft_size)
    assert_equal(
        len(decoded.channel_estimate), nr_pusch_allocation_subcarriers(config)
    )
    assert_equal(len(decoded.demapper_llrs), len(decoded.descrambled_llrs))
    assert_equal(
        len(decoded.rate_recovered_llrs), len(transmit.encoded_null_mask)
    )
    for i in range(len(transmit.modulated_symbols)):
        _assert_complex_close(
            decoded.equalized_symbols[i], transmit.modulated_symbols[i], 1.0e-9
        )


def test_complete_dft_s_ofdm_pusch_16qam_rv2_waveform() raises:
    comptime payload_bits = 48
    comptime modulation_order = 4
    comptime redundancy_version = 2
    var config = NRPUSCHConfig(
        64, 8, 14, 3, 16, 1, 5, 61, 1, 0x4567,
        transform_precoding=True,
        dmrs_cyclic_shift=5,
    )
    assert_equal(nr_pusch_coded_bit_capacity(config, modulation_order), 624)
    var payload = _payload(payload_bits)
    var transmit = nr_pusch_encode_transport_block(
        Span(payload), 0.4, modulation_order, redundancy_version, config
    )
    assert_equal(len(transmit.dmrs), 6)
    assert_equal(len(transmit.modulated_symbols), 156)
    assert_equal(len(transmit.mapped_data_symbols), 156)
    # DFT spreading preserves energy but changes the first nonconstant block.
    var before = 0.0
    var after = 0.0
    var changed = False
    for i in range(12):
        before += transmit.modulated_symbols[i].magnitude_squared()
        after += transmit.mapped_data_symbols[i].magnitude_squared()
        changed = changed or (
            abs(transmit.modulated_symbols[i].re - transmit.mapped_data_symbols[i].re)
            > 1.0e-8
        ) or (
            abs(transmit.modulated_symbols[i].im - transmit.mapped_data_symbols[i].im)
            > 1.0e-8
        )
    assert_true(abs(before - after) < 1.0e-9)
    assert_true(changed)

    var gain = Complex64(0.65, -0.25)
    var received = _apply_flat_channel(Span(transmit.waveform), gain)
    var decoded = nr_pusch_decode_waveform(
        Span(received),
        config,
        Span(transmit.encoded_null_mask),
        transmit.profile,
        payload_bits,
        modulation_order,
        redundancy_version,
        0.01,
    )
    assert_true(decoded.ldpc_converged)
    assert_true(decoded.code_block_crc_ok)
    assert_true(decoded.transport_crc_ok)
    assert_equal(decoded.payload, payload)
    for i in range(len(transmit.modulated_symbols)):
        _assert_complex_close(
            decoded.equalized_symbols[i], transmit.modulated_symbols[i], 1.0e-8
        )


def test_cp_ofdm_all_qam_orders_and_redundancy_versions() raises:
    """Exercise Qm={2,4,6,8,10} and every standardized LDPC RV."""
    comptime payload_bits = 32
    var config = NRPUSCHConfig(
        64, 8, 5, 1, 8, 4, 1, 77, 0, 0x7012,
        dmrs_n_id=50000,
    )
    var payload = _payload(payload_bits)
    var modulation_orders: List[Int] = [2, 4, 6, 8, 10]
    var redundancy_versions: List[Int] = [0, 1, 2, 3, 0]
    for test_index in range(len(modulation_orders)):
        var modulation_order = modulation_orders[test_index]
        var redundancy_version = redundancy_versions[test_index]
        var transmit = nr_pusch_encode_transport_block(
            Span(payload), 0.3, modulation_order, redundancy_version, config
        )
        var received = _apply_flat_channel(
            Span(transmit.waveform), Complex64(0.9, -0.1)
        )
        var decoded = nr_pusch_decode_waveform(
            Span(received),
            config,
            Span(transmit.encoded_null_mask),
            transmit.profile,
            payload_bits,
            modulation_order,
            redundancy_version,
            0.01,
        )
        assert_true(decoded.ldpc_converged)
        assert_true(decoded.code_block_crc_ok)
        assert_true(decoded.transport_crc_ok)
        assert_equal(decoded.payload, payload)


def test_pusch_chain_validation_boundaries() raises:
    with assert_raises():
        _ = NRPUSCHConfig(
            64, 8, 14, 2, 0, 2, 0, 1, 0, 1,
            transform_precoding=True,
        )
    with assert_raises():
        _ = NRPUSCHConfig(63, 8, 14, 2, 0, 1, 0, 1, 0, 1)
    var config = NRPUSCHConfig(64, 8, 2, 1, 0, 1, 0, 1, 0, 1)
    var payload = _payload(16)
    with assert_raises():
        _ = nr_pusch_encode_transport_block(Span(payload), 0.5, 1, 0, config)
    var too_short = List[Complex64](length=10, fill=Complex64(0.0))
    with assert_raises():
        _ = nr_pusch_waveform_to_grid(config, Span(too_short))
    var empty_mask = List[UInt8]()
    var profile = nr_ldpc_profile(16 + 24, 0.5)
    with assert_raises():
        _ = nr_pusch_decode_waveform(
            Span(too_short),
            config,
            Span(empty_mask),
            profile,
            16,
            2,
            0,
            nan[DType.float64](),
        )
    with assert_raises():
        _ = nr_pusch_decode_waveform(
            Span(too_short),
            config,
            Span(empty_mask),
            profile,
            16,
            2,
            0,
            inf[DType.float64](),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
