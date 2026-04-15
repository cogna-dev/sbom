///|
/// # cogna-dev/sbom
///
/// Software Composition Analysis (SCA) library for generating Software Bill of
/// Materials (SBOM) in multiple formats.
///
/// ## Supported SBOM Formats
/// - **SPDX 2.3**: Standard format for software package data exchange
/// - **CycloneDX 1.5**: Lightweight SBOM standard designed for application security
///
/// ## Supported Project Types
/// - **Cargo (Rust)**: Parses Cargo.toml and Cargo.lock, supports workspaces
/// - **Go**: Parses go.mod and go.sum
/// - **Terraform**: Parses .terraform.lock.hcl and required_providers
///
/// ## Usage
///
/// ```moonbit
/// // Scan a Cargo project
/// let project = scan_cargo(
///   "my-project",
///   cargo_toml_content,
///   Some(lock_content),
/// )
///
/// // Export as SPDX
/// let sbom = project.to_sbom()
/// let spdx_json = @spdx.to_spdx(sbom)
///
/// // Or use the convenient scan function with virtual filesystem
/// let entries = @discovery.entries_from_map(files)
/// let result = scan_all("repo/", entries, None)
/// for item in result.projects {
///   println(item.project.name)
/// }
/// ```

// ============================================================================
// Re-exported types (public API)
// ============================================================================

// Key types are from @types, @discovery, etc.
// This lib package provides the high-level scanning API.

// ============================================================================
// Single-project scan API
// ============================================================================

///|
/// Scan a Cargo project given file contents.
///
/// # Parameters
/// - `root_path`: Path to the project root (used as name/path)
/// - `cargo_toml_content`: Content of Cargo.toml
/// - `lock_content`: Optional content of Cargo.lock
pub fn scan_cargo(
  root_path : String,
  cargo_toml_content : String,
  lock_content : String?,
) -> @types.Project {
  @cargo.parse_cargo_project(root_path, cargo_toml_content, lock_content)
}

///|
/// Scan a Terraform project given file contents.
///
/// # Parameters
/// - `root_path`: Path to the project root
/// - `tf_files`: Array of (filename, content) pairs for .tf files
/// - `lock_content`: Optional content of .terraform.lock.hcl
pub fn scan_terraform(
  root_path : String,
  tf_files : Array[(String, String)],
  lock_content : String?,
) -> @types.Project {
  @terraform.parse_terraform_project(root_path, tf_files, lock_content)
}

///|
/// Scan a Go module project given file contents.
///
/// # Parameters
/// - `root_path`: Path to the project root (used as fallback name)
/// - `go_mod_content`: Content of go.mod
/// - `go_sum_content`: Optional content of go.sum (provides checksums)
pub fn scan_go(
  root_path : String,
  go_mod_content : String,
  go_sum_content : String?,
) -> @types.Project {
  @go.parse_go_project(root_path, go_mod_content, go_sum_content)
}

///|
/// Detect the project type at a directory based on file presence.
///
/// Checks in order: Cargo.toml → package.json → go.mod → pyproject.toml/setup.py/requirements.txt → .terraform.lock.hcl → *.tf
pub fn detect_project_type(
  dir_path : String,
  file_names : Array[String],
) -> @types.ProjectType {
  for f in file_names {
    let name = basename(f)
    if name == "Cargo.toml" {
      return @types.ProjectType::Cargo
    }
  }
  for f in file_names {
    let name = basename(f)
    if name == "package.json" {
      return @types.ProjectType::Npm
    }
  }
  for f in file_names {
    let name = basename(f)
    if name == "go.mod" {
      return @types.ProjectType::Go
    }
  }
  for f in file_names {
    let name = basename(f)
    if name == "pyproject.toml" ||
      name == "setup.py" ||
      name == "requirements.txt" {
      return @types.ProjectType::Python
    }
  }
  for f in file_names {
    let name = basename(f)
    if name == ".terraform.lock.hcl" || name.has_suffix(".tf") {
      return @types.ProjectType::Terraform
    }
  }
  let _ = dir_path
  @types.ProjectType::Unknown
}

///|
/// Get the base name (last path component) from a path.
fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => path[idx + 1:].to_string()
    None => path
  }
}

// ============================================================================
// Multi-project scan API
// ============================================================================

///|
/// Result of scanning a single discovered project.
pub(all) struct ProjectScanResult {
  /// Path to the project root.
  path : String
  /// Detected project type.
  project_type : @types.ProjectType
  /// Whether this project is a workspace.
  is_workspace : Bool
  /// Project name (if detected).
  discovered_name : String?
  /// Parsed project with dependencies.
  project : @types.Project
  /// Generated SBOM.
  sbom : @types.Sbom
}

///|
/// Result of scanning all projects in a directory.
pub(all) struct MultiProjectScanResult {
  /// All successfully scanned projects.
  projects : Array[ProjectScanResult]
  /// Warnings for projects that could not be parsed.
  warnings : Array[String]
}

