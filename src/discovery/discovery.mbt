///|
/// Multi-project discovery for repositories.
///
/// Since MoonBit has no stdlib filesystem API, discovery works on a virtual
/// filesystem: the caller provides a list of (path, is_dir, optional_content)
/// entries, and this module runs the discovery logic on that data.
///
/// ## Usage
///
/// ```moonbit
/// let entries = [
///   ("repo/Cargo.toml", false, Some(cargo_toml_content)),
///   ("repo/crates/lib1/Cargo.toml", false, Some(lib1_content)),
///   ("repo/crates/lib2", true, None),
/// ]
/// let options = DiscoveryOptions::default()
/// let projects = discover_projects("repo", entries, options)
/// ```

// ============================================================================
// Public types
// ============================================================================

///|
/// Information about a discovered project.
pub(all) struct DiscoveredProject {
  /// Path to the project root directory.
  path : String
  /// Detected project type.
  project_type : @types.ProjectType
  /// Whether this project is a workspace/monorepo.
  is_workspace : Bool
  /// Name of the project (if detected).
  name : String?
}

///|
/// Options for project discovery.
pub(all) struct DiscoveryOptions {
  /// Maximum depth to search for projects (None = unlimited).
  max_depth : Int?
  /// Directory names to skip during discovery.
  skip_dirs : Array[String]
}

///|
/// Default discovery options: skip common noise directories, no depth limit.
pub fn DiscoveryOptions::default() -> DiscoveryOptions {
  {
    max_depth: None,
    skip_dirs: [
      "node_modules",
      "target",
      "vendor",
      "__pycache__",
      ".terraform",
      ".git",
      "dist",
      "build",
    ],
  }
}

// ============================================================================
// Virtual filesystem entry
// ============================================================================

///|
/// A virtual filesystem entry for discovery.
/// - `path`: absolute or relative path string
/// - `is_dir`: true if this entry is a directory
/// - `content`: file content (None for directories or unread files)
pub(all) struct FsEntry {
  path : String
  is_dir : Bool
  content : String?
}

// ============================================================================
// Path utilities
// ============================================================================

///|
/// Normalize a path by removing double slashes and trailing slashes.
fn normalize_path(p : String) -> String {
  let p = p.trim().to_string()
  // Remove trailing slash
  if p.has_suffix("/") && p.length() > 1 {
    p[0:p.length() - 1].to_string()
  } else {
    p
  }
}

///|
/// Get the parent directory of a path.
fn parent_path(p : String) -> String {
  let p = normalize_path(p)
  match p.rev_find("/") {
    Some(idx) => if idx == 0 { "/" } else { p[0:idx].to_string() }
    None => "."
  }
}

///|
/// Get the file/directory name (last component) from a path.
fn file_name(p : String) -> String {
  let p = normalize_path(p)
  match p.rev_find("/") {
    Some(idx) => p[idx + 1:].to_string()
    None => p
  }
}

///|
/// Join a parent path with a child name.
fn join_path(parent : String, child : String) -> String {
  let parent = normalize_path(parent)
  let child = child.trim().to_string()
  if parent == "." || parent == "" {
    child
  } else {
    "\{parent}/\{child}"
  }
}

///|
/// Check if path is a direct child directory of parent.
fn is_direct_child(parent : String, child : String) -> Bool {
  let parent = normalize_path(parent)
  let child = normalize_path(child)
  if parent_path(child) == parent {
    return true
  }
  false
}

// ============================================================================
// Glob pattern matching
// ============================================================================

///|
/// Check if a path matches a glob pattern.
/// Supports `*` (match any segment) and `**` (match any number of segments).
/// Pattern is relative to `base_path`.
fn glob_matches(base_path : String, pattern : String, target : String) -> Bool {
  let base = normalize_path(base_path)
  let target = normalize_path(target)
  // Build the full pattern
  let full_pattern = if base == "." || base == "" {
    pattern
  } else {
    "\{base}/\{pattern}"
  }
  glob_match_pattern(full_pattern, target)
}

///|
/// Match a path against a glob pattern.
fn glob_match_pattern(pattern : String, path : String) -> Bool {
  // Split into segments
  let pat_segs = split_path_segments(pattern)
  let path_segs = split_path_segments(path)
  glob_match_segments(pat_segs, 0, path_segs, 0)
}

///|
/// Split a path into segments.
fn split_path_segments(p : String) -> Array[String] {
  let result : Array[String] = []
  for seg in p.split("/") {
    let s = seg.to_string()
    if s != "" {
      result.push(s)
    }
  }
  result
}

