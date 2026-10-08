# mojo-wireless-dsp

`mojo-wireless-dsp` is a Mojo-first wireless PHY/DSP foundation library. For
the declared CPU, floating-reference, fixed-point, 4G LTE, 5G NR and Wi-Fi
profiles, the current checkout meets the scoped algorithm gates across
Phases 0--7. This
is an algorithm/reference milestone, not a claim of a complete 3GPP or IEEE
protocol stack, commercial modem, or OTA conformance. The repository root
`flake.nix` is the authoritative Mojo environment; the pinned compiler is
`1.1.0.dev2026081813`.

The integrated verification is additionally fail-closed on ratified
authority.  Matrix statuses describe implementation-evidence maturity only;
they never grant production permission.  Its 17-column authority manifest
requires an exact formal specification/version, status/date, official artifact
SHA-256, clause scope and reviewed errata state before any maturity row is
production-eligible. Company implementation rights and the required licensed
terms are explicitly confirmed. The reviewed default attestation binds each
available licensed artifact by authority ID and SHA-256; changing an artifact
still requires a new exact binding. Bluetooth Core 6.3 now implements only its
reviewed Vol 2 Part B/G Classic raw-header HEC, Vol 6 Part A GFSK parameter
limits and Part B/C LE uncoded packet, LE Coded transmit-symbol, exact
pattern-inverse and hard-FEC reference-receive clause subsets. Matter 1.6 and
Zigbee R23.2 now have byte-pinned production authorities and deliberately
narrow TLV-integer and NWK-header implementations. Final IEEE 802.11/802.15.4 and Thread
1.4.1 bytes are not present on this host, so those records also remain
`BLOCKED_METADATA` despite the resolved rights. WG contributions, drafts,
previews and landing-page HTML are never substituted for final artifacts.

The newer specification/Feature program is intentionally stricter than those
phase gates. Its 21-column matrix keeps every declared published
CPU-implementable 4G LTE, 5G NR and Wi-Fi gap visible as `PARTIAL` or
`MISSING`, and separately records the narrow Bluetooth, Matter and Zigbee
implementations plus the blocked IEEE 802.15.4 and Thread families. Passing the public API ledger therefore
does not imply that any complete standard or upper-layer stack is finished.
The required NR side includes approved Work Items for NTN, sidelink,
positioning, NR-U, MBS, enhanced MIMO/multi-TRP, coverage enhancement,
LP-WUS, Ambient IoT and FR2-2. Each feature-specific row remains `PARTIAL` or
`MISSING` until its own declared profile and evidence exist; common
terrestrial NR primitives do not satisfy it.

The implemented scope includes:

- protocol-independent complex arithmetic, zero-copy views and owned IQ
  storage; FFT/OFDM, FIR, correlation, resampling and synchronization; channel
  estimation, QAM/LLR and CRC; small-matrix MIMO; LDPC, Polar,
  convolutional coding and Viterbi;
- readable Float64 references plus practical Float32 CPU FFT/OFDM, SISO,
  pilot/CPE, FIR/correlation, QAM-LLR and 2x2/4x4 MIMO kernels, with analytic,
  seeded and static NumPy differential evidence;
- Bluetooth Core 6.3 Classic BR/EDR raw ten-bit header HEC generation and
  zero-remainder checking over caller-selected UAP/DCI, with all 20 Part-G
  examples and the complete 1024-by-256 input domain; LE 1M/2M uncoded packet-bit preamble, caller-owned Access
  Address/PDU serialization, CRC-24, all-channel whitening and strict inverse
  verdicts for the exact 2--258-octet domain; plus the optional LE Coded
  S=2/S=8 capability's transmit symbols for the exact 2--257-octet domain,
  reusing the common K=4
  convolutional encoder with the adopted CI, TERM and pattern-mapper rules;
  exact legal-codeword pattern inversion and known-boundary hard-Viterbi
  reference decoding retain 16 owned stages and stop at whitened PDU/CRC;
  complete LE 1M/2M Part-A GFSK parameter rows and compliance predicates are
  also closed, while discrete GFSK waveform/RX, acquisition, dewhitening/CRC
  verdict composition, Link Layer procedures, encryption, CTE, scheduling,
  RF and all remaining Classic/BR-EDR behavior remain separate gaps;