///|
/// Scan all independent projects in a virtual filesystem.
///
/// This function:
/// 1. Discovers all independent projects (not workspace members)
/// 2. Parses each project's dependencies
/// 3. Generates an SBOM for each
///
/// # Parameters
/// - `root`: Root path to search from
/// - `entries`: Virtual filesystem entries (use `@discovery.entries_from_map`)
/// - `options`: Optional discovery options (uses default if None)
///
/// # Returns
/// A `MultiProjectScanResult` with all parsed projects and their SBOMs.
pub fn scan_all(
  root : String,
  entries : Array[@discovery.FsEntry],
  options : @discovery.DiscoveryOptions?,
) -> MultiProjectScanResult {
  let opts = match options {
    Some(o) => o
    None => @discovery.DiscoveryOptions::default()
  }
  let discovered = @discovery.discover_projects(root, entries, opts)
  let projects : Array[ProjectScanResult] = []
  let warnings : Array[String] = []
  // Build a quick content lookup: path -> content
  let content_map : Map[String, String] = {}
  for entry in entries {
    match entry.content {
      Some(c) => content_map[entry.path] = c
      None => ()
    }
  }
  for disc in discovered {
    let result = parse_discovered_project(disc, entries, content_map)
    match result {
      Ok(scan_result) => projects.push(scan_result)
      Err(msg) =>
        warnings.push("Failed to scan project at \{disc.path}: \{msg}")
    }
  }
  { projects, warnings }
}

///|
/// Parse a single discovered project into a ProjectScanResult.
fn parse_discovered_project(
  disc : @discovery.DiscoveredProject,
  entries : Array[@discovery.FsEntry],
  content_map : Map[String, String],
) -> Result[ProjectScanResult, String] {
  let dir = disc.path
  let project_result : Result[@types.Project, String] = match
    disc.project_type {
    @types.ProjectType::Cargo => {
      let cargo_toml_path = "\{dir}/Cargo.toml"
      match content_map.get(cargo_toml_path) {
        None => Err("No Cargo.toml content available for \{dir}")
        Some(cargo_content) => {
          let lock_path = "\{dir}/Cargo.lock"
          let lock_content = content_map.get(lock_path)
          Ok(@cargo.parse_cargo_project(dir, cargo_content, lock_content))
        }
      }
    }
    @types.ProjectType::Terraform => {
      let lock_path = "\{dir}/.terraform.lock.hcl"
      let lock_content = content_map.get(lock_path)
      // Collect .tf file contents from virtual fs
      let tf_files : Array[(String, String)] = []
      for entry in entries {
        if !entry.is_dir &&
          entry.path.has_suffix(".tf") &&
          is_in_dir(entry.path, dir) {
          match entry.content {
            Some(c) => tf_files.push((entry.path, c))
            None => ()
          }
        }
      }
      Ok(@terraform.parse_terraform_project(dir, tf_files, lock_content))
    }
    @types.ProjectType::Go => {
      let go_mod_path = "\{dir}/go.mod"
      match content_map.get(go_mod_path) {
        None => Err("No go.mod content available for \{dir}")
        Some(go_mod_content) => {
          let go_sum_path = "\{dir}/go.sum"
          let go_sum_content = content_map.get(go_sum_path)
          Ok(@go.parse_go_project(dir, go_mod_content, go_sum_content))
        }
      }
    }
    _ => {
      // For unsupported project types, return an empty project
      let name = match disc.name {
        Some(n) => n
        None => basename_lib(dir)
      }
      Ok(@types.Project::new(name, "0.0.0", dir, disc.project_type))
    }
  }
  match project_result {
    Err(e) => Err(e)
    Ok(project) => {
      let sbom = project.to_sbom()
      Ok({
        path: disc.path,
        project_type: disc.project_type,
        is_workspace: disc.is_workspace,
        discovered_name: disc.name,
        project,
        sbom,
      })
    }
  }
}

///|
/// Check if a file path is directly inside a directory (not subdirectory).
fn is_in_dir(file_path : String, dir_path : String) -> Bool {
  let dir = if dir_path.has_suffix("/") { dir_path } else { "\{dir_path}/" }
  if !file_path.has_prefix(dir) {
    return false
  }
  let rel = file_path[dir.length():].to_string()
  // rel should not contain a slash (direct child only)
  !rel.contains("/")
}

///|
/// Get the base name (last component) of a path — lib-internal version.
fn basename_lib(path : String) -> String {
  let path = if path.has_suffix("/") && path.length() > 1 {
    path[0:path.length() - 1].to_string()
  } else {
    path
  }
  match path.rev_find("/") {
    Some(idx) => path[idx + 1:].to_string()
    None => path
  }
}

// ============================================================================
// SBOM export API
// ============================================================================

///|
/// Export an SBOM to SPDX 2.3 JSON format.
pub fn export_spdx(sbom : @types.Sbom) -> String {
  @spdx.to_spdx(sbom)
}

///|
/// Export an SBOM to CycloneDX 1.5 JSON format.
pub fn export_cyclonedx(sbom : @types.Sbom) -> String {
  @cyclonedx.to_cyclonedx(sbom)
}

///|
/// Export a project's SBOM to SPDX 2.3 JSON format.
pub fn project_to_spdx(project : @types.Project) -> String {
  @spdx.to_spdx(project.to_sbom())
}

///|
/// Export a project's SBOM to CycloneDX 1.5 JSON format.
pub fn project_to_cyclonedx(project : @types.Project) -> String {
  @cyclonedx.to_cyclonedx(project.to_sbom())
}
