# Test Guide

This directory contains the regression and smoke tests for the `memory-and-improvement` skill.

## How To Run

Run one test:

```bash
bash /home/example/.codex/skills/memory-and-improvement/scripts/tests/search-memory-test.sh
```

Run the full suite:

```bash
for test_script in /home/example/.codex/skills/memory-and-improvement/scripts/tests/*.sh; do
  printf '=== %s ===\n' "${test_script##*/}"
  bash "$test_script" || exit 1
done
```

On Windows with Git for Windows installed, also run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\scripts\tests\windows-maintenance-test.ps1
```

## What Is Covered

- config and path resolution
- capture and concurrent logging
- recall/search behavior, degraded inputs, and no-`rg` fallback
- maintenance flows across `project`, `global`, and `both`
- closed-loop end-to-end behavior
- project/global scale smoke coverage
- mixed-type and multi-namespace scale coverage

## Writing New Tests

- Keep tests hermetic: use `mktemp -d` fixtures and clean up with `trap`.
- Prefer behavior-level assertions over implementation-detail assertions.
- Use realistic fixtures when testing `recall`, `search`, `organize`, `writeback`, and `nightly`.
- Add targeted tests for one failure mode at a time; add larger smoke tests only when they cover a real gap.
- Keep tests runnable with plain `bash` and repo-local scripts only.

## Naming

- Use `*-test.sh` for focused regression tests.
- Use `*-smoke-test.sh` for broader scale or end-to-end coverage.
- Prefer names that match the script or workflow under test.

## Maintenance Notes

- If a test starts needing many fixtures, prefer generating them in-place inside the test rather than depending on shared mutable state.
- When adding scale tests, optimize for correctness and regression signal first; add explicit performance thresholds only if they remain stable across environments.
