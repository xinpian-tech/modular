# Fixed artifact and numeric contract V2

V2 is the canonical text contract emitted by
`wireless_dsp.testing.fixed_vectors`.  The schema version is carried by the
magic line (`MWDSP-FIXED-V2`, `MWDSP-COMPLEX-FIXED-V2`, or
`MWDSP-SCALE-TRACE-V2`).  The existing `version=` argument remains the
caller-owned testcase/vector revision and is not the wire-schema version.

## Canonical checksum

Every V2 record builds its header in the exact field order emitted by the
serializer.  Let `H` be all UTF-8 bytes from the magic through the terminating
newline of `checksum_scope=...`.  The decimal `checksum` field is unsigned
FNV-1a-64 over:

- scalar: `H`, followed by every raw value as a two's-complement Int64 in
  little-endian byte order;
- complex: `H`, followed by interleaved real and imaginary Int64 words;
- scale trace: `H`, followed by each row's raw value, storage bits, fraction
  bits, right shift, rounding mode, and overflow mode, all as Int64 words.

The `checksum=` and textual `data=`/`data_iq=` lines are not part of `H`.
Their numeric contents are protected by the canonical binary words above.
Consequently testcase identity, stage identity, vector revision, shape,
layout, Q format, rounding, overflow, and payload all affect the checksum.

`Span` inputs are contiguous.  Scalar and complex records therefore emit
`stride=1` with `scalar-contiguous` or `iq-interleaved-contiguous` layout and
reject any caller-supplied stride other than one.  A future strided serializer
must accept a real strided view and checksum the values in its declared
logical traversal order; it must not attach invented stride metadata to a
contiguous `Span`.

## Scale and FFT traces

`ScaleTrace` owns six equally sized columns:

```text
raw:storage_bits:fraction_bits:right_shift:rounding:overflow
```

`apply_scale_schedule` records the actual rounding and overflow modes at each
executed register boundary.  The legacy four-list constructor remains
available and explicitly supplies the historical nearest-away/saturating
defaults.

`FixedFFTTrace` owns the input, the exact quantized half-table twiddle ROM,
every complete radix-2 stage vector in stage-major order, per-stage
Q/shift/rounding/overflow metadata, and the final output.  Its serializer emits
independently checksummed V2 records in this order: config, input, twiddle ROM,
schedule, every stage, output, and an aggregate trace checksum split into low
and high 32-bit words.  The serializer rejects a trace whose dimensions or
final-stage/output relationship are inconsistent.

## Q-format operation boundary

Runtime fixed-point operations call `validate_qformat` before using descriptor
fields.  This is required because `QFormat` fields remain addressable for
source compatibility and can be mutated after construction.  Invalid mutated
descriptors are rejected; `raw_fits` is the non-raising predicate and returns
false for them.  `narrow_raw` is now a raising API for the same reason.

`quantize_raw(Float64, QFormat)` makes a deliberately conservative bit-exact
ingress promise only for signed storage widths up to 53 bits.  Wider formats
remain supported by integer raw-word operations through the normal 62-bit
golden-model limit.  `dequantize_raw` is an audit conversion to the nearest
representable Float64 and is not a reversible encoding for large raw
magnitudes.

The public serializer function signatures are retained, but their emitted
wire text intentionally migrates from V1 to V2.  Consumers must dispatch on
the magic line rather than interpreting V2 records as V1.
