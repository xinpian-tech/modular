from std.math import cos, exp, sin
from std.testing import assert_equal, assert_true, TestSuite
from wireless_dsp.core import Complex64
from wireless_dsp.channel.cdl import (
    CDLArray,
    CDLChannel,
    CDLProfile,
    CDL_PATH_DIFFUSE,
    CDL_PATH_LOS,
    CDL_RAYS_PER_CLUSTER,
    apply_cdl_narrowband,
    cdl_array_response,
    cdl_profile,
    cdl_ray_angles,
    cdl_ray_offsets,
    cdl_ray_polarization_matrix,
    cdl_ula,
    cdl_upa,
    realize_cdl_channel,
)


def _assert_close(
    actual: Float64, expected: Float64, tolerance: Float64
) raises:
    assert_true(abs(actual - expected) <= tolerance)


def _assert_complex_close(
    actual: Complex64, expected: Complex64, tolerance: Float64
) raises:
    _assert_close(actual.re, expected.re, tolerance)
    _assert_close(actual.im, expected.im, tolerance)


def _assert_normalized(profile: CDLProfile) raises:
    var powers = profile.normalized_linear_powers()
    var total = 0.0
    for power in powers:
        total += power
    _assert_close(total, 1.0, 2.0e-15)


def _extreme_cdl_profile(
    strongest_db: Float64, weaker_db: Float64
) raises -> CDLProfile:
    var delays: List[Float64] = [0.0, 1.0]
    var powers: List[Float64] = [strongest_db, weaker_db]
    var aod: List[Float64] = [0.0, 0.0]
    var aoa: List[Float64] = [0.0, 0.0]
    var zod: List[Float64] = [90.0, 90.0]
    var zoa: List[Float64] = [90.0, 90.0]
    var clusters: List[Int] = [0, 1]
    var kinds: List[Int] = [CDL_PATH_DIFFUSE, CDL_PATH_DIFFUSE]
    return CDLProfile(
        String("extreme-dB"), delays^, powers^, aod^, aoa^, zod^, zoa^,
        clusters^, kinds^, 2, 1.0, 0.0, 0.0, 0.0, 0.0, 10.0, False, 0.0,
    )


def test_extreme_db_xpr_steering_and_accumulation_are_scale_safe() raises:
    var positive = _extreme_cdl_profile(4000.0, 3990.0)
    var negative = _extreme_cdl_profile(-4000.0, -4010.0)
    var positive_powers = positive.normalized_linear_powers()
    var negative_powers = negative.normalized_linear_powers()
    _assert_close(positive_powers[0], 10.0 / 11.0, 1.0e-12)
    _assert_close(positive_powers[1], 1.0 / 11.0, 1.0e-12)
    assert_equal(positive_powers, negative_powers)

    var xpr_profile = cdl_profile(String("A"))
    xpr_profile.xpr_db = 4000.0
    var polarization = cdl_ray_polarization_matrix(
        xpr_profile, 0, 0, seed=UInt64(7)
    )
    _assert_close(polarization.theta_phi.magnitude(), 1.0e-200, 1.0e-208)
    _assert_close(polarization.phi_theta.magnitude(), 1.0e-200, 1.0e-208)

    var x: List[Float64] = [1.0e308]
    var y: List[Float64] = [0.0]
    var z: List[Float64] = [0.0]
    var huge_array = CDLArray(x^, y^, z^)
    var steering = cdl_array_response(huge_array, 0.0, 90.0)
    _assert_complex_close(steering[0], Complex64(1.0, 0.0), 2.0e-15)

    var delays: List[Float64] = [0.0, 0.0, 0.0, 0.0, 0.0]
    var coefficients: List[Complex64] = [
        Complex64(1.0e308, 1.0e308),
        Complex64(1.0e308, 1.0e308),
        Complex64(3.0, -4.0),
        Complex64(-1.0e308, -1.0e308),
        Complex64(-1.0e308, -1.0e308),
    ]
    var channel = CDLChannel(1, 1, delays^, coefficients^)
    _assert_complex_close(
        channel.narrowband()[0], Complex64(3.0, -4.0), 1.0e-14
    )
    _assert_complex_close(
        channel.frequency_response(1.0)[0],
        Complex64(3.0, -4.0),
        1.0e-14,
    )

    # offset*delay is finite, but forming 2*pi*offset first overflows.
    var tiny_delays: List[Float64] = [1.0e-308]
    var unit_coefficient: List[Complex64] = [Complex64(1.0, 0.0)]
    var tiny_delay_channel = CDLChannel(
        1, 1, tiny_delays^, unit_coefficient^
    )
    var phase = -6.2831853071795864769e-9
    _assert_complex_close(
        tiny_delay_channel.frequency_response(1.0e308)[0],
        Complex64(cos(phase), sin(phase)),
        2.0e-15,
    )


