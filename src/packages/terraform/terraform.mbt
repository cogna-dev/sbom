///|
/// Minimal HCL parser for Terraform files.
///
/// Parses only the sections relevant to SCA:
///   - `terraform { required_providers { ... } }` blocks in .tf files
///   - `provider "..." { version = "..." hashes = [...] }` blocks in .terraform.lock.hcl
///
/// MoonBit has no native HCL library, so we implement a line-oriented parser
/// that handles the subset of HCL used in typical Terraform projects.

// ============================================================================
// HCL parsing helpers
// ============================================================================

///|
/// Strip inline comment from an HCL value.
fn strip_hcl_comment(s : String) -> String {
  let in_quote = Ref::new(false)
  let buf = StringBuilder::new()
  let chars = s.to_array()
  let i = Ref::new(0)
  while i.val < chars.length() {
    let ch = chars[i.val]
    if ch == '"' {
      in_quote.val = !in_quote.val
      buf.write_char(ch)
    } else if (ch == '#' || ch == '/') && !in_quote.val {
      break
    } else {
      buf.write_char(ch)
    }
    i.val = i.val + 1
  }
  buf.to_string().trim().to_string()
}

///|
/// Unquote an HCL string value (remove surrounding double quotes).
fn hcl_unquote(s : String) -> String {
  let s = s.trim().to_string()
  if s.has_prefix("\"") && s.has_suffix("\"") && s.length() >= 2 {
    s[1:s.length() - 1].to_string()
  } else {
    s
  }
}

///|
/// Extract the label from a block header like `provider "registry.terraform.io/..." {`.
/// Returns the label string (unquoted) or empty string if not found.
fn extract_block_label(line : String) -> String {
  let line = strip_hcl_comment(line)
  match line.find("\"") {
    None => ""
    Some(first_quote) => {
      let rest = line[first_quote + 1:].to_string()
      match rest.find("\"") {
        None => ""
        Some(second_quote) => rest[0:second_quote].to_string()
      }
    }
  }
}

///|
/// Extract block identifier (first word) from a line like `terraform {`.
fn block_identifier(line : String) -> String {
  let line = line.trim().to_string()
  let buf = StringBuilder::new()
  for ch in line.iter() {
    if ch == ' ' || ch == '\t' || ch == '{' || ch == '"' {
      break
    }
    buf.write_char(ch)
  }
  buf.to_string()
}

// ============================================================================
// Parsed representations
// ============================================================================

///|
/// Information about a provider from the lock file.
pub(all) struct ProviderInfo {
  version : String?
  hashes : Array[String]
}

// ============================================================================
// Lock file parser (.terraform.lock.hcl)
// ============================================================================

