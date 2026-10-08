# Standards baseline and version contract

This file separates normative wireless specifications from repository artifact
and checkpoint schema versions.  A schema version is never evidence of a
3GPP Release or an IEEE revision.

## Normative baseline

| Domain | Default baseline | Authoritative publication | Scope in this library |
| --- | --- | --- | --- |
| LTE propagation profiles | 3GPP TS 36.101 V18.13.0 Annex B | [official archive](https://www.3gpp.org/ftp/Specs/archive/36_series/36.101/36101-id0.zip) | EPA/EVA/ETU power-delay profiles and seeded Doppler realization |
| LTE physical channels and modulation | 3GPP TS 36.211 V18.0.2 (frozen Release 18) | [official archive](https://www.3gpp.org/ftp/Specs/archive/36_series/36.211/36211-i02.zip) | Bounded FDD normal-CP SISO resources, synchronization/reference signals, complete 1/2-RB PUSCH DM-RS short phase tables, the 3--110-RB ZC branch, the exact `v=0` domain for 1--5 RB and `v in {0,1}` domain for 6--110 RB, plus a separately scoped caller-resolved implementation of all 6- and 18-subcarrier entries in IFDMA Tables 5.5.1.2-3/-4; applicability and higher-layer derivation remain excluded |
| LTE multiplexing and channel coding | 3GPP TS 36.212 V18.1.0 (frozen Release 18) | [official archive](https://www.3gpp.org/ftp/Specs/archive/36_series/36.212/36212-i10.zip) | CRC, code-block segmentation, QPP/turbo, tail-biting convolutional and rate-matching algorithms |
| LTE physical-layer procedures | 3GPP TS 36.213 V18.3.0 (frozen Release 18) | [official archive](https://www.3gpp.org/ftp/Specs/archive/36_series/36.213/36213-i30.zip) | Base MCS/RV, complete traditional/base TBS, Type-0 resource-group and contiguous-uplink RIV calculations |
| LTE measurements | 3GPP TS 36.214 V18.1.0 (frozen Release 18) | [official archive](https://www.3gpp.org/ftp/Specs/archive/36_series/36.214/36214-i10.zip) | RSRP, RSSI, RSRQ and RS-SINR algorithms |
| LTE non-eDRX serving-cell RRM | 3GPP TS 36.133 V18.14.0 clause 4.2.2.1 and Table 4.2.2.1-1 | [official archive](https://www.3gpp.org/ftp/Specs/archive/36_series/36.133/36133-ie0.zip) | Exact four-row DRX-cycle-to-Nserv lookup, minimum filtered-measurement spacing and consecutive-failure all-neighbour trigger; eDRX, measurement acquisition/filtering, RF requirements and broader RRM state remain gaps |
| NR physical channels and modulation | 3GPP TS 38.211 V18.9.0 (frozen Release 18) | [official archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.211/38211-i90.zip) | OFDM, synchronization, PBCH/PDSCH/PUSCH/PUCCH/PRACH sequences, reference signals, resource mapping and exact 1--8-layer PDSCH codeword mapping |
| NR multiplexing and channel coding | 3GPP TS 38.212 V18.8.0 (frozen Release 18) | [official archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.212/38212-i80.zip) | CRC, LDPC, Polar, small-block, segmentation and rate matching/recovery |
| NR control procedures | 3GPP TS 38.213 V18.8.0 and TS 38.331 V18.10.0 (frozen Release 18) | [38.213 archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip), [38.331 archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-ia0.zip) | Bounded CORESET/USS candidate, timing-advance, power and PUCCH-resource calculations plus narrow complete decoded non-grouped monitoring-slot, 14-bit first-symbol and jointly owned symbol-level occasion slices |
| NR data procedures | 3GPP TS 38.214 V18.10.0 (frozen Release 18) | [official archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/38214-ia0.zip) | MCS tables, exact TBS calculation and PT-RS density selection |
| NR measurements | 3GPP TS 38.215 V18.5.0 (frozen Release 18) | [official archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.215/38215-i50.zip) | SS/CSI RSRP, RSRQ, SINR and RSSI algorithms |
| NR ordinary RRM gap | 3GPP TS 38.133 V18.14.0 | [official archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-ie0.zip) | Artifact identity and hash are pinned, but the ordinary-RRM deterministic clause/table subset and errata review are not selected; Rel-17 RedCap evidence does not authorize it |
| NR MAC identifier arithmetic | 3GPP TS 38.321 V18.10.0 clause 5.1.3 | [official archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-ia0.zip) | Pure RA-RNTI coordinate formula; surrounding MAC state is excluded |
| NR Rel-17 RedCap Work Item | 3GPP NR_redcap, UID 900062, RP-220966 | [3GPP Work Item](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=900062) | All 19 impacted specifications are inventoried in the Feature matrix; the FR1 20-MHz cross-stage composition is `PARTIAL` representative wiring, not a single normative end-to-end clause or procedure |
| NR Rel-17 RedCap capability | 3GPP TS 38.306 V17.16.0 clause 4.2.21 | [3GPP archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.306/38306-hg0.zip) | Separate FR1/FR2 capability, forbidden-feature and initial-access validation subset |
| NR Rel-17 RedCap half-duplex timing | 3GPP TS 38.213 V17.13.0 clause 17.2 and TS 38.214 V17.16.0 clauses 6.1/6.4 | [38.213 archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-hd0.zip), [38.214 archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/38214-hg0.zip) | Complete declared-profile conflict decisions and exact Tproc2; broader generic TDW event families remain explicit gaps |
| NR Rel-17 RedCap RRM | 3GPP TS 38.133 V17.22.0 clauses 4.2B, 5.1B, 8.1B, 8.5B and Annexes A/B | [3GPP archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-hm0.zip) | Exact bounded IDLE/INACTIVE serving-measurement, RLM/BFD arithmetic and published BWP/SSB/SMTC/condition-table subsets; neighbour timing, gap derivation, RF and switching state remain explicit gaps |
| NR Rel-17 RedCap RRM conformance timing | 3GPP TS 38.533 V17.9.0 clause 4 delegation and V18.8.0 clauses 16--18 | [Rel-17 archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.533/38533-h90.zip), [delegated Rel-18 archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.533/38533-i80.zip) | Exact target-cell deadline/state subset for 13 phases after caller validation of the named test configurations; non-target observations remain pending, and remaining cases, RF, RRC/TTCN, repeated-test confidence and certification remain gaps |
| NR Rel-17 RedCap idle/MAC decisions | 3GPP TS 38.304 V17.11.0 clauses 5.2.4.4/5.2.4.9 and TS 38.321 V17.15.0 clauses 5.1.1b-d/5.15.1/5.27.1 | [38.304 archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.304/38304-hb0.zip), [38.321 archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-hf0.zip) | Stationary/edge gates, bounded reselection exclusion and decoded RA-feature/BWP/CCCH arithmetic; complete idle/MAC/RRC orchestration remains explicit |
| NR Rel-18 eRedCap | 3GPP NR_redcap_enh, UID 970080, RP-233637 | [3GPP Work Item](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=970080) | Independent FR1-only capability and reduced/non-reduced baseband PRB subset; never backported into Rel-17 RedCap |
| NR frozen Features and inventory | Rel-16 through Rel-19 frozen releases; Rel-19 froze 2025-12-12 | [3GPP Work Item portal](https://portal.3gpp.org/) | Feature matrix separately locks NTN, sidelink, positioning, NR-U, MBS, enhanced MIMO/multi-TRP, coverage enhancement and FR2-2. LP-WUS RP-251200 and Ambient IoT RP-252105 are `MISSING/BLOCKED_METADATA`: their final WIDs are hashed inventory, never production authority, and exact current TS/clause/errata joins remain incomplete |
| NR Rel-17 positioning | 3GPP NR_pos_enh, UID 900060 | [3GPP Work Item](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=900060) | Bounded DL-PRS generation/mapping and TS 38.215 positioning-time arithmetic; SRS positioning and estimators remain incomplete |
| NR Rel-17 NTN | 3GPP NR_NTN_solutions, UID 860046 | [3GPP Work Item](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860046) | Bounded service-link ECEF timing/Doppler, Common TA, validity and Koffset arithmetic; orbit, HARQ/RA/RRC and waveform algorithms remain incomplete |
| NR Rel-17 sidelink | 3GPP NR_SL_enh, UID 860042 | [3GPP Work Item](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860042) | Bounded SCI-1A/PSCCH chain; PSSCH, PSFCH, resource selection and HARQ remain incomplete |
| NR Rel-18 NTN enhancement | TS 38.213 V18.8.0, TS 38.321/38.331 V18.10.0; NR_NTN_enh UID 941006 | [3GPP Work Item](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=941006) | Nonempty decoded 4/8-bit SSB and 8-bit DMRS type-1 subsets, eight configured-grant mapping values and strict RSRP thresholding for a bounded FDD RACH-less handover slice; ASN.1, 64-bit/type-2/repetition/TDD/HARQ and complete mobility state remain incomplete |
| NR Rel-18 sidelink enhancement | TS 38.214/38.321/38.331 V18.10.0 and TS 38.101-1 V18.14.0; NR_SL_enh2 UID 940097 | [3GPP Work Item](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=940097) | Uniquely determined overlapping-slot, strict-RSRP/PSFCH-overlap and bounded two-CC SL_n47B admissibility only; random choice, scheduler/CBR policy, SCI decoding and complete CA/HARQ state remain incomplete |
| NR Rel-17 further enhanced MIMO | 3GPP NR_feMIMO, UID 860040 | [3GPP Work Item](https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860040) | Bounded TS 38.214 Type-II port-selection, RI, combinadic vector and coefficient-index arithmetic; complete CSI, precoding and multi-TRP remain incomplete |
| NR Rel-18 MIMO evolution gap | 3GPP NR_MIMO_evo_DL_UL, UID 940096; RP-233028 | [official revised WID package](https://www.3gpp.org/ftp/TSG_RAN/TSG_RAN/TSGR_102/Docs/RP-233028.zip) | All 13 impacted frozen TS artifacts are pinned by exact version and SHA-256. The WID is inventory-only, final feature-specific clause/errata mappings remain `BLOCKED_METADATA`, and the Feature stays `MISSING` |
| 3GPP channel models | 3GPP TR 38.901 V18.1.0 | [official archive](https://www.3gpp.org/ftp/Specs/archive/38_series/38.901/38901-i10.zip) | Non-normative TDL/CDL reference utility, excluded from ratified completion |
| Wi-Fi base PHY/MAC | IEEE Std 802.11-2024 | [IEEE active standard](https://standards.ieee.org/ieee/802.11/10548/) | Complete declared 20-MHz SISO Clause-17/ERP-OFDM baseband; bounded DSSS/CCK, TVHT channel/tone/MCS/timing tables, Clause-20 DMG Golay/control-STF, Clause-28 EDMG integer geometry/grid, adopted single-channel WUR reference/example, EBCS TIM Mode-1/countdown, HT/SU-VHT/HE/EHT SIGNAL, single-encoder one-through-four-stream parser/CSD/direct mapping, S1G numerology/MCS geometry and FTM range arithmetic; representative modern 20-MHz chains; deterministic MAC, fragmentation/delimiter and legacy TIM/DTIM/PS-Poll profiles |
| Wi-Fi randomized/changing MAC addresses | IEEE Std 802.11bh-2024 | [IEEE published amendment](https://standards.ieee.org/ieee/802.11bh/10525/) | Bounded Device ID, IRM and PASN ID base fields, status/action tables and explicit shared-identity results; random generation, cryptography, policy and complete session procedures remain incomplete |
| Wi-Fi EHT PHY | IEEE Std 802.11be-2024 | [IEEE active amendment](https://standards.ieee.org/ieee/802.11be/7516/) | Representative 20-MHz EHT MCS 13 RU-242 chain, bounded nonpunctured one-stream U-SIG/Common-block waveform, and exact discrete 20--320-MHz geometry, assigned non-OFDMA puncturing and large-MRU component/index tables; physical wideband tone maps and waveforms remain gaps |
| Wi-Fi channel references | IEEE 802.11-03/940r4, 09/0308r12 and 14/0882r4 | [TGn](https://mentor.ieee.org/802.11/dcn/03/11-03-0940-04-000n-tgn-channel-models.doc), [TGac](https://mentor.ieee.org/802.11/dcn/09/11-09-0308-12-00ac-tgac-channel-model-addendum-document.docx), [TGax](https://mentor.ieee.org/802.11/dcn/14/11-14-0882-04-00ax-tgax-channel-model-document.docx) | Non-normative aggregate SISO utilities; excluded from ratified completion because WG contributions are not standards |

IEEE 802.11ax-2021 names remain in a few source and test comments where they
identify the amendment that introduced an HE table.  IEEE Std 802.11-2024 is
the current consolidated base and includes HE, but it does not include EHT;
EHT is therefore pinned separately to IEEE Std 802.11be-2024.  Likewise, a
checked-in external vector retains the exact tool commit and source revision
that generated it; that provenance does not silently change when the default
baseline advances.

## Qualified expansion queue and access blockers

These records do not claim implementation. They establish the ratification
decision before any new protocol source is written:

| Candidate | Formal status and date | Artifact qualification | Current decision |
| --- | --- | --- | --- |
| Bluetooth Core Specification 6.3 | Bluetooth SIG `Adopted`, 2026-05-05 | Official 28,494,145-byte PDF, SHA-256 `e210fb8f697fca2b970001d35f8c9c7c8f836190550b7fd29d2915a1c8596d60`; incorporated errata; company rights tuple pinned | `PRODUCTION` and implemented only for reviewed Vol 2 Part B raw-header HEC clauses and Part G examples, plus Vol 6 Part A capability/GFSK-limit status, Part B bit-order/channel/packet/CRC/whitening/coded-FEC/mapping/receive-order clauses and corresponding Part C official vectors; discrete waveform and reference RX choices remain explicitly non-normative, and all other volumes/features require their own scope review |
| IEEE Std 802.15.4-2024 | IEEE Active Standard, published 2024-12-12 | Official [IEEE page](https://standards.ieee.org/ieee/802.15.4/11041/) and Xplore record 10794632; company rights confirmed, but no final PDF bytes/hash are present | `BLOCKED_METADATA`; this is the revision that supersedes IEEE Std 802.15.4-2020, while P802.15.4ab/ad and other drafts remain forbidden |
| IEEE/ISO/IEC 8802-15-4-2024 | IEEE Active International Standard, published 2024-07-26 | Official [IEEE page](https://standards.ieee.org/ieee/8802-15-4/11701/) records adoption of IEEE Std 802.15.4-2020; company rights confirmed, but final bytes are absent | `BLOCKED_METADATA`; this distinct adoption cannot authorize features unique to IEEE Std 802.15.4-2024 |
| IEEE Std 802.11bk-2025 and 802.11bf-2025 | IEEE Active amendments, published 2025-09-05 and 2025-09-26 | Official [802.11bk](https://standards.ieee.org/ieee/802.11bk/11117/) and [802.11bf](https://standards.ieee.org/ieee/802.11bf/11574/) pages; company rights confirmed, but final amendment bytes/hashes are absent | `MISSING/BLOCKED_METADATA`; no ballot draft is an acceptable substitute |
| Thread 1.4.1 | Thread Group `Released`; exact full date pending artifact review | Company implementation rights and required terms are confirmed; the official [request page](https://threadgroup.org/ThreadSpec) does not provide final bytes in this workspace | `BLOCKED_METADATA` pending final artifact hash, release date, exact clauses and errata receipt |
| Matter 1.6 and Zigbee Core R23.2 (the Zigbee 4.0 release package) | Board-accepted official PDFs: Matter 1.6 (2026-06-16), SHA-256 `48b3b117569f72558ba71813360d77abdfa11fcf28747bd269148104936b52b7`; Zigbee R23.2 (2025-11-10), SHA-256 `c2638ad11136c94f69ac6ea445d6a6ebf164791c64bea5806de2c2ad4c1fe2ea` | Direct PDF hashes, exact narrow clause scopes, errata/CCB review and company rights tuples are pinned | `PRODUCTION` only for Matter Appendix-A anonymous integer TLV elements and the Zigbee fixed unsecured unicast NWK data base header; all broader protocol behavior requires separate review |

The current snapshot is still executing the P0 expansion stage; lower-priority
LTE-M/NB-IoT/V2X/LoRaWAN and P2 DECT/DVB/PLC/NFC/GNSS work follows only after
the ordered P0 scope closes. Drafts, candidate features, press releases and
source code are never used as substitute normative text.

Bluetooth Vol 6 Part A clauses 1, 3.1 and 3.1.1 now qualify the implemented
complete GFSK parameter-limit row. Clause 4.6 remains qualified only for the
pre-coded analytic/reference waveform queue row, which is still `MISSING`.
Only literal symbol-rate, BT, modulation-index, frequency-deviation, timing
and test-signal limits are normative. A future discrete Gaussian waveform and
receiver must be named analytic/reference: Vol 6 Part H 3.5.2 is deliberately
outside production scope because its printed impulse-response normalization
gives an effective index inconsistent with its h=0.5 heading and Part A.

Bluetooth Vol 2 Part B leaf clauses 1.2.1, 6.4.6, 6.5.1.1 and 7.1.1 plus
Part G clause 4 qualify only the complete raw ten-bit header HEC arithmetic.
The implementation reuses the generic reflected CRC primitive and does not
claim Access Code, header-field/TYPE semantics, complete header validity,
whitening, header FEC, payload CRC, ARQ, AFH, timing, modulation or RF.

## Contract rules

The machine-readable qualification record is
`testing/authority_manifest.tsv`.  Its 17 columns record the authority, exact
specification/version, formal status and date, official URL, downloaded
artifact SHA-256, implemented clauses/tables, incorporated errata review and
the permitted use (`PRODUCTION`, reference/inventory/tracking, exclusion or a
specific blocker).  `scripts/audit_ratified_authorities.sh` joins every
`BOUNDED`, `PARTIAL` and `COMPLETE` matrix claim to that record and fails
closed, including every declared clause/table against the same exact
specification/version record. The script pins the complete human-reviewed
manifest SHA-256, and the full verifier checks accessible production artifact
bytes rather than trusting a syntactically valid digest. Work Items, PARs, TRs and WG contributions never independently
authorize production.  A 3GPP/ETSI record may qualify only after its release
freeze date and only with an exact full status date, hashed final artifact,
resolved clause scope and completed errata review; Release 20 and later remain
structurally barred because they are not frozen.  Existing month-dated V19
transpositions stay `BLOCKED_METADATA`, rather than becoming production
authority merely because Release 19 is frozen.

The official IEEE landing pages identify the active/published editions and
company rights are confirmed, but the final 802.11-2024, 802.11be-2024,
802.11bh-2024, 802.11bk-2025, 802.11bf-2025 and 802.15.4-2024 bytes are absent
on this host. Returned WAF/login HTML is deliberately not hashed as normative
text. Those authorities therefore remain `BLOCKED_METADATA` until each exact
final artifact, SHA-256, clause scope and errata receipt is recorded; Mentor
contributions, drafts and older amendments are not substitutes.

- A module that intentionally uses a different revision must name it in the
  module docstring and in its evidence test.  Otherwise the table above is the
  normative baseline.
- Clause/table citations define the implemented algorithm.  They do not claim
  complete conformance for every scheduling configuration or a complete
  protocol stack.
- `CheckpointMetadata.version` is the checkpoint-envelope schema revision.
  It is not a 3GPP or IEEE version.
- `MWDSP-FIXED-*-V2` and manifest `schema=2` identify the canonical fixed
  artifact wire format.  The per-record `version=` field identifies a
  testcase/vector revision.  Neither field identifies a wireless standard.
- Oracle provenance (for example a py3gpp commit or an independently
  transcribed IEEE vector) is recorded beside the vector and remains immutable
  even when an algorithm is rechecked against a newer normative baseline.

The bounded profiles and unsupported configuration space are documented in
[specification-coverage.md](specification-coverage.md) and
[all-phases-status.md](all-phases-status.md); executable evidence remains
authoritative through the specification, public-API coverage and
algorithm-only verification gates.
