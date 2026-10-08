#!/usr/bin/env bash

set -u
set -o pipefail

strict=0
if (( $# > 1 )); then
    printf 'usage: %s [--strict]\n' "$0" >&2
    exit 2
fi
if (( $# == 1 )); then
    if [[ "$1" != "--strict" ]]; then
        printf 'usage: %s [--strict]\n' "$0" >&2
        exit 2
    fi
    strict=1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "${script_dir}/.." && pwd)
matrix="${project_dir}/testing/feature_coverage.tsv"
kernel_matrix="${project_dir}/testing/kernel_coverage.tsv"

if [[ ! -f "${matrix}" ]]; then
    echo "ERROR missing feature matrix: testing/feature_coverage.tsv" >&2
    exit 2
fi
if [[ ! -f "${kernel_matrix}" ]]; then
    echo "ERROR missing kernel ledger: testing/kernel_coverage.tsv" >&2
    exit 2
fi

expected_header=$'family\trelease_or_revision\tspecification\tclause_or_table\twork_item_or_feature\talgorithm\tmandatory_or_optional\tdeclared_profile\tstatus\tsource_symbol\tdeterministic_test\tedge_test\tproperty_test\tdifferential_test\toracle_kind\ttolerance_test\ttolerance_mode\tbenchmark\tofficial_url\tboundary\tnotes'
IFS= read -r actual_header < "${matrix}"
if [[ "${actual_header}" != "${expected_header}" ]]; then
    echo "ERROR feature matrix header does not match the 21-column schema" >&2
    exit 2
fi

expected_kernel_header=$'component\tkind\tapi\tsource\tdeterministic\tedge\tproperty\tdifferential\toracle_kind\ttolerance\ttolerance_mode\tbenchmark\tnotes'
IFS= read -r actual_kernel_header < "${kernel_matrix}"
if [[ "${actual_kernel_header}" != "${expected_kernel_header}" ]]; then
    echo "ERROR kernel ledger header does not match the 13-column schema" >&2
    exit 2
fi

bad_width=$(awk -F '\t' 'NF != 21 { print NR ":" NF }' "${matrix}")
if [[ -n "${bad_width}" ]]; then
    echo "ERROR feature rows must have exactly 21 tab-separated columns:" >&2
    echo "${bad_width}" >&2
    exit 2
fi

bad_kernel_width=$(awk -F '\t' 'NF != 13 { print NR ":" NF }' "${kernel_matrix}")
if [[ -n "${bad_kernel_width}" ]]; then
    echo "ERROR kernel ledger rows must have exactly 13 tab-separated columns:" >&2
    echo "${bad_kernel_width}" >&2
    exit 2
fi

audit_tmp=$(mktemp -d)
trap 'rm -r -- "${audit_tmp}"' EXIT
errors_file="${audit_tmp}/errors"
seen_file="${audit_tmp}/seen"
actual_required_file="${audit_tmp}/actual-required"
expected_required_file="${audit_tmp}/expected-required"
formal_protocol_sources_file="${audit_tmp}/formal-protocol-sources"
protocol_sources_file="${audit_tmp}/protocol-sources"
excluded_protocol_sources_file="${audit_tmp}/excluded-protocol-sources"
orphan_protocol_sources_file="${audit_tmp}/orphan-protocol-sources"
semantic_owners_file="${audit_tmp}/semantic-owners"
facade_sources_file="${audit_tmp}/facade-sources"
: > "${errors_file}"
: > "${seen_file}"
: > "${actual_required_file}"
: > "${formal_protocol_sources_file}"
: > "${protocol_sources_file}"
: > "${orphan_protocol_sources_file}"

# These public analytic channel injectors are used to exercise reference
# receivers.  They do not implement normative NR/WLAN wire behavior and
# therefore must not be disguised as formal Feature coverage.  Keep this list
# exact and intentionally tiny: every other protocol-ledger source is required
# to resolve through a COMPLETE or PARTIAL formal Feature row below.
cat > "${excluded_protocol_sources_file}" <<'EOF'
nr|wireless_nr|wireless_dsp/wireless/nr/pucch_chain.mojo::nr_pucch_format2_flat_channel
wifi|wifi|wireless_dsp/wireless/wifi/acquisition_chain.mojo::wifi_acquisition_apply_channel_20mhz
EOF
sort -u -o "${excluded_protocol_sources_file}" "${excluded_protocol_sources_file}"

# These exact owners are part of the Feature contract, rather than merely
# reverse-reachability aliases.  For every mapping below, the owner row must
# copy all six list-valued evidence categories from the exact kernel-ledger
# source row.  This prevents a scenario-specific row from laundering a
# missing generic owner and prevents fixed protocol references from escaping
# the protocol Feature audit through their backend component name.
cat > "${semantic_owners_file}" <<'EOF'
nr|NR_TS38212_bounded_channel_coding_core|wireless_dsp/wireless/nr/ldpc_codec.mojo::nr_ldpc_encode
nr|NR_TS38212_bounded_channel_coding_core|wireless_dsp/wireless/nr/pdsch.mojo::nr_transport_crc
nr|NR_TS38212_bounded_channel_coding_core|wireless_dsp/wireless/nr/pdsch.mojo::nr_transport_crc_append
nr|NR_TS38212_bounded_channel_coding_core|wireless_dsp/wireless/nr/pdsch.mojo::nr_transport_crc_check
nr|NR_TS38212_bounded_channel_coding_core|wireless_dsp/wireless/nr/uci.mojo::nr_uci_encode
nr|NR_TS38211_bounded_PHY_core|wireless_dsp/wireless/nr/prach.mojo::nr_prach_occasion_is_active
nr|NR_TS38213_bounded_control_procedure_core|wireless_dsp/wireless/nr/procedures.mojo::nr_timing_advance_update_tc
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/control.mojo::nr_pdcch_encode
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/pdsch_chain.mojo::nr_pdsch_encode_transport_block
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/pdsch_chain.mojo::nr_pdsch_decode_grid_comb2
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/pdsch_chain.mojo::nr_pdsch_decode_waveform_comb2
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/pusch_chain.mojo::nr_pusch_encode_transport_block
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/pusch_chain.mojo::nr_pusch_decode_waveform
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/pucch_chain.mojo::nr_pucch_format2_encode
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/pucch_chain.mojo::nr_pucch_format2_decode
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/pbch.mojo::nr_pbch_encode
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/wireless/nr/pbch.mojo::nr_pbch_decode
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_default_formats
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_reference
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_result_checksum
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_scale_trace_text
nr|NR_TS38211_TS38212_bounded_channel_facades|wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_canonical_rtl_vectors
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_bcc_reference.mojo::fixed_wifi_bcc_canonical_rtl_vectors
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_bcc_reference.mojo::fixed_wifi_bcc_encode
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_bcc_reference.mojo::fixed_wifi_bcc_hard_llrs_raw
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_phy_reference.mojo::fixed_wifi_bcc_ofdm_reference
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_bcc_reference.mojo::fixed_wifi_bcc_result_checksum
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_bcc_reference.mojo::fixed_wifi_bcc_viterbi_decode_hard
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_bcc_reference.mojo::fixed_wifi_bcc_viterbi_decode_soft
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_phy_reference.mojo::fixed_wifi_phy_canonical_rtl_vectors
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_phy_reference.mojo::fixed_wifi_phy_result_checksum
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_legacy_reference.mojo::fixed_wifi_legacy_reference
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_legacy_reference.mojo::fixed_wifi_legacy_result_checksum
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_legacy_reference.mojo::fixed_wifi_legacy_canonical_rtl_vectors
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_acquired_reference.mojo::fixed_wifi_acquired_receive
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_acquired_reference.mojo::fixed_wifi_acquired_reference
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_acquired_reference.mojo::fixed_wifi_acquired_result_checksum
wifi|Legacy_OFDM_fixed_reference_artifacts|wireless_dsp/backend/fixed_wifi_acquired_reference.mojo::fixed_wifi_acquired_canonical_rtl_vectors
bluetooth|Bluetooth_LE_coded_exact_pattern_inverse|wireless_dsp/wireless/bluetooth/le_coded.mojo::bluetooth_le_coded_pattern_demap_exact
bluetooth|Bluetooth_LE_coded_known_boundary_hard_FEC_reference_RX|wireless_dsp/wireless/bluetooth/le_coded.mojo::bluetooth_le_coded_packet_fec_decode_hard_reference
bluetooth|Bluetooth_LE_GFSK_normative_parameter_limits|wireless_dsp/wireless/bluetooth/gfsk.mojo::bluetooth_le_gfsk_limits
bluetooth|Bluetooth_LE_GFSK_normative_parameter_limits|wireless_dsp/wireless/bluetooth/gfsk.mojo::bluetooth_le_gfsk_modulation_index_is_compliant
bluetooth|Bluetooth_LE_GFSK_normative_parameter_limits|wireless_dsp/wireless/bluetooth/gfsk.mojo::bluetooth_le_gfsk_frequency_deviation_is_compliant
bluetooth|Bluetooth_LE_GFSK_normative_parameter_limits|wireless_dsp/wireless/bluetooth/gfsk.mojo::bluetooth_le_gfsk_timing_is_compliant
bluetooth|Bluetooth_LE_GFSK_normative_parameter_limits|wireless_dsp/wireless/bluetooth/gfsk.mojo::bluetooth_le_gfsk_bit_deviation_sign_is_compliant
bluetooth|Bluetooth_LE_GFSK_normative_parameter_limits|wireless_dsp/wireless/bluetooth/gfsk.mojo::bluetooth_le_gfsk_stable_claim_is_compliant
bluetooth|Bluetooth_Classic_BR_EDR_header_HEC|wireless_dsp/wireless/bluetooth/br_edr_hec.mojo::bluetooth_br_edr_hec_generate
bluetooth|Bluetooth_Classic_BR_EDR_header_HEC|wireless_dsp/wireless/bluetooth/br_edr_hec.mojo::bluetooth_br_edr_hec_check
EOF
sort -u -o "${semantic_owners_file}" "${semantic_owners_file}"

# These facade identities require both TS 38.211 and TS 38.212 and therefore
# must not reappear in either single-spec generic core row.  Scenario-specific
# Feature rows may continue to reuse them.
cat > "${facade_sources_file}" <<'EOF'
wireless_dsp/wireless/nr/control.mojo::nr_pdcch_encode
wireless_dsp/wireless/nr/pdsch_chain.mojo::nr_pdsch_encode_transport_block
wireless_dsp/wireless/nr/pdsch_chain.mojo::nr_pdsch_decode_grid_comb2
wireless_dsp/wireless/nr/pdsch_chain.mojo::nr_pdsch_decode_waveform_comb2
wireless_dsp/wireless/nr/pusch_chain.mojo::nr_pusch_encode_transport_block
wireless_dsp/wireless/nr/pusch_chain.mojo::nr_pusch_decode_waveform
wireless_dsp/wireless/nr/pucch_chain.mojo::nr_pucch_format2_encode
wireless_dsp/wireless/nr/pucch_chain.mojo::nr_pucch_format2_decode
wireless_dsp/wireless/nr/pbch.mojo::nr_pbch_encode
wireless_dsp/wireless/nr/pbch.mojo::nr_pbch_decode
wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_default_formats
wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_reference
wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_result_checksum
wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_scale_trace_text
wireless_dsp/backend/fixed_nr_pdsch_reference.mojo::fixed_nr_pdsch_canonical_rtl_vectors
EOF
sort -u -o "${facade_sources_file}" "${facade_sources_file}"

cat > "${expected_required_file}" <<'EOF'
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|2B.1.2.1;2B.6.5.4.1;2B.6.5.4.13;2B.6.6.2;2B.7.1.2;2G.5;2G.6.1;2G.6.2|Bluetooth_Classic_BR_EDR_raw_ACL_payload_CRC16|BR/EDR raw ACL payload CRC-16 generation and zero-remainder checking|conditional|Caller-prepared one-through-1027-octet CRC-stage payload bytes and caller-selected 8-bit UAP or DCI|MISSING|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|IMPLEMENTATION_MISSING: exact leaf clauses and official Part G vectors are qualified, but no production raw payload CRC API or evidence exists yet
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|Vol 6 Parts B,D,F|Bluetooth_LE|LE PHY packet, coding, modulation and deterministic Link Layer procedures|mixed|LE 1M, LE 2M and LE Coded S=2/S=8 adopted Core profiles|MISSING|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|IMPLEMENTATION_MISSING: company implementation rights are bound to the pinned adopted Core 6.3 artifact; the broad LE family remains unimplemented, and RF, antenna, OTA, controller policy and qualification are excluded
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|Vol 2 Parts B,C|Bluetooth_Classic_BR_EDR|BR/EDR packet, coding, modulation, AFH and deterministic baseband timing|mixed|Basic Rate and Enhanced Data Rate adopted Core profiles|MISSING|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|IMPLEMENTATION_MISSING: company implementation rights are bound to the pinned adopted Core 6.3 artifact; BR/EDR remains unimplemented, and profiles, host policy, RF, antenna, OTA and qualification are excluded
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|2B.1.2.1;2B.6.4.6;2B.6.5.1.1;2B.7.1.1;2G.4|Bluetooth_Classic_BR_EDR_header_HEC|BR/EDR 10-bit header Error Check generation and zero-remainder validation|mandatory|Every BR/EDR packet header except headerless ID; caller supplies ten wire-order header-information bits and the selected 8-bit UAP or DCI|COMPLETE|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|Exact leaf-scoped raw header-information HEC only; Access Code, header field and TYPE semantics, complete header validity, whitening, rate-one-third FEC, payload CRC, packet assembly, ARQ, AFH, clock and timing state, security and RF are excluded
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|6A.1;6B.1.2;6B.1.4;6B.2.1;6B.3.1;6B.3.2;6C.4;6C.4.1;6C.4.2.1;6C.4.2.2;6C.4.3.1|Bluetooth_LE_uncoded_packet_bit_chain|LE 1M and LE 2M preamble, caller-owned Access Address and PDU, CRC24, whitening and inverse packet checkpoints|mixed|Uncoded LE packet-bit domain with mandatory LE 1M or optional LE 2M, 2 through 258-octet caller-owned PDU, physical channel 0 through 39, 24-bit CRCInit and exact packet length|COMPLETE|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|Exact packet-bit serialization and validation only; LE 1M support is mandatory and LE 2M support optional, while Access Address generation/admissibility, PDU semantics, GFSK, acquisition/reference RX, encryption, CTE, scheduling, deterministic Link Layer state, RF and qualification are excluded
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|6A.1;6B.1.2;6B.1.4;6B.2.2;6B.3.1;6B.3.2;6B.3.3;6C.2|Bluetooth_LE_coded_TX_packet_symbol_chain|LE Coded S=2 and S=8 preamble, caller-owned Access Address and PDU, CRC24, whitening, two terminated K=4 FEC blocks and pattern mapping|optional|2 through 257-octet opaque post-encryption PDU boundary, physical channel 0 through 39, CRCInit24, caller-owned AA32 and coding S in 2 or 8|COMPLETE|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|Only the optional LE Coded capability's exact transmit-symbol chain is in scope; when supported its packet coding rules are mandatory, while PDU and Link Layer semantics, Access Address generation/admissibility, GFSK, acquisition/reference RX, demapping/decoding, encryption, CTE, scheduling, RF and qualification are excluded
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|6A.1;6B.3.3;6C.2|Bluetooth_LE_coded_exact_pattern_inverse|Exact inverse of the S=2 and S=8 pattern mapper on legal hard received codewords|optional|LE Coded S2 binary identity observations and S8 four-symbol groups restricted to exactly 0011 or 1100; empty input allowed|COMPLETE|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|Exact inverse only on legal binary hard codewords; rejecting the other fourteen S8 groups is the bounded exact-profile API contract rather than a claim that the Core specifies a unique noisy receiver response
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|6A.1;6B.1.2;6B.2.2;6B.3;6B.3.1;6B.3.2;6B.3.3;6C.2|Bluetooth_LE_coded_known_boundary_hard_FEC_reference_RX|Known-packet-boundary hard-codeword pattern demapping and terminated K=4 reference FEC decoding through whitened PDU and CRC bits|optional|Exact binary packet-symbol observations with 80-symbol preamble, fixed S8 block one, CI-selected S2 or S8 block two and PDU length 2 through 257 octets|COMPLETE|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|Core packet geometry code and receive-stage ordering are normative; known packet boundary exact hard symbols Viterbi metric tie breaking preamble comparison and malformed-codeword policy are explicitly reference choices
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|6A.1;6A.3.1;6A.3.1.1|Bluetooth_LE_GFSK_normative_parameter_limits|LE 1M and LE 2M symbol-rate, BT, modulation-index, stable-index, frequency-deviation, timing-accuracy and zero-crossing limits|mixed|Mandatory LE 1M and optional LE 2M single-bit-per-symbol GFSK parameter rows; Channel Sounding LE 2M 2BT is excluded|COMPLETE|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|Exact adopted parameter rows and predicates only; RF power ramp spectrum antenna OTA qualification LE 2M 2BT Channel Sounding and every discrete waveform or receiver choice are excluded
bluetooth|6.3 adopted|Bluetooth Core Specification 6.3|6A.1;6A.3.1;6A.4.6|Bluetooth_LE_nominal_GFSK_reference_waveform_and_known_timing_RX|Analytic nominal h=0.5 BT=0.5 GFSK reference waveform and known-timing zero-CFO hard reference receiver|not_applicable|LE 1M and LE 2M opaque uncoded packet bits with an explicitly selected bounded samples-per-symbol analytic profile|MISSING|https://www.bluetooth.com/specifications/specs/core-specification-6-3/|IMPLEMENTATION_MISSING: the adopted parameter and receiver-test-signal clauses are qualified, but the standard does not uniquely specify a discrete Gaussian filter, initial phase, sampling convention or receiver algorithm
ieee802154|2024 active|IEEE Std 802.15.4-2024|Published PHY, MAC and HRP UWB clauses; exact clause map blocked|IEEE_802_15_4_PHY_MAC_UWB|O-QPSK, sub-GHz, SUN and UWB PHY chains plus deterministic MAC, TSCH and ranging procedures|mixed|Published IEEE 802.15.4-2024 PHY/MAC profiles and standard-defined ranging arithmetic|MISSING|https://standards.ieee.org/ieee/802.15.4/11041/|BLOCKED_METADATA: company implementation rights are confirmed, but the final artifact, hash, exact clause map and errata receipt are absent; only published discrete CPU algorithms would be in scope, while RF, antenna, OTA, product policy and certification are excluded
ieee802154|2024 active adoption|IEEE/ISO/IEC 8802-15-4-2024|Adopted 2020-edition PHY, MAC and ranging clauses; exact clause map blocked|IEEE_ISO_IEC_8802_15_4_2020_adoption|O-QPSK, sub-GHz, SUN and UWB PHY chains plus deterministic MAC, TSCH and ranging procedures present in the adopted 2020 baseline|mixed|Published international adoption of the 2020 IEEE base revision; later IEEE Std 802.15.4-2024 revision-only changes are outside this identity|MISSING|https://standards.ieee.org/ieee/8802-15-4/11701/|BLOCKED_METADATA: company implementation rights are confirmed, but the adopted artifact, hash, exact clause map and errata receipt are absent; only published discrete CPU algorithms in this exact adoption would be in scope
matter|1.6 released|Matter Core Specification 1.6|Annex A|Matter_1_6_core|Message, interaction, security-counter, commissioning, timer and fragmentation state algorithms|mixed|Published Matter 1.6 deterministic core protocol behavior|MISSING|https://csa-iot.org/wp-content/uploads/2026/06/23-27349-011_Matter-1.6-Core-Specification.pdf|IMPLEMENTATION_MISSING: the official Revision 11 PDF/hash, company rights, reviewed anonymous-integer clauses and errata receipt are qualified; certificates, cloud services, product policy, RF and certification are excluded
thread|1.4.1 released|Thread Specification 1.4.1|Published protocol clauses; exact clause map blocked|Thread_1_4_network_stack|Frame, addressing, routing, security-counter, commissioning, timer and fragmentation state algorithms|mixed|Published Thread 1.4.1 deterministic network-stack behavior|MISSING|https://threadgroup.org/ThreadSpec|BLOCKED_METADATA: company implementation rights and required terms are confirmed, but the final artifact, hash, release date, exact clauses and errata receipt are absent; only published CPU protocol algorithms would be in scope
zigbee|R23.2 released|Zigbee Core Specification R23.2|3|Zigbee_R23_2_core|Frame, addressing, routing, security-counter, commissioning, timer and fragmentation state algorithms|mixed|Published Zigbee Core R23.2 deterministic network behavior|MISSING|https://csa-iot.org/wp-content/uploads/2025/11/docs-06-3474-23-csg-zigbee-specificationR23.2_clean.pdf|IMPLEMENTATION_MISSING: the official clean-release PDF/hash, company rights, reviewed NWK base-header clauses and incorporated CCB receipt are qualified; certificate lifecycle, product policy, RF and certification are excluded
matter|1.6 released|Matter Core Specification 1.6|Annex A.1;Annex A.2.3;Annex A.4;Annex A.6;Annex A.7;Annex A.7.1;Annex A.7.2;Annex A.8.5;Annex A.11.1;Annex A.12;Table 127|Matter_1_6_TLV_anonymous_integer_codec|Anonymous signed and unsigned integer TLV control-octet, explicit-width little-endian encode and strict top-level decode|mandatory|Anonymous-tag signed and unsigned integer elements with caller-selected width 1, 2, 4 or 8 octets and exact complete-element shape|COMPLETE|https://csa-iot.org/wp-content/uploads/2026/06/23-27349-011_Matter-1.6-Core-Specification.pdf|Only explicit-width anonymous integer TLV elements are in scope; automatic shortest-width policy, other tags and element types, containers, schemas, interaction/session/security/commissioning/transport behavior are excluded
zigbee|R23.2 released|Zigbee Core Specification R23.2|1.2.3;1.4.2;3.3;3.3.1;3.3.1.1;3.3.1.1.1-3.3.1.1.8;3.3.1.2-3.3.1.5;3.3.2.1;3.3.2.1.1;Table 1-5;Table 3-51;Table 3-52;Table 3-53;Table 3-66;Table 3-80|Zigbee_R23_2_NWK_unsecured_unicast_data_base_header|Fixed eight-octet Zigbee Pro NWK unicast data base-header encode and strict receive parse|mandatory|Protocol-version-two unicast data frame with no NWK security, source route, multicast or optional IEEE addresses; caller-owned payload and routing state|COMPLETE|https://csa-iot.org/wp-content/uploads/2025/11/docs-06-3474-23-csg-zigbee-specificationR23.2_clean.pdf|Only the fixed unsecured unicast NWK base header is in scope; broadcast, source routing, commands, Inter-PAN, Green Power, security, route policy, APS, ZDO, TLV, 802.15.4 MAC/PHY and certification are excluded
lte|Rel-18|3GPP TS 36.101 V18.13.0|Annex B|LTE_channel_profiles|EPA, EVA and ETU absolute-delay power-delay profile lookup and seeded Jakes realization|conditional|SISO EPA5, EVA5, EVA70, ETU70 and ETU300 reference profiles|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/36_series/36.101/36101-id0.zip|SISO Annex-B tapped profiles and the published maximum-Doppler combinations are in scope; RF requirements, MIMO correlation matrices and conformance thresholds are excluded
lte|Rel-18|3GPP TS 36.211 V18.0.2|4.2;5.2;5.3;5.5;5.7;6.2;6.3;6.10|LTE_PHY_subset|FDD normal-CP SISO timing, synchronization, reference sequences, scrambling, SC-FDMA, bounded uplink reference signals and SISO resource mapping|mixed|15-kHz FDD normal CP, all six LTE bandwidths, ports 0-3 CRS, SISO PDSCH/PUSCH, direct 1-110-RB PUSCH DM-RS and one-root unrestricted PRACH format 0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/36_series/36.211/36211-i02.zip|Only the declared CPU baseband subset is in scope; TDD, hopping and OCC derivation, scheduler-owned reservations, MBSFN, sidelink, NB-IoT, eMTC, carrier aggregation and multi-antenna procedures are excluded; the separate IFDMA/sub-RB sequence lengths in Tables 5.5.1.2-3/-4 are excluded from this broad integer-RB row and covered only by their separate exact Feature row
lte|Rel-18|3GPP TS 36.211 V18.0.2|5.5.1.2;Table 5.5.1.2-3;Table 5.5.1.2-4|LTE_TS36211_IFDMA_short_base_sequences|Caller-resolved length-6 and length-18 PUSCH DM-RS short base-sequence phase-table lookup and complex construction|conditional|Group number 0 through 29, sequence number v=0 and an exact caller-resolved reference-signal length of 6 or 18 subcarriers|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/36_series/36.211/36211-i02.zip|Only Tables 5.5.1.2-3 and 5.5.1.2-4 after the caller has resolved IFDMA applicability and exact sequence length are in scope; delta or m derivation, RRC or DCI applicability, hopping, cyclic shift, OCC, resource mapping, Tables 5.5.2.1.1-3/-4 and clause 5.5.2.1A sub-PRB procedures are excluded
lte|Rel-18|3GPP TS 36.212 V18.1.0|5.1.1-5.1.4|LTE_channel_coding_subset|CRC attachment, code-block segmentation and concatenation, tail-biting convolutional coding, QPP interleaving, turbo coding and circular-buffer rate matching or recovery|mixed|Readable CPU reference for standardized QPP sizes, LTE CRC catalogue, K=7 rate-1/3 tail biting and bounded turbo code blocks with RV0-RV3|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/36_series/36.212/36212-i10.zip|The declared coding primitives and their direct compositions are in scope; complete transport-channel facades, HARQ policy, optimized iterative decoding and every narrowband variant are excluded
lte|Rel-18|3GPP TS 36.213 V18.3.0|7.1.6;7.1.7;8.1;8.6|LTE_resource_procedure_subset|Base downlink and uplink MCS or RV tables, traditional TBS lookup, Type-0 downlink resource-block groups and contiguous-uplink RIV arithmetic|mixed|Base MCS rows, traditional numeric TBS indices 0-26 plus named 26A over 1-110 RB, Type-0 downlink allocation and canonical contiguous-uplink allocation|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/36_series/36.213/36213-i30.zip|Pure decoded-configuration calculations are in scope; the extended current 44-row TBS table, scheduler, HARQ state, power-control loop, random-access state and MAC interaction are excluded
lte|Rel-18|3GPP TS 36.214 V18.1.0|5.1;5.2|LTE_linear_measurements|Linear-domain RSRP, RSSI, RSRQ and RS-SINR formulas over caller-supplied selected observations|mandatory|Finite nonempty caller-selected CRS and interference observations with explicit resource-block and OFDM-symbol counts|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/36_series/36.214/36214-i10.zip|Only the declared linear formulas after caller-owned RE selection are complete; measurement scheduling, filtering, reporting events, RF acquisition, calibration and conformance tolerances are excluded
lte|Rel-18|3GPP TS 36.133 V18.14.0|4.2.2.1;Table 4.2.2.1-1|LTE_TS36133_non_eDRX_serving_cell_RRM|Non-eDRX serving-cell measurement minimum spacing, Nserv lookup and all-neighbour measurement trigger|mandatory|RRC_IDLE without eDRX, DRX cycles 320/640/1280/2560 ms and a nonnegative consecutive serving-cell failure count|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/36_series/36.133/36133-ie0.zip|Only caller-decoded non-eDRX RRC_IDLE arithmetic is in scope; eDRX/PTW, RF measurement acquisition, filtering implementation, cell search/reselection state, inter-frequency/inter-RAT requirements and conformance apparatus are excluded
nr|Rel-17|3GPP TS 38.300 V17.17.0|16.13.1-16.13.5|NR_redcap (UID 900062; Core UID 900162)|RedCap definition, capability, access, camping, early-identification, RRM-relaxation and BWP constraints|mandatory|standalone single-band Rel-17 RedCap|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.300/38300-hh0.zip|Decoded Rel-17 RedCap stage-2 capability, access, camping and BWP decisions are in scope; network policy, RF and a complete RRC or NG-RAN stack are excluded
nr|Rel-17|3GPP TS 38.306 V17.16.0|4.2.21.1|NR_redcap (UID 900062; Core UID 900162)|Rel-17 RedCap hard capability and profile validation|mandatory|FR1 maximum capability exactly 20 MHz with Rx/DL=(1,1) or (2,2); FR2 exactly 100 MHz with Rx=2 and DL=1 or 2; Tx=1 and UL=1|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/38_series/38.306/38306-hg0.zip|Capability arithmetic and validation only; serving-cell/BWP bandwidth is a separate configuration and ASN.1 encoding is excluded
nr|Rel-17|3GPP TS 38.306 V17.16.0|4.2.21.2-4.2.21.7|NR_redcap (UID 900062; Core UID 900162)|Mandatory feature bundle and optional capability dependency validation|mixed|separate initial DL/UL BWP; Msg1, conditional MsgA and Msg3 early indication; optional HD-FDD type A|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/38_series/38.306/38306-hg0.zip|Decoded capability declarations and dependencies are complete for clauses 4.2.21.2 through 4.2.21.7; PDCP, RLC, SON and full RRC protocol behavior remain outside this validator
nr|Rel-17|3GPP TS 38.331 V17.17.0|5.2.2.3.3;5.2.2.3.3a;5.2.2.4.1;5.2.2.4.2;5.2.2.4.5;5.2.2.5;6.3.1;6.3.2;6.3.3|NR_redcap (UID 900062; Core UID 900162)|IFRI, Rx and HD barring, RedCap inter-frequency access, early-RA resources, initial BWP, PDCCH, CSS, CORESET, PUCCH and CD or NCD-SSB decoded configuration|mixed|RRC_IDLE, RRC_INACTIVE and RRC_CONNECTED decoded configuration projection|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-hh0.zip|Decoded deterministic configuration and IDLE or INACTIVE access outcomes are in scope; ASN.1, RF or SI acquisition itself, a full RRC state machine and connected T311 orchestration are excluded
nr|Rel-17|3GPP TS 38.211 V17.10.0|5.3.2|NR_redcap (UID 900062; Core UID 900162)|PRACH baseband placement relative to initialUplinkBWP-RedCap|mandatory|separate RedCap initial uplink BWP|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.211/38211-ha0.zip|Exact Table-6.3.3.2-1 PRACH-to-PUSCH-SCS allocation, Msg1/MsgA FDM numbering, complete initialUplinkBWP-RedCap containment and normalized sequence-sample composition are in scope; RRC decoding, time-domain occasion scheduling, RF and time-continuous radio-rate OFDM synthesis are excluded
nr|Rel-17|3GPP TS 38.212 V17.13.0|5.1;5.2.1-5.2.2;5.3.1-5.3.3;5.4.1-5.4.3;6.3.1.2-6.3.1.5|NR_redcap (UID 900062; Core UID 900162)|Inherited CRC, Polar, LDPC and UCI coding used by declared RedCap chains|mandatory-by-inheritance|bounded RedCap PDCCH, PDSCH, PUSCH and PUCCH composition|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.212/38212-hd0.zip|No invented RedCap coding delta; feature-profile composition evidence is still required
nr|Rel-17|3GPP TS 38.213 V17.13.0|17;17.1|NR_redcap (UID 900062; Core UID 900162)|Initial BWP selection, CORESET/search-space monitoring, common PUCCH and CD/NCD-SSB rules|mandatory|standalone single-band separate initial DL/UL BWP|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-hd0.zip|Finite decoded-configuration and search-space calculations are in scope; monitoring occasions and RRC state are not approximated
nr|Rel-17|3GPP TS 38.213 V17.13.0|17.2|NR_redcap (UID 900062; Core UID 900162)|Half-duplex paired-spectrum TX/RX conflict, cancellation and guard-symbol eligibility|optional|FR1 FDD halfDuplexFDD-TypeA-RedCap-r17|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-hd0.zip|Decoded-symbol and exact-Tc conflict decisions are complete for the declared FR1 HD-FDD Type-A profile; RRC/DCI field decoding and RF switching are outside this algorithm
nr|Rel-17|3GPP TS 38.214 V17.16.0|6.1.2.1;6.1.2.3.1;6.1.2.3.3;6.1.7;6.4|NR_redcap (UID 900062; Core UID 900162)|HD-UE PUSCH valid-slot counting, Tproc2, single-layer repetition or multi-slot TB constraints and DM-RS bundling windows|conditional|Rel-17 RedCap HD-FDD type A with one uplink layer|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/38214-hg0.zip|Exact-Tc timing, grant-profile-aware RedCap slot selection and RedCap-specific TDW events are in scope; generic clause-6.1.7 event classification remains separate
nr|Rel-17|3GPP TS 38.214 V17.16.0|6.4|NR_redcap_HD_Tproc2|Complete PUSCH processing-time tables and exact-Tc Tproc2 derivation|conditional|Decoded PUSCH processing capability 1 or 2 over every table-supported numerology; Rel-17 RedCap wrapper uses capability 1|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/38214-hg0.zip|Decoded timing inputs and exact integer Tc arithmetic only; DCI/RRC field decoding, scheduler policy and RF switching are outside this calculation
nr|Rel-17|3GPP TS 38.215 V17.5.0|5.1.1-5.1.6|NR_redcap (UID 900062)|SS/CSI RSRP, RSRQ, SINR and RSSI reused without a RedCap formula delta|mandatory-by-inheritance|caller-selected RedCap CD/NCD-SSB and CSI observations|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/38_series/38.215/38215-h50.zip|Inherited linear SS/CSI measurement equations and explicit Rel-17 CD/NCD-SSB capability selection are complete; scheduling, filtering, RF acquisition and reporting state belong to their owning specifications
nr|Rel-18|3GPP TS 38.306 V18.10.0|4.2.22|eRedCap (NR_redcap_enh Core UID 970180)|eRedCap hard capability and reduced-baseband scheduling validation|mandatory|FR1 maximum capability exactly 20 MHz, 15/30 kHz SCS, Rx/DL <=2, Tx/UL=1, reduced-BB PRB limits 25 or 12|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.306/38306-ia0.zip|Rel-18 eRedCap is a separate FR1 profile; 60 kHz, FR2, NCR and excess reduced/full-baseband PRBs are rejected
nr|Rel-17|3GPP TS 38.133 V17.22.0|4.2B;5.1B|NR_redcap-Perf (UID 900262; WID RP-220966)|RedCap cell-reselection measurement scheduling and relaxed-measurement criteria|mixed|1Rx/2Rx FR1; 2Rx FR2; RRC_IDLE/RRC_INACTIVE|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-hm0.zip|Decoded one-/two-Rx monitoring minima, exact serving-cell schedule tables, stationary and low-mobility reference state, strict P/Q gates, combine policies, exact K1/K4 timing rows, one-hour/four-hour gates and bounded scenario transitions are in scope; effective-T selection, idle long-eDRX cross-PTW placement, RF acquisition, RRC ASN.1 and conformance apparatus are excluded
nr|Rel-17|3GPP TS 38.133 V17.22.0|5.2B;5.7B;6.1D;6.2.1B;6.2.2B;6.2.3A;7.1A;7.2A;7.3A;7.7A|NR_redcap-Perf (UID 900262; WID RP-220966)|CG-SDT/RA-SDT applicability, handover, re-establishment, random-access timing and timing-advance decisions|mixed|SA RedCap FR1/FR2 and conditional SDT|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-hm0.zip|Generic PRACH and timing arithmetic are reusable; RRC state, RF timing acquisition and conformance apparatus are excluded
nr|Rel-17|3GPP TS 38.133 V17.22.0|8.1B;8.5B;8.6A;8.10B;8.12A;8.13A|NR_redcap-Perf (UID 900262; WID RP-220966)|RLM, beam-failure and candidate-beam detection, plus BWP, TCI, spatial-relation and CBW switching delays|mixed|RRC_CONNECTED RedCap with SSB/CSI-RS in FR1/FR2|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-hm0.zip|Exact decoded-configuration evaluation/reporting arithmetic and RLM/BFD L1 aggregation are in scope; RF sample acquisition, Qout/Qin BLER derivation, measurement-gap/SMTC derivation of P, L3 filtering and RF switching are excluded from this kernel
nr|Rel-17|3GPP TS 38.133 V17.22.0|9.1A;9.2B;9.3B;9.4A;9.5B;9.11A;10.1A;10.2A|NR_redcap-Perf (UID 900262; WID RP-220966)|Gap, scaling and report scheduling plus NR/E-UTRA RSRP, RSRQ, SINR and L1-RSRP accuracy evaluation|mixed|RedCap intra-frequency, inter-frequency, inter-RAT and autonomous-gap cases|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-hm0.zip|Measurement arithmetic is reusable; RF apparatus and certification are excluded
nr|Rel-17|3GPP TS 38.133 V17.22.0|A.3.9A;A.3.10B;A.3.11A;A.3.35;A.16-A.18;B.1.4-B.1.5;B.2.15-B.2.16|NR_redcap-Perf (UID 900262; WID RP-220966)|Official RedCap BWP, SSB, SMTC and FR1/FR2/E-UTRA static test-oracle tables|mixed|FR1 patterns 1-7; FR2 patterns 1-5; SMTC patterns 1-4; A.16/A.17/A.18 family selector; published Annex-B condition expressions|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-hm0.zip|Exact A.3.9A BWP, A.3.10B SSB, A.3.11A SMTC, A.3.35 family selection and bounded Annex-B condition expressions are in scope; remaining A.16-A.18 test-case-specific static catalogs remain in scope, while RF, fading, laboratory apparatus and certification are excluded
nr|Rel-17|3GPP TS 38.508-1 V17.11.0|1;4|NR_redcap_plus_ARCH-UEConTest (UID 950066; WID RP-240053)|Common conformance environment and RedCap fixture applicability|not_applicable|Rel-17 UE conformance environment|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.508-1/38508-1-hb0.zip|Core-network and laboratory conformance harness is not a production algorithm; bounded digital fixtures may be reused as evidence
nr|Rel-17|3GPP TS 38.508-2 V17.11.0|1;4|NR_redcap_plus_ARCH-UEConTest (UID 950066; WID RP-240053)|ICS and PICS applicability declaration for RedCap|not_applicable|Rel-17 RedCap capability declaration paperwork|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.508-2/38508-2-hb0.zip|ICS paperwork is not a production algorithm; decoded capability projection may be used as audit evidence
nr|Rel-17|3GPP TS 38.521-1 V17.11.0|1;4|NR_redcap_plus_ARCH-UEConTest (UID 950066; WID RP-240053)|FR1 RF transmission and reception conformance|not_applicable|Range-1 standalone RedCap RF conformance|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.521-1/38521-1-hb0.zip|RF, OTA, laboratory apparatus and certification are excluded; bounded digital stimuli may be reused as oracles
nr|Rel-17|3GPP TS 38.521-2 V17.5.0|1;4|NR_redcap_plus_ARCH-UEConTest (UID 950066; WID RP-240053)|FR2 RF transmission and reception conformance|not_applicable|Range-2 standalone RedCap RF conformance|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.521-2/38521-2-h50.zip|RF, OTA, laboratory apparatus and certification are excluded; bounded digital stimuli may be reused as oracles
nr|Rel-17|3GPP TS 38.521-3 V17.11.0|1;4|NR_redcap_plus_ARCH-UEConTest (UID 950066; WID RP-240053)|FR1/FR2 interworking RF conformance|not_applicable|RedCap interworking with other radios|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.521-3/38521-3-hb0.zip|Multi-radio RF, OTA, laboratory apparatus and certification are excluded
nr|Rel-17|3GPP TS 38.521-4 V17.5.0|1;4|NR_redcap_plus_ARCH-UEConTest (UID 950066; WID RP-240053)|RedCap RF and demodulation-performance conformance execution|not_applicable|Rel-17 UE laboratory conformance scope|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.521-4/38521-4-h50.zip|RF/OTA apparatus, calibrated performance thresholds, TTCN execution and certification are outside this CPU DSP library
nr|Rel-17|3GPP TS 38.533 V17.9.0; 3GPP TS 38.533 V18.8.0|3GPP TS 38.533 V17.9.0 clause 4; 3GPP TS 38.533 V18.8.0 clauses 16-18|NR_redcap_plus_ARCH-UEConTest (UID 950066; WID RP-240053)|RedCap FR1, FR2 and inter-RAT RRM finite-state decisions and timing metrics|mixed|Seven named cases and 13 response phases after caller validation: four FR1 10/20-MHz one-/two-Rx fixtures, two FR2 100-MHz 120/240-kHz TDD two-Rx fixtures at no more than 40.8 GHz and PC3, and the eight NR/E-UTRA duplex configurations of 18.2.2.1|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.533/38533-i80.zip|Exact row lookup and target-cell deadline state are in scope only after the caller validates the published case configuration; TTCN, RF instrumentation, detectability and certification are excluded
nr|Rel-17|3GPP TS 38.202 V17.5.0|WID RP-220966 impacted-spec row; final Rel-17 text|NR_redcap (UID 900062; WID RP-220966)|No RedCap-specific physical-layer service delta in the final Rel-17 specification|not_applicable|WID traceability only|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.202/38202-h50.zip|TS 38.202 is an overview specification and contributes no RedCap-specific production algorithm
nr|Rel-17|3GPP TS 38.304 V17.11.0|5.2.4.4;5.2.4.7.0;5.2.4.9.0-5.2.4.9.4;5.3.1|NR_redcap (UID 900062; Core UID 900162)|RedCap IFRI, Rx and HD barring and candidate or timer orchestration plus relaxed-measurement, stationary, low-mobility and bounded reselection decisions|mixed|RRC_IDLE/RRC_INACTIVE Rel-17 RedCap; FR1 1Rx/2Rx, FR2 2Rx; optional FR1 HD-FDD access|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.304/38304-hb0.zip|Decoded RedCap-specific access and barring, monotonic timers, stationary and low-mobility criteria are in scope; RF, ASN.1, ordinary PLMN or SNPN or CAG reservation rules and complete idle-mode orchestration are excluded
nr|Rel-17|3GPP TS 38.321 V17.15.0|5.1.1b;5.1.1c;5.1.1d;5.1.2;5.1.2a;5.15.1;5.27;Table 6.2.1-2|NR_redcap (UID 900062; Core UID 900162)|Random-access feature-set selection, RedCap initial-BWP switching and inactivity target, RA-SDT BWP binding and RedCap CCCH LCID mapping|mixed|Rel-17 RedCap CBRA, optional two-step RA and conditional RA-SDT|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-hf0.zip|Decoded finite MAC decisions are in scope; RF measurements and a complete MAC/RRC stack are excluded
nr|Rel-17|3GPP TS 38.413 V17.15.0|8.4.2;8.4.4.2;9.2.3.5;9.2.3.8;9.3.1.2;9.3.1.228|NR_redcap (UID 900062; Core UID 900162)|Optional NGAP RedCap Indication carriage and RedCap-UE-not-supported cause handling|optional|NG-RAN handover and path-switch control plane|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.413/38413-hf0.zip|NGAP procedures and ASN.1 transport are outside the CPU DSP algorithm scope
nr|Rel-17|3GPP TS 38.101-1 V17.22.0|5.3I;5.4I.1-5.4I.4|NR_redcap (UID 900062; Core UID 900162)|FR1 RedCap channel-bandwidth, transmission-bandwidth, SCS and NR-ARFCN raster legality validation|mandatory|FR1 at most 20 MHz with one or two Rx branches; FDD, TDD and conditional HD-FDD|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.101-1/38101-1-hm0.zip|Finite profile and raster validation is in scope; RF transmit power and front-end behavior are excluded
nr|Rel-17|3GPP TS 38.101-1 V17.22.0|6.2I;7.1I;7.2;7.3I|NR_redcap (UID 900062; Core UID 900162)|FR1 RedCap one-Rx/two-Rx and HD-FDD RMC, reference-sensitivity and 95-percent-throughput digital performance oracle composition|mixed|FR1 at most 20 MHz; one or two Rx; conditional HD-FDD; 256QAM only when declared|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.101-1/38101-1-hm0.zip|CPU baseband RMC, channel and BLER/throughput evaluation are in scope; calibrated REFSENS, RF front end and laboratory execution are excluded
nr|Rel-17|3GPP TS 38.101-2 V17.20.0|3.1;5.3.2;5.3.5;6.2.1.0;6.2.1.7;6.6.8;7.3.2.7;7.3.4.7|NR_redcap (UID 900062; Core UID 900162)|FR2 RedCap Power-Class-7 profile, 50/100-MHz bandwidth and beam-correspondence or throughput-oracle applicability|mixed|FR2 two-Rx RedCap with maximum capability 100 MHz and Power Class 7 or another class satisfying 38.306 core requirements|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.101-2/38101-2-hk0.zip|Finite profile plus digital RMC and throughput oracles are in scope; EIRP, TRP, EIS, antenna and OTA execution are excluded
nr|Rel-17|3GPP TS 38.101-4 V17.21.0|5.1.1.11;5.2.1.1.1;5.2.1.2.1;5.2.2.1.17;5.2.2.2.18;5.3.1.1.1;5.3.1.2.1;5.3.2.1.4;5.3.2.2.4;6.1.1.6;6.2-6.4;7.1.1.7;8.1.1.6|NR_redcap (UID 900062; Core UID 900162)|RedCap PDSCH, PDCCH, PBCH, SDR and CQI/PMI/RI digital demodulation-performance vector composition|mixed|One-Rx/two-Rx FR1 FDD, HD-FDD and TDD plus two-Rx FR2; 256QAM conditional on capability|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.101-4/38101-4-hl0.zip|Digital PHY calculations, channel models and bounded performance vectors are in scope; RF apparatus and certification are excluded
nr|Rel-17|3GPP TS 36.133 V17.16.0|4.2.2.5.8;Tables 4.2.2.5.8-1 to -3;4.2.2.14;4A.1.2.8;4A.1.2.9;Tables 4A.1.2.9-1 to -2|NR_redcap-Perf (UID 900262; WID RP-220966)|E-UTRA-side RedCap NR inter-RAT detection, measurement and evaluation timing, sample eligibility and eDRX scaling|mixed|NR-capable E-UTRAN RedCap in IDLE or INACTIVE, FR1/FR2 neighbor and optional eDRX|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/36_series/36.133/36133-hg0.zip|Finite timing, filtering and reselection calculations are in scope; RF sample acquisition is excluded
nr|Rel-17|3GPP TS 38.104 V17.22.0|WID RP-220966 impacted-spec row; final Rel-17 text|NR_redcap (UID 900062; WID RP-220966)|No RedCap-specific base-station RF requirement delta in the final Rel-17 specification|not_applicable|WID traceability only|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.104/38104-hm0.zip|Base-station RF behavior and laboratory apparatus are outside the RedCap CPU DSP feature delta
nr|Rel-17|3GPP TS 38.141-1 V17.19.0|WID RP-220966 impacted-spec row; final Rel-17 text|NR_redcap (UID 900062; WID RP-220966)|No RedCap-specific conducted base-station conformance delta in the final Rel-17 specification|not_applicable|WID traceability only|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.141-1/38141-1-hj0.zip|Conducted RF conformance apparatus and certification are excluded
nr|Rel-17|3GPP TS 38.141-2 V17.21.0|WID RP-220966 impacted-spec row; final Rel-17 text|NR_redcap (UID 900062; WID RP-220966)|No RedCap-specific radiated base-station conformance delta in the final Rel-17 specification|not_applicable|WID traceability only|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.141-2/38141-2-hl0.zip|Radiated RF and OTA conformance apparatus and certification are excluded
nr|Rel-17|3GPP Work Item 860046 (NR_NTN_solutions); 3GPP TS 38.213 V17.13.0; 3GPP TS 38.331 V17.17.0|TS 38.213 4.2;TS 38.331 6.3.2|NR_NTN_solutions (UID 860046)|Service-link range, RTT, radial-velocity and Doppler arithmetic plus common-TA drift, Differential-Koffset and validity checks|mixed|Caller-supplied Rel-17 transparent-payload GEO/non-GEO ECEF state and decoded NTN timing assistance|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860046|Orbit propagation, GNSS acquisition, feeder-link modelling, HARQ/RA state, RF payload behavior and ASN.1 decoding are excluded
nr|Rel-18|3GPP Work Item 941006 (NR_NTN_enh)|RP-240779 objectives 4.1.1-4.1.4; TS 38.213 V18.8.0 clause 22.1; TS 38.321 V18.10.0 clauses 5.8.2 and 5.33; TS 38.331 V18.10.0 clause 6.3.2|NR_NTN_enh (UID 941006; Core UID 941106)|Rel-18 NR NTN coverage, FR2-NTN, network-verified location, mobility and service-continuity enhancements, including RACH-less handover Type-1 CG mapping and threshold decisions|mixed|Published Rel-18 NTN profiles with a bounded FDD RACH-less handover Type-1 CG slice using nonempty decoded 4/8-bit SSB and 8-bit DMRS type-1 subsets, repK=1 and one valid PUSCH occasion per CG period|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=941006|Decoded deterministic CPU decisions over caller-supplied nonempty resource subsets are in scope; RRC ASN.1, NGAP/XnAP/NRPPa stacks, satellite/network deployment policy, RF/OTA and conformance apparatus are excluded
nr|Rel-17|3GPP Work Item 860042 (NR_SL_enh); 3GPP TS 38.211 V17.10.0; 3GPP TS 38.212 V17.13.0; 3GPP TS 38.213 V17.13.0; 3GPP TS 38.331 V17.17.0|TS 38.211 8.3.2.3;8.4.1.3.1-8.4.1.3.2;TS 38.212 7.3.2-7.3.4;8.3;TS 38.213 16.4;TS 38.331 6.3.5|NR_SL_enh (UID 860042)|SCI-1A packing, CRC, Polar/rate matching, PSCCH scrambling/QPSK/DM-RS and bounded resource-element mapping|mixed|One decoded Rel-17 SCI-1A and normal-CP PSCCH code block with fixed Gold initialization and first-symbol copy|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860042|PSSCH/PSFCH, second-stage SCI, sensing/resource selection, congestion control, HARQ, RRC/ASN.1, RF and interoperability are excluded
nr|Rel-18|3GPP RP-232789; TS 38.321 V18.10.0; TS 38.214 V18.10.0; TS 38.331 V18.10.0; TS 38.101-1 V18.14.0|RP-232789 objectives 1 and 4; 38.321 5.22.1.1,5.22.1.2b,5.22.1.11; 38.214 8.1,8.1.4; 38.331 5.8.9.1b,6.3.5; 38.101-1 4.2,5.2E.1A,Table 5.5E.1A.1-1|NR_SL_enh2 (UID 940097; Core UID 940197; Perf UID 940297)|Mode-2 LTE/NR co-channel overlapping-slot admissibility, gated PSFCH/LTE-reservation exclusion, and bounded two-CC SL_n47B carrier-local CA/HARQ validation|mixed|Rel-18-only decoded Mode-2 profile: 15/30 kHz dynamic sharing; qualifying decoded E-UTRA SCI and SL-Thres-RSRP; two intra-band-contiguous n47 carriers in increasing-frequency order with an exact SL_n47B bandwidth pair, same SCS and aligned non-zero PSFCH periods/phases|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=940097|Decoded finite admission decisions only: 30 kHz alignment and first-slot inclusion, qualifying-SCI/RSRP-gated half-open PSFCH overlap, and caller-classified two-CC n47B contiguous CA are in scope; ASN.1/SCI decoding, random choice, scheduler policy, RF waveform and certification are excluded
nr|Rel-17|3GPP Work Item 900060 (NR_pos_enh); 3GPP TS 38.211 V17.10.0; 3GPP TS 38.214 V17.16.0; 3GPP TS 38.215 V17.5.0|TS 38.211 5.2.1;7.4.1.7.2-7.4.1.7.3;TS 38.214 5.1.6.5;TS 38.215 5.1.29-5.1.30;5.2.2-5.2.3|NR_pos_enh (UID 900060)|DL-PRS sequence and mapping plus UL-RTOA, DL-RSTD and UE/gNB Rx-Tx time-difference arithmetic|mixed|Decoded Rel-17 DL-PRS resources and caller-supplied detected timing reference points across the published parameter envelope|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=900060|PRS activation/muting, positioning SRS, RF first-path/timestamp acquisition, AoA/AoD, location solvers and LPP/RRC are excluded
nr|Rel-16|3GPP TS 37.213 V16.14.0|4.1.1;4.1.4.3;4.2.1.1;4.2.2.3;Tables 4.1.1-1,4.2.1-1|NR_unlic (UID 820067; WID RP-201834)|NR-U channel access, listen-before-talk, channel occupancy, discovery reference signal and shared-spectrum scheduling arithmetic|mixed|Decoded DL/UL priority classes 1-4; Type-1 integer arithmetic; caller-declared DL/UL alternative-COT condition, caller-supplied N_init and decoded UL inserted-gap geometry|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/37_series/37.213/37213-ge0.zip|Exact decoded CAPC, Type-1 defer, caller-supplied backoff, allowed-CW/reset, nominal COT and UL p=3/4 Note-2 gap-extension arithmetic are in scope; RF ED/sensing classification, regulation, uniform random generation/distribution and complete scheduling are excluded
nr|Rel-17|3GPP Work Item 860048 (NR_MBS); 3GPP TS 38.211 V17.10.0; 3GPP TS 38.212 V17.13.0; 3GPP TS 38.213 V17.13.0; 3GPP TS 38.214 V17.16.0; 3GPP TS 38.321 V17.15.0; 3GPP TS 38.331 V17.17.0|TS 38.211 4.4.6;TS 38.212 7.3.1.5.1-7.3.1.5.2;TS 38.213 18;Table 18-1;TS 38.214 5.1.2.2.2;TS 38.321 5.3.1;5.8.1a;TS 38.331 5.9.1.3;6.3.2;6.3.6|NR_MBS (UID 860048)|Common-frequency-resource and RIV arithmetic, DCI 4_0/4_1 sizes, MCCH notification, NACK-only PUCCH selection and MBS SPS/HARQ indexing|mixed|Caller-decoded Rel-17 common-frequency resources and finite MBS control/SPS fields|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860048|PDCCH/PDSCH waveforms, DRX, full HARQ state, bearer delivery, core-network control, scheduler policy, RF and conformance are excluded
nr|Rel-17|3GPP Work Item 860040 (NR_feMIMO)|RP-212535 objective 4.1 item 4.b; TS 38.214 V17.16.0 clauses 5.2.2.2.7 and 5.2.3; Table 5.2.2.2.7-1|NR_feMIMO (UID 860040)|Further enhanced Type-II port-selection parameter, RI, combinadic vector-selection, strongest-coefficient, coefficient-priority and nonzero-count calculations|mixed|Decoded typeII-PortSelection-r17 over 4/8/12/16/24/32 CSI-RS ports, every legal paramCombination-r17 row, RI 1-4, M 1/2, valueOfN 2/4 when applicable and R 1/2|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860040|RF antenna hardware and commercial scheduling are excluded; this bounded slice accepts decoded configuration and implements only the exact Further Enhanced Type-II port-selection table, finite combinadic and coefficient-index arithmetic
nr|Rel-18|3GPP TS 38.101-1 V18.14.0; TS 38.101-2 V18.13.0; TS 38.101-4 V18.12.0; TS 38.133 V18.14.0; TS 38.211 V18.9.0; TS 38.212 V18.8.0; TS 38.213 V18.8.0; TS 38.214 V18.10.0; TS 38.215 V18.5.0; TS 38.300 V18.10.0; TS 38.306 V18.10.0; TS 38.321 V18.10.0; TS 38.331 V18.10.0|RP-233028 impacted-spec inventory; feature-specific final-clause and errata mapping remains BLOCKED_METADATA outside the already qualified bounded TS anchors|NR_MIMO_evo_DL_UL (UID 940096; Work Item 940096; RP-233028)|Rel-18 DL and UL MIMO evolution with multiple panels or TRPs, two timing advances, enhanced CSI and up to eight-port uplink signaling|mixed|Published Rel-18 enhanced MIMO and multi-TRP capability profiles|MISSING|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=940096|RF arrays and scheduler policy are excluded; deterministic multi-panel, multi-TRP, CSI, layer and timing calculations remain in scope only after exact final-clause qualification
nr|Rel-17|3GPP Work Item 900061 (NR_cov_enh); 3GPP TS 38.214 V17.16.0|6.1.2.1;6.1.7;Tables 6.1.2.1-1 and 6.1.2.1-1A|NR_cov_enh (UID 900061)|Decoded PUSCH S/L validity, Msg3 repetition, TB-over-multiple-slots selection and nominal/actual DM-RS bundling-window arithmetic|mixed|Rel-17 ordinary-NR decoded PUSCH repetition and TBMS geometry with caller-supplied slot eligibility|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=900061|PUCCH repetition, DCI/RRC decoding, scheduler policy, waveform generation, receiver soft combining and RF are excluded
nr|Rel-19|3GPP Work Item 1020094 (NR_LPWUS); 3GPP RP-251200; ETSI TS 138 211 V19.4.0; ETSI TS 138 212 V19.4.0; ETSI TS 138 213 V19.4.0; ETSI TS 138 214 V19.4.0; ETSI TS 138 215 V19.3.0; ETSI TS 138 321 V19.3.0|RP-251200 objectives 4.1-4.2 and impacted-spec section 5; final per-TS clause and errata join remains BLOCKED_METADATA|NR_LPWUS (UID 1020094)|Low-power wake-up signal sequence, coding, mapping, detection, paging-subgroup and monitoring-occasion calculations|mixed|Frozen Rel-19 PCG-approved LP-WUS scope; current impacted TS identities are known but feature-specific clause and errata qualification is blocked|MISSING|https://www.3gpp.org/ftp/TSG_RAN/TSG_RAN/TSGR_108/Docs/RP-251200.zip|BLOCKED_METADATA: analog always-on receiver, RF power and network paging policy are excluded; deterministic LP-WUS digital PHY and occasion logic remain in scope only after exact final-TS clause and errata qualification
nr|Rel-19|3GPP Work Item 1060084 (Ambient_IoT_Solutions); 3GPP RP-252105; current final TS identity unresolved|RP-252105 objectives 4.1-4.2 and new or impacted-spec section 5; final current TS version, clause and errata reconciliation remains BLOCKED_METADATA|Ambient_IoT_Solutions (UID 1060084)|Ambient-IoT downlink and uplink waveform, coding, modulation, detection, inventory and deterministic access calculations|mixed|Frozen Rel-19 PCG-approved Ambient-IoT scope; current final new-spec and impacted-spec identity reconciliation is blocked|MISSING|https://www.3gpp.org/ftp/TSG_RAN/TSG_RAN/TSGR_109/Docs/RP-252105.zip|BLOCKED_METADATA: energy harvesting, RF backscatter hardware, reader deployment and security backends are excluded; deterministic released digital PHY and finite access algorithms remain in scope only after exact final-TS qualification
nr|Rel-17|3GPP TS 38.211 V17.10.0; TS 38.101-2 V17.20.0; TS 38.104 V17.22.0|38.211 Tables 4.2-1, 4.3.2-1, 6.3.3.2-1; 38.101-2 Tables 5.1-1, 5.2-1, 5.3.2-1, 5.3.3-1, 5.3.5-1, 5.4.1.1, 5.4.2.1-1, 5.4.2.3-2; 38.104 Tables 5.3.2-3, 5.3.3-2a, 5.3.5-3, 5.4.2.3-3|NR_ext_to_71GHz (UID 860041; Core UID 860141)|FR2-2 n263 normal-CP numerology and slot geometry, channel-bandwidth/PRB/guardband legality, L_RA=139 PRACH-to-PUSCH SCS allocation, and NR-ARFCN raster arithmetic|mixed|n263 TDD; normal CP at 120/480/960 kHz; exact 100/400/800/1600/2000 MHz Rel-17 rows with optionality preserved; L_RA=139|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=860041|RF/OTA power, antenna, conformance and regulatory decisions are excluded; exact finite CPU configuration, timing-boundary and raster arithmetic is in scope
wifi|2024 base revision|IEEE Std 802.11-2024|9-11|Deterministic_MAC|DCF/CSMA-CA, NAV, EDCA, retry/CW, fragmentation/reassembly, A-MSDU/A-MPDU, Block Ack, sequence control and power-save state transitions|mixed|CPU-observable MAC state and frame arithmetic across published base families|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|RF carrier sensing and deployment policy are excluded; discrete MAC algorithms and frame/state calculations are in scope
wifi|2024 base revision|IEEE Std 802.11-2024|10.3.4.3-10.3.4.4;10.23.2|DCF_EDCA_contention_arithmetic|AIFS, explicit backoff draw, idle-slot countdown and retry/CW update/reset|mixed|DCF DIFS; AP AIFSN 1-15; non-AP AIFSN 2-15; CW=2^n-1 up to 32767; explicit draw|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|RF carrier sensing, random-number generation, TXOP scheduling and virtual-collision orchestration are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|9.2.4.2;10.3.2.4|NAV_Duration_arithmetic|Normalized Duration/ID NAV update and remaining-time arithmetic|mandatory|One classified 15-bit Duration value and one integral NAV time base|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|Caller classifies Duration/ID; PS-Poll AID encodings and HE dual-NAV policy are outside this row
wifi|2024 base revision|IEEE Std 802.11-2024|9.2.4.4;10.25.6.6|Sequence_Block_Ack_window|Sequence Control packing, modulo-4096 arithmetic and Block Ack receive-window decision|mixed|12-bit SN, 4-bit fragment number and Block Ack window sizes 1-1024|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|ADDBA negotiation, buffer storage, timers and delivery scheduling are outside this arithmetic row
wifi|2024 base revision|IEEE Std 802.11-2024|9.3.2.2;9.7;10.11-10.12|Basic_aggregation_length_planning|Basic A-MSDU and non-null A-MPDU delimiter, offset, padding and length planning|optional|Basic 14-octet A-MSDU subframes with maxima 3839/7935/11454; non-null MPDUs 1-11454; A-MPDU exponent 0-7|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|Short/dynamic A-MSDU, aggregate resynchronization, minimum MPDU start spacing and EOF/null delimiter placement policy remain separate gaps
wifi|2024 base revision|IEEE Std 802.11-2024|10.4-10.5|Base_fragmentation_reassembly|Base individually addressed MSDU/MMPDU fragmentation planning and canonical ordered reassembly validation|conditional|MSDU/MMPDU 1-2304 octets; threshold 256-2346; caller-declared constant overhead 28..threshold-1; 1-16 fragments; SN 0-4095|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|Pure planning and validation only; caller owns header/security-overhead derivation, address/TID grouping, retry duplicate suppression, buffers, timers and transmission scheduling; group-addressed fragmentation and A-MSDU fragmentation are outside this bounded profile
wifi|2024 base revision|IEEE Std 802.11-2024|9.7.1-9.7.2;10.12.7|Non_DMG_MPDU_delimiter|Exact MPDU-delimiter CRC-8, four-octet serialization, strict parsing and four-octet padding geometry|conditional|HT length 0-4095 with B0-B3 reserved; VHT/S1G/HE/EHT length 0-11454 with EOF B0 and B1 reserved; signature 0x4E|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|Non-DMG delimiter only; DMG format, aggregate scanning and resynchronization, minimum MPDU start spacing, null/EOF delimiter placement policy, scheduling and RF are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|15|DSSS_PHY|DSSS PLCP/PPDU, scrambling, spreading, DBPSK/DQPSK modulation and aligned receive processing|mixed|2.4 GHz 1 Mb/s or 2 Mb/s DSSS, mandatory long PLCP, PSDU at most 4095 octets, aligned complex chips and known-boundary common-gain hard RX|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|The declared aligned long-PLCP 1/2-Mb/s chip-domain profile is closed through actual MPDU FCS; pulse shaping, packet detection, timing/frequency/phase acquisition, multipath equalization, CCA, RF/OTA behavior and conformance remain absent
wifi|2024 base revision|IEEE Std 802.11-2024|16|HR_DSSS_CCK_PHY|HR/DSSS long/short PLCP/PPDU, CCK encoding/decoding, scrambling, modulation-rate switching and aligned receive processing|mixed|2.4 GHz CCK-only 2, 5.5, or 11 Mb/s with mandatory long or optional short PLCP, PSDU at most 4095 octets, aligned complex chips and known-boundary common-gain hard RX|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|The declared aligned CCK-only long/short PLCP profile is closed through actual MPDU FCS; optional PBCC is explicitly excluded, while pulse shaping, acquisition, multipath equalization, CCA, RF/OTA behavior and conformance remain absent
wifi|2024 base revision|IEEE Std 802.11-2024|17|OFDM_PHY|Legacy OFDM PPDU fields, BCC, interleaving, BPSK through 64-QAM, pilot insertion, IFFT/FFT and receive processing|mixed|20 MHz SISO NON_HT synchronized or known-timing baseband with all eight 6-54 Mb/s rates and an internally computed FCS|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|The declared synchronized or known-timing 20-MHz SISO NON_HT baseband profile is complete across all eight rates, preamble, L-SIG, SERVICE, BCC and puncturing, interleaving, modulation, pilots, tone mapping, IFFT or FFT, GI and received FCS; RF, CCA, packet detection, timing or CFO acquisition, spectral masks and MAC-header construction are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|18|ERP_PHY|ERP-OFDM inheritance, medium-occupancy signal-extension geometry and decoded NonERP or Use-Protection constraints|mixed|20 MHz SISO synchronized or known-timing ERP-OFDM baseband over all eight legacy rates with caller-owned concrete protection-mechanism policy|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|The declared ERP-OFDM CPU baseband profile inherits the complete Clause-17 chain and adds exact 6-us medium-occupancy signal-extension geometry plus the associated-NonERP Use-Protection constraint; DSSS or CCK algorithms are tracked under Clauses 15-16, while RF, CCA and selection among RTS or CTS protection mechanisms are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|19|HT_PHY|HT mixed/greenfield PPDU, HT-SIG, 20/40 MHz, MCS 0-76, BCC/LDPC, spatial streams, STBC and MIMO training|mixed|One NSS, 20 MHz, HT MCS 6 BCC, one DATA symbol and representative acquisition preamble|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|HT-SIG field/CRC and MCS 0-32 geometry exist; mixed/greenfield PPDU closure, MCS 33-76 unequal geometry, 40 MHz waveform, multi-symbol DATA, FEC mapping and MIMO remain incomplete
wifi|2024 base revision|IEEE Std 802.11-2024|20.4.3.1.2;20.11;Tables 20-23 through 20-28|DMG_PHY|DMG control, single-carrier and OFDM PPDUs, Golay sequences, beam training and receive processing|mixed|Legacy DMG Ga/Gb lengths 32/64/128 in transmission order; exact noiseless unit-axis pi/2-BPSK; complete 6400-chip control STF; exact nonnegative-lag integer autocorrelation|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|Discrete pre-rotation chips, strict noiseless exact-axis mapping/inverse and bounded integer correlation are in scope; RF/antenna/OTA, pulse shaping, synchronization and noisy detection are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|21|VHT_PHY|VHT PPDU, VHT-SIG-A/B, 20/40/80/160 MHz, MCS 0-9, BCC/LDPC, up to 8 spatial streams, MU-MIMO and beamforming|mixed|One NSS, 20 MHz, VHT MCS 8 BCC, one DATA symbol and representative acquisition preamble|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|SU VHT-SIG-A/B field, CRC and contiguous 20/40/80/160 MHz geometry exist; MU, NDP, 80+80, L-SIG spoof, full PPDU/waveform, multiple DATA symbols, multiple NSS, MU-MIMO and beamforming remain incomplete
wifi|2024 base revision|IEEE Std 802.11-2024|22.1;22.3.2;22.3.6-22.3.8;22.3.10;22.3.14;22.4.4;22.5;Tables 22-8,22-9,22-13-22-15,22-25-22-37|TVHT_PHY|TVHT channelization, OFDM/tone/SIG-A/MCS/interleaver/tone-mapping and data-symbol-driven PPDU timing arithmetic|mixed|6/7/8 MHz BCU; all MODE_1/2C/2N/4C/4N channel-index relations; one-four equal-modulation spatial streams; MCS 0-9; long/short GI; caller-supplied positive DATA-symbol count; no STBC|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|CPU-only exact TVHT table/arithmetic slice; regulatory operating-class/database permission is caller-owned and RF is excluded
wifi|2024 base revision|IEEE Std 802.11-2024|23.3.4.3-23.3.4.7;23.3.5-23.3.7;23.4.3-23.4.4;23.5;Tables 23-4,23-41,23-42,23-46,23-50,23-54,23-58|S1G_PHY|S1G PPDU, 1/2/4/8/16 MHz OFDM, S1G MCS/coding, long-range modes and receive processing|mixed|One NSS; 1/2/4/8/16 MHz; all valid MCS 0-9 cells and 1 MHz MCS 10; BCC SU long GI; S1G_1M at 1 MHz or S1G_SHORT at 2/4/8/16 MHz; configuration and geometry only|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|RF/regulatory/OTA conformance is excluded; full SIG, preamble/training, pilot positions, short GI, S1G_LONG/MU, multi-NSS/STBC, BCC/LDPC bit chains, waveform/RX/acquisition/equalization and deterministic S1G MAC/CCA remain in scope
wifi|2024 base revision|IEEE Std 802.11-2024|24|CDMG_PHY|China directional multi-gigabit PPDU, channelization, coding, preamble and receive processing|mixed|Published China directional millimeter-wave PHY|MISSING|https://standards.ieee.org/ieee/802.11/10548/|RF/antenna/OTA conformance is excluded; deterministic PHY algorithms are in scope
wifi|2024 base revision|IEEE Std 802.11-2024|25|CMMG_PHY|China millimeter-wave multi-gigabit control/SC/OFDM PPDUs, SIG, LDPC, preamble and receive processing|mixed|Published 45/60 GHz CMMG PHY|MISSING|https://standards.ieee.org/ieee/802.11/10548/|RF/antenna/OTA conformance is excluded; deterministic PPDU, SIG, coding and receive algorithms are in scope
wifi|2024 base revision|IEEE Std 802.11-2024|26|HE_MAC|HE trigger-based access, UL/DL MU scheduling rules, two NAVs, MU-EDCA, spatial reuse and deterministic MAC state|mixed|Published HE MAC behavior|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|Commercial scheduling policy is excluded; normative trigger, NAV and state-transition calculations are in scope
wifi|2024 base revision|IEEE Std 802.11-2024|26.2.4;26.2.5;26.11.5;Table 27-1|HE_Dual_NAV_normalized_state_arithmetic|HE dual-NAV updates, remaining time, CF-End/reset decisions and TXOP_DURATION arithmetic|mixed|HE STA or AP with decoded BSS classification and explicit AP two-NAV capability|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|Decoded metadata and deterministic state arithmetic are in scope; BSS classification, frame parsing/FCS, carrier sensing, UORA, MU-EDCA, spatial reuse and scheduler policy are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|9.3.1.22;Table 9-52;Table 9-53|HE_Trigger_User_RU_arithmetic|HE Trigger User Info AID12 classification and RU allocation encode/decode with contiguous random-access planning|conditional|20/40/80/160/80+80 MHz HE decoded User Info bounded allocation|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|Decoded Trigger User Info arithmetic is in scope; complete Trigger serialization/parsing, RU tone placement, MCS/DCM/NSS, UORA and scheduler policy are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|27|HE_PHY|HE SU/MU/TB PPDU, RL-SIG and HE-SIG, 20/40/80/160 MHz, MCS 0-11, OFDMA/RU, LDPC/BCC, up to 8 spatial streams and MU-MIMO|mixed|One NSS, 20 MHz RU-242, HE MCS 10 LDPC, one DATA symbol and one 4x LTF mini-PHY; bounded non-Doppler SU HE-SIG-A over contiguous 20/40/80/160 MHz plus 242-tone one-stream ER SU MCS 0-2; on-waveform 20 MHz one-NSS HE SU and 242-tone HE ER SU HE-SIG-A with signal-driven RU-242 LDPC DATA receive|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|Raw HE-SIG-A fields and geometry plus BCC, interleaving, pilots, 64-point OFDM waveform TX/RX and signal-derived RU-242 LDPC DATA receive are implemented for bounded 20 MHz SU and ER-SU slices; RL-SIG, complete PPDU assembly, MU/TB, Trigger, NDP, Doppler/midamble, 80+80 interpretation, packet extensions, 40/80/160 MHz waveforms, multiple DATA symbols, spatial training and complete TXVECTOR admissibility remain absent
wifi|2024 base revision|IEEE Std 802.11-2024|28|EDMG_PHY|EDMG control/SC/OFDM PPDUs, bonded channels, LDPC, beamforming training and receive processing|mixed|Published enhanced DMG operation above 45 GHz; bounded contiguous 1-4 by 2.16 GHz EDMG OFDM integer geometry and strict occupied-grid mapping|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|CPU-only contiguous-channel EDMG OFDM integer geometry and strict finite natural-order DFT grid packing are in scope; channel aggregation, complete PHY chains, RF, antenna, OTA, and conformance are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|29-30|WUR_MAC_PHY|Wake-up radio MAC procedures and WUR OOK PPDU, coding, waveform generation, detection and receive processing|mixed|Adopted TGba reference/example for one 20 MHz WUR channel, one transmit chain, 64-point IDFT at 20 MHz, BPSK coefficients, LDR/HDR Data On/Off waveforms and seven-bit symbol randomizer with caller-supplied already encoded decisions|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|CPU-only adopted TGba reference/example only: one 20 MHz channel, one transmit chain, 64-point IDFT at 20 MHz, BPSK coefficients on the adopted 6-tone HDR or 12-tone LDR sets, 32/64 useful plus 8/16 GI samples, all-ones seven-bit randomizer, exact Off symbols and caller-supplied already encoded On/Off decisions; returned data is discrete pre-window baseband, actual Clause 30 waveform generation remains implementation-dependent, and the adopted whole-WUR-Sync-plus-Data correlation-test construction and threshold verdict are caller-owned
wifi|2024 base revision|IEEE Std 802.11-2024|9.6.7.32-9.6.7.33;11.21.6;19;20;21;27;28;Annex B.4.37|Enhanced_positioning|FTM ranging exchanges, timing arithmetic, secure HE/EDMG ranging waveforms and position estimation support|mixed|One calibrated caller-unwrapped FTM t1/t2/t3/t4 exchange in integer picoseconds with optional initiator-to-responder clock-rate correction|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|Caller-unwrapped/calibrated timestamp arithmetic and vacuum-equivalent range conversion are in scope; finite-width field parsing/wrap recovery, RF timestamp acquisition/calibration and location policy are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|31-32|NGV_MAC_PHY|NGV OCB MAC, 10/20 MHz PPDU, NGV-SIG/RNGV-SIG, MCS/coding, repetition/duplication and ranging|mixed|Published next-generation V2X operation|MISSING|https://standards.ieee.org/ieee/802.11/10548/|Vehicular deployment policy and RF/OTA conformance are excluded; deterministic NGV PPDU, MAC and ranging algorithms are in scope
wifi|2024 base revision|IEEE Std 802.11-2024|33|LC_PHY_MAC|Light-communication PHY/MAC, optical OFDM PPDU, channelization, MCS/coding and receive processing|mixed|800 nm to 1000 nm published light-communication operation|MISSING|https://standards.ieee.org/ieee/802.11/10548/|Optical front-end, illumination and eye-safety conformance are excluded; deterministic baseband and MAC algorithms are in scope
wifi|2024 base revision|IEEE Std 802.11-2024|9.4.2.314;34|EBCS_MAC|Enhanced broadcast service discovery, frame construction, scheduling state and reception procedures|mixed|EBCS TIM Bitmap Mode 1 only when a distinct 2-31-ID list is strictly shorter than its minimal bitmap span; Content IDs 1-255; fixed DTIM period 1-255|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|CPU-only exact EBCS TIM Mode-1 element and fixed-period countdown; Mode 0 and equal-size selection are explicitly rejected because adopted Length requirements conflict; frame carriage, full EBCS exchanges, security, scheduling, RF and a complete MAC/MLME stack are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|19.2,19.5;21.2,21.5;27.2,27.5|HT_VHT_HE_profile_geometry|Normative MCS, NSS, OFDM timing and 20/40/80/160 MHz resource-count arithmetic|mixed|HT MCS 0-31, VHT MCS 0-9, HE MCS 0-11 and declared 1-8 NSS configuration records|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|Configuration arithmetic only; no 40/80/160 MHz waveform, multi-NSS mapper, spatial parser, STBC or MIMO chain
wifi|2024 base revision|IEEE Std 802.11-2024|27.3.2;27.5|HE_OFDMA_regular_RU|Regular RU geometry/counts and physical tone/pilot maps for HE OFDMA|mixed|20 MHz physical RU-26/52/106/242 maps plus wider-band count arithmetic|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|Physical tone maps stop at 20 MHz; allocation-index decoding, 40/80/160 MHz maps, trigger composition and multi-user PPDU orchestration are absent
wifi|2024 base revision|IEEE Std 802.11-2024|19.3.9.4.2;19.3.11.8.2;19.3.11.11.2;Table 19-10;21.3.8.3.2;21.3.10.6;Table 21-11;27.3.11.2.2;27.3.12.6;27.3.12.14|HT_VHT_HE_MIMO|Spatial parsing, stream mapping, cyclic shifts, STBC, channel sounding, beamforming and SU/MU-MIMO TX/RX|mixed|Single-FEC-encoder equal-modulation HT/VHT/HE with 1-4 NSS/STS, complete NSS*s parser cycles, ordered in-range tones and direct Q=I mapping with N_TX=N_STS|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|Only single-FEC-encoder equal-modulation 1-4 NSS/STS parsing, exact 1-4 STS modulated-field CSD values, ordered in-range tones and direct Q=I N_TX=N_STS mapping or unmapping are in scope; enclosing TXVECTOR, MCS, NES, code-rate and field-admissibility checks are caller-owned and RF is excluded
wifi|2024 amendment 2|IEEE Std 802.11be-2024|36|EHT_PHY|EHT SU/MU/TB PPDU, U-SIG/EHT-SIG, 20/40/80/160/320 MHz, MCS 0-15, LDPC, OFDMA/MRU, puncturing and up to 8 spatial streams|mixed|One NSS, 20 MHz RU-242, EHT MCS 13 LDPC, one DATA symbol and one 4x LTF mini-PHY; bounded 20 MHz nonpunctured EHT SU transmission U-SIG raw fields plus caller-declared EHT-SIG Common/User CRC envelopes; on-waveform U-SIG plus one 42-bit EHT-SIG Common block at EHT-SIG MCS 0 in two symbols with signal-driven RU-242 LDPC DATA receive|PARTIAL|https://standards.ieee.org/ieee/802.11be/7516/|Discrete fields and CRC envelopes plus bounded on-waveform U-SIG and the first one-user EHT-SIG Common encoding block are implemented with signal-derived RU-242 LDPC DATA receive; complete interoperable PPDU assembly, arbitrary EHT-SIG content and padding, puncturing, MRU/OFDMA/MU/TB/NDP/Trigger, 40/80/160/320 MHz waveforms, multiple DATA symbols and spatial training remain absent
wifi|2024 amendment 2|IEEE Std 802.11be-2024|36.3.2.2;Tables 36-13--36-15;36.3.12.7.2;Table 36-30|EHT_320_MHz_MRU_SIG_puncturing|Contiguous EHT wideband geometry, assigned non-OFDMA U-SIG puncturing indication decode and legal inverse, and large-MRU component/index composition|mixed|Exact contiguous 20/40/80/160/320 MHz geometry; all 45 assigned non-OFDMA puncturing rows with explicit primary-20 validation; all 72 large-MRU rows in 80/160/320 MHz Tables 36-13--36-15, including OFDMA applicability|PARTIAL|https://standards.ieee.org/ieee/802.11be/7516/|CPU-only discrete tables: contiguous channel geometry, non-OFDMA U-SIG puncturing rows and large-MRU size/index composition only; no claim of waveform, physical tone-coordinate maps, RU Allocation/EHT-SIG encoding, OFDMA scheduling, RF or interoperability
wifi|2024 amendment 2|IEEE Std 802.11be-2024|9.4.2.322.2.3;Tables 9-417i--9-417m;9.4.2.324;35.3.7|EHT_MAC_MLO|Raw TID-to-link element encoding and established mapping-state projection, EML capability timing and TSF/TU field arithmetic|mixed|Canonical raw TTLM payloads over caller-accepted setup links, caller-supplied active links and published EML timing codes|PARTIAL|https://standards.ieee.org/ieee/802.11be/7516/|Only canonical raw TTLM payloads beginning at the Control field, established per-direction mappings over caller-accepted setup links, caller-supplied active-link intersection or union projection, EML capability timing-code decoding and full-UInt64 integer TU conversions are in scope; frame context, negotiation, activation/expiry, link choice or scheduling and RF are excluded
wifi|2024 amendment 1|IEEE Std 802.11bh-2024|4.5.4.10;6.4-6.5.7;9.3.3;9.4.2;9.6.36;11-12;Annex AG|Randomized_changing_MAC_addresses|Identity/session-continuity base fields, status/action tables, local-individual address shape and explicit Recognized/Not Recognized Address-2 binding|mixed|Non-AP/AP base Device ID, IRM and PASN ID element payload fields after Element ID Extension, without trailing subelements; statuses 0-2 where defined; IRM actions 0-1; six-octet address core|PARTIAL|https://standards.ieee.org/ieee/802.11bh/10525/|CPU-only caller-supplied deterministic byte fields immediately after Element ID Extension; no trailing subelements, KDE/PASN container or complete frame; Address-2 transition is limited to explicit response statuses 0 and 1
wifi|2025 amendment 3|IEEE Std 802.11bk-2025|8.3.5;9;11;35.14.2;36.2-36.3|FTM_320_MHz_positioning|320 MHz FTM exchanges, EHT ranging NDP/TB ranging NDP, secure EHT-LTF and timing/range calculations|mixed|Published 320 MHz positioning using the EHT PHY and MAC|MISSING|https://standards.ieee.org/ieee/802.11bk/11117/|RF timestamp calibration and location policy are excluded; PPDU, secure-LTF, timestamp and range algorithms are in scope
wifi|2025 amendment 4|IEEE Std 802.11bf-2025|9;11;20;27.2;28.2-28.12;35.3.14;36.2|WLAN_sensing|Sensing MAC exchanges, HE/EHT PHY service interface, DMG/EDMG sensing PPDUs, channel measurements and deterministic sensing calculations|mixed|License-exempt bands from 1 GHz to 7.125 GHz and above 45 GHz|MISSING|https://standards.ieee.org/ieee/802.11bf/11574/|Application policy and RF/antenna/OTA conformance are excluded; published waveform, channel-measurement and sensing calculations are in scope
wifi|Active PAR|IEEE P802.11 revision|PAR scope|Next_802.11_revision|Next consolidated IEEE 802.11 revision superseding IEEE Std 802.11-2024|not_applicable|Unpublished revision project|TRACKING|https://standards.ieee.org/ieee/802.11/11852/|Track project status only; draft content cannot replace a published normative baseline
wifi|Active PAR|IEEE P802.11bi|PAR scope|Enhanced_service_privacy|MAC enhancements for privacy-protected service discovery and operation|not_applicable|Unpublished enhanced-service privacy amendment|TRACKING|https://standards.ieee.org/ieee/802.11bi/12331/|Track project status only; draft MAC behavior is non-normative
wifi|Active PAR|IEEE P802.11bn|PAR scope|Ultra_High_Reliability|PHY/MAC enhancements for throughput, latency, MPDU-loss, power and peer-to-peer reliability|not_applicable|Unpublished ultra-high-reliability amendment for 1 GHz to 7.250 GHz|TRACKING|https://standards.ieee.org/ieee/802.11bn/11393/|Track project status only; draft PHY/MAC content is non-normative
wifi|Active PAR|IEEE P802.11bp|PAR scope|Ambient_Power_communication|Sub-1 GHz and 2.4 GHz ambient-power communication plus wireless power-transfer PHY/MAC|not_applicable|Unpublished ambient-power amendment|TRACKING|https://standards.ieee.org/ieee/802.11bp/11592/|Track project status only; energy-harvesting hardware and draft behavior are non-normative
wifi|Active PAR|IEEE P802.11bq|PAR scope|Integrated_mmWave_WLAN|Non-standalone 42 GHz to 71 GHz SU-OFDM PHY/MAC and multi-link extensions|not_applicable|Unpublished integrated millimeter-wave WLAN amendment|TRACKING|https://standards.ieee.org/ieee/802.11bq/11872/|Track project status only; draft PHY/MAC content is non-normative
wifi|Active PAR|IEEE P802.11br|PAR scope|Enhanced_light_communications|Enhanced optical channelization, WDM, ranging, PAPR reduction and multi-link PHY/MAC|not_applicable|Unpublished enhanced light-communications amendment|TRACKING|https://standards.ieee.org/ieee/802.11br/11993/|Track project status only; optical front-end and draft PHY/MAC behavior are non-normative
wifi|Active PAR|IEEE P802.11bt|PAR scope|Post_quantum_cryptography|Post-quantum AKM suites, signatures, key establishment, password exchange and handshake modifications|not_applicable|Unpublished post-quantum security amendment|TRACKING|https://standards.ieee.org/ieee/802.11bt/12187/|Track project status only; draft cryptographic protocol content is non-normative
nr|Rel-18|3GPP TS 38.211 V18.9.0|7.3.1.3;Table 7.3.1.3-1|NR_PDSCH_layer_mapping|Complete PDSCH one-codeword and two-codeword spatial-multiplexing layer mapping and inverse|conditional|One codeword over 1-4 layers or two codewords over 5-8 layers with equal symbols per layer|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/38_series/38.211/38211-i90.zip|Layer mapping only; scrambling, modulation, precoding, antenna-port and RE mapping, DM-RS port selection, scheduler state and MIMO channel processing remain independently scoped
nr|Rel-17|3GPP NR_redcap Work Item 900062; 3GPP TS 38.211 V17.10.0; 3GPP TS 38.212 V17.13.0; 3GPP TS 38.213 V17.13.0; 3GPP TS 38.214 V17.16.0; 3GPP TS 38.306 V17.16.0|3GPP TS 38.211 V17.10.0 clauses 4.2-4.3;5.2-5.3;6.3-6.4;7.3-7.4; 3GPP TS 38.212 V17.13.0 clauses 5.1-5.4;6.2-6.3;7.1;7.2;7.3.2; 3GPP TS 38.213 V17.13.0 clause 17; 3GPP TS 38.214 V17.16.0 clauses 5.1;6.1; 3GPP TS 38.306 V17.16.0 clauses 4.2.21.1;4.2.21.2-4.2.21.7|NR_redcap_FR1_20MHz_representative_chains|Bounded downlink PSS/SSS to PBCH/MIB to PDCCH/DCI to PDSCH and uplink PRACH to PUSCH to PUCCH/UCI composition|mandatory|Representative FR1 20 MHz, 30 kHz SCS, 51-PRB initial-DL/UL-BWP composition across separately bounded SISO/one-layer stages; not a normative end-to-end conformance profile|PARTIAL|https://portal.3gpp.org/desktopmodules/WorkItem/WorkItemDetails.aspx?workitemId=900062|Cross-stage deterministic composition only: each PSS/SSS, PBCH/PDCCH, PDSCH/PUSCH/PUCCH and normalized-PRACH stage retains its separately declared TS/profile boundary; no single normative end-to-end clause, radio-rate PRACH placement, contiguous RF waveform, RRC/MAC, scheduler, RF or conformance procedure is claimed
wifi|2024 base revision|IEEE Std 802.11-2024|9.2.4.2;9.3.1.5;9.4.2.5.1;11.2.3.1-11.2.3.7|Legacy_power_save_TIM_DTIM_state|Canonical Method-A TIM construction/AID decoding, DTIM state, ListenInterval/ReceiveDTIMs TBTT selection, PS-Poll Duration/ID and legacy delivery/doze decision|mixed|Single-BSSID non-S1G Method A; AID 1-2007; legacy non-QoS PS STA without APSD/TWT/MLO|COMPLETE|https://standards.ieee.org/ieee/802.11/10548/|Frame parsing, TSF/beacon-loss recovery, APSD, TWT, TIM Broadcast, WNM sleep, IBSS/PBSS, MLO, channel access, buffering and delivery scheduling are excluded
wifi|2024 base revision|IEEE Std 802.11-2024|17|Legacy_OFDM_fixed_reference_artifacts|Bit-exact fixed-point BCC, bounded legacy QPSK OFDM known-timing or acquired-timing reference slices, checksums and canonical RTL vector serialization|mixed|Bit-exact K=7 rate-1/2 BCC primitives; bounded 20 MHz legacy QPSK fixed references with known timing or bounded integer timing acquisition; canonical fixed artifacts; one dense non-interoperable coded mini-PHY retained only as analytic hardware support|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/|IEEE clause-17 BCC serialization and the declared legacy DATA, FCS, scrambling, interleaving, tone, pilot and transmit wire stages are normative only within their bounded profiles. Integer Q-formats, rounding or saturation, fixed flat-channel injection, packet detection, LS, ZF, LLR, Viterbi choices, checksums and RTL text are non-normative fixed representations or reference receivers and are not uniquely specified RX behavior; the dense mini-PHY is not an interoperable PPDU. L-SIG in the acquired fixed chain, frequency-selective, CFO or noisy receive, other rates or modulations, RF and conformance are excluded
nr|Rel-18|3GPP TS 38.211 V18.9.0; 3GPP TS 38.212 V18.8.0|3GPP TS 38.211 V18.9.0 clauses 6.3-6.4;7.3-7.4; 3GPP TS 38.212 V18.8.0 clauses 6.2-6.3;7.1;7.2;7.3.2|NR_TS38211_TS38212_bounded_channel_facades|Bounded cross-specification PBCH, PDCCH, PDSCH, PUSCH and PUCCH encode/decode facades plus fixed-point PDSCH audit artifacts|mixed|Bounded CPU PBCH, PDCCH and single-codeword or single-layer PDSCH, PUSCH and PUCCH facades across the declared TS 38.211 wire stages and TS 38.212 coding stages, plus one registered fixed-point PDSCH audit profile|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.211/38211-i90.zip|Normative ownership is conjunctive: transmitted CRC, coded-bit, segmentation and rate-matching stages require TS 38.212, while physical scrambling, modulation, resource-grid and waveform stages require TS 38.211. Only transmitted wire behavior within each declared profile is normative; channel estimation, equalization, soft decisions, decoder choices, fixed Q-formats, scale schedules, checksums and RTL serialization are analytic or reference support, not uniquely specified receive behavior. Arbitrary formats or configurations, HARQ policy, scheduling, RF and conformance are excluded
nr|Rel-18|3GPP TS 38.211 V18.9.0|4.2-4.3;5.2-5.3;6.3-6.4;7.3-7.4|NR_TS38211_bounded_PHY_core|Bounded normal-CP OFDM/grid, Gold/PSS/SSS, PBCH/PDCCH/PDSCH/PUSCH/PUCCH/PRACH/PT-RS/DM-RS physical-channel generation, mapping and reference receive processing|mixed|Caller-decoded single-codeword or single-layer CPU profiles and normalized PRACH compositions|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.211/38211-i90.zip|Listed transmit bit, sequence, resource-grid and waveform behavior is normative only within each declared bounded profile; synchronization search, detection, channel estimation, equalization, common-phase correction and soft decisions are analytic or reference receivers, not uniquely specified receive algorithms; the PUCCH flat-channel injector is excluded from formal Feature coverage; arbitrary configurations, scheduling, RF and conformance are excluded
nr|Rel-18|3GPP TS 38.212 V18.8.0|5.1-5.7;6.2-6.3;7.1;7.2;7.3.2|NR_TS38212_bounded_channel_coding_core|CRC, Polar, LDPC and small-block coding, segmentation, rate matching or recovery, plus bounded channel-specific coding primitives|mixed|Caller-sized CPU reference coding for registered transport and control-channel profiles, including one registered fixed-point LDPC audit profile|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.212/38212-i80.zip|Listed transmitted CRC, coded-bit, segmentation and rate-matching behavior is normative within the declared dimensions; soft rate recovery, SC, ML and min-sum decoding, iteration or clipping choices and fixed-point formats are analytic or reference receiver choices rather than uniquely specified decoders; complete channel-format coverage, HARQ process policy, scheduler state and RF are excluded
nr|Rel-18|3GPP TS 38.213 V18.8.0|4.2;7.1;9.2;10.1|NR_TS38213_bounded_control_procedure_core|CORESET CCE counts, UE-specific search-space candidates, timing-advance arithmetic, bounded PUSCH power and PUCCH resource or BWP validation|mixed|Stateless decoded-configuration arithmetic over the explicitly validated integer and finite linear or dB domains|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip|Only uniquely determined arithmetic after caller-owned DCI/RRC decoding is in scope; random access, closed-loop power-control state, UE/MAC state, scheduler choices, RF and conformance are excluded from this broad row; monitoring occasions are covered only by the separate exact joint TS 38.213/38.331 Feature rows
nr|Rel-18|3GPP TS 38.214 V18.10.0|5.1.3;5.1.6.3|NR_TS38214_bounded_MCS_TBS_PTRS_core|Published PDSCH/PUSCH MCS-table lookup, exact transport-block-size arithmetic, PDSCH resource-element accounting and PDSCH PT-RS density or time-position selection|mixed|All registered non-reserved MCS rows and exact integer TBS branches with caller-decoded allocation and PT-RS threshold inputs|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/38214-ia0.zip|Exact table and integer admissibility or selection behavior is in scope; UE-selected MCS, CSI reporting, scheduler policy, HARQ state, multi-layer allocation policy, RF and conformance are excluded
nr|Rel-18|3GPP TS 38.215 V18.5.0|5.1-5.3|NR_TS38215_linear_measurement_core|Linear-domain SS and CSI RSRP, RSSI, RSRQ and SINR formulas over caller-supplied selected observations|mandatory|Finite nonempty caller-selected single-receive-branch observations with explicit resource-block and symbol counts|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.215/38215-i50.zip|Only the listed linear formulas after caller-owned resource selection are in scope; acquisition, calibration, antenna combining, L1 or L3 filtering, report triggering, RF and conformance tolerances are excluded
nr|Rel-18|3GPP TS 38.321 V18.10.0|5.1.3|NR_TS38321_RA_RNTI_arithmetic|RA-RNTI construction from decoded PRACH time, frequency and uplink-carrier coordinates|mandatory|Pure bounded identifier arithmetic for validated PRACH occasion coordinates|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-ia0.zip|Only the clause 5.1.3 integer identifier formula is in scope; PRACH detection, response windows, random-access state, MAC PDU handling, scheduler policy, RF and the rest of MAC are excluded
nr|Rel-18|3GPP TS 38.213 V18.8.0; 3GPP TS 38.331 V18.10.0|3GPP TS 38.213 V18.8.0 clause 10.1; 3GPP TS 38.331 V18.10.0 clause 6.3.2|NR_PDCCH_non_grouped_monitoring_slots|Decoded base SearchSpace periodicity, offset and duration validation plus deterministic non-grouped monitoring-slot membership|conditional|Base monitoringSlotPeriodicityAndOffset alternatives sl1 through sl2560; offset 0 through periodicity-1; absent duration one or present duration 2 through min(2559, periodicity-1); caller-supplied nonnegative absolute slot|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip|Decoded non-grouped base SearchSpace slot arithmetic only; ASN.1 encoding, monitoringSlotsWithinSlotGroup-r17, v1710 and duration-r17 fields, grouped occasions, DCI-format exceptions, SFN lifecycle, scheduler policy, UE state, RF and conformance are excluded from this slot-only row; symbol-level occasions are covered only by the separate exact joint Feature row
nr|Rel-18|3GPP TS 38.213 V18.8.0; 3GPP TS 38.331 V18.10.0|3GPP TS 38.213 V18.8.0 clause 10.1; 3GPP TS 38.331 V18.10.0 clause 6.3.2|NR_PDCCH_symbol_level_monitoring_occasions|Non-grouped symbol-level monitoring-occasion membership over a decoded base SearchSpace slot pattern, decoded first-symbol set and CORESET duration|conditional|Normal-CP 14-symbol or extended-CP 12-symbol slots; base monitoringSlotPeriodicityAndOffset pattern; ordered decoded first symbols; CORESET duration 1 through 3|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip|Only TS 38.213 clause 10.1 occasion membership jointly with TS 38.331 clause 6.3.2 bitmap and duration domains is in scope; grouped and DCI-specific exceptions, cross-SearchSpace overlap, CORESET linking, CCE mapping, scheduler state, RF and conformance are excluded
nr|Rel-18|3GPP TS 38.331 V18.10.0|6.3.2|NR_SearchSpace_monitoringSymbolsWithinSlot|Decoded 14-bit monitoringSymbolsWithinSlot first-symbol enumeration for normal and extended cyclic prefix|conditional|Raw BIT STRING SIZE 14 represented as an integer mask; all-zero is legal and the last two bits are ignored for extended cyclic prefix|COMPLETE|https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-ia0.zip|Only the base SearchSpace bitmap field projection is in scope; ASN.1 encoding, Need-M lifecycle, grouped or v1710 fields and complete RRC state are excluded
EOF
sort -o "${expected_required_file}" "${expected_required_file}"

definition_exists() {
    local file=$1
    local symbol=$2
    rg -q -- "^(def|fn|struct|alias)[[:space:]]+${symbol}(\\[|\\(|:|[[:space:]]*=)" "${file}"
}

validate_refs() {
    local row_key=$1
    local category=$2
    local refs=$3
    local ref path symbol seen_ref duplicate
    local -a ref_array seen_refs

    [[ "${refs}" == "-" ]] && return 0
    seen_refs=()
    IFS=';' read -r -a ref_array <<< "${refs}"
    for ref in "${ref_array[@]}"; do
        duplicate=0
        for seen_ref in "${seen_refs[@]}"; do
            if [[ "${seen_ref}" == "${ref}" ]]; then
                echo "${row_key}: duplicate ${category} reference: ${ref}" \
                    >> "${errors_file}"
                duplicate=1
                break
            fi
        done
        (( duplicate )) && continue
        seen_refs+=("${ref}")
        if [[ "${ref}" != *::* ]]; then
            echo "${row_key}: ${category} reference lacks path::symbol: ${ref}" >> "${errors_file}"
            continue
        fi
        path=${ref%%::*}
        symbol=${ref#*::}
        if [[ "${path}" == /* || "${path}" == *'..'* ]]; then
            echo "${row_key}: ${category} path must be project-relative: ${path}" >> "${errors_file}"
            continue
        fi
        case "${category}" in
            source)
                [[ "${path}" == wireless_dsp/* ]] \
                    || echo "${row_key}: source must live under wireless_dsp/: ${ref}" >> "${errors_file}"
                ;;
            benchmark)
                [[ "${path}" == benchmarks/* ]] \
                    || echo "${row_key}: benchmark must live under benchmarks/: ${ref}" >> "${errors_file}"
                ;;
            *)
                [[ "${path}" == tests/* || "${path}" == examples/* ]] \
                    || echo "${row_key}: test evidence must live under tests/ or examples/: ${ref}" >> "${errors_file}"
                ;;
        esac
        if [[ ! -f "${project_dir}/${path}" ]]; then
            echo "${row_key}: ${category} file does not exist: ${path}" >> "${errors_file}"
        elif ! definition_exists "${project_dir}/${path}" "${symbol}"; then
            echo "${row_key}: ${category} symbol does not exist: ${ref}" >> "${errors_file}"
        fi
    done
}

complete=0
partial=0
missing=0
excluded=0
tracking=0
rows=0

while IFS=$'\t' read -r family release specification clause feature algorithm mandatory profile status source deterministic edge property differential oracle tolerance tolerance_mode benchmark official_url boundary notes; do
    ((rows += 1))
    row_key="${family}|${release}|${feature}|${algorithm}"
    if rg -q -x -F -- "${row_key}" "${seen_file}"; then
        echo "${row_key}: duplicate feature row" >> "${errors_file}"
    else
        echo "${row_key}" >> "${seen_file}"
    fi

    case "${family}" in
        bluetooth|ieee802154|lte|matter|nr|thread|wifi|zigbee) ;;
        *) echo "${row_key}: invalid family '${family}'" >> "${errors_file}" ;;
    esac
    case "${mandatory}" in
        mandatory|optional|conditional|mixed|mandatory-by-inheritance|not_applicable) ;;
        *) echo "${row_key}: invalid mandatory_or_optional '${mandatory}'" >> "${errors_file}" ;;
    esac
    case "${status}" in
        COMPLETE) ((complete += 1)) ;;
        PARTIAL) ((partial += 1)) ;;
        MISSING) ((missing += 1)) ;;
        EXCLUDED) ((excluded += 1)) ;;
        TRACKING) ((tracking += 1)) ;;
        *) echo "${row_key}: invalid status '${status}'" >> "${errors_file}" ;;
    esac
    case "${official_url}" in
        https://www.bluetooth.com/*|https://www.3gpp.org/*|https://portal.3gpp.org/*|https://www.etsi.org/*|https://standards.ieee.org/*|https://www.ieee802.org/*|https://mentor.ieee.org/*|https://threadgroup.org/*|https://www.threadgroup.org/*|https://csa-iot.org/*) ;;
        *) echo "${row_key}: URL is not an approved official source: ${official_url}" >> "${errors_file}" ;;
    esac
    if [[ -z "${release}" || -z "${specification}" || -z "${clause}" \
        || -z "${feature}" || -z "${algorithm}" || -z "${profile}" \
        || -z "${boundary}" || -z "${notes}" ]]; then
        echo "${row_key}: normative, profile, boundary and notes fields must be non-empty" >> "${errors_file}"
    fi

    if [[ "${status}" == "MISSING" || "${status}" == "EXCLUDED" \
        || "${status}" == "TRACKING" ]]; then
        for value in "${source}" "${deterministic}" "${edge}" "${property}" \
            "${differential}" "${tolerance}" "${benchmark}"; do
            if [[ "${value}" != "-" ]]; then
                echo "${row_key}: ${status} rows cannot claim executable evidence" >> "${errors_file}"
                break
            fi
        done
        if [[ "${oracle}" != "not_applicable" || "${tolerance_mode}" != "not_applicable" ]]; then
            echo "${row_key}: ${status} rows require not_applicable oracle and tolerance mode" >> "${errors_file}"
        fi
        case "${family}:${status}" in
            bluetooth:MISSING|matter:MISSING|zigbee:MISSING)
                expected_gap_token=IMPLEMENTATION_MISSING
                ;;
            ieee802154:MISSING|thread:MISSING)
                expected_gap_token=BLOCKED_METADATA
                ;;
            *)
                expected_gap_token=""
                ;;
        esac
        if [[ -n "${expected_gap_token}" ]]; then
            case "${boundary}" in
                "${expected_gap_token}"|"${expected_gap_token} "*|"${expected_gap_token}:"*) ;;
                *)
                    echo "${row_key}: MISSING row boundary must start with exact ${expected_gap_token}" >> "${errors_file}"
                    ;;
            esac
            case "${notes}" in
                "${expected_gap_token}"|"${expected_gap_token} "*|"${expected_gap_token}:"*) ;;
                *)
                    echo "${row_key}: MISSING row notes must start with exact ${expected_gap_token}" >> "${errors_file}"
                    ;;
            esac
        fi
    else
        validate_refs "${row_key}" source "${source}"
        validate_refs "${row_key}" deterministic "${deterministic}"
        validate_refs "${row_key}" edge "${edge}"
        validate_refs "${row_key}" property "${property}"
        validate_refs "${row_key}" differential "${differential}"
        validate_refs "${row_key}" tolerance "${tolerance}"
        validate_refs "${row_key}" benchmark "${benchmark}"
        case "${oracle}" in
            analytic|external_static|float64_reference|cross_implementation|exhaustive_integer) ;;
            *) echo "${row_key}: invalid independent oracle kind '${oracle}'" >> "${errors_file}" ;;
        esac
        case "${tolerance_mode}" in
            exact|absolute|relative|statistical|mixed) ;;
            *) echo "${row_key}: invalid tolerance mode '${tolerance_mode}'" >> "${errors_file}" ;;
        esac
        if [[ "${status}" == "COMPLETE" ]]; then
            for value in "${source}" "${deterministic}" "${edge}" "${property}" \
                "${differential}" "${tolerance}" "${benchmark}"; do
                if [[ "${value}" == "-" ]]; then
                    echo "${row_key}: COMPLETE row lacks a required evidence category" >> "${errors_file}"
                    break
                fi
            done
        elif [[ "${source}" == "-" ]]; then
            echo "${row_key}: PARTIAL row must identify a production source" >> "${errors_file}"
        fi
    fi

    if [[ "${status}" == "COMPLETE" || "${status}" == "PARTIAL" ]]; then
        case "${family}" in
            bluetooth|matter|zigbee|lte|nr|wifi)
                IFS=';' read -r -a feature_source_array <<< "${source}"
                for feature_source in "${feature_source_array[@]}"; do
                    if [[ "${feature_source}" != "-" ]]; then
                        printf '%s|%s\n' "${family}" "${feature_source}" \
                            >> "${formal_protocol_sources_file}"
                    fi
                done
                ;;
        esac
    fi

    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "${family}" "${release}" "${specification}" "${clause}" \
        "${feature}" "${algorithm}" "${mandatory}" "${profile}" \
        "${status}" "${official_url}" "${boundary}" \
        >> "${actual_required_file}"
done < <(tail -n +2 "${matrix}")

sort -u -o "${actual_required_file}" "${actual_required_file}"
while IFS= read -r missing_required; do
    if [[ -n "${missing_required}" ]]; then
        echo "missing required feature row: ${missing_required}" >> "${errors_file}"
    fi
done < <(comm -23 "${expected_required_file}" "${actual_required_file}")

# A path::symbol claim is not executable evidence by itself.  Resolve each
# COMPLETE/PARTIAL Feature evidence entry against the exact kernel-ledger
# source/evidence join whenever that join exists, then prove a real call edge
# to at least one of those source APIs through no more than two file-local
# helpers.  Feature-only aggregate evidence predates per-API ledger entries;
# it still has to reach a source in the same formal protocol inventory, but is
# deliberately not expanded into the row's source/evidence Cartesian product.
#
# Benchmark entries additionally have to resolve the same reached API through
# a main-reachable function containing a real timer call.  Exact-joined
# benchmark symbols themselves must be reachable from main.  The scanner
# removes comments, strings, and triple-quoted docstrings before extracting
# definitions or calls, so prose cannot satisfy either reachability edge.
if ! python3 - "${project_dir}" "${matrix}" "${kernel_matrix}" \
    "${errors_file}" <<'PY'
import csv
import re
import sys
from pathlib import Path


project_dir = Path(sys.argv[1])
matrix_path = Path(sys.argv[2])
kernel_matrix_path = Path(sys.argv[3])
errors_path = Path(sys.argv[4])

feature_columns = {
    "deterministic": 10,
    "edge": 11,
    "property": 12,
    "differential": 13,
    "tolerance": 15,
    "benchmark": 17,
}
kernel_columns = {
    "deterministic": 4,
    "edge": 5,
    "property": 6,
    "differential": 7,
    "tolerance": 9,
    "benchmark": 11,
}
identifier = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
definition = re.compile(
    r"^(?:def|fn)[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?=\[|\()"
)
direct_call = re.compile(
    r"(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?=\()"
)
generic_dispatch = re.compile(
    r"(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)[ \t]*"
    r"\[[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*\][ \t]*\("
)


def split_refs(value):
    if value == "-":
        return []
    return value.split(";")


def split_ref(ref):
    if "::" not in ref:
        return None
    path, symbol = ref.split("::", 1)
    if (
        not path
        or path.startswith("/")
        or ".." in path
        or not identifier.fullmatch(symbol)
    ):
        return None
    return path, symbol


def sanitize_source(text):
    """Blank comments and all string forms while preserving line structure."""
    output = []
    index = 0
    quote = None
    triple_quote = None
    escaped = False
    in_comment = False
    while index < len(text):
        character = text[index]
        if in_comment:
            output.append("\n" if character == "\n" else " ")
            in_comment = character != "\n"
            index += 1
            continue
        if triple_quote is not None:
            if escaped:
                escaped = False
                output.append("\n" if character == "\n" else " ")
                index += 1
            elif character == "\\":
                escaped = True
                output.append(" ")
                index += 1
            elif text.startswith(triple_quote, index):
                output.extend("   ")
                index += 3
                triple_quote = None
            else:
                output.append("\n" if character == "\n" else " ")
                index += 1
            continue
        if quote is not None:
            output.append("\n" if character == "\n" else " ")
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
            index += 1
            continue
        if text.startswith('"""', index) or text.startswith("'''", index):
            triple_quote = text[index:index + 3]
            output.extend("   ")
            index += 3
            continue
        if character == "#":
            in_comment = True
            output.append(" ")
            index += 1
            continue
        if character in ('"', "'"):
            quote = character
            output.append(" ")
            index += 1
            continue
        output.append(character)
        index += 1
    return "".join(output)


graph_cache = {}


def function_graph(relative_path):
    cached = graph_cache.get(relative_path)
    if cached is not None:
        return cached

    source_path = project_dir / relative_path
    clean_lines = sanitize_source(
        source_path.read_text(encoding="utf-8")
    ).splitlines(keepends=True)
    bodies = {}
    calls = {}
    line_index = 0
    while line_index < len(clean_lines):
        match = definition.match(clean_lines[line_index])
        if match is None:
            line_index += 1
            continue

        symbol = match.group(1)
        delimiter_depth = 0
        header_end = line_index
        header_complete = False
        while header_end < len(clean_lines):
            for character in clean_lines[header_end]:
                if character in "([":
                    delimiter_depth += 1
                elif character in ")]":
                    delimiter_depth = max(0, delimiter_depth - 1)
                elif character == ":" and delimiter_depth == 0:
                    header_complete = True
                    break
            if header_complete:
                break
            header_end += 1

        body_end = header_end + 1
        while body_end < len(clean_lines):
            line = clean_lines[body_end]
            if line.strip() and not line[0].isspace():
                break
            body_end += 1
        body = "".join(clean_lines[header_end + 1:body_end])
        symbol_calls = set(direct_call.findall(body))
        for dispatch in generic_dispatch.finditer(body):
            # The callee is a call edge.  A file-local function passed as a
            # compile-time callable (for example _run[_workload]()) is also a
            # real edge once intersected with the local definition set.
            symbol_calls.add(dispatch.group(1))
            symbol_calls.add(dispatch.group(2))
        bodies[symbol] = body
        calls[symbol] = symbol_calls
        line_index = max(body_end, line_index + 1)

    parsed = calls, bodies
    graph_cache[relative_path] = parsed
    return parsed


def local_closure(graph, entry):
    reached = set()
    pending = [entry]
    while pending:
        symbol = pending.pop()
        if symbol in reached or symbol not in graph:
            continue
        reached.add(symbol)
        pending.extend((graph[symbol] & graph.keys()) - reached)
    return reached


def reached_targets(graph, entry, targets, max_helpers=2):
    # A same-named local helper shadows an imported production API and cannot
    # satisfy an external source-symbol edge.
    external_targets = targets - graph.keys()
    reached = set()
    visited = set()

    def visit(symbol, helper_depth):
        state = symbol, helper_depth
        if state in visited:
            return
        visited.add(state)
        symbol_calls = graph.get(symbol, set())
        reached.update(symbol_calls & external_targets)
        if helper_depth >= max_helpers:
            return
        for helper in symbol_calls & graph.keys():
            if helper != symbol:
                visit(helper, helper_depth + 1)

    visit(entry, 0)
    return reached


def call_tokens(text):
    """Return executable direct/generic call tokens from sanitized text."""
    tokens = set(direct_call.findall(text))
    for dispatch in generic_dispatch.finditer(text):
        tokens.add(dispatch.group(1))
        tokens.add(dispatch.group(2))
    return tokens


def timed_reached_targets(graph, bodies, owner, targets):
    """Resolve targets reached only between complete counter-read pairs."""
    body = bodies.get(owner, "")
    timer_calls = list(
        re.finditer(
            r"(?<![A-Za-z0-9_])global_perf_counter_ns[ \t]*\(", body
        )
    )
    timed_targets = set()
    external_targets = targets - graph.keys()
    # Pair counter reads in source order.  An unmatched final read is never a
    # measured interval, even when a target call follows it before function
    # exit.  This mirrors the kernel-ledger timer gate and still supports a
    # caller-owned timer whose complete pair surrounds a local workload call.
    for index in range(0, len(timer_calls) - 1, 2):
        segment = body[timer_calls[index].end():timer_calls[index + 1].start()]
        segment_calls = call_tokens(segment)
        timed_targets.update(segment_calls & external_targets)
        for helper in segment_calls & graph.keys():
            timed_targets.update(reached_targets(graph, helper, targets))
    return timed_targets


with kernel_matrix_path.open(newline="", encoding="utf-8") as handle:
    kernel_rows = list(csv.reader(handle, delimiter="\t"))[1:]
with matrix_path.open(newline="", encoding="utf-8") as handle:
    feature_rows = list(csv.reader(handle, delimiter="\t"))[1:]

category_sources = {}
any_category_sources = {}
for kernel_row in kernel_rows:
    source_ref = kernel_row[3]
    for category, column in kernel_columns.items():
        for evidence_ref in split_refs(kernel_row[column]):
            category_sources.setdefault(
                (category, evidence_ref), set()
            ).add(source_ref)
            any_category_sources.setdefault(evidence_ref, set()).add(
                source_ref
            )

formal_family_symbols = {}
for feature_row in feature_rows:
    if feature_row[8] not in ("COMPLETE", "PARTIAL"):
        continue
    family_symbols = formal_family_symbols.setdefault(feature_row[0], set())
    for source_ref in split_refs(feature_row[9]):
        parsed_source = split_ref(source_ref)
        if parsed_source is not None:
            family_symbols.add(parsed_source[1])

semantic_errors = []
evidence_count = 0
exact_join_count = 0
benchmark_count = 0
for feature_row in feature_rows:
    if feature_row[8] not in ("COMPLETE", "PARTIAL"):
        continue
    row_key = "|".join(
        (feature_row[0], feature_row[1], feature_row[4], feature_row[5])
    )
    row_sources = set(split_refs(feature_row[9]))
    for category, feature_column in feature_columns.items():
        for evidence_ref in split_refs(feature_row[feature_column]):
            evidence_count += 1
            parsed_evidence = split_ref(evidence_ref)
            if parsed_evidence is None:
                # The shell structural checks emit the canonical diagnostic.
                continue
            relative_path, evidence_symbol = parsed_evidence
            evidence_path = project_dir / relative_path
            if not evidence_path.is_file():
                continue

            exact_sources = (
                category_sources.get((category, evidence_ref), set())
                & row_sources
            )
            if not exact_sources:
                # A test can legitimately serve several evidence categories;
                # retain the exact row source identity even if this Feature
                # classifies it differently from the per-API ledger.
                exact_sources = (
                    any_category_sources.get(evidence_ref, set())
                    & row_sources
                )
            exact_join = bool(exact_sources)
            if exact_join:
                exact_join_count += 1
                candidate_symbols = {
                    parsed[1]
                    for source in exact_sources
                    if (parsed := split_ref(source)) is not None
                }
            else:
                # Composite Feature rows also carry scenario-level evidence
                # that intentionally is not duplicated into an unrelated
                # per-API ledger row.  It must still execute a registered
                # formal source in the same protocol family; that inventory
                # remains governed by the reverse-provenance and exact
                # non-formal exclusions below.  Exact joins above stay
                # fail-closed whenever a source/evidence association exists.
                candidate_symbols = set(
                    formal_family_symbols.get(feature_row[0], set())
                )

            graph, _bodies = function_graph(relative_path)
            if evidence_symbol not in graph:
                semantic_errors.append(
                    f"{row_key}: {category} evidence is not an executable "
                    f"top-level function: {evidence_ref}"
                )
                continue
            reached = reached_targets(
                graph, evidence_symbol, candidate_symbols
            )
            if not reached:
                qualifier = (
                    "an exact kernel-ledger source API"
                    if exact_join
                    else "a formal same-family source API"
                )
                semantic_errors.append(
                    f"{row_key}: {category} evidence does not reach "
                    f"{qualifier} within two local helper calls: "
                    f"{evidence_ref}"
                )
                continue

            if category != "benchmark":
                continue
            benchmark_count += 1
            main_reachable = local_closure(graph, "main")
            timed_targets = set()
            for timer_function in main_reachable:
                timed_targets.update(
                    timed_reached_targets(
                        graph, _bodies, timer_function, reached
                    )
                )
            if not timed_targets:
                semantic_errors.append(
                    f"{row_key}: benchmark evidence target is not reached "
                    f"from a main-reachable timed entry: {evidence_ref}"
                )
                continue
            if exact_join and evidence_symbol not in main_reachable:
                semantic_errors.append(
                    f"{row_key}: exact-joined benchmark evidence is not "
                    f"reachable from main: {evidence_ref}"
                )

with errors_path.open("a", encoding="utf-8") as handle:
    for error in semantic_errors:
        handle.write(error + "\n")

print(
    "FEATURE_EVIDENCE_REACHABILITY "
    f"refs={evidence_count} exact_joins={exact_join_count} "
    f"benchmarks={benchmark_count}"
)
PY
then
    echo "feature evidence semantic scanner failed" >> "${errors_file}"
fi

list_contains_exact() {
    local values=$1
    local wanted=$2
    local value
    local -a value_array

    IFS=';' read -r -a value_array <<< "${values}"
    for value in "${value_array[@]}"; do
        [[ "${value}" == "${wanted}" ]] && return 0
    done
    return 1
}

validate_owner_evidence_refs() {
    local owner_key=$1
    local category=$2
    local owner_refs=$3
    local required_refs=$4
    local required_ref
    local -a required_ref_array

    IFS=';' read -r -a required_ref_array <<< "${required_refs}"
    for required_ref in "${required_ref_array[@]}"; do
        if ! list_contains_exact "${owner_refs}" "${required_ref}"; then
            echo "${owner_key}: missing kernel-ledger ${category} evidence: ${required_ref}" \
                >> "${errors_file}"
        fi
    done
}

# Enforce semantic ownership and copy-through of the six list-valued evidence
# categories.  Reverse reachability alone is intentionally insufficient: an
# API used by a RedCap scenario, for example, still needs its generic owner.
while IFS='|' read -r owner_family owner_feature owner_source; do
    owner_rows=$(awk -F '\t' -v wanted_family="${owner_family}" \
        -v wanted_feature="${owner_feature}" \
        'NR > 1 && $1 == wanted_family && $5 == wanted_feature { print }' \
        "${matrix}")
    owner_count=$(printf '%s\n' "${owner_rows}" \
        | awk 'NF { count += 1 } END { print count + 0 }')
    owner_key="${owner_family}|${owner_feature}|${owner_source}"
    if (( owner_count != 1 )); then
        echo "${owner_key}: semantic owner must resolve to exactly one Feature row" \
            >> "${errors_file}"
        continue
    fi
    IFS=$'\t' read -r _ _ _ _ _ _ _ _ owner_status owner_sources \
        owner_deterministic owner_edge owner_property owner_differential \
        _ owner_tolerance owner_tolerance_mode owner_benchmark _ _ _ \
        <<< "${owner_rows}"
    if [[ "${owner_status}" != "COMPLETE" && "${owner_status}" != "PARTIAL" ]]; then
        echo "${owner_key}: semantic owner must be COMPLETE or PARTIAL" \
            >> "${errors_file}"
        continue
    fi
    if ! list_contains_exact "${owner_sources}" "${owner_source}"; then
        echo "${owner_key}: semantic owner lacks exact source_symbol" \
            >> "${errors_file}"
        continue
    fi

    kernel_rows=$(awk -F '\t' -v wanted_source="${owner_source}" \
        'NR > 1 && $4 == wanted_source { print }' "${kernel_matrix}")
    kernel_count=$(printf '%s\n' "${kernel_rows}" \
        | awk 'NF { count += 1 } END { print count + 0 }')
    if (( kernel_count != 1 )); then
        echo "${owner_key}: exact source must resolve to one kernel-ledger row" \
            >> "${errors_file}"
        continue
    fi
    IFS=$'\t' read -r _ _ _ _ kernel_deterministic kernel_edge \
        kernel_property kernel_differential _ kernel_tolerance \
        kernel_tolerance_mode kernel_benchmark _ <<< "${kernel_rows}"
    validate_owner_evidence_refs "${owner_key}" deterministic \
        "${owner_deterministic}" "${kernel_deterministic}"
    validate_owner_evidence_refs "${owner_key}" edge \
        "${owner_edge}" "${kernel_edge}"
    validate_owner_evidence_refs "${owner_key}" property \
        "${owner_property}" "${kernel_property}"
    validate_owner_evidence_refs "${owner_key}" differential \
        "${owner_differential}" "${kernel_differential}"
    validate_owner_evidence_refs "${owner_key}" tolerance \
        "${owner_tolerance}" "${kernel_tolerance}"
    validate_owner_evidence_refs "${owner_key}" benchmark \
        "${owner_benchmark}" "${kernel_benchmark}"
    if [[ "${owner_tolerance_mode}" != "mixed" \
        && "${owner_tolerance_mode}" != "${kernel_tolerance_mode}" ]]; then
        echo "${owner_key}: Feature tolerance mode '${owner_tolerance_mode}' does not include kernel mode '${kernel_tolerance_mode}'" \
            >> "${errors_file}"
    fi
done < "${semantic_owners_file}"

for single_spec_feature in NR_TS38211_bounded_PHY_core \
    NR_TS38212_bounded_channel_coding_core; do
    single_spec_sources=$(awk -F '\t' -v wanted_feature="${single_spec_feature}" \
        'NR > 1 && $1 == "nr" && $5 == wanted_feature { print $10 }' \
        "${matrix}")
    while IFS= read -r facade_source; do
        if list_contains_exact "${single_spec_sources}" "${facade_source}"; then
            echo "nr|${single_spec_feature}: cross-specification facade must use the conjunctive owner: ${facade_source}" \
                >> "${errors_file}"
        fi
    done < "${facade_sources_file}"
done

# Reverse reachability gate: every public Bluetooth, LTE, NR, or WLAN source registered in
# the kernel ledger must be named by at least one formal (COMPLETE/PARTIAL)
# Feature row.  A specification path or a test reference is not a substitute
# for the exact production path::symbol identity.
while IFS=$'\t' read -r component kind api source deterministic edge property differential oracle tolerance tolerance_mode benchmark notes; do
    protocol_family=""
    source_prefix=""
    case "${component}" in
        wireless_bluetooth)
            protocol_family="bluetooth"
            source_prefix="wireless_dsp/wireless/bluetooth/"
            ;;
        wireless_matter)
            protocol_family="matter"
            source_prefix="wireless_dsp/wireless/matter/"
            ;;
        wireless_zigbee)
            protocol_family="zigbee"
            source_prefix="wireless_dsp/wireless/zigbee/"
            ;;
        wireless_lte)
            protocol_family="lte"
            source_prefix="wireless_dsp/wireless/lte/"
            ;;
        wireless_nr)
            protocol_family="nr"
            source_prefix="wireless_dsp/wireless/nr/"
            ;;
        wifi|wireless_wifi)
            protocol_family="wifi"
            source_prefix="wireless_dsp/wireless/wifi/"
            ;;
        backend_fixed)
            case "${api}" in
                fixed_nr_*)
                    protocol_family="nr"
                    source_prefix="wireless_dsp/backend/"
                    ;;
                fixed_wifi_*)
                    protocol_family="wifi"
                    source_prefix="wireless_dsp/backend/"
                    ;;
                *) continue ;;
            esac
            ;;
        *) continue ;;
    esac
    if [[ "${source}" != "${source_prefix}"* || "${source}" != *::* ]]; then
        echo "${component}|${api}: protocol ledger source has invalid provenance: ${source}" \
            >> "${errors_file}"
        continue
    fi
    printf '%s|%s|%s\n' "${protocol_family}" "${component}" "${source}" \
        >> "${protocol_sources_file}"
done < <(tail -n +2 "${kernel_matrix}")

sort -u -o "${protocol_sources_file}" "${protocol_sources_file}"
sort -u -o "${formal_protocol_sources_file}" "${formal_protocol_sources_file}"

while IFS='|' read -r protocol_family component source; do
    protocol_identity="${protocol_family}|${component}|${source}"
    formal_identity="${protocol_family}|${source}"
    if rg -q -x -F -- "${protocol_identity}" "${excluded_protocol_sources_file}"; then
        continue
    fi
    if ! rg -q -x -F -- "${formal_identity}" "${formal_protocol_sources_file}"; then
        printf '%s\n' "${protocol_identity}" >> "${orphan_protocol_sources_file}"
        echo "formal Feature reverse-coverage orphan: ${protocol_identity}" \
            >> "${errors_file}"
    fi
done < "${protocol_sources_file}"

while IFS='|' read -r excluded_family excluded_component excluded_source; do
    excluded_identity="${excluded_family}|${excluded_component}|${excluded_source}"
    if ! rg -q -x -F -- "${excluded_identity}" "${protocol_sources_file}"; then
        echo "stale non-formal protocol-source exclusion: ${excluded_identity}" \
            >> "${errors_file}"
    fi
    if rg -q -x -F -- "${excluded_family}|${excluded_source}" \
        "${formal_protocol_sources_file}"; then
        echo "non-formal protocol-source exclusion is also claimed by a formal Feature row: ${excluded_identity}" \
            >> "${errors_file}"
    fi
done < "${excluded_protocol_sources_file}"

for protocol_family in bluetooth matter zigbee lte nr wifi; do
    protocol_total=$(awk -F '|' -v family="${protocol_family}" \
        '$1 == family { count += 1 } END { print count + 0 }' \
        "${protocol_sources_file}")
    protocol_excluded=$(awk -F '|' -v family="${protocol_family}" \
        '$1 == family { count += 1 } END { print count + 0 }' \
        "${excluded_protocol_sources_file}")
    protocol_orphans=$(awk -F '|' -v family="${protocol_family}" \
        '$1 == family { count += 1 } END { print count + 0 }' \
        "${orphan_protocol_sources_file}")
    protocol_covered=$((protocol_total - protocol_excluded - protocol_orphans))
    printf 'PROTOCOL_SOURCE_COVERAGE family=%s ledger=%d formal=%d excluded_nonformal=%d orphans=%d\n' \
        "${protocol_family}" "${protocol_total}" "${protocol_covered}" \
        "${protocol_excluded}" "${protocol_orphans}"
done

printf 'SUMMARY rows=%d COMPLETE=%d PARTIAL=%d MISSING=%d EXCLUDED=%d TRACKING=%d\n' \
    "${rows}" "${complete}" "${partial}" "${missing}" "${excluded}" "${tracking}"

if [[ -s "${errors_file}" ]]; then
    echo "FEATURE COVERAGE STRUCTURAL ERRORS" >&2
    sort -u "${errors_file}" >&2
    exit 2
fi
if (( strict && partial + missing > 0 )); then
    printf 'STRICT FAIL: %d PARTIAL and %d MISSING feature rows remain\n' \
        "${partial}" "${missing}" >&2
    exit 1
fi
if (( partial + missing > 0 )); then
    echo "AUDIT OK (non-strict): formal in-scope feature gaps are explicit"
else
    echo "AUDIT OK: all formal in-scope feature rows are COMPLETE"
fi
