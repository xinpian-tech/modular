"""Exact NR PDSCH codeword-to-layer mapping for one through eight layers.

The production baseline is 3GPP TS 38.211 V18.9.0 clause 7.3.1.3 and
Table 7.3.1.3-1.  This module implements the complete PDSCH spatial-
multiplexing layer-mapping table: one codeword for one through four layers and
two codewords for five through eight layers.  Precoding, antenna-port mapping,
DM-RS port selection, resource allocation, scheduler state, and MIMO channel
estimation are separate algorithms and are deliberately not inferred here.
"""

from std.collections import Span
from std.math import isfinite
from wireless_dsp.core import Complex64


struct NRPDSCHCodewordLayerAllocation(ImplicitlyCopyable):
    """Normative number of layers assigned to each PDSCH codeword."""

    var layer_count: Int
    var codeword_count: Int
    var codeword0_layers: Int
    var codeword1_layers: Int

    def __init__(
        out self,
        layer_count: Int,
        codeword_count: Int,
        codeword0_layers: Int,
        codeword1_layers: Int,
    ) raises:
        self.layer_count = layer_count
        self.codeword_count = codeword_count
        self.codeword0_layers = codeword0_layers
        self.codeword1_layers = codeword1_layers
        self.validate()

    def validate(self) raises:
        """Reject mutations that no longer match Table 7.3.1.3-1."""
        if self.layer_count < 1 or self.layer_count > 8:
            raise Error("PDSCH layer count must be in [1,8]")
        var expected_codewords = 1 if self.layer_count <= 4 else 2
        var expected_first = (
            self.layer_count
            if self.layer_count <= 4
            else self.layer_count // 2
        )
        var expected_second = self.layer_count - expected_first
        if (
            self.codeword_count != expected_codewords
            or self.codeword0_layers != expected_first
            or self.codeword1_layers != expected_second
        ):
            raise Error("PDSCH codeword-to-layer allocation is not normative")


struct NRPDSCHLayerMapping(Movable):
    """Layer-major PDSCH modulation symbols with explicit dimensions."""

    var layer_count: Int
    var symbols_per_layer: Int
    var values: List[Complex64]

    def __init__(
        out self,
        layer_count: Int,
        symbols_per_layer: Int,
        var values: List[Complex64],
    ) raises:
        self.layer_count = layer_count
        self.symbols_per_layer = symbols_per_layer
        self.values = values^
        self.validate()

    def validate(self) raises:
        """Revalidate dimensions and finite values at every public boundary."""
        _ = nr_pdsch_codeword_layer_allocation(self.layer_count)
        if self.symbols_per_layer < 1:
            raise Error("PDSCH symbols per layer must be positive")
        if self.layer_count > Int.MAX // self.symbols_per_layer:
            raise Error("PDSCH layer mapping dimensions overflow Int")
        if len(self.values) != self.layer_count * self.symbols_per_layer:
            raise Error("PDSCH layer mapping storage length is inconsistent")
        for index in range(len(self.values)):
            if (
                not isfinite(self.values[index].re)
                or not isfinite(self.values[index].im)
            ):
                raise Error("PDSCH layer symbols must be finite")

    def __getitem__(self, layer: Int, symbol: Int) raises -> Complex64:
        if (
            layer < 0
            or layer >= self.layer_count
            or symbol < 0
            or symbol >= self.symbols_per_layer
        ):
            raise Error("PDSCH layer mapping index is out of range")
        return self.values[layer * self.symbols_per_layer + symbol]


struct NRPDSCHCodewords(Movable):
    """Demapped PDSCH codewords; codeword 1 is empty for at most four layers."""

    var codeword0: List[Complex64]
    var codeword1: List[Complex64]

    def __init__(
        out self,
        var codeword0: List[Complex64],
        var codeword1: List[Complex64],
    ):
        self.codeword0 = codeword0^
        self.codeword1 = codeword1^


