///|
/// Minimal TOML parser for Cargo.toml files.
///
/// Parses only the sections relevant to SCA:
///   [package], [workspace], [dependencies], [dev-dependencies], [build-dependencies]
///
/// MoonBit has no native TOML library, so we implement a line-oriented parser
/// that handles the subset of TOML used in typical Cargo projects.

// ============================================================================
// TOML parsing helpers
// ============================================================================

///|
/// Strip inline comment from a TOML value.
fn strip_comment(s : String) -> String {
  let in_quote = Ref::new(false)
  let buf = StringBuilder::new()
  let chars = s.to_array()
  let i = Ref::new(0)
  while i.val < chars.length() {
    let ch = chars[i.val]
    if ch == '"' {
      in_quote.val = !in_quote.val
      buf.write_char(ch)
    } else if ch == '#' && !in_quote.val {
      break
    } else {
      buf.write_char(ch)
    }
    i.val = i.val + 1
  }
  buf.to_string().trim().to_string()
}

///|
/// Unquote a TOML string value (remove surrounding quotes).
fn unquote(s : String) -> String {
  let s = s.trim().to_string()
  if s.has_prefix("\"") && s.has_suffix("\"") && s.length() >= 2 {
    s[1:s.length() - 1].to_string()
  } else if s.has_prefix("'") && s.has_suffix("'") && s.length() >= 2 {
    s[1:s.length() - 1].to_string()
  } else {
    s
  }
}

///|
/// Parse a simple TOML inline table like `{ version = "1.0", features = [...] }`.
/// Returns a map of key -> raw value string.
fn parse_inline_table(s : String) -> Map[String, String] {
  let result : Map[String, String] = {}
  let s = s.trim().to_string()
  let inner = if s.has_prefix("{") && s.has_suffix("}") && s.length() >= 2 {
    s[1:s.length() - 1].to_string()
  } else {
    s
  }
  for part in inner.split(",") {
    let part = part.to_string().trim().to_string()
    match part.find("=") {
      Some(eq_pos) => {
        let key = part[0:eq_pos].to_string().trim().to_string()
        let val = part[eq_pos + 1:].to_string().trim().to_string()
        result[key] = unquote(val)
      }
      None => ()
    }
  }
  result
}

// ============================================================================
// Parsed representation
// ============================================================================

///|
priv struct CargoPackageSection {
  name : String
  version : String?
  description : String?
}

///|
priv struct CargoWorkspaceSection {
  members : Array[String]
}

///|
/// A parsed dependency entry from Cargo.toml.
priv enum CargoDep {
  /// Simple version string: `serde = "1.0"`
  Simple(String)
  /// Inline table: `tokio = { version = "1.0", features = ["full"] }`
  Table(Map[String, String])
}

///|
/// Sections parsed from Cargo.toml.
priv struct ParsedCargoToml {
  pkg : CargoPackageSection?
  workspace : CargoWorkspaceSection?
  deps : Map[String, CargoDep]
  dev_deps : Map[String, CargoDep]
  build_deps : Map[String, CargoDep]
}

// ============================================================================
// Parser state machine
// ============================================================================

///|
priv enum Section {
  PackageSection
  WorkspaceSection
  DepsSection
  DevDepsSection
  BuildDepsSection
  Other
}

