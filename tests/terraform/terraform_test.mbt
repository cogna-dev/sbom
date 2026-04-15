///|
let main_tf : String =
  #|terraform {
  #|  required_version = ">= 1.5.0"
  #|
  #|  required_providers {
  #|    aws = {
  #|      source  = "hashicorp/aws"
  #|      version = "~> 5.31"
  #|    }
  #|    random = {
  #|      source  = "hashicorp/random"
  #|      version = "~> 3.6"
  #|    }
  #|    tls = {
  #|      source  = "hashicorp/tls"
  #|      version = "~> 4.0"
  #|    }
  #|  }
  #|}

///|
let terraform_lock : String =
  #|provider "registry.terraform.io/hashicorp/aws" {
  #|  version     = "5.31.0"
  #|  constraints = "~> 5.31"
  #|  hashes = [
  #|    "h1:oL5924DTbaEuGxvDsEnBHCdgRidE00ZFqPBPanXFMaE=",
  #|  ]
  #|}
  #|
  #|provider "registry.terraform.io/hashicorp/random" {
  #|  version     = "3.6.0"
  #|  constraints = "~> 3.6"
  #|  hashes = [
  #|    "h1:R5Ucn26riKIEijcsiom99GgMSjpGC0fsKEPRm3D5c/8=",
  #|  ]
  #|}
  #|
  #|provider "registry.terraform.io/hashicorp/tls" {
  #|  version     = "4.0.5"
  #|  constraints = "~> 4.0"
  #|  hashes = [
  #|    "h1:LWGTWAAnalyzedStringForTLSProvider4x=",
  #|  ]
  #|}

///|
test "terraform: project type is Terraform" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  inspect(project.project_type.to_string(), content="terraform")
}

///|
test "terraform: providers are detected from required_providers" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let all_pkgs = project.all_packages()
  let names : Array[String] = all_pkgs.map(fn(p) { p.name })
  inspect(names.contains("aws"), content="true")
  inspect(names.contains("random"), content="true")
  inspect(names.contains("tls"), content="true")
}

///|
test "terraform: resolved versions come from lock file" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let all_pkgs = project.all_packages()
  let aws = all_pkgs.filter(fn(p) { p.name == "aws" })
  inspect(aws.length() > 0, content="true")
  inspect(aws[0].version(), content="5.31.0")
}

///|
test "terraform: random provider resolved version" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let all_pkgs = project.all_packages()
  let random = all_pkgs.filter(fn(p) { p.name == "random" })
  inspect(random.length() > 0, content="true")
  inspect(random[0].version(), content="3.6.0")
}

///|
test "terraform: tls provider resolved version" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let all_pkgs = project.all_packages()
  let tls = all_pkgs.filter(fn(p) { p.name == "tls" })
  inspect(tls.length() > 0, content="true")
  inspect(tls[0].version(), content="4.0.5")
}

///|
test "terraform: PURL type is terraform" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let all_pkgs = project.all_packages()
  let aws = all_pkgs.filter(fn(p) { p.name == "aws" })
  inspect(aws.length() > 0, content="true")
  inspect(aws[0].to_purl().has_prefix("pkg:terraform/"), content="true")
}

///|
test "terraform: namespace reflects registry source" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let all_pkgs = project.all_packages()
  let aws = all_pkgs.filter(fn(p) { p.name == "aws" })
  inspect(aws.length() > 0, content="true")
  inspect(aws[0].ns is Some(_), content="true")
}

///|
test "terraform: parsing without lock file still detects providers" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    None,
  )
  let all_pkgs = project.all_packages()
  inspect(all_pkgs.length() > 0, content="true")
  let names : Array[String] = all_pkgs.map(fn(p) { p.name })
  inspect(names.contains("aws"), content="true")
}

///|
test "terraform: SPDX export is valid" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let sbom = project.to_sbom()
  let spdx = @spdx.to_spdx(sbom)
  inspect(spdx.contains("\"spdxVersion\": \"SPDX-2.3\""), content="true")
  inspect(spdx.contains("\"dataLicense\": \"CC0-1.0\""), content="true")
  inspect(spdx.contains("\"packages\""), content="true")
}

///|
test "terraform: SPDX contains aws provider entry" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let sbom = project.to_sbom()
  let spdx = @spdx.to_spdx(sbom)
  inspect(spdx.contains("\"aws\""), content="true")
  inspect(spdx.contains("5.31.0"), content="true")
}

///|
test "terraform: CycloneDX export is valid" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let sbom = project.to_sbom()
  let cdx = @cyclonedx.to_cyclonedx(sbom)
  inspect(cdx.contains("\"bomFormat\": \"CycloneDX\""), content="true")
  inspect(cdx.contains("\"specVersion\": \"1.5\""), content="true")
  inspect(cdx.contains("\"components\""), content="true")
}

///|
test "terraform: CycloneDX contains purl for aws" {
  let project = @terraform_pkg.parse_terraform_project(
    ".",
    [("main.tf", main_tf)],
    Some(terraform_lock),
  )
  let sbom = project.to_sbom()
  let cdx = @cyclonedx.to_cyclonedx(sbom)
  inspect(cdx.contains("pkg:terraform/"), content="true")
}