def nr_pdsch_codeword_layer_allocation(
    layer_count: Int,
) raises -> NRPDSCHCodewordLayerAllocation:
    """Return the complete Table 7.3.1.3-1 codeword/layer partition."""
    if layer_count < 1 or layer_count > 8:
        raise Error("PDSCH layer count must be in [1,8]")
    if layer_count <= 4:
        return NRPDSCHCodewordLayerAllocation(
            layer_count, 1, layer_count, 0
        )
    var first_layers = layer_count // 2
    return NRPDSCHCodewordLayerAllocation(
        layer_count, 2, first_layers, layer_count - first_layers
    )


def _validate_codeword(
    codeword: Span[Complex64, ...], name: String
) raises:
    for index in range(len(codeword)):
        if not isfinite(codeword[index].re) or not isfinite(codeword[index].im):
            raise Error(name + " symbols must be finite")


def nr_pdsch_layer_map(
    codeword0: Span[Complex64, ...],
    codeword1: Span[Complex64, ...],
    layer_count: Int,
) raises -> NRPDSCHLayerMapping:
    """Map one or two modulation-symbol codewords to PDSCH layers exactly.

    For one through four layers ``codeword1`` must be empty.  For five through
    eight layers both codewords must be nonempty and yield the same number of
    symbols per layer under the normative layer partition.
    """
    var allocation = nr_pdsch_codeword_layer_allocation(layer_count)
    if len(codeword0) < 1:
        raise Error("PDSCH codeword 0 must be nonempty")
    if len(codeword0) % allocation.codeword0_layers != 0:
        raise Error("PDSCH codeword 0 does not divide across its layers")
    var symbols_per_layer = len(codeword0) // allocation.codeword0_layers
    if allocation.codeword_count == 1:
        if len(codeword1) != 0:
            raise Error("PDSCH codeword 1 requires at least five layers")
    else:
        if len(codeword1) < 1:
            raise Error("two-codeword PDSCH mapping requires codeword 1")
        if len(codeword1) % allocation.codeword1_layers != 0:
            raise Error("PDSCH codeword 1 does not divide across its layers")
        if len(codeword1) // allocation.codeword1_layers != symbols_per_layer:
            raise Error("PDSCH codewords produce unequal symbols per layer")
    _validate_codeword(codeword0, "PDSCH codeword 0")
    _validate_codeword(codeword1, "PDSCH codeword 1")

    if layer_count > Int.MAX // symbols_per_layer:
        raise Error("PDSCH layer mapping dimensions overflow Int")
    var values = List[Complex64](
        length=layer_count * symbols_per_layer,
        fill=Complex64(0.0, 0.0),
    )
    for symbol in range(symbols_per_layer):
        for layer in range(allocation.codeword0_layers):
            values[layer * symbols_per_layer + symbol] = codeword0[
                allocation.codeword0_layers * symbol + layer
            ]
        for local_layer in range(allocation.codeword1_layers):
            var layer = allocation.codeword0_layers + local_layer
            values[layer * symbols_per_layer + symbol] = codeword1[
                allocation.codeword1_layers * symbol + local_layer
            ]
    return NRPDSCHLayerMapping(
        layer_count, symbols_per_layer, values^
    )


def nr_pdsch_layer_demap(
    mapping: NRPDSCHLayerMapping,
) raises -> NRPDSCHCodewords:
    """Invert Table 7.3.1.3-1 and recover the original PDSCH codewords."""
    mapping.validate()
    var allocation = nr_pdsch_codeword_layer_allocation(mapping.layer_count)
    var codeword0 = List[Complex64](
        capacity=allocation.codeword0_layers * mapping.symbols_per_layer
    )
    var codeword1 = List[Complex64](
        capacity=allocation.codeword1_layers * mapping.symbols_per_layer
    )
    for symbol in range(mapping.symbols_per_layer):
        for layer in range(allocation.codeword0_layers):
            codeword0.append(mapping[layer, symbol])
        for local_layer in range(allocation.codeword1_layers):
            codeword1.append(
                mapping[
                    allocation.codeword0_layers + local_layer, symbol
                ]
            )
    return NRPDSCHCodewords(codeword0^, codeword1^)
