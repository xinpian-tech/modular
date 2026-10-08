"""Independent evidence for non-grouped NR PDCCH monitoring occasions.

The literal periodicity table, repeated-increment slot oracle, arithmetic
bit-string decoder, and occupied-symbol interval oracle are independent of
the production branches.  Evidence covers the SearchSpace fields and
``ControlResourceSet.duration`` domain in TS 38.331 V18.10.0 clause 6.3.2,
jointly with the non-grouped monitoring-occasion rule in TS 38.213 V18.8.0
clause 10.1.
"""

from std.collections import Span
from std.testing import assert_equal, assert_raises, TestSuite
from wireless_dsp.wireless.nr.pdcch_monitoring import (
    NR_PDCCH_MONITORING_SL1,
    NR_PDCCH_MONITORING_SL2,
    NR_PDCCH_MONITORING_SL4,
    NR_PDCCH_MONITORING_SL5,
    NR_PDCCH_MONITORING_SL8,
    NR_PDCCH_MONITORING_SL10,
    NR_PDCCH_MONITORING_SL16,
    NR_PDCCH_MONITORING_SL20,
    NR_PDCCH_MONITORING_SL40,
    NR_PDCCH_MONITORING_SL80,
    NR_PDCCH_MONITORING_SL160,
    NR_PDCCH_MONITORING_SL320,
    NR_PDCCH_MONITORING_SL640,
    NR_PDCCH_MONITORING_SL1280,
    NR_PDCCH_MONITORING_SL2560,
    NRPDCCHMonitoringPattern,
    nr_pdcch_monitoring_periodicity,
    nr_pdcch_monitoring_pattern,
    nr_pdcch_is_monitoring_slot,
    nr_pdcch_monitoring_first_symbols,
    nr_pdcch_is_monitoring_occasion,
)


def _literal_choices() -> List[Int]:
    # Independent zero-based declaration indexes, not production constants.
    return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]


def _exported_choices() -> List[Int]:
    return [
        NR_PDCCH_MONITORING_SL1,
        NR_PDCCH_MONITORING_SL2,
        NR_PDCCH_MONITORING_SL4,
        NR_PDCCH_MONITORING_SL5,
        NR_PDCCH_MONITORING_SL8,
        NR_PDCCH_MONITORING_SL10,
        NR_PDCCH_MONITORING_SL16,
        NR_PDCCH_MONITORING_SL20,
        NR_PDCCH_MONITORING_SL40,
        NR_PDCCH_MONITORING_SL80,
        NR_PDCCH_MONITORING_SL160,
        NR_PDCCH_MONITORING_SL320,
        NR_PDCCH_MONITORING_SL640,
        NR_PDCCH_MONITORING_SL1280,
        NR_PDCCH_MONITORING_SL2560,
    ]


def _literal_periodicities() -> List[Int]:
    # SearchSpace.monitoringSlotPeriodicityAndOffset declaration order.
    return [1, 2, 4, 5, 8, 10, 16, 20, 40, 80, 160, 320, 640, 1280, 2560]


def _oracle_monitoring_slot(
    periodicity: Int, offset: Int, duration: Int, absolute_slot: Int
) -> Bool:
    # Independent finite-cycle construction: walk forward from the offset and
    # wrap explicitly.  Production instead normalizes a signed distance.
    var target = absolute_slot % periodicity
    var monitored_residue = offset
    for _ in range(duration):
        if target == monitored_residue:
            return True
        monitored_residue += 1
        if monitored_residue == periodicity:
            monitored_residue = 0
    return False


