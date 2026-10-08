# Verification ledger

## Authoritative environment and algorithm gate

All Mojo validation uses the repository root `flake.nix`:

```bash
nix shell .#mojo --command mojo --version
```

The pinned compiler is `Mojo 1.1.0.dev2026081813`. Pixi or an ambient `mojo`
binary is not evidence for this project. The flake wrapper does not expose a
formatter command on this host, so warning-clean compilation, executable
tests and whitespace/diff checks are used; formatting is not claimed.

The authoritative CPU/protocol/fixed algorithm gate is:

```bash
./mojo-wireless-dsp/scripts/verify_algorithms.sh
```

It enters `nix shell .#mojo` itself and then:

1. SHA-locks the frozen Wi-Fi/NR external-oracle generator and fixture bytes,
   rejects one-byte mutations, and byte-regenerates both fixtures; the NR
   regeneration fails closed unless a clean checkout at the pinned py3gpp
   commit is supplied;
2. checks exact BUILD registration for every test, benchmark and example;
3. warning-clean precompiles the public `wireless_dsp` package;
4. warning-clean builds and runs every in-scope test, benchmark and example;
5. runs the public evidence audit in strict algorithm-only mode;
6. audits the complete communication-protocol specification matrix,
   official-source domains, executable evidence paths and explicit
   exclusions/tracking rows; runs both the Specification and 21-column Feature
   matrices in strict completion mode; and checks the exact 11-field contract
   for every required Feature row, including status, declared profile and
   boundary;
7. treats matrix status as implementation maturity, then separately joins
   every maturity claim to the 17-column ratified-authority manifest, requiring
   an eligible formal specification, exact version and clauses, official
   status/date/URL, downloaded-artifact SHA-256 and reviewed errata state;
   inventory Work Items, PARs, TRs and WG documents cannot authorize
   production, and a licensed IEEE, Bluetooth SIG, Thread Group or CSA
   authority additionally requires an artifact-bound company/user rights
   attestation;
8. compiles the fixed-artifact V2 generator, regenerates the corpus twice and
   byte-compares both outputs with the checked-in corpus;
9. syntax-checks shell scripts and rejects trailing whitespace; and
10. queries the Bazel target graph unless explicitly skipped.

Strict kernel-evidence, matrix-completion and authority results are retained
until all deterministic, artifact and Bazel checks have run, then the highest
exit status is returned. This keeps the full verification log useful while
still failing closed on evidence gaps, formal coverage gaps or a licensed
final standard that cannot be qualified. No retained failure is downgraded to
a warning.

The gate discovers sources and reports test, benchmark, package-artifact and
Bazel-label observations at run time. Those observations are authoritative;
this document intentionally does not copy totals that become stale as the
algorithm surface grows. Components outside the CPU algorithm scope are
omitted from source execution, export completeness, evidence status and all
reported counts by this gate.

`MWDSP_VERIFY_SKIP_BAZEL_QUERY=1` can isolate a host without the query tool,
but it is a reduced structural check and should be disclosed. It does not
change algorithm test or evidence results.

## Direct test, build and coverage commands

Run one suite:

```bash
nix shell .#mojo --command mojo run -I mojo-wireless-dsp \
  mojo-wireless-dsp/tests/nr_mcs_tbs_test.mojo
```

Run every algorithm-scope test from the repository root:

```bash
while IFS= read -r test_file; do
  nix shell .#mojo --command mojo run -I mojo-wireless-dsp \
    "$test_file" || exit 1
done < <(rg --files mojo-wireless-dsp/tests -g '*.mojo' \
  | rg -v '/gpu_' | sort)
```

Compile the same tests with warnings treated as errors:

```bash
while IFS= read -r test_file; do
  output="/tmp/$(basename "${test_file%.mojo}")"
  nix shell .#mojo --command mojo build --Werror -I mojo-wireless-dsp \
    "$test_file" -o "$output" || exit 1
done < <(rg --files mojo-wireless-dsp/tests -g '*.mojo' \
  | rg -v '/gpu_' | sort)
```

Precompile the complete public package:

