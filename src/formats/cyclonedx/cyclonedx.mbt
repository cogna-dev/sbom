///|
/// Sanitize a string to be a valid CycloneDX BOM reference.
fn sanitize_bom_ref(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    if ch.is_ascii_alphabetic() ||
      ch.is_ascii_digit() ||
      ch == '-' ||
      ch == '.' ||
      ch == '_' ||
      ch == '/' {
      buf.write_char(ch)
    } else {
      buf.write_char('-')
    }
  }
  buf.to_string()
}

///|
/// Build a JSON object helper.
fn obj(fields : Array[(String, Json)]) -> Json {
  let m : Map[String, Json] = {}
  for pair in fields {
    let (k, v) = pair
    m[k] = v
  }
  Json::object(m)
}

///|
/// Export an SBOM to CycloneDX 1.5 JSON format.
pub fn to_cyclonedx(sbom : @types.Sbom) -> String {
  let components : Array[Json] = []
  let dependencies : Array[Json] = []

  // Root component BOM ref
  let root_bom_ref = "pkg:\{sanitize_bom_ref(sbom.name)}"

  // Root deps list
  let root_deps : Array[Json] = []

  // Dependency components
  for pkg in sbom.packages {
    let version_str = pkg.version()
    let bom_ref = "pkg:\{pkg.pkg_type}/\{sanitize_bom_ref(pkg.name)}@\{version_str}"

    // Licenses
    let licenses : Array[Json] = []
    match pkg.license {
      Some(lic) => {
        let lic_info_fields : Array[(String, Json)] = [
          ("id", Json::string(lic)),
        ]
        let lic_obj = obj([("license", obj(lic_info_fields))])
        licenses.push(lic_obj)
      }
      None => ()
    }

    // External references
    let ext_refs : Array[Json] = []
    match pkg.homepage {
      Some(hp) =>
        ext_refs.push(
          obj([("type", Json::string("website")), ("url", Json::string(hp))]),
        )
      None => ()
    }

    // Hashes
    let hashes : Array[Json] = []
    match pkg.checksum {
      Some(cs) =>
        hashes.push(
          obj([("alg", Json::string("SHA-256")), ("content", Json::string(cs))]),
        )
      None => ()
    }

    let purl = pkg.to_purl()

    let comp_fields : Array[(String, Json)] = [
      ("type", Json::string("library")),
      ("bom-ref", Json::string(bom_ref)),
      ("name", Json::string(pkg.name)),
    ]
    match pkg.ns {
      Some(ns) => comp_fields.push(("group", Json::string(ns)))
      None => ()
    }
    comp_fields.push(("version", Json::string(version_str)))
    match pkg.description {
      Some(desc) => comp_fields.push(("description", Json::string(desc)))
      None => ()
    }
    comp_fields.push(("purl", Json::string(purl)))
    if !licenses.is_empty() {
      comp_fields.push(("licenses", Json::array(licenses)))
    }
    if !ext_refs.is_empty() {
      comp_fields.push(("externalReferences", Json::array(ext_refs)))
    }
    if !hashes.is_empty() {
      comp_fields.push(("hashes", Json::array(hashes)))
    }
    components.push(obj(comp_fields))

    root_deps.push(Json::string(bom_ref))

    // Per-component dependency entry (using stored dep names)
    let pkg_dep_refs : Array[Json] = []
    for dep_name in pkg.dependencies {
      pkg_dep_refs.push(Json::string("pkg:\{sanitize_bom_ref(dep_name)}"))
    }
    let dep_entry_fields : Array[(String, Json)] = [
      ("ref", Json::string(bom_ref)),
    ]
    if !pkg_dep_refs.is_empty() {
      dep_entry_fields.push(("dependsOn", Json::array(pkg_dep_refs)))
    }
    dependencies.push(obj(dep_entry_fields))
  }

  // Root component
  let root_comp_fields : Array[(String, Json)] = [
    ("type", Json::string("application")),
    ("bom-ref", Json::string(root_bom_ref)),
    ("name", Json::string(sbom.name)),
    ("version", Json::string(sbom.version)),
  ]
  match sbom.description {
    Some(desc) => root_comp_fields.push(("description", Json::string(desc)))
    None => ()
  }
  let root_component = obj(root_comp_fields)

  // Root dependency entry (inserted at front)
  let root_dep_entry_fields : Array[(String, Json)] = [
    ("ref", Json::string(root_bom_ref)),
  ]
  if !root_deps.is_empty() {
    root_dep_entry_fields.push(("dependsOn", Json::array(root_deps)))
  }
  let root_dep_entry = obj(root_dep_entry_fields)

  // Prepend root dep to dependencies array
  let all_deps : Array[Json] = [root_dep_entry]
  for dep in dependencies {
    all_deps.push(dep)
  }

  // Metadata
  let tool_obj = obj([
    ("vendor", Json::string("cogna-dev")),
    ("name", Json::string("cogna-dev/sbom")),
    ("version", Json::string("0.1.0")),
  ])
  let tools : Array[Json] = [tool_obj]
  let metadata = obj([
    ("timestamp", Json::string(sbom.created)),
    ("tools", Json::array(tools)),
    ("component", root_component),
  ])

  // Serial number placeholder (no UUID stdlib in MoonBit)
  let serial_number = "urn:uuid:00000000-0000-0000-0000-000000000000"

  let bom_fields : Array[(String, Json)] = [
    ("bomFormat", Json::string("CycloneDX")),
    ("specVersion", Json::string("1.5")),
    ("serialNumber", Json::string(serial_number)),
    ("version", Json::number(1.0)),
    ("metadata", metadata),
  ]
  if !components.is_empty() {
    bom_fields.push(("components", Json::array(components)))
  }
  if !all_deps.is_empty() {
    bom_fields.push(("dependencies", Json::array(all_deps)))
  }

  obj(bom_fields).stringify(indent=2)
}
