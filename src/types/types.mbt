///|
/// Supported project types for dependency scanning.
pub(all) enum ProjectType {
  Cargo
  Terraform
  Go
  Npm
  Python
  Unknown
} derive(Debug, Eq, Hash)

///|
impl Show for ProjectType with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Get the PURL type string for this project type.
pub fn ProjectType::purl_type(self : ProjectType) -> String {
  match self {
    Cargo => "cargo"
    Terraform => "terraform"
    Go => "golang"
    Npm => "npm"
    Python => "pypi"
    Unknown => "generic"
  }
}

///|
pub fn ProjectType::to_string(self : ProjectType) -> String {
  match self {
    Cargo => "cargo"
    Terraform => "terraform"
    Go => "go"
    Npm => "npm"
    Python => "python"
    Unknown => "unknown"
  }
}

///|
/// Source of a dependency.
pub(all) enum DependencySource {
  /// Package from a registry (crates.io, npm, PyPI, etc.)
  Registry(String?) // optional url
  /// Package from a Git repository
  Git(String, String?, String?) // url, ref_type, ref_value
  /// Local path dependency
  Path(String)
  /// Workspace member (internal dependency)
  Workspace
} derive(Debug, Eq)

///|
impl Show for DependencySource with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn DependencySource::to_string(self : DependencySource) -> String {
  match self {
    Registry(None) => "registry"
    Registry(Some(url)) => "registry:\{url}"
    Git(url, _, _) => "git:\{url}"
    Path(p) => "path:\{p}"
    Workspace => "workspace"
  }
}

///|
pub fn DependencySource::default() -> DependencySource {
  Registry(None)
}

///|
/// Dependency group/scope.
pub(all) enum DependencyGroup {
  Runtime
  Dev
  Build
  Optional
} derive(Debug, Eq, Hash)

///|
impl Show for DependencyGroup with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn DependencyGroup::to_string(self : DependencyGroup) -> String {
  match self {
    Runtime => "runtime"
    Dev => "dev"
    Build => "build"
    Optional => "optional"
  }
}

///|
pub fn DependencyGroup::default() -> DependencyGroup {
  Runtime
}

///|
/// A software package with metadata.
pub(all) struct Package {
  mut name : String
  mut pkg_type : String
  mut requirement : @version.VersionRequirement?
  mut resolved_version : @version.Version?
  mut source : DependencySource
  mut group : DependencyGroup
  mut ns : String?
  mut qualifiers : Array[(String, String)]
  mut subpath : String?
  mut description : String?
  mut license : String?
  mut homepage : String?
  mut checksum : String?
  mut dependencies : Array[String]
}

///|
/// Create a new package with name and type.
pub fn Package::new(name : String, pkg_type : String) -> Package {
  {
    name,
    pkg_type,
    requirement: None,
    resolved_version: None,
    source: DependencySource::default(),
    group: DependencyGroup::default(),
    ns: None,
    qualifiers: [],
    subpath: None,
    description: None,
    license: None,
    homepage: None,
    checksum: None,
    dependencies: [],
  }
}

///|
/// Create a package with a resolved version.
pub fn Package::with_version(
  name : String,
  version : String,
  pkg_type : String,
) -> Package {
  let resolved = @version.Version::parse(version)
  {
    name,
    pkg_type,
    requirement: None,
    resolved_version: resolved,
    source: DependencySource::default(),
    group: DependencyGroup::default(),
    ns: None,
    qualifiers: [],
    subpath: None,
    description: None,
    license: None,
    homepage: None,
    checksum: None,
    dependencies: [],
  }
}

///|
/// Set the version requirement.
pub fn Package::set_requirement(
  self : Package,
  req : @version.VersionRequirement,
) -> Package {
  { ..self, requirement: Some(req) }
}

///|
/// Set the resolved version.
pub fn Package::set_resolved_version(
  self : Package,
  version : @version.Version,
) -> Package {
  { ..self, resolved_version: Some(version) }
}

///|
/// Set the dependency source.
pub fn Package::set_source(
  self : Package,
  source : DependencySource,
) -> Package {
  { ..self, source, }
}

///|
/// Set the dependency group.
pub fn Package::set_group(self : Package, group : DependencyGroup) -> Package {
  { ..self, group, }
}

///|
/// Set the namespace.
pub fn Package::set_namespace(self : Package, ns : String) -> Package {
  { ..self, ns: Some(ns) }
}

///|
/// Set the description.
pub fn Package::set_description(
  self : Package,
  description : String,
) -> Package {
  { ..self, description: Some(description) }
}

///|
/// Set the license.
pub fn Package::set_license(self : Package, license : String) -> Package {
  { ..self, license: Some(license) }
}

///|
/// Set the homepage.
pub fn Package::set_homepage(self : Package, homepage : String) -> Package {
  { ..self, homepage: Some(homepage) }
}

///|
/// Set the checksum.
pub fn Package::set_checksum(self : Package, checksum : String) -> Package {
  { ..self, checksum: Some(checksum) }
}