```bash
nix shell .#mojo --command mojo precompile --Werror -I mojo-wireless-dsp \
  mojo-wireless-dsp/wireless_dsp -o /tmp/wireless_dsp.mojoc
test -s /tmp/wireless_dsp.mojoc
```

Audit exactly the algorithm scope:

```bash
./mojo-wireless-dsp/scripts/audit_kernel_coverage.sh \
  --strict --exclude-component backend_gpu
./mojo-wireless-dsp/scripts/audit_specification_coverage.sh --strict
bash mojo-wireless-dsp/scripts/audit_feature_coverage.sh --strict
bash mojo-wireless-dsp/scripts/audit_ratified_authorities.sh
bash mojo-wireless-dsp/scripts/audit_ratified_authorities.sh \
  --verify-downloads
```

The audit enumerates exported functions in enabled DSP, channel, CPU, fixed,
testing/link-simulation, NR and Wi-Fi scopes. It requires exactly one ledger
row per public function, validates referenced test and benchmark symbols,
follows local helpers to confirm API reachability, and rejects unsupported
independent-oracle claims.  Benchmark evidence additionally resolves to one
unique `@no_inline` workload per ledger API; a workload must call its target
one or more times as a homogeneous batch, may not call another ledger API,
cannot be reused as the denominator for multiple APIs, and must execute
between a complete ordered pair of counter reads reachable from `main`.
A caller may own that pair around a reachable workload, but an unmatched
start read is never timing evidence.  This structural
gate complements the source
review that keeps configuration, `List`, `Span`, fixtures and full-output
scans outside the timed region. Every enabled `kernel`, `table_config` and
`artifact` row requires deterministic, edge, property, independent
differential, tolerance and reachable dedicated benchmark evidence; there is
no weaker table/artifact exception. A `PARTIAL` or `MISSING` enabled row fails
strict mode. Excluded rows
remain subject to global ledger syntax and duplicate-name checks but cannot
affect the algorithm result.

The call-graph part of this audit strips comments, ordinary strings and
triple-quoted docstrings, and recognizes an API only at an executable call
site; a field name or prose mention cannot satisfy evidence reachability.
The Feature benchmark scanner applies the same complete counter-pair rule, so
a lone start read or a target moved beyond its stop cannot qualify a row. Its
automatic timer-boundary/full-output scanner is additionally enabled for the
specialized Wi-Fi CCK, PLCP, OFDM, SIGNAL and HE/EHT benchmark families that
publish separate full-output and O(1) fingerprints. For other benchmark
families the automatic guarantee is deliberately limited to unique
`@no_inline` target attribution; fixture placement and timer-after result
consumption are established by the checked source-review findings and retained
double-run logs, rather than being overclaimed as a universal parser proof.

The separate specification audit requires the current published LTE
36.101-Annex-B/36.211/36.212/36.213/36.214 and the bounded TS 36.133
clause 4.2.2.1 non-eDRX serving-cell slice, NR
38.211/38.212/38.213/38.214/38.215, the bounded TS 38.321 clause 5.1.3
RA-RNTI arithmetic, TR 38.901 and IEEE 802.11-2024/802.11be-2024 baselines,
plus the Rel-17 RedCap impacted-spec inventory and separately scoped Rel-18
eRedCap feature. It keeps Bluetooth Core 6.3, Matter 1.6 and Zigbee Core R23.2
as `PARTIAL` Specification rows while requiring separate broad `MISSING` and
narrow `COMPLETE` Feature identities. IEEE 802.15.4-2024 and Thread 1.4.1
remain `MISSING/BLOCKED_METADATA`; no family may borrow another family's
evidence. The 21-column audit additionally requires the approved NR
Work Items for NTN, sidelink, positioning, NR-U, MBS, enhanced MIMO/multi-TRP,
coverage enhancement, LP-WUS, Ambient IoT and FR2-2, alongside the published
Wi-Fi PHY and deterministic-MAC families. `BOUNDED` rows must point to real source
and test files. The separate 21-column Feature audit admits
`COMPLETE/PARTIAL/MISSING/EXCLUDED/TRACKING`, so a formally published
CPU-implementable algorithm cannot disappear behind a broad exclusion. This
prevents a generic DSP primitive or a draft from being counted as
protocol-specific coverage. These values describe implementation maturity,
not production authority; the separate ratification join may block even a
`COMPLETE` implementation. Non-strict mode verifies that every gap is
explicit; strict Specification and Feature modes are expected to fail while
any formal row remains `PARTIAL` or `MISSING`. The reviewed matrices and exact boundaries are in
[specification-coverage.md](specification-coverage.md).

