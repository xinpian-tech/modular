"""Independent evidence for bounded Rel-17 NR FR2-2/n263 algorithms."""

from std.testing import (
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
    TestSuite,
)
from std.utils.numerics import inf, nan
from wireless_dsp.wireless.nr.fr2_2_rel17 import (
    NR_FR2_2_REL17_BAND_N263,
    NR_FR2_2_REL17_N263_MAX_FREQUENCY_MHZ,
    NR_FR2_2_REL17_N263_MIN_FREQUENCY_MHZ,
    NR_FR2_2_REL17_SUBCARRIERS_PER_RB,
    NR_FR2_2_REL17_SYMBOLS_PER_SLOT,
    nr_fr2_2_rel17_carrier_config,
    nr_fr2_2_rel17_elapsed_slot_start_ns,
    nr_fr2_2_rel17_frequency_in_n263_mhz,
    nr_fr2_2_rel17_minimum_guardband_khz,
    nr_fr2_2_rel17_n263_2000mhz_exception_arfcn,
    nr_fr2_2_rel17_n263_arfcn_supported,
    nr_fr2_2_rel17_n263_center_frequency_hz,
    nr_fr2_2_rel17_n263_regular_arfcn,
    nr_fr2_2_rel17_n263_regular_arfcn_count,
    nr_fr2_2_rel17_nominal_channel_spacing_100khz,
    nr_fr2_2_rel17_numerology,
    nr_fr2_2_rel17_occupied_bandwidth_khz,
    nr_fr2_2_rel17_prach_allocation,
    nr_fr2_2_rel17_prach_allocation_subcarriers,
    nr_fr2_2_rel17_symbol_ordinal,
)


def test_official_numerology_slot_and_symbol_geometry_exact() raises:
    # External-static transcription of 38.211 Tables 4.2-1/4.3.2-1.
    var scs: List[Int] = [120, 480, 960]
    var mu: List[Int] = [3, 5, 6]
    var slots_per_subframe: List[Int] = [8, 32, 64]
    var slots_per_frame: List[Int] = [80, 320, 640]
    var slot_duration_ns: List[Int] = [125000, 31250, 15625]
    for index in range(3):
        var row = nr_fr2_2_rel17_numerology(scs[index])
        assert_equal(row.mu, mu[index])
        assert_equal(row.subcarrier_spacing_khz, scs[index])
        assert_equal(row.symbols_per_slot, 14)
        assert_equal(row.slots_per_subframe, slots_per_subframe[index])
        assert_equal(row.slots_per_frame, slots_per_frame[index])
        assert_equal(row.slot_duration_ns, slot_duration_ns[index])

        var frame = 17
        var slot = slots_per_frame[index] - 1
        var absolute_slot = frame * slots_per_frame[index] + slot
        assert_equal(
            nr_fr2_2_rel17_elapsed_slot_start_ns(row, frame, slot),
            absolute_slot * slot_duration_ns[index],
        )
        assert_equal(
            nr_fr2_2_rel17_symbol_ordinal(row, frame, slot, 13),
            absolute_slot * 14 + 13,
        )


def test_official_n263_carrier_tables_exhaustive_static_oracle() raises:
    # 38.101-2 V17.20.0 Tables 5.3.2-1, 5.3.3-1, 5.3.5-1.
    var scs: List[Int] = [120, 120, 480, 480, 480, 960, 960, 960, 960]
    var bandwidth: List[Int] = [
        100, 400, 400, 800, 1600, 400, 800, 1600, 2000
    ]
    var resource_blocks: List[Int] = [66, 264, 66, 124, 248, 33, 62, 124, 148]
    var guardband: List[Int] = [
        2420, 9860, 9680, 42640, 85520, 9440, 42400, 85280, 147040
    ]
    var optional_scs: List[Bool] = [
        False, False, True, True, True, True, True, True, True
    ]
    var optional_bandwidth: List[Bool] = [
        False, False, False, True, True, False, True, True, True
    ]
    for index in range(9):
        var row = nr_fr2_2_rel17_carrier_config(
            scs[index], bandwidth[index]
        )
        assert_equal(row.band, NR_FR2_2_REL17_BAND_N263)
        assert_equal(row.maximum_resource_blocks, resource_blocks[index])
        assert_equal(row.minimum_guardband_khz, guardband[index])
        assert_equal(row.optional_subcarrier_spacing, optional_scs[index])
        assert_equal(row.optional_channel_bandwidth, optional_bandwidth[index])

        var occupied = (
            resource_blocks[index]
            * NR_FR2_2_REL17_SUBCARRIERS_PER_RB
            * scs[index]
        )
        var independent_guard = (
            (bandwidth[index] * 1000 - occupied) // 2 - scs[index] // 2
        )
        assert_equal(
            nr_fr2_2_rel17_occupied_bandwidth_khz(row), occupied
        )
        assert_equal(independent_guard, guardband[index])
        assert_equal(
            nr_fr2_2_rel17_minimum_guardband_khz(row),
            independent_guard,
        )


