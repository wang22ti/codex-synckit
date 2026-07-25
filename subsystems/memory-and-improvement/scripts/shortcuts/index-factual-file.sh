#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "$SCRIPT_DIR/../capture/log-asset.sh" \
    --scope global \
    --type structured_fact_file \
    "$@"
