"""Acceptance evidence for the bounded Rel-17 RedCap FR1 20-MHz chains."""

from std.collections import Span
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.testing.checkpoint import (
    CheckpointMetadata,
    checkpoint_bits_checksum,
)
from wireless_dsp.wireless.nr.redcap_chain import (
    NRRedCapRel17FR120MHzChainConfig,
    nr_redcap_rel17_fr1_20mhz_downlink,
    nr_redcap_rel17_fr1_20mhz_uplink,
)


def _oracle_mib(config: NRRedCapRel17FR120MHzChainConfig) -> List[UInt8]:
    """Independent integer transcription of the declared MIB fixture."""
    var result = List[UInt8](length=24, fill=UInt8(0))
    for index in range(6):
        result[index] = UInt8(
            (config.system_frame_number // (1 << (9 - index))) % 2
        )
    for index in range(6, 24):
        result[index] = UInt8(
            (
                config.physical_cell_id
                + 5 * index
                + config.rnti
                + (
                    config.system_frame_number
                    // (1 << (index % 10))
                )
            ) % 2
        )
    return result^


def _oracle_dci(
    mib: Span[UInt8, ...], config: NRRedCapRel17FR120MHzChainConfig
) -> List[UInt8]:
    """Independent combination oracle for decoded MIB -> DCI wiring."""
    var result = List[UInt8](length=32, fill=UInt8(0))
    for index in range(32):
        var rnti_bit = (config.rnti // (1 << (index % 16))) % 2
        var sfn_bit = (
            config.system_frame_number // (1 << (index % 10))
        ) % 2
        result[index] = UInt8(
            (Int(mib[(7 * index + 3) % 24]) + rnti_bit + sfn_bit) % 2
        )
    return result^


def _oracle_downlink_payload(
    dci: Span[UInt8, ...],
    mib: Span[UInt8, ...],
    config: NRRedCapRel17FR120MHzChainConfig,
) -> List[UInt8]:
    """Independent combination oracle for DCI/MIB -> DL-SCH payload."""
    var result = List[UInt8](length=128, fill=UInt8(0))
    for index in range(128):
        var pci_bit = (
            config.physical_cell_id // (1 << (index % 10))
        ) % 2
        result[index] = UInt8(
            (
                Int(dci[(11 * index + 1) % 32])
                + Int(mib[(5 * index + 2) % 24])
                + pci_bit
            ) % 2
        )
    return result^


def _oracle_uplink_payload(
    preamble: Int, config: NRRedCapRel17FR120MHzChainConfig
) -> List[UInt8]:
    """Independent combination oracle for detected PRACH -> UL-SCH."""
    var result = List[UInt8](length=128, fill=UInt8(0))
    for index in range(128):
        var pattern = (preamble + 3 * index + index // 7) % 2
        var rnti_bit = (config.rnti // (1 << (index % 16))) % 2
        var pci_bit = (
            config.physical_cell_id // (1 << (index % 10))
        ) % 2
        result[index] = UInt8((pattern + rnti_bit + pci_bit) % 2)
    return result^


def _oracle_uci(
    pusch: Span[UInt8, ...],
    crc_ok: Bool,
    config: NRRedCapRel17FR120MHzChainConfig,
) -> List[UInt8]:
    """Independent combination oracle for decoded UL-SCH -> UCI."""
    var result = List[UInt8](length=12, fill=UInt8(0))
    result[0] = UInt8(1) if crc_ok else UInt8(0)
    for index in range(1, 12):
        var sfn_bit = (
            config.system_frame_number // (1 << (index % 10))
        ) % 2
        result[index] = UInt8(
            (Int(pusch[(13 * index + 5) % len(pusch)]) + sfn_bit) % 2
        )
    return result^


def _assert_testcase(
    metadata: List[CheckpointMetadata], testcase_id: StringSlice
) raises:
    assert_true(len(metadata) > 0)
    for index in range(len(metadata)):
        assert_equal(metadata[index].testcase_id, testcase_id)
        assert_true(metadata[index].stage.byte_length() > 0)
        assert_true(metadata[index].dtype.byte_length() > 0)
        assert_true(metadata[index].shape.byte_length() > 0)
        assert_true(metadata[index].stride.byte_length() > 0)
        assert_true(metadata[index].q_format.byte_length() > 0)
        assert_true(metadata[index].layout.byte_length() > 0)
        assert_equal(metadata[index].scale, 1.0)
        assert_equal(metadata[index].version, 1)


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    assert_true(abs(actual.re - expected.re) <= tolerance)
    assert_true(abs(actual.im - expected.im) <= tolerance)


def test_downlink_deterministic_chain_and_independent_wiring_oracle() raises:
    var config = NRRedCapRel17FR120MHzChainConfig()
    var result = nr_redcap_rel17_fr1_20mhz_downlink(
        config, testcase_id="redcap-dl-static"
    )
    assert_true(result.complete)
    assert_equal(result.capabilities.channel_bandwidth_mhz, 20.0)
    assert_equal(result.capabilities.rx_branches, 1)
    assert_equal(result.capabilities.dl_layers, 1)
    assert_equal(result.capabilities.tx_branches, 1)
    assert_equal(result.capabilities.ul_layers, 1)
    assert_equal(result.initial_access.dl_bwp.resource_blocks, 51)
    assert_equal(result.initial_access.ul_bwp.resource_blocks, 51)
    assert_equal(result.initial_access.dl_bwp.subcarrier_spacing_khz, 30)
    assert_equal(result.ra_first_cces, [0, 4])

    assert_equal(result.pss_detection.offset, 5)
    assert_equal(result.pss_detection.n_id_2, config.physical_cell_id % 3)
    assert_equal(result.sss_detection.physical_cell_id, config.physical_cell_id)
    assert_true(abs(result.pss_detection.metric - 1.0) <= 1.0e-12)
    assert_true(abs(result.sss_detection.metric - 1.0) <= 1.0e-12)

    var expected_mib = _oracle_mib(config)
    assert_equal(result.mib_bits, expected_mib)
    assert_equal(result.pbch_decode.mib_bits, expected_mib)
    assert_equal(result.pbch_decode.system_frame_number, config.system_frame_number)
    assert_true(result.pbch_decode.crc_ok)
    var expected_dci = _oracle_dci(Span(expected_mib), config)
    assert_equal(result.dci_payload, expected_dci)
    assert_equal(result.pdcch_decode.payload, expected_dci)
    assert_true(result.pdcch_decode.crc_ok)
    var expected_payload = _oracle_downlink_payload(
        Span(expected_dci), Span(expected_mib), config
    )
    assert_equal(result.pdsch_payload, expected_payload)
    assert_equal(result.pdsch_decode.payload, expected_payload)
    assert_true(result.pdsch_decode.ldpc_converged)
    assert_true(result.pdsch_decode.code_block_crc_ok)
    assert_true(result.pdsch_decode.transport_crc_ok)
    assert_equal(result.pdsch_config.resource_blocks, 51)
    assert_equal(result.pdsch_config.fft_size, 1024)
    assert_equal(len(result.pdsch_waveform), 1096)
    for index in range(len(result.pdsch_transmit.symbols)):
        _assert_complex_close(
            result.pdsch_decode.equalized_symbols[index],
            result.pdsch_transmit.symbols[index],
            2.0e-9,
        )

    _assert_testcase(result.checkpoint_metadata, "redcap-dl-static")
    _assert_testcase(result.pbch_transmit.checkpoint_metadata, "redcap-dl-static")
    _assert_testcase(result.pbch_decode.checkpoint_metadata, "redcap-dl-static")
    _assert_testcase(result.pdcch_transmit.checkpoint_metadata, "redcap-dl-static")
    _assert_testcase(result.pdcch_decode.checkpoint_metadata, "redcap-dl-static")
    _assert_testcase(result.pdsch_transmit.checkpoint_metadata, "redcap-dl-static")
    _assert_testcase(result.pdsch_decode.checkpoint_metadata, "redcap-dl-static")
    assert_equal(result.checkpoint_metadata[0].stage, "redcap-fr1-20mhz-profile")
    assert_equal(result.checkpoint_metadata[6].shape, "1x1024")


def test_uplink_deterministic_chain_and_independent_wiring_oracle() raises:
    var config = NRRedCapRel17FR120MHzChainConfig()
    var result = nr_redcap_rel17_fr1_20mhz_uplink(
        config, testcase_id="redcap-ul-static"
    )
    assert_true(result.complete)
    assert_equal(result.capabilities.channel_bandwidth_mhz, 20.0)
    assert_equal(result.initial_access.ul_bwp.resource_blocks, 51)
    assert_equal(result.prach.parameters.sequence_length, 139)
    assert_equal(result.prach.parameters.numerology, 1)
    assert_equal(result.prach.detection.preamble_index, config.prach_preamble_index)
    assert_true(result.prach.detection.metric > 0.999999999)

    var expected_pusch = _oracle_uplink_payload(
        result.prach.detection.preamble_index, config
    )
    assert_equal(result.pusch_payload, expected_pusch)
    assert_equal(result.pusch_decode.payload, expected_pusch)
    assert_equal(result.pusch_config.resource_blocks, 51)
    assert_equal(result.pusch_config.symbol_count, 2)
    assert_true(result.pusch_decode.ldpc_converged)
    assert_true(result.pusch_decode.code_block_crc_ok)
    assert_true(result.pusch_decode.transport_crc_ok)
    for index in range(len(result.pusch_transmit.modulated_symbols)):
        _assert_complex_close(
            result.pusch_decode.equalized_symbols[index],
            result.pusch_transmit.modulated_symbols[index],
            2.0e-9,
        )

    var expected_uci = _oracle_uci(
        Span(expected_pusch), result.pusch_decode.transport_crc_ok, config
    )
    assert_equal(result.uci_payload, expected_uci)
    assert_equal(result.pucch_decode.payload, expected_uci)
    assert_true(result.pucch_decode.crc_ok)
    assert_true(result.pucch_decode.parity_ok)
    assert_true(result.pucch_decode.decision_directed_evm <= 2.0e-9)
    assert_true(result.pucch_decode.maximum_symbol_error <= 2.0e-9)

    _assert_testcase(result.checkpoint_metadata, "redcap-ul-static")
    _assert_testcase(result.prach.checkpoint_metadata, "redcap-ul-static")
    _assert_testcase(result.pusch_transmit.checkpoint_metadata, "redcap-ul-static")
    _assert_testcase(result.pusch_decode.checkpoint_metadata, "redcap-ul-static")
    _assert_testcase(result.pucch_transmit.checkpoint_metadata, "redcap-ul-static")
    _assert_testcase(result.pucch_decode.checkpoint_metadata, "redcap-ul-static")
    assert_equal(result.checkpoint_metadata[0].stage, "redcap-fr1-20mhz-profile")
    assert_equal(result.checkpoint_metadata[2].shape, "2x1024")
    assert_equal(result.checkpoint_metadata[6].shape, "14x1024")


def test_seeded_profile_property_and_direct_differential_oracles() raises:
    var physical_cell_ids: List[Int] = [0, 503, 1007]
    var frame_numbers: List[Int] = [0, 511, 1023]
    var rntis: List[Int] = [1, 0x4321, 0xFFFF]
    var preambles: List[Int] = [0, 31, 63]
    var combined_checksum = UInt64(1469598103934665603)
    for index in range(3):
        var config = NRRedCapRel17FR120MHzChainConfig(
            physical_cell_ids[index],
            frame_numbers[index],
            index & 1,
            (3 * index) % 8,
            rntis[index],
            preambles[index],
        )
        var downlink = nr_redcap_rel17_fr1_20mhz_downlink(
            config, testcase_id="redcap-dl-property"
        )
        var expected_mib = _oracle_mib(config)
        var expected_dci = _oracle_dci(Span(expected_mib), config)
        var expected_dl = _oracle_downlink_payload(
            Span(expected_dci), Span(expected_mib), config
        )
        assert_true(downlink.complete)
        assert_equal(downlink.pbch_decode.mib_bits, expected_mib)
        assert_equal(downlink.pdcch_decode.payload, expected_dci)
        assert_equal(downlink.pdsch_decode.payload, expected_dl)

        var uplink = nr_redcap_rel17_fr1_20mhz_uplink(
            config, testcase_id="redcap-ul-property"
        )
        var expected_ul = _oracle_uplink_payload(preambles[index], config)
        var expected_uci = _oracle_uci(Span(expected_ul), True, config)
        assert_true(uplink.complete)
        assert_equal(uplink.prach.detection.preamble_index, preambles[index])
        assert_equal(uplink.pusch_decode.payload, expected_ul)
        assert_equal(uplink.pucch_decode.payload, expected_uci)
        combined_checksum ^= checkpoint_bits_checksum(Span(expected_dl))
        combined_checksum *= UInt64(1099511628211)
        combined_checksum ^= checkpoint_bits_checksum(Span(expected_ul))
    assert_true(combined_checksum != UInt64(0))


def test_profile_invalid_edges_mutation_and_testcase_ownership() raises:
    with assert_raises():
        _ = NRRedCapRel17FR120MHzChainConfig(-1, 0, 0, 0, 1, 0)
    with assert_raises():
        _ = NRRedCapRel17FR120MHzChainConfig(1008, 0, 0, 0, 1, 0)
    with assert_raises():
        _ = NRRedCapRel17FR120MHzChainConfig(0, -1, 0, 0, 1, 0)
    with assert_raises():
        _ = NRRedCapRel17FR120MHzChainConfig(0, 1024, 0, 0, 1, 0)
    with assert_raises():
        _ = NRRedCapRel17FR120MHzChainConfig(0, 0, 2, 0, 1, 0)
    with assert_raises():
        _ = NRRedCapRel17FR120MHzChainConfig(0, 0, 0, 8, 1, 0)
    with assert_raises():
        _ = NRRedCapRel17FR120MHzChainConfig(0, 0, 0, 0, 0, 0)
    with assert_raises():
        _ = NRRedCapRel17FR120MHzChainConfig(0, 0, 0, 0, 1, 64)
    with assert_raises():
        _ = NRRedCapRel17FR120MHzChainConfig(Int.MAX, Int.MAX, 0, 0, 1, 0)

    var mutated = NRRedCapRel17FR120MHzChainConfig()
    mutated.physical_cell_id = -1
    with assert_raises():
        _ = nr_redcap_rel17_fr1_20mhz_downlink(mutated)
    mutated = NRRedCapRel17FR120MHzChainConfig()
    mutated.prach_preamble_index = 64
    with assert_raises():
        _ = nr_redcap_rel17_fr1_20mhz_uplink(mutated)
    var valid = NRRedCapRel17FR120MHzChainConfig()
    with assert_raises():
        _ = nr_redcap_rel17_fr1_20mhz_downlink(valid, testcase_id="")
    with assert_raises():
        _ = nr_redcap_rel17_fr1_20mhz_uplink(
            valid, testcase_id="invalid\nidentifier"
        )


def test_exact_replay_and_continuous_tolerance_contract() raises:
    var config = NRRedCapRel17FR120MHzChainConfig(
        42, 321, 0, 3, 0x7012, 9
    )
    var first_dl = nr_redcap_rel17_fr1_20mhz_downlink(config)
    var second_dl = nr_redcap_rel17_fr1_20mhz_downlink(config)
    assert_equal(
        checkpoint_bits_checksum(Span(first_dl.pbch_transmit.physical_channel_bits)),
        checkpoint_bits_checksum(Span(second_dl.pbch_transmit.physical_channel_bits)),
    )
    assert_equal(
        checkpoint_bits_checksum(Span(first_dl.pdcch_transmit.scrambled)),
        checkpoint_bits_checksum(Span(second_dl.pdcch_transmit.scrambled)),
    )
    assert_equal(
        checkpoint_bits_checksum(Span(first_dl.pdsch_transmit.scrambled_bits)),
        checkpoint_bits_checksum(Span(second_dl.pdsch_transmit.scrambled_bits)),
    )
    for index in range(len(first_dl.pdsch_decode.equalized_symbols)):
        _assert_complex_close(
            first_dl.pdsch_decode.equalized_symbols[index],
            second_dl.pdsch_decode.equalized_symbols[index],
            0.0,
        )

    var first_ul = nr_redcap_rel17_fr1_20mhz_uplink(config)
    var second_ul = nr_redcap_rel17_fr1_20mhz_uplink(config)
    assert_equal(
        checkpoint_bits_checksum(Span(first_ul.pusch_transmit.scrambled_bits)),
        checkpoint_bits_checksum(Span(second_ul.pusch_transmit.scrambled_bits)),
    )
    assert_equal(
        first_ul.pucch_transmit.scrambled_bits_checksum,
        second_ul.pucch_transmit.scrambled_bits_checksum,
    )
    assert_true(first_ul.pucch_decode.decision_directed_evm <= 2.0e-9)
    assert_true(second_ul.pucch_decode.decision_directed_evm <= 2.0e-9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