def _oracle_first_symbols(mask: Int, extended_cp: Bool) -> List[Int]:
    # Read the 14-bit value as descending arithmetic weights.  This does not
    # share the production decoder's shift-by-symbol implementation.
    var result = List[Int]()
    var weight = 8192
    var symbol_count = 12 if extended_cp else 14
    for symbol in range(14):
        if symbol < symbol_count and (mask // weight) % 2 == 1:
            result.append(symbol)
        weight //= 2
    return result^


def _oracle_symbol_configuration_valid(
    first_symbols: Span[Int, ...],
    coreset_duration_symbols: Int,
    extended_cp: Bool,
) -> Bool:
    # Independently paint each half-open CORESET interval into a finite slot.
    # A crossing or an already-painted symbol makes the configuration invalid.
    var symbol_count = 12 if extended_cp else 14
    var occupied = List[Bool](length=symbol_count, fill=False)
    for index in range(len(first_symbols)):
        var start = first_symbols[index]
        if start < 0 or start >= symbol_count:
            return False
        for delta in range(coreset_duration_symbols):
            var symbol = start + delta
            if symbol >= symbol_count or occupied[symbol]:
                return False
            occupied[symbol] = True
    return True


def _oracle_contains(values: Span[Int, ...], target: Int) -> Bool:
    for index in range(len(values)):
        if values[index] == target:
            return True
    return False


def _occasion_outcome(
    pattern: NRPDCCHMonitoringPattern,
    first_symbols: Span[Int, ...],
    coreset_duration_symbols: Int,
    extended_cp: Bool,
    absolute_slot: Int,
    first_symbol: Int,
) -> Int:
    try:
        return (
            1
            if nr_pdcch_is_monitoring_occasion(
                pattern,
                first_symbols,
                coreset_duration_symbols,
                extended_cp,
                absolute_slot,
                first_symbol,
            )
            else 0
        )
    except:
        return -1


def test_exported_choice_constants_match_declared_alternatives() raises:
    var exported = _exported_choices()
    for choice in range(15):
        assert_equal(exported[choice], choice)


def test_complete_base_choice_table_and_every_offset() raises:
    var choices = _literal_choices()
    var periodicities = _literal_periodicities()
    assert_equal(len(choices), 15)
    assert_equal(len(periodicities), 15)
    for choice in range(15):
        var periodicity = periodicities[choice]
        assert_equal(
            nr_pdcch_monitoring_periodicity(choices[choice]), periodicity
        )
        for offset in range(periodicity):
            var absent = nr_pdcch_monitoring_pattern(choice, offset)
            assert_equal(absent.periodicity_slots, periodicity)
            assert_equal(absent.offset_slots, offset)
            assert_equal(absent.duration_present, False)
            assert_equal(absent.duration_slots, 1)

        if periodicity >= 4:
            var shortest = nr_pdcch_monitoring_pattern(
                choice, periodicity - 1, True, 2
            )
            var longest = nr_pdcch_monitoring_pattern(
                choice, periodicity - 1, True, periodicity - 1
            )
            assert_equal(shortest.duration_slots, 2)
            assert_equal(longest.duration_slots, periodicity - 1)


def test_period_boundaries_and_wrapped_duration_endpoints() raises:
    var periodicities = _literal_periodicities()
    for choice in range(15):
        var periodicity = periodicities[choice]
        var first = nr_pdcch_monitoring_pattern(choice, 0)
        var last = nr_pdcch_monitoring_pattern(
            choice, periodicity - 1
        )
        # Scan both sides of two complete period boundaries for every row.
        for absolute_slot in range(2 * periodicity + 1):
            assert_equal(
                nr_pdcch_is_monitoring_slot(first, absolute_slot),
                _oracle_monitoring_slot(periodicity, 0, 1, absolute_slot),
            )
            assert_equal(
                nr_pdcch_is_monitoring_slot(last, absolute_slot),
                _oracle_monitoring_slot(
                    periodicity, periodicity - 1, 1, absolute_slot
                ),
            )

        assert_equal(nr_pdcch_is_monitoring_slot(first, 0), True)
        assert_equal(
            nr_pdcch_is_monitoring_slot(first, periodicity - 1),
            periodicity == 1,
        )
        assert_equal(
            nr_pdcch_is_monitoring_slot(first, periodicity), True
        )
        assert_equal(
            nr_pdcch_is_monitoring_slot(last, periodicity - 1), True
        )
        assert_equal(
            nr_pdcch_is_monitoring_slot(last, periodicity),
            periodicity == 1,
        )

        if periodicity >= 4:
            var wrapped = nr_pdcch_monitoring_pattern(
                choice, periodicity - 1, True, periodicity - 1
            )
            for absolute_slot in range(2 * periodicity + 1):
                assert_equal(
                    nr_pdcch_is_monitoring_slot(wrapped, absolute_slot),
                    _oracle_monitoring_slot(
                        periodicity,
                        periodicity - 1,
                        periodicity - 1,
                        absolute_slot,
                    ),
                )
            assert_equal(
                nr_pdcch_is_monitoring_slot(
                    wrapped, periodicity - 2
                ),
                False,
            )
            assert_equal(
                nr_pdcch_is_monitoring_slot(
                    wrapped, periodicity - 1
                ),
                True,
            )
            assert_equal(
                nr_pdcch_is_monitoring_slot(wrapped, periodicity), True
            )
            assert_equal(
                nr_pdcch_is_monitoring_slot(
                    wrapped, 2 * periodicity - 2
                ),
                False,
            )


def test_duration_presence_offset_and_integer_boundaries() raises:
    var periodicities = _literal_periodicities()
    for choice in range(15):
        var periodicity = periodicities[choice]
        with assert_raises():
            _ = nr_pdcch_monitoring_pattern(choice, -1)
        with assert_raises():
            _ = nr_pdcch_monitoring_pattern(choice, periodicity)
        with assert_raises():
            _ = nr_pdcch_monitoring_pattern(choice, Int.MIN)
        with assert_raises():
            _ = nr_pdcch_monitoring_pattern(choice, Int.MAX)

        for latent_duration in [Int.MIN, -1, 0, 2, Int.MAX]:
            with assert_raises():
                _ = nr_pdcch_monitoring_pattern(
                    choice, 0, False, latent_duration
                )

        for invalid_present_duration in [Int.MIN, -1, 0, 1, Int.MAX]:
            with assert_raises():
                _ = nr_pdcch_monitoring_pattern(
                    choice, 0, True, invalid_present_duration
                )
        with assert_raises():
            _ = nr_pdcch_monitoring_pattern(
                choice, 0, True, periodicity
            )

    for invalid_choice in [Int.MIN, -1, 15, Int.MAX]:
        with assert_raises():
            _ = nr_pdcch_monitoring_periodicity(invalid_choice)
        with assert_raises():
            _ = nr_pdcch_monitoring_pattern(invalid_choice, 0)


def test_mutable_revalidation_and_int_extremes() raises:
    var valid = nr_pdcch_monitoring_pattern(
        NR_PDCCH_MONITORING_SL20, 19, True, 19
    )
    assert_equal(
        nr_pdcch_is_monitoring_slot(valid, Int.MAX),
        _oracle_monitoring_slot(20, 19, 19, Int.MAX),
    )
    var every_slot = nr_pdcch_monitoring_pattern(
        NR_PDCCH_MONITORING_SL1, 0
    )
    assert_equal(nr_pdcch_is_monitoring_slot(every_slot, Int.MAX), True)
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(valid, -1)
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(valid, Int.MIN)

    var mutated = valid.copy()
    mutated.periodicity_slots = Int.MAX
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(mutated, 0)
    mutated = valid.copy()
    mutated.offset_slots = Int.MIN
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(mutated, 0)
    mutated = valid.copy()
    mutated.offset_slots = mutated.periodicity_slots
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(mutated, 0)
    mutated = valid.copy()
    mutated.duration_slots = Int.MAX
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(mutated, 0)
    mutated = valid.copy()
    mutated.duration_slots = 1
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(mutated, 0)
    mutated = valid.copy()
    mutated.duration_present = False
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(mutated, 0)

    var absent = nr_pdcch_monitoring_pattern(
        NR_PDCCH_MONITORING_SL10, 3
    )
    absent.duration_slots = 2
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(absent, 3)
    absent = nr_pdcch_monitoring_pattern(
        NR_PDCCH_MONITORING_SL10, 3
    )
    absent.duration_present = True
    with assert_raises():
        _ = nr_pdcch_is_monitoring_slot(absent, 3)


def test_monitoring_symbol_bit_order_cp_and_mask_domain() raises:
    for symbol in range(14):
        var mask = 1 << (13 - symbol)
        var normal = nr_pdcch_monitoring_first_symbols(mask)
        assert_equal(len(normal), 1)
        assert_equal(normal[0], symbol)

        var extended = nr_pdcch_monitoring_first_symbols(mask, True)
        if symbol < 12:
            assert_equal(len(extended), 1)
            assert_equal(extended[0], symbol)
        else:
            assert_equal(len(extended), 0)

    assert_equal(len(nr_pdcch_monitoring_first_symbols(0)), 0)
    assert_equal(len(nr_pdcch_monitoring_first_symbols(0, True)), 0)
    # Bits 1:0 represent normal-CP symbols 12:13 and are ignored for extended
    # CP; the retained bits still decode in symbol order.
    assert_equal(
        nr_pdcch_monitoring_first_symbols(0x2007, True), [0, 11]
    )
    assert_equal(nr_pdcch_monitoring_first_symbols(0x0003, True), [])

    for invalid_mask in [Int.MIN, -1, 0x4000, Int.MAX]:
        with assert_raises():
            _ = nr_pdcch_monitoring_first_symbols(invalid_mask)
        with assert_raises():
            _ = nr_pdcch_monitoring_first_symbols(invalid_mask, True)


def test_complete_mask_duration_cp_domain_against_analytic_oracle() raises:
    # Exhaust all 16,384 bit strings, all three CORESET durations, and both
    # cyclic-prefix symbol counts.  Invalid interval sets must be rejected;
    # every valid set is checked at a deterministic queried start symbol.
    var pattern = nr_pdcch_monitoring_pattern(
        NR_PDCCH_MONITORING_SL1, 0
    )
    for extended_cp in [False, True]:
        var symbol_count = 12 if extended_cp else 14
        for mask in range(0x4000):
            var expected = _oracle_first_symbols(mask, extended_cp)
            var actual = nr_pdcch_monitoring_first_symbols(mask, extended_cp)
            assert_equal(actual, expected)
            for duration in range(1, 4):
                var valid = _oracle_symbol_configuration_valid(
                    Span(expected), duration, extended_cp
                )
                var probe = (mask + duration) % symbol_count
                var outcome = _occasion_outcome(
                    pattern,
                    Span(actual),
                    duration,
                    extended_cp,
                    mask,
                    probe,
                )
                if valid:
                    assert_equal(
                        outcome,
                        1 if _oracle_contains(Span(expected), probe) else 0,
                    )
                else:
                    assert_equal(outcome, -1)


def test_occasion_pairs_boundaries_empty_and_slot_composition() raises:
    var every_slot = nr_pdcch_monitoring_pattern(
        NR_PDCCH_MONITORING_SL1, 0
    )
    var exact_spacing = [0, 3, 6, 9]
    assert_equal(
        nr_pdcch_is_monitoring_occasion(
            every_slot, Span(exact_spacing), 3, False, Int.MAX, 6
        ),
        True,
    )
    assert_equal(
        nr_pdcch_is_monitoring_occasion(
            every_slot, Span(exact_spacing), 3, False, 0, 5
        ),
        False,
    )

    var empty = List[Int]()
    assert_equal(
        nr_pdcch_is_monitoring_occasion(
            every_slot, Span(empty), 1, False, 0, 0
        ),
        False,
    )

    var normal_last = [13]
    assert_equal(
        nr_pdcch_is_monitoring_occasion(
            every_slot, Span(normal_last), 1, False, 0, 13
        ),
        True,
    )
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            every_slot, Span(normal_last), 2, False, 0, 13
        )

    var extended_last = [11]
    assert_equal(
        nr_pdcch_is_monitoring_occasion(
            every_slot, Span(extended_last), 1, True, 0, 11
        ),
        True,
    )
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            every_slot, Span(extended_last), 2, True, 0, 11
        )

    var overlap = [0, 2]
    var duplicate = [3, 3]
    var descending = [3, 0]
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            every_slot, Span(overlap), 3, False, 0, 0
        )
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            every_slot, Span(duplicate), 3, False, 0, 0
        )
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            every_slot, Span(descending), 3, False, 0, 0
        )

    for invalid_start in [Int.MIN, -1, 14, Int.MAX]:
        var invalid_starts = [invalid_start]
        with assert_raises():
            _ = nr_pdcch_is_monitoring_occasion(
                every_slot, Span(invalid_starts), 1, False, 0, 0
            )
    var extended_out_of_bounds = [12]
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            every_slot, Span(extended_out_of_bounds), 1, True, 0, 0
        )

    for invalid_duration in [Int.MIN, -1, 0, 4, Int.MAX]:
        with assert_raises():
            _ = nr_pdcch_is_monitoring_occasion(
                every_slot,
                Span(exact_spacing),
                invalid_duration,
                False,
                0,
                0,
            )
    # Isolate the upper bound from interval spacing: an empty start set is
    # otherwise valid, so duration four can fail only at the TS 38.331 field
    # boundary rather than at the TS 38.213 overlap check.
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            every_slot, Span(empty), 4, False, 0, 0
        )
    for invalid_query in [Int.MIN, -1, 14, Int.MAX]:
        with assert_raises():
            _ = nr_pdcch_is_monitoring_occasion(
                every_slot,
                Span(exact_spacing),
                3,
                False,
                0,
                invalid_query,
            )
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            every_slot, Span(exact_spacing), 3, False, Int.MIN, 0
        )
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            every_slot, Span(exact_spacing), 3, False, -1, 0
        )

    # Recheck slot composition through every base periodicity alternative.
    var periodicities = _literal_periodicities()
    var one_start = [0]
    for choice in range(15):
        var periodicity = periodicities[choice]
        for offset in range(periodicity):
            var pattern = nr_pdcch_monitoring_pattern(choice, offset)
            assert_equal(
                nr_pdcch_is_monitoring_occasion(
                    pattern, Span(one_start), 1, False, offset, 0
                ),
                True,
            )
            assert_equal(
                nr_pdcch_is_monitoring_occasion(
                    pattern, Span(one_start), 1, False, offset + 1, 0
                ),
                periodicity == 1,
            )

    var mutated = every_slot.copy()
    mutated.periodicity_slots = Int.MAX
    with assert_raises():
        _ = nr_pdcch_is_monitoring_occasion(
            mutated, Span(empty), 1, False, 0, 0
        )