- Matter 1.6 Appendix-A anonymous signed and unsigned integer TLV elements
  with explicit 1/2/4/8-octet widths, exact little-endian two's-complement
  encoding and strict single-element decoding; tags, containers, schemas and
  interaction/session/security/commissioning behavior remain separate gaps;
- Zigbee R23.2 fixed eight-octet protocol-version-two unsecured unicast NWK
  data base headers with canonical transmit flags and strict receive parsing;
  security, source routing, broadcast, APS/ZDO, route policy and payload state
  remain outside this slice;
- seeded AWGN and impairments, fading, 3GPP TDL/CDL A--E and Wi-Fi
  TGn/TGac/TGax channels, plus a common CPU Monte-Carlo contract for explicit
  SNR meanings, raw BER/BLER/PER/CRC/FCS/convergence counters, EVM, Wilson
  intervals, stopping policies, semantic seeds, exact replay and shard merge;
- 4G LTE frozen Release-18 algorithm references for EPA/EVA/ETU channels, FDD
  normal-CP resources, LTE Gold/PSS/SSS/CRS, PDSCH/PUSCH scrambling and
  caller-mask-driven SISO mapping, direct-parameter 1--110-RB PUSCH DM-RS with
  complete 1/2-RB short phase tables (`v=0` for 1--5 RB and `v` in `{0,1}`
  for 6--110 RB), plus a separate caller-resolved exact-length helper for all
  30 rows of the 6- and 18-subcarrier IFDMA Tables 5.5.1.2-3/-4; the
  integer-RB API still excludes those distinct tables; normalized
  format-0 PRACH and SC-FDMA; QPP/turbo and tail-biting convolutional coding
  with code-block segmentation and rate matching; bounded MCS/RV, complete
  traditional/base TBS and resource-allocation procedures;
  RSRP/RSSI/RSRQ/RS-SINR measurements; and the TS 36.133 V18.14.0
  non-eDRX serving-cell Nserv, filter-spacing and all-neighbour trigger slice;
- 5G NR synchronization, grid/OFDM, PBCH, PDSCH, PUSCH, PRACH and PUCCH; UCI,
  PDCCH/DCI, DM-RS/PTRS, NR LDPC, Polar and small-block coding; bounded
  TS 38.213 procedures, including the complete decoded non-grouped base
  SearchSpace monitoring-slot arithmetic, the TS 38.331 14-bit first-symbol
  projection and jointly owned TS 38.213/38.331 symbol-level occasion
  membership, and TS 38.215 measurements; the four TS 38.214 V18.10.0
  MCS tables, exact integer TBS algorithm and complete one-/two-codeword
  PDSCH layer mapping for one through eight layers; Rel-17 DL-PRS sequence/resource
  mapping and normative RTOA/RSTD/Rx-Tx timing arithmetic; Rel-17 NTN
  service-link timing/Doppler/Common-TA/Koffset arithmetic and bounded Rel-18
  RACH-less-handover Type-1 CG ordering over nonempty decoded 4/8-bit SSB and
  8-bit type-1 DMRS subsets plus strict RSRP thresholding; bounded Rel-17
  sidelink SCI-1A and PSCCH coding, scrambling, DM-RS and RE mapping; bounded
  Rel-18 sidelink slot/PSFCH-overlap/two-CC n47 admissibility without random
  selection or scheduler policy; a normalized PRACH
  allocation-to-Zadoff--Chu-to-waveform-to-detection composite; and real CPU
  PUSCH/PDSCH link trials over AWGN and TDL-A/C/D with per-tone reliability;
  bounded Rel-17 MBS CFR/DCI/MCCH/NACK-only-PUCCH/SPS arithmetic and coverage-
  enhancement PUSCH allocation, Msg3 repetition, TBMS slot and nominal-TDW
  decisions; bounded Rel-16 NR-U DL/UL CAPC, Type-1 defer/backoff/CW, nominal
  COT and UL Note-2 gap-extension arithmetic; bounded Rel-17 FR2-2 n263
  numerology, carrier/guardband,
  `L_RA=139` PRACH allocation and NR-ARFCN raster tables, with all three wider
  Feature procedures retained as `PARTIAL`;
  plus separate Rel-17 RedCap capability, initial-BWP/access, IFRI and
  matching-Rx/HD barring with checked exclusion timers, HD-FDD conflict,
  available-slot/DM-RS-window, RLM/beam-failure, exhaustive bounded
  IDLE/INACTIVE serving-measurement tables, exact Annex BWP/SSB/SMTC and
  published condition tables, bounded TS 38.533 FR1/FR2/inter-RAT
  target-cell deadline verdicts for 13 delegated phases after caller-side
  case-configuration validation, stationary relaxation and decoded
  TS 38.321 Msg3/RA FeatureCombination/BWP/CCCH decisions; an explicit FR1
  20-MHz representative chain composes synchronization through DL-SCH and
  normalized PRACH through UL-SCH/UCI as `PARTIAL` cross-stage wiring across
  separately scoped profiles, without claiming one normative end-to-end clause
  or a contiguous RF stack;
