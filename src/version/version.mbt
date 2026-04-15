///|
/// A semantic version.
pub(all) struct Version {
  major : Int
  minor : Int
  patch : Int
  pre : String?
  build : String?
} derive(Debug, Eq, Hash)

///|
/// Create a new version.
pub fn Version::new(major : Int, minor : Int, patch : Int) -> Version {
  { major, minor, patch, pre: None, build: None }
}

///|
/// Create a version with prerelease info.
pub fn Version::with_pre(self : Version, pre : String) -> Version {
  { ..self, pre: Some(pre) }
}

///|
/// Create a version with build metadata.
pub fn Version::with_build(self : Version, build : String) -> Version {
  { ..self, build: Some(build) }
}

///|
/// Parse an integer from a string, returning 0 on failure.
fn parse_int_safe(s : String) -> Int {
  try @string.parse_int(s) catch {
    _ => 0
  } noraise {
    n => n
  }
}

///|
/// Parse a version string. Returns None if the string is not a valid version.
pub fn Version::parse(s : String) -> Version? {
  let s : String = s.trim().to_string()
  // Strip leading v/V
  let s : String = if s.has_prefix("v") || s.has_prefix("V") {
    s[1:].to_string()
  } else {
    s
  }
  // Split off build metadata (+)
  let (version_pre, build) : (String, String?) = match s.find("+") {
    Some(idx) => (s[0:idx].to_string(), Some(s[idx + 1:].to_string()))
    None => (s, None)
  }
  // Split off prerelease (-)
  let (version, pre) : (String, String?) = match version_pre.find("-") {
    Some(idx) =>
      (version_pre[0:idx].to_string(), Some(version_pre[idx + 1:].to_string()))
    None => (version_pre, None)
  }
  let parts : Array[String] = version
    .split(".")
    .map(fn(sv) { sv.to_string() })
    .collect()
  let major = parse_int_safe(parts.get(0).unwrap_or("0"))
  let minor = parse_int_safe(parts.get(1).unwrap_or("0"))
  let patch = parse_int_safe(parts.get(2).unwrap_or("0"))
  Some({ major, minor, patch, pre, build })
}

///|
/// Convert version to string representation.
pub fn Version::to_string(self : Version) -> String {
  let buf = StringBuilder::new()
  buf.write_string("\{self.major}.\{self.minor}.\{self.patch}")
  match self.pre {
    Some(p) => buf.write_string("-\{p}")
    None => ()
  }
  match self.build {
    Some(b) => buf.write_string("+\{b}")
    None => ()
  }
  buf.to_string()
}

///|
impl Show for Version with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Compare two versions. Returns negative if self < other, 0 if equal, positive if self > other.
pub fn Version::compare(self : Version, other : Version) -> Int {
  if self.major != other.major {
    return self.major - other.major
  }
  if self.minor != other.minor {
    return self.minor - other.minor
  }
  if self.patch != other.patch {
    return self.patch - other.patch
  }
  // Prerelease versions have lower precedence
  match (self.pre, other.pre) {
    (None, None) => 0
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (Some(a), Some(b)) => a.compare(b)
  }
}

///|
/// A version constraint.
pub(all) enum VersionConstraint {
  Exact(Version)
  Gt(Version)
  Gte(Version)
  Lt(Version)
  Lte(Version)
  Caret(Version)
  Tilde(Version)
  Pessimistic(Version)
  Wildcard(Int, Int?)
  Any
} derive(Debug, Eq)

///|
impl Show for VersionConstraint with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Check if a version satisfies this constraint.
pub fn VersionConstraint::matches(
  self : VersionConstraint,
  version : Version,
) -> Bool {
  match self {
    Exact(v) => version == v
    Gt(v) => version.compare(v) > 0
    Gte(v) => version.compare(v) >= 0
    Lt(v) => version.compare(v) < 0
    Lte(v) => version.compare(v) <= 0
    Caret(v) => {
      if version.compare(v) < 0 {
        return false
      }
      if v.major == 0 && v.minor == 0 {
        version.major == 0 && version.minor == 0
      } else if v.major == 0 {
        version.major == 0 && version.minor == v.minor
      } else {
        version.major == v.major
      }
    }
    Tilde(v) => {
      if version.compare(v) < 0 {
        return false
      }
      version.major == v.major && version.minor == v.minor
    }
    Pessimistic(v) => {
      if version.compare(v) < 0 {
        return false
      }
      if v.patch != 0 {
        version.major == v.major && version.minor == v.minor
      } else {
        version.major == v.major
      }
    }
    Wildcard(major, minor) => {
      if version.major != major {
        return false
      }
      match minor {
        Some(m) => version.minor == m
        None => true
      }
    }
    Any => true
  }
}

