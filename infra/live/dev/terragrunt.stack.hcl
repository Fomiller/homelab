locals {
  stacks_path  = find_in_parent_folders("stacks")
  account_vars = read_terragrunt_config("${get_terragrunt_dir()}/account.hcl")
}

# aws and cloudflare each need one specific unit from the other stack
# (secrets<-tunnels, dns<-ses). unit.<name>.path/stack.<name>.path only
# resolve for components declared in the same stack file, so the specific
# sibling-stack unit path is computed here (where both stacks are visible)
# and threaded down through `values` — see the "Depending on a stack" /
# "Limitations" sections of https://docs.terragrunt.com/reference/hcl/blocks/#autoinclude.

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