def test_cdl_doppler_products_reduce_in_cycle_domain() raises:
    var profile = cdl_profile(String("D"))
    var scalar = cdl_ula(1)
    var at_zero = realize_cdl_channel(
        profile, scalar, scalar, seed=UInt64(4242),
        time_seconds=0.0, speed_mps=1.0,
    )
    var after_huge_integer_cycles = realize_cdl_channel(
        profile, scalar, scalar, seed=UInt64(4242),
        time_seconds=1.0e308, speed_mps=1.0,
    )
    assert_equal(after_huge_integer_cycles.coefficients, at_zero.coefficients)

    # speed*carrier overflows in this order, while the subsequent tiny time
    # leaves a finite Doppler phase.  Compare with the algebraically balanced
    # ordinary-scale realization.
    var balanced = realize_cdl_channel(
        profile, scalar, scalar, seed=UInt64(99),
        time_seconds=1.0, carrier_frequency_hz=10.0,
        speed_mps=1.0e8,
    )
    var extreme = realize_cdl_channel(
        profile, scalar, scalar, seed=UInt64(99),
        time_seconds=1.0e-300, carrier_frequency_hz=10.0,
        speed_mps=1.0e308,
    )
    for index in range(len(balanced.coefficients)):
        _assert_complex_close(
            extreme.coefficients[index], balanced.coefficients[index], 2.0e-11
        )


def _assert_offset_multiset(
    values: List[Float64], center: Float64, spread: Float64
) raises:
    var expected = cdl_ray_offsets()
    assert_equal(len(values), CDL_RAYS_PER_CLUSTER)
    for offset in expected:
        var matches = 0
        for value in values:
            if abs((value - center) / spread - offset) < 2.0e-12:
                matches += 1
        assert_equal(matches, 1)


