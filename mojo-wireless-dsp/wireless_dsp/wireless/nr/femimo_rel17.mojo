"""Bounded Rel-17 further-enhanced Type-II port-selection algorithms.

This scalar CPU reference implements an exact, decoded-configuration slice of
3GPP Work Item ``NR_FeMIMO`` (feature UID 860040, core UID 860140):

* TS 38.214 V17.16.0 clause 5.2.2.2.7, Table 5.2.2.2.7-1 and the
  immediately following configuration restrictions;
* the clause-5.2.2.2.7 combinatorial mapping between ``i1,2`` and the
  selected port-vector indices ``m(i)`` using the published ``C(x,y)``
  tables; and
* the strongest-coefficient index in clause 5.2.2.2.7 and the Further
  Enhanced Type-II coefficient priority in clause 5.2.3.

Normative TS source:

* https://www.3gpp.org/ftp/Specs/latest/Rel-17/38_series/38214-hg0.zip

Work Item inventory and scope cross-checks, not normative authorities:

* https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860040
* https://www.3gpp.org/ftp/tsg_ran/TSG_RAN/TSGR_93e/Docs/RP-212535.zip

The caller supplies already-decoded RRC values.  This bounded module does not
construct the amplitude/phase coefficient fields or complete precoding
matrices, pack or channel-code CSI Parts 1/2, estimate CSI, decode RRC/DCI,
schedule resources, generate waveforms, or implement the remaining beam,
SRS, HST-SFN, inter-cell, and multi-TRP objectives of UID 860040.
"""

from std.math import isfinite


def _valid_csi_rs_port_count(value: Int) -> Bool:
    return (
        value == 4
        or value == 8
        or value == 12
        or value == 16
        or value == 24
        or value == 32
    )


def _parameter_values(
    param_combination: Int,
) raises -> Tuple[Int, Int, Int, Int, Int]:
    # (M, alpha numerator, alpha denominator, beta numerator,
    #  beta denominator), transcribed from Table 5.2.2.2.7-1.
    if param_combination == 1:
        return (1, 3, 4, 1, 2)
    if param_combination == 2:
        return (1, 1, 1, 1, 2)
    if param_combination == 3:
        return (1, 1, 1, 3, 4)
    if param_combination == 4:
        return (1, 1, 1, 1, 1)
    if param_combination == 5:
        return (2, 1, 2, 1, 2)
    if param_combination == 6:
        return (2, 3, 4, 1, 2)
    if param_combination == 7:
        return (2, 1, 1, 1, 2)
    if param_combination == 8:
        return (2, 1, 1, 3, 4)
    raise Error("Rel-17 paramCombination-r17 must be in 1..8")


def _checked_exact_product_ratio(
    first: Int, second: Int, numerator: Int, denominator: Int, field: String
) raises -> Int:
    var product = (
        Int128(first) * Int128(second) * Int128(numerator)
    )
    if product < 0 or product % Int128(denominator) != 0:
        raise Error(field + " is not an exact integer")
    var result = product // Int128(denominator)
    if result > Int128(Int.MAX):
        raise Error(field + " exceeds Int")
    return Int(result)


