"""Independent composition oracles for the bounded NR uplink wrappers.

The expected checkpoints in this file are assembled from the public,
individually tested PHY primitives.  No wrapper under test is used to create
its own expected input or output, and the receive tests are not TX/RX
round-trip assertions: their waveform fixtures and expected receive stages are
constructed explicitly from the lower-level TS 38.211/38.212 operations.
"""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.utils.numerics import nan
from wireless_dsp.core import Complex64
from wireless_dsp.dsp import ofdm_modulate
from wireless_dsp.modem import qam_map, qam_demapper_llr_piecewise
from wireless_dsp.wireless.nr.grid import (
    NRResourceGrid,
    nr_normal_cp_samples,
)
from wireless_dsp.wireless.nr.pdsch import (
    nr_transport_crc_append,
    nr_transport_crc_check,
)
from wireless_dsp.wireless.nr.ldpc_profile import (
    NRLDPCProfile,
    nr_ldpc_profile,
)
from wireless_dsp.wireless.nr.ldpc_segmentation import (
    nr_ldpc_segment,
    nr_ldpc_desegment,
    nr_ldpc_encode_code_blocks,
    nr_ldpc_rate_match_code_blocks,
    nr_ldpc_rate_recover_code_blocks,
    nr_ldpc_decode_code_blocks,
)
from wireless_dsp.wireless.nr.uplink import (
    nr_pusch_scramble,
    nr_pusch_descramble_llrs,
    nr_pusch_dmrs,
)
from wireless_dsp.wireless.nr.pusch_chain import (
    NRPUSCHConfig,
    nr_pusch_encode_transport_block,
    nr_pusch_decode_waveform,
)
from wireless_dsp.wireless.nr.pucch import nr_pucch_scramble
from wireless_dsp.wireless.nr.pucch_resources import (
    nr_pucch_format2_dmrs,
    nr_extract_pucch_format2_data,
    nr_extract_pucch_format2_dmrs,
)
from wireless_dsp.wireless.nr.uci import (
    nr_uci_encode,
    nr_uci_decode,
)
from wireless_dsp.wireless.nr.pucch_chain import (
    NRPUCCHFormat2Config,
    nr_pucch_format2_encode,
    nr_pucch_format2_decode,
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
        var actual_value = Complex64(actual[index].re, actual[index].im)
        var expected_value = Complex64(expected[index].re, expected[index].im)
        _assert_complex_close(
            actual_value,
            expected_value,
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


def _assert_grids_close(
    actual: NRResourceGrid,
    expected: NRResourceGrid,
    absolute_tolerance: Float64,
    relative_tolerance: Float64,
) raises:
    assert_equal(actual.symbol_count, expected.symbol_count)
    assert_equal(actual.subcarrier_count, expected.subcarrier_count)
    for symbol in range(actual.symbol_count):
        for subcarrier in range(actual.subcarrier_count):
            _assert_complex_close(
                actual[symbol, subcarrier],
                expected[symbol, subcarrier],
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


def _payload(length: Int, multiplier: Int) -> List[UInt8]:
    var result = List[UInt8](capacity=length)
    for index in range(length):
        result.append(
            UInt8((multiplier * index + index // 3 + index // 7 + 1) & 1)
        )
    return result^


def _fnv1a_binary(bits: Span[UInt8, ...]) raises -> UInt64:
    """Independent FNV-1a checkpoint formula used by the wrapper contract."""
    var checksum = UInt64(14695981039346656037)
    for index in range(len(bits)):
        if bits[index] > 1:
            raise Error("oracle checksum input must be binary")
        checksum ^= UInt64(bits[index])
        checksum *= UInt64(1099511628211)
    return checksum


def _complex_energy(values: Span[Complex64, ...]) -> Float64:
    var result = 0.0
    for index in range(len(values)):
        result += (
            values[index].re * values[index].re
            + values[index].im * values[index].im
        )
    return result


def _grid_energy(grid: NRResourceGrid) raises -> Float64:
    var result = 0.0
    for symbol in range(grid.symbol_count):
        for subcarrier in range(grid.subcarrier_count):
            var value = grid[symbol, subcarrier]
            result += value.re * value.re + value.im * value.im
    return result


def _hard_bits(llrs: Span[Float64, ...]) -> List[UInt8]:
    var result = List[UInt8](capacity=len(llrs))
    for index in range(len(llrs)):
        result.append(UInt8(0) if llrs[index] >= 0.0 else UInt8(1))
    return result^


struct _PUSCHOracleStages(Movable):
    var profile: NRLDPCProfile
    var transport_block: List[UInt8]
    var encoded_null_mask: List[UInt8]
    var rate_matched_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var modulated_symbols: List[Complex64]
    var mapped_data_symbols: List[Complex64]
    var dmrs: List[Complex64]
    var grid: NRResourceGrid
    var waveform: List[Complex64]

    def __init__(
        out self,
        var profile: NRLDPCProfile,
        var transport_block: List[UInt8],
        var encoded_null_mask: List[UInt8],
        var rate_matched_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var modulated_symbols: List[Complex64],
        var mapped_data_symbols: List[Complex64],
        var dmrs: List[Complex64],
        var grid: NRResourceGrid,
        var waveform: List[Complex64],
    ):
        self.profile = profile^
        self.transport_block = transport_block^
        self.encoded_null_mask = encoded_null_mask^
        self.rate_matched_bits = rate_matched_bits^
        self.scrambled_bits = scrambled_bits^
        self.modulated_symbols = modulated_symbols^
        self.mapped_data_symbols = mapped_data_symbols^
        self.dmrs = dmrs^
        self.grid = grid^
        self.waveform = waveform^


def _manual_pusch_cp_ofdm_encode(
    payload: Span[UInt8, ...],
    target_code_rate: Float64,
    modulation_order: Int,
    redundancy_version: Int,
    config: NRPUSCHConfig,
) raises -> _PUSCHOracleStages:
    """Compose TS 38.212 coding and TS 38.211 mapping without the wrapper."""
    # One layer, one codeword, a full reserved DM-RS row, and CP-OFDM are the
    # explicit profile under test.  E=(L-1)*12*N_RB*Qm.
    if config.transform_precoding:
        raise Error("this composition oracle is the CP-OFDM branch")
    var allocation = 12 * config.resource_blocks
    var data_re = (config.symbol_count - 1) * allocation
    var output_bits = data_re * modulation_order

    var profile = nr_ldpc_profile(len(payload), target_code_rate)
    var transport_block = nr_transport_crc_append(payload)
    var segments = nr_ldpc_segment(Span(transport_block), profile)
    var encoded = nr_ldpc_encode_code_blocks(segments, profile)
    var encoded_null_mask = encoded.null_mask.copy()
    var rate_matched = nr_ldpc_rate_match_code_blocks(
        encoded,
        profile,
        redundancy_version,
        output_bits,
        modulation_order,
        1,
    )
    var scrambled = nr_pusch_scramble(
        Span(rate_matched), config.rnti, 0, config.n_id
    )
    var modulated = qam_map(Span(scrambled), modulation_order)
    var mapped_data = modulated.copy()
    var dmrs = nr_pusch_dmrs(
        config.slot,
        config.dmrs_symbol,
        config.dmrs_n_id,
        config.n_scid,
        allocation // 2,
    )

    # Direct clause-6.4.1.1 mapping: even local subcarriers in the DM-RS row,
    # all allocated subcarriers in every other row.
    var grid = NRResourceGrid(config.symbol_count, config.fft_size)
    var data_index = 0
    for symbol in range(config.symbol_count):
        if symbol == config.dmrs_symbol:
            for local in range(0, allocation, 2):
                grid[symbol, config.first_subcarrier + local] = dmrs[local // 2]
        else:
            for local in range(allocation):
                grid[symbol, config.first_subcarrier + local] = mapped_data[
                    data_index
                ]
                data_index += 1
    assert_equal(data_index, len(mapped_data))

    # Direct symbol-wise CP-OFDM composition, independent of the chain helper.
    var waveform = List[Complex64](
        capacity=config.symbol_count
        * (config.fft_size + config.cyclic_prefix)
    )
    for symbol in range(config.symbol_count):
        var spectrum = List[Complex64](capacity=config.fft_size)
        for subcarrier in range(config.fft_size):
            spectrum.append(grid[symbol, subcarrier])
        var samples = ofdm_modulate(Span(spectrum), config.cyclic_prefix)
        for sample in samples:
            waveform.append(sample)

    return _PUSCHOracleStages(
        profile^,
        transport_block^,
        encoded_null_mask^,
        rate_matched^,
        scrambled^,
        modulated^,
        mapped_data^,
        dmrs^,
        grid^,
        waveform^,
    )


def _apply_flat_gain(
    waveform: Span[Complex64, ...], gain: Complex64
) -> List[Complex64]:
    var result = List[Complex64](capacity=len(waveform))
    for index in range(len(waveform)):
        var sample = Complex64(waveform[index].re, waveform[index].im)
        result.append(sample * gain)
    return result^


struct _PUCCHOracleStages(Movable):
    var payload: List[UInt8]
    var coded_bits: List[UInt8]
    var scrambled_bits: List[UInt8]
    var data_symbols: List[Complex64]
    var dmrs: List[Complex64]
    var grid: NRResourceGrid
    var waveform: List[Complex64]
    var uci_scheme: Int
    var code_blocks: Int

    def __init__(
        out self,
        var payload: List[UInt8],
        var coded_bits: List[UInt8],
        var scrambled_bits: List[UInt8],
        var data_symbols: List[Complex64],
        var dmrs: List[Complex64],
        var grid: NRResourceGrid,
        var waveform: List[Complex64],
        uci_scheme: Int,
        code_blocks: Int,
    ):
        self.payload = payload^
        self.coded_bits = coded_bits^
        self.scrambled_bits = scrambled_bits^
        self.data_symbols = data_symbols^
        self.dmrs = dmrs^
        self.grid = grid^
        self.waveform = waveform^
        self.uci_scheme = uci_scheme
        self.code_blocks = code_blocks


def _manual_pucch_format2_encode(
    payload: Span[UInt8, ...], config: NRPUCCHFormat2Config
) raises -> _PUCCHOracleStages:
    """Compose UCI, scrambling, mapping, and OFDM without the wrapper."""
    # Format 2 has eight QPSK data REs per PRB and symbol: E=16*N_sym.
    var encoded = nr_uci_encode(payload, 16 * config.symbol_count)
    var coded = encoded.bits.copy()
    var scrambled = nr_pucch_scramble(
        Span(coded), config.rnti, config.n_id
    )
    var data_symbols = qam_map(Span(scrambled), 2)

    var dmrs = List[Complex64](capacity=4 * config.symbol_count)
    for local_symbol in range(config.symbol_count):
        var symbol_dmrs = nr_pucch_format2_dmrs(
            config.slot_in_frame,
            config.start_symbol + local_symbol,
            config.dmrs_n_id,
            1,
        )
        for value in symbol_dmrs:
            dmrs.append(value)

    # Direct format-2 one-PRB map: DM-RS at k mod 3 == 1.
    var grid = NRResourceGrid(14, config.fft_size)
    var data_index = 0
    var dmrs_index = 0
    for local_symbol in range(config.symbol_count):
        var symbol = config.start_symbol + local_symbol
        for local_subcarrier in range(12):
            if local_subcarrier % 3 == 1:
                grid[symbol, config.first_subcarrier + local_subcarrier] = dmrs[
                    dmrs_index
                ]
                dmrs_index += 1
            else:
                grid[symbol, config.first_subcarrier + local_subcarrier] = (
                    data_symbols[data_index]
                )
                data_index += 1
    assert_equal(data_index, len(data_symbols))
    assert_equal(dmrs_index, len(dmrs))

    # Direct normal-CP OFDM composition for the allocation-only waveform.
    var waveform = List[Complex64]()
    var slot_in_subframe = config.slot_in_frame % (1 << config.numerology)
    for local_symbol in range(config.symbol_count):
        var symbol = config.start_symbol + local_symbol
        var spectrum = List[Complex64](capacity=config.fft_size)
        for subcarrier in range(config.fft_size):
            spectrum.append(grid[symbol, subcarrier])
        var cyclic_prefix = nr_normal_cp_samples(
            config.fft_size,
            symbol,
            config.numerology,
            slot_in_subframe=slot_in_subframe,
        )
        var samples = ofdm_modulate(Span(spectrum), cyclic_prefix)
        for sample in samples:
            waveform.append(sample)

    var payload_copy = List[UInt8](capacity=len(payload))
    for index in range(len(payload)):
        payload_copy.append(payload[index])
    return _PUCCHOracleStages(
        payload_copy^,
        coded^,
        scrambled^,
        data_symbols^,
        dmrs^,
        grid^,
        waveform^,
        encoded.scheme,
        encoded.code_blocks,
    )


def test_nr_pusch_encode_transport_block_composition_oracle() raises:
    """Differential: every TX checkpoint vs an independent stage graph."""
    comptime target_code_rate = 0.3
    comptime modulation_order = 2
    comptime redundancy_version = 3
    comptime absolute_tolerance = 1.0e-12
    comptime relative_tolerance = 1.0e-12
    var config = NRPUSCHConfig(
        64, 8, 5, 1, 8, 4, 7, 311, 1, 0x5A31, dmrs_n_id=50001
    )
    var payload = _payload(32, 11)
    var expected = _manual_pusch_cp_ofdm_encode(
        Span(payload),
        target_code_rate,
        modulation_order,
        redundancy_version,
        config,
    )
    var actual = nr_pusch_encode_transport_block(
        Span(payload),
        target_code_rate,
        modulation_order,
        redundancy_version,
        config,
    )

    _assert_profiles_equal(actual.profile, expected.profile)
    assert_equal(actual.transport_block, expected.transport_block)
    assert_equal(actual.encoded_null_mask, expected.encoded_null_mask)
    assert_equal(actual.rate_matched_bits, expected.rate_matched_bits)
    assert_equal(actual.scrambled_bits, expected.scrambled_bits)
    _assert_complex_lists_close(
        Span(actual.modulated_symbols),
        Span(expected.modulated_symbols),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_lists_close(
        Span(actual.mapped_data_symbols),
        Span(expected.mapped_data_symbols),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_lists_close(
        Span(actual.dmrs),
        Span(expected.dmrs),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_grids_close(
        actual.grid,
        expected.grid,
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_lists_close(
        Span(actual.waveform),
        Span(expected.waveform),
        absolute_tolerance,
        relative_tolerance,
    )

    # Direct wrapper edge evidence, separate from lower-level validation.
    var invalid_payload = payload.copy()
    invalid_payload[5] = UInt8(2)
    with assert_raises():
        _ = nr_pusch_encode_transport_block(
            Span(invalid_payload),
            target_code_rate,
            modulation_order,
            redundancy_version,
            config,
        )


def test_nr_pusch_decode_waveform_composition_oracle() raises:
    """Differential: ideal flat-channel checkpoints vs a manual RX graph."""
    comptime target_code_rate = 0.3
    comptime modulation_order = 2
    comptime redundancy_version = 1
    comptime equalized_noise_variance = 0.01
    comptime absolute_tolerance = 1.0e-8
    comptime relative_tolerance = 1.0e-10
    var config = NRPUSCHConfig(
        64, 8, 5, 2, 4, 4, 9, 477, 0, 0x7312, dmrs_n_id=61234
    )
    var payload = _payload(32, 13)

    # The receive fixture is produced by the explicit lower-stage graph, not
    # by nr_pusch_encode_transport_block.
    var manual_tx = _manual_pusch_cp_ofdm_encode(
        Span(payload),
        target_code_rate,
        modulation_order,
        redundancy_version,
        config,
    )
    var gain = Complex64(0.81, -0.27)
    var received = _apply_flat_gain(Span(manual_tx.waveform), gain)
    var expected_received_grid = NRResourceGrid(
        manual_tx.grid.symbol_count, manual_tx.grid.subcarrier_count
    )
    for symbol in range(manual_tx.grid.symbol_count):
        for subcarrier in range(manual_tx.grid.subcarrier_count):
            expected_received_grid[symbol, subcarrier] = (
                manual_tx.grid[symbol, subcarrier] * gain
            )
    var expected_channel = List[Complex64](
        capacity=12 * config.resource_blocks
    )
    for _ in range(12 * config.resource_blocks):
        expected_channel.append(gain)

    # For a noiseless constant channel, the independent analytic ZF result is
    # exactly the transmitted QAM sequence.  Decode the corresponding ideal
    # soft values through the standalone 38.212 receive primitives.
    var expected_equalized = manual_tx.modulated_symbols.copy()
    var raw_llrs = qam_demapper_llr_piecewise(
        Span(expected_equalized),
        modulation_order,
        equalized_noise_variance,
    )
    var expected_descrambled = nr_pusch_descramble_llrs(
        Span(raw_llrs), config.rnti, 0, config.n_id
    )
    var recovered = nr_ldpc_rate_recover_code_blocks(
        Span(expected_descrambled),
        Span(manual_tx.encoded_null_mask),
        manual_tx.profile,
        redundancy_version,
        modulation_order,
        1,
    )
    var decoded_blocks = nr_ldpc_decode_code_blocks(
        Span(recovered),
        Span(manual_tx.encoded_null_mask),
        manual_tx.profile,
        max_iterations=30,
        normalization=0.8,
        offset=0.0,
    )
    var expected_desegmented = nr_ldpc_desegment(
        Span(decoded_blocks.bits), manual_tx.profile
    )
    var expected_transport_crc_ok = nr_transport_crc_check(
        Span(expected_desegmented.bits), len(payload)
    )
    var expected_payload = List[UInt8](capacity=len(payload))
    for index in range(len(payload)):
        expected_payload.append(expected_desegmented.bits[index])

    var actual = nr_pusch_decode_waveform(
        Span(received),
        config,
        Span(manual_tx.encoded_null_mask),
        manual_tx.profile,
        len(payload),
        modulation_order,
        redundancy_version,
        equalized_noise_variance,
        max_iterations=30,
        normalization=0.8,
        offset=0.0,
    )
    assert_equal(actual.payload, expected_payload)
    assert_equal(actual.transport_block, expected_desegmented.bits)
    _assert_grids_close(
        actual.received_grid,
        expected_received_grid,
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
        Span(raw_llrs),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_float_lists_close(
        Span(actual.descrambled_llrs),
        Span(expected_descrambled),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_float_lists_close(
        Span(actual.rate_recovered_llrs),
        Span(recovered),
        absolute_tolerance,
        relative_tolerance,
    )
    assert_equal(actual.iterations, decoded_blocks.iterations)
    assert_equal(actual.transport_crc_ok, expected_transport_crc_ok)
    assert_equal(
        actual.code_block_crc_ok, expected_desegmented.code_block_crc_ok
    )
    assert_equal(actual.ldpc_converged, decoded_blocks.converged)
    assert_equal(actual.payload, payload)
    assert_true(
        actual.transport_crc_ok
        and actual.code_block_crc_ok
        and actual.ldpc_converged
    )

    var nonfinite_waveform = received.copy()
    nonfinite_waveform[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_pusch_decode_waveform(
            Span(nonfinite_waveform),
            config,
            Span(manual_tx.encoded_null_mask),
            manual_tx.profile,
            len(payload),
            modulation_order,
            redundancy_version,
            equalized_noise_variance,
        )


def test_nr_pucch_format2_encode_composition_oracle() raises:
    """Differential: UCI through waveform plus all wrapper checksums."""
    comptime absolute_tolerance = 1.0e-12
    comptime relative_tolerance = 1.0e-12
    var config = NRPUCCHFormat2Config(
        128, 1, 13, 3, 2, 48, 617, 50000, 0x7012
    )
    var payload = _payload(12, 5)
    var expected = _manual_pucch_format2_encode(Span(payload), config)
    var actual = nr_pucch_format2_encode(Span(payload), config)

    assert_equal(actual.payload, expected.payload)
    assert_equal(actual.coded_bits, expected.coded_bits)
    assert_equal(actual.scrambled_bits, expected.scrambled_bits)
    _assert_complex_lists_close(
        Span(actual.data_symbols),
        Span(expected.data_symbols),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_lists_close(
        Span(actual.dmrs),
        Span(expected.dmrs),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_grids_close(
        actual.grid,
        expected.grid,
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_lists_close(
        Span(actual.waveform),
        Span(expected.waveform),
        absolute_tolerance,
        relative_tolerance,
    )
    assert_equal(actual.uci_scheme, expected.uci_scheme)
    assert_equal(actual.code_blocks, expected.code_blocks)
    assert_equal(
        actual.payload_checksum, _fnv1a_binary(Span(expected.payload))
    )
    assert_equal(
        actual.coded_bits_checksum,
        _fnv1a_binary(Span(expected.coded_bits)),
    )
    assert_equal(
        actual.scrambled_bits_checksum,
        _fnv1a_binary(Span(expected.scrambled_bits)),
    )
    _assert_float_close(
        actual.grid_energy,
        _grid_energy(expected.grid),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_float_close(
        actual.waveform_energy,
        _complex_energy(Span(expected.waveform)),
        absolute_tolerance,
        relative_tolerance,
    )

    var invalid_payload = payload.copy()
    invalid_payload[4] = UInt8(2)
    with assert_raises():
        _ = nr_pucch_format2_encode(Span(invalid_payload), config)


def test_nr_pucch_format2_decode_composition_oracle() raises:
    """Differential: analytic flat-LS/ZF and standalone UCI receive stages."""
    comptime absolute_tolerance = 1.0e-9
    comptime relative_tolerance = 1.0e-10
    comptime sample_noise_variance = 1.0e-4
    var config = NRPUCCHFormat2Config(
        128, 1, 13, 3, 2, 48, 617, 50000, 0x7012
    )
    var payload = _payload(12, 5)

    # Build the receive input explicitly; the format-2 encode wrapper is not
    # part of this test's fixture path.
    var manual_tx = _manual_pucch_format2_encode(Span(payload), config)
    var gain = Complex64(0.75, -0.35)
    var received = _apply_flat_gain(Span(manual_tx.waveform), gain)

    # Analytic flat-channel reference checkpoints.  In an exact noiseless
    # channel each LS observation is gain and ZF restores each QPSK point.
    var expected_grid = NRResourceGrid(14, config.fft_size)
    for symbol in range(14):
        for subcarrier in range(config.fft_size):
            expected_grid[symbol, subcarrier] = (
                manual_tx.grid[symbol, subcarrier] * gain
            )
    var expected_received_dmrs = List[Complex64](
        capacity=len(manual_tx.dmrs)
    )
    var expected_ls = List[Complex64](capacity=len(manual_tx.dmrs))
    for dmrs in manual_tx.dmrs:
        expected_received_dmrs.append(dmrs * gain)
        expected_ls.append(gain)
    var expected_equalized = manual_tx.data_symbols.copy()
    var expected_equalized_noise_variance = (
        Float64(config.fft_size) * sample_noise_variance
        / gain.magnitude_squared()
    )
    var expected_raw_llrs = qam_demapper_llr_piecewise(
        Span(expected_equalized), 2, expected_equalized_noise_variance
    )
    var scrambling_sequence = nr_pucch_scramble(
        Span(List[UInt8](length=len(expected_raw_llrs), fill=UInt8(0))),
        config.rnti,
        config.n_id,
    )
    var expected_descrambled = List[Float64](
        capacity=len(expected_raw_llrs)
    )
    for index in range(len(expected_raw_llrs)):
        expected_descrambled.append(
            expected_raw_llrs[index]
            if scrambling_sequence[index] == 0
            else -expected_raw_llrs[index]
        )
    var expected_hard_bits = _hard_bits(Span(expected_descrambled))
    var expected_decoded = nr_uci_decode(
        Span(expected_descrambled), len(payload)
    )

    var actual = nr_pucch_format2_decode(
        Span(received),
        config,
        len(payload),
        sample_noise_variance,
        testcase_id="nr-pucch-f2-composition-oracle",
    )
    assert_equal(actual.payload, expected_decoded.bits)
    _assert_grids_close(
        actual.grid,
        expected_grid,
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_lists_close(
        Span(actual.received_dmrs),
        Span(expected_received_dmrs),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_lists_close(
        Span(actual.dmrs_ls_estimates),
        Span(expected_ls),
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_complex_close(
        actual.channel_estimate,
        gain,
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
        Span(actual.raw_llrs),
        Span(expected_raw_llrs),
        1.0e-8,
        relative_tolerance,
    )
    _assert_float_lists_close(
        Span(actual.descrambled_llrs),
        Span(expected_descrambled),
        1.0e-8,
        relative_tolerance,
    )
    assert_equal(actual.hard_coded_bits, expected_hard_bits)
    assert_equal(actual.uci_scheme, expected_decoded.scheme)
    assert_equal(actual.code_blocks, expected_decoded.code_blocks)
    assert_equal(actual.crc_ok, expected_decoded.crc_ok)
    assert_equal(actual.parity_ok, expected_decoded.parity_ok)
    assert_equal(
        actual.hard_coded_bits_checksum,
        _fnv1a_binary(Span(expected_hard_bits)),
    )
    _assert_float_close(
        actual.equalized_noise_variance,
        expected_equalized_noise_variance,
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_float_close(
        actual.decision_directed_evm,
        0.0,
        absolute_tolerance,
        relative_tolerance,
    )
    _assert_float_close(
        actual.maximum_symbol_error,
        0.0,
        absolute_tolerance,
        relative_tolerance,
    )
    assert_equal(actual.payload, payload)
    assert_true(actual.crc_ok and actual.parity_ok)

    # Check the complete metadata contract emitted alongside the numeric
    # checkpoints rather than merely asserting that metadata exists.
    assert_equal(len(actual.checkpoint_metadata), 9)
    var stages: List[String] = [
        "received-grid",
        "received-dmrs",
        "dmrs-ls-estimates",
        "channel-estimate",
        "equalized-symbols",
        "raw-llrs",
        "descrambled-llrs",
        "hard-coded-bits",
        "payload",
    ]
    var dtypes: List[String] = [
        "complex64",
        "complex64",
        "complex64",
        "complex64",
        "complex64",
        "float64",
        "float64",
        "uint8",
        "uint8",
    ]
    var shapes: List[String] = [
        "14x128", "8", "8", "1", "16", "32", "32", "32", "12"
    ]
    var strides: List[String] = [
        "128,1", "1", "1", "1", "1", "1", "1", "1", "1"
    ]
    var q_formats: List[String] = [
        "floating",
        "floating",
        "floating",
        "floating",
        "floating",
        "floating",
        "floating",
        "binary-u1",
        "binary-u1",
    ]
    var layouts: List[String] = [
        "row-major-iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
        "iq-interleaved",
        "linear",
        "linear",
        "bit-per-byte",
        "bit-per-byte",
    ]
    for index in range(9):
        assert_equal(
            actual.checkpoint_metadata[index].testcase_id,
            "nr-pucch-f2-composition-oracle",
        )
        assert_equal(actual.checkpoint_metadata[index].stage, stages[index])
        assert_equal(actual.checkpoint_metadata[index].dtype, dtypes[index])
        assert_equal(actual.checkpoint_metadata[index].shape, shapes[index])
        assert_equal(actual.checkpoint_metadata[index].stride, strides[index])
        assert_equal(
            actual.checkpoint_metadata[index].q_format, q_formats[index]
        )
        assert_equal(actual.checkpoint_metadata[index].layout, layouts[index])
        assert_equal(actual.checkpoint_metadata[index].scale, 1.0)
        assert_equal(actual.checkpoint_metadata[index].version, 1)

    var nonfinite_waveform = received.copy()
    nonfinite_waveform[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = nr_pucch_format2_decode(
            Span(nonfinite_waveform),
            config,
            len(payload),
            sample_noise_variance,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
