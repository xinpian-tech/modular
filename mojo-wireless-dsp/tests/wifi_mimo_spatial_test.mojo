"""Exact and independent evidence for bounded HT/VHT/HE spatial processing.

Static bit fixtures exercise the stream-parser round-robin rule without using
the production deparser as the oracle.  Literal Table 19-10/Table 21-11 rows
cover every supported STS count.  CSD mapping is checked against exact axis
cases and a separate component-wise analytic implementation.  Discrete
results use exact tolerance; Float64 rotations use absolute tolerance 2e-12.
"""

from std.collections import Span
from std.math import cos, sin
from std.testing import (
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
    TestSuite,
)
from std.utils.numerics import inf, nan
from wireless_dsp.core import Complex64
from wireless_dsp.wireless.wifi.profiles import (
    WIFI_PHY_HT,
    WIFI_PHY_VHT,
    WIFI_PHY_HE,
    WIFI_PHY_EHT,
)
from wireless_dsp.wireless.wifi.mimo_spatial import (
    WIFI_MIMO_MAX_BOUNDED_SPATIAL_STREAMS,
    WifiMIMOSpatialConfig,
    wifi_mimo_parser_block_bits,
    wifi_mimo_spatial_parse,
    wifi_mimo_spatial_deparse,
    wifi_mimo_cyclic_shift_ns,
    wifi_mimo_direct_csd_map,
    wifi_mimo_direct_csd_unmap,
)


comptime _TWO_PI = 6.283185307179586476925286766559


