# Phase 0/1 design and capability report

## Goal and boundary

This slice establishes a compilable Mojo package, explicit numeric semantics,
and reusable value/view types. It is not an NR or Wi-Fi modem. CPU-readable
reference code is the active backend; SIMD and GPU are execution policies to
add only after the same API and tests are validated.

## Toolchain findings

- A source package is a directory containing `__init__.mojo`. In the pinned
  Mojo 1.1 nightly, `mojo package` is deprecated; `mojo precompile` emits a
  `.mojoc` package artifact. This project supports both source imports and
  precompiled packages.
- Mojo parameters in `[]` accept both types and compile-time values. `Complex`
  is parameterized by `DType`; `Fixed` is value-parameterized by its Q format
  and policies.
- `SIMD[dtype, width]` is the native CPU vector abstraction. Optimized kernels
  will specialize widths while retaining scalar reference entry points.
- `Pointer[T, origin]` and standard `Span[T, origin]` carry lifetime and
  mutability in `Origin`. `StridedSpan` preserves that model and performs no
  allocation.
- Mojo GPU APIs use device-passable values and separate host launch policy.
  Views deliberately keep explicit pointer/shape/stride metadata so later GPU
  buffers can preserve semantics without sharing CPU loop structure.
- Tests use `std.testing.TestSuite` and run with the Mojo package exported by
  the repository Nix flake or through Bazel. The benchmark uses a monotonic
  nanosecond counter and retains a checksum to keep work observable.

The repository's `flake.nix` derives the exact Mojo version from
`bazel/mojo.MODULE.bazel` and builds it reproducibly from this checkout. It is
the authoritative environment. Stable users should use the matching stable
repository branch rather than mixing compiler and source APIs.

The validation host reports Float32/Float64 native SIMD widths of 16/8 and no
compatible accelerator. GPU host/runtime execution is therefore researched
from the checked-in `max.gpu.host` and `std.gpu` sources but is not falsely
reported as runtime-tested. The checked-in GPU vector-add example, including
`DeviceContext`, device buffers, `enqueue_function`, and `std.gpu` indices, was
successfully compiled with the pinned compiler. Run
`examples/capabilities.mojo` to reproduce the host probe on another machine.

## API and data model

`Complex[dtype]` is a split pair of scalar components and defines add,
subtract, multiply, conjugate, MAC, magnitude, squared magnitude, and safe
zero normalization. This is the mathematical value type; `ComplexSpan` and
`IQBuffer` will be layout views, allowing interleaved or split IQ without
changing arithmetic.

The standard `Span` is the contiguous view. `StridedSpan[T, origin]` adds an
element stride and retains lifetime/mutability tracking. It is non-owning and
zero-copy. Kernels will accept input/output views and explicit workspace;
allocating convenience wrappers belong outside the kernel layer.

`Fixed[fraction_bits, storage_bits, rounding_mode, overflow_mode]` uses Int64
as its reference accumulator/storage carrier, but narrows to the configured
signed two's-complement width after each public operation. The initial policy
set is round-toward-zero or nearest-ties-away, and wrap or saturation.

## Mathematical and numerical basis

Complex multiplication follows
`(a+jb)(c+jd)=(ac-bd)+j(ad+bc)`. Magnitude squared is `a^2+b^2`; normalize
divides both components by its square root and maps zero to zero.

For Q-format multiplication, raw operands `A` and `B` produce
`narrow(round(A*B / 2^F))`. The implementation defines the order explicitly:
Int64 product, signed rounding, arithmetic rescale, then narrowing. Addition
and subtraction narrow after the operation. `storage_bits` is initially
limited to 32 so every raw multiplication fits the signed Int64 reference
accumulator. A later wide-accumulator MAC must state its accumulator width and
narrowing boundary.

## Verification and benchmark

Deterministic tests cover complex arithmetic, conjugation, normalization,
zero, MAC, zero-copy striding, Q-format arithmetic, positive/negative
saturation, wrap, rescaling, and symmetric negative rounding. The capability
test compiles value-parameterized Float32 and Int16 SIMD specializations.
Deterministic property/differential tests sweep complex arithmetic against
independent scalar formulas, exhaust a local fixed-point raw domain, and check
the unit-magnitude normalization invariant. The next testing increment adds a
seeded external Python/NumPy vector generator whose output is data-only, never
a runtime dependency.

Run:

```bash
nix run .#mojo -- run -I mojo-wireless-dsp mojo-wireless-dsp/tests/core_test.mojo
nix run .#mojo -- run -I mojo-wireless-dsp mojo-wireless-dsp/tests/fixed_test.mojo
nix run .#mojo -- run -I mojo-wireless-dsp mojo-wireless-dsp/tests/capability_test.mojo
nix run .#mojo -- run -I mojo-wireless-dsp mojo-wireless-dsp/tests/differential_test.mojo
nix run .#mojo -- run -I mojo-wireless-dsp mojo-wireless-dsp/benchmarks/core_bench.mojo
nix run .#mojo -- precompile mojo-wireless-dsp/wireless_dsp -o wireless_dsp.mojoc
nix develop -c bazel-nix test //mojo-wireless-dsp:core_test //mojo-wireless-dsp:fixed_test //mojo-wireless-dsp:capability_test //mojo-wireless-dsp:differential_test
# Compile-only GPU capability spike (runtime requires a compatible accelerator):
nix run .#mojo -- build -I max/mojo -I max/kernels/src max/examples/gpu-intro/vector_addition.mojo -o /tmp/vector_addition
```

Report median and p95 ns/element across repeated runs, compiler version, CPU,
dtype, input length/alignment, and checksum. Optimization is accepted only if
the reference tests and differential vectors remain unchanged.

## Cross-protocol reuse and next step

These types contain no NR or IEEE configuration. They are shared by FFT,
correlation, channel estimation, equalization, QAM/LLR, and synchronization in
both families. The smallest next vertical increment is reductions
(sum/dot/complex-dot/energy) over contiguous and strided views, with Float64
reference, Float32 practical reference, seeded differential tests, and a SIMD
CPU specialization benchmark.
