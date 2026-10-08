#!/usr/bin/env bash

set -u
set -o pipefail

usage() {
    cat <<'EOF'
Usage: scripts/audit_ratified_authorities.sh [--verify-downloads]

Fail-closed authority gate for implementation-maturity claims.  BOUNDED,
PARTIAL and COMPLETE describe executable evidence maturity only; they do not
grant production authority.  The default mode validates
testing/authority_manifest.tsv and requires every such row to resolve every
exact normative specification/version token to a qualified PRODUCTION
authority before the implementation may be production-eligible.

--verify-downloads additionally downloads direct official artifacts into a
temporary directory and verifies their recorded SHA-256 and file magic.  A
licensed artifact may instead be supplied in MWDSP_AUTHORITY_ARTIFACT_DIR;
the audit locates it by its pinned hash and never hashes landing-page HTML.
Licensed IEEE, Bluetooth SIG, Thread Group and CSA production records also
require an artifact-bound IMPLEMENTATION_RIGHTS_CONFIRMED company/user
attestation.  The reviewed repository receipt is used by default;
MWDSP_LICENSE_RIGHTS_ATTESTATION_FILE may select another user-controlled
three-column receipt.

Exit 0: all implementation-maturity claims are production-authorized.
Exit 1: qualification/download blockers remain.
Exit 2: manifest or matrix structure is invalid.
EOF
}

verify_downloads=0
if (( $# > 1 )); then
    usage >&2
    exit 2
fi
if (( $# == 1 )); then
    if [[ "$1" != "--verify-downloads" ]]; then
        usage >&2
        exit 2
    fi
    verify_downloads=1
fi

if ! command -v rg >/dev/null 2>&1 \
    || ! command -v sha256sum >/dev/null 2>&1; then
    echo "ERROR authority audit requires rg and sha256sum" >&2
    exit 2
fi
if (( verify_downloads )) \
    && { ! command -v curl >/dev/null 2>&1 \
        || ! command -v od >/dev/null 2>&1; }; then
    echo "ERROR --verify-downloads requires curl, sha256sum and od" >&2
    exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "${script_dir}/.." && pwd)
artifact_cache_dir=${MWDSP_AUTHORITY_ARTIFACT_DIR:-}
if [[ -n "${artifact_cache_dir}" && ! -d "${artifact_cache_dir}" ]]; then
    echo "ERROR MWDSP_AUTHORITY_ARTIFACT_DIR is not a directory" >&2
    exit 2
fi
manifest="${project_dir}/testing/authority_manifest.tsv"
spec_matrix="${project_dir}/testing/specification_coverage.tsv"
feature_matrix="${project_dir}/testing/feature_coverage.tsv"
kernel_matrix="${project_dir}/testing/kernel_coverage.tsv"
reference_map="${project_dir}/testing/source_authority_references.tsv"
default_license_rights_attestation="${project_dir}/testing/license_rights_attestation.tsv"

# The manifest is the human-reviewed trust receipt for exact status/date,
# clause scope, errata disposition and artifact identity.  Pin its complete
# bytes here so a plausible-looking metadata or digest mutation cannot pass
# the normal/full gate merely because it remains syntactically valid.  A
# deliberate authority refresh must review the official records and update
# this receipt digest in the same change.
expected_manifest_sha256=557017ba6da4164ba9c6835a74dbb2d810a4345c89347d7ea387595455d0e8d0
expected_default_attestation_sha256=a56191aea823ae4cfa2affa6f2c22de8b5838707ec4b8769a0da3ec14c38cb9a

for required_file in "${manifest}" "${spec_matrix}" "${feature_matrix}" "${kernel_matrix}" "${reference_map}" "${default_license_rights_attestation}"; do
    if [[ ! -f "${required_file}" ]]; then
        printf 'ERROR missing authority input: %s\n' "${required_file}" >&2
        exit 2
    fi
done

actual_manifest_sha256=$(sha256sum "${manifest}" | awk '{ print $1 }')
if [[ "${actual_manifest_sha256}" != "${expected_manifest_sha256}" ]]; then
    echo "ERROR authority manifest differs from the reviewed trust receipt: expected ${expected_manifest_sha256}, got ${actual_manifest_sha256}" >&2
    exit 2
fi

license_rights_attestation=${MWDSP_LICENSE_RIGHTS_ATTESTATION_FILE:-${default_license_rights_attestation}}
if [[ ! -f "${license_rights_attestation}" ]]; then
    echo "ERROR licensed-authority attestation is not a file: ${license_rights_attestation}" >&2
    exit 2
fi
expected_attestation_header=$'authority_id\tartifact_sha256\tauthorization'
IFS= read -r actual_attestation_header < "${license_rights_attestation}"
if [[ "${actual_attestation_header}" != "${expected_attestation_header}" ]]; then
    echo "ERROR licensed-authority attestation header does not match the 3-column schema" >&2
    exit 2
fi
bad_attestation_width=$(awk -F '\t' 'NF != 3 { print NR ":" NF }' "${license_rights_attestation}")
if [[ -n "${bad_attestation_width}" ]]; then
    echo "ERROR licensed-authority attestations must have exactly 3 tab-separated columns:" >&2
    echo "${bad_attestation_width}" >&2
    exit 2
fi
if ! awk -F '\t' '
    NR == 1 { next }
    $1 !~ /^[a-z0-9][a-z0-9._-]*$/ { exit 1 }
    $2 !~ /^[0-9a-f]{64}$/ { exit 1 }
    $3 != "IMPLEMENTATION_RIGHTS_CONFIRMED" { exit 1 }
    seen[$1]++ { exit 1 }
' "${license_rights_attestation}"; then
    echo "ERROR licensed-authority attestation contains an invalid or duplicate record" >&2
    exit 2
fi
if [[ "${license_rights_attestation}" == "${default_license_rights_attestation}" ]]; then
    actual_attestation_sha256=$(sha256sum "${license_rights_attestation}" | awk '{ print $1 }')
    if [[ "${actual_attestation_sha256}" != "${expected_default_attestation_sha256}" ]]; then
        echo "ERROR default licensed-authority attestation differs from the reviewed receipt: expected ${expected_default_attestation_sha256}, got ${actual_attestation_sha256}" >&2
        exit 2
    fi
fi

expected_header=$'authority_id\tfamily\tauthority\tsource_kind\texact_spec\tversion\tauthority_status\tstatus_date\tofficial_url\tdownload_sha256\tclauses\terrata_status\terrata_review_date\terrata_url\tqualification\tmatrix_match\tnotes'
IFS= read -r actual_header < "${manifest}"
if [[ "${actual_header}" != "${expected_header}" ]]; then
    echo "ERROR authority manifest header does not match the 17-column schema" >&2
    exit 2
fi

bad_width=$(awk -F '\t' 'NF != 17 { print NR ":" NF }' "${manifest}")
if [[ -n "${bad_width}" ]]; then
    echo "ERROR authority rows must have exactly 17 tab-separated columns:" >&2
    echo "${bad_width}" >&2
    exit 2
fi

audit_tmp=$(mktemp -d "${TMPDIR:-/tmp}/mwdsp-authority-audit.XXXXXX")
cleanup() {
    rm -r -- "${audit_tmp}"
}
trap cleanup EXIT

errors_file="${audit_tmp}/structural-errors"
blockers_file="${audit_tmp}/qualification-blockers"
warnings_file="${audit_tmp}/warnings"
seen_ids_file="${audit_tmp}/seen-ids"
matches_file="${audit_tmp}/matches"
urls_file="${audit_tmp}/urls"
downloads_file="${audit_tmp}/download-blockers"
qualified_sources_file="${audit_tmp}/qualified-claim-sources"
blocked_sources_file="${audit_tmp}/blocked-claim-sources"
formal_feature_sources_file="${audit_tmp}/formal-feature-sources"
qualified_feature_sources_file="${audit_tmp}/qualified-feature-sources"
blocked_feature_sources_file="${audit_tmp}/blocked-feature-sources"
: > "${errors_file}"
: > "${blockers_file}"
: > "${warnings_file}"
: > "${seen_ids_file}"
: > "${matches_file}"
: > "${urls_file}"
: > "${downloads_file}"
: > "${qualified_sources_file}"
: > "${blocked_sources_file}"
: > "${formal_feature_sources_file}"
: > "${qualified_feature_sources_file}"
: > "${blocked_feature_sources_file}"

is_full_date() {
    local canonical
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    canonical=$(date -u -d "$1" +%F 2>/dev/null) || return 1
    [[ "${canonical}" == "$1" ]]
}

is_record_date() {
    local canonical
    if [[ "$1" == "-" || "$1" =~ ^[0-9]{4}$ ]]; then
        return 0
    fi
    if [[ "$1" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
        canonical=$(date -u -d "$1-01" +%Y-%m 2>/dev/null) || return 1
        [[ "${canonical}" == "$1" ]]
        return
    fi
    is_full_date "$1"
}

is_production_date() {
    is_full_date "$1"
}

release_freeze_date() {
    case "$1" in
        15) printf '%s\n' '2019-06-07' ;;
        16) printf '%s\n' '2020-07-03' ;;
        17) printf '%s\n' '2022-06-10' ;;
        18) printf '%s\n' '2024-06-21' ;;
        19) printf '%s\n' '2025-12-12' ;;
        *) return 1 ;;
    esac
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

audit_date=$(date -u +%F)

