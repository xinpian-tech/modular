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
matrix="${project_dir}/testing/specification_coverage.tsv"

if [[ ! -f "${matrix}" ]]; then
    echo "ERROR missing specification matrix: testing/specification_coverage.tsv" >&2
    exit 2
fi

expected_header=$'family\tspecification\tbaseline\tstatus\tofficial_source\talgorithm_scope\tsource_evidence\ttest_evidence\tboundary'
IFS= read -r actual_header < "${matrix}"
if [[ "${actual_header}" != "${expected_header}" ]]; then
    echo "ERROR specification matrix header does not match the documented schema" >&2
    exit 2
fi

bad_width=$(awk -F '\t' 'NF != 9 { print NR ":" NF }' "${matrix}")
if [[ -n "${bad_width}" ]]; then
    echo "ERROR specification rows must have exactly 9 tab-separated columns:" >&2
    echo "${bad_width}" >&2
    exit 2
fi

audit_tmp=$(mktemp -d)
trap 'rm -r -- "${audit_tmp}"' EXIT
errors_file="${audit_tmp}/errors"
seen_file="${audit_tmp}/seen"
actual_required_file="${audit_tmp}/actual-required"
expected_required_file="${audit_tmp}/expected-required"
: > "${errors_file}"
: > "${seen_file}"
: > "${actual_required_file}"

