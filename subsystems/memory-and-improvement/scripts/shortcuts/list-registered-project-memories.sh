#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_ROOT/shared/memory-paths.sh"

existing_only="false"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--existing-only true|false]
Print registered project memory directories from the local registry.
With --existing-only true, only print entries whose directories still exist.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --existing-only)
            existing_only="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "$existing_only" in
    true|false) ;;
    *)
        printf 'Invalid --existing-only: %s\n' "$existing_only" >&2
        exit 1
        ;;
esac

while IFS= read -r memory_dir; do
    [[ -n "$memory_dir" ]] || continue
    if [[ "$existing_only" == "true" && ! -d "$memory_dir" ]]; then
        continue
    fi
    printf '%s\n' "$memory_dir"
done < <(self_improving_list_registered_project_memory_dirs)
