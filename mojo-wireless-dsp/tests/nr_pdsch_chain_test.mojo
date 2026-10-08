from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import ofdm_modulate, ofdm_demodulate
from wireless_dsp.testing import CheckpointMetadata
from wireless_dsp.wireless.nr import (
    NRResourceGrid,
    nr_pdsch_dmrs_c_init,
    nr_pdsch_dmrs,
    nr_map_pdsch_comb2,
    nr_pdsch_encode_transport_block,
    nr_pdsch_decode_grid_comb2,
)


def _payload(length: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for i in range(length):
        result.append(UInt8((i * 13 + i // 5 + 1) & 1))
    return result^


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


def test_complete_pdsch_waveform_rx_chain() raises:
    comptime payload_bits = 100
    comptime modulation_order = 2
    comptime output_bits = 480
    comptime allocation_size = 480
    comptime fft_size = 512
    comptime cyclic_prefix = 36
    comptime physical_cell_id = 42
    comptime rnti = 0x1234
    comptime slot = 3
    comptime dmrs_symbol = 2

    var payload = _payload(payload_bits)
    var transmit = nr_pdsch_encode_transport_block(
        Span(payload),
        0.5,
        modulation_order,
        0,
        output_bits,
        rnti,
        0,
        physical_cell_id,
    )
    assert_equal(len(transmit.transport_block), 116)
    assert_equal(len(transmit.encoded_null_mask), 1000)
    assert_equal(len(transmit.rate_matched_bits), 480)
    assert_equal(len(transmit.scrambled_bits), 480)
    assert_equal(len(transmit.symbols), allocation_size // 2)
    var tx_stages: List[String] = [
        "transport-block",
        "encoded-null-mask",
        "rate-matched-bits",
        "scrambled-bits",
        "qam-symbols",
    ]
    var tx_dtypes: List[String] = [
        "uint8", "uint8", "uint8", "uint8", "complex64"
    ]
    var tx_shapes: List[String] = ["116", "1000", "480", "480", "240"]
    var tx_q_formats: List[String] = [
        "binary-u1", "binary-u1", "binary-u1", "binary-u1", "floating"
    ]
    var tx_layouts: List[String] = [
        "bit-per-byte",
        "bit-per-byte",
        "bit-per-byte",
        "bit-per-byte",
        "iq-interleaved",
    ]
    _assert_checkpoint_metadata(
        transmit.checkpoint_metadata,
        "nr-pdsch-tx",
        tx_stages,
        tx_dtypes,
        tx_shapes,
        tx_q_formats,
        tx_layouts,
    )
    var c_init = nr_pdsch_dmrs_c_init(
        slot, dmrs_symbol, physical_cell_id, 0
    )
    var dmrs = nr_pdsch_dmrs(c_init, allocation_size // 2)
    var transmit_grid = NRResourceGrid(1, fft_size)
    nr_map_pdsch_comb2(
        transmit_grid,
        0,
        0,
        allocation_size,
        0,
        Span(transmit.symbols),
        Span(dmrs),
    )

    var spectrum = List[Complex64](capacity=fft_size)
    for subcarrier in range(fft_size):
        spectrum.append(transmit_grid[0, subcarrier])
    var waveform = ofdm_modulate(Span(spectrum), cyclic_prefix)
    var channel = Complex64(0.8, 0.3)
    for i in range(len(waveform)):
        waveform[i] = waveform[i] * channel
    var received_spectrum = ofdm_demodulate(
        Span(waveform), fft_size, cyclic_prefix
    )
    var received_grid = NRResourceGrid(1, fft_size)
    for subcarrier in range(fft_size):
        received_grid[0, subcarrier] = received_spectrum[subcarrier]

    var decoded = nr_pdsch_decode_grid_comb2(
        received_grid,
        0,
        0,
        allocation_size,
        0,
        Span(dmrs),
        Span(transmit.encoded_null_mask),
        transmit.profile,
        payload_bits,
        modulation_order,
        0,
        rnti,
        0,
        physical_cell_id,
        0.01,
        testcase_id="nr-pdsch-chain-integration",
    )
    assert_true(decoded.ldpc_converged)
    assert_true(decoded.code_block_crc_ok)
    assert_true(decoded.transport_crc_ok)
    assert_equal(decoded.payload, payload)
    assert_equal(len(decoded.received_data), allocation_size // 2)
    assert_equal(len(decoded.channel_estimate), allocation_size)
    assert_equal(len(decoded.equalized_symbols), allocation_size // 2)
    assert_equal(len(decoded.demapper_llrs), output_bits)
    assert_equal(len(decoded.descrambled_llrs), output_bits)
    assert_equal(
        len(decoded.rate_recovered_llrs),
        len(transmit.encoded_null_mask),
    )
    assert_equal(len(decoded.checkpoint_metadata), 9)
    for index in range(len(decoded.checkpoint_metadata)):
        assert_equal(
            decoded.checkpoint_metadata[index].testcase_id,
            "nr-pdsch-chain-integration",
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
        assert_equal(decoded.checkpoint_metadata[index].stride, "1")
        assert_true(
            decoded.checkpoint_metadata[index].q_format.byte_length() > 0
        )
        assert_equal(decoded.checkpoint_metadata[index].scale, 1.0)
        assert_equal(decoded.checkpoint_metadata[index].version, 1)
        assert_true(
            decoded.checkpoint_metadata[index].layout.byte_length() > 0
        )
    assert_equal(decoded.checkpoint_metadata[0].stage, "received-data")
    assert_equal(decoded.checkpoint_metadata[0].dtype, "complex64")
    assert_equal(decoded.checkpoint_metadata[0].shape, "240")
    assert_equal(decoded.checkpoint_metadata[0].q_format, "floating")
    assert_equal(decoded.checkpoint_metadata[0].layout, "iq-interleaved")
    assert_equal(decoded.checkpoint_metadata[1].stage, "channel-estimate")
    assert_equal(decoded.checkpoint_metadata[2].stage, "equalized-symbols")
    assert_equal(decoded.checkpoint_metadata[3].stage, "demapper-llrs")
    assert_equal(decoded.checkpoint_metadata[4].stage, "descrambled-llrs")
    assert_equal(
        decoded.checkpoint_metadata[5].stage, "rate-recovered-llrs"
    )
    assert_equal(decoded.checkpoint_metadata[6].stage, "ldpc-iterations")
    assert_equal(decoded.checkpoint_metadata[7].stage, "transport-block")
    assert_equal(decoded.checkpoint_metadata[8].stage, "payload")
    assert_equal(decoded.checkpoint_metadata[8].dtype, "uint8")
    assert_equal(decoded.checkpoint_metadata[8].shape, "100")
    assert_equal(decoded.checkpoint_metadata[8].q_format, "binary-u1")
    assert_equal(decoded.checkpoint_metadata[8].layout, "bit-per-byte")
    for index in range(len(transmit.symbols)):
        assert_true(
            abs(
                decoded.equalized_symbols[index].re
                - transmit.symbols[index].re
            ) < 1.0e-10
        )
        assert_true(
            abs(
                decoded.equalized_symbols[index].im
                - transmit.symbols[index].im
            ) < 1.0e-10
        )
    for index in range(output_bits):
        assert_equal(
            decoded.descrambled_llrs[index] < 0.0,
            transmit.rate_matched_bits[index] == 1,
        )

    # A subnormal channel power must not collapse representable, channel-
    # scaled LLRs to zero.  Here the separate 1/N0 LLR and |h|^2 terms are
    # respectively about 1e300 and 1e-400, while their product is finite.
    var tiny_grid = NRResourceGrid(1, fft_size)
    var tiny_channel = Complex64(1.0e-200, -0.5e-200)
    for subcarrier in range(fft_size):
        tiny_grid[0, subcarrier] = (
            transmit_grid[0, subcarrier] * tiny_channel
        )
    var tiny_decoded = nr_pdsch_decode_grid_comb2(
        tiny_grid,
        0,
        0,
        allocation_size,
        0,
        Span(dmrs),
        Span(transmit.encoded_null_mask),
        transmit.profile,
        payload_bits,
        modulation_order,
        0,
        rnti,
        0,
        physical_cell_id,
        1.0e-300,
        max_iterations=1,
        testcase_id="nr-pdsch-tiny-channel-llr-scaling",
    )
    for llr in tiny_decoded.demapper_llrs:
        assert_true(llr != 0.0)
        assert_true(llr == llr)

    # The opposite exponent combination has a true LLR below the minimum
    # subnormal.  It must underflow to zero instead of accepting finite
    # garbage from an out-of-domain ldexp call.
    var underflow_grid = NRResourceGrid(1, fft_size)
    var underflow_channel = Complex64(1.0e-150, 0.0)
    for subcarrier in range(fft_size):
        underflow_grid[0, subcarrier] = (
            transmit_grid[0, subcarrier] * underflow_channel
        )
    var underflow_decoded = nr_pdsch_decode_grid_comb2(
        underflow_grid,
        0,
        0,
        allocation_size,
        0,
        Span(dmrs),
        Span(transmit.encoded_null_mask),
        transmit.profile,
        payload_bits,
        modulation_order,
        0,
        rnti,
        0,
        physical_cell_id,
        1.0e300,
        max_iterations=1,
    )
    for llr in underflow_decoded.demapper_llrs:
        assert_equal(llr, 0.0)

    # A normal channel with enormous N0 produces representable subnormal
    # LLRs; preserve them instead of flushing the entire subnormal domain.
    var subnormal_decoded = nr_pdsch_decode_grid_comb2(
        transmit_grid,
        0,
        0,
        allocation_size,
        0,
        Span(dmrs),
        Span(transmit.encoded_null_mask),
        transmit.profile,
        payload_bits,
        modulation_order,
        0,
        rnti,
        0,
        physical_cell_id,
        1.0e308,
        max_iterations=1,
    )
    for llr in subnormal_decoded.demapper_llrs:
        assert_true(llr != 0.0)
        assert_true(llr == llr)


def test_pdsch_chain_rejects_nonstandard_modulation() raises:
    var payload = _payload(16)
    with assert_raises():
        _ = nr_pdsch_encode_transport_block(
            Span(payload), 0.5, 12, 0, 120, 1, 0, 0
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
