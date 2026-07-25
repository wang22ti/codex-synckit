#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "$SCRIPT_DIR/../capture/log-memory.sh" \
    --scope global \
    --type learning \
    --category insight \
    "$@"
