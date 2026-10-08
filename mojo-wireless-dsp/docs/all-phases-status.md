# All-phase scoped algorithm status

All Phases 0--7 meet their scoped algorithm gates for the CPU,
floating-reference, fixed-point, 4G LTE, 5G NR and Wi-Fi profiles declared below.
These statuses do not mean a complete standards stack, commercial modem,
OTA certification or RTL implementation. The authoritative scope here is the
legacy phase-gated CPU algorithm surface. The broader formal
specification/Feature matrix is intentionally not complete and must be read
separately; its `PARTIAL` and `MISSING` rows are not overridden by this table.
Company implementation rights and required licensed terms are confirmed.
Bluetooth Core 6.3 has a pinned artifact-bound attestation and deliberately
narrow reviewed Classic raw-header HEC, LE 1M/2M uncoded packet-bit, optional
LE Coded transmit and hard-FEC reference-receive, and Part-A GFSK
parameter-limit implementations.
Matter 1.6 and
Zigbee R23.2 now have equally narrow production-qualified TLV-integer and
unsecured-NWK-header slices. IEEE 802.15.4 and Thread remain
`BLOCKED_METADATA` because their final bytes are absent. Draft or candidate
content remains excluded.

| Phase | Status | Executable evidence and boundary |
| --- | --- | --- |
| 0 | Scoped algorithm gate met | The root flake pins Mojo `1.1.0.dev2026081813`; package import/precompile, origin-tracked views, generic value parameters, SIMD probes, benchmark contracts and BUILD source registration are executable. |
| 1 | Scoped algorithm gate met | Complex values, zero-copy complex/split-IQ/matrix/bit views, owned IQ/LLR buffers, explicit `Fixed`/`QFormat`, rounding and overflow policies, scale traces and owned checkpoint metadata are implemented. The V2 fixed-artifact schema has strict record/manifest parsing and deterministic checked-in corpus regeneration. Recorded buffer alignment remains metadata rather than a custom aligned allocator. |
| 2 | Scoped algorithm gate met | Float64 reference FFT/IFFT through 4096, OFDM, FIR, correlation, windows/NCO/resampling, BPSK--4096-QAM, exact/max-log LLR, CRC, impairments and seeded channel models are covered. Practical Float32 CPU plans/workspaces cover FFT, CP-OFDM, FIR/correlation, SISO estimation/equalization/pilots/CPE, QAM LLR and 2x2/4x4 MIMO. Phase-wide performance specialization is not an algorithm-completion criterion. |
| 3 | Scoped algorithm gate met | 1/2/4/8 complex matrices, inverse/QR/Cholesky/ZF/MMSE, reusable LDPC, NR LDPC/Polar/small-block and convolutional/Viterbi algorithms have deterministic, edge, property and independent evidence. Static NumPy 2.3.2 vectors pin 2x2/4x4 MIMO and scale-relative decomposition boundaries without a runtime Python dependency. |
| 4 | Scoped algorithm gate met | Legacy Wi-Fi plus bounded 20 MHz one-stream HT6/VHT8 BCC and HE10/EHT13 RU-242 LDPC paths include acquisition, channel estimation, pilot correction, SERVICE, soft FEC and FCS. HT/SU-VHT SIGNAL fields, bounded HE/EHT SIGNAL waveforms, single-encoder one-through-four-stream parsing/CSD/direct identity mapping, exact TVHT table/arithmetic, exact discrete EHT 20--320-MHz geometry, assigned non-OFDMA puncturing and large-MRU tables, an adopted single-channel WUR LDR/HDR reference/example, and bounded 802.11bh identity fields/status transitions are executable. S1G and FTM arithmetic, independent VHT/EHT fixtures, CPU AWGN/TGn/TGac/TGax trials, deterministic base/HE MAC and bounded EHT MLO state remain covered. Complete TVHT and wideband waveforms, small/regular MRU, arbitrary MIMO/STBC/beamforming, full OFDMA/MU/TB/NDP, complete WUR coding/PPDU/MAC/RX and whole-PPDU correlation-test verdict, random-address generation/cryptography/full roaming state, S1G/positioning PPDUs, remaining MAC/MLO state and OTA interoperability remain formal Feature gaps. |
| 5 | Scoped algorithm gate met | NR synchronization, PBCH/PDSCH/PUSCH, PRACH, PUCCH, UCI, PDCCH/DCI, grid/OFDM, reference signals and channel coding are implemented for declared bounded profiles, including exact 1--8-layer PDSCH codeword mapping. TS 38.213/38.331 stateless control helpers include narrow complete decoded non-grouped monitoring-slot, 14-bit first-symbol and jointly owned symbol-level occasion slices; TS 38.214 MCS/TBS, TS 38.215 measurements, bounded Rel-16 NR-U Type-1 channel-access arithmetic, Rel-17 DL-PRS/timestamp positioning, NTN timing/Doppler, SCI-1A/PSCCH sidelink, MBS finite procedures, coverage-enhancement PUSCH/TBMS/TDW and FR2-2 n263 configuration/raster slices are executable. Rel-17 RedCap adds bounded capability/access, complete declared-profile HD-FDD conflict and Tproc2 decisions, RLM/BFD, serving-measurement and Annex table subsets, stationary relaxation, corrected FeatureCombination MAC decisions, 13 bounded TS 38.533 conformance phases and a `PARTIAL` FR1 20-MHz DL/UL representative composition across separately scoped stages; it is not a normative end-to-end procedure and remains distinct from Rel-18 eRedCap. PUSCH and one-symbol PDSCH CPU trials use true MCS/TBS, waveform-domain AWGN or TDL-A/C/D, CP constraints and per-tone reliability. Full scheduling/HARQ/RRM/random-access state, grouped/v1710/DCI-specific/cross-SearchSpace PDCCH monitoring, NR-U RF sensing/Type-2/shared-COT state, remaining TS 38.533 cases, complete MBS/coverage-enhancement/FR2-2 chains, positioning SRS/estimators, NTN orbit/waveform state, sidelink PSSCH/PSFCH/resource selection, precoding/ports and general multi-layer channel processing remain formal Feature gaps. |
| 6 | Scoped algorithm gate met | The common CPU Monte-Carlo layer defines Es/N0 and coded/information Eb/N0 conversions, complex sample N0, raw BER/BLER/PER/CRC/FCS/convergence counters, EVM, Wilson intervals, stopping rules, semantic seed derivation, exact replay, Cartesian sweeps and mergeable trial shards. Real PUSCH, PDSCH and Wi-Fi packet chains consume this contract rather than an uncoded link abstraction. Short statistical tests validate identities and accounting; they do not assert noisy monotonic curves from too few samples. |
| 7 | Scoped algorithm gate met | Bit-exact fixed DSP, FFT scale schedules, 2x2 ZF, repetition sync, BCC/Viterbi and fixed mini-PHYs are implemented. Generic fixed flooding/layered min-sum plus NR BG1/BG2 rate recovery/decode feed the bounded fixed PDSCH, whose production receive path remains integer through LDPC and CRC. A fixed legacy Wi-Fi acquisition chain makes the detected STF boundary drive actual LTF/DATA LS/ZF/LLR/Viterbi/FCS processing. Strict V2 artifacts, manifest validation and two-pass byte regeneration close the algorithm/vector interface; generalized fixed modems, synthesized RTL and hardware equivalence are not claimed. |

