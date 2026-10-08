#!/usr/bin/env bash

set -u
set -o pipefail

usage() {
    cat <<'EOF'
Usage: scripts/audit_kernel_coverage.sh [--strict]
       [--exclude-component COMPONENT]...

Audit testing/kernel_coverage.tsv against the enabled public DSP, channel,
backend, testing/link-simulation, LTE, NR, and Wi-Fi APIs and the referenced test
and benchmark entry points.  The default mode reports honest
coverage gaps without failing.  --strict exits 1 when any row is PARTIAL or
MISSING, making it suitable as a release gate once the ledger is complete.
--exclude-component removes an explicitly out-of-scope component completely
from status, counts, evidence, duplicate-name, and public-export validation.

Structural errors (bad/missing references, duplicate or omitted public APIs,
invalid independent-oracle claims, or benchmark bundles that reuse one timed
workload for multiple public APIs) always exit 2.

Ledger references use relative/path.mojo::top_level_function; '-' means that
the category is honestly uncovered.  Every public kernel, table_config, and
artifact row requires deterministic, edge, property, independent differential,
tolerance, and attributable benchmark evidence.  Non-executable constants do
not belong in this public API ledger and cannot be printed COMPLETE by using a
weaker kind.  Only analytic, external_static, float64_reference,
cross_implementation, and exhaustive_integer are accepted as independent
oracle kinds; round trips are property evidence, not differential evidence.
EOF
}

