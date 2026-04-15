#!/usr/bin/env python3
"""
compare.py — SBOM comparison engine.

Compares our tool's SPDX/CycloneDX output against syft and microsoft/sbom-tool
for a given ecosystem fixture. Emits a structured JSON diff to stdout.

Usage:
    python3 compare.py --ecosystem cargo \
        --ours  tests/snapshots/cargo/our_spdx.json \
        --syft  tests/snapshots/cargo/syft_spdx.json \
        --msbom tests/snapshots/cargo/msbom_spdx.json \
        --format spdx
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

SKIP_FIELDS = {"created", "serialNumber", "timestamp", "creationInfo"}


def _purl_key(purl: str | None, name: str) -> str:
    if purl:
        p = purl.strip().rstrip("/").rstrip("#")
        while "//" in p:
            p = p.replace("//", "/")
        at = p.rfind("@")
        if at != -1:
            pkg_part = p[:at]
            ver_part = p[at + 1 :].lstrip("v")
            return f"{pkg_part}@{ver_part}".lower()
        return p.lower()
    return name.lower()


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class PackageInfo:
    name: str
    version: str
    purl: str | None
    license: str | None
    checksum: str | None
    source_file: str


@dataclass
class Diff:
    tag: str
    package: str
    version_ours: str | None = None
    version_theirs: str | None = None
    purl_ours: str | None = None
    purl_theirs: str | None = None
    detail: str | None = None


@dataclass
class ToolComparison:
    tool: str
    ecosystem: str
    format: str
    only_ours: list[Diff] = field(default_factory=list)
    only_theirs: list[Diff] = field(default_factory=list)
    version_mismatches: list[Diff] = field(default_factory=list)
    purl_diffs: list[Diff] = field(default_factory=list)
    matched: int = 0
    total_ours: int = 0
    total_theirs: int = 0


@dataclass
class ComparisonResult:
    ecosystem: str
    comparisons: list[ToolComparison] = field(default_factory=list)


# ---------------------------------------------------------------------------
# SPDX parsing
# ---------------------------------------------------------------------------


def _purl_from_spdx_pkg(pkg: dict[str, Any]) -> str | None:
    for ref in pkg.get("externalRefs", []):
        if ref.get("referenceType") == "purl":
            return ref.get("referenceLocator")
    return None


def _license_from_spdx_pkg(pkg: dict[str, Any]) -> str | None:
    lic = pkg.get("licenseConcluded") or pkg.get("licenseDeclared")
    if lic in ("NOASSERTION", "NONE", None):
        return None
    return lic


def _checksum_from_spdx_pkg(pkg: dict[str, Any]) -> str | None:
    for cs in pkg.get("checksums", []):
        return cs.get("checksumValue")
    return None


def parse_spdx(path: Path, source_label: str) -> dict[str, PackageInfo]:
    data = json.loads(path.read_text())
    result: dict[str, PackageInfo] = {}
    for pkg in data.get("packages", []):
        name = pkg.get("name", "")
        version = pkg.get("versionInfo", "unknown")
        spdx_id: str = pkg.get("SPDXID", "")
        if spdx_id == "SPDXRef-DOCUMENT" or spdx_id.endswith("-DOCUMENT"):
            continue
        purl = _purl_from_spdx_pkg(pkg)
        license_ = _license_from_spdx_pkg(pkg)
        checksum = _checksum_from_spdx_pkg(pkg)
        key = _purl_key(purl, name)
        _register(
            result,
            PackageInfo(
                name=name,
                version=version,
                purl=purl,
                license=license_,
                checksum=checksum,
                source_file=source_label,
            ),
            key,
        )
    return result


# ---------------------------------------------------------------------------
# CycloneDX parsing
# ---------------------------------------------------------------------------


def _purl_from_cdx_component(comp: dict[str, Any]) -> str | None:
    return comp.get("purl")


def _license_from_cdx_component(comp: dict[str, Any]) -> str | None:
    for entry in comp.get("licenses", []):
        lic = entry.get("license", {})
        if "id" in lic:
            return lic["id"]
        if "name" in lic:
            return lic["name"]
    return None


def _checksum_from_cdx_component(comp: dict[str, Any]) -> str | None:
    for h in comp.get("hashes", []):
        return h.get("content")
    return None


def parse_cyclonedx(path: Path, source_label: str) -> dict[str, PackageInfo]:
    data = json.loads(path.read_text())
    result: dict[str, PackageInfo] = {}
    for comp in data.get("components", []):
        name = comp.get("name", "")
        version = comp.get("version", "unknown")
        purl = _purl_from_cdx_component(comp)
        license_ = _license_from_cdx_component(comp)
        checksum = _checksum_from_cdx_component(comp)
        key = _purl_key(purl, name)
        _register(
            result,
            PackageInfo(
                name=name,
                version=version,
                purl=purl,
                license=license_,
                checksum=checksum,
                source_file=source_label,
            ),
            key,
        )
    return result


# ---------------------------------------------------------------------------
# Core diff logic
# ---------------------------------------------------------------------------


def _normalise_version(v: str) -> str:
    return v.strip().lstrip("v")


def _normalise_purl(p: str | None) -> str | None:
    if p is None:
        return None
    p = p.strip().rstrip("/").rstrip("#")
    while "//" in p:
        p = p.replace("//", "/")
    at = p.rfind("@")
    if at != -1:
        pkg_part = p[:at]
        ver_part = p[at + 1 :].lstrip("v")
        return f"{pkg_part}@{ver_part}"
    return p


def _name_segment_key(name: str) -> str:
    seg = name.rstrip("/").rsplit("/", 1)[-1]
    return seg.lower()


def _register(
    result: dict[str, "PackageInfo"], info: "PackageInfo", primary_key: str
) -> None:
    result[primary_key] = info
    alt = _name_segment_key(info.name)
    if alt and alt != primary_key and alt not in result:
        result[alt] = info


def _unique_count(d: dict[str, "PackageInfo"]) -> int:
    return len({id(v) for v in d.values()})


def diff_packages(
    ours: dict[str, PackageInfo],
    theirs: dict[str, PackageInfo],
    tool: str,
    ecosystem: str,
    fmt: str,
) -> ToolComparison:
    comp = ToolComparison(
        tool=tool,
        ecosystem=ecosystem,
        format=fmt,
        total_ours=_unique_count(ours),
        total_theirs=_unique_count(theirs),
    )

    our_keys = set(ours.keys())
    their_keys = set(theirs.keys())

    matched = 0
    seen_matched: set[int] = set()
    seen_matched_ours: set[int] = set()
    seen_matched_theirs: set[int] = set()
    for key in our_keys & their_keys:
        o = ours[key]
        t = theirs[key]
        pair_id = (id(o), id(t))
        if pair_id in seen_matched:
            continue
        seen_matched.add(pair_id)
        seen_matched_ours.add(id(o))
        seen_matched_theirs.add(id(t))
        ov = _normalise_version(o.version)
        tv = _normalise_version(t.version)
        op = _normalise_purl(o.purl)
        tp = _normalise_purl(t.purl)

        has_diff = False
        if ov != tv:
            comp.version_mismatches.append(
                Diff(
                    tag="version-mismatch",
                    package=o.name,
                    version_ours=ov,
                    version_theirs=tv,
                )
            )
            has_diff = True

        if op is not None and tp is not None and op != tp:
            comp.purl_diffs.append(
                Diff(
                    tag="purl-diff",
                    package=o.name,
                    purl_ours=op,
                    purl_theirs=tp,
                )
            )
            has_diff = True

        if not has_diff:
            matched += 1

    comp.matched = matched

    seen_ours: set[int] = set()
    for key in our_keys - their_keys:
        o = ours[key]
        if id(o) in seen_ours or id(o) in seen_matched_ours:
            continue
        seen_ours.add(id(o))
        comp.only_ours.append(
            Diff(
                tag="only-ours",
                package=o.name,
                version_ours=_normalise_version(o.version),
                purl_ours=_normalise_purl(o.purl),
            )
        )

    seen_theirs: set[int] = set()
    for key in their_keys - our_keys:
        t = theirs[key]
        if id(t) in seen_theirs or id(t) in seen_matched_theirs:
            continue
        seen_theirs.add(id(t))
        comp.only_theirs.append(
            Diff(
                tag="missing",
                package=t.name,
                version_theirs=_normalise_version(t.version),
                purl_theirs=_normalise_purl(t.purl),
            )
        )

    comp.only_ours.sort(key=lambda d: d.package)
    comp.only_theirs.sort(key=lambda d: d.package)
    comp.version_mismatches.sort(key=lambda d: d.package)
    comp.purl_diffs.sort(key=lambda d: d.package)

    return comp


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def load_packages(path: Path, fmt: str, label: str) -> dict[str, PackageInfo]:
    if fmt == "spdx":
        return parse_spdx(path, label)
    elif fmt == "cyclonedx":
        return parse_cyclonedx(path, label)
    else:
        print(f"[compare] unknown format: {fmt}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare SBOM outputs between our tool, syft, and microsoft/sbom-tool."
    )
    parser.add_argument("--ecosystem", required=True, help="cargo | go | terraform")
    parser.add_argument("--ours", required=True, type=Path, help="Our SBOM JSON file")
    parser.add_argument("--syft", type=Path, default=None, help="syft SBOM JSON file")
    parser.add_argument(
        "--msbom", type=Path, default=None, help="microsoft/sbom-tool SBOM JSON file"
    )
    parser.add_argument(
        "--format",
        default="spdx",
        choices=["spdx", "cyclonedx"],
        help="SBOM format to compare",
    )
    args = parser.parse_args()

    if not args.ours.exists():
        print(f"[compare] --ours file not found: {args.ours}", file=sys.stderr)
        sys.exit(1)

    ours = load_packages(args.ours, args.format, "ours")

    result = ComparisonResult(ecosystem=args.ecosystem)

    if args.syft is not None:
        if args.syft.exists():
            theirs = load_packages(args.syft, args.format, "syft")
            comp = diff_packages(ours, theirs, "syft", args.ecosystem, args.format)
            result.comparisons.append(comp)
        else:
            print(
                f"[compare] syft file not found, skipping: {args.syft}", file=sys.stderr
            )

    if args.msbom is not None:
        if args.msbom.exists():
            theirs = load_packages(args.msbom, args.format, "msbom")
            comp = diff_packages(ours, theirs, "msbom", args.ecosystem, args.format)
            result.comparisons.append(comp)
        else:
            print(
                f"[compare] msbom file not found, skipping: {args.msbom}",
                file=sys.stderr,
            )

    print(json.dumps(asdict(result), indent=2))


if __name__ == "__main__":
    main()