///|
/// Parse Cargo.toml content into a ParsedCargoToml.
fn parse_cargo_toml(content : String) -> ParsedCargoToml {
  let section : Ref[Section] = Ref::new(Section::Other)
  let cur_pkg_name : Ref[String] = Ref::new("")
  let cur_pkg_version : Ref[String?] = Ref::new(None)
  let cur_pkg_description : Ref[String?] = Ref::new(None)
  let in_pkg_section = Ref::new(false)
  let ws_members : Array[String] = []
  let in_ws_section = Ref::new(false)
  let in_members_array = Ref::new(false)
  let members_buf : Ref[String] = Ref::new("")
  let final_pkg : Ref[CargoPackageSection?] = Ref::new(None)
  let final_ws : Ref[CargoWorkspaceSection?] = Ref::new(None)
  let deps : Map[String, CargoDep] = {}
  let dev_deps : Map[String, CargoDep] = {}
  let build_deps : Map[String, CargoDep] = {}

  fn flush_package() {
    if in_pkg_section.val && cur_pkg_name.val != "" {
      final_pkg.val = Some({
        name: cur_pkg_name.val,
        version: cur_pkg_version.val,
        description: cur_pkg_description.val,
      })
    }
  }

  fn flush_workspace() {
    if in_ws_section.val {
      final_ws.val = Some({ members: ws_members })
    }
  }

  for raw_line in content.split("\n") {
    let line = raw_line.to_string().trim().to_string()
    if !in_members_array.val {
      if line == "" || line.has_prefix("#") {
        continue
      }
    }
    if line.has_prefix("[") && !line.has_prefix("[[") {
      if in_members_array.val {
        in_members_array.val = false
        parse_toml_string_array(members_buf.val + line, ws_members)
        members_buf.val = ""
        continue
      }
      flush_package()
      flush_workspace()
      let header = strip_comment(line)
      let header = if header.has_prefix("[") && header.has_suffix("]") &&
        header.length() >= 2 {
        header[1:header.length() - 1].to_string().trim().to_string()
      } else {
        header
      }
      match header {
        "package" => {
          section.val = Section::PackageSection
          in_pkg_section.val = true
          cur_pkg_name.val = ""
          cur_pkg_version.val = None
          cur_pkg_description.val = None
        }
        "workspace" => {
          section.val = Section::WorkspaceSection
          in_ws_section.val = true
        }
        "dependencies" => section.val = Section::DepsSection
        "dev-dependencies" => section.val = Section::DevDepsSection
        "build-dependencies" => section.val = Section::BuildDepsSection
        _ => section.val = Section::Other
      }
      continue
    }
    match section.val {
      PackageSection => {
        match line.find("=") {
          Some(eq) => {
            let key = line[0:eq].to_string().trim().to_string()
            let val = unquote(strip_comment(line[eq + 1:].to_string()))
            match key {
              "name" => cur_pkg_name.val = val
              "version" => cur_pkg_version.val = Some(val)
              "description" => cur_pkg_description.val = Some(val)
              _ => ()
            }
          }
          None => ()
        }
      }
      WorkspaceSection => {
        if in_members_array.val {
          if line.contains("]") {
            in_members_array.val = false
            parse_toml_string_array(members_buf.val + line, ws_members)
            members_buf.val = ""
          } else {
            members_buf.val = members_buf.val + line + "\n"
          }
        } else {
          match line.find("=") {
            Some(eq) => {
              let key = line[0:eq].to_string().trim().to_string()
              let val_part = line[eq + 1:].to_string().trim().to_string()
              if key == "members" {
                if val_part.contains("[") && val_part.contains("]") {
                  parse_toml_string_array(val_part, ws_members)
                } else if val_part.contains("[") {
                  in_members_array.val = true
                  members_buf.val = val_part + "\n"
                }
              }
            }
            None => ()
          }
        }
      }
      DepsSection => parse_dep_line(line, deps)
      DevDepsSection => parse_dep_line(line, dev_deps)
      BuildDepsSection => parse_dep_line(line, build_deps)
      Other => ()
    }
  }
  flush_package()
  flush_workspace()
  { pkg: final_pkg.val, workspace: final_ws.val, deps, dev_deps, build_deps, }
}

///|
/// Parse a TOML array of strings like `["a", "b", "c/*"]` into an Array[String].
fn parse_toml_string_array(s : String, out : Array[String]) -> Unit {
  let inner = match s.find("[") {
    Some(start) =>
      match s.find("]") {
        Some(end) =>
          if end > start {
            s[start + 1:end].to_string()
          } else {
            s
          }
        None => s[start + 1:].to_string()
      }
    None => s
  }
  for part in inner.split(",") {
    let item = unquote(part.to_string().trim().to_string()).trim().to_string()
    if item != "" {
      out.push(item)
    }
  }
}