- bounded Rel-17 further-enhanced Type-II port-selection tables, RI masks,
  combinadic vector selection and coefficient index/priority/count arithmetic,
  without claiming complete CSI reports, precoding or multi-TRP scheduling;
- complete declared 20 MHz SISO Clause-17/ERP-OFDM baseband TX/RX across all
  eight legacy rates, plus bounded aligned Clause-15/16 DSSS/CCK long/short
  PLCP/PPDU TX/RX through MPDU FCS at 1, 2, 5.5 and 11 Mb/s,
  and representative single-stream 20 MHz HT MCS 6, VHT MCS 8,
  HE MCS 10 RU-242 and EHT MCS 13 RU-242 chains, all twelve WLAN LDPC
  matrices, bounded HT-SIG and SU VHT-SIG-A/B field/CRC geometry, and bounded
  20-MHz one-stream HE-SIG-A/U-SIG/EHT-SIG waveform slices whose decoded
  SIGNAL profiles drive RU-242 LDPC DATA receive; bounded 1--4-stream
  HT/VHT/HE parsing, exact cyclic shifts and direct identity spatial mapping;
  exact bounded TVHT 6/7/8-MHz BCU channel plans, occupied/pilot tones,
  SIG-A bandwidth bits, 600 mode-expanded one-to-four-stream configurations
  over 120 normative MCS rows, and data-symbol-driven PPDU timing without a
  waveform claim;
  exact discrete EHT 20--320-MHz geometry, all assigned non-OFDMA puncturing
  rows and the published large-MRU component/index tables; acquisition, pilot tracking,
  SERVICE/FCS and soft FEC; independent
  hand-composed VHT MCS 8 and EHT MCS 13 receive fixtures; and real CPU packet
  sweeps over AWGN, TGn, TGac and TGax with per-tone post-ZF LLR weighting;
  deterministic DCF/EDCA timing, backoff/retry, NAV, sequence/Block-Ack window
  and basic A-MSDU/A-MPDU planning arithmetic; plus bounded base
  fragmentation/reassembly and exact non-DMG MPDU-delimiter CRC,
  serialization and strict parsing; plus bounded HE dual-NAV, TXOP_DURATION
  and Trigger User/RU allocation arithmetic, canonical Method-A TIM/DTIM,
  ListenInterval/ReceiveDTIMs and legacy PS-Poll state; bounded EHT MLO
  TID-to-link mapping state, EML timing-table decoding and TSF/TU arithmetic;
  bounded IEEE 802.11bh Device ID, IRM and PASN ID base fields, complete
  status/action tables and explicit shared-identity status transitions, without
  claiming random generation, cryptography or a complete roaming state machine;
  bounded Clause-20 DMG Ga/Gb Golay tables, exact pi/2-BPSK chip mapping and
  the complete 6400-chip control STF; bounded Clause-28 EDMG contiguous-channel
  integer geometry and strict occupied-grid mapping; bounded EBCS TIM Mode-1
  elements and fixed-period countdown; plus the adopted single-channel WUR
  LDR/HDR MC-OOK reference/example geometry, symbol randomizer and pre-window
  On/Off modulation without claiming a mandatory interoperable waveform or
  whole-PPDU correlation-test compliance;
  exact S1G 1/2/4/8/16-MHz numerology, occupied-tone and one-stream MCS
  configuration/TXTIME arithmetic; and bounded FTM t1/t2/t3/t4 clock-rate,
  propagation-delay and range calculations over caller-calibrated timestamps;