def test_release_18_cdl_static_tables() raises:
    var a = cdl_profile(String("A"), desired_delay_spread_ns=100.0)
    assert_equal(a.name, String("CDL-A"))
    assert_equal(a.cluster_count, 23)
    assert_equal(a.component_count(), 23)
    _assert_close(a.delays[1], 0.3819, 0.0)
    _assert_close(a.delay_ns(22), 965.86, 1.0e-12)
    _assert_close(a.powers_db[0], -13.4, 0.0)
    _assert_close(a.aod_deg[17], 148.4, 0.0)
    _assert_close(a.aoa_deg[21], -151.8, 0.0)
    _assert_close(a.zod_deg[11], 171.6, 0.0)
    _assert_close(a.zoa_deg[22], 156.1, 0.0)
    _assert_close(a.azimuth_departure_spread_deg, 5.0, 0.0)
    _assert_close(a.azimuth_arrival_spread_deg, 11.0, 0.0)
    _assert_close(a.xpr_db, 10.0, 0.0)
    assert_true(not a.has_los)
    _assert_normalized(a)

    var b = cdl_profile(String("B"))
    assert_equal(b.cluster_count, 23)
    _assert_close(b.delays[17], 2.8294, 0.0)
    _assert_close(b.powers_db[15], -1.9, 0.0)
    _assert_close(b.aod_deg[20], -103.6, 0.0)
    _assert_close(b.aoa_deg[3], 125.5, 0.0)
    _assert_close(b.zod_deg[22], 115.7, 0.0)
    _assert_close(b.zoa_deg[17], 82.9, 0.0)
    _assert_close(b.azimuth_arrival_spread_deg, 22.0, 0.0)
    _assert_close(b.xpr_db, 8.0, 0.0)
    _assert_normalized(b)

    var c = cdl_profile(String("C"))
    assert_equal(c.cluster_count, 24)
    assert_equal(c.component_count(), 24)
    _assert_close(c.delays[23], 8.6523, 0.0)
    _assert_close(c.powers_db[5], 0.0, 0.0)
    _assert_close(c.aod_deg[23], -123.8, 0.0)
    _assert_close(c.aoa_deg[17], 3.8, 0.0)
    _assert_close(c.zod_deg[9], 95.3, 0.0)
    _assert_close(c.zoa_deg[15], 100.7, 0.0)
    _assert_close(c.azimuth_departure_spread_deg, 2.0, 0.0)
    _assert_close(c.xpr_db, 7.0, 0.0)
    _assert_normalized(c)

    var d = cdl_profile(String("D"))
    assert_equal(d.cluster_count, 13)
    assert_equal(d.component_count(), 14)
    assert_true(d.has_los)
    assert_equal(d.path_kinds[0], CDL_PATH_LOS)
    assert_equal(d.path_kinds[1], CDL_PATH_DIFFUSE)
    assert_equal(d.cluster_indices[0], 0)
    assert_equal(d.cluster_indices[1], 0)
    assert_equal(d.cluster_indices[13], 12)
    _assert_close(d.powers_db[0] - d.powers_db[1], 13.3, 1.0e-14)
    _assert_close(d.los_k_factor_db, 13.3, 0.0)
    _assert_close(d.aod_deg[12], -132.1, 0.0)
    _assert_close(d.aoa_deg[10], 127.7, 0.0)
    _assert_close(d.zod_deg[11], 103.8, 0.0)
    _assert_close(d.zoa_deg[13], 72.9, 0.0)
    _assert_close(d.xpr_db, 11.0, 0.0)
    _assert_normalized(d)

    var e = cdl_profile(String("E"))
    assert_equal(e.cluster_count, 14)
    assert_equal(e.component_count(), 15)
    assert_true(e.has_los)
    assert_equal(e.path_kinds[0], CDL_PATH_LOS)
    assert_equal(e.cluster_indices[14], 13)
    _assert_close(e.delays[14], 20.6419, 0.0)
    _assert_close(e.powers_db[0] - e.powers_db[1], 22.0, 1.0e-14)
    _assert_close(e.los_k_factor_db, 22.0, 0.0)
    _assert_close(e.aod_deg[13], 55.9, 0.0)
    _assert_close(e.aoa_deg[12], 147.0, 0.0)
    _assert_close(e.zod_deg[14], 104.6, 0.0)
    _assert_close(e.zoa_deg[13], 88.6, 0.0)
    _assert_normalized(e)


def test_twenty_ray_offsets_coupling_and_seed() raises:
    var offsets = cdl_ray_offsets()
    assert_equal(len(offsets), CDL_RAYS_PER_CLUSTER)
    _assert_close(offsets[0], 0.0447, 0.0)
    _assert_close(offsets[1], -0.0447, 0.0)
    _assert_close(offsets[18], 2.1551, 0.0)
    _assert_close(offsets[19], -2.1551, 0.0)

    var profile = cdl_profile(String("A"))
    var first = cdl_ray_angles(profile, 0, seed=UInt64(0x12345678))
    var again = cdl_ray_angles(profile, 0, seed=UInt64(0x12345678))
    var different = cdl_ray_angles(profile, 0, seed=UInt64(0x12345679))
    assert_equal(first.aod_deg, again.aod_deg)
    assert_equal(first.aoa_deg, again.aoa_deg)
    assert_equal(first.zod_deg, again.zod_deg)
    assert_equal(first.zoa_deg, again.zoa_deg)
    assert_true(first.aod_deg[0] != different.aod_deg[0])
    assert_equal(first.ray_count(), CDL_RAYS_PER_CLUSTER)

    _assert_offset_multiset(
        first.aod_deg, profile.aod_deg[0],
        profile.azimuth_departure_spread_deg,
    )
    _assert_offset_multiset(
        first.aoa_deg, profile.aoa_deg[0],
        profile.azimuth_arrival_spread_deg,
    )
    _assert_offset_multiset(
        first.zod_deg, profile.zod_deg[0],
        profile.zenith_departure_spread_deg,
    )
    _assert_offset_multiset(
        first.zoa_deg, profile.zoa_deg[0],
        profile.zenith_arrival_spread_deg,
    )
    _assert_close(
        first.aoa_deg[0],
        profile.aoa_deg[0]
        + profile.azimuth_arrival_spread_deg * offsets[0],
        2.0e-14,
    )


