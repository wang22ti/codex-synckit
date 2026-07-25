#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PATHS_SCRIPT="$SKILL_DIR/scripts/shared/memory-paths.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/project-registry-locking-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_ROOT="$TMP_ROOT/home"
STATE_ROOT="$TMP_ROOT/state"
CODEXKIT_ROOT="$TMP_ROOT/OneDrive/CodexKit"
ONEDRIVE_ROOT="$TMP_ROOT/OneDrive"
PROJECT_ROOT="$TMP_ROOT/project"
REGISTRY_FILE="$CODEXKIT_ROOT/memory-system/project-memory-registry.tsv"
LEGACY_FILE="$STATE_ROOT/memory-and-improvement/project-memory-registry.txt"
LOCAL_A="$TMP_ROOT/local-a/.learnings"
LOCAL_B="$TMP_ROOT/local-b/.learnings"
ONEDRIVE_A="$ONEDRIVE_ROOT/projects/a/.learnings"
ONEDRIVE_B="$ONEDRIVE_ROOT/projects/b/.learnings"
LOCK_DIR="$STATE_ROOT/memory-and-improvement/project-memory-registry.lock"
DEVICE_ID="TEST-DEVICE"

mkdir -p "$HOME_ROOT" "$PROJECT_ROOT" "$LOCAL_A" "$LOCAL_B" "$ONEDRIVE_A" "$ONEDRIVE_B" "$(dirname "$LEGACY_FILE")"
printf '%s\n' "$LOCAL_A" > "$LEGACY_FILE"

run_registry() {
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        COMPUTERNAME="$DEVICE_ID" \
        OneDrive="$ONEDRIVE_ROOT" \
        SELF_IMPROVING_CODEXKIT_ROOT="$CODEXKIT_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc "$1"
}

for _ in $(seq 1 8); do
    run_registry 'source "'"$PATHS_SCRIPT"'"; self_improving_register_project_memory_dir "'"$LOCAL_A"'"; self_improving_register_project_memory_dir "'"$ONEDRIVE_A"'"' &
done
wait

[[ -f "$REGISTRY_FILE" ]] || {
    printf 'Expected shared registry file: %s\n' "$REGISTRY_FILE" >&2
    exit 1
}
[[ ! -f "$LEGACY_FILE" ]] || {
    printf 'Expected legacy registry to be removed after migration\n' >&2
    exit 1
}

grep -Fqx $'storage\tdevice\tpath' "$REGISTRY_FILE"
grep -Fxc $'local\tTEST-DEVICE\t'"$LOCAL_A" "$REGISTRY_FILE" | grep -qx '1'
grep -Fxc $'onedrive\t-\tprojects/a/.learnings' "$REGISTRY_FILE" | grep -qx '1'

mtime_before="$(stat -c %Y "$REGISTRY_FILE")"
sleep 1
run_registry 'source "'"$PATHS_SCRIPT"'"; self_improving_register_project_memory_dir "'"$ONEDRIVE_A"'"'
mtime_after="$(stat -c %Y "$REGISTRY_FILE")"
[[ "$mtime_before" == "$mtime_after" ]] || {
    printf 'Expected an already-registered path not to rewrite the shared registry\n' >&2
    exit 1
}

conflict_file="$CODEXKIT_ROOT/memory-system/project-memory-registry-OTHER-DEVICE-conflicted-copy.tsv"
{
    printf 'storage\tdevice\tpath\n'
    printf 'local\tOTHER-DEVICE\t%s\n' "$TMP_ROOT/other-local/.learnings"
    printf 'onedrive\t-\tprojects/b/.learnings\n'
} > "$conflict_file"
run_registry 'source "'"$PATHS_SCRIPT"'"; self_improving_register_project_memory_dir "'"$ONEDRIVE_A"'"'
grep -Fxc $'onedrive\t-\tprojects/b/.learnings' "$REGISTRY_FILE" | grep -qx '1'

listed="$(run_registry 'source "'"$PATHS_SCRIPT"'"; self_improving_list_registered_project_memory_dirs')"
[[ "$listed" == *"$LOCAL_A"* ]]
[[ "$listed" == *"$ONEDRIVE_A"* ]]
[[ "$listed" == *"$ONEDRIVE_B"* ]]

other_device_listed="$(
    env \
        HOME="$HOME_ROOT" \
        XDG_STATE_HOME="$STATE_ROOT" \
        COMPUTERNAME="OTHER-DEVICE" \
        OneDrive="$ONEDRIVE_ROOT" \
        SELF_IMPROVING_CODEXKIT_ROOT="$CODEXKIT_ROOT" \
        SELF_IMPROVING_PROJECT_ROOT="$PROJECT_ROOT" \
        bash -lc 'source "'"$PATHS_SCRIPT"'"; self_improving_list_registered_project_memory_dirs'
)"
[[ "$other_device_listed" != *"$LOCAL_A"* ]]
[[ "$other_device_listed" == *"$ONEDRIVE_A"* ]]

for _ in $(seq 1 8); do
    run_registry 'source "'"$PATHS_SCRIPT"'"; self_improving_unregister_project_memory_dir "'"$LOCAL_A"'"; self_improving_register_project_memory_dir "'"$LOCAL_B"'"' &
done
wait

if grep -Fq -- "$LOCAL_A" "$REGISTRY_FILE"; then
    printf 'Expected LOCAL_A to be absent after unregister\n' >&2
    exit 1
fi
grep -Fxc $'local\tTEST-DEVICE\t'"$LOCAL_B" "$REGISTRY_FILE" | grep -qx '1'
grep -Fxc $'onedrive\t-\tprojects/a/.learnings' "$REGISTRY_FILE" | grep -qx '1'

mkdir -p "$LOCK_DIR"
(
    sleep 1
    rmdir "$LOCK_DIR"
) &

start_epoch="$(date +%s)"
run_registry 'source "'"$PATHS_SCRIPT"'"; self_improving_register_project_memory_dir "'"$LOCAL_A"'"'
elapsed="$(( $(date +%s) - start_epoch ))"
[[ "$elapsed" -ge 1 ]] || {
    printf 'Expected register call to wait for held registry lock\n' >&2
    exit 1
}

printf 'project-registry-locking assertions passed\n'