`testing/authority_manifest.tsv` is the human-reviewed trust receipt for
ratification, and the audit script pins its complete SHA-256 so a plausible
status/date/scope/hash edit cannot silently change that receipt. A deliberate
authority refresh must review official records and update both files. A
`PRODUCTION` authority must be a normative specification, standard or
amendment in an allowed formal status, with an exact calendar-valid full date, direct
artifact hash, exact clause scope and completed errata review. For every
family's `COMPLETE` or `PARTIAL` row, each clause/table token must be contained
by the same exact specification/version `PRODUCTION` record; numeric points and
ranges are joined by safe parent/range inclusion, while Annex and Table
identities accept only explicit published spellings and bounded shorthand. A uniquely resolved
`WORK_ITEM/INVENTORY_ONLY` URL is permitted as feature provenance only when its
registered UID/WID identity is explicit in the row, and every normative
TS/version token still qualifies independently. Release 19 is eligible for
that normal fail-closed process only after its 2025-12-12 freeze date; the
current month-dated, broad-scope V19 records remain `BLOCKED_METADATA`.
Release 20 and later remain structurally forbidden from `PRODUCTION`; Work Item,
PAR, TR and WG-document records are inventory/reference only. The authoritative
full verifier always uses download mode, which re-fetches direct official artifacts and checks both SHA-256
and file magic.  Licensed IEEE, Bluetooth SIG, Thread Group and CSA artifacts
cannot become `PRODUCTION` unless the reviewed three-column rights receipt
names an exact authority ID, artifact SHA-256 and
`IMPLEMENTATION_RIGHTS_CONFIRMED`. The repository default is
`testing/license_rights_attestation.tsv`; an absolute
`MWDSP_LICENSE_RIGHTS_ATTESTATION_FILE` remains available for a separately
managed company receipt. The audit pins the reviewed default receipt bytes and
validates every exact artifact binding. It is not a digital-signature service,
membership registry or independent legal opinion, so the company/user remains
responsible for the truth and applicability of the assertion.
Production source files that cite WG records must also
appear in `testing/source_authority_references.tsv`; the audit requires their
final normative authority plus `CROSS_CHECK_ONLY` reference identities.  A
source that intentionally exposes only non-normative channel profiles uses
`REFERENCE_PROFILE_ONLY` with no normative authority and is excluded from
protocol completion.  Explicit WG URLs and bare DCN, ballot and superseded
public-draft identifiers must all resolve to pinned `WG_DOC/REFERENCE_ONLY`
artifacts.

## Coverage by evidence class