Phase 4 additionally tracks bounded, still-`PARTIAL` Clause-28 EDMG integer
OFDM geometry/grid mapping and EBCS TIM Mode-1/fixed-countdown slices. Their
complete PPDU/MAC procedures remain gaps. Phase 5 additionally tracks the
bounded Rel-18 NTN nonempty-resource RACH-less configured-grant mapping and
strict-RSRP decision, plus Rel-18 sidelink uniquely determined slot/overlap/
two-CC n47 admissibility. ASN.1, random selection and complete mobility,
scheduler, CA and HARQ state remain explicit gaps.

## Standards-oriented profile coverage

The NR phase also contains an exact bounded Rel-17 Type-II port-selection,
RI, combinadic vector-selection and coefficient-index arithmetic layer. Full
CSI packing/coding, precoding, beam and multi-TRP orchestration remain formal
Feature gaps.

- Standards versions: the published CPU algorithm baselines cover LTE
  TS 36.101/211/212/213/214 plus the bounded TS 36.133 non-eDRX serving-cell
  slice, NR TS 38.211--38.215, the bounded RA-RNTI
  arithmetic in TS 38.321 clause 5.1.3, the Rel-17 RedCap impacted-spec
  inventory and separately declared Rel-18 eRedCap subset, and TR 38.901, IEEE Std
  802.11-2024 and the separate IEEE Std 802.11be-2024 EHT amendment. Exact
  versions, links, reference models and schema-version separation are in
  [standards-baseline.md](standards-baseline.md).
