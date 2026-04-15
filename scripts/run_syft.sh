#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures"
SNAPSHOT_DIR="$REPO_ROOT/tests/snapshots"

run_syft_on_fixture() {
    local ecosystem="$1"
    local fixture_path="$FIXTURE_DIR/$ecosystem"
    local out_dir="$SNAPSHOT_DIR/$ecosystem"

    mkdir -p "$out_dir"

    echo "[syft] scanning $ecosystem fixture at $fixture_path"

    syft dir:"$fixture_path" \
        -o spdx-json \
        --file "$out_dir/syft_spdx.json" \
        --quiet

    syft dir:"$fixture_path" \
        -o cyclonedx-json \
        --file "$out_dir/syft_cyclonedx.json" \
        --quiet

    echo "[syft] $ecosystem done → $out_dir/syft_spdx.json, syft_cyclonedx.json"
}

for eco in cargo go terraform; do
    if [ -d "$FIXTURE_DIR/$eco" ]; then
        run_syft_on_fixture "$eco"
    else
        echo "[syft] fixture not found, skipping: $FIXTURE_DIR/$eco"
    fi
done
