# Architecture and API map

## Layering

```text
wireless_dsp/
  core/              Complex values, views, owned IQ/LLR buffers
  numerics/          Q formats, quantization, fixed complex math, scale plans
  dsp/               FFT/OFDM, FIR, correlation, estimation, NCO, resampling
  modem/             BPSK through 4096-QAM, hard/soft LLR, CRC
  fec/               LDPC, Polar, small-block, convolutional/Viterbi
  mimo/              1/2/4/8 matrices, QR/Cholesky/ZF/MMSE
  channel/           impairments, fading, TDL/CDL and TGn/TGac/TGax
  synchronization/   repeated-preamble detection, timing and CFO
  wireless/lte/      LTE channels, coding, physical and measurement references
  wireless/nr/       NR tables, resources, coding and bounded mini PHYs
  wireless/wifi/     legacy/HT/VHT/HE/EHT tables and bounded mini PHYs
  wireless/bluetooth/ raw Classic HEC plus bounded LE packet/coding references
  backend/cpu/       practical Float32 CPU kernels and reusable workspaces
  backend/            bit-exact fixed DSP, FEC, sync and mini PHYs
  testing/           checkpoints, fixed artifacts and CPU link simulation
```

Protocol modules own standards tables, configuration validation and resource
mapping. Complex math, transforms, estimation, equalization, channel models
and coding primitives remain reusable. Readable Float64 and integer
implementations are behavioral oracles for practical CPU paths; a faster path
must preserve the same numeric and checkpoint contracts.

## Data, numeric and simulation contracts

- `Complex[dtype]` is a value type with explicit real and imaginary scalars.
  `Span` is a lifetime-tracked contiguous view, `StridedSpan` adds a signed
  stride, and `ComplexSpan`, `SplitComplexSpan`, `MatrixView` and `BitSpan`
  cover the supported zero-copy layouts. `IQBuffer` and `LLRBuffer` own data;
  recorded alignment is metadata rather than a custom allocator guarantee.
- Floating references use Float64 for formula-oriented behavior and Float32
  for practical CPU paths. Forward FFT is unscaled and IFFT applies `1/N`.
  Square QAM uses unit average energy and MSB-first Gray labels; a positive
  LLR means bit zero.
- `QFormat` and `Fixed` make word width, fraction width, rounding and
  wrap/saturation explicit. Fixed complex MAC/FIR/correlation and FFT narrow
  only at documented boundaries. Twiddles and per-stage scale schedules are
  explicit inputs so canonical vectors do not depend on hidden `libm` state.
- Random channels require explicit seeds. Complex AWGN variance is
  `E[|n|^2]`, split equally between I and Q; normalized CFO is cycles/sample.
  Frequency-selective link receivers convert sample-domain noise to FFT-bin
  noise and then to per-tone post-ZF reliability using the estimated channel.
- `testing.monte_carlo` distinguishes data-symbol Es/N0, coded Eb/N0,
  information-bit Eb/N0 and sample SNR. It retains raw integer BER, BLER, PER,
  CRC/FCS and convergence counts plus raw EVM energies. Wilson intervals and
  RMS EVM are derived views. Semantic protocol/MCS/SNR/channel/trial/stream
  coordinates derive domain-separated seeds, making reordered sweeps and
  independently merged trial shards reproducible.

The common checkpoint schema owns version/testcase identity, dtype, shape,
stride, Q-format, scale and layout. PBCH, PDSCH, PUSCH and PUCCH format-2
transmit/receive results; Wi-Fi BCC/LDPC and acquisition results; and legacy
L-SIG transmit results carry these envelopes while retaining typed stage
fields. A schema version identifies the envelope, never a wireless-standard
revision. Canonical fixed-artifact V2 records separately bind text bytes,
record identity, shape, Q-format/scale and checksum through a strict manifest.

Ratified expansion is fail-closed before a new protocol directory or export is
created. Company implementation rights and required licensed terms are now an
explicit repository input, bound to each available artifact hash. Bluetooth
Core 6.3 has reviewed Vol 2 Part B/G raw-header HEC plus Vol 6 Part A
GFSK-limit and Part B/C packet/coded-FEC production subsets. Matter 1.6 and
Zigbee R23.2 have reviewed narrow production scopes for anonymous integer TLV
elements and the fixed unsecured unicast NWK base header. IEEE 802.15.4-2024
and Thread 1.4.1 remain blocked because their final bytes are absent. No draft,
preview or landing-page HTML can cross that boundary.