///|
/// Get the version string (resolved version preferred, falls back to requirement).
pub fn Package::version(self : Package) -> String {
  match self.resolved_version {
    Some(v) => v.to_string()
    None =>
      match self.requirement {
        Some(req) => req.to_string()
        None => "unknown"
      }
  }
}

///|
/// Generate a Package URL (PURL) for this package.
/// Format: pkg:type/namespace/name@version
pub fn Package::to_purl(self : Package) -> String {
  let buf = StringBuilder::new()
  buf.write_string("pkg:\{self.pkg_type}/")
  match self.ns {
    Some(ns) => buf.write_string("\{ns}/")
    None => ()
  }
  buf.write_string(self.name)
  match self.resolved_version {
    Some(v) => buf.write_string("@\{v.to_string()}")
    None => ()
  }
  buf.to_string()
}

///|
/// Get the unique identifier for this package.
pub fn Package::id(self : Package) -> String {
  let version = self.version()
  match self.ns {
    Some(ns) => "\{self.pkg_type}/\{ns}/\{self.name}@\{version}"
    None => "\{self.pkg_type}/\{self.name}@\{version}"
  }
}

///|
/// Supported SBOM export formats.
pub(all) enum ExportFormat {
  Spdx
  CycloneDx
} derive(Debug, Eq)

///|
impl Show for ExportFormat with output(self, logger) {
  match self {
    Spdx => logger.write_string("spdx")
    CycloneDx => logger.write_string("cyclonedx")
  }
}

///|
/// Software Bill of Materials (SBOM) container.
pub(all) struct Sbom {
  mut name : String
  mut version : String
  mut description : String?
  mut packages : Array[Package]
  mut created : String
  mut creator_tool : String
}

///|
/// Create a new SBOM for a project.
pub fn Sbom::new(name : String, version : String) -> Sbom {
  {
    name,
    version,
    description: None,
    packages: [],
    created: "1970-01-01T00:00:00Z", // placeholder; no stdlib time in MoonBit
    creator_tool: "cogna-dev/sbom/0.1.0",
  }
}

///|
/// Add a package to the SBOM.
pub fn Sbom::add_package(self : Sbom, pkg : Package) -> Unit {
  self.packages.push(pkg)
}

///|
/// A sub-project within a larger project.
pub(all) struct SubProject {
  name : String
  path : String
  project_type : ProjectType
  mut version : String?
  mut description : String?
  mut packages : Array[Package]
}

///|
/// Create a new sub-project.
pub fn SubProject::new(
  name : String,
  path : String,
  project_type : ProjectType,
) -> SubProject {
  { name, path, project_type, version: None, description: None, packages: [] }
}

///|
/// Set sub-project version.
pub fn SubProject::set_version(
  self : SubProject,
  version : String,
) -> SubProject {
  { ..self, version: Some(version) }
}

///|
/// Set sub-project description.
pub fn SubProject::set_description(
  self : SubProject,
  description : String,
) -> SubProject {
  { ..self, description: Some(description) }
}

///|
/// Add a package to the sub-project.
pub fn SubProject::add_package(self : SubProject, pkg : Package) -> Unit {
  self.packages.push(pkg)
}

///|
/// A complete project that may contain multiple sub-projects.
pub(all) struct Project {
  mut name : String
  mut version : String
  mut root_path : String
  mut project_type : ProjectType
  mut description : String?
  mut subprojects : Array[SubProject]
  mut shared_packages : Array[Package]
  mut packages : Array[Package]
}

///|
/// Create a new project.
pub fn Project::new(
  name : String,
  version : String,
  root_path : String,
  project_type : ProjectType,
) -> Project {
  {
    name,
    version,
    root_path,
    project_type,
    description: None,
    subprojects: [],
    shared_packages: [],
    packages: [],
  }
}

///|
/// Add a sub-project.
pub fn Project::add_subproject(self : Project, subproject : SubProject) -> Unit {
  self.subprojects.push(subproject)
}

///|
/// Add a shared package.
pub fn Project::add_shared_package(self : Project, pkg : Package) -> Unit {
  self.shared_packages.push(pkg)
}

///|
/// Add a resolved package.
pub fn Project::add_package(self : Project, pkg : Package) -> Unit {
  self.packages.push(pkg)
}

///|
/// Get all packages including from sub-projects.
pub fn Project::all_packages(self : Project) -> Array[Package] {
  let all : Array[Package] = []
  for pkg in self.packages {
    all.push(pkg)
  }
  for pkg in self.shared_packages {
    all.push(pkg)
  }
  for subproject in self.subprojects {
    for pkg in subproject.packages {
      all.push(pkg)
    }
  }
  all
}

///|
/// Convert to SBOM for export.
pub fn Project::to_sbom(self : Project) -> Sbom {
  let sbom = Sbom::new(self.name, self.version)
  match self.description {
    Some(desc) => sbom.description = Some(desc)
    None => ()
  }
  for pkg in self.all_packages() {
    sbom.add_package(pkg)
  }
  sbom
}