///|
/// Recursive glob matching on segment arrays.
fn glob_match_segments(
  pat : Array[String],
  pi : Int,
  path : Array[String],
  pathi : Int
) -> Bool {
  if pi >= pat.length() {
    return pathi >= path.length()
  }
  let p = pat[pi]
  if p == "**" {
    // ** matches zero or more segments
    let mut j = pathi
    while j <= path.length() {
      if glob_match_segments(pat, pi + 1, path, j) {
        return true
      }
      j = j + 1
    }
    return false
  }
  if pathi >= path.length() {
    return false
  }
  if glob_segment_match(p, path[pathi]) {
    return glob_match_segments(pat, pi + 1, path, pathi + 1)
  }
  false
}

///|
/// Match a single glob segment against a path segment.
/// `*` matches any characters within a segment.
fn glob_segment_match(pattern : String, segment : String) -> Bool {
  if pattern == "*" {
    return true
  }
  if !pattern.contains("*") {
    return pattern == segment
  }
  // Handle * within segment: e.g. "lib*" matches "lib1", "library"
  let parts = pattern.split("*").map(fn(sv) { sv.to_string() }).collect()
  let i = Ref::new(0) // position in segment
  let seg_chars = segment.to_array()
  for idx, part in parts {
    if part == "" {
      if idx == parts.length() - 1 {
        return true
      }
      continue
    }
    // Find part in seg_chars starting at i
    let found = Ref::new(false)
    let start = i.val
    let mut j = start
    while j + part.length() <= seg_chars.length() {
      let slice = String::from_array(seg_chars[j:j + part.length()])
      if slice == part {
        if idx == 0 && j != 0 {
          // First part must match at the beginning
          break
        }
        i.val = j + part.length()
        found.val = true
        break
      }
      if idx == 0 {
        break // First part must match at start
      }
      j = j + 1
    }
    if !found.val {
      return false
    }
  }
  // For the last part (after final *), check it ends the segment
  let last_part = parts[parts.length() - 1]
  if last_part == "" {
    return true
  }
  // Last part must end at the segment's end
  i.val >= seg_chars.length() || (
    i.val == seg_chars.length() - last_part.length() + last_part.length() &&
    segment.has_suffix(last_part)
  )
}

// ============================================================================
// Discovery logic
// ============================================================================

///|
/// Build a lookup map: path -> FsEntry, and dir -> [child_paths] for traversal.
fn build_fs_map(
  entries : Array[FsEntry]
) -> (Map[String, FsEntry], Map[String, Array[String]]) {
  let by_path : Map[String, FsEntry] = {}
  let children : Map[String, Array[String]] = {}
  for entry in entries {
    let p = normalize_path(entry.path)
    by_path[p] = { path: p, is_dir: entry.is_dir, content: entry.content }
    let par = parent_path(p)
    match children.get(par) {
      Some(arr) => arr.push(p)
      None => {
        let arr : Array[String] = [p]
        children[par] = arr
      }
    }
  }
  (by_path, children)
}

///|
/// Collect all workspace member paths from the given project directory.
fn collect_workspace_members_from_entries(
  root : String,
  entries : Array[FsEntry],
  by_path : Map[String, FsEntry]
) -> Array[String] {
  let members : Array[String] = []
  let cargo_toml_path = join_path(root, "Cargo.toml")
  match by_path.get(cargo_toml_path) {
    Some(e) =>
      match e.content {
        Some(content) => {
          let patterns = @cargo.get_workspace_members(content)
          for pattern in patterns {
            expand_member_pattern(root, pattern, entries, members)
          }
        }
        None => ()
      }
    None => ()
  }
  members
}

///|
/// Expand a workspace member glob pattern into actual paths.
fn expand_member_pattern(
  base : String,
  pattern : String,
  entries : Array[FsEntry],
  out : Array[String]
) -> Unit {
  if !pattern.contains("*") {
    // Simple path
    let full = join_path(base, pattern)
    out.push(normalize_path(full))
    return
  }
  // Glob pattern — scan entries
  for entry in entries {
    if entry.is_dir && glob_matches(base, pattern, entry.path) {
      out.push(normalize_path(entry.path))
    }
  }
}