The Bluetooth namespace currently exposes five deliberately narrow CPU layers:
Classic BR/EDR raw header HEC generation/checking; LE 1M/2M uncoded packet-bit serialization and inverse verdicts; optional LE
Coded S=2/S=8 transmit-symbol construction; exact legal-codeword pattern
inversion plus a known-boundary hard-Viterbi reference receiver that stops at
the still-whitened PDU/CRC; and the complete adopted LE 1M/2M GFSK parameter
rows and compliance predicates. Composite results own every actual runtime
stage plus versioned checkpoint metadata and testcase identity. The namespace
does not own Access Code or Classic header-field validity, PDU semantics,
Access Address generation, a discrete GFSK
waveform/receiver, acquisition, dewhitening/CRC-verdict composition, Link Layer
state, encryption, CTE, scheduling, RF, or any remaining Classic/BR-EDR chain.

The Matter namespace exposes only explicit-width anonymous signed/unsigned
integer TLV element encoding and strict decoding. The Zigbee namespace exposes
only the fixed eight-octet protocol-version-two unsecured unicast NWK data
base-header codec. Both are CPU-only wire-format layers and intentionally own
no session, security, routing-policy, payload, commissioning or RF state.

## 4G LTE algorithms

The LTE layer is protocol-specific rather than an alias for NR. Its bounded
FDD, 15 kHz, normal-CP SISO profile covers all six LTE channel bandwidth
configurations; LTE Gold, 62-element PSS/SSS and ports 0--3 CRS; ordinary
PDSCH/PUSCH scrambling; direct-parameter 1--110-RB PUSCH DM-RS with complete
1/2-RB short phase tables and the 3--110-RB Zadoff--Chu branch (`v=0` for
1--5 RB and `v` in `{0,1}` for 6--110 RB); a separately scoped caller-resolved
helper covering all 30 rows of both 6- and 18-subcarrier IFDMA short tables
without inferring DCI/RRC applicability; a
normalized format-0 PRACH sequence/waveform/detector; caller-mask-driven SISO PDSCH/PUSCH
mapping; and unitary SC-FDMA transform precoding/deprecoding. The
coding layer provides CRC24A/24B/16/8, code-block segmentation with filler and
concatenation, K=7 tail-biting convolutional coding, all 188 standardized QPP
interleavers, terminated turbo constituent coding, sub-block/circular-buffer
rate matching/recovery and a readable max-log decoder. Base downlink/uplink
MCS and RV metadata, the complete traditional 0..26/26A by 1..110 TBS table,
Type-0 resource-block groups, contiguous-uplink RIV, linear
RSRP/RSSI/RSRQ/RS-SINR formulas, and the four-row TS 36.133 non-eDRX
serving-cell Nserv/filter-spacing/all-neighbour trigger arithmetic complete
the stateless procedure surface.

TS 36.101 V18.13.0 Annex B supplies exact EPA/EVA/ETU tapped profiles. TS
36.211 V18.0.2, 36.212 V18.1.0, 36.213 V18.3.0, 36.214 V18.1.0 and the
narrow 36.133 V18.14.0 clause 4.2.2.1 slice remain
separate, auditable baselines. The current boundary excludes TDD, other PRACH
formats and radio-rate occasion
mapping, hopping/OCC/DCI-derived uplink
reference-signal configuration, scheduler-selected resource reservations,
multi-layer mapping, transport-channel state, the extended current 44-row TBS
table, scheduling/HARQ, eDRX, measurement acquisition/filtering, broader RRM
state and RF/RRM conformance.

## 5G NR algorithms

The NR layer composes common FFT/OFDM, QAM, estimation, MIMO and FEC engines.
It implements PSS/SSS synchronization; Gold sequences, scrambling, DM-RS and
PTRS; resource grids; PBCH; bounded PDSCH and PUSCH chains; UCI small-block and
Polar coding; PUCCH formats 0--4 primitives and resource placement; a one-PRB
format-2 waveform chain; PRACH generation and detection; and the complete
TS 38.211 one-/two-codeword PDSCH layer partition and exact inverse for one
through eight layers. Precoding, antenna-port selection and multi-layer
channel estimation remain separate algorithms.

