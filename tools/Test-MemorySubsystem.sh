#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
subsystem_root="$repo_root/subsystems/memory-and-improvement"

while IFS= read -r -d '' script_path; do
  bash -n "$script_path"
done < <(find "$subsystem_root/scripts" -type f -name '*.sh' -print0)

for test_script in "$subsystem_root"/scripts/tests/*.sh; do
  printf '=== %s ===\n' "${test_script##*/}"
  bash "$test_script"
done

printf '[OK] memory subsystem shell tests passed\n'
