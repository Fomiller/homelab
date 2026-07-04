# Root Terragrunt config. Every unit includes this. It generates the backend,
# provider, versions, and common variables, so each unit's own terragrunt.hcl
# only needs `include "root"` + `inputs`.
#
# Every unit is single-provider after the provider-tightening pass (aws units
# only use aws, cloudflare units only cloudflare, etc.), so which provider
# block/required_providers entry to generate is derived from the path itself:
# path_relative_to_include() is "<env>/<provider>/<scope>/<unit...>", segment
# [1] is the provider. (Terragrunt doesn't support a child `generate` block
# silently overriding a same-named one inherited from an include — it's a
# hard error — so this has to be one conditional generator here rather than
# per-unit overrides.)

locals {
  service_vars = read_terragrunt_config(find_in_parent_folders("service.hcl"))
  tag_vars     = read_terragrunt_config(find_in_parent_folders("tags.hcl"))
  version_vars = read_terragrunt_config(find_in_parent_folders("version.hcl"))
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  environment = local.account_vars.locals.environment
  region      = local.account_vars.locals.region

  bucket = "fomiller-terraform-state-${local.environment}"

  # path_relative_to_include() is "<env>/<provider>/<scope>/<unit...>";
  # segment [1] is the provider.
  path_parts = split("/", path_relative_to_include())
  provider   = local.path_parts[1]

  # Fail fast with a readable message if the derived provider isn't one we
  # configure below (tobool() on a non-"true"/"false" string raises an error
  # carrying that message).
  _assert_provider = contains(keys(local.provider_versions), local.provider) ? true : tobool(
    "unknown provider '${local.provider}' from path '${path_relative_to_include()}'; expected one of ${join(", ", keys(local.provider_versions))}"
  )

  # required_providers entry per provider. Every unit also gets `random`
  # (cheap, several units across providers use it for generated secrets).
  provider_versions = {
    aws = {
      source  = "hashicorp/aws"
      version = local.version_vars.locals.aws_provider_version
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">=5.0.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = ">=2026.2.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">=0.7.0"
    }
  }

  # The generated `provider` block body per provider. authentik is empty —
  # authentik/global/access configures it directly in main.tf, since its
  # url/token come from a computed local/dependency input, not something a
  # static generated block can express.
  provider_blocks = {
    aws = <<-EOT
      provider "aws" {
        region = "${local.region}"
        default_tags {
          tags = ${jsonencode(local.tag_vars.locals.default_tags)}
        }
      }
    EOT
    cloudflare = <<-EOT
      provider "cloudflare" {
        api_token = var.cloudflare_api_token
      }
    EOT
    authentik = ""
    talos = <<-EOT
      provider "talos" {}
    EOT
  }
}

remote_state {
  backend = "s3"
  config = {
    encrypt               = true
    disable_bucket_update = true
    bucket                = local.bucket
    # <repo>/<env>/<provider>/<scope>/<unit>/terraform.tfstate
    key            = "${local.service_vars.locals.repo_name}/${path_relative_to_include()}/terraform.tfstate"
    region         = local.region
    dynamodb_table = "fomiller-terraform-state-lock"
  }
  generate = {
    path      = "_.backend.gen.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "_.provider.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = local.provider_blocks[local.provider]
}

generate "versions" {
  path      = "_.versions.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = "${local.version_vars.locals.terraform_version}"
      required_providers {
        ${local.provider} = {
          source  = "${local.provider_versions[local.provider].source}"
          version = "${local.provider_versions[local.provider].version}"
        }
        random = {
          source  = "hashicorp/random"
          version = ">=3.6.0"
        }
      }
    }
  EOF
}

generate "variables" {
  path      = "_.variables.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    variable "environment" {
      type    = string
      default = "${local.environment}"
    }

    variable "app_prefix" {
      type    = string
      default = "${local.service_vars.locals.app_prefix}"
    }

    variable "namespace" {
      type    = string
      default = "${local.service_vars.locals.namespace}"
    }

    variable "asset_name" {
      type = string
    }
  EOF
}
