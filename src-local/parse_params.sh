#!/bin/bash

declare -a PARAM_KEYS=()

trim_whitespace() {
    local s="${1-}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf "%s" "$s"
}

clear_params() {
    local key
    for key in "${PARAM_KEYS[@]-}"; do
        unset "PARAM_${key}"
    done
    PARAM_KEYS=()
}

validate_param_key() {
    local key="${1-}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

validate_case_no() {
    local case_no="${1-}"

    if [[ ! "$case_no" =~ ^[0-9]{4}$ ]] || [ "$case_no" -lt 1000 ] || [ "$case_no" -gt 9999 ]; then
        echo "ERROR: CaseNo must be a 4-digit integer in [1000, 9999], got: ${case_no:-<empty>}" >&2
        return 1
    fi
}

parse_param_file() {
    local file="${1-}"
    local line key value

    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "ERROR: Parameter file not found: $file" >&2
        return 1
    fi

    clear_params

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(trim_whitespace "$line")"
        [ -z "$line" ] && continue
        [[ "$line" != *"="* ]] && continue

        key="$(trim_whitespace "${line%%=*}")"
        value="$(trim_whitespace "${line#*=}")"

        [ -z "$key" ] && continue
        if ! validate_param_key "$key"; then
            echo "WARNING: Invalid key '$key' in $file, skipping" >&2
            continue
        fi

        PARAM_KEYS+=("$key")
        printf -v "PARAM_${key}" "%s" "$value"
    done < "$file"
}

get_param() {
    local key="${1-}"
    local var="PARAM_${key}"
    printf "%s" "${!var-}"
}

get_param_value() {
    local file="${1-}"
    local key="${2-}"

    parse_param_file "$file" || return 1
    get_param "$key"
}

require_params() {
    local file="${1-}"
    shift

    parse_param_file "$file" || return 1

    local key
    local missing=0
    for key in "$@"; do
        if [ -z "$(get_param "$key")" ]; then
            echo "ERROR: Required parameter '$key' missing in $file" >&2
            missing=1
        fi
    done

    [ "$missing" -eq 0 ]
}

set_param_in_file() {
    local file="${1-}"
    local key="${2-}"
    local value="${3-}"
    local tmp_file

    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "ERROR: Parameter file not found: $file" >&2
        return 1
    fi

    if ! validate_param_key "$key"; then
        echo "ERROR: Invalid parameter key: $key" >&2
        return 1
    fi

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/params.XXXXXX")"

    awk -v key="$key" -v value="$value" '
        BEGIN {
            updated = 0;
            pattern = "^[[:space:]]*" key "[[:space:]]*=";
        }
        {
            if (!updated && $0 !~ /^[[:space:]]*#/ && $0 ~ pattern) {
                print key "=" value;
                updated = 1;
                next;
            }
            print;
        }
        END {
            if (!updated) {
                print key "=" value;
            }
        }
    ' "$file" > "$tmp_file"

    mv "$tmp_file" "$file"
}