- LTE: exact EPA/EVA/ETU tables; all six FDD normal-CP bandwidth profiles;
  LTE Gold/PSS/SSS/CRS, PDSCH/PUSCH scrambling, direct-parameter 1--110-RB
  PUSCH DM-RS with complete 1/2-RB short phase tables, normalized format-0
  PRACH, caller-mask-driven SISO mapping and SC-FDMA;
  CRC/segmentation/QPP/turbo/tail-biting/rate matching; base MCS/RV/TBS and
  resource allocation; caller-selected linear measurements; and exact
  non-eDRX Nserv/filter-spacing/all-neighbour trigger arithmetic form the
  bounded frozen Release-18 profile. TDD, other
  PRACH formats, hopping/OCC and scheduler-derived mapping, the extended current TBS table, stateful
  scheduling/HARQ, eDRX/acquisition/filtering/broader RRM state and RF/RRM
  conformance remain explicit boundaries.
- NR MCS/TBS: all four supported TS 38.214 MCS tables retain exact
  rate-times-2048 values and reserved indices. PDSCH RE accounting and both
  small/large integer TBS branches are checked against static py3gpp vectors
  and an independently composed integer oracle grid.
- NR LDPC/Polar/UCI: BG1/BG2 across all supported lifting sizes, segmentation,
  encode/decode, rate matching/recovery and CRC; small-block lengths 3--11,
  CRC6/CRC11, PC-Polar, parity-check handling and two-code-block paths.
- NR physical chains: PBCH decode has a complete external py3gpp `E=864`
  input. Bounded PUSCH and PUCCH format-2 wrappers have independent
  stage-composition oracles. CPU PUSCH/PDSCH Monte-Carlo retains true
  transport blocks, CRC, decoder convergence, EVM and erasure semantics.
- PRACH: long/short family algorithms include format/root/cyclic-shift tables,
  restricted and unrestricted sets, waveform generation and multi-root
  detection. The connected normalized composite owns all major checkpoints;
  occasion rows remain representative rather than an exhaustive deployment
  database.
- Fixed NR PDSCH: one mu=0, 512FFT/CP36, single-layer QPSK, 480-RE comb-2
  profile crosses integer IFFT/FIR/FFT, LS/interpolation, ZF, LLR, fixed rate
  recovery, layered BG2 decode and CRC. Float64 decode is differential audit
  data only.
- Wi-Fi: legacy and representative HT6/VHT8/HE10/EHT13 profiles, all twelve
  WLAN LDPC matrices with a dual-source 2,160-entry, 55,620-edge and twelve-
  codeword oracle corpus, bounded floating acquisition chains, independent VHT/EHT
  receive fixtures, AWGN/TGn/TGac/TGax CPU packet sweeps and a narrower
  acquired fixed legacy chain. These are mini-PHY references, not published
  OTA packet-vector certification.
- Channels: TDL A--E, CDL A--E, TGn A--F and TGac/TGax interpolation. CDL is a
  bounded far-field isotropic ULA/UPA realization.

## Authoritative completion gate

Run from the repository root:

```bash
./mojo-wireless-dsp/scripts/verify_algorithms.sh
```

This is the authoritative Phase 0--7 algorithm gate. It precompiles the public
package; first SHA-locks and byte-regenerates the frozen Wi-Fi/NR external
oracle corpus, failing closed without the clean pinned py3gpp checkout; also
byte-regenerates the complete WLAN LDPC corpus from clean exact YALDPC and
tavildar checkouts; builds
and runs in-scope tests, benchmarks and examples; performs the
strict public evidence-ledger audit with the optional device component
excluded; verifies the checked-in fixed-artifact V2 corpus by two exact
regenerations; checks source hygiene; and queries the Bazel graph. Runtime
results are authoritative, so this status page deliberately carries no frozen
test count, benchmark count, package size or per-row coverage total. The exact
commands and the external Bazel-loader boundary are documented in
[verification.md](verification.md).