///|
/// Parse .terraform.lock.hcl content into a map of provider source -> ProviderInfo.
///
/// Lock file format:
/// ```hcl
/// provider "registry.terraform.io/hashicorp/aws" {
///   version     = "5.31.0"
///   constraints = "~> 5.0"
///   hashes = [
///     "h1:abc123=",
///   ]
/// }
/// ```
pub fn parse_lock_file(content : String) -> Map[String, ProviderInfo] {
  let result : Map[String, ProviderInfo] = {}
  // Parser state
  let depth = Ref::new(0)
  let cur_provider_key : Ref[String] = Ref::new("")
  let cur_info_version : Ref[String?] = Ref::new(None)
  let cur_info_hashes : Array[String] = []
  let in_provider = Ref::new(false)
  let in_hashes_array = Ref::new(false)
  let hashes_buf : Ref[String] = Ref::new("")

  fn flush_provider() {
    if in_provider.val && cur_provider_key.val != "" {
      let hashes_copy : Array[String] = []
      for h in cur_info_hashes {
        hashes_copy.push(h)
      }
      result[cur_provider_key.val] = {
        version: cur_info_version.val,
        hashes: hashes_copy,
      }
    }
  }

  for raw_line in content.split("\n") {
    let line = raw_line.to_string().trim().to_string()
    if line == "" || line.has_prefix("#") {
      continue
    }

    // Count braces for depth tracking
    let open_count = count_char(line, '{')
    let close_count = count_char(line, '}')

    // Handle hashes array spanning multiple lines
    if in_hashes_array.val {
      if line.contains("]") {
        in_hashes_array.val = false
        let combined = hashes_buf.val + line
        parse_hcl_string_array(combined, cur_info_hashes)
        hashes_buf.val = ""
      } else {
        hashes_buf.val = hashes_buf.val + line + "\n"
      }
      continue
    }

    if depth.val == 0 {
      // Top-level block detection
      if block_identifier(line) == "provider" && line.contains("{") {
        flush_provider()
        cur_provider_key.val = extract_block_label(line)
        cur_info_version.val = None
        cur_info_hashes.clear()
        in_provider.val = true
        depth.val = depth.val + open_count - close_count
        continue
      }
    } else if depth.val == 1 && in_provider.val {
      // Inside provider block
      match line.find("=") {
        Some(eq) => {
          let key = line[0:eq].to_string().trim().to_string()
          let val_part = line[eq + 1:].to_string().trim().to_string()
          match key {
            "version" =>
              cur_info_version.val = Some(
                hcl_unquote(strip_hcl_comment(val_part)),
              )
            "hashes" =>
              if val_part.contains("[") && val_part.contains("]") {
                parse_hcl_string_array(val_part, cur_info_hashes)
              } else if val_part.contains("[") {
                in_hashes_array.val = true
                hashes_buf.val = val_part + "\n"
              }
            _ => ()
          }
        }
        None => ()
      }
    }
    depth.val = depth.val + open_count - close_count
    if depth.val <= 0 {
      depth.val = 0
      if in_provider.val {
        flush_provider()
        in_provider.val = false
        cur_provider_key.val = ""
      }
    }
  }
  // Final flush
  flush_provider()
  result
}

///|
/// Count occurrences of a character in a string.
fn count_char(s : String, target : Char) -> Int {
  let count = Ref::new(0)
  for ch in s.iter() {
    if ch == target {
      count.val = count.val + 1
    }
  }
  count.val
}

///|
/// Parse an HCL array of strings like `["a", "b"]` into an Array[String].
fn parse_hcl_string_array(s : String, out : Array[String]) -> Unit {
  let inner = match s.find("[") {
    Some(start) =>
      match s.find("]") {
        Some(end) =>
          if end > start {
            s[start + 1:end].to_string()
          } else {
            s[start + 1:].to_string()
          }
        None => s[start + 1:].to_string()
      }
    None => s
  }
  for part in inner.split(",") {
    let item = hcl_unquote(part.to_string().trim().to_string())
    if item != "" {
      out.push(item)
    }
  }
}

// ============================================================================
// .tf file parser
// ============================================================================

///|
/// A provider requirement parsed from a .tf file.
pub(all) struct ProviderRequirement {
  local_name : String
  source : String? // e.g. "hashicorp/aws"
  version_constraint : String?
}

///|
/// Parse required_providers block content (everything inside the block).
fn parse_required_providers_block(
  block_content : String,
) -> Array[ProviderRequirement] {
  let result : Array[ProviderRequirement] = []
  // Split into lines and scan for key = { ... } entries
  let lines = block_content.split("\n").map(fn(sv) { sv.to_string() }).collect()
  let i = Ref::new(0)
  while i.val < lines.length() {
    let line = lines[i.val].trim().to_string()
    i.val = i.val + 1
    if line == "" || line.has_prefix("#") {
      continue
    }
    // Look for: provider_name = { ... } or provider_name = "version"
    match line.find("=") {
      None => ()
      Some(eq) => {
        let local_name = line[0:eq].to_string().trim().to_string()
        let val_part = line[eq + 1:].to_string().trim().to_string()
        if val_part.has_prefix("{") {
          // Inline object or multi-line object
          let obj_content = if val_part.contains("}") {
            val_part
          } else {
            // Collect lines until matching }
            let buf = StringBuilder::new()
            buf.write_string(val_part)
            buf.write_char('\n')
            let found = Ref::new(false)
            while i.val < lines.length() && !found.val {
              let next = lines[i.val].trim().to_string()
              i.val = i.val + 1
              buf.write_string(next)
              buf.write_char('\n')
              if next.contains("}") {
                found.val = true
              }
            }
            buf.to_string()
          }
          let req = parse_provider_object(local_name, obj_content)
          result.push(req)
        } else {
          // Simple string value (rare for Terraform providers)
          result.push({
            local_name,
            source: None,
            version_constraint: Some(hcl_unquote(strip_hcl_comment(val_part))),
          })
        }
      }
    }
  }
  result
}