///|
/// Parse a single dependency line and insert into the given map.
fn parse_dep_line(line : String, deps : Map[String, CargoDep]) -> Unit {
  if line == "" || line.has_prefix("#") {
    return
  }
  match line.find("=") {
    None => ()
    Some(eq) => {
      let name = line[0:eq].to_string().trim().to_string()
      let val = strip_comment(line[eq + 1:].to_string()).trim().to_string()
      if val.has_prefix("{") {
        deps[name] = CargoDep::Table(parse_inline_table(val))
      } else {
        deps[name] = CargoDep::Simple(unquote(val))
      }
    }
  }
}

// ============================================================================
// Cargo.lock parser
// ============================================================================

///|
/// Parse Cargo.lock content and return a map of name -> (version, checksum?).
fn parse_cargo_lock(content : String) -> Map[String, (String, String?)] {
  let result : Map[String, (String, String?)] = {}
  let current_name : Ref[String] = Ref::new("")
  let current_version : Ref[String] = Ref::new("")
  let current_checksum : Ref[String?] = Ref::new(None)
  let in_package = Ref::new(false)

  for raw_line in content.split("\n") {
    let line = raw_line.to_string().trim().to_string()
    if line == "[[package]]" {
      if in_package.val && current_name.val != "" {
        result[current_name.val] = (current_version.val, current_checksum.val)
      }
      current_name.val = ""
      current_version.val = ""
      current_checksum.val = None
      in_package.val = true
      continue
    }
    if !in_package.val || line == "" || line.has_prefix("#") {
      continue
    }
    match line.find("=") {
      None => ()
      Some(eq) => {
        let key = line[0:eq].to_string().trim().to_string()
        let val = unquote(line[eq + 1:].to_string().trim().to_string())
        match key {
          "name" => current_name.val = val
          "version" => current_version.val = val
          "checksum" => current_checksum.val = Some(val)
          _ => ()
        }
      }
    }
  }
  if in_package.val && current_name.val != "" {
    result[current_name.val] = (current_version.val, current_checksum.val)
  }
  result
}

// ============================================================================
// Convert parsed data to types.Package
// ============================================================================

///|
fn dep_to_package(
  name : String,
  dep : CargoDep,
  group : @types.DependencyGroup,
  resolved : Map[String, (String, String?)]
) -> @types.Package {
  let actual_name : String = match dep {
    Table(tbl) =>
      match tbl.get("package") {
        Some(pkg_name) => pkg_name
        None => name
      }
    Simple(_) => name
  }
  let version_req : String? = match dep {
    Simple(ver) => Some(ver)
    Table(tbl) => tbl.get("version")
  }
  let source : @types.DependencySource = match dep {
    Simple(_) => @types.DependencySource::Registry(Some("https://crates.io"))
    Table(tbl) =>
      if tbl.contains("git") {
        let url = match tbl.get("git") {
          Some(u) => u
          None => ""
        }
        let ref_type : String? = if tbl.contains("tag") {
          Some("tag")
        } else if tbl.contains("branch") {
          Some("branch")
        } else if tbl.contains("rev") {
          Some("rev")
        } else {
          None
        }
        let ref_value : String? = match ref_type {
          Some(rt) => tbl.get(rt)
          None => None
        }
        @types.DependencySource::Git(url, ref_type, ref_value)
      } else if tbl.contains("path") {
        let path = match tbl.get("path") {
          Some(p) => p
          None => "."
        }
        @types.DependencySource::Path(path)
      } else {
        @types.DependencySource::Registry(Some("https://crates.io"))
      }
  }
  let effective_group : @types.DependencyGroup = match dep {
    Table(tbl) =>
      match tbl.get("optional") {
        Some("true") => @types.DependencyGroup::Optional
        _ => group
      }
    Simple(_) => group
  }
  let pkg = @types.Package::new(actual_name, "cargo")
  let pkg = { ..pkg, group: effective_group, source, }
  let pkg = match version_req {
    Some(req_str) =>
      match @version.VersionRequirement::parse(req_str) {
        Some(req) => { ..pkg, requirement: Some(req) }
        None => pkg
      }
    None => pkg
  }
  match resolved.get(actual_name) {
    Some((ver_str, checksum)) => {
      let pkg = match @version.Version::parse(ver_str) {
        Some(v) => { ..pkg, resolved_version: Some(v) }
        None => pkg
      }
      match checksum {
        Some(cs) => { ..pkg, checksum: Some(cs) }
        None => pkg
      }
    }
    None => pkg
  }
}

