"""Independent end-to-end oracles for the public NR PDSCH wrappers.

The transmit oracle restates CRC16, the single-code-block BG2 profile,
segmentation/filler placement, RV selection/interleaving, Gold scrambling,
QPSK, and comb-2 placement.  Only separately evidenced low-level LDPC
encoder/decoder primitives are reused.  The receive fixture is built from
those independent values and never from ``nr_pdsch_encode_transport_block``.
"""

from std.collections import Span
from std.math import sqrt
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.nr import (
    NRLDPCProfile,
    NRResourceGrid,
    nr_ldpc_encode,
    nr_ldpc_decode,
    nr_pdsch_encode_transport_block,
    nr_pdsch_decode_grid_comb2,
)


def _assert_float_close(
    actual: Float64,
    expected: Float64,
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    var scale = max(abs(actual), abs(expected))
    assert_true(
        abs(actual - expected)
        <= absolute_tolerance + relative_tolerance * scale
    )


def _assert_complex_close(
    actual: Complex64,
    expected: Complex64,
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    _assert_float_close(
        actual.re, expected.re, absolute_tolerance, relative_tolerance
    )
    _assert_float_close(
        actual.im, expected.im, absolute_tolerance, relative_tolerance
    )


def _assert_complex_lists_close(
    actual: Span[Complex64, ...],
    expected: Span[Complex64, ...],
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        _assert_complex_close(
            Complex64(actual[index].re, actual[index].im),
            Complex64(expected[index].re, expected[index].im),
            absolute_tolerance,
            relative_tolerance,
        )


def _assert_float_lists_close(
    actual: Span[Float64, ...],
    expected: Span[Float64, ...],
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        _assert_float_close(
            actual[index],
            expected[index],
            absolute_tolerance,
            relative_tolerance,
        )


def _assert_profiles_equal(
    actual: NRLDPCProfile, expected: NRLDPCProfile
) raises:
    assert_equal(actual.base_graph, expected.base_graph)
    assert_equal(actual.code_blocks, expected.code_blocks)
    assert_equal(actual.code_block_crc_bits, expected.code_block_crc_bits)
    assert_equal(actual.lifting_size, expected.lifting_size)
    assert_equal(actual.information_columns, expected.information_columns)
    assert_equal(actual.code_block_bits, expected.code_block_bits)
    assert_equal(actual.transport_crc_bits, expected.transport_crc_bits)
    assert_equal(actual.transport_block_bits, expected.transport_block_bits)
    assert_equal(actual.segmented_bits, expected.segmented_bits)
    assert_equal(
        actual.code_block_payload_bits, expected.code_block_payload_bits
    )
    assert_equal(actual.code_block_data_bits, expected.code_block_data_bits)
    assert_equal(actual.filler_bits, expected.filler_bits)
    assert_equal(actual.encoder_input_bits, expected.encoder_input_bits)
    assert_equal(actual.encoded_bits, expected.encoded_bits)
    assert_equal(actual.lifting_set_index, expected.lifting_set_index)


def _reference_crc(
    bits: Span[UInt8, ...], width: Int, polynomial: UInt64,
) raises -> UInt64:
    """Independent MSB-first CRC shift-register traversal."""
    var mask = (UInt64(1) << UInt64(width)) - UInt64(1)
    var top = UInt64(1) << UInt64(width - 1)
    var state = UInt64(0)
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("reference CRC accepts binary inputs only")
        var feedback = (
            UInt64(1)
            if ((state & top) != 0) != (bits[index] != 0)
            else UInt64(0)
        )
        state = (state << UInt64(1)) & mask
        if feedback != 0:
            state ^= polynomial & mask
    return state


def _reference_crc_append(
    bits: Span[UInt8, ...], width: Int, polynomial: UInt64,
) raises -> List[UInt8]:
    var remainder = _reference_crc(bits, width, polynomial)
    var result = List[UInt8](capacity=len(bits) + width)
    for index in range(len(bits)):
        result.append(bits[index])
    for index in range(width):
        result.append(
            UInt8((remainder >> UInt64(width - index - 1)) & UInt64(1))
        )
    return result^


def _reference_gold(c_init: UInt32, length: Int) -> List[UInt8]:
    """TS 38.211 5.2.1 as rolling registers, unlike production arrays."""
    var x1 = UInt32(1)
    var x2 = c_init & UInt32(0x7FFFFFFF)
    var result = List[UInt8](capacity=length)
    for index in range(1600 + length):
        var output = UInt8((x1 ^ x2) & UInt32(1))
        var feedback1 = ((x1 >> 3) ^ x1) & UInt32(1)
        var feedback2 = (
            (x2 >> 3) ^ (x2 >> 2) ^ (x2 >> 1) ^ x2
        ) & UInt32(1)
        x1 = (x1 >> 1) | (feedback1 << 30)
        x2 = (x2 >> 1) | (feedback2 << 30)
        if index >= 1600:
            result.append(output)
    return result^


def _fixture_payload() -> List[UInt8]:
    var state = UInt64(0x9E3779B97F4A7C15)
    var result = List[UInt8](capacity=100)
    for _ in range(100):
        state = (
            state * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        result.append(UInt8((state >> UInt64(63)) & UInt64(1)))
    return result^


def _static_profile() -> NRLDPCProfile:
    """Exact TS 38.212 profile for A=100 and target rate 1/2."""
    return NRLDPCProfile(
        2,   # BG2
        1,   # one code block
        0,   # no CB CRC for C=1
        20,  # Zc
        6,   # BG2 Kb for B=116
        120,
        16,
        116,
        116,
        116,
        116,
        84,
        200,
        1000,
        2,
    )


def _manual_information_bits(
    transport_block: Span[UInt8, ...]
) -> List[UInt8]:
    # With C=1 there is no CB CRC.  The 84 remaining encoder-input positions
    # are zero-valued <NULL> filler bits.
    var result = List[UInt8](length=200, fill=UInt8(0))
    for index in range(len(transport_block)):
        result[index] = transport_block[index]
    return result^


def _manual_encoded_null_mask() -> List[UInt8]:
    # Full information positions [116,200) are filler.  Puncturing the first
    # 2*Zc=40 positions moves that interval to encoded indices [76,160).
    var result = List[UInt8](length=1000, fill=UInt8(0))
    for index in range(76, 160):
        result[index] = UInt8(1)
    return result^


def _reference_rate_match_rv2_qpsk(
    encoded: Span[UInt8, ...], null_mask: Span[UInt8, ...], output_bits: Int,
) -> List[UInt8]:
    # BG2 RV2 starts at 25*Zc.  Selection and Qm=2 interleaving are restated
    # directly instead of calling either production rate-match wrapper.
    var cursor = 25 * 20
    var selected = List[UInt8](capacity=output_bits)
    while len(selected) < output_bits:
        if null_mask[cursor] == 0:
            selected.append(encoded[cursor])
        cursor = (cursor + 1) % len(encoded)
    var symbols = output_bits // 2
    var result = List[UInt8](capacity=output_bits)
    for symbol in range(symbols):
        result.append(selected[symbol])
        result.append(selected[symbols + symbol])
    return result^


def _reference_rate_recover_rv2_qpsk(
    received: Span[Float64, ...], null_mask: Span[UInt8, ...],
) -> List[Float64]:
    var symbol_count = len(received) // 2
    var selected = List[Float64](length=len(received), fill=0.0)
    for symbol in range(symbol_count):
        selected[symbol] = received[2 * symbol]
        selected[symbol_count + symbol] = received[2 * symbol + 1]
    var result = List[Float64](length=1000, fill=0.0)
    var cursor = 25 * 20
    for value in selected:
        while null_mask[cursor] != 0:
            cursor = (cursor + 1) % 1000
        result[cursor] += value
        cursor = (cursor + 1) % 1000
    for index in range(1000):
        if null_mask[index] != 0:
            result[index] = 50.0
    return result^


def _reference_qpsk(bits: Span[UInt8, ...]) -> List[Complex64]:
    var scale = 1.0 / sqrt(2.0)
    var result = List[Complex64](capacity=len(bits) // 2)
    for symbol in range(len(bits) // 2):
        result.append(Complex64(
            scale * (1.0 - 2.0 * Float64(bits[2 * symbol])),
            scale * (1.0 - 2.0 * Float64(bits[2 * symbol + 1])),
        ))
    return result^


def _reference_dmrs_c_init() -> UInt32:
    comptime slot = 3
    comptime symbol = 2
    comptime n_id = 71
    comptime n_scid = 0
    var modulus = UInt64(1) << UInt64(31)
    var value = (
        (UInt64(1) << UInt64(17))
        * UInt64(14 * slot + symbol + 1)
        * UInt64(2 * n_id + 1)
        + UInt64(2 * n_id + n_scid)
    ) % modulus
    return UInt32(value)


def _reference_dmrs(length: Int) -> List[Complex64]:
    var bits = _reference_gold(_reference_dmrs_c_init(), 2 * length)
    return _reference_qpsk(Span(bits))


struct IndependentPDSCHVector(Movable):
    var profile: NRLDPCProfile
    var payload: List[UInt8]
    var transport_block: List[UInt8]
    var information_bits: List[UInt8]
    var encoded_bits: List[UInt8]
    var encoded_null_mask: List[UInt8]
    var rate_matched_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var symbols: List[Complex64]
    var dmrs: List[Complex64]

    def __init__(
        out self,
        var profile: NRLDPCProfile,
        var payload: List[UInt8],
        var transport_block: List[UInt8],
        var information_bits: List[UInt8],
        var encoded_bits: List[UInt8],
        var encoded_null_mask: List[UInt8],
        var rate_matched_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var symbols: List[Complex64],
        var dmrs: List[Complex64],
    ):
        self.profile = profile^
        self.payload = payload^
        self.transport_block = transport_block^
        self.information_bits = information_bits^
        self.encoded_bits = encoded_bits^
        self.encoded_null_mask = encoded_null_mask^
        self.rate_matched_bits = rate_matched_bits^
        self.scrambled_bits = scrambled_bits^
        self.symbols = symbols^
        self.dmrs = dmrs^


def _independent_vector() raises -> IndependentPDSCHVector:
    comptime output_bits = 1000
    comptime rnti = 0x3456
    comptime codeword = 1
    comptime n_id = 71
    var profile = _static_profile()
    var payload = _fixture_payload()
    var transport = _reference_crc_append(
        Span(payload), 16, UInt64(0x1021)
    )
    var information = _manual_information_bits(Span(transport))
    # The QC-LDPC encoder is a separately evidenced primitive.  Every other
    # composition step below is an independent scalar implementation.
    var encoded = nr_ldpc_encode(Span(information), 2, 20)
    var null_mask = _manual_encoded_null_mask()
    var rate_matched = _reference_rate_match_rv2_qpsk(
        Span(encoded), Span(null_mask), output_bits
    )
    var c_init = UInt32((rnti << 15) + (codeword << 14) + n_id)
    var gold = _reference_gold(c_init, output_bits)
    var scrambled = List[UInt8](capacity=output_bits)
    for index in range(output_bits):
        scrambled.append(rate_matched[index] ^ gold[index])
    var symbols = _reference_qpsk(Span(scrambled))
    var dmrs = _reference_dmrs(output_bits // 2)
    return IndependentPDSCHVector(
        profile^,
        payload^,
        transport^,
        information^,
        encoded^,
        null_mask^,
        rate_matched^,
        scrambled^,
        symbols^,
        dmrs^,
    )


def _channel_for_local(local: Int, allocation_size: Int) -> Complex64:
    # Pilots occupy even indices.  Linear interpolation recovers this affine
    # response exactly; the final odd RE uses the held last-pilot value.
    var position = min(local, allocation_size - 2)
    return Complex64(
        0.65 + 0.00035 * Float64(position),
        -0.20 + 0.00017 * Float64(position),
    )


def _manual_received_grid(
    data: Span[Complex64, ...],
    dmrs: Span[Complex64, ...],
    symbol: Int,
    first_subcarrier: Int,
    allocation_size: Int,
) raises -> NRResourceGrid:
    # This is deliberately not nr_map_pdsch_comb2.  Each RE is written from
    # the comb-2 indexing rule and an analytic frequency-selective channel.
    var grid = NRResourceGrid(symbol + 2, first_subcarrier + allocation_size + 3)
    for local in range(allocation_size):
        var channel = _channel_for_local(local, allocation_size)
        if local % 2 == 0:
            var dmrs_value = Complex64(
                dmrs[local // 2].re, dmrs[local // 2].im
            )
            grid[symbol, first_subcarrier + local] = (
                dmrs_value * channel
            )
        else:
            var data_value = Complex64(
                data[local // 2].re, data[local // 2].im
            )
            grid[symbol, first_subcarrier + local] = (
                data_value * channel
            )
    return grid^


def test_nr_pdsch_encode_transport_block_full_independent_oracle() raises:
    """Differential: hand composition through a manual comb-2 grid."""
    comptime output_bits = 1000
    comptime rnti = 0x3456
    comptime codeword = 1
    comptime n_id = 71
    comptime absolute_tolerance = 1.0e-13
    comptime relative_tolerance = 1.0e-12
    var expected = _independent_vector()
    var actual = nr_pdsch_encode_transport_block(
        Span(expected.payload),
        0.5,
        2,
        2,
        output_bits,
        rnti,
        codeword,
        n_id,
    )

    _assert_profiles_equal(actual.profile, expected.profile)
    assert_equal(actual.transport_block, expected.transport_block)
    assert_equal(actual.encoded_null_mask, expected.encoded_null_mask)
    assert_equal(actual.rate_matched_bits, expected.rate_matched_bits)
    assert_equal(actual.scrambled_bits, expected.scrambled_bits)
    _assert_complex_lists_close(
        Span(actual.symbols),
        Span(expected.symbols),
        absolute_tolerance,
        relative_tolerance,
    )

    assert_equal(len(expected.information_bits), 200)
    assert_equal(len(expected.encoded_bits), 1000)
    for index in range(116, 200):
        assert_equal(expected.information_bits[index], UInt8(0))
    for index in range(1000):
        assert_equal(
            expected.encoded_null_mask[index],
            UInt8(1) if index >= 76 and index < 160 else UInt8(0),
        )

    # Carry both actual and independent symbol vectors through the same
    # explicit RE formula so the wrapper's terminal QAM output is checked at
    # its comb-2 grid boundary as well as in isolation.
    var expected_grid = _manual_received_grid(
        Span(expected.symbols), Span(expected.dmrs), 1, 3, output_bits
    )
    var actual_grid = _manual_received_grid(
        Span(actual.symbols), Span(expected.dmrs), 1, 3, output_bits
    )
    for local in range(output_bits):
        _assert_complex_close(
            actual_grid[1, 3 + local],
            expected_grid[1, 3 + local],
            absolute_tolerance,
            relative_tolerance,
        )


def test_nr_pdsch_decode_grid_comb2_manual_fixture_all_checkpoints() raises:
    """Differential: manual grid and independent stage-by-stage RX oracle."""
    comptime payload_bits = 100
    comptime output_bits = 1000
    comptime symbol = 1
    comptime first_subcarrier = 3
    comptime rnti = 0x3456
    comptime codeword = 1
    comptime n_id = 71
    comptime noise_variance = 0.01
    comptime absolute_tolerance = 2.0e-10
    comptime relative_tolerance = 2.0e-11
    var reference = _independent_vector()
    var grid = _manual_received_grid(
        Span(reference.symbols),
        Span(reference.dmrs),
        symbol,
        first_subcarrier,
        output_bits,
    )

    # No PDSCH TX wrapper participates in constructing grid, profile, mask,
    # DM-RS, or any expected receive checkpoint.
    var actual = nr_pdsch_decode_grid_comb2(
        grid,
        symbol,
        first_subcarrier,
        output_bits,
        0,
        Span(reference.dmrs),
        Span(reference.encoded_null_mask),
        reference.profile,
        payload_bits,
        2,
        2,
        rnti,
        codeword,
        n_id,
        noise_variance,
        max_iterations=30,
        normalization=0.8,
        offset=0.0,
        testcase_id="nr-pdsch-independent-rx",
    )

    var expected_received = List[Complex64](capacity=output_bits // 2)
    var expected_channel = List[Complex64](capacity=output_bits)
    var expected_equalized = reference.symbols.copy()
    var expected_llrs = List[Float64](capacity=output_bits)
    var qpsk_factor = 2.0 * sqrt(2.0)
    for local in range(output_bits):
        var channel = _channel_for_local(local, output_bits)
        expected_channel.append(channel)
        if local % 2 != 0:
            var data_index = local // 2
            var symbol_value = Complex64(
                reference.symbols[data_index].re,
                reference.symbols[data_index].im,
            )
            expected_received.append(symbol_value * channel)
            var power = channel.magnitude_squared()
            expected_llrs.append(
                qpsk_factor * symbol_value.re * power / noise_variance
            )
            expected_llrs.append(
                qpsk_factor * symbol_value.im * power / noise_variance
            )

    _assert_complex_lists_close(
        Span(actual.received_data),
        Span(expected_received),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_lists_close(
        Span(actual.channel_estimate),
        Span(expected_channel),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_lists_close(
        Span(actual.equalized_symbols),
        Span(expected_equalized),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_float_lists_close(
        Span(actual.demapper_llrs),
        Span(expected_llrs),
        absolute_tolerance,
        relative_tolerance,
    )

    var scramble_init = UInt32((rnti << 15) + (codeword << 14) + n_id)
    var gold = _reference_gold(scramble_init, output_bits)
    var expected_descrambled = List[Float64](capacity=output_bits)
    for index in range(output_bits):
        expected_descrambled.append(
            expected_llrs[index]
            if gold[index] == 0 else -expected_llrs[index]
        )
    _assert_float_lists_close(
        Span(actual.descrambled_llrs),
        Span(expected_descrambled),
        absolute_tolerance,
        relative_tolerance,
    )

    var expected_recovered = _reference_rate_recover_rv2_qpsk(
        Span(expected_descrambled), Span(reference.encoded_null_mask)
    )
    _assert_float_lists_close(
        Span(actual.rate_recovered_llrs),
        Span(expected_recovered),
        5.0e-10,
        relative_tolerance,
    )

    # LDPC is checked through its independently evidenced low-level decoder;
    # desegmentation and both CRC/payload expectations are reconstructed here.
    var expected_ldpc = nr_ldpc_decode(
        Span(expected_recovered),
        Span(reference.encoded_null_mask),
        2,
        20,
        max_iterations=30,
        normalization=0.8,
        offset=0.0,
    )
    assert_equal(len(actual.iterations), 1)
    assert_equal(actual.iterations[0], expected_ldpc.iterations)
    assert_equal(actual.ldpc_converged, expected_ldpc.converged)
    assert_true(actual.ldpc_converged)
    for index in range(116):
        assert_equal(expected_ldpc.bits[index], reference.transport_block[index])
    assert_equal(actual.transport_block, reference.transport_block)
    assert_equal(
        _reference_crc(
            Span(reference.transport_block), 16, UInt64(0x1021)
        ),
        UInt64(0),
    )
    assert_true(actual.code_block_crc_ok)
    assert_true(actual.transport_crc_ok)
    assert_equal(actual.payload, reference.payload)

    assert_equal(len(actual.checkpoint_metadata), 9)
    var stages: List[String] = [
        "received-data",
        "channel-estimate",
        "equalized-symbols",
        "demapper-llrs",
        "descrambled-llrs",
        "rate-recovered-llrs",
        "ldpc-iterations",
        "transport-block",
        "payload",
    ]
    var dtypes: List[String] = [
        "complex64",
        "complex64",
        "complex64",
        "float64",
        "float64",
        "float64",
        "int",
        "uint8",
        "uint8",
    ]
    var shapes: List[String] = [
        "500", "1000", "500", "1000", "1000", "1000", "1", "116", "100"
    ]
    var q_formats: List[String] = [
        "floating",
        "floating",
        "floating",
        "floating",
        "floating",
        "floating",
        "integer",
        "binary-u1",
        "binary-u1",
    ]
    var layouts: List[String] = [
        "iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
        "linear",
        "linear",
        "linear",
        "linear",
        "bit-per-byte",
        "bit-per-byte",
    ]
    for index in range(9):
        assert_equal(
            actual.checkpoint_metadata[index].testcase_id,
            "nr-pdsch-independent-rx",
        )
        assert_equal(actual.checkpoint_metadata[index].stage, stages[index])
        assert_equal(actual.checkpoint_metadata[index].dtype, dtypes[index])
        assert_equal(actual.checkpoint_metadata[index].shape, shapes[index])
        assert_equal(actual.checkpoint_metadata[index].stride, "1")
        assert_equal(
            actual.checkpoint_metadata[index].q_format, q_formats[index]
        )
        assert_equal(actual.checkpoint_metadata[index].layout, layouts[index])
        assert_equal(actual.checkpoint_metadata[index].scale, 1.0)
        assert_equal(actual.checkpoint_metadata[index].version, 1)


def test_nr_pdsch_wrappers_replay_and_direct_boundaries() raises:
    comptime output_bits = 1000
    comptime rnti = 0x3456
    comptime codeword = 1
    comptime n_id = 71
    var reference = _independent_vector()

    var tx_first = nr_pdsch_encode_transport_block(
        Span(reference.payload), 0.5, 2, 2, output_bits, rnti, codeword, n_id
    )
    var tx_second = nr_pdsch_encode_transport_block(
        Span(reference.payload), 0.5, 2, 2, output_bits, rnti, codeword, n_id
    )
    assert_equal(tx_first.transport_block, tx_second.transport_block)
    assert_equal(tx_first.encoded_null_mask, tx_second.encoded_null_mask)
    assert_equal(tx_first.rate_matched_bits, tx_second.rate_matched_bits)
    assert_equal(tx_first.scrambled_bits, tx_second.scrambled_bits)
    assert_equal(tx_first.symbols, tx_second.symbols)

    var grid = _manual_received_grid(
        Span(reference.symbols), Span(reference.dmrs), 1, 3, output_bits
    )
    var rx_first = nr_pdsch_decode_grid_comb2(
        grid, 1, 3, output_bits, 0, Span(reference.dmrs),
        Span(reference.encoded_null_mask), reference.profile,
        100, 2, 2, rnti, codeword, n_id, 0.01,
        testcase_id="nr-pdsch-replay",
    )
    var rx_second = nr_pdsch_decode_grid_comb2(
        grid, 1, 3, output_bits, 0, Span(reference.dmrs),
        Span(reference.encoded_null_mask), reference.profile,
        100, 2, 2, rnti, codeword, n_id, 0.01,
        testcase_id="nr-pdsch-replay",
    )
    assert_equal(rx_first.payload, rx_second.payload)
    assert_equal(rx_first.transport_block, rx_second.transport_block)
    assert_equal(rx_first.iterations, rx_second.iterations)
    assert_equal(rx_first.received_data, rx_second.received_data)
    assert_equal(rx_first.channel_estimate, rx_second.channel_estimate)
    assert_equal(rx_first.equalized_symbols, rx_second.equalized_symbols)
    assert_equal(rx_first.demapper_llrs, rx_second.demapper_llrs)
    assert_equal(rx_first.descrambled_llrs, rx_second.descrambled_llrs)
    assert_equal(rx_first.rate_recovered_llrs, rx_second.rate_recovered_llrs)
    assert_equal(rx_first.transport_crc_ok, rx_second.transport_crc_ok)
    assert_equal(rx_first.code_block_crc_ok, rx_second.code_block_crc_ok)
    assert_equal(rx_first.ldpc_converged, rx_second.ldpc_converged)

    var invalid_payload = reference.payload.copy()
    invalid_payload[7] = UInt8(2)
    with assert_raises():
        _ = nr_pdsch_encode_transport_block(
            Span(invalid_payload), 0.5, 2, 2, output_bits,
            rnti, codeword, n_id,
        )
    with assert_raises():
        _ = nr_pdsch_encode_transport_block(
            Span(reference.payload), 0.5, 1, 2, output_bits,
            rnti, codeword, n_id,
        )
    with assert_raises():
        _ = nr_pdsch_encode_transport_block(
            Span(reference.payload), 0.5, 2, 2, output_bits - 1,
            rnti, codeword, n_id,
        )
    with assert_raises():
        _ = nr_pdsch_encode_transport_block(
            Span(reference.payload), 0.0, 2, 2, output_bits,
            rnti, codeword, n_id,
        )

    var short_mask = reference.encoded_null_mask.copy()
    _ = short_mask.pop()
    with assert_raises():
        _ = nr_pdsch_decode_grid_comb2(
            grid, 1, 3, output_bits, 0, Span(reference.dmrs),
            Span(short_mask), reference.profile,
            100, 2, 2, rnti, codeword, n_id, 0.01,
        )
    with assert_raises():
        _ = nr_pdsch_decode_grid_comb2(
            grid, 1, 3, output_bits, 0, Span(reference.dmrs),
            Span(reference.encoded_null_mask), reference.profile,
            100, 2, 2, rnti, codeword, n_id, nan[DType.float64](),
        )
    with assert_raises():
        _ = nr_pdsch_decode_grid_comb2(
            grid, 1, 3, output_bits, 2, Span(reference.dmrs),
            Span(reference.encoded_null_mask), reference.profile,
            100, 2, 2, rnti, codeword, n_id, 0.01,
        )
    with assert_raises():
        _ = nr_pdsch_decode_grid_comb2(
            grid, 1, 3, output_bits, 0, Span(reference.dmrs),
            Span(reference.encoded_null_mask), reference.profile,
            -1, 2, 2, rnti, codeword, n_id, 0.01,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
