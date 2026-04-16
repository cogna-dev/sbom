# SBOM Tool Comparison Report

> Auto-generated on **2026-04-16 10:37 UTC** by `scripts/generate_readme.py`.
> Re-run `scripts/generate_report.sh` to refresh.

## Summary

| Ecosystem | Tool | Format | Ours | Theirs | Matched | Missing | Extra |
|-----------|------|--------|------|--------|---------|---------|-------|
| 🦀 `cargo` | [syft](https://github.com/anchore/syft) | `SPDX` | 11 | 12 | 11 | 1 | 0 |
| 🦀 `cargo` | [microsoft/sbom-tool](https://github.com/microsoft/sbom-tool) | `SPDX` | 11 | 11 | 10 | 1 | 1 |
| 🦀 `cargo` | [syft](https://github.com/anchore/syft) | `CYCLONEDX` | 10 | 12 | 10 | 2 | 0 |
| 🐹 `go` | [syft](https://github.com/anchore/syft) | `SPDX` | 28 | 28 | 27 | 1 | 1 |
| 🐹 `go` | [microsoft/sbom-tool](https://github.com/microsoft/sbom-tool) | `SPDX` | 28 | 28 | 27 | 1 | 1 |
| 🐹 `go` | [syft](https://github.com/anchore/syft) | `CYCLONEDX` | 27 | 28 | 27 | 1 | 0 |
| 🏗️ `terraform` | [syft](https://github.com/anchore/syft) | `SPDX` | 4 | 4 | 3 | 1 | 1 |
| 🏗️ `terraform` | [microsoft/sbom-tool](https://github.com/microsoft/sbom-tool) | `SPDX` | 4 | 1 | 0 | 1 | 4 |
| 🏗️ `terraform` | [syft](https://github.com/anchore/syft) | `CYCLONEDX` | 3 | 4 | 3 | 1 | 0 |

## Legend

| Symbol | Meaning |
|--------|---------|
| 🔵 `only-ours` | Package present in our output but not in the reference tool |
| 🔴 `missing` | Package present in reference tool but absent from our output |
| 🟡 `version-mismatch` | Same package, different resolved version |
| 🟠 `purl-diff` | Same package, different PURL string format |
| ⚪ `no-license` | Package has no license info (expected — we only read manifests, not registries) |

> **Note on known gaps:**
> - License data: syft queries registries; we only extract from manifests.
> - Terraform: microsoft/sbom-tool does not support Terraform providers.
> - Timestamps: `created` / `serialNumber` fields are excluded from comparison.

---

## Detailed Results

### 🦀 `cargo`

#### vs [syft](https://github.com/anchore/syft) · `SPDX`

| Metric | Value |
|--------|-------|
| Our packages | 11 |
| syft packages | 12 |
| Exact matches | 11 (100%) |
| 🔵 Only in ours | 0 |
| 🔴 Missing (only in syft) | 1 |
| 🟡 Version mismatches | 0 |
| 🟠 PURL diffs | 0 |

<details>
<summary>🔴 Packages missing from our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `/home/runner/work/sbom/sbom/tests/fixtures/cargo` | `unknown` | `–` |

</details>

#### vs [microsoft/sbom-tool](https://github.com/microsoft/sbom-tool) · `SPDX`

| Metric | Value |
|--------|-------|
| Our packages | 11 |
| msbom packages | 11 |
| Exact matches | 10 (91%) |
| 🔵 Only in ours | 1 |
| 🔴 Missing (only in msbom) | 1 |
| 🟡 Version mismatches | 0 |
| 🟠 PURL diffs | 0 |

<details>
<summary>🔵 Packages only in our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `sample-app` | `0.3.0` | `–` |

</details>

<details>
<summary>🔴 Packages missing from our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `sample-cargo` | `0.1.0` | `pkg:swid/cogna-dev/cogna-dev.github.io/sample-cargo@0.1.0?tag_id=df66f600-9e94-47cf-b24c-e555015ac4bf` |

</details>

#### vs [syft](https://github.com/anchore/syft) · `CYCLONEDX`

| Metric | Value |
|--------|-------|
| Our packages | 10 |
| syft packages | 12 |
| Exact matches | 10 (100%) |
| 🔵 Only in ours | 0 |
| 🔴 Missing (only in syft) | 2 |
| 🟡 Version mismatches | 0 |
| 🟠 PURL diffs | 0 |

<details>
<summary>🔴 Packages missing from our output (2)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `/home/runner/work/sbom/sbom/tests/fixtures/cargo/Cargo.lock` | `unknown` | `–` |
| `sample-app` | `0.3.0` | `pkg:cargo/sample-app@0.3.0` |

</details>


### 🐹 `go`

#### vs [syft](https://github.com/anchore/syft) · `SPDX`

| Metric | Value |
|--------|-------|
| Our packages | 28 |
| syft packages | 28 |
| Exact matches | 27 (96%) |
| 🔵 Only in ours | 1 |
| 🔴 Missing (only in syft) | 1 |
| 🟡 Version mismatches | 0 |
| 🟠 PURL diffs | 0 |

<details>
<summary>🔵 Packages only in our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `sample-go-app` | `1.21` | `–` |

</details>

<details>
<summary>🔴 Packages missing from our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `/home/runner/work/sbom/sbom/tests/fixtures/go` | `unknown` | `–` |

</details>

#### vs [microsoft/sbom-tool](https://github.com/microsoft/sbom-tool) · `SPDX`

| Metric | Value |
|--------|-------|
| Our packages | 28 |
| msbom packages | 28 |
| Exact matches | 27 (96%) |
| 🔵 Only in ours | 1 |
| 🔴 Missing (only in msbom) | 1 |
| 🟡 Version mismatches | 0 |
| 🟠 PURL diffs | 0 |

<details>
<summary>🔵 Packages only in our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `sample-go-app` | `1.21` | `–` |

</details>

<details>
<summary>🔴 Packages missing from our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `sample-go` | `0.1.0` | `pkg:swid/cogna-dev/cogna-dev.github.io/sample-go@0.1.0?tag_id=eadc6fce-8c30-44ca-845a-fb15c1f59256` |

</details>

#### vs [syft](https://github.com/anchore/syft) · `CYCLONEDX`

| Metric | Value |
|--------|-------|
| Our packages | 27 |
| syft packages | 28 |
| Exact matches | 27 (100%) |
| 🔵 Only in ours | 0 |
| 🔴 Missing (only in syft) | 1 |
| 🟡 Version mismatches | 0 |
| 🟠 PURL diffs | 0 |

<details>
<summary>🔴 Packages missing from our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `/home/runner/work/sbom/sbom/tests/fixtures/go/go.mod` | `unknown` | `–` |

</details>


### 🏗️ `terraform`

#### vs [syft](https://github.com/anchore/syft) · `SPDX`

| Metric | Value |
|--------|-------|
| Our packages | 4 |
| syft packages | 4 |
| Exact matches | 3 (75%) |
| 🔵 Only in ours | 1 |
| 🔴 Missing (only in syft) | 1 |
| 🟡 Version mismatches | 0 |
| 🟠 PURL diffs | 0 |

<details>
<summary>🔵 Packages only in our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `.` | `0.0.0` | `–` |

</details>

<details>
<summary>🔴 Packages missing from our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `/home/runner/work/sbom/sbom/tests/fixtures/terraform` | `unknown` | `–` |

</details>

#### vs [microsoft/sbom-tool](https://github.com/microsoft/sbom-tool) · `SPDX`

| Metric | Value |
|--------|-------|
| Our packages | 4 |
| msbom packages | 1 |
| Exact matches | 0 (0%) |
| 🔵 Only in ours | 4 |
| 🔴 Missing (only in msbom) | 1 |
| 🟡 Version mismatches | 0 |
| 🟠 PURL diffs | 0 |

<details>
<summary>🔵 Packages only in our output (4)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `.` | `0.0.0` | `–` |
| `aws` | `5.31.0` | `pkg:terraform/hashicorp/aws@5.31.0` |
| `random` | `3.6.0` | `pkg:terraform/hashicorp/random@3.6.0` |
| `tls` | `4.0.5` | `pkg:terraform/hashicorp/tls@4.0.5` |

</details>

<details>
<summary>🔴 Packages missing from our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `sample-terraform` | `0.1.0` | `pkg:swid/cogna-dev/cogna-dev.github.io/sample-terraform@0.1.0?tag_id=ea3c8b80-4388-44cd-8e1a-b7038299ab25` |

</details>

#### vs [syft](https://github.com/anchore/syft) · `CYCLONEDX`

| Metric | Value |
|--------|-------|
| Our packages | 3 |
| syft packages | 4 |
| Exact matches | 3 (100%) |
| 🔵 Only in ours | 0 |
| 🔴 Missing (only in syft) | 1 |
| 🟡 Version mismatches | 0 |
| 🟠 PURL diffs | 0 |

<details>
<summary>🔴 Packages missing from our output (1)</summary>

| Package | Version | PURL |
|---------|---------|------|
| `/home/runner/work/sbom/sbom/tests/fixtures/terraform/.terraform.lock.hcl` | `unknown` | `–` |

</details>