///|
/// Convert constraint to string representation.
pub fn VersionConstraint::to_string(self : VersionConstraint) -> String {
  match self {
    Exact(v) => "=\{v.to_string()}"
    Gt(v) => ">\{v.to_string()}"
    Gte(v) => ">=\{v.to_string()}"
    Lt(v) => "<\{v.to_string()}"
    Lte(v) => "<=\{v.to_string()}"
    Caret(v) => "^\{v.to_string()}"
    Tilde(v) => "~\{v.to_string()}"
    Pessimistic(v) => "~> \{v.to_string()}"
    Wildcard(major, None) => "\{major}.*"
    Wildcard(major, Some(minor)) => "\{major}.\{minor}.*"
    Any => "*"
  }
}

///|
/// Parse a version constraint string.
pub fn VersionConstraint::parse(s : String) -> VersionConstraint? {
  let s : String = s.trim().to_string()
  if s == "*" || s == "" {
    return Some(Any)
  }
  if s.has_prefix("^") {
    let rest : String = s[1:].to_string()
    match Version::parse(rest) {
      Some(v) => return Some(Caret(v))
      None => return None
    }
  }
  if s.has_prefix("~>") {
    let rest : String = s[2:].to_string()
    match Version::parse(rest) {
      Some(v) => return Some(Pessimistic(v))
      None => return None
    }
  }
  if s.has_prefix("~") {
    let rest : String = s[1:].to_string()
    match Version::parse(rest) {
      Some(v) => return Some(Tilde(v))
      None => return None
    }
  }
  if s.has_prefix(">=") {
    let rest : String = s[2:].to_string()
    match Version::parse(rest) {
      Some(v) => return Some(Gte(v))
      None => return None
    }
  }
  if s.has_prefix("<=") {
    let rest : String = s[2:].to_string()
    match Version::parse(rest) {
      Some(v) => return Some(Lte(v))
      None => return None
    }
  }
  if s.has_prefix(">") {
    let rest : String = s[1:].to_string()
    match Version::parse(rest) {
      Some(v) => return Some(Gt(v))
      None => return None
    }
  }
  if s.has_prefix("<") {
    let rest : String = s[1:].to_string()
    match Version::parse(rest) {
      Some(v) => return Some(Lt(v))
      None => return None
    }
  }
  if s.has_prefix("=") {
    let rest : String = s[1:].to_string()
    match Version::parse(rest) {
      Some(v) => return Some(Exact(v))
      None => return None
    }
  }
  // Check for wildcard
  if s.contains("*") || s.contains("x") || s.contains("X") {
    let parts : Array[String] = s
      .split(".")
      .map(fn(sv) { sv.to_string() })
      .collect()
    let major = parse_int_safe(parts.get(0).unwrap_or("0"))
    let minor : Int? = match parts.get(1) {
      Some(p) =>
        if p == "*" || p == "x" || p == "X" {
          None
        } else {
          Some(parse_int_safe(p))
        }
      None => None
    }
    return Some(Wildcard(major, minor))
  }
  // Default: exact match
  match Version::parse(s) {
    Some(v) => Some(Exact(v))
    None => None
  }
}

///|
/// A version requirement (one or more constraints).
pub(all) struct VersionRequirement {
  constraints : Array[VersionConstraint]
} derive(Debug, Eq)

///|
impl Show for VersionRequirement with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Create an "any version" requirement.
pub fn VersionRequirement::any() -> VersionRequirement {
  { constraints: [Any] }
}

///|
/// Create a requirement with a single constraint.
pub fn VersionRequirement::new(
  constraint : VersionConstraint,
) -> VersionRequirement {
  { constraints: [constraint] }
}

///|
/// Parse a version requirement string (comma-separated constraints).
pub fn VersionRequirement::parse(s : String) -> VersionRequirement? {
  let s : String = s.trim().to_string()
  if s == "" || s == "*" {
    return Some(VersionRequirement::any())
  }
  let constraints : Array[VersionConstraint] = []
  for part in s.split(",") {
    let part_str : String = part.to_string().trim().to_string()
    match VersionConstraint::parse(part_str) {
      Some(c) => constraints.push(c)
      None => return None
    }
  }
  if constraints.is_empty() {
    return None
  }
  Some({ constraints, })
}

///|
/// Check if a version satisfies all constraints.
pub fn VersionRequirement::matches(
  self : VersionRequirement,
  version : Version,
) -> Bool {
  self.constraints.iter().all(fn(c) { c.matches(version) })
}

///|
/// Convert requirement to string representation.
pub fn VersionRequirement::to_string(self : VersionRequirement) -> String {
  self.constraints.map(fn(c) { c.to_string() }).join(", ")
}
