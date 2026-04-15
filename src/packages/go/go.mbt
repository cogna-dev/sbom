///|
/// Minimal Go module parser.
///
/// Parses only the sections relevant to SCA:
///   - go.mod: module path, Go version, require directives
///   - go.sum: module checksums
///
/// MoonBit has no native Go module library, so we implement a line-oriented
/// parser that handles the subset of go.mod/go.sum used in typical Go projects.

// ============================================================================
// Parsing helpers
// ============================================================================

///|
/// Strip an inline comment from a Go line (everything from `//` onward).
fn strip_go_comment(s : String) -> String {
  let in_quote = Ref::new(false)
  let buf = StringBuilder::new()
  let chars = s.to_array()
  let i = Ref::new(0)
  while i.val < chars.length() {
    let ch = chars[i.val]
    if ch == '"' {
      in_quote.val = !in_quote.val
      buf.write_char(ch)
    } else if ch == '/' &&
      !in_quote.val &&
      i.val + 1 < chars.length() &&
      chars[i.val + 1] == '/' {
      break
    } else {
      buf.write_char(ch)
    }
    i.val = i.val + 1
  }
  buf.to_string().trim().to_string()
}

///|
/// Unquote a Go string value (remove surrounding double quotes).
fn go_unquote(s : String) -> String {
  let s = s.trim().to_string()
  if s.has_prefix("\"") && s.has_suffix("\"") && s.length() >= 2 {
    s[1:s.length() - 1].to_string()
  } else {
    s
  }
}

///|
/// Split a line on whitespace and return non-empty tokens.
fn split_whitespace(s : String) -> Array[String] {
  let result : Array[String] = []
  for token in s.split(" ") {
    let t = token.to_string().trim().to_string()
    if t != "" {
      result.push(t)
    }
  }
  result
}

// ============================================================================
// Parsed representations
// ============================================================================

///|
/// A single require entry from go.mod.
priv struct GoRequire {
  module_path : String
  version : String
  indirect : Bool
}

///|
/// Parsed go.mod file.
priv struct ParsedGoMod {
  module_path : String?
  go_version : String?
  requires : Array[GoRequire]
}

// ============================================================================
// go.mod parser
// ============================================================================

///|
/// Parse go.mod content into a ParsedGoMod.
fn parse_go_mod(content : String) -> ParsedGoMod {
  let module_path : Ref[String?] = Ref::new(None)
  let go_version : Ref[String?] = Ref::new(None)
  let requires : Array[GoRequire] = []
  let in_require_block = Ref::new(false)
  for raw_line in content.split("\n") {
    let line = raw_line.to_string().trim().to_string()
    if line == "" || line.has_prefix("//") {
      continue
    }
    if in_require_block.val {
      if line.has_prefix(")") {
        in_require_block.val = false
        continue
      }
      // Parse: <module> <version> [// indirect]
      let is_indirect = line.contains("// indirect")
      let clean = strip_go_comment(line)
      let tokens = split_whitespace(clean)
      if tokens.length() >= 2 {
        requires.push({
          module_path: tokens[0],
          version: tokens[1],
          indirect: is_indirect,
        })
      }
      continue
    }
    if line.has_prefix("module ") {
      let rest = line[7:].to_string()
      module_path.val = Some(go_unquote(strip_go_comment(rest)))
    } else if line.has_prefix("go ") {
      let rest = line[3:].to_string()
      go_version.val = Some(strip_go_comment(rest))
    } else if line == "require (" {
      in_require_block.val = true
    } else if line.has_prefix("require ") {
      let rest = line[8:].to_string().trim().to_string()
      if rest.has_prefix("(") {
        in_require_block.val = true
      } else {
        // Single-line: require <module> <version>
        let is_indirect = rest.contains("// indirect")
        let clean = strip_go_comment(rest)
        let tokens = split_whitespace(clean)
        if tokens.length() >= 2 {
          requires.push({
            module_path: tokens[0],
            version: tokens[1],
            indirect: is_indirect,
          })
        }
      }
    }
  }
  { module_path: module_path.val, go_version: go_version.val, requires }
}

// ============================================================================
// go.sum parser
// ============================================================================