- explicit Q-format arithmetic, quantization, complex MAC/FIR/dot, per-stage
  FFT scaling, 2x2 ZF MIMO, repetition synchronization, integer BCC/Viterbi,
  fixed mini-PHYs and canonical raw checkpoints; the bounded fixed NR PDSCH
  receive path remains integer through rate recovery, BG2 layered min-sum LDPC
  and CRC, while its Float64 decode is audit-only and cannot select output;
- a bounded acquired fixed legacy Wi-Fi chain in which the detected STF
  boundary drives the actual LTF/DATA slices through integer LS, ZF, LLR,
  Viterbi and FCS; and a strict fixed-artifact V2 parser, checked-in
  scalar/complex/scale/FFT corpus, manifest validation and byte-for-byte
  two-pass regeneration gate.

The bounded profiles are intentionally smaller than complete standards
procedures. They do not implement a complete MAC/RLC/PDCP/RRC stack, complete PPDU signaling,
arbitrary LTE/NR scheduling and resource combinations, wideband MU-MIMO/OFDMA,
every legal impairment/configuration, synthesized RTL, or OTA certification.
Performance specialization is also not required for algorithm completion. See
[all-phases-status.md](docs/all-phases-status.md) for the precise boundaries and
[standards-baseline.md](docs/standards-baseline.md) for the normative version
contract. The reviewed published/draft/out-of-scope matrix is in
[specification-coverage.md](docs/specification-coverage.md).

## Reproduce the algorithm validation

From the repository root, run the authoritative algorithm gate:

```bash
./mojo-wireless-dsp/scripts/verify_algorithms.sh
```

It enters the pinned flake itself, audits BUILD source registration,
SHA-locks the frozen Wi-Fi/NR external-oracle generators and fixtures and
byte-regenerates them (requiring the clean pinned py3gpp checkout), separately
regenerates the complete dual-source WLAN LDPC matrix/graph/codeword corpus
from clean pinned YALDPC and tavildar checkouts, precompiles
the public package, builds and runs the in-scope warning-clean
tests, benchmarks and examples, runs the strict public evidence audit, runs
the complete communication-protocol Specification and Feature matrices in
strict completion mode, joins implementation-maturity claims to the separate
ratified-authority eligibility manifest, validates the pinned manifest trust
receipt and re-fetches accessible production artifacts to verify their actual
SHA-256 and file magic, verifies the fixed-artifact V2 corpus by two separate
exact regenerations, audits source
hygiene, and queries the Bazel target graph. Counts and artifact sizes are
reported at run time rather than copied into documentation.

Individual checks still use the root flake:

```bash
nix shell .#mojo --command mojo run -I mojo-wireless-dsp \
  mojo-wireless-dsp/tests/nr_mcs_tbs_test.mojo
nix shell .#mojo --command mojo run -I mojo-wireless-dsp \
  mojo-wireless-dsp/tests/nr_monte_carlo_test.mojo
nix shell .#mojo --command mojo run -I mojo-wireless-dsp \
  mojo-wireless-dsp/tests/wifi_monte_carlo_test.mojo
nix shell .#mojo --command mojo precompile --Werror -I mojo-wireless-dsp \
  mojo-wireless-dsp/wireless_dsp -o /tmp/wireless_dsp.mojoc
```

The exact gate contents, direct audit commands and the external Bazel-loader
limitation are recorded in [verification.md](docs/verification.md).
Architecture and public API boundaries are described in
[architecture.md](docs/architecture.md); the original capability study remains
in [phase0-design.md](docs/phase0-design.md).