| Area | Deterministic and edge evidence | Independent/property/statistical evidence |
| --- | --- | --- |
| Core/numerics | Complex operations, zero-copy/owned storage, Q-format ties, wrap/saturation, accumulators and scale schedules | Formula grids and exhaustive/seeded fixed raw-input comparisons |
| DSP/modem | FFT 64--4096, OFDM, FIR/streaming, correlation, QAM/LLR and CRC boundaries | Direct DFT/formula checks, round trips and seeded AWGN statistics |
| MIMO/FEC | Matrix decomposition/equalization, relative singularity/Hermitian/positive-definite checks, syndrome, rate matching and decoder termination | Reconstruction/residual checks, scale-invariant decisions, embedded NumPy MIMO vectors and encode/decode differentials |
| Monte-Carlo | Checked SNR conversions, counter overflow/merge, Wilson intervals, stopping and Cartesian validation | Semantic-seed replay, axis-order invariance, exact shard merge and raw-energy composition |
| Bluetooth | Core 6.3 Classic BR/EDR raw ten-bit header HEC generation/checking; LE 1M/2M uncoded preamble, caller-owned Access Address/PDU bit serialization, CRC-24, whitening and inverse verdicts over the exact 2--258-octet domain; optional LE Coded S=2/S=8 transmit symbols and exact-pattern/known-boundary hard-FEC reference receive over the exact 2--257-octet domain; complete Part-A LE 1M/2M GFSK parameter-limit rows and predicates | All 20 Part-G HEC literals plus an independent eight-cell oracle over all 1024-by-256 header/initialization pairs; two consistent uncoded official packets, all 40 official whitening prefixes, independent scalar CRC/LFSR composition and the pinned Part C 4.2.2 conflict; both complete 510/912-symbol coded fixtures, all 16 S8 words, every legal coded PDU geometry, independent delay-cell FEC composition, 16 owned RX checkpoints, exact endpoints and mutable rejection; complete literal GFSK rows, all 17 mutable fields across five consumers, strict/inclusive endpoints, NaN/Inf/Int edges and 512 seeded independent predicate cases; each public API has a unique post-timer-consumed workload |
| Matter | Matter 1.6 anonymous signed/unsigned integer TLV elements with explicit 1/2/4/8-octet width and exact single-element shape | Six official Table 127 vectors, exhaustive one-octet domains, all 256 control octets, independent repeated-division base-256 oracle, width/value endpoints and mutable decode rejection |
| Zigbee | Zigbee R23.2 fixed eight-octet protocol-version-two unsecured unicast NWK data base header | Literal and independent bit-pack oracles, exhaustive 65,536-word Frame Control predicate, all unicast addresses, all radius/sequence octets, ignored receive-reserved bits and full mutable-field rejection |
| LTE | EPA/EVA/ETU with mutable-profile revalidation, FDD normal-CP resources, LTE PSS/SSS/CRS/Gold, PDSCH/PUSCH scrambling and SISO mapping, complete 1/2-RB short-table plus 3--110-RB ZC PUSCH DM-RS, exact caller-resolved 6-/18-subcarrier IFDMA short tables, format-0 PRACH, exact 2/3/5-smooth SC-FDMA domain, CRC/segmentation/QPP/turbo/tail-biting/rate matching with filler `NULL` carried through systematic and first-parity streams, base MCS/RV/TBS/resource allocation, finite-domain measurements, and TS 36.133 non-eDRX Nserv/spacing/trigger arithmetic | Complete static tables including all 30x12, 30x24, 30x6 and 30x18 short DM-RS phases, independent sequence/coding/mapping equations, seeded profile realization, all four Table 4.2.2.1-1 rows plus exhaustive/seeded threshold oracles, NaN/infinity/overflow/Int-extreme boundaries, and dedicated per-API LTE workloads with O(1) post-timing fingerprints; IFDMA applicability and delta/m derivation, DM-RS hopping/OCC/resource mapping, other PRACH formats, eDRX/acquisition/filtering/broader RRM state and the extended current 44-row TBS table are not claimed |
| NR | Frozen Release-18 MCS/TBS tables and exact 1--8-layer codeword mapping; PBCH/PDSCH/PUSCH/PUCCH/PRACH/UCI; bounded PDCCH/DCI and TS 38.213 procedures, including complete narrow non-grouped monitoring-slot, 14-bit first-symbol and jointly owned TS 38.213/38.331 symbol-level occasion slices; TS 38.215 measurement/positioning-time arithmetic; Rel-17 NTN timing/Doppler, Rel-18 NTN RACH-less-CG mapping/threshold and SCI-1A/PSCCH sidelink slices; RedCap capability/HD-FDD/RLM/BFD/serving/Annex schedules/relaxation/MAC decisions, 13 caller-profiled TS 38.533 target-cell deadline phases and a `PARTIAL` FR1 20-MHz representative cross-stage composition; LDPC/Polar and numeric edges | Static clause vectors, external PBCH, independent layer-index and uplink/PRACH compositions, complete periodicity/offset tables, repeated-increment monitoring-slot oracle, all 14 bit anchors, exhaustive 14-bit mask/duration/CP oracle and interval-pair edges, PDCCH checkpoints, measurement/NTN equations and exact SSB/DMRS ordering tables, SCI/PSCCH static digests, independent DL-PRS Gold/mapping oracles, exact RedCap table/timer/FeatureCombination and seed-driven conformance-state oracles, nested representative wiring checkpoints (not a normative end-to-end oracle) and true PUSCH/PDSCH AWGN/TDL trials |
| Wi-Fi | Complete declared 20-MHz SISO Clause-17/ERP-OFDM baseband over all eight rates; bounded aligned Clause-15/16 DSSS/CCK PLCP/PPDU; TVHT tables/arithmetic; Clause-20 DMG core; Clause-28 EDMG integer geometry/grid; adopted single-channel WUR LDR/HDR reference; EBCS Mode-1/countdown; HT6/VHT8/HE10/EHT13 and SIGNAL fields; bounded one-through-four-stream parser/CSD/direct identity mapping; exact EHT 20--320-MHz geometry, assigned non-OFDMA puncturing and large-MRU tables; S1G/FTM; WLAN LDPC; acquisition and deterministic MAC arithmetic; bounded 802.11bh Device/IRM/PASN base fields and explicit shared-identity status transitions | Independent legacy/DSSS/CCK/VHT8/EHT13 receive fixtures; exhaustive TVHT channel/tone tables and 600 mode-expanded MCS/timing configurations over 120 normative MCS rows; all six DMG Golay tables; all EDMG geometry/channel/GI rows and independent grid maps; complete WUR randomizer/tone/shift tables and direct-IDFT oracle; EBCS Mode-1 bytes, exhaustive countdown and seeded membership; independent BCC/interleaver/QAM/direct-IDFT/SIGNAL assemblers; exhaustive parser/CSD and EHT puncturing/MRU tables plus seeded inverses; S1G/FTM/CCK/scrambler evidence; complete 802.11bh status/action/address-bit tables, direct byte-layout assembler and seeded payload/state differential oracles; packet replay/shards; exact MAC/delimiter properties and low-SNR erasure counters |
| Channel/CPU | Impairments, fading, fractional delay, TDL/CDL/TGn/TGac/TGax; practical Float32 FFT/OFDM/SISO/MIMO/FIR/QAM | Seed reproducibility, empirical power/Doppler/spatial checks and Float32-versus-Float64/scalar-versus-SIMD comparisons |
| Fixed/artifacts | Fixed DSP/MIMO/sync/BCC, acquired Wi-Fi, generic and NR LDPC, bounded fixed NR PDSCH, V2 records and manifest fault classes | Bit-exact integer oracles, fixed-versus-Float64 audit, detected-slice composition, checked-in corpus parsing and two-pass byte regeneration |