def _validate_profile_inputs(
    csi_rs_ports: Int,
    param_combination: Int,
    ri_restriction_bitmap: Int,
    value_of_n: Int,
    pmi_subbands_per_cqi_subband: Int,
) raises -> Tuple[Int, Int, Int, Int, Int, Int, Int, Int]:
    if not _valid_csi_rs_port_count(csi_rs_ports):
        raise Error("Further Enhanced Type-II supports 4/8/12/16/24/32 ports")
    if ri_restriction_bitmap < 0 or ri_restriction_bitmap > 0xF:
        raise Error("typeII-PortSelectionRI-Restriction-r17 is four bits")

    var values = _parameter_values(param_combination)
    var frequency_vectors = values[0]
    var alpha_numerator = values[1]
    var alpha_denominator = values[2]
    var beta_numerator = values[3]
    var beta_denominator = values[4]

    # The three explicit "not expected to be configured" restrictions
    # immediately following Table 5.2.2.2.7-1.
    if (
        (param_combination == 1 or param_combination == 6)
        and (csi_rs_ports == 4 or csi_rs_ports == 12)
    ):
        raise Error("paramCombination-r17 1/6 excludes 4 and 12 CSI-RS ports")
    if (
        (param_combination == 7 or param_combination == 8)
        and csi_rs_ports == 32
    ):
        raise Error("paramCombination-r17 7/8 excludes 32 CSI-RS ports")
    if (
        param_combination == 5
        and csi_rs_ports == 4
        and (ri_restriction_bitmap & 0xC) != 0
    ):
        raise Error("4-port paramCombination-r17 5 excludes RI above two")

    if frequency_vectors == 1:
        if value_of_n != 0:
            raise Error("valueOfN is configured only when M equals two")
        if pmi_subbands_per_cqi_subband != 1:
            raise Error("R is fixed to one when M equals one")
    else:
        if value_of_n != 2 and value_of_n != 4:
            raise Error("valueOfN must be two or four when M equals two")
        if (
            pmi_subbands_per_cqi_subband != 1
            and pmi_subbands_per_cqi_subband != 2
        ):
            raise Error("Rel-17 R must be one or two when M equals two")

    var selected_ports = _checked_exact_product_ratio(
        csi_rs_ports,
        1,
        alpha_numerator,
        alpha_denominator,
        "K1",
    )
    if (selected_ports & 1) != 0:
        raise Error("K1 must select an even number of ports")
    var selected_vectors = selected_ports // 2
    # The specification writes K0 = ceil(beta * K1 * M).  Across all eight
    # Rel-17 table rows after the three legality restrictions above, the
    # product is integral, so this exact ratio is equal to the normative ceil.
    # Keeping the integrality assertion prevents a future table extension
    # from silently applying the current proof outside its domain.
    var per_layer_nonzero_limit = _checked_exact_product_ratio(
        selected_ports,
        frequency_vectors,
        beta_numerator,
        beta_denominator,
        "K0",
    )
    return (
        frequency_vectors,
        alpha_numerator,
        alpha_denominator,
        beta_numerator,
        beta_denominator,
        selected_ports,
        selected_vectors,
        per_layer_nonzero_limit,
    )


struct NRFeMIMORel17PortSelectionConfig(ImplicitlyCopyable):
    """Validated clause-5.2.2.2.7 decoded codebook configuration.

    Fields remain mutable for ordinary Mojo value semantics.  Every public
    algorithm below calls ``validate()`` again before using them.
    """

    var csi_rs_ports: Int
    var param_combination: Int
    var ri_restriction_bitmap: Int
    var frequency_vectors: Int
    var alpha: Float64
    var beta: Float64
    var value_of_n: Int
    var pmi_subbands_per_cqi_subband: Int
    var selected_ports: Int
    var selected_vectors: Int
    var per_layer_nonzero_limit: Int

    def __init__(
        out self,
        csi_rs_ports: Int,
        param_combination: Int,
        ri_restriction_bitmap: Int,
        frequency_vectors: Int,
        alpha: Float64,
        beta: Float64,
        value_of_n: Int,
        pmi_subbands_per_cqi_subband: Int,
        selected_ports: Int,
        selected_vectors: Int,
        per_layer_nonzero_limit: Int,
    ) raises:
        self.csi_rs_ports = csi_rs_ports
        self.param_combination = param_combination
        self.ri_restriction_bitmap = ri_restriction_bitmap
        self.frequency_vectors = frequency_vectors
        self.alpha = alpha
        self.beta = beta
        self.value_of_n = value_of_n
        self.pmi_subbands_per_cqi_subband = (
            pmi_subbands_per_cqi_subband
        )
        self.selected_ports = selected_ports
        self.selected_vectors = selected_vectors
        self.per_layer_nonzero_limit = per_layer_nonzero_limit
        self.validate()

    def validate(self) raises:
        """Revalidate mutable state against the exact table and restrictions."""
        if not isfinite(self.alpha) or not isfinite(self.beta):
            raise Error("Rel-17 alpha and beta must be finite")
        var expected = _validate_profile_inputs(
            self.csi_rs_ports,
            self.param_combination,
            self.ri_restriction_bitmap,
            self.value_of_n,
            self.pmi_subbands_per_cqi_subband,
        )
        var expected_alpha = (
            Float64(expected[1]) / Float64(expected[2])
        )
        var expected_beta = Float64(expected[3]) / Float64(expected[4])
        if (
            self.frequency_vectors != expected[0]
            or self.alpha != expected_alpha
            or self.beta != expected_beta
            or self.selected_ports != expected[5]
            or self.selected_vectors != expected[6]
            or self.per_layer_nonzero_limit != expected[7]
        ):
            raise Error("mutated or inconsistent Rel-17 feMIMO configuration")