The TS 38.214 V18.10.0 data-procedure layer contains all four supported MCS
tables with exact rate-times-2048 values, every reserved row, PDSCH RE
accounting and the exact integer TBS algorithm, including the normative small
TBS table and large-block segmentation branch. Static py3gpp provenance and
an independently composed integer property grid pin boundary behavior. The
published baseline for 38.211--38.215 and TR 38.901 is centralized in
[standards-baseline.md](standards-baseline.md).

The control layer adds bounded non-interleaved CORESET/PDCCH resource mapping,
DCI CRC/RNTI masking, Polar/rate-matched encode/decode, scrambling and DM-RS.
TS 38.213 helpers cover CCE/search-space candidates, timing advance, an
open-loop PUSCH power expression and PUCCH resource/BWP validation. A narrow
TS 38.213 clause 10.1 plus TS 38.331 clause 6.3.2 layer validates every base
periodicity/offset/duration alternative and evaluates non-grouped monitoring
slots over an overflow-safe absolute-slot ordinal. It also decodes the base
14-bit first-symbol field and evaluates a jointly owned, validated symbol-level
occasion slice. Grouped, v1710, DCI-specific and cross-SearchSpace monitoring
behavior remains outside those closed slices. The
RA-RNTI coordinate formula is pinned separately to TS 38.321 clause 5.1.3. TS
38.215 measurement APIs evaluate caller-selected SS/CSI observations. A
bounded Rel-17 positioning layer adds DL-PRS Gold generation and complete
symbol/comb resource geometry together with UL-RTOA, DL-RSTD and UE/gNB Rx-Tx
time-difference arithmetic. It consumes already detected timestamps; RF ToA,
positioning SRS and AoA/AoD estimation remain separate gaps.

Rel-17 NTN kernels consume caller-evaluated ECEF state vectors to compute
scale-safe service-link range, RTT, radial velocity, received Doppler and
uplink frequency pre-compensation. They also evaluate the published
Common-TA/drift polynomial, validity duration and effective Koffset lower
bound. Orbit propagation, raw ephemeris decoding, discrete terrestrial
timing-advance composition, NTN HARQ/RA/RRC state and waveform synthesis
remain explicit gaps. A separate Rel-17 sidelink module closes a bounded
SCI-1A/PSCCH slice through CRC24C, Polar rate matching/SC decode, Gold
scrambling, QPSK, DM-RS and RE mapping; PSSCH, PSFCH, second-stage SCI,
resource selection and HARQ remain outside that slice.

A Rel-18 NTN enhancement slice is kept separate from the Rel-17 timing layer.
It consumes caller-decoded, nonempty 4/8-bit SSB and 8-bit type-1 DMRS
subsets to evaluate the eight `rrc-SSB-PerCG-PUSCH` mappings and the strict
latest-unfiltered L1 SS-RSRP threshold rule for a bounded FDD, `repK=1`,
single-occasion RACH-less Type-1 configured grant. ASN.1 decoding, 64-bit
subsets, type-2 DMRS, repetitions, TDD/PRACH validity, HARQ/fallback and the
complete handover state machine remain gaps. A separate Rel-18 sidelink
slice implements only uniquely determined admissibility: 15/30-kHz
overlapping-slot masks, strict-RSRP-gated half-open PSFCH/LTE-reservation
overlap and a decoded two-CC SL_n47B same-SCS/aligned-PSFCH configuration.
Random resource choice, scheduler/CBR policy, SCI decoding and complete CA or
HARQ state are intentionally not production algorithms.

A bounded Rel-17 FR2-2 configuration layer transcribes n263 120/480/960-kHz
normal-CP slot geometry, all nine declared channel-bandwidth/PRB/guardband
rows, the 3-by-3 `L_RA=139` PRACH-to-PUSCH SCS allocation table and the regular
plus exceptional NR-ARFCN rasters. It intentionally stops before waveform and
per-symbol CP timing, PRACH occasions, shared-spectrum access, PUSCH/PUCCH
processing, RRC decoding and scheduler state.

A separate bounded Rel-16 NR-U layer transcribes TS 37.213 DL/UL channel-
access priority classes and implements Type-1 defer, caller-supplied backoff,
contention-window progression/reset, nominal channel-occupancy bounds and the
UL priority-3/4 Note-2 6-to-8-ms inserted-gap decision. RF energy detection,
uniform random generation/distribution, regulation, Type-2 access, shared-COT
orchestration, discovery/DRS, RRC/DCI decoding, waveform and complete scheduler
state remain outside that slice.

