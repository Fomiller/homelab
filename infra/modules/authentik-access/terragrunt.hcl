# Apply this module only after infra/modules/authentik has been applied AND
# k8s/apps/authentik is up and reachable at https://authentik.<zone_name> —
# the authentik provider below authenticates against that live instance's API.
generate "provider" {
  path      = "_.provider.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      email       = "forrestmillerj@gmail.com"
      managedWith = "terraform"
    }
  }
}
EOF
}

generate "versions" {
  path      = "_.versions.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">=1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=5.0.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = ">=2026.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">=3.6.0"
    }
  }
}
EOF
}

remote_state {
  backend = "s3"
  config = {
    encrypt               = true
    disable_bucket_update = true
    bucket                = "fomiller-terraform-state-dev"
    key                   = "homelab/authentik-access/terraform.tfstate"
    region                = "us-east-1"
    dynamodb_table        = "fomiller-terraform-state-lock"
  }
  generate = {
    path      = "_.backend.gen.tf"
    if_exists = "overwrite_terragrunt"
  }
}
