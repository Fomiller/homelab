generate "provider" {
  path      = "_.provider.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "talos" {}
EOF
}

generate "versions" {
  path      = "_.versions.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">=1.3.0"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">=0.7.0"
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
    key                   = "homelab/talos/terraform.tfstate"
    region                = "us-east-1"
    dynamodb_table        = "fomiller-terraform-state-lock"
  }
  generate = {
    path      = "_.backend.gen.tf"
    if_exists = "overwrite_terragrunt"
  }
}