The executable Wi-Fi LDPC profile, encoder, rate-matching and decoder paths
are now backed by a complete independent all-profile corpus. Pinned BSD-3
YALDPC and MIT tavildar implementations agree on all 2,160 base shifts; a
test-owned expansion compares all 55,620 CSR edges, and the tavildar native
C++ encoder supplies twelve fixed information/codeword pairs. This evidence
caught and fixed the 1296-bit rate-2/3 row-3 column-10 shift (`23` to `22`).
The generator and fixture have SHA-256 receipts, embedded license notices,
one-byte mutation rejection and exact dual-source byte regeneration. They are
cross-implementation evidence only: production tables, checksums and local
round trips remain inadmissible as independent oracles, and the IEEE
normative authority remains `BLOCKED_METADATA` until final IEEE artifact bytes,
hashes, exact clauses and errata receipts are available.

The Rel-18 NTN verification profile requires nonempty decoded 4/8-bit SSB
and 8-bit type-1 DMRS subsets; its width, reserved-bit, ordering and strict
threshold edges are tested independently. Rel-18 sidelink verification covers
only the complete bounded slot-mask truth table, half-open overlap/strict-RSRP
endpoints and the published two-CC SL_n47B table. It does not use random
selection or scheduler policy as an oracle.

Rel-17 feMIMO evidence additionally exhausts the bounded Type-II
port-selection parameter table, RI masks and combinadic vector-selection
domain, with independent coefficient index/priority/count formulas. It does
not claim full CSI reports, precoding matrices, beams or multi-TRP procedures.

