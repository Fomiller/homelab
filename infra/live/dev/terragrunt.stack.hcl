locals {
  stacks_path  = find_in_parent_folders("stacks")
  account_vars = read_terragrunt_config("${get_terragrunt_dir()}/account.hcl")
}

stack "global" {
  source                  = "${local.stacks_path}/global"
  path                    = "."
  no_dot_terragrunt_stack = true

  values = {
    environment = local.account_vars.locals.environment
  }
}