def test_nominal_n263_channel_spacing_closed_form_exact() raises:
    var bw100 = nr_fr2_2_rel17_carrier_config(120, 100)
    var bw400 = nr_fr2_2_rel17_carrier_config(480, 400)
    var bw800 = nr_fr2_2_rel17_carrier_config(960, 800)
    var bw1600 = nr_fr2_2_rel17_carrier_config(960, 1600)
    var bw2000 = nr_fr2_2_rel17_carrier_config(960, 2000)
    # Independent integer expansion of ceil((BW1+BW2)/100.8)*50.4 MHz.
    assert_equal(
        nr_fr2_2_rel17_nominal_channel_spacing_100khz(bw100, bw400),
        2520,
    )
    assert_equal(
        nr_fr2_2_rel17_nominal_channel_spacing_100khz(bw800, bw1600),
        12096,
    )
    assert_equal(
        nr_fr2_2_rel17_nominal_channel_spacing_100khz(bw2000, bw2000),
        20160,
    )


def test_official_lra139_prach_table_exhaustive_static_oracle() raises:
    # Complete 3x3 n263 slice of 38.211 V17.10.0 Table 6.3.3.2-1.
    var prach_scs: List[Int] = [120, 120, 120, 480, 480, 480, 960, 960, 960]
    var pusch_scs: List[Int] = [120, 480, 960, 120, 480, 960, 120, 480, 960]
    var resource_blocks: List[Int] = [12, 3, 2, 48, 12, 6, 96, 24, 12]
    var k_bar: List[Int] = [2, 1, 23, 2, 2, 2, 2, 2, 2]
    for index in range(9):
        var row = nr_fr2_2_rel17_prach_allocation(
            prach_scs[index], pusch_scs[index]
        )
        assert_equal(row.sequence_length, 139)
        assert_equal(
            row.pusch_allocation_resource_blocks, resource_blocks[index]
        )
        assert_equal(row.k_bar, k_bar[index])
        assert_equal(
            nr_fr2_2_rel17_prach_allocation_subcarriers(row),
            resource_blocks[index] * 12,
        )


def test_n263_arfcn_tables_and_global_raster_exact() raises:
    # External-static transcription of 38.101-2 Table 5.4.2.3-2.
    var bandwidth: List[Int] = [100, 400, 800, 1600, 2000]
    var base: List[Int] = [2564083, 2566603, 2569963, 2576683, 2580043]
    var step: List[Int] = [1680, 6720, 6720, 6720, 6720]
    var max_n: List[Int] = [137, 33, 32, 30, 29]
    for row_index in range(5):
        assert_equal(
            nr_fr2_2_rel17_n263_regular_arfcn_count(
                bandwidth[row_index]
            ),
            max_n[row_index] + 1,
        )
        for n in range(max_n[row_index] + 1):
            var expected = base[row_index] + step[row_index] * n
            var actual = nr_fr2_2_rel17_n263_regular_arfcn(
                bandwidth[row_index], n
            )
            assert_equal(actual, expected)
            assert_true(
                nr_fr2_2_rel17_n263_arfcn_supported(
                    bandwidth[row_index], actual
                )
            )
            # 38.101-2 Table 5.4.2.1-1: 24.25008 GHz + 60 kHz delta.
            var expected_hz = (
                24250080000 + 60000 * (expected - 2016667)
            )
            assert_equal(
                nr_fr2_2_rel17_n263_center_frequency_hz(
                    bandwidth[row_index], actual
                ),
                expected_hz,
            )
        # Reject an in-range off-step value and the first value after every
        # bandwidth-specific regular sequence.
        assert_false(
            nr_fr2_2_rel17_n263_arfcn_supported(
                bandwidth[row_index], base[row_index] + 1
            )
        )
        assert_false(
            nr_fr2_2_rel17_n263_arfcn_supported(
                bandwidth[row_index],
                base[row_index] + step[row_index] * (max_n[row_index] + 1),
            )
        )

    var exceptional: List[Int] = [2585083, 2655643, 2692603, 2764843]
    for index in range(4):
        var actual = nr_fr2_2_rel17_n263_2000mhz_exception_arfcn(index)
        assert_equal(actual, exceptional[index])
        assert_true(nr_fr2_2_rel17_n263_arfcn_supported(2000, actual))
        assert_equal(
            nr_fr2_2_rel17_n263_center_frequency_hz(2000, actual),
            24250080000 + 60000 * (actual - 2016667),
        )


