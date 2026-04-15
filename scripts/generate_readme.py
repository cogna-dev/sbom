#!/usr/bin/env python3
"""
generate_readme.py — Render a structured diff JSON into COMPARISON.md.

Reads the JSON diff files produced by compare.py (one per ecosystem+format
combination) and merges them into a single Markdown report committed to the
repository.

Usage:
    python3 scripts/generate_readme.py \
        --results tests/snapshots/cargo/diff_spdx.json \
                  tests/snapshots/go/diff_spdx.json \
                  tests/snapshots/terraform/diff_spdx.json \
        --output COMPARISON.md
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


EMOJI = {
    "only-ours": "🔵",
    "missing": "🔴",
    "version-mismatch": "🟡",
    "purl-diff": "🟠",
    "no-license": "⚪",
}

TOOL_LABELS = {
    "syft": "[syft](https://github.com/anchore/syft)",
    "msbom": "[microsoft/sbom-tool](https://github.com/microsoft/sbom-tool)",
}

ECOSYSTEM_EMOJI = {
    "cargo": "🦀",
    "go": "🐹",
    "terraform": "🏗️",
}


def _tag_label(tag: str) -> str:
    emoji = EMOJI.get(tag, "❓")
    return f"`{emoji} {tag}`"


def _pct(n: int, total: int) -> str:
    if total == 0:
        return "–"
    return f"{n / total * 100:.0f}%"


def render_comparison(comp: dict) -> str:
    lines: list[str] = []
    tool = comp["tool"]
    fmt = comp["format"].upper()
    total_ours = comp["total_ours"]
    total_theirs = comp["total_theirs"]
    matched = comp["matched"]

    tool_label = TOOL_LABELS.get(tool, tool)
    lines.append(f"#### vs {tool_label} · `{fmt}`\n")

    lines.append("| Metric | Value |")
    lines.append("|--------|-------|")
    lines.append(f"| Our packages | {total_ours} |")
    lines.append(f"| {tool} packages | {total_theirs} |")
    lines.append(f"| Exact matches | {matched} ({_pct(matched, total_ours)}) |")

    only_ours = comp["only_ours"]
    only_theirs = comp["only_theirs"]
    ver_mismatches = comp["version_mismatches"]
    purl_diffs = comp["purl_diffs"]

    lines.append(f"| {EMOJI['only-ours']} Only in ours | {len(only_ours)} |")
    lines.append(
        f"| {EMOJI['missing']} Missing (only in {tool}) | {len(only_theirs)} |"
    )
    lines.append(
        f"| {EMOJI['version-mismatch']} Version mismatches | {len(ver_mismatches)} |"
    )
    lines.append(f"| {EMOJI['purl-diff']} PURL diffs | {len(purl_diffs)} |")
    lines.append("")

    if only_ours:
        lines.append(f"<details>")
        lines.append(
            f"<summary>{EMOJI['only-ours']} Packages only in our output ({len(only_ours)})</summary>\n"
        )
        lines.append("| Package | Version | PURL |")
        lines.append("|---------|---------|------|")
        for d in only_ours:
            purl = d.get("purl_ours") or "–"
            lines.append(
                f"| `{d['package']}` | `{d.get('version_ours', '–')}` | `{purl}` |"
            )
        lines.append("\n</details>\n")

    if only_theirs:
        lines.append(f"<details>")
        lines.append(
            f"<summary>{EMOJI['missing']} Packages missing from our output ({len(only_theirs)})</summary>\n"
        )
        lines.append("| Package | Version | PURL |")
        lines.append("|---------|---------|------|")
        for d in only_theirs:
            purl = d.get("purl_theirs") or "–"
            lines.append(
                f"| `{d['package']}` | `{d.get('version_theirs', '–')}` | `{purl}` |"
            )
        lines.append("\n</details>\n")

    if ver_mismatches:
        lines.append(f"<details>")
        lines.append(
            f"<summary>{EMOJI['version-mismatch']} Version mismatches ({len(ver_mismatches)})</summary>\n"
        )
        lines.append("| Package | Ours | " + tool + " |")
        lines.append("|---------|------|" + "-" * (len(tool) + 2) + "|")
        for d in ver_mismatches:
            lines.append(
                f"| `{d['package']}` | `{d.get('version_ours', '–')}` | `{d.get('version_theirs', '–')}` |"
            )
        lines.append("\n</details>\n")

    if purl_diffs:
        lines.append(f"<details>")
        lines.append(
            f"<summary>{EMOJI['purl-diff']} PURL format differences ({len(purl_diffs)})</summary>\n"
        )
        lines.append("| Package | Ours | " + tool + " |")
        lines.append("|---------|------|" + "-" * (len(tool) + 2) + "|")
        for d in purl_diffs:
            lines.append(
                f"| `{d['package']}` | `{d.get('purl_ours', '–')}` | `{d.get('purl_theirs', '–')}` |"
            )
        lines.append("\n</details>\n")

    return "\n".join(lines)


def render_ecosystem(ecosystem_results: list[dict]) -> str:
    eco = ecosystem_results[0]["ecosystem"]
    emoji = ECOSYSTEM_EMOJI.get(eco, "📦")
    lines: list[str] = []
    lines.append(f"### {emoji} `{eco}`\n")

    for result in ecosystem_results:
        for comp in result["comparisons"]:
            lines.append(render_comparison(comp))

    return "\n".join(lines)


def render_legend() -> str:
    lines = [
        "## Legend\n",
        "| Symbol | Meaning |",
        "|--------|---------|",
        f"| {EMOJI['only-ours']} `only-ours` | Package present in our output but not in the reference tool |",
        f"| {EMOJI['missing']} `missing` | Package present in reference tool but absent from our output |",
        f"| {EMOJI['version-mismatch']} `version-mismatch` | Same package, different resolved version |",
        f"| {EMOJI['purl-diff']} `purl-diff` | Same package, different PURL string format |",
        f"| {EMOJI['no-license']} `no-license` | Package has no license info (expected — we only read manifests, not registries) |",
        "",
        "> **Note on known gaps:**",
        "> - License data: syft queries registries; we only extract from manifests.",
        "> - Terraform: microsoft/sbom-tool does not support Terraform providers.",
        "> - Timestamps: `created` / `serialNumber` fields are excluded from comparison.",
        "",
    ]
    return "\n".join(lines)


def render_summary_table(all_results: list[dict]) -> str:
    rows: list[str] = []
    rows.append(
        "| Ecosystem | Tool | Format | Ours | Theirs | Matched | Missing | Extra |"
    )
    rows.append(
        "|-----------|------|--------|------|--------|---------|---------|-------|"
    )

    for result in all_results:
        eco = result["ecosystem"]
        emoji = ECOSYSTEM_EMOJI.get(eco, "📦")
        for comp in result["comparisons"]:
            tool = TOOL_LABELS.get(comp["tool"], comp["tool"])
            rows.append(
                f"| {emoji} `{eco}` "
                f"| {tool} "
                f"| `{comp['format'].upper()}` "
                f"| {comp['total_ours']} "
                f"| {comp['total_theirs']} "
                f"| {comp['matched']} "
                f"| {len(comp['only_theirs'])} "
                f"| {len(comp['only_ours'])} |"
            )

    return "\n".join(rows)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render diff JSON files into COMPARISON.md"
    )
    parser.add_argument(
        "--results",
        nargs="+",
        type=Path,
        required=True,
        help="Paths to diff JSON files produced by compare.py",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("COMPARISON.md"),
        help="Output Markdown file (default: COMPARISON.md)",
    )
    args = parser.parse_args()

    all_results: list[dict] = []
    for p in args.results:
        if p.exists():
            data = json.loads(p.read_text())
            all_results.append(data)
        else:
            print(f"[generate_readme] skipping missing file: {p}")

    if not all_results:
        print("[generate_readme] no result files found, nothing to render.")
        return

    by_ecosystem: dict[str, list[dict]] = {}
    for r in all_results:
        eco = r["ecosystem"]
        by_ecosystem.setdefault(eco, []).append(r)

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    sections: list[str] = []
    sections.append("# SBOM Tool Comparison Report\n")
    sections.append(
        f"> Auto-generated on **{now}** by `scripts/generate_readme.py`.\n"
        "> Re-run `scripts/generate_report.sh` to refresh.\n"
    )
    sections.append("## Summary\n")
    sections.append(render_summary_table(all_results))
    sections.append("")
    sections.append(render_legend())
    sections.append("---\n")
    sections.append("## Detailed Results\n")

    for eco in ["cargo", "go", "terraform"]:
        if eco in by_ecosystem:
            sections.append(render_ecosystem(by_ecosystem[eco]))
            sections.append("")

    for eco, results in by_ecosystem.items():
        if eco not in ("cargo", "go", "terraform"):
            sections.append(render_ecosystem(results))
            sections.append("")

    output = "\n".join(sections)
    args.output.write_text(output)
    print(f"[generate_readme] written to {args.output}")


if __name__ == "__main__":
    main()