def _assert_bits_equal(
    actual: Span[UInt8, ...], expected: Span[UInt8, ...]
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_equal(actual[index], expected[index])


def _assert_complex_close(
    actual: Span[Complex64, ...],
    expected: Span[Complex64, ...],
    tolerance: Float64 = 2.0e-12,
) raises:
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_almost_equal(
            actual[index].re, expected[index].re, atol=tolerance
        )
        assert_almost_equal(
            actual[index].im, expected[index].im, atol=tolerance
        )


def _literal_shift(stream: Int) -> Int:
    return [0, -400, -200, -600][stream]


def _oracle_parse(
    bits: Span[UInt8, ...], spatial_streams: Int, block_bits: Int
) -> List[UInt8]:
    var per_stream = len(bits) // spatial_streams
    var expected = List[UInt8](length=len(bits), fill=0)
    for stream in range(spatial_streams):
        for output_index in range(per_stream):
            var input_index = (
                stream * block_bits
                + spatial_streams * block_bits * (output_index // block_bits)
                + output_index % block_bits
            )
            expected[stream * per_stream + output_index] = bits[input_index]
    return expected^


def _oracle_csd_map(
    config: WifiMIMOSpatialConfig,
    values: Span[Complex64, ...],
    tones: Span[Int, ...],
    inverse: Bool = False,
) -> List[Complex64]:
    var useful_ns = 12_800 if config.family == WIFI_PHY_HE else 3_200
    var result = List[Complex64](capacity=len(values))
    for stream in range(config.spatial_streams):
        var shift = _literal_shift(stream)
        for tone_offset in range(len(tones)):
            var angle = (
                -_TWO_PI
                * Float64(tones[tone_offset])
                * Float64(shift)
                / Float64(useful_ns)
            )
            if inverse:
                angle = -angle
            var real_scale = cos(angle)
            var imaginary_scale = sin(angle)
            var value = values[stream * len(tones) + tone_offset]
            result.append(
                Complex64(
                    value.re * real_scale - value.im * imaginary_scale,
                    value.re * imaginary_scale + value.im * real_scale,
                )
            )
    return result^


def test_all_bounded_configs_parser_blocks_and_csd_rows_exact() raises:
    assert_equal(WIFI_MIMO_MAX_BOUNDED_SPATIAL_STREAMS, 4)
    var families: List[Int] = [WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE]
    var fft_sizes: List[Int] = [64, 256, 1024]
    var bpsc_values: List[Int] = [1, 2, 4, 6]
    var block_values: List[Int] = [1, 1, 2, 3]
    for family_index in range(3):
        for streams in range(1, 5):
            for modulation_index in range(4):
                var config = WifiMIMOSpatialConfig(
                    families[family_index],
                    streams,
                    bpsc_values[modulation_index],
                    fft_sizes[family_index],
                )
                assert_equal(
                    wifi_mimo_parser_block_bits(config),
                    block_values[modulation_index],
                )
            for stream in range(streams):
                var config = WifiMIMOSpatialConfig(
                    families[family_index], streams, 2, fft_sizes[family_index]
                )
                assert_equal(
                    wifi_mimo_cyclic_shift_ns(config, stream),
                    _literal_shift(stream),
                )

    assert_equal(
        wifi_mimo_parser_block_bits(
            WifiMIMOSpatialConfig(WIFI_PHY_VHT, 4, 8, 512)
        ),
        4,
    )
    assert_equal(
        wifi_mimo_parser_block_bits(
            WifiMIMOSpatialConfig(WIFI_PHY_HE, 4, 10, 2048)
        ),
        5,
    )


def test_static_stream_parser_vectors_and_independent_inverse_exact() raises:
    # Eight labeled three-bit groups, represented as binary values 000..111.
    var source_64qam: List[UInt8] = [
        0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1,
        1, 0, 0, 1, 0, 1, 1, 1, 0, 1, 1, 1,
    ]
    var expected_64qam: List[UInt8] = [
        0, 0, 0, 1, 0, 0,
        0, 0, 1, 1, 0, 1,
        0, 1, 0, 1, 1, 0,
        0, 1, 1, 1, 1, 1,
    ]
    var ht = WifiMIMOSpatialConfig(WIFI_PHY_HT, 4, 6, 64)
    var parsed_64qam = wifi_mimo_spatial_parse(ht, Span(source_64qam))
    _assert_bits_equal(Span(parsed_64qam), Span(expected_64qam))
    var restored_64qam = wifi_mimo_spatial_deparse(ht, Span(expected_64qam))
    _assert_bits_equal(Span(restored_64qam), Span(source_64qam))

    var source_qpsk: List[UInt8] = [0, 1, 1, 0, 1, 0, 0, 0, 1, 1, 0, 1]
    var expected_qpsk: List[UInt8] = [0, 0, 0, 1, 1, 1, 0, 0, 1, 0, 1, 1]
    var he = WifiMIMOSpatialConfig(WIFI_PHY_HE, 3, 2, 256)
    var parsed_qpsk = wifi_mimo_spatial_parse(he, Span(source_qpsk))
    _assert_bits_equal(Span(parsed_qpsk), Span(expected_qpsk))
    var restored_qpsk = wifi_mimo_spatial_deparse(he, Span(expected_qpsk))
    _assert_bits_equal(Span(restored_qpsk), Span(source_qpsk))


def test_direct_csd_static_axis_vectors_and_analytic_oracle() raises:
    var tones: List[Int] = [1]
    var values: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(1.0, 0.0),
        Complex64(1.0, 0.0),
        Complex64(1.0, 0.0),
    ]
    var vht = WifiMIMOSpatialConfig(WIFI_PHY_VHT, 4, 8, 64)
    var mapped = wifi_mimo_direct_csd_map(vht, Span(values), Span(tones))
    var expected: List[Complex64] = [
        Complex64(1.0, 0.0),
        Complex64(0.7071067811865476, 0.7071067811865475),
        Complex64(0.9238795325112867, 0.3826834323650898),
        Complex64(0.38268343236508984, 0.9238795325112867),
    ]
    _assert_complex_close(Span(mapped), Span(expected), 1.0e-15)
    var unmapped = wifi_mimo_direct_csd_unmap(
        vht, Span(expected), Span(tones)
    )
    _assert_complex_close(Span(unmapped), Span(values), 1.0e-15)
    var inverse_analytic = _oracle_csd_map(
        vht, Span(expected), Span(tones), True
    )
    _assert_complex_close(Span(unmapped), Span(inverse_analytic), 1.0e-15)

    var he_tones: List[Int] = [-8, 8]
    var he_values: List[Complex64] = [
        Complex64(2.0, -3.0), Complex64(-4.0, 5.0),
        Complex64(1.0, 0.0), Complex64(1.0, 0.0),
    ]
    var he = WifiMIMOSpatialConfig(WIFI_PHY_HE, 2, 10, 256)
    var he_mapped = wifi_mimo_direct_csd_map(
        he, Span(he_values), Span(he_tones)
    )
    var he_expected: List[Complex64] = [
        Complex64(2.0, -3.0), Complex64(-4.0, 5.0),
        Complex64(0.0, -1.0), Complex64(0.0, 1.0),
    ]
    _assert_complex_close(Span(he_mapped), Span(he_expected), 1.0e-15)
    var analytic = _oracle_csd_map(he, Span(he_values), Span(he_tones))
    _assert_complex_close(Span(he_mapped), Span(analytic), 1.0e-15)


def test_seeded_parser_and_mapper_differential_properties() raises:
    var seed = UInt64(0x80211_2024_4D494D4F)
    var tones: List[Int] = [-7, -3, -1, 0, 2, 5, 9]
    for iteration in range(1021):
        seed = (
            seed * UInt64(6364136223846793005)
            + UInt64(1442695040888963407)
        )
        var family = [WIFI_PHY_HT, WIFI_PHY_VHT, WIFI_PHY_HE][iteration % 3]
        var fft_size = [64, 256, 1024][iteration % 3]
        var streams = 1 + Int((seed >> 9) % UInt64(4))
        var bpsc: Int
        if family == WIFI_PHY_HT:
            bpsc = [1, 2, 4, 6][Int(seed % UInt64(4))]
        elif family == WIFI_PHY_VHT:
            bpsc = [1, 2, 4, 6, 8][Int(seed % UInt64(5))]
        else:
            bpsc = [1, 2, 4, 6, 8, 10][Int(seed % UInt64(6))]
        var config = WifiMIMOSpatialConfig(family, streams, bpsc, fft_size)
        var block_bits = 1 if bpsc == 1 else bpsc // 2
        var bits = List[UInt8](capacity=streams * block_bits * 5)
        for _ in range(streams * block_bits * 5):
            seed = (
                seed * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            bits.append(UInt8(seed & UInt64(1)))
        var parsed = wifi_mimo_spatial_parse(config, Span(bits))
        var oracle = _oracle_parse(Span(bits), streams, block_bits)
        _assert_bits_equal(Span(parsed), Span(oracle))
        var restored = wifi_mimo_spatial_deparse(config, Span(parsed))
        _assert_bits_equal(Span(restored), Span(bits))

        var values = List[Complex64](capacity=streams * len(tones))
        for _ in range(streams * len(tones)):
            seed = (
                seed * UInt64(6364136223846793005)
                + UInt64(1442695040888963407)
            )
            var real = (
                Float64(Int((seed >> 16) & UInt64(0xFFFF)) - 32768)
                / 8192.0
            )
            var imag = (
                Float64(Int((seed >> 40) & UInt64(0xFFFF)) - 32768)
                / 8192.0
            )
            values.append(Complex64(real, imag))
        var mapped = wifi_mimo_direct_csd_map(
            config, Span(values), Span(tones)
        )
        var expected = _oracle_csd_map(config, Span(values), Span(tones))
        _assert_complex_close(Span(mapped), Span(expected))
        var restored_values = wifi_mimo_direct_csd_unmap(
            config, Span(mapped), Span(tones)
        )
        _assert_complex_close(Span(restored_values), Span(values))


def test_public_mutation_shape_nonfinite_overflow_and_int_edges() raises:
    for family in [Int.MIN, 0, WIFI_PHY_EHT, Int.MAX]:
        with assert_raises():
            _ = WifiMIMOSpatialConfig(family, 1, 1, 64)
    for streams in [Int.MIN, -1, 0, 5, Int.MAX]:
        with assert_raises():
            _ = WifiMIMOSpatialConfig(WIFI_PHY_HT, streams, 1, 64)
    for bpsc in [Int.MIN, -1, 0, 3, 5, 7, 9, Int.MAX]:
        with assert_raises():
            _ = WifiMIMOSpatialConfig(WIFI_PHY_HT, 1, bpsc, 64)
    for fft_size in [Int.MIN, -1, 0, 63, 65, 2048, Int.MAX]:
        with assert_raises():
            _ = WifiMIMOSpatialConfig(WIFI_PHY_VHT, 1, 2, fft_size)

    var one_bit: List[UInt8] = [1]
    var one_symbol: List[Complex64] = [Complex64(1.0, 0.0)]
    var one_tone: List[Int] = [0]
    var mutable = WifiMIMOSpatialConfig(WIFI_PHY_HT, 1, 1, 64)
    mutable.family = WIFI_PHY_EHT
    with assert_raises():
        _ = wifi_mimo_parser_block_bits(mutable)
    mutable.family = WIFI_PHY_HT
    mutable.spatial_streams = 5
    with assert_raises():
        _ = wifi_mimo_spatial_parse(mutable, Span(one_bit))
    mutable.spatial_streams = 1
    mutable.bits_per_subcarrier = 3
    with assert_raises():
        _ = wifi_mimo_spatial_deparse(mutable, Span(one_bit))
    mutable.bits_per_subcarrier = 1
    mutable.fft_size = Int.MAX
    with assert_raises():
        _ = wifi_mimo_cyclic_shift_ns(mutable, 0)
    with assert_raises():
        _ = wifi_mimo_direct_csd_map(
            mutable, Span(one_symbol), Span(one_tone)
        )
    with assert_raises():
        _ = wifi_mimo_direct_csd_unmap(
            mutable, Span(one_symbol), Span(one_tone)
        )

    var ht2 = WifiMIMOSpatialConfig(WIFI_PHY_HT, 2, 6, 64)
    var empty_bits = List[UInt8]()
    with assert_raises():
        _ = wifi_mimo_spatial_parse(ht2, Span(empty_bits))
    var nonbinary: List[UInt8] = [0, 1, 2, 0, 1, 0]
    with assert_raises():
        _ = wifi_mimo_spatial_parse(ht2, Span(nonbinary))
    var incomplete: List[UInt8] = [0, 1, 0, 1, 0]
    with assert_raises():
        _ = wifi_mimo_spatial_parse(ht2, Span(incomplete))
    with assert_raises():
        _ = wifi_mimo_spatial_deparse(ht2, Span(incomplete))

    var tones: List[Int] = [-1, 0, 1]
    var values = List[Complex64](length=6, fill=Complex64(1.0, -1.0))
    var empty_tones = List[Int]()
    with assert_raises():
        _ = wifi_mimo_direct_csd_map(ht2, Span(values), Span(empty_tones))
    var short_values = List[Complex64](length=5, fill=Complex64(1.0, 0.0))
    with assert_raises():
        _ = wifi_mimo_direct_csd_map(ht2, Span(short_values), Span(tones))
    for invalid in [Int.MIN, -33, 32, Int.MAX]:
        var invalid_tones: List[Int] = [-1, 0, invalid]
        with assert_raises():
            _ = wifi_mimo_direct_csd_map(
                ht2, Span(values), Span(invalid_tones)
            )
    var duplicate_tones: List[Int] = [-1, -1, 1]
    with assert_raises():
        _ = wifi_mimo_direct_csd_map(
            ht2, Span(values), Span(duplicate_tones)
        )
    var descending_tones: List[Int] = [0, -1, 1]
    with assert_raises():
        _ = wifi_mimo_direct_csd_map(
            ht2, Span(values), Span(descending_tones)
        )

    values[0] = Complex64(nan[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_mimo_direct_csd_map(ht2, Span(values), Span(tones))
    values[0] = Complex64(0.0, inf[DType.float64]())
    with assert_raises():
        _ = wifi_mimo_direct_csd_unmap(ht2, Span(values), Span(tones))
    values[0] = Complex64(-inf[DType.float64](), 0.0)
    with assert_raises():
        _ = wifi_mimo_direct_csd_map(ht2, Span(values), Span(tones))

    var one_tone_positive: List[Int] = [1]
    var overflow_values: List[Complex64] = [
        Complex64(0.0, 0.0),
        Complex64(Float64.MAX_FINITE, Float64.MAX_FINITE),
    ]
    with assert_raises():
        _ = wifi_mimo_direct_csd_map(
            ht2, Span(overflow_values), Span(one_tone_positive)
        )
    var huge_values: List[Complex64] = [
        Complex64(Float64.MAX_FINITE / 4.0, 0.0),
        Complex64(0.0, Float64.MAX_FINITE / 4.0),
    ]
    var huge_mapped = wifi_mimo_direct_csd_map(
        ht2, Span(huge_values), Span(one_tone_positive)
    )
    assert_true(huge_mapped[0].re == Float64.MAX_FINITE / 4.0)
    assert_true(huge_mapped[1].re < 0.0 and huge_mapped[1].im > 0.0)

    for stream_index in [Int.MIN, -1, 2, Int.MAX]:
        with assert_raises():
            _ = wifi_mimo_cyclic_shift_ns(ht2, stream_index)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
