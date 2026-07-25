#!/bin/bash
# Cross-platform advisory file locks with a mkdir fallback for Git Bash.

if [[ -n "${SELF_IMPROVING_FILE_LOCK_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
SELF_IMPROVING_FILE_LOCK_SH_LOADED=1

self_improving_lock_acquire() {
    local name="$1"
    local lock_file="$2"
    local fd="$3"
    local lock_dir="${lock_file}.d"
    local attempt

    mkdir -p "$(dirname "$lock_file")"

    if command -v flock >/dev/null 2>&1; then
        touch "$lock_file"
        eval "exec ${fd}>>\"\$lock_file\""
        flock "$fd"
        printf -v "${name}_lock_mode" '%s' "flock"
        printf -v "${name}_lock_fd" '%s' "$fd"
        return 0
    fi

    for ((attempt = 1; attempt <= 200; attempt++)); do
        if mkdir "$lock_dir" 2>/dev/null; then
            printf -v "${name}_lock_mode" '%s' "mkdir"
            printf -v "${name}_lock_dir" '%s' "$lock_dir"
            return 0
        fi
        sleep 0.05
    done

    echo "Timed out waiting for fallback lock: $lock_dir" >&2
    return 1
}

self_improving_lock_release() {
    local name="$1"
    local mode_var="${name}_lock_mode"
    local mode="${!mode_var:-}"

    case "$mode" in
        flock)
            local fd_var="${name}_lock_fd"
            local fd="${!fd_var}"
            flock -u "$fd" || true
            eval "exec ${fd}>&-" || true
            ;;
        mkdir)
            local dir_var="${name}_lock_dir"
            local lock_dir="${!dir_var}"
            rmdir "$lock_dir" 2>/dev/null || true
            ;;
    esac

    printf -v "$mode_var" '%s' ""
}
