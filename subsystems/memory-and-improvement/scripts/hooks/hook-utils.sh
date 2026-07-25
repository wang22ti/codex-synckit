#!/bin/bash
# Shared helpers for Codex hook scripts.

if [[ -n "${SELF_IMPROVING_HOOK_UTILS_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
SELF_IMPROVING_HOOK_UTILS_SH_LOADED=1

hook_input=""

read_hook_input() {
    if [[ -t 0 ]]; then
        return 0
    fi

    hook_input="$(cat)"
}

hook_find_python() {
    if command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "python3"
        return 0
    fi

    if command -v python >/dev/null 2>&1; then
        printf '%s\n' "python"
        return 0
    fi

    return 1
}

extract_hook_field_without_python() {
    local field_name="$1"

    printf '%s' "$hook_input" | awk -v field="$field_name" '
        BEGIN {
            pattern = "\"" field "\"[[:space:]]*:[[:space:]]*\""
        }
        {
            if (!match($0, pattern)) {
                next
            }

            rest = substr($0, RSTART + RLENGTH)
            value = ""
            escaped = 0

            for (i = 1; i <= length(rest); i++) {
                c = substr(rest, i, 1)

                if (escaped) {
                    value = value c
                    escaped = 0
                    continue
                }

                if (c == "\\") {
                    escaped = 1
                    continue
                }

                if (c == "\"") {
                    print value
                    exit
                }

                value = value c
            }
        }
    '
}

extract_hook_field() {
    local field_name="$1"
    local python_cmd=""

    [[ -n "$hook_input" ]] || return 0

    if ! python_cmd="$(hook_find_python)"; then
        extract_hook_field_without_python "$field_name"
        return 0
    fi

    PYTHONIOENCODING=utf-8 HOOK_INPUT="$hook_input" "$python_cmd" - "$field_name" <<'PY'
import json
import os
import sys

field = sys.argv[1]
raw = os.environ.get("HOOK_INPUT", "")
if not raw.strip():
    raise SystemExit(0)

try:
    payload = json.loads(raw)
except Exception:
    raise SystemExit(0)

value = payload.get(field)
if value is None:
    raise SystemExit(0)

print(value)
PY
}

trim_whitespace() {
    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

truncate_chars() {
    local value="${1:-}"
    local limit="${2:-0}"

    if [[ -z "$limit" || ! "$limit" =~ ^[0-9]+$ || "$limit" -le 0 ]]; then
        printf '%s' "$value"
        return 0
    fi

    if [[ "${#value}" -le "$limit" ]]; then
        printf '%s' "$value"
        return 0
    fi

    printf '%s…' "${value:0:limit}"
}

run_with_optional_timeout() {
    local timeout_seconds="$1"
    shift

    if [[ -n "$timeout_seconds" ]] && command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_seconds" "$@"
        return $?
    fi

    "$@"
}