Rel-17 RedCap and Rel-18 eRedCap use distinct capability types. The RedCap
layer validates FR1/FR2 capability ceilings, initial BWP/access geometry and
HD-FDD conflicts, complete clause-6.4 exact-Tc processing-time tables,
DCI/higher-layer PRACH conflict categories, guards, available-slot counting,
checked TBMS slot counts and DM-RS bundling-window
events. Separate kernels implement exact TS 38.133 V17.22.0 RLM/BFD period
tables, L1 aggregation/report intervals, the bounded 4.2B/5.1B one-/two-Rx
IDLE and INACTIVE serving-measurement tables, TS 38.304 stationary-reference
and relaxed-measurement gates, exact Annex A BWP/SSB/SMTC tables and bounded
Annex B FR1/FR2 condition expressions, and TS 38.321 decoded Msg3 applicability,
four-step/two-step FeatureCombination grouping, initial-BWP, inactivity-target
and RedCap CCCH decisions. A separate TS 38.533 layer preserves all 13 phases
of seven bounded FR1, FR2 and E-UTRA target-cell timing cases delegated from
V17.9.0 to V18.8.0. The caller first validates each published bandwidth,
duplex, power-class and frequency configuration; non-target observations stay
pending until the target responds or the strict deadline expires. This layer
is not RF, TTCN or certification execution. The
idle-access layer additionally preserves the
specified discretionary-versus-mandatory 300-second exclusions, matching-Rx
barring and SIB4 inter-frequency access without overflowing absolute time.
A separate FR1 20-MHz composition makes decoded
PSS/SSS drive PBCH/MIB, PDCCH/DCI and PDSCH, and detected normalized PRACH
drive PUSCH and PUCCH/UCI while propagating owned checkpoint identity. It is
representative cross-stage wiring across separately scoped TS/profile stages,
not a single normative end-to-end clause, contiguous radio-rate waveform or
RRC/MAC scheduler; its Feature status is therefore `PARTIAL`. These kernels do not derive the
measurement-gap/SMTC availability factor, Qout/Qin from BLER, candidate-beam
state, RF switching, ASN.1 or a complete MAC/RRC state machine.

NR LDPC contains BG1/BG2 shift tables for all supported lifting sizes,
transport-block segmentation, encoding, rate matching/recovery, layered
min-sum decode, syndrome and CRC checkpoints. NR Polar covers reliability
construction, rate matching/recovery, parity-check handling and SC decoding.
PBCH decoder input is independently pinned by a complete external py3gpp
`E=864` vector from commit
`17b432b30c965ffd350257ee4b1fc4de642c8e37`; a local encoder does not create
that oracle.

The PUSCH CPU link runner uses the true MCS/TBS allocation, waveform-domain
AWGN or TDL-A/C/D, CP-length validation, per-tone post-ZF noise variance,
transport-block decode and CRC. The bounded one-symbol PDSCH runner uses a
single-layer configuration-type-1 comb-2 DM-RS allocation with the same
MCS/TBS, AWGN/TDL, per-tone reliability and erasure accounting contracts.
Both expose deterministic trial ranges, replayable Cartesian cases, mergeable
shards, Wilson stopping, BER/BLER/PER/CRC/convergence and EVM.

The normalized PRACH composite retains allocation, root and preamble
sequences, frequency sequence, waveform, detector input, detection and owned
metadata in one result. Its test recomputes the Zadoff--Chu equation and cyclic
shift independently. Bounded PUSCH and PUCCH format-2 wrappers likewise have
separate stage-composition oracles rather than wrapper round trips, and uplink
facades exercise finite, unrepresentable-result and integer-overflow edges.

The verified NR profiles remain deliberately bounded: single codeword/layer
and continuous allocations for PDSCH/PUSCH; one PUSCH DM-RS symbol; one PRB,
one/two normal-CP symbols and a flat channel for the format-2 waveform chain;
caller-supplied format-3/4 DM-RS sequences; and representative PRACH occasion
rows. No scheduler, HARQ state machine, complete signaling procedure or
arbitrary multi-layer/multi-codeword modem is claimed.

## Wi-Fi algorithms

