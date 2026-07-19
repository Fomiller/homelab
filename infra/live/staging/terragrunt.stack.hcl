# Scaffold only — see account.hcl. CI never runs `terragrunt`/`terragrunt
# stack` commands against this directory.
locals {
  stacks_path  = find_in_parent_folders("stacks")
  account_vars = read_terragrunt_config("${get_terragrunt_dir()}/account.hcl")
}

stack "aws" {
  source                  = "${local.stacks_path}/aws/global"
  path                    = "aws/global"
  no_dot_terragrunt_stack = true

  values = {
    environment  = local.account_vars.locals.environment
    tunnels_path = "${stack.cloudflare.path}/tunnels"
  }
}

stack "cloudflare" {
  source                  = "${local.stacks_path}/cloudflare/global"
  path                    = "cloudflare/global"
  no_dot_terragrunt_stack = true

  values = {
    environment = local.account_vars.locals.environment
    ses_path    = "${stack.aws.path}/ses"
  }
}

stack "authentik" {
  source                  = "${local.stacks_path}/authentik/global"
  path                    = "authentik/global"
  no_dot_terragrunt_stack = true

  values = {
    environment  = local.account_vars.locals.environment
    secrets_path = "${stack.aws.path}/secrets"
  }
}

stack "talos" {
  source                  = "${local.stacks_path}/talos/global"
  path                    = "talos/global"
  no_dot_terragrunt_stack = true

  values = {
    environment = local.account_vars.locals.environment
  }
}