// ============================================================================
// Public API
// ============================================================================

///|
/// Parse Cargo.toml (and optional Cargo.lock) content into a Project.
pub fn parse_cargo_project(
  root_path : String,
  cargo_toml_content : String,
  lock_content : String?
) -> @types.Project {
  let parsed = parse_cargo_toml(cargo_toml_content)
  let resolved : Map[String, (String, String?)] = match lock_content {
    Some(lock_str) => parse_cargo_lock(lock_str)
    None => {}
  }
  let project_name = match parsed.pkg {
    Some(p) => p.name
    None => dir_name(root_path)
  }
  let project_version = match parsed.pkg {
    Some(p) =>
      match p.version {
        Some(v) => v
        None => "0.0.0"
      }
    None => "0.0.0"
  }
  let project = @types.Project::new(
    project_name,
    project_version,
    root_path,
    @types.ProjectType::Cargo,
  )
  match parsed.pkg {
    Some(p) =>
      match p.description {
        Some(desc) => project.description = Some(desc)
        None => ()
      }
    None => ()
  }
  match parsed.workspace {
    Some(_) => ()
    None => {
      let subproject = @types.SubProject::new(
        project_name,
        root_path,
        @types.ProjectType::Cargo,
      )
      subproject.version = Some(project_version)
      for name, dep in parsed.deps {
        subproject.add_package(
          dep_to_package(name, dep, @types.DependencyGroup::Runtime, resolved),
        )
      }
      for name, dep in parsed.dev_deps {
        subproject.add_package(
          dep_to_package(name, dep, @types.DependencyGroup::Dev, resolved),
        )
      }
      for name, dep in parsed.build_deps {
        subproject.add_package(
          dep_to_package(name, dep, @types.DependencyGroup::Build, resolved),
        )
      }
      project.add_subproject(subproject)
    }
  }
  project
}

///|
/// Parse a workspace member's Cargo.toml into a SubProject.
pub fn parse_cargo_member(
  member_path : String,
  cargo_toml_content : String,
  resolved : Map[String, (String, String?)]
) -> @types.SubProject? {
  let parsed = parse_cargo_toml(cargo_toml_content)
  match parsed.pkg {
    None => None
    Some(p) => {
      let subproject = @types.SubProject::new(
        p.name,
        member_path,
        @types.ProjectType::Cargo,
      )
      subproject.version = p.version
      match p.description {
        Some(desc) => subproject.description = Some(desc)
        None => ()
      }
      for name, dep in parsed.deps {
        subproject.add_package(
          dep_to_package(name, dep, @types.DependencyGroup::Runtime, resolved),
        )
      }
      for name, dep in parsed.dev_deps {
        subproject.add_package(
          dep_to_package(name, dep, @types.DependencyGroup::Dev, resolved),
        )
      }
      for name, dep in parsed.build_deps {
        subproject.add_package(
          dep_to_package(name, dep, @types.DependencyGroup::Build, resolved),
        )
      }
      Some(subproject)
    }
  }
}

///|
/// Get workspace member glob patterns from Cargo.toml content.
pub fn get_workspace_members(cargo_toml_content : String) -> Array[String] {
  match parse_cargo_toml(cargo_toml_content).workspace {
    Some(ws) => ws.members
    None => []
  }
}

///|
/// Parse Cargo.lock content into a resolved versions map.
pub fn parse_lock_file(
  lock_content : String
) -> Map[String, (String, String?)] {
  parse_cargo_lock(lock_content)
}

///|
/// Return the last path component (directory name) from a path string.
fn dir_name(path : String) -> String {
  let path = path.trim().to_string()
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
