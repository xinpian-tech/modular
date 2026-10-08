# Communication-protocol specification coverage

This document records the standards review performed through 2026-08-23.  It uses
published, active specifications as normative baselines and keeps active PARs
as tracking items only.  “Covered” means that a deliberately bounded algorithm
profile has executable source and tests; it does not mean complete protocol,
RF, interoperability or conformance coverage.

The machine-readable baseline authority is
[`testing/specification_coverage.tsv`](../testing/specification_coverage.tsv).
The specification/Work Item/Feature authority is the 21-column
[`testing/feature_coverage.tsv`](../testing/feature_coverage.tsv). The two
matrices are joined to the 17-column ratification record in
[`testing/authority_manifest.tsv`](../testing/authority_manifest.tsv).  The
audits check pinned versions and official sources, required rows, executable
evidence, unique identities and explicit boundaries:

```bash
./mojo-wireless-dsp/scripts/audit_specification_coverage.sh --strict
bash mojo-wireless-dsp/scripts/audit_feature_coverage.sh --strict
bash mojo-wireless-dsp/scripts/audit_ratified_authorities.sh
```

Omit `--strict` only for a structural inventory audit that is expected to
report, but not fail on, explicit `PARTIAL` and `MISSING` rows. The
authoritative `verify_algorithms.sh` gate always uses strict completion for
both matrices.

The matrix statuses below measure implementation and evidence maturity, not
license or production eligibility.  The last command performs that separate
join and fails closed unless every maturity claim resolves to a formally
eligible exact specification/version with official status and date, artifact
SHA-256, exact clause scope and reviewed errata.  Inventory Work Items, PARs,
TRs and WG documents can locate or cross-check a feature but cannot authorize
production code.  Explicit source-to-reference mappings live in
[`testing/source_authority_references.tsv`](../testing/source_authority_references.tsv).
Its optional `--verify-downloads` mode re-fetches direct official artifacts
and validates their hashes and file magic.

## Implementation-maturity status vocabulary

None of these values is an authority qualification.  A row may be
implementation-`COMPLETE` and still be production-blocked until its separate
manifest authority is `PRODUCTION` qualified.

Licensed authorities also require artifact-bound company/user implementation
rights. Those rights are now explicitly confirmed and the reviewed default
attestation pins Bluetooth Core 6.3, Matter 1.6 and Zigbee R23.2 by exact hash.
Bluetooth, Matter and Zigbee are production-qualified only for their reviewed
narrow clause subsets. IEEE and Thread Group records remain
`BLOCKED_METADATA` because the final artifacts are absent. The Specification
matrix records Matter and Zigbee as `PARTIAL`, while their narrow Feature rows
are `COMPLETE` and their broad protocol-family rows remain `MISSING`. Separate
evidence-free `MISSING` rows remain for IEEE 802.15.4-2024 and Thread 1.4.1.
These boundaries prevent a narrow wire-format helper or lower-layer PHY from
being reused as an upper-layer completion claim.

- `BOUNDED`: implemented algorithm scope with source and executable tests.
- `COMPLETE`: a Feature row has production code, all required independent
  evidence classes, an attributable CPU benchmark and integration metadata.
- `PARTIAL`: implementation or evidence exists, but the declared Feature
  profile is not yet closed.
- `MISSING`: a formally published, CPU-implementable algorithm has no usable
  implementation yet.
- `EXCLUDED`: published material explicitly excluded from ratified completion;
  a separately labelled analytic/reference utility may still be executable.
- `TRACKING`: an active project or draft that is not a normative completion
  target until it is published.

## Published specification baselines and reference models

