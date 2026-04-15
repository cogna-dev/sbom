///|
/// Sanitize a string to be a valid SPDX ID component.
/// Replaces non-alphanumeric, non-hyphen, non-dot characters with hyphens.
fn sanitize_spdx_id(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    if ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '-' || ch == '.' {
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
/// Export an SBOM to SPDX 2.3 JSON format.
pub fn to_spdx(sbom : @types.Sbom) -> String {
  let project_spdx_id = "SPDXRef-Package-\{sanitize_spdx_id(sbom.name)}"
  let root_spdx_id = "SPDXRef-DOCUMENT"
  let doc_namespace = "https://spdx.org/spdxdocs/\{sbom.name.to_lower()}-\{sbom.version}"

  let packages : Array[Json] = []
  let relationships : Array[Json] = []

  // Root package (the project itself)
  let root_pkg_fields : Array[(String, Json)] = [
    ("SPDXID", Json::string(project_spdx_id)),
    ("name", Json::string(sbom.name)),
    ("versionInfo", Json::string(sbom.version)),
    ("downloadLocation", Json::string("NOASSERTION")),
    ("filesAnalyzed", Json::boolean(false)),
    ("copyrightText", Json::string("NOASSERTION")),
    ("licenseConcluded", Json::string("NOASSERTION")),
  ]
  match sbom.description {
    Some(desc) => root_pkg_fields.push(("description", Json::string(desc)))
    None => ()
  }
  packages.push(obj(root_pkg_fields))

  // Document DESCRIBES root package
  relationships.push(
    obj([
      ("spdxElementId", Json::string(root_spdx_id)),
      ("relationshipType", Json::string("DESCRIBES")),
      ("relatedSpdxElement", Json::string(project_spdx_id)),
    ]),
  )

  // Dependency packages
  for pkg in sbom.packages {
    let pkg_spdx_id = "SPDXRef-Package-\{sanitize_spdx_id(pkg.pkg_type)}-\{sanitize_spdx_id(pkg.name)}"
    let purl = pkg.to_purl()

    let ext_refs : Array[Json] = [
      obj([
        ("referenceCategory", Json::string("PACKAGE-MANAGER")),
        ("referenceType", Json::string("purl")),
        ("referenceLocator", Json::string(purl)),
      ]),
    ]

    let checksums : Array[Json] = []
    match pkg.checksum {
      Some(cs) =>
        checksums.push(
          obj([
            ("algorithm", Json::string("SHA256")),
            ("checksumValue", Json::string(cs)),
          ]),
        )
      None => ()
    }

    let download_loc = match pkg.homepage {
      Some(hp) => Json::string(hp)
      None => Json::string("NOASSERTION")
    }
    let pkg_fields : Array[(String, Json)] = [
      ("SPDXID", Json::string(pkg_spdx_id)),
      ("name", Json::string(pkg.name)),
      ("versionInfo", Json::string(pkg.version())),
      ("downloadLocation", download_loc),
      ("filesAnalyzed", Json::boolean(false)),
      ("copyrightText", Json::string("NOASSERTION")),
      ("externalRefs", Json::array(ext_refs)),
    ]
    if !checksums.is_empty() {
      pkg_fields.push(("checksums", Json::array(checksums)))
    }
    match pkg.homepage {
      Some(hp) => pkg_fields.push(("homepage", Json::string(hp)))
      None => ()
    }
    match pkg.description {
      Some(desc) => pkg_fields.push(("description", Json::string(desc)))
      None => ()
    }
    match pkg.license {
      Some(lic) => {
        pkg_fields.push(("licenseDeclared", Json::string(lic)))
        pkg_fields.push(("licenseConcluded", Json::string(lic)))
      }
      None => pkg_fields.push(("licenseConcluded", Json::string("NOASSERTION")))
    }
    packages.push(obj(pkg_fields))

    relationships.push(
      obj([
        ("spdxElementId", Json::string(project_spdx_id)),
        ("relationshipType", Json::string("DEPENDS_ON")),
        ("relatedSpdxElement", Json::string(pkg_spdx_id)),
      ]),
    )
  }

  let creators : Array[Json] = [Json::string("Tool: \{sbom.creator_tool}")]
  let creation_info = obj([
    ("created", Json::string(sbom.created)),
    ("creators", Json::array(creators)),
    ("licenseListVersion", Json::string("3.21")),
  ])

  let doc = obj([
    ("spdxVersion", Json::string("SPDX-2.3")),
    ("dataLicense", Json::string("CC0-1.0")),
    ("SPDXID", Json::string(root_spdx_id)),
    ("name", Json::string(sbom.name)),
    ("documentNamespace", Json::string(doc_namespace)),
    ("creationInfo", creation_info),
    ("packages", Json::array(packages)),
    ("relationships", Json::array(relationships)),
  ])

  doc.stringify(indent=2)
}