def nr_femimo_rel17_port_selection_config(
    csi_rs_ports: Int,
    param_combination: Int,
    ri_restriction_bitmap: Int,
    value_of_n: Int = 0,
    pmi_subbands_per_cqi_subband: Int = 1,
) raises -> NRFeMIMORel17PortSelectionConfig:
    """Decode Table 5.2.2.2.7-1 and all adjacent legality restrictions.

    ``value_of_n=0`` denotes the normative absence of ``valueOfN`` for
    ``M=1``; for ``M=2`` the caller must supply 2 or 4.  The final argument
    is the decoded ``R`` value.
    """
    var values = _validate_profile_inputs(
        csi_rs_ports,
        param_combination,
        ri_restriction_bitmap,
        value_of_n,
        pmi_subbands_per_cqi_subband,
    )
    return NRFeMIMORel17PortSelectionConfig(
        csi_rs_ports,
        param_combination,
        ri_restriction_bitmap,
        values[0],
        Float64(values[1]) / Float64(values[2]),
        Float64(values[3]) / Float64(values[4]),
        value_of_n,
        pmi_subbands_per_cqi_subband,
        values[5],
        values[6],
        values[7],
    )


def nr_femimo_rel17_ri_allowed(
    config: NRFeMIMORel17PortSelectionConfig, layers: Int
) raises -> Bool:
    """Return bit ``r[layers-1]`` from the Rel-17 four-bit RI restriction."""
    config.validate()
    if layers < 1 or layers > 4:
        raise Error("Further Enhanced Type-II RI must be in one to four")
    return (config.ri_restriction_bitmap & (1 << (layers - 1))) != 0


def _binomial(n: Int, k: Int) raises -> Int:
    if n < 0 or k < 0 or k > n:
        return 0
    var reduced_k = k
    if reduced_k > n - reduced_k:
        reduced_k = n - reduced_k
    var result = Int128(1)
    for divisor in range(1, reduced_k + 1):
        result = (
            result * Int128(n - reduced_k + divisor)
        ) // Int128(divisor)
    if result > Int128(Int.MAX):
        raise Error("combinatorial state count exceeds Int")
    return Int(result)