def test_seeded_phase_xpr_and_los_polarization() raises:
    var b = cdl_profile(String("B"))
    var first = cdl_ray_polarization_matrix(
        b, 3, 7, seed=UInt64(987654321)
    )
    var again = cdl_ray_polarization_matrix(
        b, 3, 7, seed=UInt64(987654321)
    )
    var different = cdl_ray_polarization_matrix(
        b, 3, 7, seed=UInt64(987654322)
    )
    assert_equal(first.theta_theta, again.theta_theta)
    assert_equal(first.theta_phi, again.theta_phi)
    assert_true(first.theta_theta != different.theta_theta)
    _assert_close(first.theta_theta.magnitude_squared(), 1.0, 2.0e-15)
    _assert_close(first.phi_phi.magnitude_squared(), 1.0, 2.0e-15)
    _assert_close(
        first.theta_phi.magnitude_squared(), 1.0 / b.xpr_linear(), 1.0e-13
    )
    _assert_close(
        first.phi_theta.magnitude_squared(), 1.0 / b.xpr_linear(), 1.0e-13
    )

    var d = cdl_profile(String("D"))
    var los = cdl_ray_polarization_matrix(d, 0, 0, seed=UInt64(1))
    assert_equal(los.theta_theta, Complex64(1.0, 0.0))
    assert_equal(los.theta_phi, Complex64(0.0, 0.0))
    assert_equal(los.phi_theta, Complex64(0.0, 0.0))
    assert_equal(los.phi_phi, Complex64(-1.0, 0.0))


def test_independent_ula_upa_responses_and_dimensions() raises:
    var ula = cdl_ula(2, spacing_wavelengths=0.5, axis=1)
    var response = cdl_array_response(ula, 90.0, 90.0)
    assert_equal(len(response), 2)
    _assert_complex_close(response[0], Complex64(0.0, -1.0), 2.0e-15)
    _assert_complex_close(response[1], Complex64(0.0, 1.0), 2.0e-15)

    var upa = cdl_upa(2, 3)
    assert_equal(upa.element_count(), 6)
    _assert_close(upa.x_wavelengths[0], 0.0, 0.0)
    _assert_close(upa.y_wavelengths[0], -0.5, 0.0)
    _assert_close(upa.z_wavelengths[0], -0.25, 0.0)
    _assert_close(upa.y_wavelengths[5], 0.5, 0.0)
    _assert_close(upa.z_wavelengths[5], 0.25, 0.0)

    var tx = cdl_ula(3, spacing_wavelengths=0.4, axis=0)
    var rx = cdl_upa(
        2, 2, horizontal_spacing_wavelengths=0.6,
        vertical_spacing_wavelengths=0.7,
    )
    var profile = cdl_profile(String("C"))
    var channel = realize_cdl_channel(
        profile, tx, rx, seed=UInt64(1234)
    )
    assert_equal(channel.transmit_count, 3)
    assert_equal(channel.receive_count, 4)
    assert_equal(channel.component_count(), 24)
    assert_equal(len(channel.coefficients), 24 * 4 * 3)
    assert_equal(len(channel.narrowband()), 4 * 3)

    # Tx and Rx steering are evaluated from their own geometries: changing
    # only the Tx axis changes columns while preserving the channel shape.
    var alternate_tx = cdl_ula(3, spacing_wavelengths=0.4, axis=2)
    var alternate = realize_cdl_channel(
        profile, alternate_tx, rx, seed=UInt64(1234)
    )
    assert_true(
        channel.coefficient(0, 0, 0)
        != alternate.coefficient(0, 0, 0)
    )
    assert_equal(len(alternate.coefficients), len(channel.coefficients))