def test_seeded_independent_cycle_oracle() raises:
    var periodicities = _literal_periodicities()
    var seed = UInt64(0x9E3779B97F4A7C15)
    var checksum = UInt64(1469598103934665603)
    for _ in range(4096):
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var choice = Int(seed % UInt64(15))
        var periodicity = periodicities[choice]
        assert_equal(
            nr_pdcch_monitoring_periodicity(choice), periodicity
        )
        seed = seed * UInt64(6364136223846793005) + UInt64(1)
        var offset = Int(seed % UInt64(periodicity))
        var duration_present = periodicity >= 4 and (seed & UInt64(1)) != 0
        var duration = 1
        if duration_present:
            duration = 2 + Int((seed >> 1) % UInt64(periodicity - 2))
        seed = seed * UInt64(2862933555777941757) + UInt64(3037000493)
        var absolute_slot = Int(seed & UInt64(Int.MAX))
        var pattern = nr_pdcch_monitoring_pattern(
            choice, offset, duration_present, duration
        )
        assert_equal(pattern.periodicity_slots, periodicity)
        var actual = nr_pdcch_is_monitoring_slot(pattern, absolute_slot)
        assert_equal(
            actual,
            _oracle_monitoring_slot(
                periodicity, offset, duration, absolute_slot
            ),
        )
        checksum = (
            checksum
            ^ UInt64(choice + 1)
            ^ UInt64(offset + 1)
            ^ UInt64(duration + 1)
            ^ UInt64(1 if actual else 0)
        ) * UInt64(1099511628211)
    # Retain the seeded walk so accidental vacuous-loop changes are visible.
    assert_equal(checksum, UInt64(11477779422575107225))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