def nr_femimo_rel17_i12_state_count(
    config: NRFeMIMORel17PortSelectionConfig,
) raises -> Int:
    """Return the exact number ``C(P_CSI-RS/2,L)`` of ``i1,2`` states.

    When ``alpha=1``, this returns one: clause 5.2.2.2.7 fixes ``m(i)=i``
    and does not report ``i1,2``.
    """
    config.validate()
    return _binomial(config.csi_rs_ports // 2, config.selected_vectors)


def nr_femimo_rel17_i12_to_vector_indices(
    config: NRFeMIMORel17PortSelectionConfig, i12: Int
) raises -> List[Int]:
    """Decode ``i1,2`` to the increasing selected vector indices ``m(i)``.

    This is the literal largest-``x*`` combinatorial algorithm in clause
    5.2.2.2.7.  Indices are zero based, matching the clause's ``m(i)``.
    """
    config.validate()
    var state_count = _binomial(
        config.csi_rs_ports // 2, config.selected_vectors
    )
    if i12 < 0 or i12 >= state_count:
        raise Error("i1,2 is outside the configured combinatorial range")

    var half_ports = config.csi_rs_ports // 2
    var cumulative = 0
    var selected = List[Int](capacity=config.selected_vectors)
    for index in range(config.selected_vectors):
        var y = config.selected_vectors - index
        var lower = y - 1
        var upper = half_ports - 1 - index
        var largest = lower
        for x in range(lower, upper + 1):
            var coefficient = _binomial(x, y)
            if i12 - cumulative >= coefficient:
                largest = x
        cumulative += _binomial(largest, y)
        selected.append(half_ports - 1 - largest)
    return selected^


def nr_femimo_rel17_vector_indices_to_i12(
    config: NRFeMIMORel17PortSelectionConfig,
    vector_indices: Span[Int, ...],
) raises -> Int:
    """Encode increasing ``m(i)`` indices with the normative combinadic sum."""
    config.validate()
    if len(vector_indices) != config.selected_vectors:
        raise Error("selected vector count does not equal L")
    var half_ports = config.csi_rs_ports // 2
    var result = Int128(0)
    for index in range(len(vector_indices)):
        var selected = vector_indices[index]
        if selected < 0 or selected >= half_ports:
            raise Error("selected port-vector index is outside P_CSI-RS/2")
        if index > 0 and selected <= vector_indices[index - 1]:
            raise Error("selected port-vector indices must strictly increase")
        result += Int128(_binomial(
            half_ports - 1 - selected,
            config.selected_vectors - index,
        ))
    var state_count = _binomial(half_ports, config.selected_vectors)
    if result < 0 or result >= Int128(state_count):
        raise Error("encoded i1,2 is outside the configured range")
    return Int(result)


def nr_femimo_rel17_strongest_coefficient_index(
    config: NRFeMIMORel17PortSelectionConfig,
    vector_index: Int,
    frequency_index: Int,
) raises -> Int:
    """Return ``i1,8,l = K1 * f* + i*`` from clause 5.2.2.2.7.

    ``vector_index`` is the clause's coefficient-vector index ``i*`` over
    ``0..K1-1``.  It is not a selected port-vector index ``m(i)`` over
    ``0..L-1``.
    """
    config.validate()
    if vector_index < 0 or vector_index >= config.selected_ports:
        raise Error("strongest-coefficient vector index is outside K1")
    if frequency_index < 0 or frequency_index >= config.frequency_vectors:
        raise Error("strongest-coefficient frequency index is outside M")
    var result = (
        Int128(config.selected_ports) * Int128(frequency_index)
        + Int128(vector_index)
    )
    if result > Int128(Int.MAX):
        raise Error("strongest-coefficient index exceeds Int")
    return Int(result)


def nr_femimo_rel17_strongest_coefficient_coordinates(
    config: NRFeMIMORel17PortSelectionConfig, i18: Int
) raises -> Tuple[Int, Int]:
    """Invert ``i1,8,l`` to ``(vector_index, frequency_index)`` exactly."""
    config.validate()
    var state_count = Int128(config.selected_ports) * Int128(
        config.frequency_vectors
    )
    if i18 < 0 or Int128(i18) >= state_count:
        raise Error("i1,8,l is outside K1*M")
    return (
        i18 % config.selected_ports,
        i18 // config.selected_ports,
    )


def nr_femimo_rel17_csi_coefficient_priority(
    config: NRFeMIMORel17PortSelectionConfig,
    layers: Int,
    layer_index: Int,
    vector_index: Int,
    frequency_index: Int,
) raises -> Int:
    """Return clause-5.2.3 ``Pri(l,i,f)`` for the Rel-17 codebook.

    ``layer_index`` is zero based at the API boundary; the formula uses the
    specification's one-based ``l=layer_index+1``. ``vector_index`` is the
    coefficient-vector index ``i`` over ``0..K1-1``, not ``m(i)`` over
    ``0..L-1``. Lower values have higher CSI Part-2 reporting priority.
    """
    config.validate()
    if layers < 1 or layers > 4:
        raise Error("Further Enhanced Type-II priority needs one to four layers")
    if (config.ri_restriction_bitmap & (1 << (layers - 1))) == 0:
        raise Error("priority requested for a rank excluded by the RI bitmap")
    if layer_index < 0 or layer_index >= layers:
        raise Error("layer index is outside the reported rank")
    if vector_index < 0 or vector_index >= config.selected_ports:
        raise Error("priority vector index is outside K1")
    if frequency_index < 0 or frequency_index >= config.frequency_vectors:
        raise Error("priority frequency index is outside M")
    var result = (
        Int128(config.selected_ports)
        * Int128(layers)
        * Int128(frequency_index)
        + Int128(layers) * Int128(vector_index)
        + Int128(layer_index + 1)
    )
    if result > Int128(Int.MAX):
        raise Error("CSI coefficient priority exceeds Int")
    return Int(result)


def nr_femimo_rel17_nonzero_coefficient_total(
    config: NRFeMIMORel17PortSelectionConfig,
    per_layer_counts: Span[Int, ...],
) raises -> Int:
    """Validate ``K_l_NZ <= K0`` and ``K_NZ <= 2*K0`` and return ``K_NZ``.

    One count is supplied per reported layer.  The strongest coefficient in
    each layer is always nonzero in clause 5.2.2.2.7, hence zero is rejected.
    """
    config.validate()
    if len(per_layer_counts) < 1 or len(per_layer_counts) > 4:
        raise Error("nonzero counts require one to four reported layers")
    var layers = len(per_layer_counts)
    if (config.ri_restriction_bitmap & (1 << (layers - 1))) == 0:
        raise Error("nonzero counts use a rank excluded by the RI bitmap")
    var total = Int128(0)
    for layer in range(layers):
        var count = per_layer_counts[layer]
        if count < 1 or count > config.per_layer_nonzero_limit:
            raise Error("per-layer nonzero coefficient count exceeds K0")
        total += Int128(count)
    var total_limit = Int128(2) * Int128(
        config.per_layer_nonzero_limit
    )
    if total > total_limit:
        raise Error("overall nonzero coefficient count exceeds 2*K0")
    if total > Int128(Int.MAX):
        raise Error("overall nonzero coefficient count exceeds Int")
    return Int(total)
