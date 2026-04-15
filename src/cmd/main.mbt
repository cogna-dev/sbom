///|
/// CLI entry point for SBOM generation.
///
/// Reads JSON-encoded virtual filesystem from argv[1]:
///   { "ecosystem": "cargo"|"go"|"terraform", "files": { "path": "content", ... } }
///
/// Writes to stdout two JSON strings (one per line):
///   Line 1: SPDX 2.3 JSON
///   Line 2: CycloneDX 1.5 JSON
fn main {
  let args = @env.args()
  // args[0] is the program name; args[1] is the JSON payload
  if args.length() < 2 {
    println("ERROR: expected JSON payload as first argument")
    return
  }
  let input = args[1]
  let parsed = try? @json.parse(input)
  match parsed {
    Err(e) => {
      println("ERROR: failed to parse JSON argument: \{e}")
      return
    }
    Ok(json) => {
      let ecosystem = get_string_field(json, "ecosystem")
      let files_json = get_object_field(json, "files")
      let files : Map[String, String] = {}
      for key, val in files_json {
        match val {
          String(s) => files[key] = s
          _ => ()
        }
      }
      let project = match ecosystem {
        "cargo" => {
          let cargo_toml = match files.get("Cargo.toml") {
            Some(c) => c
            None => {
              println("ERROR: Cargo.toml not found in files")
              return
            }
          }
          let lock = files.get("Cargo.lock")
          @lib.scan_cargo(".", cargo_toml, lock)
        }
        "go" => {
          let go_mod = match files.get("go.mod") {
            Some(c) => c
            None => {
              println("ERROR: go.mod not found in files")
              return
            }
          }
          let go_sum = files.get("go.sum")
          @lib.scan_go(".", go_mod, go_sum)
        }
        "terraform" => {
          let tf_files : Array[(String, String)] = []
          for path, content in files {
            if path.has_suffix(".tf") {
              tf_files.push((path, content))
            }
          }
          let lock = files.get(".terraform.lock.hcl")
          @lib.scan_terraform(".", tf_files, lock)
        }
        _ => {
          println("ERROR: unknown ecosystem: \{ecosystem}")
          return
        }
      }
      let sbom = project.to_sbom()
      println(@lib.export_spdx(sbom))
      println(@lib.export_cyclonedx(sbom))
    }
  }
}

///|
fn get_string_field(json : Json, key : String) -> String {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn get_object_field(json : Json, key : String) -> Map[String, Json] {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(Object(inner)) => inner
        _ => {}
      }
    _ => {}
  }
}