def test_seeded_integer_geometry_matches_independent_oracles() raises:
    var scs: List[Int] = [120, 120, 480, 480, 480, 960, 960, 960, 960]
    var bandwidth: List[Int] = [
        100, 400, 400, 800, 1600, 400, 800, 1600, 2000
    ]
    var resource_blocks: List[Int] = [66, 264, 66, 124, 248, 33, 62, 124, 148]
    var prach_scs: List[Int] = [120, 120, 120, 480, 480, 480, 960, 960, 960]
    var pusch_scs: List[Int] = [120, 480, 960, 120, 480, 960, 120, 480, 960]
    var prach_resource_blocks: List[Int] = [12, 3, 2, 48, 12, 6, 96, 24, 12]
    var prach_k_bar: List[Int] = [2, 1, 23, 2, 2, 2, 2, 2, 2]
    var arfcn_bandwidth: List[Int] = [100, 400, 800, 1600, 2000]
    var arfcn_base: List[Int] = [2564083, 2566603, 2569963, 2576683, 2580043]
    var arfcn_step: List[Int] = [1680, 6720, 6720, 6720, 6720]
    var arfcn_count: List[Int] = [138, 34, 33, 31, 30]
    var exceptional: List[Int] = [2585083, 2655643, 2692603, 2764843]
    var seed = UInt64(0x243F6A8885A308D3)
    for _ in range(257):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var row_index = Int(seed % UInt64(9))
        var carrier = nr_fr2_2_rel17_carrier_config(
            scs[row_index], bandwidth[row_index]
        )
        var expected_occupied = resource_blocks[row_index] * 12 * scs[row_index]
        assert_equal(
            nr_fr2_2_rel17_occupied_bandwidth_khz(carrier),
            expected_occupied,
        )
        assert_equal(
            nr_fr2_2_rel17_minimum_guardband_khz(carrier),
            (bandwidth[row_index] * 1000 - expected_occupied) // 2
            - scs[row_index] // 2,
        )
        var other_index = Int((seed >> 24) % UInt64(9))
        var other = nr_fr2_2_rel17_carrier_config(
            scs[other_index], bandwidth[other_index]
        )
        var sum_tenth_mhz = (
            bandwidth[row_index] + bandwidth[other_index]
        ) * 10
        assert_equal(
            nr_fr2_2_rel17_nominal_channel_spacing_100khz(
                carrier, other
            ),
            ((sum_tenth_mhz + 1007) // 1008) * 504,
        )

        var numerology = nr_fr2_2_rel17_numerology(scs[row_index])
        var frame = Int((seed >> 8) % UInt64(1000000))
        var slot = Int((seed >> 32) % UInt64(numerology.slots_per_frame))
        var symbol = Int((seed >> 48) % UInt64(14))
        var absolute_slot = frame * numerology.slots_per_frame + slot
        assert_equal(
            nr_fr2_2_rel17_elapsed_slot_start_ns(
                numerology, frame, slot
            ),
            absolute_slot * numerology.slot_duration_ns,
        )
        assert_equal(
            nr_fr2_2_rel17_symbol_ordinal(
                numerology, frame, slot, symbol
            ),
            absolute_slot * 14 + symbol,
        )

        var prach_index = Int((seed >> 12) % UInt64(9))
        var allocation = nr_fr2_2_rel17_prach_allocation(
            prach_scs[prach_index], pusch_scs[prach_index]
        )
        assert_equal(
            allocation.pusch_allocation_resource_blocks,
            prach_resource_blocks[prach_index],
        )
        assert_equal(allocation.k_bar, prach_k_bar[prach_index])
        assert_equal(
            nr_fr2_2_rel17_prach_allocation_subcarriers(allocation),
            prach_resource_blocks[prach_index] * 12,
        )

        var arfcn_row = Int((seed >> 20) % UInt64(5))
        var count = nr_fr2_2_rel17_n263_regular_arfcn_count(
            arfcn_bandwidth[arfcn_row]
        )
        assert_equal(count, arfcn_count[arfcn_row])
        var n = Int((seed >> 36) % UInt64(count))
        var expected_arfcn = (
            arfcn_base[arfcn_row] + arfcn_step[arfcn_row] * n
        )
        var actual_arfcn = nr_fr2_2_rel17_n263_regular_arfcn(
            arfcn_bandwidth[arfcn_row], n
        )
        assert_equal(actual_arfcn, expected_arfcn)
        assert_true(
            nr_fr2_2_rel17_n263_arfcn_supported(
                arfcn_bandwidth[arfcn_row], actual_arfcn
            )
        )
        assert_equal(
            nr_fr2_2_rel17_n263_center_frequency_hz(
                arfcn_bandwidth[arfcn_row], actual_arfcn
            ),
            24250080000 + 60000 * (expected_arfcn - 2016667),
        )
        var exception_index = Int((seed >> 52) & UInt64(3))
        assert_equal(
            nr_fr2_2_rel17_n263_2000mhz_exception_arfcn(
                exception_index
            ),
            exceptional[exception_index],
        )

        var frequency_mhz = 56000.0 + Float64(seed % UInt64(16001))
        var expected_membership = (
            frequency_mhz >= 57000.0 and frequency_mhz <= 71000.0
        )
        assert_equal(
            nr_fr2_2_rel17_frequency_in_n263_mhz(frequency_mhz),
            expected_membership,
        )


def test_mutation_nonfinite_invalid_and_overflow_edges() raises:
    with assert_raises():
        _ = nr_fr2_2_rel17_numerology(240)
    var numerology = nr_fr2_2_rel17_numerology(480)
    with assert_raises():
        _ = nr_fr2_2_rel17_elapsed_slot_start_ns(numerology, -1, 0)
    with assert_raises():
        _ = nr_fr2_2_rel17_elapsed_slot_start_ns(numerology, 0, 320)
    with assert_raises():
        _ = nr_fr2_2_rel17_symbol_ordinal(numerology, 0, 0, 14)
    with assert_raises():
        _ = nr_fr2_2_rel17_elapsed_slot_start_ns(numerology, Int.MAX, 0)
    with assert_raises():
        _ = nr_fr2_2_rel17_symbol_ordinal(numerology, Int.MAX, 0, 0)
    numerology.slots_per_frame = 319
    with assert_raises():
        _ = nr_fr2_2_rel17_elapsed_slot_start_ns(numerology, 0, 0)
    with assert_raises():
        _ = nr_fr2_2_rel17_symbol_ordinal(numerology, 0, 0, 0)

    with assert_raises():
        _ = nr_fr2_2_rel17_carrier_config(480, 100)
    var carrier = nr_fr2_2_rel17_carrier_config(480, 400)
    carrier.maximum_resource_blocks = Int.MAX
    with assert_raises():
        _ = nr_fr2_2_rel17_occupied_bandwidth_khz(carrier)
    with assert_raises():
        _ = nr_fr2_2_rel17_minimum_guardband_khz(carrier)
    with assert_raises():
        _ = nr_fr2_2_rel17_nominal_channel_spacing_100khz(
            carrier, nr_fr2_2_rel17_carrier_config(120, 100)
        )

    with assert_raises():
        _ = nr_fr2_2_rel17_prach_allocation(240, 480)
    var allocation = nr_fr2_2_rel17_prach_allocation(480, 960)
    allocation.k_bar = Int.MAX
    with assert_raises():
        _ = nr_fr2_2_rel17_prach_allocation_subcarriers(allocation)

    with assert_raises():
        _ = nr_fr2_2_rel17_n263_regular_arfcn_count(200)
    with assert_raises():
        _ = nr_fr2_2_rel17_n263_regular_arfcn(100, -1)
    with assert_raises():
        _ = nr_fr2_2_rel17_n263_regular_arfcn(100, 138)
    with assert_raises():
        _ = nr_fr2_2_rel17_n263_2000mhz_exception_arfcn(4)
    assert_false(nr_fr2_2_rel17_n263_arfcn_supported(100, 2564082))
    assert_false(nr_fr2_2_rel17_n263_arfcn_supported(1600, 2585083))
    with assert_raises():
        _ = nr_fr2_2_rel17_n263_center_frequency_hz(100, 2564082)

    assert_true(
        nr_fr2_2_rel17_frequency_in_n263_mhz(
            NR_FR2_2_REL17_N263_MIN_FREQUENCY_MHZ
        )
    )
    assert_true(
        nr_fr2_2_rel17_frequency_in_n263_mhz(
            NR_FR2_2_REL17_N263_MAX_FREQUENCY_MHZ
        )
    )
    assert_false(nr_fr2_2_rel17_frequency_in_n263_mhz(56999.999))
    assert_false(nr_fr2_2_rel17_frequency_in_n263_mhz(71000.001))
    with assert_raises():
        _ = nr_fr2_2_rel17_frequency_in_n263_mhz(nan[DType.float64]())
    with assert_raises():
        _ = nr_fr2_2_rel17_frequency_in_n263_mhz(inf[DType.float64]())

    assert_equal(NR_FR2_2_REL17_SYMBOLS_PER_SLOT, 14)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