///|
/// Parse a provider object like `{ source = "hashicorp/aws", version = "~> 5.0" }`.
fn parse_provider_object(
  local_name : String,
  s : String,
) -> ProviderRequirement {
  let source : Ref[String?] = Ref::new(None)
  let version : Ref[String?] = Ref::new(None)
  for line in s.split("\n") {
    let line = line.to_string().trim().to_string()
    if line == "" || line.has_prefix("#") || line == "{" || line == "}" {
      continue
    }
    match line.find("=") {
      None => ()
      Some(eq) => {
        let key = line[0:eq].to_string().trim().to_string()
        let val = hcl_unquote(strip_hcl_comment(line[eq + 1:].to_string()))
        match key {
          "source" => source.val = Some(val)
          "version" => version.val = Some(val)
          _ => ()
        }
      }
    }
  }
  { local_name, source: source.val, version_constraint: version.val }
}

///|
/// Extract required_providers blocks from a single .tf file content.
/// Returns the list of provider requirements found.
pub fn extract_providers_from_tf(
  content : String,
) -> Array[ProviderRequirement] {
  let result : Array[ProviderRequirement] = []
  let lines = content.split("\n").map(fn(sv) { sv.to_string() }).collect()
  let i = Ref::new(0)
  while i.val < lines.length() {
    let line = lines[i.val].trim().to_string()
    i.val = i.val + 1
    if block_identifier(line) == "terraform" && line.contains("{") {
      // Inside terraform block, look for required_providers
      let depth = Ref::new(1)
      while i.val < lines.length() && depth.val > 0 {
        let inner = lines[i.val].trim().to_string()
        i.val = i.val + 1
        depth.val = depth.val + count_char(inner, '{') - count_char(inner, '}')
        if block_identifier(inner) == "required_providers" &&
          inner.contains("{") {
          // Collect content of required_providers block
          let buf = StringBuilder::new()
          let rp_depth = Ref::new(1)
          while i.val < lines.length() && rp_depth.val > 0 {
            let rp_line = lines[i.val].trim().to_string()
            i.val = i.val + 1
            rp_depth.val = rp_depth.val +
              count_char(rp_line, '{') -
              count_char(rp_line, '}')
            if rp_depth.val > 0 {
              buf.write_string(rp_line)
              buf.write_char('\n')
            }
          }
          let reqs = parse_required_providers_block(buf.to_string())
          for req in reqs {
            result.push(req)
          }
        }
      }
    }
  }
  result
}

// ============================================================================
// Convert parsed data to types.Package / types.Project
// ============================================================================