///|
/// Parse go.sum content and return a map of "module@version" -> h1: hash.
///
/// go.sum format (one entry per line):
///   <module> <version> <hash>
///   <module> <version>/go.mod <hash>
///
/// We keep only the source-tree entry (without `/go.mod` suffix) and prefer
/// the h1: hash algorithm.
fn parse_go_sum(content : String) -> Map[String, String] {
  let result : Map[String, String] = {}
  for raw_line in content.split("\n") {
    let line = raw_line.to_string().trim().to_string()
    if line == "" || line.has_prefix("//") {
      continue
    }
    let tokens = split_whitespace(line)
    if tokens.length() < 3 {
      continue
    }
    let module_path = tokens[0]
    let version = tokens[1]
    let hash = tokens[2]
    // Skip go.mod-only hash entries
    if version.has_suffix("/go.mod") {
      continue
    }
    let key = "\{module_path}@\{version}"
    // Prefer h1: hashes; don't overwrite an existing entry
    if !result.contains(key) && hash.has_prefix("h1:") {
      result[key] = hash
    }
  }
  result
}

// ============================================================================
// Helpers
// ============================================================================

///|
/// Split a Go module path into (namespace, name).
///
/// Examples:
///   "github.com/google/uuid"  → (Some("github.com/google"), "uuid")
///   "golang.org/x/text"       → (Some("golang.org/x"), "text")
///   "gopkg.in/yaml.v3"        → (None, "gopkg.in/yaml.v3")
fn split_module_path(module_path : String) -> (String?, String) {
  match module_path.rev_find("/") {
    None => (None, module_path)
    Some(idx) => {
      let ns = module_path[0:idx].to_string()
      let name = module_path[idx + 1:].to_string()
      if ns == "" {
        (None, name)
      } else {
        (Some(ns), name)
      }
    }
  }
}

///|
/// Derive a human-readable project name from the module path or root path.
fn project_name_from_module(
  module_path : String?,
  root_path : String,
) -> String {
  match module_path {
    Some(mp) => {
      let (_, name) = split_module_path(mp)
      name
    }
    None =>
      match root_path.rev_find("/") {
        Some(idx) => root_path[idx + 1:].to_string()
        None => root_path
      }
  }
}

///|
/// Convert a GoRequire entry to a Package.
fn require_to_package(
  req : GoRequire,
  checksums : Map[String, String],
) -> @types.Package {
  let (ns, name) = split_module_path(req.module_path)
  let pkg = @types.Package::new(name, "golang")
  let pkg = match ns {
    Some(n) => { ..pkg, ns: Some(n) }
    None => pkg
  }
  let pkg = {
    ..pkg,
    source: @types.DependencySource::Registry(
      Some("https://pkg.go.dev"),
    ),
  }
  // Resolve the version (Go versions always start with "v")
  let pkg = match @version.Version::parse(req.version) {
    Some(v) => { ..pkg, resolved_version: Some(v) }
    None => pkg
  }
  // Attach checksum from go.sum when available
  let checksum_key = "\{req.module_path}@\{req.version}"
  let pkg = match checksums.get(checksum_key) {
    Some(cs) => { ..pkg, checksum: Some(cs) }
    None => pkg
  }
  pkg
}

// ============================================================================
// Public API
// ============================================================================

///|
/// Parse a Go module project from go.mod (and optional go.sum) content.
///
/// # Parameters
/// - `root_path`: Filesystem path to the project root (used as fallback name)
/// - `go_mod_content`: Content of the go.mod file
/// - `go_sum_content`: Optional content of go.sum (provides checksums)
///
/// # Returns
/// A `Project` with all direct and indirect dependencies as packages.
pub fn parse_go_project(
  root_path : String,
  go_mod_content : String,
  go_sum_content : String?,
) -> @types.Project {
  let parsed = parse_go_mod(go_mod_content)
  let checksums : Map[String, String] = match go_sum_content {
    Some(sum_content) => parse_go_sum(sum_content)
    None => {}
  }
  let project_name = project_name_from_module(parsed.module_path, root_path)
  let go_version = match parsed.go_version {
    Some(v) => v
    None => "0.0.0"
  }
  let project = @types.Project::new(
    project_name,
    go_version,
    root_path,
    @types.ProjectType::Go,
  )
  let subproject = @types.SubProject::new(
    project_name,
    root_path,
    @types.ProjectType::Go,
  )
  for req in parsed.requires {
    subproject.add_package(require_to_package(req, checksums))
  }
  project.add_subproject(subproject)
  project
}

///|
/// Parse a go.mod file and return the list of module requirements.
///
/// Useful for inspecting individual requirements without creating a Project.
pub fn parse_go_mod_requires(
  content : String,
) -> Array[(String, String, Bool)] {
  let parsed = parse_go_mod(content)
  let result : Array[(String, String, Bool)] = []
  for req in parsed.requires {
    result.push((req.module_path, req.version, req.indirect))
  }
  result
}