///|
/// Detect the project type at a given directory path.
fn detect_project_at(
  dir_path : String,
  by_path : Map[String, FsEntry]
) -> DiscoveredProject? {
  // Cargo
  let cargo_toml = join_path(dir_path, "Cargo.toml")
  match by_path.get(cargo_toml) {
    Some(e) => {
      let (is_workspace, name) = parse_cargo_project_info(e.content)
      return Some({
        path: dir_path,
        project_type: @types.ProjectType::Cargo,
        is_workspace,
        name,
      })
    }
    None => ()
  }
  // npm/package.json
  let package_json = join_path(dir_path, "package.json")
  match by_path.get(package_json) {
    Some(e) => {
      let (is_workspace, name) = parse_npm_project_info(e.content)
      return Some({
        path: dir_path,
        project_type: @types.ProjectType::Npm,
        is_workspace,
        name,
      })
    }
    None => ()
  }
  // Go
  let go_mod = join_path(dir_path, "go.mod")
  match by_path.get(go_mod) {
    Some(_) =>
      return Some({
        path: dir_path,
        project_type: @types.ProjectType::Go,
        is_workspace: false,
        name: None,
      })
    None => ()
  }
  // Python
  let pyproject = join_path(dir_path, "pyproject.toml")
  let setup_py = join_path(dir_path, "setup.py")
  let requirements = join_path(dir_path, "requirements.txt")
  if by_path.contains(pyproject) ||
    by_path.contains(setup_py) ||
    by_path.contains(requirements) {
    return Some({
      path: dir_path,
      project_type: @types.ProjectType::Python,
      is_workspace: false,
      name: None,
    })
  }
  // Terraform
  let lock_hcl = join_path(dir_path, ".terraform.lock.hcl")
  if by_path.contains(lock_hcl) || has_tf_files(dir_path, by_path) {
    return Some({
      path: dir_path,
      project_type: @types.ProjectType::Terraform,
      is_workspace: false,
      name: None,
    })
  }
  None
}

///|
/// Check if a directory contains .tf files.
fn has_tf_files(dir_path : String, by_path : Map[String, FsEntry]) -> Bool {
  for path, entry in by_path {
    if !entry.is_dir &&
      parent_path(path) == normalize_path(dir_path) &&
      path.has_suffix(".tf") {
      return true
    }
  }
  false
}

///|
/// Quick parse of Cargo.toml content to detect workspace and name.
fn parse_cargo_project_info(content : String?) -> (Bool, String?) {
  match content {
    None => (false, None)
    Some(c) => {
      let has_workspace = Ref::new(false)
      let name : Ref[String?] = Ref::new(None)
      let in_workspace_section = Ref::new(false)
      let in_package_section = Ref::new(false)
      for raw in c.split("\n") {
        let line = raw.to_string().trim().to_string()
        if line == "[workspace]" {
          has_workspace.val = true
          in_workspace_section.val = true
          in_package_section.val = false
        } else if line == "[package]" {
          in_package_section.val = true
          in_workspace_section.val = false
        } else if line.has_prefix("[") {
          in_workspace_section.val = false
          in_package_section.val = false
        } else if in_package_section.val {
          match line.find("=") {
            Some(eq) => {
              let key = line[0:eq].to_string().trim().to_string()
              if key == "name" {
                let val = line[eq + 1:].to_string().trim().to_string()
                // Unquote
                let val = if val.has_prefix("\"") && val.has_suffix("\"") && val.length() >= 2 {
                  val[1:val.length() - 1].to_string()
                } else {
                  val
                }
                name.val = Some(val)
              }
            }
            None => ()
          }
        } else if in_workspace_section.val && line.has_prefix("members") {
          has_workspace.val = true
        }
      }
      (has_workspace.val, name.val)
    }
  }
}

///|
/// Quick parse of package.json to detect workspace and name.
fn parse_npm_project_info(content : String?) -> (Bool, String?) {
  match content {
    None => (false, None)
    Some(c) => {
      let has_workspace = c.contains("\"workspaces\"")
      let name : Ref[String?] = Ref::new(None)
      // Find "name": "..."
      match c.find("\"name\"") {
        None => ()
        Some(pos) => {
          let rest = c[pos + 6:].to_string()
          match rest.find(":") {
            None => ()
            Some(colon) => {
              let val_part = rest[colon + 1:].to_string().trim().to_string()
              if val_part.has_prefix("\"") {
                match val_part[1:].to_string().find("\"") {
                  Some(end) => name.val = Some(val_part[1:end + 1].to_string())
                  None => ()
                }
              }
            }
          }
        }
      }
      (has_workspace, name.val)
    }
  }
}

