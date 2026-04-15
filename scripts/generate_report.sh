#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures"
SNAPSHOT_DIR="$REPO_ROOT/tests/snapshots"
SCRIPTS_DIR="$REPO_ROOT/scripts"

generate_our_sbom() {
    local ecosystem="$1"
    local out_dir="$SNAPSHOT_DIR/$ecosystem"
    mkdir -p "$out_dir"

    python3 "$SCRIPTS_DIR/run_our_tool.py" \
        --ecosystem "$ecosystem" \
        --fixture "$FIXTURE_DIR/$ecosystem" \
        --out-spdx "$out_dir/our_spdx.json" \
        --out-cyclonedx "$out_dir/our_cyclonedx.json"

    echo "[ours] $ecosystem done → $out_dir/our_spdx.json, our_cyclonedx.json"
}

run_comparisons() {
    local ecosystem="$1"
    local out_dir="$SNAPSHOT_DIR/$ecosystem"
    local diff_dir="$out_dir"

    for fmt in spdx cyclonedx; do
        local our_file="$out_dir/our_${fmt}.json"
        local syft_file="$out_dir/syft_${fmt}.json"
        local msbom_file="$out_dir/msbom_${fmt}.json"
        local diff_file="$diff_dir/diff_${fmt}.json"

        if [ ! -f "$our_file" ]; then
            echo "[compare] missing our file for $ecosystem/$fmt, skipping"
            continue
        fi

        syft_arg=""
        msbom_arg=""
        [ -f "$syft_file" ]  && syft_arg="--syft $syft_file"
        [ -f "$msbom_file" ] && msbom_arg="--msbom $msbom_file"

        if [ -z "$syft_arg" ] && [ -z "$msbom_arg" ]; then
            echo "[compare] no reference files for $ecosystem/$fmt, skipping"
            continue
        fi

        python3 "$SCRIPTS_DIR/compare.py" \
            --ecosystem "$ecosystem" \
            --ours "$our_file" \
            $syft_arg \
            $msbom_arg \
            --format "$fmt" \
            > "$diff_file"

        echo "[compare] $ecosystem/$fmt → $diff_file"
    done
}

for eco in cargo go terraform; do
    if [ -d "$FIXTURE_DIR/$eco" ]; then
        generate_our_sbom "$eco"
        run_comparisons "$eco"
    fi
done

diff_files=()
for eco in cargo go terraform; do
    for fmt in spdx cyclonedx; do
        f="$SNAPSHOT_DIR/$eco/diff_${fmt}.json"
        [ -f "$f" ] && diff_files+=("$f")
    done
done

if [ ${#diff_files[@]} -gt 0 ]; then
    python3 "$SCRIPTS_DIR/generate_readme.py" \
        --results "${diff_files[@]}" \
        --output "$REPO_ROOT/COMPARISON.md"
    echo "[report] COMPARISON.md updated"
else
    echo "[report] no diff files found, COMPARISON.md not updated"
fi
