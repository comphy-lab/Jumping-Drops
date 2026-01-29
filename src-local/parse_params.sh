#!/bin/bash

PARAM_KEYS=()

_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf "%s" "$s"
}

clear_params() {
    local key
    for key in "${PARAM_KEYS[@]}"; do
        unset "PARAM_${key}"
    done
    PARAM_KEYS=()
}

parse_param_file() {
    local file="$1"
    local line key value

    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "ERROR: Parameter file not found: $file" >&2
        return 1
    fi

    clear_params

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(_trim "$line")"
        [ -z "$line" ] && continue
        [[ "$line" != *"="* ]] && continue

        key="$(_trim "${line%%=*}")"
        value="$(_trim "${line#*=}")"

        [ -z "$key" ] && continue
        if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            echo "WARNING: Invalid key '$key' in $file, skipping" >&2
            continue
        fi

        PARAM_KEYS+=("$key")
        printf -v "PARAM_${key}" "%s" "$value"
    done < "$file"
}

get_param() {
    local key="$1"
    local var="PARAM_${key}"
    printf "%s" "${!var}"
}