The Wi-Fi layer includes a complete declared 20-MHz SISO Clause-17 and
ERP-OFDM baseband reference across all eight rates. It builds and receives
the preamble, L-SIG and DATA fields through BCC, puncturing, interleaving,
QAM, pilots, 64-IFFT/FFT, GI and real FCS; its synchronized/known-timing
boundary excludes CCA and acquisition. Exact DSSS Barker and CCK chip-symbol
cores are separate bounded profiles. Profile and resource tables then cover
HT, VHT, HE and EHT. The representative 20 MHz, one-spatial-stream profiles
are HT MCS 6 with 64-QAM BCC, VHT MCS 8 with 256-QAM BCC, HE MCS 10 RU-242
with 1024-QAM WLAN LDPC, and EHT MCS 13 RU-242 with 4096-QAM WLAN LDPC. They
retain LTF estimation, equalization, pilot phase/slope correction, SERVICE,
soft FEC and FCS checkpoints.

The HT/VHT acquired chain joins L-STF detection, coarse CFO, profile-LTF fine
timing/CFO, legacy L-SIG validation, FFT/LS estimation, pilot correction,
deinterleaving/depuncturing, soft Viterbi, SERVICE and FCS. The HE/EHT acquired
chain joins L-STF, representative L-LTF, validated L-SIG, one 4x LTF,
fine timing/CFO, per-tone LS, iterative LDPC, SERVICE and FCS. Independent
manual receive fixtures construct VHT MCS 8 and EHT MCS 13 packets without
calling the transmit wrapper, preventing a wrapper round trip from serving as
the differential oracle.

The adjacent SIGNAL-field layer serializes and validates Clause 19 HT-SIG,
the ordinary SU forms of Clause 21 VHT-SIG-A/B, HE-SIG-A, U-SIG and bounded
EHT-SIG Common/User envelopes. A separate 20-MHz one-stream waveform slice
closes BCC, the 13-by-4 SIGNAL interleaver, pilots, 64-IFFT/FFT, HE ER-SU
repetition/QBPSK and EHT-SIG PAPR phase rules for HE-SIG-A, U-SIG and one
42-bit EHT SU Common block. Its receivers derive the DATA family, MCS and
coding before invoking the existing RU-242 LDPC DATA receiver. HT/VHT field
geometry covers contiguous 20/40/80/160 MHz where applicable, while complete
PPDU assembly, MU/TB, arbitrary EHT-SIG content/padding, 80+80 and wider-band
waveforms remain explicit Feature gaps.

A bounded spatial layer implements the single-FEC-encoder, equal-modulation
HT/VHT/HE stream parser and exact inverse for one through four streams. It
also imports the one-through-four-STS cyclic-shift tables and applies them to
ordered tones through direct `Q=I`, `N_TX=N_STS` mapping. Multiple encoders,
unequal modulation, five through eight STS, STBC, arbitrary or beamformed
matrices, sounding, channel estimation and full MU-MIMO remain explicit.

A separate EHT wideband table layer owns contiguous 20/40/80/160/320-MHz
geometry, all 45 assigned non-OFDMA U-SIG puncturing rows with legal inverse
and primary-20 validation, and all 72 published large-MRU component/index
rows. These are discrete CPU table algorithms, not physical tone-coordinate
maps or punctured waveforms; small/regular RU maps, EHT-SIG allocation
encoding, scheduling, acquisition and interoperability remain incomplete.

The CPU Wi-Fi packet runner executes those actual acquisition and decode
paths for HT6/VHT8/HE10/EHT13 over AWGN, TGn, TGac and TGax sample-domain
channels. It measures exact pre-channel waveform energy, supplies per-tone
post-ZF LLR reliability, treats acquisition exceptions as explicitly counted
erasures, and reports BER/PER/FCS/convergence/EVM with semantic replay,
sharding and Wilson stopping.

The deterministic MAC arithmetic layer is intentionally state-minimal: it
implements DCF/EDCA AIFS and backoff/retry transitions, NAV end/remaining
time, Sequence Control and modulo-4096 Block-Ack window decisions, plus basic
A-MSDU/A-MPDU size and offset plans. It does not substitute commercial
scheduling policy or claim complete MAC behavior. A bounded base
fragmentation/reassembly layer and strict non-DMG MPDU-delimiter CRC,
serialization and parsing sit beside these planners; address/TID grouping,
duplicate suppression and aggregate resynchronization remain independent
Feature gaps. A bounded legacy power-save state layer adds canonical
single-BSSID non-S1G Method-A TIM construction/AID lookup, DTIM progression,
ListenInterval/ReceiveDTIMs TBTT selection and PS-Poll Duration/ID decisions.
APSD, TWT, TIM Broadcast, WNM sleep and IBSS/PBSS are still absent. A bounded
EHT MLO layer implements TID-to-link wire/state transitions, mapped-link union
projection, EML timing tables and full-UInt64 TSF/TU field arithmetic for
caller-supplied established setup/active-link state; frame-context parsing,
negotiation, full setup/reconfiguration, activation/expiry, power-save,
NSTR/STR, cross-link Block Ack and security procedures remain absent.
Bounded HE dual-NAV/TXOP-duration and Trigger User/RU arithmetic are
implemented without claiming a complete HE MAC state machine.