cat > "${expected_required_file}" <<'EOF'
bluetooth|Bluetooth Core Specification|Bluetooth Core Specification 6.3|PARTIAL|https://www.bluetooth.com/specifications/specs/core-specification-6-3/
ieee802154|IEEE Std 802.15.4|IEEE Std 802.15.4-2024|MISSING|https://standards.ieee.org/ieee/802.15.4/11041/
ieee802154|IEEE/ISO/IEC 8802-15-4|IEEE/ISO/IEC 8802-15-4-2024|MISSING|https://standards.ieee.org/ieee/8802-15-4/11701/
matter|Matter Core Specification|Matter Core Specification 1.6|PARTIAL|https://csa-iot.org/wp-content/uploads/2026/06/23-27349-011_Matter-1.6-Core-Specification.pdf
thread|Thread Specification|Thread Specification 1.4.1|MISSING|https://threadgroup.org/ThreadSpec
zigbee|Zigbee Core Specification|Zigbee Core Specification R23.2|PARTIAL|https://csa-iot.org/wp-content/uploads/2025/11/docs-06-3474-23-csg-zigbee-specificationR23.2_clean.pdf
lte|3GPP TS 36.101 Annex B|3GPP TS 36.101 V18.13.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/36_series/36.101/36101-id0.zip
lte|3GPP TS 36.211|3GPP TS 36.211 V18.0.2|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/36_series/36.211/36211-i02.zip
lte|3GPP TS 36.211 IFDMA short base-sequence tables|3GPP TS 36.211 V18.0.2|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/36_series/36.211/36211-i02.zip
lte|3GPP TS 36.212|3GPP TS 36.212 V18.1.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/36_series/36.212/36212-i10.zip
lte|3GPP TS 36.213|3GPP TS 36.213 V18.3.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/36_series/36.213/36213-i30.zip
lte|3GPP TS 36.214|3GPP TS 36.214 V18.1.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/36_series/36.214/36214-i10.zip
lte|3GPP TS 36.133|3GPP TS 36.133 V18.14.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/36_series/36.133/36133-ie0.zip
lte|3GPP TS 36.101/36.104/36.141/36.508/36.521|Release 18 RF and conformance family|EXCLUDED|https://www.3gpp.org/dynareport/36-series.htm
lte|3GPP TS 36.321/36.331|Release 18 MAC and RRC family|EXCLUDED|https://www.3gpp.org/dynareport/36-series.htm
nr|3GPP TS 38.211|3GPP TS 38.211 V18.9.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.211/38211-i90.zip
nr|3GPP TS 38.212|3GPP TS 38.212 V18.8.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.212/38212-i80.zip
nr|3GPP TS 38.213|3GPP TS 38.213 V18.8.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip
nr|3GPP TS 38.214|3GPP TS 38.214 V18.10.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/38214-ia0.zip
nr|3GPP TS 38.215|3GPP TS 38.215 V18.5.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.215/38215-i50.zip
nr|3GPP TS 38.321 clause 5.1.3|3GPP TS 38.321 V18.10.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-ia0.zip
nr|3GPP TS 38.213 Rel-18 NTN RACH-less handover|3GPP TS 38.213 V18.8.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip
nr|3GPP TS 38.321 Rel-18 NTN RACH-less handover|3GPP TS 38.321 V18.10.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-ia0.zip
nr|3GPP TS 38.331 Rel-18 NTN RACH-less handover|3GPP TS 38.331 V18.10.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-ia0.zip
nr|3GPP TS 38.214 Rel-18 sidelink enhancement|3GPP TS 38.214 V18.10.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/38214-ia0.zip
nr|3GPP TS 38.321 Rel-18 sidelink enhancement|3GPP TS 38.321 V18.10.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/38321-ia0.zip
nr|3GPP TS 38.331 Rel-18 sidelink enhancement|3GPP TS 38.331 V18.10.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-ia0.zip
nr|3GPP TS 38.331 PDCCH monitoring configuration|3GPP TS 38.331 V18.10.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-ia0.zip
nr|3GPP TS 38.213/38.331 PDCCH symbol-level monitoring occasions|3GPP TS 38.213 V18.8.0; 3GPP TS 38.331 V18.10.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/38213-i80.zip
nr|3GPP TS 38.331 monitoringSymbolsWithinSlot configuration|3GPP TS 38.331 V18.10.0|BOUNDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-ia0.zip
nr|3GPP TS 38.101-1 Rel-18 sidelink n47|3GPP TS 38.101-1 V18.14.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.101-1/38101-1-ie0.zip
nr|3GPP TS 38.306 Rel-17 RedCap|3GPP TS 38.306 V17.16.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.306/38306-hg0.zip
nr|3GPP TS 38.133 Rel-17 RedCap|3GPP TS 38.133 V17.22.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-hm0.zip
nr|3GPP TS 38.533 Rel-17 RedCap|3GPP TS 38.533 V17.9.0 delegating V18.8.0|PARTIAL|https://www.3gpp.org/ftp/Specs/archive/38_series/38.533/38533-i80.zip
nr|3GPP TR 38.901|3GPP TR 38.901 V18.1.0|EXCLUDED|https://www.3gpp.org/ftp/Specs/archive/38_series/38.901/38901-i10.zip
nr|3GPP TS 38.133|V18.14.0 ordinary RRM requirements family|MISSING|https://www.3gpp.org/ftp/Specs/archive/38_series/38.133/38133-ie0.zip
nr|3GPP TS 38.101/38.104/38.141/38.508/38.521|Release 18 RF and conformance family|EXCLUDED|https://www.3gpp.org/dynareport/38-series.htm
nr|3GPP TS 38.321/38.331 protocol remainder|Release 18 MAC and RRC family beyond isolated algorithm slices|EXCLUDED|https://www.3gpp.org/dynareport/38-series.htm
wifi|IEEE Std 802.11|IEEE Std 802.11-2024|BOUNDED|https://standards.ieee.org/ieee/802.11/10548/
wifi|IEEE Std 802.11be|IEEE Std 802.11be-2024|BOUNDED|https://standards.ieee.org/ieee/802.11be/7516/
wifi|IEEE 802.11-03/940r4|TGn channel-model reference revision 4|EXCLUDED|https://mentor.ieee.org/802.11/dcn/03/11-03-0940-04-000n-tgn-channel-models.doc
wifi|IEEE 802.11-09/0308r12|TGac channel-model addendum revision 12|EXCLUDED|https://mentor.ieee.org/802.11/dcn/09/11-09-0308-12-00ac-tgac-channel-model-addendum-document.docx
wifi|IEEE 802.11-14/0882r4|TGax channel-model document revision 4|EXCLUDED|https://mentor.ieee.org/802.11/dcn/14/11-14-0882-04-00ax-tgax-channel-model-document.docx
wifi|IEEE 802.11 incorporated alternate PHY and service families|IEEE Std 802.11-2024|PARTIAL|https://standards.ieee.org/ieee/802.11/10548/
wifi|IEEE Std 802.11bh|IEEE Std 802.11bh-2024|PARTIAL|https://standards.ieee.org/ieee/802.11bh/10525/
wifi|IEEE Std 802.11bk|IEEE Std 802.11bk-2025|MISSING|https://standards.ieee.org/ieee/802.11bk/11117/
wifi|IEEE Std 802.11bf|IEEE Std 802.11bf-2025|MISSING|https://standards.ieee.org/ieee/802.11bf/11574/
wifi|IEEE P802.11 revision|Active PAR superseding IEEE Std 802.11-2024|TRACKING|https://standards.ieee.org/ieee/802.11/11852/
wifi|IEEE P802.11bi|Active PAR|TRACKING|https://standards.ieee.org/ieee/802.11bi/12331/
wifi|IEEE P802.11bn|Active PAR|TRACKING|https://standards.ieee.org/ieee/802.11bn/11393/
wifi|IEEE P802.11bp|Active PAR|TRACKING|https://standards.ieee.org/ieee/802.11bp/11592/
wifi|IEEE P802.11bq|Active PAR|TRACKING|https://standards.ieee.org/ieee/802.11bq/11872/
wifi|IEEE P802.11br|Active PAR|TRACKING|https://standards.ieee.org/ieee/802.11br/11993/
wifi|IEEE P802.11bt|Active PAR|TRACKING|https://standards.ieee.org/ieee/802.11bt/12187/
EOF
sort -o "${expected_required_file}" "${expected_required_file}"

