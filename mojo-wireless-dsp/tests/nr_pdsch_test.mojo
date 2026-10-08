from std.testing import assert_equal, assert_true, TestSuite
from wireless_dsp.core import Complex64, Span
from wireless_dsp.modem import qam_map, qam_demapper_llr_maxlog, hard_bits_from_llr
from wireless_dsp.wireless.nr import (
    NRNumerology,
    NRResourceGrid,
    nr_normal_cp_samples,
    nr_pdsch_dmrs_c_init,
    nr_pdsch_dmrs,
    nr_pdsch_scramble,
    nr_pdsch_descramble_llrs,
    nr_transport_crc_append,
    nr_transport_crc_check,
    nr_map_pdsch_comb2,
    nr_extract_pdsch_comb2,
    nr_extract_dmrs_comb2,
    nr_ls_channel_estimate_comb2,
    nr_equalize_pdsch_comb2,
    nr_pss,
    nr_sss,
    nr_search_pss,
    nr_detect_sss,
    nr_pbch_dmrs_c_init,
    nr_pbch_dmrs,
    nr_map_ssb_synchronization,
)


def test_nr_numerology_and_cp_boundaries() raises:
    for mu in range(5):
        var numerology = NRNumerology(mu)
        assert_equal(numerology.subcarrier_spacing_hz, 15000 * (1 << mu))
        assert_equal(numerology.slots_per_frame, 10 * (1 << mu))
        assert_equal(numerology.symbols_per_slot, 14)
    var extended = NRNumerology(2, extended_cp=True)
    assert_equal(extended.symbols_per_slot, 12)
    assert_equal(nr_normal_cp_samples(2048, 0, 0), 160)
    assert_equal(nr_normal_cp_samples(2048, 1, 0), 144)
    assert_equal(nr_normal_cp_samples(2048, 7, 0), 160)
    assert_equal(nr_normal_cp_samples(2048, 0, 1, slot_in_subframe=0), 176)
    assert_equal(nr_normal_cp_samples(2048, 0, 1, slot_in_subframe=1), 176)


def test_nr_transport_crc_append_and_detection() raises:
    var payload: List[UInt8] = [1, 0, 1, 1, 0, 1, 0, 0, 1]
    var codeword = nr_transport_crc_append(Span(payload))
    assert_true(nr_transport_crc_check(Span(codeword), len(payload)))
    codeword[2] ^= 1
    assert_true(not nr_transport_crc_check(Span(codeword), len(payload)))


def test_nr_pdsch_front_end_checkpoint_chain() raises:
    # Five QPSK data REs interleaved with six comb-2 DM-RS REs.
    var payload: List[UInt8] = [1, 0, 0, 1, 1, 1, 0, 0, 1, 0]
    var scrambled = nr_pdsch_scramble(Span(payload), 0x1234, 0, 42)
    var data_symbols = qam_map(Span(scrambled), 2)
    var c_init = nr_pdsch_dmrs_c_init(3, 2, 42, 0)
    var dmrs = nr_pdsch_dmrs(c_init, 6)
    var transmit = NRResourceGrid(14, 24)
    nr_map_pdsch_comb2(
        transmit, 2, 4, 11, 0, Span(data_symbols), Span(dmrs)
    )

    var channel = Complex64(0.8, 0.3)
    var received = NRResourceGrid(14, 24)
    for local in range(11):
        received[2, 4 + local] = transmit[2, 4 + local] * channel
    var received_dmrs = nr_extract_dmrs_comb2(received, 2, 4, 11, 0)
    var estimate = nr_ls_channel_estimate_comb2(
        Span(received_dmrs), Span(dmrs), 11, 0
    )
    for value in estimate:
        assert_true(abs(value.re - channel.re) < 1.0e-12)
        assert_true(abs(value.im - channel.im) < 1.0e-12)
    var received_data = nr_extract_pdsch_comb2(received, 2, 4, 11, 0)
    var equalized = nr_equalize_pdsch_comb2(Span(received_data), Span(estimate), 0)
    var llrs = qam_demapper_llr_maxlog(Span(equalized), 2, 0.01)
    var descrambled = nr_pdsch_descramble_llrs(Span(llrs), 0x1234, 0, 42)
    assert_equal(hard_bits_from_llr(Span(descrambled)), payload)