// ============================================================================
// BFS discovery
// ============================================================================

///|
/// Discover all independent projects in a virtual filesystem.
///
/// # Parameters
/// - `root`: The root path to search from
/// - `entries`: All filesystem entries (files and directories)
/// - `options`: Discovery options
///
/// # Returns
/// Array of discovered independent projects
pub fn discover_projects(
  root : String,
  entries : Array[FsEntry],
  options : DiscoveryOptions
) -> Array[DiscoveredProject] {
  let root = normalize_path(root)
  let (by_path, children) = build_fs_map(entries)

  // First pass: collect all workspace member paths (to exclude them)
  let workspace_members : Array[String] = []
  collect_all_workspace_members(root, entries, by_path, workspace_members)
  let member_set : Map[String, Bool] = {}
  for m in workspace_members {
    member_set[normalize_path(m)] = true
  }

  // BFS
  let projects : Array[DiscoveredProject] = []
  // Queue: (path, depth)
  let queue : Array[(String, Int)] = [(root, 0)]
  let visited : Map[String, Bool] = {}
  let qi = Ref::new(0)

  while qi.val < queue.length() {
    let (cur_path, depth) = queue[qi.val]
    qi.val = qi.val + 1
    let norm = normalize_path(cur_path)
    if visited.contains(norm) {
      continue
    }
    visited[norm] = true

    // Skip workspace members
    if member_set.contains(norm) {
      continue
    }

    // Detect project at this directory
    let is_workspace_node = Ref::new(false)
    match detect_project_at(norm, by_path) {
      Some(proj) => {
        is_workspace_node.val = proj.is_workspace
        projects.push(proj)
        // For non-workspace projects, don't descend
        if !proj.is_workspace {
          continue
        }
      }
      None => ()
    }

    // Check depth limit
    match options.max_depth {
      Some(max) => if depth >= max { continue }
      None => ()
    }

    // Explore subdirectories
    let dir_children = match children.get(norm) {
      Some(arr) => arr
      None => []
    }
    for child_path in dir_children {
      match by_path.get(child_path) {
        Some(entry) =>
          if entry.is_dir {
            let name = file_name(child_path)
            // Skip hidden dirs and skipped dirs
            if !name.has_prefix(".") && !contains_string(options.skip_dirs, name) {
              queue.push((child_path, depth + 1))
            }
          }
        None => ()
      }
    }
  }

  projects
}

///|
/// Collect workspace members from all workspace files in the filesystem.
fn collect_all_workspace_members(
  root : String,
  entries : Array[FsEntry],
  by_path : Map[String, FsEntry],
  out : Array[String]
) -> Unit {
  let root = normalize_path(root)
  // BFS over directories to find workspace files
  let queue : Array[String] = [root]
  let visited : Map[String, Bool] = {}
  let qi = Ref::new(0)
  while qi.val < queue.length() {
    let cur = queue[qi.val]
    qi.val = qi.val + 1
    if visited.contains(cur) {
      continue
    }
    visited[cur] = true
    let members = collect_workspace_members_from_entries(cur, entries, by_path)
    for m in members {
      out.push(m)
    }
    // Enqueue subdirectories
    for entry in entries {
      if entry.is_dir && is_direct_child(cur, normalize_path(entry.path)) {
        queue.push(normalize_path(entry.path))
      }
    }
  }
}

///|
/// Check if an array contains a string.
fn contains_string(arr : Array[String], s : String) -> Bool {
  for item in arr {
    if item == s {
      return true
    }
  }
  false
}

// ============================================================================
// Convenience: build FsEntry list from a simple map
// ============================================================================

///|
/// Build FsEntry list from a path -> content map.
/// Directories are auto-detected (paths ending in "/" or having children).
pub fn entries_from_map(files : Map[String, String]) -> Array[FsEntry] {
  let result : Array[FsEntry] = []
  // Add all files
  for path, content in files {
    let p = normalize_path(path)
    result.push({ path: p, is_dir: false, content: Some(content) })
  }
  // Auto-add parent directories
  let dirs : Map[String, Bool] = {}
  for path, _ in files {
    let p = normalize_path(path)
    let par = parent_path(p)
    if par != "." && par != "" {
      dirs[par] = true
      // Also add grandparent etc.
      let gpar = parent_path(par)
      if gpar != "." && gpar != "" {
        dirs[gpar] = true
      }
    }
  }
  for dir, _ in dirs {
    result.push({ path: dir, is_dir: true, content: None })
  }
  result
}
