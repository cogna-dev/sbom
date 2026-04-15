#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures"
SNAPSHOT_DIR="$REPO_ROOT/tests/snapshots"
MSBOM_TMP="$REPO_ROOT/tests/snapshots/.msbom_tmp"

run_msbom_on_fixture() {
    local ecosystem="$1"
    local fixture_path="$FIXTURE_DIR/$ecosystem"
    local out_dir="$SNAPSHOT_DIR/$ecosystem"
    local tmp_out="$MSBOM_TMP/$ecosystem"

    mkdir -p "$out_dir"
    rm -rf "$tmp_out"
    mkdir -p "$tmp_out"

    echo "[msbom] scanning $ecosystem fixture at $fixture_path"

    sbom-tool generate \
        -b "$tmp_out" \
        -bc "$fixture_path" \
        -pn "sample-$ecosystem" \
        -pv "0.1.0" \
        -ps "cogna-dev" \
        -nsb "https://cogna-dev.github.io/sbom" \
        -V 4 2>/dev/null || true

    local msbom_file
    msbom_file=$(find "$tmp_out" -name "*.spdx.json" 2>/dev/null | head -1)
    if [ -n "$msbom_file" ]; then
        cp "$msbom_file" "$out_dir/msbom_spdx.json"
        echo "[msbom] $ecosystem done → $out_dir/msbom_spdx.json"
    else
        echo "[msbom] $ecosystem: no SPDX output found (tool may not support this ecosystem)"
        echo '{"packages":[],"relationships":[]}' > "$out_dir/msbom_spdx.json"
    fi
}

for eco in cargo go terraform; do
    if [ -d "$FIXTURE_DIR/$eco" ]; then
        run_msbom_on_fixture "$eco"
    else
        echo "[msbom] fixture not found, skipping: $FIXTURE_DIR/$eco"
    fi
done
