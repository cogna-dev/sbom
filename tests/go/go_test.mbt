///|
let go_mod : String =
  #|module github.com/example/sample-go-app
  #|
  #|go 1.21
  #|
  #|require (
  #|	github.com/gin-gonic/gin v1.9.1
  #|	github.com/go-redis/redis/v8 v8.11.5
  #|	github.com/jmoiron/sqlx v1.3.5
  #|	github.com/lib/pq v1.10.9
  #|	go.uber.org/zap v1.26.0
  #|	golang.org/x/crypto v0.17.0
  #|)
  #|
  #|require (
  #|	github.com/bytedance/sonic v1.9.1 // indirect
  #|	github.com/chenzhuoyu/base64x v0.0.0-20221115062448-fe3a3abad311 // indirect
  #|	github.com/gabriel-vasile/mimetype v1.4.2 // indirect
  #|	github.com/gin-contrib/sse v0.1.0 // indirect
  #|	github.com/go-playground/locales v0.14.1 // indirect
  #|	github.com/go-playground/universal-translator v0.18.1 // indirect
  #|	github.com/go-playground/validator/v10 v10.15.5 // indirect
  #|	github.com/goccy/go-json v0.10.2 // indirect
  #|	github.com/klauspost/cpuid/v2 v2.2.5 // indirect
  #|	github.com/leodido/go-urn v1.2.4 // indirect
  #|	github.com/mattn/go-isatty v0.0.19 // indirect
  #|	github.com/pelletier/go-toml/v2 v2.0.8 // indirect
  #|	github.com/twitchyliquid64/golang-asm v0.15.1 // indirect
  #|	github.com/ugorji/go/codec v1.2.11 // indirect
  #|	go.uber.org/multierr v1.11.0 // indirect
  #|	golang.org/x/arch v0.3.0 // indirect
  #|	golang.org/x/net v0.17.0 // indirect
  #|	golang.org/x/sys v0.15.0 // indirect
  #|	golang.org/x/text v0.14.0 // indirect
  #|	google.golang.org/protobuf v1.31.0 // indirect
  #|	gopkg.in/yaml.v3 v3.0.1 // indirect
  #|)

///|
let go_sum : String =
  #|github.com/gin-gonic/gin v1.9.1 h1:4idEAncQnU5cB7BeOkPtxjfCSye0AAm1R0RVIqJ+Jmg=
  #|github.com/go-redis/redis/v8 v8.11.5 h1:AcZZR7igkdvfVmQTPnu9WE37LRrO/YrBH5zWyjDC0oI=
  #|github.com/jmoiron/sqlx v1.3.5 h1:vFFPA71p1o5gAeqtEAwLU4dnX2napprKtHr7PYIcN3g=
  #|github.com/lib/pq v1.10.9 h1:YXG7RB+JIjhP29X+OtkiDnYaXQwpS3htCVWkH1EQZUE=
  #|go.uber.org/zap v1.26.0 h1:sI7k6L95XOKS281NhVKOFCUDIr/uLAJpLV4Blz+HyhQ=
  #|golang.org/x/crypto v0.17.0 h1:r8bRNjWL3GshPW3gkd+RpvzWrZAwPS49OmTGZ/uhM4k=

///|
// The parser splits module paths into (namespace, name) using the last '/' segment.
// e.g. "github.com/gin-gonic/gin" → name="gin", ns="github.com/gin-gonic"
// Project name is the last segment of the module path.

///|
test "go: module path becomes project name (last segment)" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  inspect(project.name, content="sample-go-app")
}

///|
test "go: project type is Go" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  inspect(project.project_type.to_string(), content="go")
}

///|
test "go: direct dependencies are detected" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let all_pkgs = project.all_packages()
  // Names are the last path segment of the module path
  let names : Array[String] = all_pkgs.map(fn(p) { p.name })
  inspect(names.contains("gin"), content="true")
  inspect(names.contains("sqlx"), content="true")
  inspect(names.contains("pq"), content="true")
  inspect(names.contains("zap"), content="true")
  inspect(names.contains("crypto"), content="true")
}

///|
test "go: indirect dependencies are detected" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let all_pkgs = project.all_packages()
  let names : Array[String] = all_pkgs.map(fn(p) { p.name })
  inspect(names.contains("sonic"), content="true")
  inspect(names.contains("yaml.v3"), content="true")
  inspect(names.contains("multierr"), content="true")
}

///|
test "go: resolved versions are correct" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let all_pkgs = project.all_packages()
  // Filter by name (last path segment) and namespace
  let gin = all_pkgs.filter(fn(p) { p.name == "gin" })
  inspect(gin.length() > 0, content="true")
  inspect(gin[0].version(), content="1.9.1")
}

///|
test "go: PURL type is golang" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let all_pkgs = project.all_packages()
  let gin = all_pkgs.filter(fn(p) { p.name == "gin" })
  inspect(gin.length() > 0, content="true")
  inspect(gin[0].to_purl().has_prefix("pkg:golang/"), content="true")
}

///|
test "go: PURL contains version" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let all_pkgs = project.all_packages()
  let zap = all_pkgs.filter(fn(p) { p.name == "zap" })
  inspect(zap.length() > 0, content="true")
  inspect(zap[0].to_purl(), content="pkg:golang/go.uber.org/zap@1.26.0")
}

///|
test "go: checksum from go.sum (h1 hash)" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let all_pkgs = project.all_packages()
  let gin = all_pkgs.filter(fn(p) { p.name == "gin" })
  inspect(gin.length() > 0, content="true")
  inspect(gin[0].checksum is Some(_), content="true")
}

///|
test "go: parsing without go.sum still works" {
  let project = @go_pkg.parse_go_project(".", go_mod, None)
  let all_pkgs = project.all_packages()
  inspect(all_pkgs.length() > 0, content="true")
}

///|
test "go: total dependency count" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let all_pkgs = project.all_packages()
  inspect(all_pkgs.length() >= 6, content="true")
}

///|
test "go: SPDX export contains required fields" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let sbom = project.to_sbom()
  let spdx = @spdx.to_spdx(sbom)
  inspect(spdx.contains("\"spdxVersion\": \"SPDX-2.3\""), content="true")
  inspect(spdx.contains("\"dataLicense\": \"CC0-1.0\""), content="true")
  inspect(spdx.contains("\"packages\""), content="true")
  inspect(spdx.contains("\"relationships\""), content="true")
}

///|
test "go: SPDX export contains gin package with PURL" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let sbom = project.to_sbom()
  let spdx = @spdx.to_spdx(sbom)
  inspect(spdx.contains("gin"), content="true")
  inspect(spdx.contains("pkg:golang/"), content="true")
}

///|
test "go: CycloneDX export contains required fields" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let sbom = project.to_sbom()
  let cdx = @cyclonedx.to_cyclonedx(sbom)
  inspect(cdx.contains("\"bomFormat\": \"CycloneDX\""), content="true")
  inspect(cdx.contains("\"specVersion\": \"1.5\""), content="true")
  inspect(cdx.contains("\"components\""), content="true")
}

///|
test "go: CycloneDX contains purl in components" {
  let project = @go_pkg.parse_go_project(".", go_mod, Some(go_sum))
  let sbom = project.to_sbom()
  let cdx = @cyclonedx.to_cyclonedx(sbom)
  inspect(cdx.contains("pkg:golang/"), content="true")
}
