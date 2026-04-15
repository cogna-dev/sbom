#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys

ECOSYSTEM_FILES = {
    "cargo": ["Cargo.toml", "Cargo.lock"],
    "go": ["go.mod", "go.sum"],
    "terraform": [".terraform.lock.hcl"],
}


def load_fixture_files(ecosystem: str, fixture_dir: str) -> dict[str, str]:
    files: dict[str, str] = {}
    if ecosystem == "terraform":
        for fname in os.listdir(fixture_dir):
            if fname.endswith(".tf"):
                with open(os.path.join(fixture_dir, fname), encoding="utf-8") as f:
                    files[fname] = f.read()
        lock_path = os.path.join(fixture_dir, ".terraform.lock.hcl")
        if os.path.exists(lock_path):
            with open(lock_path, encoding="utf-8") as f:
                files[".terraform.lock.hcl"] = f.read()
    else:
        for fname in ECOSYSTEM_FILES.get(ecosystem, []):
            path = os.path.join(fixture_dir, fname)
            if os.path.exists(path):
                with open(path, encoding="utf-8") as f:
                    files[fname] = f.read()
    return files


def run_our_tool(
    ecosystem: str,
    fixture_dir: str,
    out_spdx: str,
    out_cyclonedx: str,
    repo_root: str,
) -> None:
    files = load_fixture_files(ecosystem, fixture_dir)
    if not files:
        print(
            f"[run_our_tool] ERROR: no fixture files found in {fixture_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    payload = json.dumps({"ecosystem": ecosystem, "files": files})
    result = subprocess.run(
        ["moon", "run", "src/cmd", "--", payload],
        cwd=repo_root,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(
            f"[run_our_tool] ERROR: moon run failed (exit {result.returncode})\n"
            f"stderr:\n{result.stderr}",
            file=sys.stderr,
        )
        sys.exit(1)

    # The CLI emits two pretty-printed JSON objects concatenated on stdout.
    # Use raw_decode to parse them sequentially instead of splitting on newlines.
    raw = result.stdout.strip()
    decoder = json.JSONDecoder()
    try:
        spdx_obj, idx = decoder.raw_decode(raw)
    except json.JSONDecodeError as e:
        print(
            f"[run_our_tool] ERROR: SPDX output is not valid JSON: {e}\n"
            f"Output (first 500 chars):\n{raw[:500]}",
            file=sys.stderr,
        )
        sys.exit(1)

    rest = raw[idx:].lstrip()
    if not rest:
        print(
            "[run_our_tool] ERROR: CycloneDX output missing (only one JSON object in output)",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        cdx_obj, _ = decoder.raw_decode(rest)
    except json.JSONDecodeError as e:
        print(
            f"[run_our_tool] ERROR: CycloneDX output is not valid JSON: {e}\n"
            f"Rest (first 500 chars):\n{rest[:500]}",
            file=sys.stderr,
        )
        sys.exit(1)

    os.makedirs(os.path.dirname(out_spdx), exist_ok=True)
    os.makedirs(os.path.dirname(out_cyclonedx), exist_ok=True)

    with open(out_spdx, "w", encoding="utf-8") as f:
        json.dump(spdx_obj, f, indent=2)
    print(f"[run_our_tool] wrote {out_spdx}")

    with open(out_cyclonedx, "w", encoding="utf-8") as f:
        json.dump(cdx_obj, f, indent=2)
    print(f"[run_our_tool] wrote {out_cyclonedx}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--ecosystem", required=True, choices=["cargo", "go", "terraform"]
    )
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--out-spdx", required=True)
    parser.add_argument("--out-cyclonedx", required=True)
    parser.add_argument("--repo-root", default=None)
    args = parser.parse_args()

    repo_root = args.repo_root or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))
    )

    run_our_tool(
        ecosystem=args.ecosystem,
        fixture_dir=os.path.abspath(args.fixture),
        out_spdx=os.path.abspath(args.out_spdx),
        out_cyclonedx=os.path.abspath(args.out_cyclonedx),
        repo_root=repo_root,
    )


if __name__ == "__main__":
    main()