authority_rows=0
production_authorities=0
blocked_authorities=0
while IFS=$'\t' read -r authority_id family authority source_kind exact_spec version authority_status status_date official_url download_sha256 clauses errata_status errata_review_date errata_url qualification matrix_match notes; do
    ((authority_rows += 1))
    row_key="${authority_id}"

    if [[ ! "${authority_id}" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
        echo "${row_key}: invalid authority_id" >> "${errors_file}"
    elif rg -q -x -F -- "${authority_id}" "${seen_ids_file}"; then
        echo "${row_key}: duplicate authority_id" >> "${errors_file}"
    else
        echo "${authority_id}" >> "${seen_ids_file}"
    fi

    case "${family}" in
        lte|nr|wifi|bluetooth|ieee802154|thread|matter|zigbee) ;;
        *) echo "${row_key}: invalid family '${family}'" >> "${errors_file}" ;;
    esac
    case "${authority}" in
        3GPP|ETSI|IEEE-SA|IEEE-802.11|Bluetooth-SIG|Thread-Group|CSA) ;;
        *) echo "${row_key}: invalid authority '${authority}'" >> "${errors_file}" ;;
    esac
    case "${source_kind}" in
        NORMATIVE_SPEC|STANDARD|AMENDMENT|TR|WORK_ITEM|PAR|WG_DOC) ;;
        *) echo "${row_key}: invalid source_kind '${source_kind}'" >> "${errors_file}" ;;
    esac
    case "${authority_status}" in
        PUBLISHED|FROZEN|ADOPTED|IN_FORCE|APPROVED|ACTIVE|RELEASED|SUPERSEDED) ;;
        *) echo "${row_key}: invalid authority_status '${authority_status}'" >> "${errors_file}" ;;
    esac
    case "${errata_status}" in
        REVIEWED_NONE|INCORPORATED|NOT_REVIEWED|NOT_APPLICABLE|OPEN_BLOCKING) ;;
        *) echo "${row_key}: invalid errata_status '${errata_status}'" >> "${errors_file}" ;;
    esac
    case "${qualification}" in
        PRODUCTION|REFERENCE_ONLY|INVENTORY_ONLY|TRACKING|EXCLUDED|BLOCKED_ERRATA|BLOCKED_LICENSE|BLOCKED_ACCESS|BLOCKED_METADATA|BLOCKED_DOWNLOAD) ;;
        *) echo "${row_key}: invalid qualification '${qualification}'" >> "${errors_file}" ;;
    esac

    if [[ "${source_kind}" =~ ^(NORMATIVE_SPEC|STANDARD|AMENDMENT)$ \
        && ( "${qualification}" == "EXCLUDED" || "${qualification}" == BLOCKED_* ) ]]; then
        case "${authority}:${authority_status}" in
            3GPP:PUBLISHED|3GPP:FROZEN|ETSI:PUBLISHED|\
            IEEE-SA:ACTIVE|IEEE-SA:PUBLISHED|\
            Bluetooth-SIG:ADOPTED|\
            Thread-Group:RELEASED|Thread-Group:ADOPTED|\
            Thread-Group:PUBLISHED|CSA:RELEASED|CSA:ADOPTED|CSA:PUBLISHED) ;;
            *) echo "${row_key}: blocked/excluded final artifact status is not valid for ${authority}" >> "${errors_file}" ;;
        esac
    fi
    if [[ "${qualification}" == "EXCLUDED" ]]; then
        if [[ ! "${source_kind}" =~ ^(NORMATIVE_SPEC|STANDARD|AMENDMENT)$ ]]; then
            echo "${row_key}: EXCLUDED identity must name a final normative artifact" >> "${errors_file}"
        fi
        if ! is_sha256 "${download_sha256}"; then
            echo "${row_key}: EXCLUDED final artifact requires a downloaded SHA-256" >> "${errors_file}"
        fi
    fi

    if [[ -z "${exact_spec}" || -z "${version}" || -z "${clauses}" \
        || -z "${matrix_match}" || -z "${notes}" ]]; then
        echo "${row_key}: exact_spec/version/clauses/matrix_match/notes must be non-empty" >> "${errors_file}"
    fi
    if ! is_record_date "${status_date}"; then
        echo "${row_key}: status_date must be '-', YYYY, YYYY-MM, or YYYY-MM-DD" >> "${errors_file}"
    fi
    if ! is_record_date "${errata_review_date}"; then
        echo "${row_key}: errata_review_date must be '-', YYYY, YYYY-MM, or YYYY-MM-DD" >> "${errors_file}"
    fi
    if [[ ! "${official_url}" =~ ^https:// ]]; then
        echo "${row_key}: official_url must use https" >> "${errors_file}"
    fi
    if [[ "${download_sha256}" != "-" ]] && ! is_sha256 "${download_sha256}"; then
        echo "${row_key}: download_sha256 must be '-' or 64 lowercase hexadecimal characters" >> "${errors_file}"
    fi
    if [[ "${errata_url}" != "-" && ! "${errata_url}" =~ ^https:// ]]; then
        echo "${row_key}: errata_url must be '-' or an https URL" >> "${errors_file}"
    fi

    case "${authority}:${source_kind}:${official_url}" in
        3GPP:NORMATIVE_SPEC:https://www.3gpp.org/ftp/Specs/archive/*) ;;
        3GPP:TR:https://www.3gpp.org/ftp/Specs/archive/*) ;;
        3GPP:WORK_ITEM:https://portal.3gpp.org/*) ;;
        3GPP:WORK_ITEM:https://www.3gpp.org/ftp/TSG_RAN/*) ;;
        ETSI:NORMATIVE_SPEC:https://www.etsi.org/deliver/*) ;;
        ETSI:TR:https://www.etsi.org/deliver/*) ;;
        IEEE-SA:STANDARD:https://standards.ieee.org/*) ;;
        IEEE-SA:AMENDMENT:https://standards.ieee.org/*) ;;
        IEEE-SA:PAR:https://standards.ieee.org/*) ;;
        IEEE-802.11:WG_DOC:https://mentor.ieee.org/*) ;;
        IEEE-802.11:WG_DOC:https://www.ieee802.org/*) ;;
        Bluetooth-SIG:STANDARD:https://www.bluetooth.com/*) ;;
        Thread-Group:STANDARD:https://threadgroup.org/*) ;;
        Thread-Group:STANDARD:https://www.threadgroup.org/*) ;;
        CSA:STANDARD:https://csa-iot.org/*) ;;
        *) echo "${row_key}: authority/source_kind does not match its official URL" >> "${errors_file}" ;;
    esac

    if [[ "${source_kind}" == "PAR" \
        || ( "${source_kind}" == "WORK_ITEM" && "${official_url}" == https://portal.3gpp.org/* ) ]]; then
        if [[ "${download_sha256}" != "-" ]]; then
            echo "${row_key}: inventory/PAR landing pages cannot carry an artifact hash" >> "${errors_file}"
        fi
    fi
    if [[ "${source_kind}" == "WORK_ITEM" \
        && "${official_url}" == https://www.3gpp.org/ftp/TSG_RAN/* \
        && "${download_sha256}" == "-" ]]; then
        echo "${row_key}: direct official Work Item artifacts require a SHA-256" >> "${errors_file}"
    fi
    eligible=0
    if [[ "${qualification}" == "PRODUCTION" ]]; then
        ((production_authorities += 1))
        eligible=1
        if [[ "${authority}" =~ ^(3GPP|ETSI)$ && "${version}" =~ ^V([0-9]+)\. ]]; then
            release_major=${BASH_REMATCH[1]}
            if (( release_major >= 20 )); then
                echo "${row_key}: Rel-${release_major} is not a frozen PRODUCTION baseline" >> "${errors_file}"
                eligible=0
            elif (( release_major >= 15 )); then
                frozen_date=$(release_freeze_date "${release_major}") || frozen_date=""
                if [[ -z "${frozen_date}" || "${audit_date}" < "${frozen_date}" ]]; then
                    echo "${row_key}: Rel-${release_major} is not frozen as of ${audit_date}" >> "${errors_file}"
                    eligible=0
                fi
            fi
        fi
        case "${source_kind}" in
            NORMATIVE_SPEC|STANDARD|AMENDMENT) ;;
            *)
                echo "${row_key}: PRODUCTION cannot use source_kind ${source_kind}" >> "${errors_file}"
                eligible=0
                ;;
        esac
        case "${authority}" in
            IEEE-SA|Bluetooth-SIG|Thread-Group|CSA)
                if [[ -z "${license_rights_attestation}" \
                    || ! -f "${license_rights_attestation}" ]]; then
                    echo "${row_key}: PRODUCTION requires MWDSP_LICENSE_RIGHTS_ATTESTATION_FILE for licensed authority ${authority}" >> "${errors_file}"
                    eligible=0
                elif ! awk -F '\t' \
                    -v wanted_id="${authority_id}" \
                    -v wanted_hash="${download_sha256}" \
                    '$1 == wanted_id && $2 == wanted_hash && $3 == "IMPLEMENTATION_RIGHTS_CONFIRMED" { found=1 } END { exit(found ? 0 : 1) }' \
                    "${license_rights_attestation}"; then
                    echo "${row_key}: licensed-authority attestation must bind authority_id, artifact SHA-256, and IMPLEMENTATION_RIGHTS_CONFIRMED" >> "${errors_file}"
                    eligible=0
                fi
                ;;
        esac
        case "${authority}:${authority_status}" in
            3GPP:PUBLISHED|3GPP:FROZEN|ETSI:PUBLISHED|\
            IEEE-SA:ACTIVE|IEEE-SA:PUBLISHED|\
            Bluetooth-SIG:ADOPTED|\
            Thread-Group:RELEASED|Thread-Group:ADOPTED|\
            Thread-Group:PUBLISHED|CSA:RELEASED|CSA:ADOPTED|CSA:PUBLISHED) ;;
            *)
                echo "${row_key}: PRODUCTION status is not valid for ${authority}" >> "${errors_file}"
                eligible=0
                ;;
        esac
        if ! is_production_date "${status_date}"; then
            echo "${row_key}: PRODUCTION requires an official YYYY-MM-DD status_date" >> "${errors_file}"
            eligible=0
        elif [[ "${status_date}" > "${audit_date}" ]]; then
            echo "${row_key}: PRODUCTION status_date is in the future" >> "${errors_file}"
            eligible=0
        fi
        if ! is_sha256 "${download_sha256}"; then
            echo "${row_key}: PRODUCTION requires a downloaded artifact SHA-256" >> "${errors_file}"
            eligible=0
        fi
        if [[ "${clauses^^}" =~ (UNRESOLVED|DECLARED_|INVENTORY|PAR\.SCOPE|TBD|PLACEHOLDER) \
            || "${clauses^^}" =~ (^|[^A-Z0-9])(XX|YY|ZZ)([^A-Z0-9]|$) ]]; then
            echo "${row_key}: PRODUCTION requires resolved exact clauses" >> "${errors_file}"
            eligible=0
        fi
        if [[ "${clauses}" == "-" || "${clauses^^}" == "ALL" \
            || ";${clauses^^};" == *';ALL;'* ]]; then
            echo "${row_key}: PRODUCTION clause scope cannot be '-' or ALL" >> "${errors_file}"
            eligible=0
        fi
        while IFS= read -r scope_fragment; do
            normalized_scope_fragment=$(printf '%s\n' "${scope_fragment}" \
                | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/^[Cc]lauses?[[:space:]]+//; s/[[:space:]]+//g' \
                | tr '[:upper:]' '[:lower:]')
            if [[ "${normalized_scope_fragment}" =~ ^[0-9]+[a-z]*([.][0-9]+[a-z]*)*(-[0-9]+[a-z]*([.][0-9]+[a-z]*)*)?$ \
                || "${normalized_scope_fragment}" =~ ^annex(es)?[a-z]+(and[a-z]+)?([.][0-9]+[a-z]*)*(-[a-z]+([.][0-9]+[a-z]*)*)?$ \
                || "${normalized_scope_fragment}" =~ ^tables?[0-9a-z.-]+((to|through|and)[0-9a-z.-]+)*$ ]]; then
                continue
            fi
            echo "${row_key}: PRODUCTION clause scope fragment is not an exact clause, Annex, or Table identity: '${scope_fragment}'" >> "${errors_file}"
            eligible=0
        done < <(printf '%s\n' "${clauses}" | tr ';' '\n')
        case "${errata_status}" in
            REVIEWED_NONE|INCORPORATED) ;;
            *)
                echo "${row_key}: PRODUCTION requires completed non-blocking errata qualification" >> "${errors_file}"
                eligible=0
                ;;
        esac
        if ! is_production_date "${errata_review_date}"; then
            echo "${row_key}: PRODUCTION requires an official YYYY-MM-DD errata_review_date" >> "${errors_file}"
            eligible=0
        elif [[ "${errata_review_date}" > "${audit_date}" ]]; then
            echo "${row_key}: PRODUCTION errata_review_date is in the future" >> "${errors_file}"
            eligible=0
        fi
        if [[ ! "${errata_url}" =~ ^https:// ]]; then
            echo "${row_key}: PRODUCTION requires an official errata qualification URL" >> "${errors_file}"
            eligible=0
        fi
    elif [[ "${qualification}" == BLOCKED_* ]]; then
        ((blocked_authorities += 1))
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${matrix_match}" "${authority_id}" "${family}" "${source_kind}" \
        "${qualification}" "${eligible}" >> "${matches_file}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${official_url}" "${authority_id}" "${download_sha256}" \
        "${source_kind}" "${qualification}" "${eligible}" >> "${urls_file}"
done < <(tail -n +2 "${manifest}")

if [[ -s "${errors_file}" ]]; then
    echo "AUTHORITY MANIFEST STRUCTURAL ERRORS" >&2
    sort -u "${errors_file}" >&2
    printf 'SUMMARY authority_rows=%d production=%d blocked=%d\n' \
        "${authority_rows}" "${production_authorities}" "${blocked_authorities}" >&2
    exit 2
fi

expected_reference_header=$'source_symbol_pattern\tnormative_authority_ids\treference_authority_ids\treference_role\tnotes'
IFS= read -r actual_reference_header < "${reference_map}"
if [[ "${actual_reference_header}" != "${expected_reference_header}" ]]; then
    echo "ERROR source-authority reference map header does not match the 5-column schema" >&2
    exit 2
fi
bad_reference_width=$(awk -F '\t' 'NF != 5 { print NR ":" NF }' "${reference_map}")
if [[ -n "${bad_reference_width}" ]]; then
    echo "ERROR source-authority reference rows must have exactly 5 tab-separated columns:" >&2
    echo "${bad_reference_width}" >&2
    exit 2
fi

reference_map_rows=0
seen_reference_patterns="${audit_tmp}/seen-reference-patterns"
: > "${seen_reference_patterns}"
while IFS=$'\t' read -r source_pattern normative_ids reference_ids reference_role reference_notes; do
    ((reference_map_rows += 1))
    if [[ "${source_pattern}" != *'::*' ]]; then
        echo "reference:${source_pattern}: source_symbol_pattern must end in ::*" >> "${errors_file}"
        continue
    fi
    source_path=${source_pattern%::*}
    if [[ ! -f "${project_dir}/${source_path}" ]]; then
        echo "reference:${source_pattern}: source path does not exist" >> "${errors_file}"
    fi
    if rg -q -x -F -- "${source_pattern}" "${seen_reference_patterns}"; then
        echo "reference:${source_pattern}: duplicate source mapping" >> "${errors_file}"
    else
        echo "${source_pattern}" >> "${seen_reference_patterns}"
    fi
    if [[ ! "${reference_role}" =~ ^(CROSS_CHECK_ONLY|REFERENCE_PROFILE_ONLY)$ || -z "${reference_notes}" ]]; then
        echo "reference:${source_pattern}: role must be CROSS_CHECK_ONLY or REFERENCE_PROFILE_ONLY and notes must be non-empty" >> "${errors_file}"
    fi
    if [[ "${reference_role}" == "REFERENCE_PROFILE_ONLY" ]]; then
        if [[ "${normative_ids}" != "-" ]]; then
            echo "reference:${source_pattern}: a non-normative reference profile must use '-' for normative_authority_ids" >> "${errors_file}"
        fi
    else
        IFS=';' read -r -a mapped_normative_ids <<< "${normative_ids}"
        for normative_id in "${mapped_normative_ids[@]}"; do
            normative_match=$(awk -F '\t' -v wanted="${normative_id}" \
                '$2 == wanted && $4 ~ /^(STANDARD|AMENDMENT|NORMATIVE_SPEC)$/ { print }' "${matches_file}")
            if [[ -z "${normative_match}" ]]; then
                echo "reference:${source_pattern}: normative authority '${normative_id}' is absent or is not a final normative artifact" >> "${errors_file}"
            fi
        done
    fi
    IFS=';' read -r -a mapped_reference_ids <<< "${reference_ids}"
    if (( ${#mapped_reference_ids[@]} == 0 )); then
        echo "reference:${source_pattern}: at least one reference authority is required" >> "${errors_file}"
    fi
    for reference_id in "${mapped_reference_ids[@]}"; do
        reference_match=$(awk -F '\t' -v wanted="${reference_id}" \
            '$2 == wanted && $4 == "WG_DOC" && $5 == "REFERENCE_ONLY" { print }' "${matches_file}")
        if [[ -z "${reference_match}" ]]; then
            echo "reference:${source_pattern}: '${reference_id}' is not a WG_DOC/REFERENCE_ONLY authority" >> "${errors_file}"
        fi
        reference_hash_match=$(awk -F '\t' -v wanted="${reference_id}" \
            '$2 == wanted && $3 ~ /^[0-9a-f]{64}$/ { print }' "${urls_file}")
        if [[ -z "${reference_hash_match}" ]]; then
            echo "reference:${source_pattern}: '${reference_id}' lacks a pinned downloaded artifact SHA-256" >> "${errors_file}"
        fi
    done
    if [[ -f "${project_dir}/${source_path}" ]]; then
        while IFS= read -r reference_url; do
            [[ -z "${reference_url}" ]] && continue
            url_reference_id=$(awk -F '\t' -v wanted="${reference_url}" \
                '$1 == wanted && $4 == "WG_DOC" && $5 == "REFERENCE_ONLY" { print $2 }' "${urls_file}")
            if [[ -z "${url_reference_id}" ]]; then
                echo "reference:${source_pattern}: source WG URL lacks a WG_DOC/REFERENCE_ONLY authority: ${reference_url}" >> "${errors_file}"
            elif [[ ";${reference_ids};" != *";${url_reference_id};"* ]]; then
                echo "reference:${source_pattern}: source WG URL authority '${url_reference_id}' is absent from its explicit mapping" >> "${errors_file}"
            fi
        done < <(rg -o 'https://(mentor\.ieee\.org|www\.ieee802\.org)/[^[:space:])>"`]*' \
            "${project_dir}/${source_path}" | sort -u)

        # Historical WG identifiers are sometimes cited without a URL (for
        # example, a DCN, ballot number or superseded public draft).  Resolve
        # those tokens against the same pinned REFERENCE_ONLY records so that
        # omitting a URL cannot bypass provenance registration.
        while IFS= read -r reference_token; do
            [[ -z "${reference_token}" ]] && continue
            token_reference_ids=$(awk -F '\t' -v wanted="${reference_token}" '
                BEGIN { wanted = tolower(wanted) }
                $4 == "WG_DOC" && $15 == "REFERENCE_ONLY" {
                    haystack = tolower($5 " " $9 " " $16)
                    if (index(haystack, wanted) > 0) print $1
                }
            ' "${manifest}")
            if [[ -z "${token_reference_ids}" ]]; then
                echo "reference:${source_pattern}: historical identifier lacks a pinned WG_DOC/REFERENCE_ONLY authority: ${reference_token}" >> "${errors_file}"
                continue
            fi
            token_is_mapped=0
            while IFS= read -r token_reference_id; do
                [[ -z "${token_reference_id}" ]] && continue
                if [[ ";${reference_ids};" == *";${token_reference_id};"* ]]; then
                    token_is_mapped=1
                    break
                fi
            done <<< "${token_reference_ids}"
            if (( ! token_is_mapped )); then
                echo "reference:${source_pattern}: historical identifier '${reference_token}' is absent from its explicit mapping" >> "${errors_file}"
            fi
        done < <(rg -o '11-[0-9]{2}/[0-9]{4}r[0-9]+|P802\.11[a-z]*/D[0-9]+(\.[0-9]+)?|LB[0-9]{3,4}' \
            "${project_dir}/${source_path}" | sort -u)
    fi
done < <(tail -n +2 "${reference_map}")

while IFS= read -r source_with_reference; do
    relative_source=${source_with_reference#"${project_dir}/"}
    if ! rg -q -x -F -- "${relative_source}::*" "${seen_reference_patterns}"; then
        echo "reference:${relative_source}: source contains an explicit WG URL but has no source-authority mapping" >> "${errors_file}"
    fi
done < <(rg -l 'https://(mentor\.ieee\.org|www\.ieee802\.org)/' \
    "${project_dir}/wireless_dsp" | sort -u)

while IFS= read -r source_with_identifier; do
    relative_source=${source_with_identifier#"${project_dir}/"}
    if ! rg -q -x -F -- "${relative_source}::*" "${seen_reference_patterns}"; then
        echo "reference:${relative_source}: source contains a historical WG/draft identifier but has no source-authority mapping" >> "${errors_file}"
    fi
done < <(rg -l '11-[0-9]{2}/[0-9]{4}r[0-9]+|P802\.11[a-z]*/D[0-9]+(\.[0-9]+)?|LB[0-9]{3,4}' \
    "${project_dir}/wireless_dsp" | sort -u)

if [[ -s "${errors_file}" ]]; then
    echo "SOURCE-AUTHORITY REFERENCE STRUCTURAL ERRORS" >&2
    sort -u "${errors_file}" >&2
    exit 2
fi

extract_normative_tokens() {
    local claim_text=$1
    local base_spec delegated_version delegation_text token raw_token
    local candidates
    candidates=$({
        printf '%s\n' "${claim_text}" \
            | rg -o 'ETSI (TS|TR) [0-9]{3} [0-9]{3} V[0-9]+\.[0-9]+\.[0-9]+' || true
        printf '%s\n' "${claim_text}" \
            | rg -o 'TS [0-9]{2}\.[0-9]{3}(-[0-9])? V[0-9]+\.[0-9]+\.[0-9]+' \
            | sed 's/^/3GPP /' || true
        printf '%s\n' "${claim_text}" \
            | rg -o 'IEEE Std 802\.(11[a-z]*|15\.4)-[0-9]{4}' || true
        printf '%s\n' "${claim_text}" \
            | rg -o 'IEEE/ISO/IEC 8802-15-4-[0-9]{4}' || true
        printf '%s\n' "${claim_text}" \
            | rg -o 'Bluetooth Core Specification [0-9]+\.[0-9]+' || true
        printf '%s\n' "${claim_text}" \
            | rg -o 'Thread Specification [0-9]+\.[0-9]+\.[0-9]+' || true
        printf '%s\n' "${claim_text}" \
            | rg -o 'Matter Core Specification [0-9]+\.[0-9]+' || true
        printf '%s\n' "${claim_text}" \
            | rg -o 'Zigbee Core Specification R[0-9]+\.[0-9]+' || true
    } | sort -u)
    while IFS= read -r token; do
        [[ -z "${token}" ]] && continue
        # A regex substring is not an exact specification identity.  Reject
        # extensions such as V18.1.0PLACEHOLDER or 802.11-2024-draft by
        # requiring identifier boundaries around the complete token.
        raw_token=${token#3GPP }
        if contains_identity_literal "${claim_text}" "${token}" \
            || { [[ "${token}" == 3GPP\ * ]] \
                && contains_identity_literal "${claim_text}" "${raw_token}"; }; then
            printf '%s\n' "${token}"
        fi
    done <<< "${candidates}"
    if [[ "${claim_text}" =~ (3GPP[[:space:]]TS[[:space:]][0-9]{2}\.[0-9]{3}(-[0-9])?)[[:space:]]V[0-9]+\.[0-9]+\.[0-9]+[[:space:]]delegating[[:space:]]V([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        base_spec=${BASH_REMATCH[1]}
        delegated_version=${BASH_REMATCH[3]}
        delegation_text=${BASH_REMATCH[0]}
        if contains_identity_literal "${claim_text}" "${delegation_text}"; then
            printf '%s V%s\n' "${base_spec}" "${delegated_version}"
        fi
    fi
}

contains_identity_literal() {
    local text=$1
    local literal=$2

    [[ -n "${literal}" ]] || return 1
    awk -v text="${text}" -v literal="${literal}" '
        BEGIN {
            offset = 1
            while (offset <= length(text)) {
                relative = index(substr(text, offset), literal)
                if (relative == 0) exit 1
                start = offset + relative - 1
                before = start > 1 ? substr(text, start - 1, 1) : ""
                after_at = start + length(literal)
                after = after_at <= length(text) ? substr(text, after_at, 1) : ""
                if (before !~ /[[:alnum:]_.-]/ && after !~ /[[:alnum:]_.-]/) exit 0
                offset = start + 1
            }
            exit 1
        }
    '
}

maturity_claim_rows=0
production_eligible_maturity_claims=0
authority_blocked_maturity_claims=0
nonproduction_identity_rows=0
resolved_nonproduction_identities=0
missing_nonproduction_identities=0
record_claim_sources() {
    local source_refs=$1
    local destination=$2
    local ref path
    local -a refs

    IFS=';' read -r -a refs <<< "${source_refs}"
    for ref in "${refs[@]}"; do
        [[ -z "${ref}" || "${ref}" == "-" ]] && continue
        if [[ "${ref}" == *::* ]]; then
            printf '%s\n' "${ref}" >> "${destination}"
        else
            path=${ref}
            printf '%s::*\n' "${path}" >> "${destination}"
        fi
    done
}

record_formal_feature_sources() {
    local family=$1
    local source_refs=$2
    local ref
    local -a refs

    IFS=';' read -r -a refs <<< "${source_refs}"
    for ref in "${refs[@]}"; do
        [[ -z "${ref}" || "${ref}" == "-" ]] && continue
        if [[ "${ref}" != *::* || "${ref}" == *'::*' ]]; then
            echo "feature:${family}: formal source_symbol must be an exact path::API reference rather than '${ref}'" >> "${errors_file}"
            continue
        fi
        printf '%s\t%s\n' "${family}" "${ref}" \
            >> "${formal_feature_sources_file}"
    done
}

record_feature_authority_sources() {
    local family=$1
    local source_refs=$2
    local destination=$3
    local ref
    local -a refs

    IFS=';' read -r -a refs <<< "${source_refs}"
    for ref in "${refs[@]}"; do
        [[ -z "${ref}" || "${ref}" == "-" ]] && continue
        [[ "${ref}" != *::* || "${ref}" == *'::*' ]] && continue
        printf '%s\t%s\n' "${family}" "${ref}" >> "${destination}"
    done
}

audit_claim() {
    local matrix_kind=$1
    local row_number=$2
    local row_key=$3
    local family=$4
    local claim_text=$5
    local claim_url=$6
    local source_refs=$7
    local tokens token matches eligible_matches inventory_matches details
    local url_matches url_normative_matches url_eligible_matches
    local url_inventory_matches url_match_count inventory_url_count
    local inventory_authority_id inventory_exact_spec inventory_version
    local inventory_matrix_match combined_claim
    local inventory_url_bound=0
    local url_authority_id token_url_join=0
    local claim_blocked=0

    ((maturity_claim_rows += 1))
    url_matches=$(awk -F '\t' -v wanted="${claim_url}" '$1 == wanted { print }' "${urls_file}")
    if [[ -z "${url_matches}" ]]; then
        echo "${matrix_kind}:${row_number}:${row_key}: official URL is absent from authority manifest: ${claim_url}" >> "${blockers_file}"
        claim_blocked=1
    else
        url_normative_matches=$(printf '%s\n' "${url_matches}" \
            | awk -F '\t' '$4 ~ /^(NORMATIVE_SPEC|STANDARD|AMENDMENT|TR|WG_DOC)$/ { print }')
        if [[ -n "${url_normative_matches}" ]]; then
            url_eligible_matches=$(printf '%s\n' "${url_normative_matches}" \
                | while IFS=$'\t' read -r url_id_url url_id url_sha url_kind url_qualification url_eligible; do
                    awk -F '\t' -v wanted="${url_id}" '$2 == wanted && $6 == 1 { print $2 }' "${matches_file}"
                done)
            if [[ -z "${url_eligible_matches}" ]]; then
                details=$(printf '%s\n' "${url_normative_matches}" \
                    | awk -F '\t' '{ print $2 "/" $4 }' | paste -sd, -)
                echo "${matrix_kind}:${row_number}:${row_key}: official artifact URL is not production-qualified (${details})" >> "${blockers_file}"
                claim_blocked=1
            fi
        fi

        # A Work Item is inventory provenance, never normative production
        # authority.  Permit its URL on a maturity row only when that URL
        # resolves to one unambiguous INVENTORY_ONLY record and the row binds
        # the registered WI identity explicitly.  A full matrix_match is the
        # preferred binding; where portal spelling differs, require both the
        # exact_spec name and version/UID.  Exact TS/version tokens below must
        # still resolve independently to PRODUCTION records.
        url_inventory_matches=$(printf '%s\n' "${url_matches}" \
            | awk -F '\t' '$4 == "WORK_ITEM" && $5 == "INVENTORY_ONLY" { print }')
        url_match_count=$(printf '%s\n' "${url_matches}" \
            | awk 'NF { count += 1 } END { print count + 0 }')
        inventory_url_count=$(printf '%s\n' "${url_inventory_matches}" \
            | awk 'NF { count += 1 } END { print count + 0 }')
        if (( inventory_url_count > 0 )); then
            if (( url_match_count != 1 || inventory_url_count != 1 )); then
                echo "${matrix_kind}:${row_number}:${row_key}: Work Item URL must resolve to exactly one WORK_ITEM/INVENTORY_ONLY authority record" >> "${blockers_file}"
                claim_blocked=1
            else
                inventory_authority_id=$(printf '%s\n' "${url_inventory_matches}" \
                    | awk -F '\t' 'NF { print $2; exit }')
                IFS=$'\t' read -r inventory_exact_spec inventory_version inventory_matrix_match \
                    < <(awk -F '\t' -v wanted="${inventory_authority_id}" \
                        '$1 == wanted { print $5 "\t" $6 "\t" $16; exit }' "${manifest}")
                combined_claim="${claim_text} ${row_key}"
                if contains_identity_literal "${combined_claim}" "${inventory_matrix_match}" \
                    || { contains_identity_literal "${combined_claim}" "${inventory_exact_spec}" \
                        && contains_identity_literal "${combined_claim}" "${inventory_version}"; }; then
                    inventory_url_bound=1
                else
                    echo "${matrix_kind}:${row_number}:${row_key}: Work Item URL authority '${inventory_authority_id}' is not explicitly bound by its registered matrix_match or exact_spec plus version/UID" >> "${blockers_file}"
                    claim_blocked=1
                fi
            fi
        fi
    fi

    tokens=$(extract_normative_tokens "${claim_text}")
    if [[ -z "${tokens}" ]]; then
        inventory_matches=$(awk -F '\t' -v text="${claim_text}" '
            index(text, $1) > 0 { print $2 "/" $4 "/" $5 }
        ' "${matches_file}" | paste -sd, -)
        if [[ -z "${inventory_matches}" ]]; then
            inventory_matches="none"
        fi
        echo "${matrix_kind}:${row_number}:${row_key}: no exact normative specification/version; matching inventory/reference=${inventory_matches}" >> "${blockers_file}"
        record_claim_sources "${source_refs}" "${blocked_sources_file}"
        ((authority_blocked_maturity_claims += 1))
        return 1
    fi

    while IFS= read -r token; do
        [[ -z "${token}" ]] && continue
        matches=$(awk -F '\t' -v wanted="${token}" '$1 == wanted { print }' "${matches_file}")
        if [[ -z "${matches}" ]]; then
            echo "${matrix_kind}:${row_number}:${row_key}: missing authority record for exact token '${token}'" >> "${blockers_file}"
            claim_blocked=1
            continue
        fi
        # A feature may normatively depend on a specification from another
        # family (for example, an NR feature using an LTE-numbered TS).  The
        # exact specification/version and eligible source kind are the trust
        # boundary; the manifest family is classification metadata only.
        eligible_matches=$(printf '%s\n' "${matches}" | awk -F '\t' '$6 == 1 { print $2 }')
        if [[ -z "${eligible_matches}" ]]; then
            details=$(printf '%s\n' "${matches}" | awk -F '\t' '{ print $2 "/" $4 "/" $5 }' | paste -sd, -)
            echo "${matrix_kind}:${row_number}:${row_key}: '${token}' has no qualified PRODUCTION authority (${details})" >> "${blockers_file}"
            claim_blocked=1
        else
            while IFS= read -r url_authority_id; do
                [[ -z "${url_authority_id}" ]] && continue
                if printf '%s\n' "${matches}" \
                    | awk -F '\t' -v wanted="${url_authority_id}" \
                        '$2 == wanted && $6 == 1 { found=1 } END { exit(found ? 0 : 1) }'; then
                    token_url_join=1
                    break
                fi
            done < <(printf '%s\n' "${url_matches}" | awk -F '\t' '{ print $2 }')
        fi
    done <<< "${tokens}"

    if (( inventory_url_bound )); then
        token_url_join=1
    fi

    if (( ! token_url_join )); then
        echo "${matrix_kind}:${row_number}:${row_key}: official URL does not identify the same qualified normative authority record as any exact specification/version token" >> "${blockers_file}"
        claim_blocked=1
    fi

    if (( claim_blocked )); then
        record_claim_sources "${source_refs}" "${blocked_sources_file}"
        ((authority_blocked_maturity_claims += 1))
    else
        record_claim_sources "${source_refs}" "${qualified_sources_file}"
        ((production_eligible_maturity_claims += 1))
    fi
    return "${claim_blocked}"
}

normalize_clause_scope() {
    printf '%s\n' "$1" \
        | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/^[Vv][0-9]+\.[0-9]+\.[0-9]+[[:space:]]+//; s/^[Cc]lauses?[[:space:]]+//; s/[[:space:]]+//g' \
        | tr '[:upper:]' '[:lower:]'
}

scope_includes() {
    local claimed_scope=$1
    local authority_scope=$2
    local claimed_annex authority_annex annex_low annex_high
    local table_claim table_authority
    local table_prefix table_index table_low table_high part

    case "${claimed_scope}" in
        *tbd*|*unresolved*|*placeholder*|*draft*|*.xx|*.yy|*.zz|xx|yy|zz|*.)
            return 1
            ;;
    esac
    [[ "${claimed_scope}" == *..* ]] && return 1

    [[ "${claimed_scope}" == "${authority_scope}" ]] && return 0

    # Annex scopes use letters rather than numeric clause components.  Expand
    # the common published "Annexes A and B" spelling explicitly and otherwise
    # apply the same exact-or-dot-descendant rule to a single annex identity.
    claimed_annex=${claimed_scope#annexes}
    claimed_annex=${claimed_annex#annex}
    authority_annex=${authority_scope#annexes}
    authority_annex=${authority_annex#annex}
    if [[ "${authority_scope}" == annexesaandb ]]; then
        [[ "${claimed_annex}" =~ ^[ab]([.][0-9]+[a-z]*)*$ ]] \
            && return 0
        if [[ "${claimed_annex}" == *-* ]]; then
            annex_low=${claimed_annex%%-*}
            annex_high=${claimed_annex#*-}
            if [[ "${annex_low}" =~ ^[ab]([.][0-9]+[a-z]*)+$ \
                && "${annex_high}" =~ ^[ab]([.][0-9]+[a-z]*)+$ \
                && "${annex_low%%.*}" == "${annex_high%%.*}" ]] \
                && awk -v low="${annex_low#*.}" -v high="${annex_high#*.}" '
                    function number(part, value) {
                        value = part
                        sub(/[a-z]+$/, "", value)
                        return value + 0
                    }
                    function suffix(part, value) {
                        value = part
                        sub(/^[0-9]+/, "", value)
                        return value
                    }
                    BEGIN {
                        low_count = split(low, low_parts, "\\.")
                        high_count = split(high, high_parts, "\\.")
                        if (low_count != high_count) exit 1
                        for (idx = 1; idx <= low_count; idx += 1) {
                            low_number = number(low_parts[idx])
                            high_number = number(high_parts[idx])
                            if (low_number < high_number) exit 0
                            if (low_number > high_number) exit 1
                            low_suffix = suffix(low_parts[idx])
                            high_suffix = suffix(high_parts[idx])
                            if (low_suffix < high_suffix) exit 0
                            if (low_suffix > high_suffix) exit 1
                        }
                        exit 0
                    }
                '; then
                return 0
            fi
        fi
    elif [[ "${authority_scope}" == annex* ]]; then
        [[ "${claimed_annex}" =~ ^[a-z]+([.][0-9]+[a-z]*)*$ ]] \
            && { [[ "${claimed_annex}" == "${authority_annex}" \
                || "${claimed_annex}" == "${authority_annex}."* ]]; } \
            && return 0
        if [[ "${claimed_annex}" == *-* ]]; then
            annex_low=${claimed_annex%%-*}
            annex_high=${claimed_annex#*-}
            if [[ "${annex_low}" =~ ^[a-z]+([.][0-9]+[a-z]*)+$ \
                && "${annex_high}" =~ ^[a-z]+([.][0-9]+[a-z]*)+$ \
                && "${annex_low%%.*}" == "${authority_annex}" \
                && "${annex_high%%.*}" == "${authority_annex}" ]] \
                && awk -v low="${annex_low#*.}" -v high="${annex_high#*.}" '
                    function number(part, value) {
                        value = part
                        sub(/[a-z]+$/, "", value)
                        return value + 0
                    }
                    function suffix(part, value) {
                        value = part
                        sub(/^[0-9]+/, "", value)
                        return value
                    }
                    BEGIN {
                        low_count = split(low, low_parts, "\\.")
                        high_count = split(high, high_parts, "\\.")
                        if (low_count != high_count) exit 1
                        for (idx = 1; idx <= low_count; idx += 1) {
                            low_number = number(low_parts[idx])
                            high_number = number(high_parts[idx])
                            if (low_number < high_number) exit 0
                            if (low_number > high_number) exit 1
                            low_suffix = suffix(low_parts[idx])
                            high_suffix = suffix(high_parts[idx])
                            if (low_suffix < high_suffix) exit 0
                            if (low_suffix > high_suffix) exit 1
                        }
                        exit 0
                    }
                '; then
                return 0
            fi
        fi
    fi

    # Table numbers contain '-' as part of their identity, so do not feed them
    # to the numeric clause-range comparator.  Support only an explicit exact
    # table or the published shorthand "Tables X-1 to -3".  Multiple table
    # ranges joined by "and" are checked independently; no lexical range guess
    # is made across different table prefixes.
    if [[ "${claimed_scope}" == table* || "${claimed_scope}" == tables* \
        || "${authority_scope}" == table* || "${authority_scope}" == tables* ]]; then
        table_claim=${claimed_scope#tables}
        table_claim=${table_claim#table}
        authority_scope=${authority_scope#tables}
        authority_scope=${authority_scope#table}
        while IFS= read -r part; do
            [[ -z "${part}" ]] && continue
            table_authority=${part#tables}
            table_authority=${table_authority#table}
            [[ "${table_claim}" == "${table_authority}" ]] && return 0
            if [[ "${table_claim}" =~ ^(.+)-([0-9]+)$ \
                && "${table_authority}" =~ ^(.+)-([0-9]+)to-([0-9]+)$ ]]; then
                table_prefix=${BASH_REMATCH[1]}
                table_low=${BASH_REMATCH[2]}
                table_high=${BASH_REMATCH[3]}
                if [[ "${table_claim}" =~ ^(.+)-([0-9]+)$ ]]; then
                    table_index=${BASH_REMATCH[2]}
                    [[ "${BASH_REMATCH[1]}" == "${table_prefix}" ]] \
                        && (( table_index >= table_low && table_index <= table_high )) \
                        && return 0
                fi
            fi
            if [[ "${table_authority}" =~ ^(.+)-([0-9]+)to-([0-9]+)$ ]]; then
                table_prefix=${BASH_REMATCH[1]}
                table_low=${BASH_REMATCH[2]}
                table_high=${BASH_REMATCH[3]}
                if [[ "${table_claim}" =~ ^(.+)-([0-9]+)to-([0-9]+)$ ]]; then
                    [[ "${BASH_REMATCH[1]}" == "${table_prefix}" \
                        && ${BASH_REMATCH[2]} -ge ${table_low} \
                        && ${BASH_REMATCH[3]} -le ${table_high} \
                        && ${BASH_REMATCH[2]} -le ${BASH_REMATCH[3]} ]] \
                        && return 0
                fi
            fi
        done < <(printf '%s\n' "${authority_scope}" | sed 's/and/\n/g')
        return 1
    fi

    # A published numeric/alphanumeric parent clause covers its dot-delimited
    # descendants.  Validate both identities before applying the prefix rule:
    # this admits 6.2 -> 6.2.1B but rejects 5.1.TBD, trailing dots and prose
    # placeholders.  The dot boundary also prevents 6.2 from covering 6.20.
    if [[ "${claimed_scope}" =~ ^[0-9]+[a-z]*([.][0-9]+[a-z]*)*(-[0-9]+[a-z]*([.][0-9]+[a-z]*)*)?$ \
        && "${authority_scope}" =~ ^[0-9]+[a-z]*([.][0-9]+[a-z]*)*(-[0-9]+[a-z]*([.][0-9]+[a-z]*)*)?$ \
        && "${claimed_scope}" == "${authority_scope}."* ]]; then
        return 0
    fi

    awk -v claimed="${claimed_scope}" -v authority="${authority_scope}" '
        function endpoint_compare(left, right, left_parts, right_parts, left_count, right_count, idx) {
            left_count = split(left, left_parts, "\\.")
            right_count = split(right, right_parts, "\\.")
            if (left_count != right_count) return 2
            for (idx = 1; idx <= left_count; idx += 1) {
                if ((left_parts[idx] + 0) < (right_parts[idx] + 0)) return -1
                if ((left_parts[idx] + 0) > (right_parts[idx] + 0)) return 1
            }
            return 0
        }
        BEGIN {
            numeric = "[0-9]+(\\.[0-9]+)*"
            if (claimed !~ ("^" numeric "(-" numeric ")?$") \
                || authority !~ ("^" numeric "(-" numeric ")?$") ) exit 1

            claimed_count = split(claimed, claimed_range, "-")
            authority_count = split(authority, authority_range, "-")
            claimed_low = claimed_range[1]
            claimed_high = claimed_count == 2 ? claimed_range[2] : claimed_range[1]
            authority_low = authority_range[1]
            authority_high = authority_count == 2 ? authority_range[2] : authority_range[1]

            # A single authority parent was handled by the dot-prefix rule
            # above.  For a numeric authority range, compare a deeper claimed
            # endpoint at the authority range depth (for example, 6.3.1 is
            # inside 6.2-6.4).  Both authority endpoints must have equal depth.
            authority_depth_low = split(authority_low, authority_low_parts, "\\.")
            authority_depth_high = split(authority_high, authority_high_parts, "\\.")
            if (authority_depth_low != authority_depth_high) exit 1
            claimed_depth_low = split(claimed_low, claimed_low_parts, "\\.")
            claimed_depth_high = split(claimed_high, claimed_high_parts, "\\.")
            if (claimed_depth_low < authority_depth_low \
                || claimed_depth_high < authority_depth_low) exit 1
            projected_low = claimed_low_parts[1]
            projected_high = claimed_high_parts[1]
            for (idx = 2; idx <= authority_depth_low; idx += 1) {
                projected_low = projected_low "." claimed_low_parts[idx]
                projected_high = projected_high "." claimed_high_parts[idx]
            }

            claimed_order = endpoint_compare(projected_low, projected_high)
            authority_order = endpoint_compare(authority_low, authority_high)
            low_cmp = endpoint_compare(authority_low, projected_low)
            high_cmp = endpoint_compare(projected_high, authority_high)
            if (claimed_order == 2 || authority_order == 2 \
                || claimed_order > 0 || authority_order > 0 \
                || low_cmp == 2 || high_cmp == 2) exit 1
            exit(low_cmp <= 0 && high_cmp <= 0 ? 0 : 1)
        }
    '
}

audit_maturity_clause_scope() {
    local row_number=$1
    local row_key=$2
    local maturity_status=$3
    local specification=$4
    local claim_clauses=$5
    local tokens token token_count short_spec candidate candidate_scope
    local detected_spec detected_version active_spec active_version subcandidate
    local token_version other_token other_short_spec short_spec_count
    local eligible_ids authority_id manifest_scopes manifest_scope normalized_candidate
    local found_candidate found_token scope_blocked=0

    tokens=$(extract_normative_tokens "${specification} ${claim_clauses}")
    token_count=$(printf '%s\n' "${tokens}" | awk 'NF { count += 1 } END { print count + 0 }')
    if (( token_count == 0 )) || [[ -z "${claim_clauses}" \
        || "${claim_clauses}" == "-" \
        || "${claim_clauses^^}" == "ALL" ]]; then
        echo "feature:${row_number}:${row_key}: ${maturity_status} claim requires exact clause/table scope rather than '${claim_clauses}'" >> "${blockers_file}"
        return 1
    fi

    while IFS= read -r token; do
        [[ -z "${token}" ]] && continue
        short_spec=${token% V*}
        short_spec=${short_spec#3GPP }
        if [[ "${short_spec}" =~ ([0-9]{2}\.[0-9]{3}(-[0-9])?) ]]; then
            short_spec=${BASH_REMATCH[1]}
        fi
        token_version=${token##* V}
        short_spec_count=0
        while IFS= read -r other_token; do
            [[ -z "${other_token}" ]] && continue
            other_short_spec=${other_token% V*}
            other_short_spec=${other_short_spec#3GPP }
            if [[ "${other_short_spec}" =~ ([0-9]{2}\.[0-9]{3}(-[0-9])?) ]]; then
                other_short_spec=${BASH_REMATCH[1]}
            fi
            [[ "${other_short_spec}" == "${short_spec}" ]] \
                && ((short_spec_count += 1))
        done <<< "${tokens}"
        eligible_ids=$(awk -F '\t' -v wanted="${token}" \
            '$1 == wanted && $6 == 1 { print $2 }' "${matches_file}")
        found_token=0
        active_spec=""
        active_version=""

        while IFS= read -r candidate; do
            candidate=$(printf '%s\n' "${candidate}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
            [[ -z "${candidate}" ]] && continue
            detected_spec=$(printf '%s\n' "${candidate}" \
                | rg -o '[0-9]{2}\.[0-9]{3}(-[0-9])?' | head -n 1 || true)
            detected_version=$(printf '%s\n' "${candidate}" \
                | rg -o '[Vv][0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
            if [[ -n "${detected_spec}" ]]; then
                active_spec=${detected_spec}
                active_version=${detected_version#[Vv]}
            elif [[ -n "${detected_version}" ]]; then
                active_version=${detected_version#[Vv]}
            fi
            if [[ "${candidate}" == RP-* || "${candidate}" == *" objective"* \
                || "${candidate}" == *" objectives "* ]]; then
                continue
            fi
            if (( token_count > 1 )); then
                if [[ "${active_spec}" != "${short_spec}" ]]; then
                    continue
                fi
                # Two exact versions of the same specification in one row
                # are separate trust dependencies.  A short-spec prefix alone
                # must not let one version's scope qualify the other.
                if (( short_spec_count > 1 )) \
                    && [[ "${active_version}" != "${token_version}" ]]; then
                    continue
                fi
            fi
            candidate_scope=${candidate#*"${short_spec}"}
            while IFS= read -r subcandidate; do
                subcandidate=$(printf '%s\n' "${subcandidate}" \
                    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
                normalized_candidate=$(normalize_clause_scope "${subcandidate}")
                [[ -z "${normalized_candidate}" ]] && continue
                found_candidate=0

                while IFS= read -r authority_id; do
                    [[ -z "${authority_id}" ]] && continue
                    manifest_scopes=$(awk -F '\t' -v wanted="${authority_id}" \
                        '$1 == wanted { print $11 }' "${manifest}")
                    while IFS= read -r manifest_scope; do
                        if scope_includes "${normalized_candidate}" \
                            "$(normalize_clause_scope "${manifest_scope}")"; then
                            found_candidate=1
                            found_token=1
                            break
                        fi
                    done < <(printf '%s\n' "${manifest_scopes}" | tr ';' '\n')
                    (( found_candidate )) && break
                done <<< "${eligible_ids}"

                if (( ! found_candidate )); then
                    echo "feature:${row_number}:${row_key}: ${maturity_status} clause/table '${subcandidate}' is not included by the same exact specification/version PRODUCTION authority scope for '${token}'" >> "${blockers_file}"
                    scope_blocked=1
                fi
            done < <(printf '%s\n' "${candidate_scope}" \
                | sed -E 's/[[:space:]]+and[[:space:]]+/\n/g; s/,/\n/g')
        done < <(printf '%s\n' "${claim_clauses}" | tr ';' '\n')

        if (( ! found_token )); then
            echo "feature:${row_number}:${row_key}: ${maturity_status} claim has no exact clause/table joined to '${token}'" >> "${blockers_file}"
            scope_blocked=1
        fi
    done <<< "${tokens}"
    return "${scope_blocked}"
}

# MISSING and exact EXCLUDED rows do not make implementation-maturity claims,
# but they still need a stable, auditable identity.  A blocked, excluded or
# tracking authority is sufficient here: the purpose is to prove that the row
# names an exact ratified/frozen artifact (or an explicit access/metadata
# blocker), not to grant production authority.
audit_gap_identity() {
    local matrix_kind=$1
    local row_number=$2
    local row_key=$3
    local claim_family=$4
    local claim_text=$5
    local claim_url=$6
    local row_status=$7
    local tokens token matches identity_matches url_matches qualified_url_matches
    local final_url_matches inventory_url_matches inventory_claim_matches
    local joined_identity_matches identity_id inventory_id inventory_match
    local identity_missing=0

    ((nonproduction_identity_rows += 1))
    url_matches=$(awk -F '\t' -v wanted="${claim_url}" '$1 == wanted { print }' "${urls_file}")
    if [[ -z "${url_matches}" ]]; then
        echo "${matrix_kind}:${row_number}:${row_key}: ${row_status}-row official URL is absent from authority manifest: ${claim_url}" >> "${blockers_file}"
        identity_missing=1
    fi
    final_url_matches=$(printf '%s\n' "${url_matches}" \
        | awk -F '\t' '$4 ~ /^(NORMATIVE_SPEC|STANDARD|AMENDMENT)$/ { print }')
    inventory_url_matches=$(printf '%s\n' "${url_matches}" \
        | awk -F '\t' '$4 ~ /^(WORK_ITEM|PAR)$/ && $5 ~ /^(INVENTORY_ONLY|TRACKING)$/ { print }')
    if [[ -n "${url_matches}" && -z "${final_url_matches}" \
        && -z "${inventory_url_matches}" ]]; then
        echo "${matrix_kind}:${row_number}:${row_key}: ${row_status}-row URL is neither a final normative record nor an eligible inventory record" >> "${blockers_file}"
        identity_missing=1
    fi
    if [[ -n "${inventory_url_matches}" && -z "${final_url_matches}" ]]; then
        inventory_claim_matches=""
        while IFS=$'\t' read -r inventory_url inventory_id inventory_sha inventory_kind inventory_qualification inventory_eligible; do
            [[ -z "${inventory_id}" ]] && continue
            inventory_match=$(awk -F '\t' -v wanted="${inventory_id}" '$2 == wanted { print $1 }' "${matches_file}")
            if [[ -n "${inventory_match}" && "${claim_text}" == *"${inventory_match}"* ]]; then
                inventory_claim_matches+="${inventory_id}"$'\n'
            fi
        done <<< "${inventory_url_matches}"
        if [[ -z "${inventory_claim_matches}" ]]; then
            echo "${matrix_kind}:${row_number}:${row_key}: inventory URL record is not explicitly identified by the row" >> "${blockers_file}"
            identity_missing=1
        fi
    fi
    if [[ "${row_status}" == "EXCLUDED" ]]; then
        qualified_url_matches=$(printf '%s\n' "${url_matches}" \
            | awk -F '\t' '$3 ~ /^[0-9a-f]{64}$/ && $4 ~ /^(NORMATIVE_SPEC|STANDARD|AMENDMENT)$/ && $5 == "EXCLUDED" { print }')
        if [[ -z "${qualified_url_matches}" ]]; then
            echo "${matrix_kind}:${row_number}:${row_key}: EXCLUDED-row URL lacks a hashed final EXCLUDED authority" >> "${blockers_file}"
            identity_missing=1
        fi
    fi

    tokens=$(extract_normative_tokens "${claim_text}")
    if [[ -z "${tokens}" ]]; then
        echo "${matrix_kind}:${row_number}:${row_key}: ${row_status} row has no exact normative specification/version identity" >> "${blockers_file}"
        identity_missing=1
    else
        while IFS= read -r token; do
            [[ -z "${token}" ]] && continue
            matches=$(awk -F '\t' -v wanted="${token}" '$1 == wanted { print }' "${matches_file}")
            if [[ -z "${matches}" ]]; then
                echo "${matrix_kind}:${row_number}:${row_key}: ${row_status} identity has no authority record for '${token}'" >> "${blockers_file}"
                identity_missing=1
                continue
            fi
            if [[ "${row_status}" == "EXCLUDED" ]]; then
                identity_matches=$(printf '%s\n' "${matches}" \
                    | awk -F '\t' '$4 ~ /^(NORMATIVE_SPEC|STANDARD|AMENDMENT)$/ && $5 == "EXCLUDED" { print }')
            else
                identity_matches=$(printf '%s\n' "${matches}" \
                    | awk -F '\t' '$4 ~ /^(NORMATIVE_SPEC|STANDARD|AMENDMENT)$/ && $5 ~ /^(PRODUCTION|BLOCKED_LICENSE|BLOCKED_ACCESS|BLOCKED_METADATA|BLOCKED_DOWNLOAD)$/ { print }')
            fi
            case "${claim_family}:${row_status}" in
                bluetooth:MISSING|matter:MISSING|zigbee:MISSING)
                    identity_matches=$(printf '%s\n' "${identity_matches}" \
                        | awk -F '\t' -v wanted="${claim_family}" \
                            '$3 == wanted && $5 == "PRODUCTION" { print }')
                    ;;
                ieee802154:MISSING|thread:MISSING)
                    identity_matches=$(printf '%s\n' "${identity_matches}" \
                        | awk -F '\t' -v wanted="${claim_family}" \
                            '$3 == wanted && $5 == "BLOCKED_METADATA" { print }')
                    ;;
            esac
            if [[ -z "${identity_matches}" ]]; then
                echo "${matrix_kind}:${row_number}:${row_key}: ${row_status} identity '${token}' lacks an allowed final normative authority" >> "${blockers_file}"
                identity_missing=1
            elif [[ -n "${final_url_matches}" ]]; then
                joined_identity_matches=""
                while IFS=$'\t' read -r identity_match identity_id identity_family identity_kind identity_qualification identity_eligible; do
                    [[ -z "${identity_id}" ]] && continue
                    if printf '%s\n' "${final_url_matches}" \
                        | awk -F '\t' -v wanted="${identity_id}" '$2 == wanted { found=1 } END { exit(found ? 0 : 1) }'; then
                        joined_identity_matches+="${identity_id}"$'\n'
                    fi
                done <<< "${identity_matches}"
                if [[ -z "${joined_identity_matches}" ]]; then
                    echo "${matrix_kind}:${row_number}:${row_key}: ${row_status} identity '${token}' and official URL do not resolve to the same authority record" >> "${blockers_file}"
                    identity_missing=1
                fi
            fi
        done <<< "${tokens}"
    fi

    if (( identity_missing )); then
        ((missing_nonproduction_identities += 1))
    else
        ((resolved_nonproduction_identities += 1))
    fi
}

spec_header=$'family\tspecification\tbaseline\tstatus\tofficial_source\talgorithm_scope\tsource_evidence\ttest_evidence\tboundary'
IFS= read -r actual_spec_header < "${spec_matrix}"
if [[ "${actual_spec_header}" != "${spec_header}" ]]; then
    echo "specification matrix header changed before authority audit" >> "${errors_file}"
else
    spec_line=1
    while IFS=$'\t' read -r family specification baseline status official_source algorithm_scope source_evidence test_evidence boundary; do
        ((spec_line += 1))
        case "${status}" in
            BOUNDED|PARTIAL|COMPLETE)
                audit_claim specification "${spec_line}" \
                    "${family}|${specification}" "${family}" \
                    "${specification} ${baseline}" "${official_source}" \
                    "${source_evidence}"
                ;;
            MISSING)
                audit_gap_identity specification "${spec_line}" \
                    "${family}|${specification}" "${family}" \
                    "${specification} ${baseline}" "${official_source}" \
                    "${status}"
                ;;
        esac
    done < <(tail -n +2 "${spec_matrix}")
fi

feature_header=$'family\trelease_or_revision\tspecification\tclause_or_table\twork_item_or_feature\talgorithm\tmandatory_or_optional\tdeclared_profile\tstatus\tsource_symbol\tdeterministic_test\tedge_test\tproperty_test\tdifferential_test\toracle_kind\ttolerance_test\ttolerance_mode\tbenchmark\tofficial_url\tboundary\tnotes'
IFS= read -r actual_feature_header < "${feature_matrix}"
if [[ "${actual_feature_header}" != "${feature_header}" ]]; then
    echo "feature matrix header changed before authority audit" >> "${errors_file}"
else
    feature_line=1
    while IFS=$'\t' read -r family release specification clause feature algorithm mandatory profile status source deterministic edge property differential oracle tolerance tolerance_mode benchmark official_url boundary notes; do
        ((feature_line += 1))
        case "${status}" in
            BOUNDED|PARTIAL|COMPLETE)
                record_formal_feature_sources "${family}" "${source}"
                claim_authority_status=0
                audit_claim feature "${feature_line}" \
                    "${family}|${release}|${feature}" "${family}" \
                    "${specification} ${clause} ${release}" "${official_url}" \
                    "${source}" || claim_authority_status=$?
                clause_scope_status=0
                audit_maturity_clause_scope "${feature_line}" \
                    "${family}|${release}|${feature}" "${status}" \
                    "${specification}" "${clause}" \
                    || clause_scope_status=$?
                if (( clause_scope_status != 0 && claim_authority_status == 0 )); then
                    record_claim_sources "${source}" "${blocked_sources_file}"
                    ((production_eligible_maturity_claims -= 1))
                    ((authority_blocked_maturity_claims += 1))
                fi
                if (( clause_scope_status != 0 )); then
                    claim_authority_status=1
                fi
                if (( claim_authority_status == 0 )); then
                    record_feature_authority_sources "${family}" "${source}" \
                        "${qualified_feature_sources_file}"
                else
                    record_feature_authority_sources "${family}" "${source}" \
                        "${blocked_feature_sources_file}"
                fi
                ;;
            MISSING|EXCLUDED)
                audit_gap_identity feature "${feature_line}" \
                    "${family}|${release}|${feature}" "${family}" \
                    "${specification} ${clause} ${release} ${feature}" "${official_url}" \
                    "${status}"
                ;;
        esac
    done < <(tail -n +2 "${feature_matrix}")
fi

kernel_header=$'component\tkind\tapi\tsource\tdeterministic\tedge\tproperty\tdifferential\toracle_kind\ttolerance\ttolerance_mode\tbenchmark\tnotes'
IFS= read -r actual_kernel_header < "${kernel_matrix}"
protocol_kernels=0
qualified_kernels=0
blocked_kernels=0
uncovered_kernels=0
reference_kernels=0
blocked_kernel_components_file="${audit_tmp}/blocked-kernel-components"
: > "${blocked_kernel_components_file}"
if [[ "${actual_kernel_header}" != "${kernel_header}" ]]; then
    echo "kernel matrix header changed before authority audit" >> "${errors_file}"
else
    kernel_line=1
    while IFS=$'\t' read -r component kind api source deterministic edge property differential oracle_kind tolerance tolerance_mode benchmark notes; do
        ((kernel_line += 1))

        # These public helpers deliberately model a synthetic/reference
        # channel rather than a protocol-defined wire algorithm.  Keep them in
        # the executable kernel ledger, but never force them into (or let them
        # qualify through) a formal protocol Feature solely because their
        # source module lives under a Wi-Fi or NR package.
        case "${source}" in
            wireless_dsp/wireless/wifi/acquisition_chain.mojo::wifi_acquisition_apply_channel_20mhz|\
            wireless_dsp/wireless/nr/pucch_chain.mojo::nr_pucch_format2_flat_channel)
                ((reference_kernels += 1))
                continue
                ;;
        esac

        protocol_family=""
        case "${component}" in
            wireless_bluetooth) protocol_family=bluetooth ;;
            wireless_matter) protocol_family=matter ;;
            wireless_zigbee) protocol_family=zigbee ;;
            wireless_lte) protocol_family=lte ;;
            wireless_nr) protocol_family=nr ;;
            wifi|wireless_wifi) protocol_family=wifi ;;
            *)
                case "${api}:${source}" in
                    fixed_wifi_*:*) protocol_family=wifi ;;
                    fixed_nr_*:*|nr_*:*) protocol_family=nr ;;
                    lte_profile:*) protocol_family=lte ;;
                    simulate_wifi_*:wireless_dsp/testing/*|\
                    simulate_nr_*:wireless_dsp/testing/*|\
                    *:wireless_dsp/channel/cdl.mojo::*|\
                    *:wireless_dsp/channel/standard_profiles.mojo::*)
                        ((reference_kernels += 1))
                        continue
                        ;;
                    *) continue ;;
                esac
                ;;
        esac
        ((protocol_kernels += 1))
        if [[ "${source}" != *::* ]]; then
            echo "kernel:${kernel_line}:${protocol_family}|${api}: protocol kernel source must be path::API" >> "${errors_file}"
            continue
        fi
        if ! awk -F '\t' -v wanted_family="${protocol_family}" \
            -v wanted_source="${source}" \
            '$1 == wanted_family && $2 == wanted_source { found=1 } END { exit(found ? 0 : 1) }' \
            "${formal_feature_sources_file}"; then
            ((uncovered_kernels += 1))
            echo "kernel:${kernel_line}:${protocol_family}|${api}: protocol source/API is absent from every formal COMPLETE/PARTIAL Feature source_symbol (${source})" >> "${blockers_file}"
            continue
        fi
        # Formal dependencies are conjunctive, never alternatives: if an API
        # is claimed by both an authority-qualified row and a row whose exact
        # specification/version/clause dependency is blocked, the blocked
        # dependency wins.  This prevents a single-spec primitive row from
        # laundering a multi-spec facade whose other normative dependency is
        # unavailable.  A future finer-grained dependency group may remove a
        # false-negative, but the production gate must remain fail-closed.
        if awk -F '\t' -v wanted_family="${protocol_family}" \
            -v wanted_source="${source}" \
            '$1 == wanted_family && $2 == wanted_source { found=1 } END { exit(found ? 0 : 1) }' \
            "${blocked_feature_sources_file}"; then
            ((blocked_kernels += 1))
            printf '%s\n' "${protocol_family}" >> "${blocked_kernel_components_file}"
        elif awk -F '\t' -v wanted_family="${protocol_family}" \
            -v wanted_source="${source}" \
            '$1 == wanted_family && $2 == wanted_source { found=1 } END { exit(found ? 0 : 1) }' \
            "${qualified_feature_sources_file}"; then
            ((qualified_kernels += 1))
        else
            ((uncovered_kernels += 1))
            echo "kernel:${kernel_line}:${protocol_family}|${api}: protocol source/API has no authority-qualified or authority-blocked formal Feature claim (${source})" >> "${blockers_file}"
        fi
    done < <(tail -n +2 "${kernel_matrix}")
fi

if [[ -s "${blocked_kernel_components_file}" ]]; then
    while read -r component_count component_name; do
        echo "kernel:${component_name}: ${component_count} protocol source/API rows are covered only by authority-blocked implementation-maturity claims" >> "${blockers_file}"
    done < <(sort "${blocked_kernel_components_file}" | uniq -c)
fi

if [[ -s "${errors_file}" ]]; then
    echo "AUTHORITY CROSS-MATRIX STRUCTURAL ERRORS" >&2
    sort -u "${errors_file}" >&2
    exit 2
fi

if (( verify_downloads )); then
    report_download_issue() {
        local eligible_download=$1
        local issue=$2
        if (( eligible_download )); then
            echo "${issue}" >> "${downloads_file}"
        else
            echo "${issue}; non-production reference/tracking refresh did not gate production" >> "${warnings_file}"
        fi
    }
    while IFS=$'\t' read -r official_url authority_id expected_sha source_kind qualification eligible; do
        [[ "${expected_sha}" == "-" ]] && continue
        cached_artifact=""
        if [[ -n "${artifact_cache_dir}" ]]; then
            for candidate in "${artifact_cache_dir}"/*; do
                [[ -f "${candidate}" ]] || continue
                candidate_sha=$(sha256sum "${candidate}" | awk '{print $1}')
                if [[ "${candidate_sha}" == "${expected_sha}" ]]; then
                    cached_artifact=${candidate}
                    break
                fi
            done
        fi
        if [[ -n "${cached_artifact}" ]]; then
            magic=$(od -An -tx1 -N8 "${cached_artifact}" | tr -d ' \n')
            case "${official_url}" in
                *.htm|*.html) ;;
                *)
                    case "${magic}" in
                        25504446*|504b*|d0cf11e0a1b11ae1*) ;;
                        *) report_download_issue "${eligible}" \
                            "${authority_id}: cached artifact magic is not PDF/ZIP/DOC" ;;
                    esac
                    ;;
            esac
            continue
        fi
        case "${official_url}" in
            *.zip|*.pdf|*.doc|*.docx|*.xls|*.xlsx|*.htm|*.html)
                artifact="${audit_tmp}/${authority_id}.artifact"
                if ! curl -L --fail --silent --show-error --retry 2 \
                    --connect-timeout 15 --max-time 180 -A 'Mozilla/5.0' \
                    -o "${artifact}" "${official_url}" \
                    || [[ ! -s "${artifact}" ]]; then
                    report_download_issue "${eligible}" \
                        "${authority_id}: failed to download a non-empty artifact from ${official_url}"
                    continue
                fi
                actual_sha=$(sha256sum "${artifact}" | awk '{print $1}')
                if [[ "${actual_sha}" != "${expected_sha}" ]]; then
                    report_download_issue "${eligible}" \
                        "${authority_id}: SHA-256 mismatch expected=${expected_sha} actual=${actual_sha}"
                    continue
                fi
                magic=$(od -An -tx1 -N8 "${artifact}" | tr -d ' \n')
                case "${official_url}" in
                    *.pdf) [[ "${magic}" == 25504446* ]] || report_download_issue "${eligible}" "${authority_id}: PDF magic mismatch" ;;
                    *.zip|*.docx|*.xlsx) [[ "${magic}" == 504b* ]] || report_download_issue "${eligible}" "${authority_id}: ZIP magic mismatch" ;;
                    *.doc|*.xls) [[ "${magic}" == d0cf11e0a1b11ae1* || "${magic}" == 504b* ]] || report_download_issue "${eligible}" "${authority_id}: OLE/ZIP document magic mismatch" ;;
                    *.htm|*.html) : ;;
                esac
                ;;
            *)
                report_download_issue "${eligible}" \
                    "${authority_id}: landing URL is not a direct artifact and no matching cached artifact was supplied"
                ;;
        esac
    done < "${urls_file}"
fi

printf 'SUMMARY authority_rows=%d PRODUCTION=%d blocked_authorities=%d maturity_claims=%d production_eligible_maturity_claims=%d authority_blocked_maturity_claims=%d nonproduction_identities=%d resolved_nonproduction_identities=%d missing_nonproduction_identities=%d source_reference_mappings=%d protocol_kernels=%d qualified_kernels=%d blocked_kernels=%d uncovered_kernels=%d reference_kernels=%d\n' \
    "${authority_rows}" "${production_authorities}" "${blocked_authorities}" \
    "${maturity_claim_rows}" "${production_eligible_maturity_claims}" \
    "${authority_blocked_maturity_claims}" "${nonproduction_identity_rows}" \
    "${resolved_nonproduction_identities}" "${missing_nonproduction_identities}" \
    "${reference_map_rows}" \
    "${protocol_kernels}" "${qualified_kernels}" "${blocked_kernels}" \
    "${uncovered_kernels}" "${reference_kernels}"

if [[ -s "${warnings_file}" ]]; then
    echo "WARNINGS"
    sort -u "${warnings_file}"
fi
if [[ -s "${downloads_file}" ]]; then
    echo "AUTHORITY DOWNLOAD BLOCKERS" >&2
    sort -u "${downloads_file}" >&2
fi
if [[ -s "${blockers_file}" ]]; then
    echo "RATIFIED-ONLY QUALIFICATION BLOCKERS" >&2
    sort -u "${blockers_file}" >&2
fi

if [[ -s "${downloads_file}" || -s "${blockers_file}" ]]; then
    exit 1
fi

echo "AUTHORITY AUDIT OK: every implementation-maturity claim is production-authorized by a ratified-only authority"