A separate S1G configuration layer records all five Clause-23 bandwidth
numerologies, exhaustive occupied-tone intervals, the valid one-stream MCS
cells and bounded BCC SU long-GI geometry.  It intentionally stops before
SIG/preamble, FEC, waveform and receive processing.  The FTM arithmetic layer
keeps caller-unwrapped/calibrated integer-picosecond t1/t2/t3/t4 timestamps,
performs the exact round-trip subtraction before floating conversion, applies
an explicit clock-rate ratio and returns propagation delay/range.  Frame and
session state, timestamp acquisition/calibration, secure HE/EDMG ranging and
multi-range position estimation remain independent Feature gaps.

A bounded Clause-20 DMG reference layer provides the six published Ga/Gb
Golay sequences, exact noiseless pi/2-BPSK chip mapping/inversion, the complete
control STF and integer complementary-correlation checks.  CEF, complete
control/SC/OFDM PPDU chains, FEC, acquisition, equalization and beam-training
state remain separate Feature gaps.

A distinct Clause-28 EDMG layer owns the four published contiguous 1--4
channel integer OFDM geometry rows, all 26 legal channel-center rows, exact
GI sample counts and strict finite natural-DFT occupied-grid pack/unpack with
three zero DC tones and zero guards. It does not reuse the legacy DMG Golay
evidence, and it does not claim pilot/data tone-index tables, DC relative
shift, channel aggregation, EDMG STF/CEF, Control/SC/complete OFDM PPDUs,
LDPC, TRN, beamforming/MIMO or receive processing.

A bounded WUR reference layer implements the adopted one-channel, one-chain
LDR/HDR MC-OOK example: exact active-tone and symbol geometry, the complete
seven-bit randomizer period and cyclic-shift tables, direct-IDFT On symbols,
exact Off symbols and modulation of caller-supplied already encoded decisions.
The adopted comment resolution explicitly leaves actual WUR-Sync/WUR-Data
waveform generation implementation-dependent, so this layer is a reproducible
CPU reference rather than a unique mandatory transmitter. Manchester and
repetition coding, WUR-Sync contents, MAC/FCS fields, full PPDU serialization,
windowing, the adopted whole-PPDU correlation-test verdict, detection and
receive processing remain Feature gaps.

A bounded TVHT table layer owns the exact 6/7/8 MHz basic-channel-unit and
MODE_1/2C/2N/4C/4N channel relationships, occupied and pilot tones, SIG-A
bandwidth bits, MCS/interleaver/tone-mapping parameters and data-symbol-driven
field timing. Regulatory database permission, SIGNAL serialization, FEC and
complete PPDU waveforms or receivers remain separate Feature gaps.

The bounded IEEE 802.11bh layer accepts caller-supplied bytes and owns exact
Device ID, IRM and PASN ID base payload directionality, complete defined
Identifier Status and IRM Action rows, local-individual address validation and
the explicit Recognized/Not Recognized Address-2 shared-identity result. It
does not generate or assess random addresses, perform AES-SIV/key handling,
construct opaque identifiers, distribute ESS identity, or implement complete
authentication, association, PASN, fast-transition or roaming state.

The EBCS layer is deliberately narrower still: it serializes and parses only
the conflict-free EBCS TIM Content-ID-list Mode 1 when a distinct 2--31-ID
list is strictly shorter than its minimal bitmap span, provides exact
membership, and advances a fixed-period DTIM countdown. Mode 0 and equal-size
selection remain excluded because the adopted Length requirements conflict;
frame carriage, EBCS exchanges, security, buffering policy and scheduling
state remain gaps.

All twelve WLAN LDPC matrices (648/1296/1944 and rates 1/2, 2/3, 3/4, 5/6)
support patterned construction, systematic encoding, syndrome checks,
min-sum decoding and shortening/puncturing/repetition. The acquired profiles
remain bounded to one 20 MHz stream and one DATA symbol; complete SIGNAL-field
state machines beyond the bounded HT/SU-VHT fields, packet extensions,
wideband waveform operation, MU-MIMO/OFDMA,
DCM/STBC/MRU and OTA interoperability are not claimed.