def test_seed_dimensions_normalization_and_application() raises:
    var profile = cdl_profile(String("B"))
    _assert_normalized(profile)
    var tx = cdl_ula(2)
    var rx = cdl_upa(2, 2)
    var first = realize_cdl_channel(
        profile, tx, rx, seed=UInt64(0xCAFEBABE)
    )
    var again = realize_cdl_channel(
        profile, tx, rx, seed=UInt64(0xCAFEBABE)
    )
    var different = realize_cdl_channel(
        profile, tx, rx, seed=UInt64(0xCAFEBABF)
    )
    assert_equal(first.coefficients, again.coefficients)
    assert_true(first.coefficients[0] != different.coefficients[0])
    assert_equal(first.receive_count, 4)
    assert_equal(first.transmit_count, 2)
    assert_equal(len(first.coefficients), 23 * 4 * 2)
    assert_equal(first.delays_ns[22], profile.delay_ns(22))

    var zero_response = first.frequency_response(0.0)
    assert_equal(zero_response, first.narrowband())
    var symbols: List[Complex64] = [
        Complex64(0.5, -0.25), Complex64(-1.0, 0.75),
    ]
    var output = apply_cdl_narrowband(first, symbols)
    var matrix = first.narrowband()
    assert_equal(len(output), 4)
    for receive in range(4):
        var expected = (
            matrix[receive * 2] * symbols[0]
            + matrix[receive * 2 + 1] * symbols[1]
        )
        _assert_complex_close(output[receive], expected, 2.0e-15)

    # Unit co-polarized SISO links inherit the unit-normalized table PDP.
    var scalar = cdl_ula(1)
    var tapped_mean = 0.0
    var narrowband_mean = 0.0
    var realization_count = 100
    for realization in range(realization_count):
        var sample = realize_cdl_channel(
            profile, scalar, scalar, seed=UInt64(10000 + realization)
        )
        tapped_mean += sample.total_tapped_energy()
        var narrowband = sample.narrowband()
        narrowband_mean += narrowband[0].magnitude_squared()
    tapped_mean /= Float64(realization_count)
    narrowband_mean /= Float64(realization_count)
    _assert_close(tapped_mean, 1.0, 0.14)
    _assert_close(narrowband_mean, 1.0, 0.22)


def test_los_k_distance_phase_and_doppler_evolution() raises:
    var profile = cdl_profile(String("D"))
    var powers = profile.normalized_linear_powers()
    _assert_close(
        powers[0] / powers[1],
        exp(0.2302585092994045684 * 13.3),
        2.0e-13,
    )
    var scalar = cdl_ula(1)
    var seed_a = realize_cdl_channel(
        profile, scalar, scalar, seed=UInt64(111)
    )
    var seed_b = realize_cdl_channel(
        profile, scalar, scalar, seed=UInt64(222)
    )
    # The specular phase is geometric; the diffuse initial phases are seeded.
    assert_equal(seed_a.coefficient(0, 0, 0), seed_b.coefficient(0, 0, 0))
    assert_true(seed_a.coefficient(1, 0, 0) != seed_b.coefficient(1, 0, 0))

    # At fc=c, wavelength is one metre, so another half metre flips LOS.
    var shifted = realize_cdl_channel(
        profile, scalar, scalar, seed=UInt64(111),
        carrier_frequency_hz=299792458.0, link_distance_m=0.5,
    )
    _assert_complex_close(
        shifted.coefficient(0, 0, 0),
        -seed_a.coefficient(0, 0, 0),
        2.0e-15,
    )
    assert_equal(
        shifted.coefficient(1, 0, 0), seed_a.coefficient(1, 0, 0)
    )

    var static_later = realize_cdl_channel(
        profile, scalar, scalar, seed=UInt64(111), time_seconds=8.0
    )
    assert_equal(seed_a.coefficients, static_later.coefficients)

    # Travel exactly along the LOS arrival direction.  With fc=c and 10 m/s,
    # f_D=10 Hz; 25 ms therefore rotates the specular component by +pi/2.
    var moving = realize_cdl_channel(
        profile, scalar, scalar, seed=UInt64(111),
        time_seconds=0.025, carrier_frequency_hz=299792458.0,
        speed_mps=10.0, travel_azimuth_deg=-180.0,
        travel_zenith_deg=81.5,
    )
    var initial_los = seed_a.coefficient(0, 0, 0)
    _assert_complex_close(
        moving.coefficient(0, 0, 0),
        Complex64(-initial_los.im, initial_los.re),
        3.0e-14,
    )
    assert_true(moving.coefficient(1, 0, 0) != seed_a.coefficient(1, 0, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