strict=0
excluded_components=()
while (( $# > 0 )); do
    case "$1" in
        --strict)
            strict=1
            shift
            ;;
        --exclude-component)
            if (( $# < 2 )) || [[ ! "$2" =~ ^[A-Za-z0-9_]+$ ]]; then
                usage >&2
                exit 2
            fi
            excluded_components+=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

component_is_excluded() {
    local wanted=$1
    local excluded
    for excluded in "${excluded_components[@]}"; do
        [[ "${wanted}" == "${excluded}" ]] && return 0
    done
    return 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "${script_dir}/.." && pwd)
ledger="${project_dir}/testing/kernel_coverage.tsv"

if [[ ! -f "${ledger}" ]]; then
    echo "ERROR missing ledger: testing/kernel_coverage.tsv" >&2
    exit 2
fi

expected_header=$'component\tkind\tapi\tsource\tdeterministic\tedge\tproperty\tdifferential\toracle_kind\ttolerance\ttolerance_mode\tbenchmark\tnotes'
IFS= read -r actual_header < "${ledger}"
if [[ "${actual_header}" != "${expected_header}" ]]; then
    echo "ERROR ledger header does not match the documented schema" >&2
    exit 2
fi

bad_width=$(awk -F '\t' 'NF != 13 { print NR ":" NF }' "${ledger}")
if [[ -n "${bad_width}" ]]; then
    echo "ERROR ledger rows must have exactly 13 tab-separated columns:" >&2
    echo "${bad_width}" >&2
    exit 2
fi

audit_tmp=$(mktemp -d)
trap 'rm -rf -- "${audit_tmp}"' EXIT
errors_file="${audit_tmp}/errors"
gaps_file="${audit_tmp}/gaps"
seen_file="${audit_tmp}/seen"
excluded_apis_file="${audit_tmp}/excluded-apis"
benchmark_workloads_file="${audit_tmp}/benchmark-workloads"
timing_contract_files="${audit_tmp}/timing-contract-files"
sanitized_source_dir="${audit_tmp}/sanitized-source"
: > "${errors_file}"
: > "${gaps_file}"
: > "${seen_file}"
: > "${excluded_apis_file}"
: > "${benchmark_workloads_file}"
: > "${timing_contract_files}"
mkdir -p -- "${sanitized_source_dir}"

# Strip comments and string/docstring contents before doing call-graph or
# benchmark-attribution analysis.  A coverage reference is evidence only when
# its function body contains an executable call expression; an API name in a
# comment, diagnostic string, or docstring must never satisfy reachability.
# Keep line boundaries and non-string source text intact so the downstream
# top-level function scanners retain their simple, deterministic behaviour.
sanitized_source_file() {
    local file=$1
    local relative cache
    relative=${file#"${project_dir}/"}
    relative=${relative//\//__}
    relative=${relative//:/_}
    cache="${sanitized_source_dir}/${relative}"
    if [[ ! -f "${cache}" ]]; then
        awk '
            BEGIN {
                double_quote = sprintf("%c", 34)
                single_quote = sprintf("%c", 39)
            }
            {
                line = $0
                output = ""
                quote = ""
                escaped = 0
                i = 1
                while (i <= length(line)) {
                    triple = substr(line, i, 3)
                    character = substr(line, i, 1)

                    if (in_triple != "") {
                        if (triple == in_triple) {
                            output = output "   "
                            in_triple = ""
                            i += 3
                        } else {
                            output = output " "
                            i += 1
                        }
                        continue
                    }

                    if (quote != "") {
                        output = output " "
                        if (escaped) {
                            escaped = 0
                        } else if (character == "\\") {
                            escaped = 1
                        } else if (character == quote) {
                            quote = ""
                        }
                        i += 1
                        continue
                    }

                    if (triple == double_quote double_quote double_quote \
                        || triple == single_quote single_quote single_quote) {
                        in_triple = triple
                        output = output "   "
                        i += 3
                        continue
                    }
                    if (character == "#") break
                    if (character == double_quote || character == single_quote) {
                        quote = character
                        output = output " "
                        i += 1
                        continue
                    }
                    output = output character
                    i += 1
                }
                print output
            }
        ' "${file}" > "${cache}"
    fi
    printf '%s\n' "${cache}"
}

definition_exists() {
    local file=$1
    local symbol=$2
    local clean_file
    clean_file=$(sanitized_source_file "${file}")
    rg -q -- "^(def|fn)[[:space:]]+${symbol}(\\[|\\()" "${clean_file}"
}

symbol_body_mentions() {
    local file=$1
    local symbol=$2
    local needle=$3
    local clean_file
    clean_file=$(sanitized_source_file "${file}")
    awk -v wanted_symbol="${symbol}" -v wanted_word="${needle}" '
        function has_call(text, word, pattern, dispatch) {
            pattern = "(^|[^A-Za-z0-9_])" word \
                "[[:space:]]*(\\[[^]]*\\][[:space:]]*)?[(]"
            dispatch = "enqueue_function[[:space:]]*\\[[[:space:]]*" \
                word "[[:space:]]*\\][[:space:]]*[(]"
            return text ~ pattern || text ~ dispatch
        }
        /^(def|fn)[[:space:]]+/ {
            if (inside) exit
            name=$0
            sub(/^(def|fn)[[:space:]]+/, "", name)
            sub(/[[(].*$/, "", name)
            if (name == wanted_symbol) inside=1
            next
        }
        inside { body = body "\n" $0 }
        END { exit(has_call(body, wanted_word) ? 0 : 1) }
    ' "${clean_file}"
}

symbol_reaches_api() {
    local file=$1
    local symbol=$2
    local api=$3
    local clean_file
    clean_file=$(sanitized_source_file "${file}")

    # Build the complete file-local call graph in one pass.  Besides ordinary
    # calls, a function supplied as a compile-time parameter (run[workload]())
    # is an executable reachability edge.  GPU kernels are executable only via
    # the explicit enqueue_function[api](...) dispatch form.
    awk -v start_symbol="${symbol}" -v wanted_api="${api}" '
        function executable_call(text, word, pattern, dispatch) {
            pattern = "(^|[^A-Za-z0-9_])" word \
                "[[:space:]]*(\\[[^]]*\\][[:space:]]*)?[(]"
            dispatch = "enqueue_function[[:space:]]*\\[[[:space:]]*" \
                word "[[:space:]]*\\][[:space:]]*[(]"
            return text ~ pattern || text ~ dispatch
        }
        function build_edges(text, caller, rest, call, callee, generic, token,
                             next_rest) {
            rest=text
            while (match(rest, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\[[^]]*\][[:space:]]*)?[(]/)) {
                call=substr(rest, RSTART, RLENGTH)
                next_rest=substr(rest, RSTART + RLENGTH)
                callee=call
                sub(/[[:space:]]*(\[[^]]*\][[:space:]]*)?[(]$/, "", callee)
                if (callee in functions) edges[caller SUBSEP callee]=1
                if (call ~ /\[/) {
                    generic=call
                    sub(/^[^[]*\[/, "", generic)
                    sub(/\][[:space:]]*[(]$/, "", generic)
                    while (match(generic, /[A-Za-z_][A-Za-z0-9_]*/)) {
                        token=substr(generic, RSTART, RLENGTH)
                        if (token in functions)
                            edges[caller SUBSEP token]=1
                        generic=substr(generic, RSTART + RLENGTH)
                    }
                }
                rest=next_rest
            }
        }
        /^(def|fn)[[:space:]]+/ {
            current=$0
            sub(/^(def|fn)[[:space:]]+/, "", current)
            sub(/[[(].*$/, "", current)
            functions[current]=1
            next
        }
        current != "" { bodies[current] = bodies[current] "\n" $0 }
        END {
            if (!(start_symbol in functions)) exit 1
            for (caller in functions) build_edges(bodies[caller], caller)
            head=1
            tail=1
            queue[1]=start_symbol
            seen[start_symbol]=1
            while (head <= tail) {
                caller=queue[head++]
                if (caller == wanted_api) exit 0
                if (executable_call(bodies[caller], wanted_api)) exit 0
                for (key in edges) {
                    split(key, pair, SUBSEP)
                    if (pair[1] == caller && !seen[pair[2]]) {
                        seen[pair[2]]=1
                        queue[++tail]=pair[2]
                    }
                }
            }
            exit 1
        }
    ' "${clean_file}"
}

symbol_has_no_inline() {
    local file=$1
    local symbol=$2
    local clean_file
    clean_file=$(sanitized_source_file "${file}")
    awk -v wanted_symbol="${symbol}" '
        /^@no_inline([[:space:]]|$)/ { decorated=1; next }
        /^(def|fn)[[:space:]]+/ {
            name=$0
            sub(/^(def|fn)[[:space:]]+/, "", name)
            sub(/[[(].*$/, "", name)
            if (name == wanted_symbol && decorated) found=1
            decorated=0
        }
        /^[^@[:space:]]/ && $0 !~ /^(def|fn)[[:space:]]+/ { decorated=0 }
        END { exit(found ? 0 : 1) }
    ' "${clean_file}"
}

benchmark_workload_is_timed() {
    local file=$1
    local workload=$2
    local api=$3
    local clean_file
    clean_file=$(sanitized_source_file "${file}")

    # A valid measurement path starts at main, reaches the resolved workload,
    # and executes that workload below a live timer pair.  The timer may live
    # in the @no_inline workload itself or in a real caller such as main.  This
    # rejects a perfectly shaped but dead helper, and rejects a target call
    # moved before the start timer or after the stop timer.
    awk -v wanted_workload="${workload}" -v wanted_api="${api}" '
        function executable_call(text, word, pattern, dispatch) {
            pattern = "(^|[^A-Za-z0-9_])" word \
                "[[:space:]]*(\\[[^]]*\\][[:space:]]*)?[(]"
            dispatch = "enqueue_function[[:space:]]*\\[[[:space:]]*" \
                word "[[:space:]]*\\][[:space:]]*[(]"
            return text ~ pattern || text ~ dispatch
        }
        function build_edges(text, caller, rest, call, callee, generic, token,
                             next_rest) {
            rest=text
            while (match(rest, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\[[^]]*\][[:space:]]*)?[(]/)) {
                call=substr(rest, RSTART, RLENGTH)
                next_rest=substr(rest, RSTART + RLENGTH)
                callee=call
                sub(/[[:space:]]*(\[[^]]*\][[:space:]]*)?[(]$/, "", callee)
                if (callee in functions) edges[caller SUBSEP callee]=1
                if (call ~ /\[/) {
                    generic=call
                    sub(/^[^[]*\[/, "", generic)
                    sub(/\][[:space:]]*[(]$/, "", generic)
                    while (match(generic, /[A-Za-z_][A-Za-z0-9_]*/)) {
                        token=substr(generic, RSTART, RLENGTH)
                        if (token in functions)
                            edges[caller SUBSEP token]=1
                        generic=substr(generic, RSTART + RLENGTH)
                    }
                }
                rest=next_rest
            }
        }
        function segment_reaches_workload(segment, owner, rest, call, callee,
                                          generic, token, next_rest) {
            if (owner == wanted_workload \
                && executable_call(segment, wanted_api)) return 1
            rest=segment
            while (match(rest, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\[[^]]*\][[:space:]]*)?[(]/)) {
                call=substr(rest, RSTART, RLENGTH)
                next_rest=substr(rest, RSTART + RLENGTH)
                callee=call
                sub(/[[:space:]]*(\[[^]]*\][[:space:]]*)?[(]$/, "", callee)
                if (can_reach_workload[callee]) return 1
                if (call ~ /\[/) {
                    generic=call
                    sub(/^[^[]*\[/, "", generic)
                    sub(/\][[:space:]]*[(]$/, "", generic)
                    while (match(generic, /[A-Za-z_][A-Za-z0-9_]*/)) {
                        token=substr(generic, RSTART, RLENGTH)
                        if (can_reach_workload[token]) return 1
                        generic=substr(generic, RSTART + RLENGTH)
                    }
                }
                rest=next_rest
            }
            return 0
        }
        function timed_region_reaches_workload(text, owner, timer_pattern,
                                                segment, timer_open) {
            timer_pattern = "global_perf_counter_ns[[:space:]]*[(]"
            timer_open=0
            while (match(text, timer_pattern)) {
                segment=substr(text, 1, RSTART - 1)
                if (timer_open && segment_reaches_workload(segment, owner))
                    return 1
                timer_open = !timer_open
                text=substr(text, RSTART + RLENGTH)
            }
            # An unmatched first counter read is not a timer region.  In
            # particular, a target call after one start read must not become
            # attributable merely because the function ends before a second
            # counter read.  Only the segment enclosed by a complete pair is
            # eligible; callers that own the timer remain supported because
            # their two reads surround the reachable workload call above.
            return 0
        }
        /^(def|fn)[[:space:]]+/ {
            current=$0
            sub(/^(def|fn)[[:space:]]+/, "", current)
            sub(/[[(].*$/, "", current)
            functions[current]=1
            next
        }
        current != "" { bodies[current] = bodies[current] "\n" $0 }
        END {
            if (!("main" in functions) \
                || !(wanted_workload in functions)) exit 1

            for (caller in functions) build_edges(bodies[caller], caller)

            # Forward reachability proves that the workload is not a dead
            # helper and limits eligible timer owners to executable runners.
            reachable_from_main["main"]=1
            changed=1
            while (changed) {
                changed=0
                for (key in edges) {
                    split(key, pair, SUBSEP)
                    if (reachable_from_main[pair[1]] \
                        && !reachable_from_main[pair[2]]) {
                        reachable_from_main[pair[2]]=1
                        changed=1
                    }
                }
            }
            if (!reachable_from_main[wanted_workload]) exit 1

            # Reverse reachability lets a timer wrap an intermediate runner
            # rather than naming the workload directly.
            can_reach_workload[wanted_workload]=1
            changed=1
            while (changed) {
                changed=0
                for (key in edges) {
                    split(key, pair, SUBSEP)
                    if (can_reach_workload[pair[2]] \
                        && !can_reach_workload[pair[1]]) {
                        can_reach_workload[pair[1]]=1
                        changed=1
                    }
                }
            }

            for (owner in functions) {
                if (reachable_from_main[owner] \
                    && timed_region_reaches_workload(bodies[owner], owner))
                    exit 0
            }
            exit 1
        }
    ' "${clean_file}"
}

validate_benchmark_execution_contract() {
    local api=$1
    local path=$2
    local entry_symbol=$3
    local workload=$4
    local file="${project_dir}/${path}"

    if ! definition_exists "${file}" main; then
        echo "${api}: benchmark ${path} has no executable main entrypoint" \
            >> "${errors_file}"
        return
    fi
    if ! symbol_reaches_api "${file}" main "${workload}"; then
        echo "${api}: benchmark workload ${path}::${workload} is not reachable from main" \
            >> "${errors_file}"
        return
    fi
    if [[ "${entry_symbol}" != "${workload}" ]] \
        && ! symbol_reaches_api "${file}" "${entry_symbol}" "${workload}"; then
        echo "${api}: benchmark ledger entry ${path}::${entry_symbol} does not reach @no_inline workload ${workload}" \
            >> "${errors_file}"
        return
    fi
    if ! benchmark_workload_is_timed "${file}" "${workload}" "${api}"; then
        echo "${api}: benchmark workload ${path}::${workload} is not executed inside a main-reachable timer region" \
            >> "${errors_file}"
    fi
}

benchmark_requires_post_timer_contract() {
    local path=$1
    local file="${project_dir}/${path}"
    local clean_file

    [[ "${path}" == benchmarks/wifi*_bench.mojo ]] || return 1
    clean_file=$(sanitized_source_file "${file}")
    rg -q -- '^def (_mix_bits|_mix_chips|_consume_bits|_consume_complex)\(' \
        "${clean_file}"
}

# Return success only when the requested label is an argument of an executable
# print(...) call.  This deliberately retains ordinary string contents while
# discarding comments and triple-quoted docstrings, so a commented label or a
# prose example cannot satisfy the benchmark metadata contract.  The optional
# third argument must occur in the same (possibly multiline) print call.
printed_label_exists() {
    local file=$1
    local wanted=$2
    local also=${3:-}
    awk -v wanted="${wanted}" -v also="${also}" '
        BEGIN {
            double_quote = sprintf("%c", 34)
            single_quote = sprintf("%c", 39)
        }
        function paren_delta(text, copy, opens, closes) {
            copy = text
            opens = gsub(/[(]/, "", copy)
            copy = text
            closes = gsub(/[)]/, "", copy)
            return opens - closes
        }
        {
            line = $0
            visible = ""
            structure = ""
            quote = ""
            escaped = 0
            i = 1
            while (i <= length(line)) {
                triple = substr(line, i, 3)
                character = substr(line, i, 1)
                if (in_triple != "") {
                    if (triple == in_triple) {
                        visible = visible "   "
                        structure = structure "   "
                        in_triple = ""
                        i += 3
                    } else {
                        visible = visible " "
                        structure = structure " "
                        i += 1
                    }
                    continue
                }
                if (quote != "") {
                    visible = visible character
                    structure = structure " "
                    if (escaped) {
                        escaped = 0
                    } else if (character == "\\") {
                        escaped = 1
                    } else if (character == quote) {
                        quote = ""
                    }
                    i += 1
                    continue
                }
                if (triple == double_quote double_quote double_quote \
                    || triple == single_quote single_quote single_quote) {
                    in_triple = triple
                    visible = visible "   "
                    structure = structure "   "
                    i += 3
                    continue
                }
                if (character == "#") break
                if (character == double_quote || character == single_quote) {
                    quote = character
                    visible = visible character
                    structure = structure " "
                    i += 1
                    continue
                }
                visible = visible character
                structure = structure character
                i += 1
            }

            if (!in_print && structure ~ /^[[:space:]]*print[[:space:]]*[(]/) {
                in_print = 1
                depth = 0
                call_text = ""
            }
            if (in_print) {
                call_text = call_text visible "\n"
                depth += paren_delta(structure)
                if (depth <= 0) {
                    if (index(call_text, wanted) > 0 \
                        && (also == "" || index(call_text, also) > 0)) found = 1
                    in_print = 0
                    call_text = ""
                }
            }
        }
        END { exit(found ? 0 : 1) }
    ' "${file}"
}

validate_post_timer_contract() {
    local api=$1
    local path=$2
    local symbol=$3
    local file="${project_dir}/${path}"
    local clean_file
    local result

    benchmark_requires_post_timer_contract "${path}" || return 0

    # File-level declarations are checked once even when many ledger APIs use
    # independent workloads in the same benchmark.
    if ! rg -q -x -F -- "${path}" "${timing_contract_files}"; then
        echo "${path}" >> "${timing_contract_files}"
        if printed_label_exists "${file}" 'timed_scope:' 'checksum'; then
            echo "${path}: timed_scope must not include checksum consumption" >> "${errors_file}"
        fi
        if ! printed_label_exists "${file}" \
            'post_timer_scope: keep-plus-full-output-checksum-plus-o1-fingerprint'; then
            echo "${path}: missing explicit post-timer full-output/fingerprint scope" >> "${errors_file}"
        fi
        if ! printed_label_exists "${file}" 'full_output_checksum:' \
            || ! printed_label_exists "${file}" 'fingerprint_checksum:'; then
            echo "${path}: benchmark must print separate full-output and O(1) fingerprint checksums" >> "${errors_file}"
        fi
    fi

    clean_file=$(sanitized_source_file "${file}")
    result=$(awk -v wanted_symbol="${symbol}" -v wanted_api="${api}" '
        function has_call(line, word, pattern) {
            pattern = "(^|[^A-Za-z0-9_])" word "[[:space:]]*[(]"
            return line ~ pattern
        }
        function fail(message) {
            if (error == "") error = message
        }
        /^(def|fn)[[:space:]]+/ {
            if (inside) exit
            name=$0
            sub(/^(def|fn)[[:space:]]+/, "", name)
            sub(/[[(].*$/, "", name)
            if (name == wanted_symbol) inside=1
        }
        inside {
            line=$0
            timer=(line ~ /global_perf_counter_ns[[:space:]]*\(/)
            target=has_call(line, wanted_api)
            consumer=(line ~ /(_consume_[A-Za-z0-9_]*|_mix_bits|_mix_chips|_mix_he_fields|_mix_u_fields|_mix)[[:space:]]*\(/)
            retained=(line ~ /keep[[:space:]]*\(/)

            if (timer) {
                if (state == 0) {
                    if (completed > 0 && (!post_consumed || !post_kept))
                        fail("next timed call starts before post-timer consume/keep")
                    state=1
                    post_consumed=0
                    post_kept=0
                } else if (state == 2) {
                    state=0
                    completed += 1
                } else {
                    fail("timer stopped or restarted before target API")
                }
            }

            if (target) {
                targets += 1
                if (state == 0) fail("target API executes without an in-workload timer")
                state=2
            }

            if (state == 2 && !target && (consumer || retained))
                fail("output consumption or keep occurs before timer stop")
            if (state == 0 && completed > 0 && consumer) post_consumed=1
            if (state == 0 && completed > 0 && retained) post_kept=1
        }
        END {
            if (!inside) fail("workload definition not found")
            if (targets == 0) fail("target API call not found")
            if (state != 0) fail("timed target has no matching timer stop")
            if (completed > 0 && (!post_consumed || !post_kept))
                fail("final timed call lacks post-timer consume/keep")
            if (error == "") print "OK"
            else print error
        }
    ' "${clean_file}")

    if [[ "${result}" != "OK" ]]; then
        echo "${api}: benchmark workload ${path}::${symbol} violates target-only timing contract (${result})" >> "${errors_file}"
    fi
}

validate_attributable_workload() {
    local api=$1
    local path=$2
    local symbol=$3
    local file="${project_dir}/${path}"
    local clean_file
    local calls target_count=0 other_calls=""

    # Tokenize call sites in the workload body and join them against every
    # public API recorded by the ledger.  This rejects a superficially unique
    # wrapper that still times a second public API.  Repeated calls to the same
    # target are a legitimate homogeneous batch when the benchmark reports the
    # corresponding operation denominator.
    clean_file=$(sanitized_source_file "${file}")
    calls=$(awk -F '\t' -v wanted_symbol="${symbol}" '
        NR == FNR {
            if (FNR > 1) apis[$3] = 1
            next
        }
        /^(def|fn)[[:space:]]+/ {
            if (inside) exit
            name=$0
            sub(/^(def|fn)[[:space:]]+/, "", name)
            sub(/[[(].*$/, "", name)
            if (name == wanted_symbol) inside=1
            next
        }
        inside { body = body "\n" $0 }
        END {
            dispatch_text=body
            while (match(dispatch_text, /enqueue_function[[:space:]]*\[[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\][[:space:]]*\(/)) {
                token=substr(dispatch_text, RSTART, RLENGTH)
                sub(/^.*\[[[:space:]]*/, "", token)
                sub(/[[:space:]]*\].*$/, "", token)
                if (token in apis) count[token] += 1
                dispatch_text=substr(dispatch_text, RSTART + RLENGTH)
            }
            call_text=body
            while (match(call_text, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\[[^]]*\][[:space:]]*)?\(/)) {
                token=substr(call_text, RSTART, RLENGTH)
                sub(/[[:space:]]*(\[[^]]*\][[:space:]]*)?\($/, "", token)
                if (token in apis) count[token] += 1
                call_text=substr(call_text, RSTART + RLENGTH)
            }
            for (token in count) print token "\t" count[token]
        }
    ' "${ledger}" "${clean_file}")

    while IFS=$'\t' read -r called_api call_count; do
        [[ -z "${called_api}" ]] && continue
        if [[ "${called_api}" == "${api}" ]]; then
            target_count=${call_count}
        else
            other_calls+="${other_calls:+,}${called_api}x${call_count}"
        fi
    done <<< "${calls}"
    if (( target_count < 1 )); then
        echo "${api}: benchmark workload ${path}::${symbol} must call its target at least once; found ${target_count}" >> "${errors_file}"
    fi
    if [[ -n "${other_calls}" ]]; then
        echo "${api}: benchmark workload ${path}::${symbol} also calls other public APIs (${other_calls})" >> "${errors_file}"
    fi
    validate_post_timer_contract "${api}" "${path}" "${symbol}"
}

resolve_benchmark_workload() {
    local api=$1
    local path=$2
    local entry_symbol=$3
    local file="${project_dir}/${path}"
    local helper
    local -a candidates=()

    # The strict contract prefers a direct workload reference.  This fast path
    # also keeps the thousand-row audit linear for the common case.
    if [[ "${entry_symbol}" != "main" ]] \
        && symbol_has_no_inline "${file}" "${entry_symbol}" \
        && symbol_body_mentions "${file}" "${entry_symbol}" "${api}"; then
        validate_attributable_workload "${api}" "${path}" "${entry_symbol}"
        validate_benchmark_execution_contract \
            "${api}" "${path}" "${entry_symbol}" "${entry_symbol}"
        printf '%s\t%s\t%s\n' "${api}" "${path}" "${entry_symbol}" \
            >> "${benchmark_workloads_file}"
        return
    fi

    while IFS= read -r helper; do
        [[ -z "${helper}" ]] && continue
        if ! symbol_has_no_inline "${file}" "${helper}"; then
            continue
        fi
        if ! symbol_body_mentions "${file}" "${helper}" "${api}"; then
            continue
        fi
        if [[ "${entry_symbol}" == "${helper}" ]] \
            || symbol_reaches_api "${file}" "${entry_symbol}" "${helper}"; then
            candidates+=("${helper}")
        fi
    done < <(
        clean_file=$(sanitized_source_file "${file}")
        awk '/^(def|fn)[[:space:]]+/ {
            name=$0
            sub(/^(def|fn)[[:space:]]+/, "", name)
            sub(/[[(].*$/, "", name)
            print name
        }' "${clean_file}"
    )

    if (( ${#candidates[@]} != 1 )); then
        echo "${api}: benchmark ${path}::${entry_symbol} must reach exactly one @no_inline workload that directly calls only its attributable API; found ${#candidates[@]} candidate(s)" >> "${errors_file}"
        return
    fi
    validate_attributable_workload "${api}" "${path}" "${candidates[0]}"
    validate_benchmark_execution_contract \
        "${api}" "${path}" "${entry_symbol}" "${candidates[0]}"
    printf '%s\t%s\t%s\n' "${api}" "${path}" "${candidates[0]}" \
        >> "${benchmark_workloads_file}"
}

validate_refs() {
    local api=$1
    local category=$2
    local refs=$3
    local ref path symbol
    local reachable_count=0
    local -a ref_array unreachable_refs=()

    [[ "${refs}" == "-" ]] && return 0
    IFS=';' read -r -a ref_array <<< "${refs}"
    for ref in "${ref_array[@]}"; do
        if [[ "${ref}" != *::* ]]; then
            echo "${api}: ${category} reference lacks path::symbol: ${ref}" >> "${errors_file}"
            continue
        fi
        path=${ref%%::*}
        symbol=${ref#*::}
        if [[ ! "${symbol}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            echo "${api}: ${category} has invalid symbol: ${ref}" >> "${errors_file}"
            continue
        fi
        if [[ "${path}" == /* || "${path}" == *'..'* ]]; then
            echo "${api}: ${category} path must be project-relative: ${path}" >> "${errors_file}"
            continue
        fi
        case "${category}" in
            source)
                [[ "${path}" == wireless_dsp/* ]] \
                    || echo "${api}: source must live under wireless_dsp/: ${ref}" >> "${errors_file}"
                ;;
            benchmark)
                [[ "${path}" == benchmarks/* ]] \
                    || echo "${api}: benchmark evidence must live under benchmarks/: ${ref}" >> "${errors_file}"
                ;;
            *)
                if [[ "${path}" != tests/* && "${path}" != examples/* ]]; then
                    echo "${api}: ${category} evidence must live under tests/ or examples/: ${ref}" >> "${errors_file}"
                fi
                ;;
        esac
        if [[ ! -f "${project_dir}/${path}" ]]; then
            echo "${api}: ${category} file does not exist: ${path}" >> "${errors_file}"
            continue
        fi
        if ! definition_exists "${project_dir}/${path}" "${symbol}"; then
            echo "${api}: ${category} symbol does not exist: ${ref}" >> "${errors_file}"
            continue
        fi
        if [[ "${category}" == "benchmark" ]]; then
            if ! symbol_reaches_api \
                "${project_dir}/${path}" "${symbol}" "${api}"; then
                echo "${api}: ${category} entry does not reach API through executable local calls: ${ref}" \
                    >> "${errors_file}"
            fi
            resolve_benchmark_workload "${api}" "${path}" "${symbol}"
        elif [[ "${category}" != "source" ]]; then
            if symbol_reaches_api \
                "${project_dir}/${path}" "${symbol}" "${api}"; then
                ((reachable_count += 1))
            else
                unreachable_refs+=("${ref}")
            fi
        fi
    done

    # A semicolon-separated evidence category may contain supporting fixtures
    # alongside the executable target exercise.  Keep every path/symbol check,
    # but require target reachability from the category as a whole.  A single
    # prose/comment-only reference therefore still fails.
    if [[ "${category}" != "source" && "${category}" != "benchmark" ]] \
        && (( reachable_count == 0 )); then
        for ref in "${unreachable_refs[@]}"; do
            echo "${api}: ${category} entry does not reach API through executable calls: ${ref}" \
                >> "${errors_file}"
        done
    fi
}

complete=0
partial=0
missing=0
rows=0

while IFS=$'\t' read -r component kind api source deterministic edge property differential oracle_kind tolerance tolerance_mode benchmark notes; do
    if component_is_excluded "${component}"; then
        echo "${api}" >> "${excluded_apis_file}"
        continue
    fi

    ((rows += 1))
    if rg -q -x -F -- "${api}" "${seen_file}"; then
        echo "${api}: duplicate ledger row" >> "${errors_file}"
    else
        echo "${api}" >> "${seen_file}"
    fi

    case "${kind}" in
        kernel|table_config|artifact) ;;
        *) echo "${api}: invalid kind '${kind}'" >> "${errors_file}" ;;
    esac

    validate_refs "${api}" source "${source}"
    validate_refs "${api}" deterministic "${deterministic}"
    validate_refs "${api}" edge "${edge}"
    validate_refs "${api}" property "${property}"
    validate_refs "${api}" differential "${differential}"
    validate_refs "${api}" tolerance "${tolerance}"
    validate_refs "${api}" benchmark "${benchmark}"

    if [[ "${source}" == *';'* || "${source}" == "-" ]]; then
        echo "${api}: source must be one path::symbol reference" >> "${errors_file}"
    elif [[ "${source#*::}" != "${api}" ]]; then
        echo "${api}: source symbol must equal API name: ${source}" >> "${errors_file}"
    fi

    if [[ "${differential}" != "-" ]]; then
        case "${oracle_kind}" in
            analytic|external_static|float64_reference|cross_implementation|exhaustive_integer) ;;
            *) echo "${api}: differential evidence needs an independent oracle kind, not '${oracle_kind}'" >> "${errors_file}" ;;
        esac
    elif [[ "${oracle_kind}" != "none" && "${oracle_kind}" != "not_applicable" ]]; then
        echo "${api}: oracle_kind '${oracle_kind}' has no differential evidence" >> "${errors_file}"
    fi

    if [[ "${tolerance}" != "-" ]]; then
        case "${tolerance_mode}" in
            exact|absolute|relative|statistical|mixed) ;;
            *) echo "${api}: tolerance evidence needs a valid tolerance_mode" >> "${errors_file}" ;;
        esac
    elif [[ "${tolerance_mode}" != "none" && "${tolerance_mode}" != "not_applicable" ]]; then
        echo "${api}: tolerance_mode '${tolerance_mode}' has no tolerance evidence" >> "${errors_file}"
    fi

    required=()
    [[ "${deterministic}" == "-" ]] && required+=(deterministic)
    [[ "${edge}" == "-" ]] && required+=(edge)
    [[ "${property}" == "-" ]] && required+=(property)
    [[ "${differential}" == "-" ]] && required+=(differential)
    [[ "${tolerance}" == "-" ]] && required+=(tolerance)
    [[ "${benchmark}" == "-" ]] && required+=(benchmark)
    evidence_total=6

    missing_count=${#required[@]}
    if (( missing_count == 0 )); then
        status=COMPLETE
        ((complete += 1))
        gap_text="-"
    elif (( missing_count == evidence_total )); then
        status=MISSING
        ((missing += 1))
        gap_text=$(IFS=,; echo "${required[*]}")
    else
        status=PARTIAL
        ((partial += 1))
        gap_text=$(IFS=,; echo "${required[*]}")
    fi
    printf '%-8s %-14s %-44s missing=%s\n' "${status}" "${component}/${kind}" "${api}" "${gap_text}"
    printf '%d\t%s\t%s\n' "${missing_count}" "${component}" "${api}" >> "${gaps_file}"
done < <(tail -n +2 "${ledger}")

awk -F '\t' '
    {
        key=$2 "::" $3
        count[key] += 1
        apis[key] = apis[key] (apis[key] == "" ? "" : ",") $1
    }
    END {
        for (key in count) {
            if (count[key] > 1) {
                print key " is reused by " count[key] " ledger APIs (" apis[key] ")"
            }
        }
    }
' "${benchmark_workloads_file}" | while IFS= read -r duplicate_workload; do
    [[ -z "${duplicate_workload}" ]] && continue
    echo "benchmark workload bundle: ${duplicate_workload}" >> "${errors_file}"
done

# Resolve every imported public function in the scoped package initializers.
# Imported structs/constants are deliberately ignored: a token is an API here
# only when a matching top-level def exists in one of the scoped source trees.
exports_file="${audit_tmp}/exports"
public_defs_file="${audit_tmp}/public-defs"
: > "${exports_file}"
: > "${public_defs_file}"
while IFS= read -r init_file; do
    awk '
        /^from .* import / { collecting=1 }
        collecting {
            line=$0
            sub(/^from .* import[[:space:]]*/, "", line)
            gsub(/[(),]/, " ", line)
            n=split(line, words, /[[:space:]]+/)
            for (i=1; i<=n; ++i) {
                if (words[i] ~ /^[A-Za-z_][A-Za-z0-9_]*$/ && words[i] != "from" && words[i] != "import") print words[i]
            }
            if ($0 !~ /\($/ && $0 !~ /^[[:space:]]/) collecting=0
            if (collecting && $0 ~ /\)/) collecting=0
        }
    ' "${init_file}" >> "${exports_file}"
done < <(
    find "${project_dir}/wireless_dsp/core" \
        "${project_dir}/wireless_dsp/numerics" \
        "${project_dir}/wireless_dsp/dsp" \
        "${project_dir}/wireless_dsp/modem" \
        "${project_dir}/wireless_dsp/mimo" \
        "${project_dir}/wireless_dsp/fec" \
        "${project_dir}/wireless_dsp/channel" \
        "${project_dir}/wireless_dsp/synchronization" \
        "${project_dir}/wireless_dsp/backend" \
        "${project_dir}/wireless_dsp/testing" \
        "${project_dir}/wireless_dsp/wireless/bluetooth" \
        "${project_dir}/wireless_dsp/wireless/matter" \
        "${project_dir}/wireless_dsp/wireless/zigbee" \
        "${project_dir}/wireless_dsp/wireless/lte" \
        "${project_dir}/wireless_dsp/wireless/nr" \
        "${project_dir}/wireless_dsp/wireless/wifi" \
        -name __init__.mojo -type f \
        | while IFS= read -r init_file; do
            if component_is_excluded backend_gpu \
                && [[ "${init_file}" == */wireless_dsp/backend/gpu/* ]]; then
                continue
            fi
            printf '%s\n' "${init_file}"
        done \
        | sort
)

sort -u "${exports_file}" -o "${exports_file}"
if [[ ! -s "${exports_file}" ]]; then
    echo "public API scan produced no import tokens" >> "${errors_file}"
fi
while IFS= read -r exported; do
    [[ -z "${exported}" ]] && continue
    if rg -q -g '*.mojo' -- "^def[[:space:]]+${exported}(\\[|\\()" \
        "${project_dir}/wireless_dsp/core" \
        "${project_dir}/wireless_dsp/numerics" \
        "${project_dir}/wireless_dsp/dsp" \
        "${project_dir}/wireless_dsp/modem" \
        "${project_dir}/wireless_dsp/mimo" \
        "${project_dir}/wireless_dsp/fec" \
        "${project_dir}/wireless_dsp/channel" \
        "${project_dir}/wireless_dsp/synchronization" \
        "${project_dir}/wireless_dsp/backend" \
        "${project_dir}/wireless_dsp/testing" \
        "${project_dir}/wireless_dsp/wireless/bluetooth" \
        "${project_dir}/wireless_dsp/wireless/matter" \
        "${project_dir}/wireless_dsp/wireless/zigbee" \
        "${project_dir}/wireless_dsp/wireless/lte" \
        "${project_dir}/wireless_dsp/wireless/nr" \
        "${project_dir}/wireless_dsp/wireless/wifi"; then
        echo "${exported}" >> "${public_defs_file}"
        if ! rg -q -x -F -- "${exported}" "${seen_file}"; then
            echo "${exported}: exported public function is absent from ledger" >> "${errors_file}"
        fi
    fi
done < "${exports_file}"

sort -u "${public_defs_file}" -o "${public_defs_file}"
while IFS= read -r recorded; do
    if rg -q -x -F -- "${recorded}" "${excluded_apis_file}"; then
        continue
    fi
    if ! rg -q -x -F -- "${recorded}" "${public_defs_file}"; then
        echo "${recorded}: ledger API is not exported by a scoped package initializer" >> "${errors_file}"
    fi
done < "${seen_file}"

echo
echo "SUMMARY rows=${rows} COMPLETE=${complete} PARTIAL=${partial} MISSING=${missing}"
if (( partial + missing > 0 )); then
    echo "GAP RANKING (missing required categories, descending; top 20)"
    sort -t $'\t' -k1,1nr -k2,2 -k3,3 "${gaps_file}" | awk -F '\t' '$1 > 0 { printf "  %d  %s/%s\n", $1, $2, $3 }' | head -n 20
fi

if [[ -s "${errors_file}" ]]; then
    echo >&2
    echo "STRUCTURAL ERRORS" >&2
    sort -u "${errors_file}" >&2
    exit 2
fi

if (( strict && partial + missing > 0 )); then
    echo "STRICT FAIL: ${partial} PARTIAL and ${missing} MISSING rows remain" >&2
    exit 1
fi

if (( partial + missing > 0 )); then
    echo "AUDIT OK (non-strict): coverage gaps are reported above"
else
    echo "AUDIT OK: all required coverage is COMPLETE"
fi