def test_nr_pss_timing_and_full_cell_identity_detection() raises:
    var pss = nr_pss(2)
    var samples = List[Complex64](capacity=137)
    for _ in range(10):
        samples.append(Complex64(0.0, 0.0))
    # Include an arbitrary common phase to prove noncoherent PSS detection.
    var phase = Complex64(0.6, 0.8)
    for value in pss:
        samples.append(Complex64(value, 0.0) * phase)
    var detection = nr_search_pss(Span(samples))
    assert_equal(detection.offset, 10)
    assert_equal(detection.n_id_2, 2)
    assert_true(abs(detection.metric - 1.0) < 1.0e-12)
    assert_true(abs(detection.phase_re - 0.6) < 1.0e-12)
    assert_true(abs(detection.phase_im - 0.8) < 1.0e-12)

    # Cell search is invariant to every finite common amplitude scale.
    var scales: List[Float64] = [1.0e-300, 1.0e300]
    for scale in scales:
        var scaled_samples = List[Complex64](capacity=len(samples))
        for sample in samples:
            scaled_samples.append(Complex64(sample.re * scale, sample.im * scale))
        var scaled_detection = nr_search_pss(Span(scaled_samples))
        assert_equal(scaled_detection.offset, 10)
        assert_equal(scaled_detection.n_id_2, 2)
        assert_true(abs(scaled_detection.metric - 1.0) < 1.0e-12)
        assert_true(abs(scaled_detection.phase_re - 0.6) < 1.0e-12)
        assert_true(abs(scaled_detection.phase_im - 0.8) < 1.0e-12)

    var sss = nr_sss(321, 2)
    var received_sss = List[Complex64](capacity=127)
    for value in sss:
        received_sss.append(Complex64(value, 0.0))
    var cell = nr_detect_sss(Span(received_sss), 2)
    assert_equal(cell.n_id_1, 321)
    assert_equal(cell.physical_cell_id, 965)
    assert_true(abs(cell.metric - 1.0) < 1.0e-12)
    for scale in scales:
        var scaled_sss = List[Complex64](capacity=len(received_sss))
        for sample in received_sss:
            scaled_sss.append(Complex64(sample.re * scale, sample.im * scale))
        var scaled_cell = nr_detect_sss(Span(scaled_sss), 2)
        assert_equal(scaled_cell.n_id_1, 321)
        assert_equal(scaled_cell.physical_cell_id, 965)
        assert_true(abs(scaled_cell.metric - 1.0) < 1.0e-12)


def test_nr_ssb_mapping_and_pbch_dmrs() raises:
    var pss = nr_pss(1)
    var sss = nr_sss(10, 1)
    var grid = NRResourceGrid(4, 256)
    nr_map_ssb_synchronization(grid, 8, Span(pss), Span(sss))
    assert_equal(grid[0, 64], Complex64(pss[0], 0.0))
    assert_equal(grid[2, 64 + 126], Complex64(sss[126], 0.0))
    assert_equal(grid[1, 64], Complex64(0.0, 0.0))
    assert_equal(
        nr_pbch_dmrs_c_init(42, 1, 0, 4),
        UInt32((1 << 11) * 2 * 11 + (1 << 6) * 2 + 2),
    )
    var dmrs = nr_pbch_dmrs(42, 1, 0, 4)
    assert_equal(len(dmrs), 144)
    var energy = 0.0
    for value in dmrs:
        energy += value.magnitude_squared()
    assert_true(abs(energy - 144.0) < 1.0e-12)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