These tests validate the declared algorithms and bounded mini-PHY profiles.
They do not substitute for exhaustive standard conformance vectors,
third-party OTA interoperability, RF calibration, complete PPDUs/MAC behavior,
every scheduler configuration, synthesized RTL or hardware equivalence.

## CPU link-simulation evidence

`wireless_dsp.testing.monte_carlo` stores raw counts and energies so independent
workers can merge results before any division. Its semantic seed coordinates
separate payload, channel, noise and impairment streams and make results
independent of loop order. Wilson intervals and metric-specific stopping are
derived deterministically from the raw state.

The NR PUSCH runner obtains real MCS/TBS allocations, executes the transmit
waveform, applies AWGN or TDL-A/C/D in the sample domain, checks the cyclic
prefix, computes per-tone post-ZF noise variance and runs the real decoder.
The one-symbol PDSCH runner uses the corresponding comb-2 DM-RS chain. Both
retain BER/BLER/PER/CRC/convergence/EVM and conservative erasure semantics.

The Wi-Fi runner executes real SERVICE/scrambling/FEC/FCS packet paths for
HT6, VHT8, HE10 and EHT13. AWGN, TGn, TGac and TGax act on the full sample
waveform; acquisition and equalization feed per-tone reliability to soft FEC.
Acquisition failure is a counted packet erasure rather than an exception that
silently removes a trial. Small statistical tests assert identities,
reproducibility and interval validity, not an unreliable monotonic BER curve.

The lightweight deterministic testing wrappers have explicit non-normative
CPU work bounds: 131072 scalar-QAM bits, 1024 sweep points and 131072 aggregate
sweep symbols, 512 legacy Wi-Fi packets, and 16 bounded NR PDSCH packets with
at most 512 payload bits and 4096 rate-matched output bits. These are resource
guards, not radio-standard limits. Scalar QAM and its sweep have an independent
BPSK Q-function oracle. The Wi-Fi legacy-BPSK wrapper additionally has a
production-independent CPython standard-library scrambler/BCC/interleaver/
direct-DFT/AWGN/Viterbi fixture over five fixed configurations, including
three with nonzero errors. The NR PDSCH wrapper has a pinned py3gpp transmit
reference plus independently implemented scalar AWGN, comb-2 LS/ZF, QPSK-LLR
and flooding-decoder fixture for a nonzero-noise QPSK BG2 profile. Both tests
strictly parse their checked-in TSV rows and drive the public API from those
rows. They compare exact counts, an independent discrete-stage FNV transcript,
and an FNV transcript of signed big-endian Q12 values from the actual
production-path AWGN samples. The coarser Q12 trace is intentional: it is
stable across conforming transcendental-library implementations while still
detecting the fixed seed-stride and 2% noise-scale adversarial mutations. It
is a non-cryptographic regression diagnostic; generator and whole-fixture
bytes are separately locked with SHA-256 and regeneration byte comparison by
`scripts/verify_external_oracles.sh`. Production TX-to-RX round trips remain
property evidence only and are not counted as differential evidence.

The standalone artifact gate is intentionally fail-closed for NR
regeneration:

```bash
MWDSP_PY3GPP_CHECKOUT=/path/to/clean/pinned/py3gpp \
MWDSP_PY3GPP_PYTHON=/path/to/pinned/python3 \
  bash scripts/verify_external_oracles.sh
```

The checkout must be exactly commit
`17b432b30c965ffd350257ee4b1fc4de642c8e37`, clean for tracked and untracked
files, and the interpreter must provide the pinned NumPy 2.3.2 and SciPy 1.16.1
runtime. The gate makes a no-hardlink, detached local clone of the pinned
commit and disables bytecode writes before importing it, so ignored files and
cached modules in the caller's worktree cannot participate. Without that
input, receipt/schema/mutation checks and Wi-Fi regeneration still run, but
the gate returns nonzero instead of treating an unregenerated NR fixture as
success.