validate_evidence_paths() {
    local row_key=$1
    local category=$2
    local refs=$3
    local ref
    local -a ref_array

    IFS=';' read -r -a ref_array <<< "${refs}"
    for ref in "${ref_array[@]}"; do
        if [[ -z "${ref}" || "${ref}" == "-" ]]; then
            echo "${row_key}: BOUNDED row lacks ${category} evidence" >> "${errors_file}"
            continue
        fi
        if [[ "${ref}" == /* || "${ref}" == *'..'* ]]; then
            echo "${row_key}: ${category} path must be project-relative: ${ref}" >> "${errors_file}"
            continue
        fi
        if [[ "${category}" == "source" && "${ref}" != wireless_dsp/* ]]; then
            echo "${row_key}: source evidence must live under wireless_dsp/: ${ref}" >> "${errors_file}"
        fi
        if [[ "${category}" == "test" && "${ref}" != tests/* ]]; then
            echo "${row_key}: test evidence must live under tests/: ${ref}" >> "${errors_file}"
        fi
        if [[ ! -f "${project_dir}/${ref}" ]]; then
            echo "${row_key}: ${category} evidence file does not exist: ${ref}" >> "${errors_file}"
        fi
    done
}

bounded=0
partial=0
missing_rows=0
excluded=0
tracking=0
rows=0
while IFS=$'\t' read -r family specification baseline status official_source algorithm_scope source_evidence test_evidence boundary; do
    ((rows += 1))
    row_key="${family}|${specification}"

    if rg -q -x -F -- "${row_key}" "${seen_file}"; then
        echo "${row_key}: duplicate specification row" >> "${errors_file}"
    else
        echo "${row_key}" >> "${seen_file}"
    fi

    case "${family}" in
        bluetooth|ieee802154|lte|matter|nr|thread|wifi|zigbee) ;;
        *) echo "${row_key}: invalid family '${family}'" >> "${errors_file}" ;;
    esac
    case "${status}" in
        BOUNDED) ((bounded += 1)) ;;
        PARTIAL) ((partial += 1)) ;;
        MISSING) ((missing_rows += 1)) ;;
        EXCLUDED) ((excluded += 1)) ;;
        TRACKING) ((tracking += 1)) ;;
        *) echo "${row_key}: invalid status '${status}'" >> "${errors_file}" ;;
    esac

    if [[ -z "${baseline}" || -z "${algorithm_scope}" || -z "${boundary}" ]]; then
        echo "${row_key}: baseline, algorithm_scope and boundary must be non-empty" >> "${errors_file}"
    fi
    case "${official_source}" in
        https://www.bluetooth.com/*|https://www.etsi.org/*|https://www.3gpp.org/*|https://standards.ieee.org/*|https://www.ieee802.org/*|https://mentor.ieee.org/*|https://threadgroup.org/*|https://www.threadgroup.org/*|https://csa-iot.org/*) ;;
        *) echo "${row_key}: source is not an approved official standards URL: ${official_source}" >> "${errors_file}" ;;
    esac

    if [[ "${status}" == "BOUNDED" || "${status}" == "PARTIAL" ]]; then
        validate_evidence_paths "${row_key}" source "${source_evidence}"
        validate_evidence_paths "${row_key}" test "${test_evidence}"
    elif [[ "${source_evidence}" != "-" || "${test_evidence}" != "-" ]]; then
        echo "${row_key}: ${status} rows must use '-' for executable evidence" >> "${errors_file}"
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
    fi
    printf '%s|%s|%s|%s|%s\n' \
        "${family}" "${specification}" "${baseline}" "${status}" \
        "${official_source}" >> "${actual_required_file}"
done < <(tail -n +2 "${matrix}")

sort -u -o "${actual_required_file}" "${actual_required_file}"
while IFS= read -r missing_required; do
    if [[ -n "${missing_required}" ]]; then
        echo "missing required baseline: ${missing_required}" >> "${errors_file}"
    fi
done < <(comm -23 "${expected_required_file}" "${actual_required_file}")

if [[ -s "${errors_file}" ]]; then
    echo "SPECIFICATION COVERAGE ERRORS" >&2
    sort -u "${errors_file}" >&2
    printf 'SUMMARY rows=%d BOUNDED=%d PARTIAL=%d MISSING=%d EXCLUDED=%d TRACKING=%d\n' \
        "${rows}" "${bounded}" "${partial}" "${missing_rows}" \
        "${excluded}" "${tracking}" >&2
    exit 2
fi

printf 'SUMMARY rows=%d BOUNDED=%d PARTIAL=%d MISSING=%d EXCLUDED=%d TRACKING=%d\n' \
    "${rows}" "${bounded}" "${partial}" "${missing_rows}" \
    "${excluded}" "${tracking}"

if (( strict && partial + missing_rows > 0 )); then
    printf 'STRICT FAIL: %d PARTIAL and %d MISSING specification rows remain\n' \
        "${partial}" "${missing_rows}" >&2
    exit 1
fi