## Channel and practical CPU algorithms

The Rel-17 feMIMO table layer accepts already decoded Type-II port-selection
configuration and owns the exact parameter-combination/RI table, combinadic
vector-selection inverse and strongest/nonzero coefficient index arithmetic.
CSI estimation and packing, precoding matrices, beam state, multi-TRP
orchestration and waveforms remain outside that bounded layer.

Channel models include seeded AWGN/CFO and RF impairments, Rayleigh/Rician and
Doppler fading, fractional delays, 3GPP TDL A--E, CDL A--E, Wi-Fi TGn A--F and
TGac/TGax interpolation. CDL includes the 20-ray offsets/couplings, XPR,
polarization, seeded phases, LOS/K factor, Doppler and ULA/UPA responses; it is
a far-field isotropic-element model, not a measured antenna or near-field
model.

The practical Float32 CPU layer provides reusable radix-2 FFT plans,
in/out-of-place and batched FFT/IFFT; workspace-controlled CP-OFDM for sizes
64--4096; real FIR and split-IQ correlation; QAM LLRs through 4096-QAM;
scale-safe SISO division, LS, ZF/MMSE, pilot-noise and CPE; and reusable
2x2/4x4 MIMO matrix-vector, Gram, matched-filter, ZF and MMSE workspaces.
FIR/correlation and the sum/dot/energy kernels use native-width SIMD; other
kernels make no SIMD-specialization claim. Float32 results are compared with
Float64/analytic oracles at ordinary and extreme finite scales. Static NumPy
2.3.2 inverse/QR/Cholesky/ZF/MMSE vectors are checked without a runtime Python
dependency.

`wireless_dsp.benchmarking` centralizes compiler/target/core/SIMD metadata,
observed alignment, warmups, independent timing samples, median,
nearest-rank p95 and named normalized denominators. The evidence audit follows
each benchmark entry point to the named public API; merely mentioning an API
in a benchmark file is not completion evidence.

## Fixed-point algorithms and artifacts

The fixed layer supplies bit-exact arithmetic, dot/FIR/correlation, radix-2
FFT scale schedules, a QPSK-OFDM/flat-channel/LS/ZF chain, 2x2
normal-equation ZF, repetition synchronization, K=7 rate-1/2 BCC and hard/soft
Viterbi. Its legacy Wi-Fi DATA profile adds 64-point OFDM/CP16, 48 data and
four pilot tones, IEEE interleaving, SERVICE, CRC-32 FCS, tail/pad handling,
L-LTF flat LS/ZF and variable payload recovery.

The connected fixed Wi-Fi acquisition reference prepends a standard periodic
L-STF, scans it with integer repetition correlation, and uses the detected
boundary—not the configured transmit delay—to slice the actual L-LTF and DATA
observations. Those slices drive fixed LS, ZF, QPSK LLR, deinterleaving, soft
Viterbi, descrambling and FCS. Its scope is legacy 20 MHz QPSK rate-1/2 BCC,
a flat channel, bounded integer timing and zero CFO/noise; it has no L-SIG.

The bounded fixed NR PDSCH reference is mu=0, 512-point FFT/CP36,
single-layer QPSK, a contiguous 480-RE allocation and comb-2 DM-RS. Gold
scrambling, grid mapping, IFFT/CP, two/three-tap causal FIR, FFT, per-pilot LS,
interpolation, per-tone ZF and coordinate LLRs are integer. The receive path
then narrows into the registered Q10.6 LDPC domain, performs fixed NR rate
recovery, layered BG2 min-sum, transport-block recovery and CRC without a
floating decision boundary. Parallel Float64 arrays are diagnostics only and
never select payload or status. Generic fixed flooding/layered min-sum and
BG1/BG2 rate-recovery/decode APIs provide the reusable FEC layer.

Fixed-artifact V2 serialization is an executable contract rather than a text
dump. The strict parser validates scalar, complex, ScaleTrace and complete FFT
trace records; the manifest binds safe filenames, schemas, byte counts,
checksums and record identities. The checked-in corpus is regenerated twice
and each byte is compared both between runs and against version control. These
are golden algorithm/RTL-interface vectors, not a claim of synthesized RTL or
hardware equivalence.