The WLAN LDPC table/graph corpus has a separate dual-source gate:

```bash
MWDSP_YALDPC_CHECKOUT=/path/to/clean/YALDPC-at-7ac1cd6 \
MWDSP_TAVILDAR_LDPC_CHECKOUT=/path/to/clean/LDPC-at-05ee7f4 \
  bash scripts/verify_wifi_ldpc_oracle.sh
```

Both checkouts must be clean and at the exact pinned commits. The verifier
checks generator, fixture, source and license hashes, isolates detached local
clones, regenerates twice through the pinned native C++ encoder, and requires
byte identity with the checked-in 12-profile corpus. The top-level verifier
retains this gate's nonzero status through all later tests and audits; absent
checkouts are reported as an explicit blocker, never as a pass.

## Benchmarks

The algorithm gate discovers every benchmark. A corresponding manual
warning-clean loop is:

```bash
for benchmark_file in mojo-wireless-dsp/benchmarks/*.mojo; do
  benchmark="$(basename "${benchmark_file%.mojo}")"
  nix shell .#mojo --command mojo build --Werror -I mojo-wireless-dsp \
    "$benchmark_file" -o "/tmp/${benchmark}"
  "/tmp/${benchmark}"
done
```

The benchmark families include scalar and practical Float32 DSP/MIMO,
MCS/TBS, NR LDPC and bounded channel wrappers, common Monte-Carlo primitives,
PUSCH/PDSCH AWGN and TDL cases, Wi-Fi HT6/VHT8/HE10/EHT13 packet/channel
cases, fixed DSP/MIMO/sync/BCC/LDPC, acquired fixed Wi-Fi, bounded fixed NR
PDSCH, and fixed-artifact V2 parsing/manifest validation.

Shared reporting prints compiler, target, core/SIMD and observed alignment
metadata. Timed reports require at least three warmups, nine independent
samples, a positive operations-per-sample denominator and a named denominator
unit; they emit median and nearest-rank p95. Timings are smoke baselines, not
comparative optimization claims. The strict audit, not the existence of a
benchmark filename, decides whether a public API has reachable timed evidence.

## Fixed-artifact reproducibility gate

Run the artifact gate alone with:

```bash
./mojo-wireless-dsp/scripts/verify_fixed_artifacts.sh
```

It warning-clean builds the corpus generator, writes two separate temporary
corpora, verifies the canonical file set, compares both regenerations with
each other and compares every byte with `artifacts/fixed-v2`. Parser tests also
fault-inject record headers, shapes, payloads, scale traces, FFT-stage graphs,
manifest filenames, byte counts and checksums. The exact format contract is in
[fixed-artifact-v2.md](fixed-artifact-v2.md).

## Bazel and NixOS boundary

`nix develop --command bazel-nix query '//mojo-wireless-dsp:*'` validates the
current target graph and reports its observed label count at run time. An
actual Bazel build is currently blocked before project code is compiled: the
external `rules_mojo` generic Linux tool is dynamically linked and cannot
start through the NixOS stub loader. This external-loader limitation is not an
algorithm blocker because flake-pinned direct `mojo run`, `mojo build` and
`mojo precompile` are the authoritative executable paths. Do not report the
Bazel build itself as passing until that external packaging issue is fixed.

## Source hygiene and version contracts

```bash
git diff --check -- mojo-wireless-dsp
rg -n '[ \t]+$' mojo-wireless-dsp \
  -g '*.mojo' -g '*.md' -g '*.sh' -g '*.tsv' -g 'BUILD.bazel'
```

Canonical serializers retain shape, dtype, stride/Q-format, scale, schema and
testcase identity. Checkpoint/artifact schema versions are not 3GPP Releases
or IEEE revisions; the normative algorithm baseline and exact source links are
in [standards-baseline.md](standards-baseline.md), while the complete reviewed
status matrix is in [specification-coverage.md](specification-coverage.md).