| Family | Published baseline | Implemented algorithm profile |
| --- | --- | --- |
| LTE channel | [TS 36.101 V18.13.0 Annex B](https://www.3gpp.org/ftp/Specs/archive/36_series/36.101/36101-id0.zip) | EPA/EVA/ETU absolute-delay power profiles, seeded Jakes-Doppler realization and public-boundary mutable-profile revalidation |
| LTE | [TS 36.211 V18.0.2](https://www.3gpp.org/ftp/Specs/archive/36_series/36.211/36211-i02.zip) | FDD normal-CP SISO resources, LTE Gold/PSS/SSS/CRS, PDSCH/PUSCH scrambling and bounded mapping, integer-RB PUSCH DM-RS plus the separately scoped exact 6-/18-subcarrier IFDMA short tables, PRACH format 0 and SC-FDMA over the exact 2/3/5-smooth allocation domain |
| LTE | [TS 36.212 V18.1.0](https://www.3gpp.org/ftp/Specs/archive/36_series/36.212/36212-i10.zip) | CRC, code-block segmentation/filler/concatenation, tail-biting convolutional coding, complete QPP table, turbo coding and rate matching/recovery with filler `NULL` propagation in the systematic and first-parity streams |
| LTE | [TS 36.213 V18.3.0](https://www.3gpp.org/ftp/Specs/archive/36_series/36.213/36213-i30.zip) | Base MCS/RV, complete traditional/base TBS, Type-0 resource groups and contiguous-uplink RIV |
| LTE | [TS 36.214 V18.1.0](https://www.3gpp.org/ftp/Specs/archive/36_series/36.214/36214-i10.zip) | Linear-domain RSRP, RSSI, RSRQ and RS-SINR measurements with explicit NaN, infinity and finite-overflow rejection |
| LTE RRM | [TS 36.133 V18.14.0 clause 4.2.2.1 and Table 4.2.2.1-1](https://www.3gpp.org/ftp/Specs/archive/36_series/36.133/36133-ie0.zip) | Complete non-eDRX four-row DRX-cycle/Nserv lookup, exact half-cycle filtered-measurement spacing and consecutive-failure all-neighbour trigger; acquisition, filtering, eDRX and broader RRM state remain excluded from this narrow row |
| NR | [TS 38.211 V18.9.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.211/38211-i90.zip) | OFDM/grid, synchronization, PBCH/PDSCH/PUSCH/PUCCH/PRACH, reference signals, bounded PDCCH mapping and exact 1--8-layer PDSCH codeword mapping |
| NR | [TS 38.212 V18.8.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.212/38212-i80.zip) | CRC, LDPC, Polar, small-block, segmentation/rate matching and bounded DCI coding |
| NR | [TS 38.213 V18.8.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip) and [TS 38.331 V18.10.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-ia0.zip) | CORESET/USS candidate, timing-advance, PUSCH-power and PUCCH-resource calculations plus exact decoded non-grouped monitoring-slot, 14-bit first-symbol and symbol-level occasion arithmetic |
| NR | [TS 38.214 V18.10.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/38214-ia0.zip) | Four MCS tables, exact TBS, PDSCH RE accounting and PT-RS density |
| NR | [TS 38.215 V18.5.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.215/38215-i50.zip) | SS/CSI RSRP, RSRQ, SINR and RSSI plus bounded positioning-time arithmetic |
| NR MAC arithmetic | [TS 38.321 V18.10.0 clause 5.1.3](https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-ia0.zip) | RA-RNTI coordinate formula only |
| NR Rel-17 RedCap | [NR_redcap Work Item 900062 / RP-220966](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=900062) | Impacted-spec inventory; capability/access/BWP, HD-FDD and bounded RLM/BFD/serving-measurement calculations. The FR1 20-MHz cross-stage composition is `PARTIAL` representative wiring across separately scoped stages, not a normative end-to-end clause or procedure |
| NR Rel-17 RedCap capability | [TS 38.306 V17.16.0 clause 4.2.21](https://www.3gpp.org/ftp/Specs/archive/38_series/38.306/38306-hg0.zip) | Separate FR1/FR2 capability and forbidden-feature validation; no ASN.1 codec claim |
| NR Rel-17 RedCap RRM | [TS 38.133 V17.22.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-hm0.zip) | Exact integer-microsecond RLM/BFD, bounded serving schedules, and published Annex BWP/SSB/SMTC/condition-table subsets |
| NR Rel-17 RedCap RRM conformance timing | [TS 38.533 V17.9.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.533/38533-h90.zip) delegating [V18.8.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.533/38533-i80.zip) | All 13 target-cell response phases of seven named FR1/FR2/E-UTRA cases after caller-side configuration validation; non-target observations remain pending, while other cases, RF/TTCN and certification remain explicit |
| NR Rel-18 eRedCap | [NR_redcap_enh Work Item 970080 / RP-233637](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=970080) | Distinct FR1-only capability type and reduced/non-reduced baseband PRB validation; never substituted for Rel-17 RedCap |
| NR Rel-17 NTN | [NR_NTN_solutions Work Item 860046](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860046) | Caller-evaluated ECEF service-link RTT/Doppler, Common TA, validity and effective Koffset subset; orbit, HARQ/RA/RRC and waveform gaps remain |
| NR Rel-18 NTN enhancements | [NR_NTN_enh Work Item 941006 / RP-240779](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=941006) | Bounded FDD RACH-less-handover Type-1 configured-grant ordering over nonempty decoded 4/8-bit SSB and 8-bit DMRS type-1 subsets, plus strict latest-unfiltered L1 SS-RSRP thresholding; 64-bit subsets, DMRS type 2, repetitions, TDD, HARQ and wider mobility/RRM remain gaps |
| NR Rel-17 sidelink | [NR_SL_enh Work Item 860042](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860042) | Bounded SCI-1A and PSCCH coding/scrambling/DM-RS/RE-mapping subset; PSSCH/PSFCH/resource-selection/HARQ gaps remain |
| NR Rel-18 sidelink enhancement | [NR_SL_enh2 Work Item 940097 / RP-232789](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=940097) | Uniquely determined 15/30-kHz slot-mask admissibility, strict-RSRP-gated PSFCH/LTE overlap and bounded two-CC SL_n47B configuration checks; random choice, scheduler policy, SCI decoding and complete CA/HARQ state remain gaps |
| NR Rel-17 further enhanced MIMO | [NR_feMIMO Work Item 860040](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860040) | Exact decoded Type-II port-selection configuration, RI, combinadic vector selection and coefficient index/priority/count subset; full CSI, precoding, beam and multi-TRP procedures remain |
| NR Rel-18 MIMO evolution | [RP-233028 official package](https://www.3gpp.org/ftp/TSG_RAN/TSG_RAN/TSGR_102/Docs/RP-233028.zip) | Exact versions and hashes for all 13 frozen impacted TS artifacts are recorded, but unresolved final clause/maintenance mappings remain `BLOCKED_METADATA`; no Rel-18 multi-panel, multi-TRP, dual-timing-advance or enhanced-CSI implementation is claimed |
| NR published Feature inventory | [3GPP Work Items](https://portal.3gpp.org/) | Required Feature rows for NTN, sidelink, positioning, NR-U, MBS, enhanced MIMO/multi-TRP, coverage enhancement, LP-WUS, Ambient IoT and operation through 71 GHz; every remaining feature-specific gap stays explicit |
| NR channel | [TR 38.901 V18.1.0](https://www.3gpp.org/ftp/Specs/archive/38_series/38.901/38901-i10.zip) | Non-normative seeded TDL/CDL reference utility, excluded from ratified completion |
| Wi-Fi | [IEEE Std 802.11-2024](https://standards.ieee.org/ieee/802.11/10548/) | Complete declared 20-MHz SISO Clause-17/ERP-OFDM baseband; bounded DSSS/CCK, TVHT, DMG, EDMG integer-grid, WUR reference and EBCS Mode-1/countdown subsets; representative one-stream HT/VHT/HE chains, HE SIGNAL-driven receive, and a bounded single-encoder one-through-four-stream parser/CSD/direct-mapping slice |
| Wi-Fi randomized/changing MAC addresses | [IEEE Std 802.11bh-2024](https://standards.ieee.org/ieee/802.11bh/10525/) | Exact bounded Device/IRM/PASN base fields and explicit status transitions; address generation, cryptography, policy and complete session procedures remain gaps |
| Wi-Fi EHT | [IEEE Std 802.11be-2024](https://standards.ieee.org/ieee/802.11be/7516/) | Representative 20-MHz one-stream EHT chain and SIGNAL-driven receive plus exact discrete 20--320-MHz geometry, all assigned non-OFDMA puncturing rows and published large-MRU component/index rows; no physical wideband waveform claim |
| Wi-Fi channel references | [TGn](https://mentor.ieee.org/802.11/dcn/03/11-03-0940-04-000n-tgn-channel-models.doc), [TGac](https://mentor.ieee.org/802.11/dcn/09/11-09-0308-12-00ac-tgac-channel-model-addendum-document.docx), [TGax](https://mentor.ieee.org/802.11/dcn/14/11-14-0882-04-00ax-tgax-channel-model-document.docx) | Non-normative aggregate SISO reference utilities; WG contributions are excluded from ratified completion |
| Bluetooth | [Core Specification 6.3](https://www.bluetooth.com/specifications/specs/core-specification-6-3/) | `PARTIAL`: reviewed Classic raw-header HEC, LE 1M/2M uncoded packet-bit, optional LE Coded transmit/exact-pattern/hard-FEC-reference-RX, and Part-A GFSK parameter-limit slices are implemented and production-qualified; broad LE and BR/EDR remain `MISSING` |
| IEEE 802.15.4 | [IEEE Std 802.15.4-2024](https://standards.ieee.org/ieee/802.15.4/11041/) | `MISSING/BLOCKED_METADATA`; company rights are confirmed but no final artifact/hash/clause/errata receipt is present |
| IEEE/ISO/IEC 8802-15-4 | [IEEE/ISO/IEC 8802-15-4-2024](https://standards.ieee.org/ieee/8802-15-4/11701/) | `MISSING/BLOCKED_METADATA`; this is a distinct adoption of IEEE Std 802.15.4-2020 and its final bytes are absent, so it cannot infer later revision-only content |
| Thread | [Thread Specification 1.4.1](https://threadgroup.org/ThreadSpec) | `MISSING/BLOCKED_METADATA`; rights and terms are confirmed but final bytes and exact release metadata are absent |
| Matter | [Matter Core Specification 1.6](https://csa-iot.org/wp-content/uploads/2026/06/23-27349-011_Matter-1.6-Core-Specification.pdf) | `PARTIAL`: the Appendix-A anonymous signed/unsigned integer TLV element slice is implemented and production-qualified; the broad Matter core remains `MISSING` |
| Zigbee | [Zigbee Core Specification R23.2](https://csa-iot.org/wp-content/uploads/2025/11/docs-06-3474-23-csg-zigbee-specificationR23.2_clean.pdf) | `PARTIAL`: the fixed unsecured unicast NWK data base-header slice is implemented and production-qualified; the broad Zigbee network stack remains `MISSING` |

The Classic BR/EDR HEC row covers exactly ten caller-owned header-information
bits in wire order and an explicit eight-bit UAP or DCI initialization. All
twenty adopted Part G examples and an independent eight-cell recurrence cover
all 1024 headers by 256 initializations. A zero remainder is only an HEC
result: Access Code, header-field/TYPE semantics and complete header validity
remain outside this atomic row.

The Bluetooth LE uncoded narrow row covers exact 2--258-octet caller-owned PDU bits,
1M/2M preambles, a caller-owned 32-bit Access Address, 24-bit CRCInit, physical
channels 0--39, CRC-24, whitening and inverse verdict flags. Two internally
consistent official Part C packets, all 40 official whitening prefixes and a
test-owned CRC/LFSR differential close that domain. The published Part C
4.2.2 extended-advertising example contains a ChSel/CRC inconsistency; it is
retained as an explicit negative `crc_ok` regression and never overrides the
normative Part B CRC recurrence.

The uncoded encoder and decoder retain their actual preamble, Access Address,
PDU, CRC, whitening/dewhitening and packet stages. Every stage has owned
checkpoint metadata and a caller-owned testcase identity; verdicts do not
replace the real receive intermediates.

The separate optional LE Coded transmit row covers exact 2--257-octet opaque PDU bits,
the fixed coded preamble, caller-owned Access Address, CI and TERM fields, two
terminated K=4 FEC blocks, and the complete S=2/S=8 pattern mapping. It reuses
the common convolutional encoder, contains no invented PHY interleaver, and
does not claim GFSK, Link Layer semantics or scheduling. Its
result likewise retains the actual CI, TERM1/2, both FEC inputs and outputs,
both mapped blocks and final packet symbols with owned metadata.

Two additional optional LE Coded receive rows are now `COMPLETE`: one inverts
only exact legal S=2/S=8 hard codewords, and the other uses the shared hard
Viterbi decoder on a caller-delimited complete packet. The latter preserves 16
actual received/demapped/decoded checkpoints, including observed TERM tails,
and stops at whitened PDU plus CRC. Packet-boundary knowledge, exact preamble
comparison, hard metric/tie-breaking and malformed-codeword behavior are
reference choices; GFSK, synchronization, dewhitening, CRC/AA validity and
Link Layer decisions remain outside these rows. Official 510/912-symbol Part C
fixtures, all legal PDU geometries, all 16 S8 groups and a test-local delay-cell
encoder provide exact independent evidence.

The adopted Vol 6 Part A GFSK parameter-limit row is also `COMPLETE`. It owns
the full mandatory LE 1M and optional LE 2M rows, BT=0.5, inclusive standard
and stable modulation-index ranges, asymmetric Fmin calculation, absolute and
relative deviation floors, strict timing/zero-crossing limits, bit-deviation
signs and all-supported-PHY stable-claim rule. The remaining GFSK waveform/RX
row stays `MISSING`: a future bounded nominal-h analytic/reference waveform
and known-timing receiver can never be called a normative discrete filter or
decoder. The conflicting printed Vol 6 Part H 3.5.2 equation remains excluded
pending an official incorporated resolution and is not inferred from industry
convention.

The Matter narrow row covers one exact anonymous signed or unsigned integer
TLV element with caller-selected 1/2/4/8-octet width. All six official Table
127 integer examples, every one-octet value, all control octets and width
endpoints are checked against a test-owned base-256 oracle. The Zigbee narrow
row covers only the fixed eight-octet unsecured unicast NWK data base header;
all 65,536 frame-control words, every short-address endpoint and all radius and
sequence octets are checked independently. Neither row claims a complete
Matter or Zigbee protocol stack.

IEEE Std 802.11-2024 is the active consolidated base, but it does not contain
EHT.  EHT therefore remains pinned separately to IEEE Std 802.11be-2024.
Schema versions such as `CheckpointMetadata.version` and
`MWDSP-FIXED-*-V2` are repository formats, never substitutes for these
normative revisions.

## 4G LTE boundary

LTE has protocol-specific algorithms that cannot be inferred from similarly
named NR code.  The bounded LTE layer therefore owns the 62-subcarrier LTE
PSS/SSS constructions, CRS placement, LTE Gold initializations, FDD
normal-CP resource arithmetic, SC-FDMA transform precoding over exactly the
2/3/5-smooth DFT allocations, the complete 1/2-RB short phase tables and
3--110-RB Zadoff--Chu branch of PUSCH DM-RS, plus a separate exact helper for
the caller-resolved 6- and 18-subcarrier phase tables in Tables 5.5.1.2-3/-4,
PRACH format 0, caller-mask-driven SISO PDSCH/PUSCH mapping, LTE MCS/RV and
traditional/base TBS tables, QPP/turbo/segmentation (including filler `NULL`
propagation through the systematic and first-parity turbo streams),
finite-domain LTE measurements, and the TS 36.133 clause 4.2.2.1 non-eDRX
serving-cell Nserv/spacing/trigger arithmetic. TS
36.101 Annex B EPA/EVA/ETU
profiles provide the LTE-specific channel baseline, with every public profile
consumer revalidating mutable fields before use. Dedicated per-API workloads
cover all public LTE table/config entry points and retain full owned outputs
while using O(1) post-timing fingerprints. Common FFT, QAM, CRC
storage, complex arithmetic and channel realization remain shared engines.

The supported profile is a readable SISO/FDD reference for all six LTE
bandwidth configurations from 1.4 through 20 MHz. PUSCH DM-RS accepts direct
`u`/`v`/`n_cs` inputs for 1--110 allocated RB; the 1/2-RB branches exhaustively
transcribe Tables 5.5.1.2-1/-2. Allocations of 1--5 RB require `v=0`, while
6--110 RB permits `v` in `{0,1}`. Tables 5.5.1.2-3/-4 define separate
IFDMA/sub-RB sequence lengths that the integer-RB API cannot represent; the
dedicated API accepts only caller-resolved lengths 6 or 18 and covers all 30
phase rows without inferring IFDMA/DCI/RRC applicability. PRACH is a normalized one-root format-0 sequence
and detector, and mapping consumes explicit caller masks rather than scheduler
state. TDD, carrier aggregation, MBSFN, sidelink, eMTC, NB-IoT, arbitrary
multi-antenna transmission, hopping/OCC/DCI-derived DM-RS configuration,
complete transport-channel facades, every PRACH format/radio-rate occasion,
the extended current 44-row LTE transport-block-size table and a scheduler/
HARQ state machine, eDRX behavior, measurement acquisition/filtering and
broader RRM state remain explicit boundaries.

## 5G NR boundary

The existing bounded NR data and uplink chains are complemented by PDCCH/DCI
algorithms, bounded TS 38.213 stateless calculations, the TS 38.321 RA-RNTI
formula and TS 38.215 measurements.
PDCCH/DCI coverage is a bounded CORESET/non-interleaved search-space profile;
the narrow TS 38.213 clause 10.1 and TS 38.331 clause 6.3.2 Features close all
15 base periodicities, every legal offset, duration presence and slot-window
membership, the 14-bit `monitoringSymbolsWithinSlot` projection, and joint
symbol-level occasion membership with duration, ordering, separation and slot
containment revalidation. Grouped, v1710 and DCI-specific monitoring,
complete random-access procedures, scheduler policy,
closed-loop power-control state, CSI reporting state and arbitrary
multi-layer/multi-codeword scheduling are excluded.

Rel-17 RedCap is tracked independently from ordinary NR and Rel-18 eRedCap.
The implemented subset validates hard capability profiles, initial BWP/access,
HD-FDD conflict and guard decisions, grant-profile-aware available-slot
counting, DM-RS bundling-window splits, exact TS 38.133 RLM/BFD arithmetic,
TS 38.304 stationary/edge/exclusion state, and TS 38.321 decoded RA feature-set,
BWP fallback and CCCH-LCID decisions. The bounded 38.133 4.2B/5.1B
one-/two-Rx IDLE/INACTIVE serving-measurement tables and exact failure threshold
are also executable. Exact A.3.9A BWP, A.3.10B SSB, A.3.11A SMTC, A.3.35
scope selection and bounded Annex-B condition expressions are imported as
static evidence without fabricating the anomalous B.2.16-2 FR1 rows.
TS 38.321 selection returns the unique four-step and
optional two-step members of the chosen FeatureCombination; it does not invent
a random tie. An explicit representative FR1 20-MHz profile composes PSS/SSS, PBCH/MIB,
PDCCH/DCI and PDSCH in the downlink and normalized PRACH, PUSCH and PUCCH/UCI
in the uplink. Each stage retains its separately declared TS/profile scope;
there is no single normative clause or end-to-end conformance oracle for this
composition, so its Feature row is `PARTIAL`. Exact clause-6.4 `N2` tables and `T_proc,2`, DCI-triggered
PRACH precedence, higher-layer PRACH/MsgA choice categories and checked TBMS
`N*K` are now explicit. The matrix remains `PARTIAL`: generic TDW event
families, gap/SMTC-derived availability, candidate-beam and
switching-delay state, PRACH-occasion/SDT procedures, full RRC/MAC orchestration
and conformance vectors are not silently inferred from these helpers.

Ordinary NR is also audited by published Work Item rather than inferred from
the frozen Release-18 core primitives. The required inventory now locks
[Rel-17 NTN](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860046),
[Rel-18 NTN enhancements](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=941006),
[Rel-17 and Rel-18 sidelink](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860042),
[positioning](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=900060),
[NR-U](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=820067),
[MBS](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860048),
[Rel-17/18 enhanced MIMO and multi-TRP](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860040),
[coverage enhancement](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=900061),
[Rel-19 LP-WUS](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=1020094),
[Rel-19 Ambient IoT](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=1060084),
and [FR2-2 operation through 71 GHz](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860041).
The positioning, Rel-17/Rel-18 NTN, Rel-17/Rel-18 sidelink, NR-U, MBS,
coverage-enhancement and FR2-2 rows are `PARTIAL`.
Release 19 is frozen as of 2025-12-12, so LP-WUS and Ambient IoT are no longer
draft `TRACKING` entries. They are `MISSING/BLOCKED_METADATA`: final revised
WIDs RP-251200 and RP-252105 are pinned by official ZIP hash for inventory,
but Work Items cannot authorize production. LP-WUS still lacks a qualified
per-TS clause/errata join, while Ambient IoT also has an unresolved current
new-spec/impacted-spec reconciliation (including the TS 38.291 portal
association); neither feature has production source or completion evidence.
Positioning lacks SRS, RF ToA and AoA/AoD estimators. Rel-17 NTN lacks raw
ephemeris/orbit propagation, discrete timing-advance, HARQ/RA/RRC and waveform
composition. The Rel-18 NTN slice adds all eight decoded
`rrc-SSB-PerCG-PUSCH` values, bounded nonempty 4/8-bit SSB and 8-bit type-1
DMRS ordering and
the strict configured-grant SS-RSRP threshold, while 64-bit subsets, DMRS
type 2, repetitions, TDD/PRACH validity and full mobility/RRM remain missing.
Rel-17 sidelink lacks PSSCH, PSFCH, resource selection and HARQ. The Rel-18
slice adds only uniquely determined overlapping-slot, strict-RSRP/PSFCH-
reservation overlap and bounded two-CC n47 admissibility; random selection,
SCI decoding and complete scheduler/CA/HARQ state remain missing. The MBS
slice closes CFR allocation, DCI 4_0/4_1 sizes, MCCH notification, NACK-only
PUCCH selection and SPS/HARQ-index arithmetic, but not MBS waveform, group
scrambling/DM-RS, complete HARQ/SPS/DRX/MCCH/MTCH state or end-to-end PTM
reception. The coverage-enhancement slice closes the declared PUSCH
allocation, Msg3 repetition, TBMS slot-selection and nominal-TDW arithmetic,
but not PUCCH repetition, all actual-TDW events, scheduler orchestration or
waveform combining. The NR-U slice closes TS 37.213 V16.14.0 DL/UL priority-
class tables, Type-1 defer/caller-supplied backoff and contention-window
arithmetic, repeated-CWmax reset, nominal COT bounds and the UL priority-3/4
Note-2 6-to-8-ms inserted-gap decision. Type-2 access, RF sensing, uniform
random generation/distribution, HARQ-driven CW update, shared-COT
initiator/responder procedures beyond that bounded gap geometry, discovery or
DRS, RRC/DCI decoding, waveform and the complete channel-access state machine
remain missing.
Remaining listed rows stay `MISSING`, because terrestrial
OFDM, coding, matrix and channel primitives are not feature-specific
implementations. The FR2-2 slice closes n263 normal-CP numerology and slot
geometry, all declared Rel-17 PRB/guardband rows, the complete 3-by-3
`L_RA=139` PRACH/PUSCH-SCS table and bandwidth-specific NR-ARFCN rasters; its
waveform, per-symbol CP timing, PRACH occasions, shared-spectrum access and
PUSCH/PUCCH procedures remain missing. Each row has an explicit CPU-algorithm
boundary so RF, network policy and protocol-stack exclusions cannot hide
baseband or finite-procedure gaps.

TR 38.901 is separately represented because channel realizations are not part
of TS 38.211--38.215. TDL/CDL behavior is a non-normative deterministic
reference utility and is excluded from ratified completion, as well as from
RF or OTA channel-emulator certification claims.

## Wi-Fi boundary

The published data-PHY profile is deliberately sub-7.25 GHz and 20 MHz. The
declared Clause-17/ERP-OFDM SISO known-timing baseband profile is complete for
all eight rates, including preamble, L-SIG, DATA, FCS and inverse receive
processing. The bounded aligned DSSS/CCK profile composes exact Barker/CCK
chip-symbol mappings with long/short PLCP/PPDU processing through MPDU FCS;
packet acquisition, pulse shaping, equalization and optional PBCC remain
outside that profile, so the broad Clause-15/16 rows remain partial. HT MCS 6,
VHT MCS 8, HE MCS 10 RU-242 and EHT MCS 13 RU-242 remain representative.
It includes BCC/LDPC, mapping, OFDM, acquisition, channel estimation, pilot
tracking, SERVICE/FCS and CPU packet trials over AWGN/TGn/TGac/TGax. Clause 19
HT-SIG and ordinary SU Clause 21 VHT-SIG-A/B field/CRC and geometry algorithms
are available, but they do not close a complete HT/VHT PPDU.
The base-MAC subset also implements exact DCF/EDCA AIFS, explicit backoff and
retry/CW transitions, NAV arithmetic, Sequence Control and Block-Ack window
classification, basic A-MSDU/A-MPDU length planning, bounded base
fragmentation/reassembly, strict non-DMG MPDU-delimiter CRC/serialization, and
bounded HE dual-NAV, TXOP_DURATION and Trigger User/RU arithmetic. Canonical
Method-A TIM/DTIM, ListenInterval/ReceiveDTIMs and legacy PS-Poll arithmetic
form a separate complete narrow profile. APSD, TWT, TIM Broadcast, WNM sleep,
IBSS/PBSS, BSS classification, complete Trigger parsing/UORA/MU-EDCA/spatial
reuse and aggregate resynchronization policy remain formal gaps. A bounded EHT
MLO slice now implements TID-to-link element encoding/decoding, default and
incremental DL/UL mapping state, mapped-link union projection, EML timing-table
decoding and full-UInt64 TSF/TU field arithmetic. Complete frame-context
parsing, setup/reconfiguration, negotiation and
activation/expiry procedures, Multi-Link and Per-STA Profile parsing, power
save, NSTR/STR, eMLSR/eMLMR state, cross-link Block Ack and security remain
formal gaps, so the broad MLO row stays `PARTIAL`.

Clause-23 S1G now has a bounded configuration subset covering all five
bandwidth numerologies, occupied-tone sets, all valid single-stream MCS cells
and BCC SU long-GI SERVICE/tail/pad/TXTIME arithmetic.  SIG, preamble/training,
short-GI, FEC, waveform/RX and deterministic S1G MAC remain incomplete.  The
enhanced-positioning row also has exact FTM t1/t2/t3/t4 timing, optional
clock-rate correction and vacuum-equivalent range conversion for already
unwrapped and calibrated timestamps; frame/session/security state, RF timing,
HE/EDMG ranging waveforms and position solving remain incomplete.

Clause-20 DMG now has a bounded Golay/control-training subset: all six
published Ga/Gb tables at lengths 32/64/128, exact noiseless pi/2-BPSK chip
mapping/inversion, the complete 6400-chip control STF and exact complementary
autocorrelation.  Control/SC/OFDM headers and payload chains, CEF, HCS,
scrambling/LDPC, acquisition, channel estimation, equalization and beam
training remain gaps, so `DMG_PHY` stays `PARTIAL`.

Clause-28 EDMG now has a bounded integer OFDM subset: all four contiguous
NCB signal-parameter rows, all 26 legal channel-center rows, all 12 GI/sample
combinations and strict finite natural-DFT-order occupied-grid pack/unpack with
three zero DC tones and zero guards. Pilot/data tone tables, DC relative shift,
EDMG STF/CEF, complete Control/SC/OFDM PPDUs, headers, LDPC, TRN,
beamforming/MIMO and receive processing remain gaps, so `EDMG_PHY` stays
`PARTIAL`.

Clause-34 EBCS now has a deliberately narrow TIM Mode-1 subset: distinct
Content IDs 1--255, canonical Mode-1 element serialization/parsing when the
list is strictly shorter than its minimal bitmap, membership and fixed-period
DTIM countdown. Mode 0 and equal-size selection are rejected because the
adopted CID2068 and 0089r8/CID5138 Length rules differ by one octet; frame
carriage, full exchanges, security and scheduling remain gaps, so `EBCS_MAC`
stays `PARTIAL`.

Clauses 29--30 WUR now have a bounded adopted-reference subset for one 20 MHz
channel and one transmit chain: both LDR/HDR tone and symbol geometries, the
complete 127-state symbol randomizer, cyclic-shift tables, direct-IDFT On
symbols, exact Off symbols and full-output modulation of caller-supplied
already encoded decisions.  Adopted TGba material says actual Sync/Data
waveform generation is implementation-dependent, so this reproducible example
does not claim a unique mandatory waveform. Manchester/repetition coding,
WUR-Sync contents, MAC/FCS fields, complete PPDU assembly, windowing, detector
and receive processing plus the adopted whole-WUR-Sync-plus-Data correlation
test remain missing; `WUR_MAC_PHY` stays `PARTIAL`.

Published but unsupported CPU-implementable PHY and service families are
explicit `MISSING` rows rather than exclusions: CDMG/CMMG, NGV, light
communication, 320 MHz positioning and WLAN sensing. TVHT, S1G, DMG, EDMG,
WUR, EBCS and enhanced positioning are `PARTIAL` rather than absent.

IEEE 802.11bh-2024 now has a bounded CPU-only identity-field subset: exact
Device ID, IRM and PASN ID base payload directionality, complete non-reserved
Identifier Status and IRM Action rows, six-octet local-individual address
validation, and the explicit Recognized/Not Recognized Address-2
shared-identity result. Random generation and quality, AES-SIV/key handling,
opaque identifiers, privacy policy, ESS distribution, complete
MLME/authentication/association/PASN/FT/roaming, duplicate-detection policy,
full frames and complete session state remain gaps, so
`Randomized_changing_MAC_addresses` stays `PARTIAL`. Deterministic algorithm
subsets of IEEE 802.11bk-2025 and IEEE 802.11bf-2025 remain feature gaps;
deployment policy, RF and OTA behavior stay outside the library.

The active IEEE projects P802.11 revision, P802.11bi, P802.11bn, P802.11bp,
P802.11bq, P802.11br and P802.11bt are recorded as `TRACKING`; draft content is
not silently treated as a stable implementation requirement.

## Excluded layers and conformance

Finite RRM timing, threshold, aggregation and state decisions from the pinned
TS 36.133 V18.14.0 and TS 38.133 V18.14.0 artifacts, and applicable digital
conformance-vector calculations, are in scope.  The narrow LTE non-eDRX
clause 4.2.2.1/Table 4.2.2.1-1 slice is implemented and qualified; the broad
LTE row stays `PARTIAL`. Ordinary NR RRM remains `MISSING/BLOCKED_METADATA`
until exact CPU-only clauses/tables and errata qualification are reviewed;
Rel-17 RedCap evidence cannot satisfy it. RF/OTA
apparatus, calibrated accuracy/certification execution, 36/38.101 RF clauses,
36/38.104, 36/38.141, 36/38.508 and RF portions of 36/38.521 remain excluded.
Complete MAC/RLC/PDCP/RRC stacks, commercial scheduler policy, regulatory
tests, third-party interoperability and complete network procedure state
machines are outside this algorithm library, while pure deterministic
MAC/procedure calculations and decoded-configuration validators remain in
scope. An excluded
row is not a claim that the specification is unimportant; it makes the
boundary reviewable and prevents a generic primitive from being counted as
protocol conformance.