///|
/// Return the last path component from a path string.
fn tf_dir_name(path : String) -> String {
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

///|
/// Build a Package from a ProviderRequirement and optional lock file info.
fn provider_to_package(
  req : ProviderRequirement,
  resolved : Map[String, ProviderInfo],
) -> @types.Package {
  let full_source = match req.source {
    Some(src) => src
    None => "hashicorp/\{req.local_name}"
  }
  // Split source into namespace and provider name
  let (ns, provider_name) = match full_source.find("/") {
    Some(slash) => {
      let n = full_source[0:slash].to_string()
      let p = full_source[slash + 1:].to_string()
      // Handle multi-segment paths like "namespace/provider/subname" — use last segment
      let p = match p.rev_find("/") {
        Some(last) => p[last + 1:].to_string()
        None => p
      }
      (Some(n), p)
    }
    None => (None, full_source)
  }
  let registry_url = "https://registry.terraform.io/providers/\{full_source}"
  let pkg = @types.Package::new(provider_name, "terraform")
  let pkg = {
    ..pkg,
    ns,
    source: @types.DependencySource::Registry(Some(registry_url)),
  }
  // Parse version constraint
  let pkg = match req.version_constraint {
    Some(constraint_str) =>
      match @version.VersionRequirement::parse(constraint_str) {
        Some(req_parsed) => { ..pkg, requirement: Some(req_parsed) }
        None => pkg
      }
    None => pkg
  }
  // Apply resolved info from lock file
  // Lock file key: "registry.terraform.io/hashicorp/aws" or "hashicorp/aws"
  let lock_key = "registry.terraform.io/\{full_source}"
  let info : ProviderInfo? = match resolved.get(lock_key) {
    Some(i) => Some(i)
    None => resolved.get(full_source)
  }
  match info {
    None => pkg
    Some(pi) => {
      let pkg = match pi.version {
        Some(ver_str) =>
          match @version.Version::parse(ver_str) {
            Some(v) => { ..pkg, resolved_version: Some(v) }
            None => pkg
          }
        None => pkg
      }
      // Find first h1: hash as checksum
      let h1_hash : Ref[String?] = Ref::new(None)
      for hash in pi.hashes {
        match h1_hash.val {
          Some(_) => ()
          None => if hash.has_prefix("h1:") { h1_hash.val = Some(hash) }
        }
      }
      match h1_hash.val {
        Some(cs) => { ..pkg, checksum: Some(cs) }
        None => pkg
      }
    }
  }
}

// ============================================================================
// Public API
// ============================================================================

///|
/// Parse a Terraform project from text content.
///
/// # Parameters
/// - `root_path`: The filesystem path (used as project name/path)
/// - `tf_contents`: Array of (filename, content) pairs for .tf files
/// - `lock_content`: Optional content of .terraform.lock.hcl
pub fn parse_terraform_project(
  root_path : String,
  tf_contents : Array[(String, String)],
  lock_content : String?,
) -> @types.Project {
  let name = tf_dir_name(root_path)
  let resolved : Map[String, ProviderInfo] = match lock_content {
    Some(lc) => parse_lock_file(lc)
    None => {}
  }
  let project = @types.Project::new(
    name,
    "0.0.0",
    root_path,
    @types.ProjectType::Terraform,
  )
  let subproject = @types.SubProject::new(
    name,
    root_path,
    @types.ProjectType::Terraform,
  )
  // Track seen providers to avoid duplicates
  let seen : Map[String, Bool] = {}
  for pair in tf_contents {
    let (_, file_content) = pair
    let reqs = extract_providers_from_tf(file_content)
    for req in reqs {
      let full_source = match req.source {
        Some(src) => src
        None => "hashicorp/\{req.local_name}"
      }
      if !seen.contains(full_source) {
        seen[full_source] = true
        subproject.add_package(provider_to_package(req, resolved))
      }
    }
  }
  project.add_subproject(subproject)
  project
}

///|
/// Parse a single .tf file content and return provider requirements.
pub fn parse_tf_file(content : String) -> Array[ProviderRequirement] {
  extract_providers_from_tf(content)
}

///|
/// Parse .terraform.lock.hcl content and return resolved provider versions.
/// Returns a map of provider source -> (version?, hashes).
pub fn parse_terraform_lock(
  content : String,
) -> Map[String, (String?, Array[String])] {
  let raw = parse_lock_file(content)
  let result : Map[String, (String?, Array[String])] = {}
  for key, info in raw {
    result[key] = (info.version, info.hashes)
  }
  result
}
