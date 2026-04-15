```
 ███████╗██████╗  ██████╗ ███╗   ███╗
 ██╔════╝██╔══██╗██╔═══██╗████╗ ████║
 ███████╗██████╔╝██║   ██║██╔████╔██║
 ╚════██║██╔══██╗██║   ██║██║╚██╔╝██║
 ███████║██████╔╝╚██████╔╝██║ ╚═╝ ██║
 ╚══════╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝

 Software Bill of Materials · MoonBit
```

[![MoonBit](https://img.shields.io/badge/language-MoonBit-blueviolet?logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48Y2lyY2xlIGN4PSIxMiIgY3k9IjEyIiByPSIxMiIgZmlsbD0iIzZCNDZDMSIvPjwvc3ZnPg==)](https://www.moonbitlang.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![moon check](https://img.shields.io/badge/moon%20check-passing-brightgreen)](https://www.moonbitlang.com/docs/build-system-tutorial)
[![SPDX 2.3](https://img.shields.io/badge/SPDX-2.3-blue)](https://spdx.github.io/spdx-spec/v2.3/)
[![CycloneDX 1.5](https://img.shields.io/badge/CycloneDX-1.5-orange)](https://cyclonedx.org/specification/overview/)
[![PURL](https://img.shields.io/badge/PURL-spec-lightgrey)](https://github.com/package-url/purl-spec)

> **`cogna-dev/sbom`** — A pure-MoonBit Software Composition Analysis (SCA) library that parses dependency manifests and lock files to produce industry-standard Software Bills of Materials in **SPDX 2.3** and **CycloneDX 1.5** JSON formats.

---

## ✨ Features

| Feature | Details |
|---------|---------|
| 🦀 **Cargo / Rust** | Parses `Cargo.toml` (workspace + single-crate) and `Cargo.lock` |
| 🏗️ **Terraform / HCL** | Parses `.tf` provider blocks and `.terraform.lock.hcl` |
| 📄 **SPDX 2.3** | Full JSON export with packages, relationships, document info |
| 🔄 **CycloneDX 1.5** | Full JSON export with components, metadata, BOM serial |
| 🔍 **Auto-discovery** | Virtual-FS BFS traversal with glob matching & workspace exclusion |
| 🔒 **Pure MoonBit** | Zero external dependencies — hand-rolled TOML/HCL parsers |
| 🧮 **SemVer engine** | `^`, `~`, `>=`, `<=`, `>`, `<`, `=`, `*` constraint matching |
| 🪪 **PURL support** | Generates Package URLs for every detected dependency |
| 🏗️ **Monorepo-aware** | Discovers and deduplicates workspace members automatically |

---

## 📦 Package Architecture

```
cogna-dev/sbom
└── src/
    ├── version/          # SemVer parsing & constraint matching
    ├── types/            # Core domain types (Package, Project, Sbom…)
    ├── formats/
    │   ├── spdx/         # SPDX 2.3 JSON exporter
    │   └── cyclonedx/    # CycloneDX 1.5 JSON exporter
    ├── packages/
    │   ├── cargo/        # Cargo.toml + Cargo.lock parser
    │   └── terraform/    # .tf + .terraform.lock.hcl parser
    ├── discovery/        # VFS-based project discovery engine
    └── lib/              # Top-level public API
```

### Dependency Graph

```
         lib
        / | \
       /  |  \
 cargo  terra  discovery
   \     |      /
    \    |     /
      types  version
        |
      formats
      /     \
   spdx  cyclonedx
```

---

## 🚀 Getting Started

### Add to your `moon.mod.json`

```json
{
  "deps": {
    "cogna-dev/sbom": "0.1.0"
  }
}
```

### Add to your package's `moon.pkg.json`

```json
{
  "import": [
    "cogna-dev/sbom/src/lib"
  ]
}
```

### Basic Usage

```moonbit
// Scan a Cargo workspace from a virtual filesystem
let files : Map[String, String] = ...  // path -> file content
let result = @lib.scan_cargo(files)

match result {
  Ok(project) => {
    // Export as SPDX 2.3 JSON
    let spdx_json = @lib.export_spdx(project)
    // Export as CycloneDX 1.5 JSON
    let cdx_json  = @lib.export_cyclonedx(project)
  }
  Err(e) => println("Scan failed: \{e}")
}
```

---

## 📚 Package Reference

### `src/version` — SemVer Engine

Parses semantic versions and evaluates version constraints without any external library.

```moonbit
let v = @version.parse_version("1.2.3-alpha.1")!
// Version { major: 1, minor: 2, patch: 3, pre: Some("alpha.1") }

let req = @version.parse_requirement("^1.2")!
let matches = @version.satisfies(v, req)   // true
```

**Supported constraint operators:**

| Operator | Meaning |
|----------|---------|
| `^1.2.3` | Compatible — `>=1.2.3, <2.0.0` |
| `~1.2.3` | Patch-compatible — `>=1.2.3, <1.3.0` |
| `>=1.0`  | Greater-or-equal |
| `>1.0`   | Strictly greater |
| `<=2.0`  | Less-or-equal |
| `<2.0`   | Strictly less |
| `=1.2.3` | Exact match |
| `*`      | Any version |

---

### `src/types` — Domain Model

All core types live here. Every other package imports from `types`.

```moonbit
// A resolved dependency
pub struct Package {
  name        : String
  version     : String
  purl        : String        // e.g. "pkg:cargo/serde@1.0.195"
  license     : String?
  description : String?
  source      : DependencySource
  group       : DependencyGroup
}

// A scanned sub-project (e.g. a single Cargo crate)
pub struct SubProject {
  name         : String
  version      : String
  pkg_type     : ProjectType   // Cargo | Terraform | Npm | …
  manifest     : String        // path to manifest file
  dependencies : Array[Package]
}

// A root project containing sub-projects
pub struct Project {
  name         : String
  version      : String
  sub_projects : Array[SubProject]
}
```

---

### `src/packages/cargo` — Cargo Parser

Parses `Cargo.toml` (including workspace manifests) and `Cargo.lock` v3.

```moonbit
// Provide a virtual filesystem: Map[String, String]
let project = @cargo.parse(files)!

// project.sub_projects has one entry per crate discovered
// Each entry contains resolved packages from Cargo.lock
```

**Handles:**
- Workspace `[workspace.members]` glob patterns
- `[package]` + `[dependencies]` / `[dev-dependencies]` / `[build-dependencies]`
- `Cargo.lock` `[[package]]` entries with checksum & source
- Path, git, and registry dependencies

---

### `src/packages/terraform` — Terraform Parser

Parses Terraform `.tf` files and `.terraform.lock.hcl` provider lock files.

```moonbit
let project = @terraform.parse(files)!

// Discovers terraform { required_providers { … } } blocks
// Cross-references with .terraform.lock.hcl for resolved versions
```

**Handles:**
- `terraform { required_providers { name = { source = "…", version = "…" } } }`
- `.terraform.lock.hcl` `provider "…" { version = "…" }` blocks
- Multiple `.tf` files in the same directory

---

### `src/formats/spdx` — SPDX 2.3 Exporter

Produces a spec-compliant SPDX 2.3 document as a MoonBit `Json` value.

```moonbit
let json : Json = @spdx.to_spdx(project)
// Serialise with standard MoonBit JSON utilities
```

**Output structure:**
```json
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "my-project-1.0.0",
  "documentNamespace": "https://spdx.org/spdxdocs/...",
  "packages": [ ... ],
  "relationships": [ ... ]
}
```

---

### `src/formats/cyclonedx` — CycloneDX 1.5 Exporter

Produces a spec-compliant CycloneDX 1.5 BOM as a MoonBit `Json` value.

```moonbit
let json : Json = @cyclonedx.to_cyclonedx(project)
```

**Output structure:**
```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "serialNumber": "urn:uuid:...",
  "version": 1,
  "metadata": { "component": { ... } },
  "components": [ ... ]
}
```

---

### `src/discovery` — Project Discovery Engine

Traverses a virtual filesystem (BFS) to locate manifest files and group them into projects.

```moonbit
// VirtualFS is just Map[String, String]
let sub_projects = @discovery.discover(files)

// Returns an Array[DiscoveredProject] with:
//   .manifest_path  — path to the root manifest
//   .ecosystem      — Cargo | Terraform | …
//   .files          — scoped file map for this project
```

**Features:**
- Glob pattern matching for workspace members
- Skips `.git/`, `node_modules/`, `vendor/` automatically
- Deduplicates paths already claimed by a parent workspace

---

### `src/lib` — Top-Level API

The single entry point for consumers. Combines discovery + parsing + export.

```moonbit
// ── Scanning ──────────────────────────────────────────────────────────

// Scan only Cargo projects
let p1 : Result[Project, String] = @lib.scan_cargo(files)

// Scan only Terraform projects
let p2 : Result[Project, String] = @lib.scan_terraform(files)

// Scan everything (auto-detects ecosystem)
let p3 : Result[Project, String] = @lib.scan_all(files)

// ── Export ────────────────────────────────────────────────────────────

// Produce SPDX 2.3 JSON string
let spdx : String = @lib.export_spdx(project)

// Produce CycloneDX 1.5 JSON string
let cdx  : String = @lib.export_cyclonedx(project)
```

---

## 🏛️ Design Principles

| Principle | Implementation |
|-----------|---------------|
| **No I/O** | All functions accept `Map[String, String]` (virtual FS) — callers own I/O |
| **No external deps** | Hand-rolled TOML and HCL parsers; zero `moon.mod.json` deps |
| **Immutable-first** | Structs are built once and never mutated |
| **Zero type suppression** | No `as Any`, no `@ts-ignore` equivalent — strict types throughout |
| **Fail-fast errors** | Parsers return `Result[T, String]!` — errors propagate, never silenced |
| **Pure functions** | All parsers are deterministic given the same input map |

---

## 🗺️ Roadmap

| Ecosystem | Status |
|-----------|--------|
| 🦀 Cargo (Rust) | ✅ Implemented |
| 🏗️ Terraform | ✅ Implemented |
| 📦 npm / package.json | 🔜 Planned |
| 🐍 Python / pyproject.toml | 🔜 Planned |
| 🐹 Go / go.mod | 🔜 Planned |
| ☕ Maven / pom.xml | 🔜 Planned |
| 💎 Bundler / Gemfile | 🔜 Planned |
| 🧪 SBOM merge / diff | 🔜 Planned |

---

## 🤝 Contributing

1. **Fork** the repository and create a feature branch.
2. Run `moon check` — **0 errors required** before opening a PR.
3. Follow the existing coding style (no `as Any`, no empty catches).
4. Add or update tests with `moon test`.
5. Open a PR with a clear description of what changed and why.

```bash
# Clone
git clone https://github.com/cogna-dev/sbom
cd sbom

# Check everything compiles
moon check

# Run tests
moon test

# Build
moon build
```

---

## 📄 License

MIT © cogna-dev — see [LICENSE](LICENSE) for details.

> Built with ❤️ in [MoonBit](https://www.moonbitlang.com)
