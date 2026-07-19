# cloudflare units. dns depends on tunnels (same stack) and aws/ses — a
# cross-provider edge, so that half of the autoinclude reads config_path
# from values.ses_path, which the parent stack (live/dev/terragrunt.stack.hcl)
# computes from stack.aws.path and threads down (unit.*.path only resolves
# within this file's own scope).

locals {
  units_path = find_in_parent_folders("units")
}

unit "tunnels" {
  source                  = "${local.units_path}/cloudflare/global/tunnels"
  path                    = "tunnels"
  no_dot_terragrunt_stack = true
}

unit "dns" {
  source                  = "${local.units_path}/cloudflare/global/dns"
  path                    = "dns"
  no_dot_terragrunt_stack = true

  autoinclude {
    dependency "tunnels" {
      config_path                             = unit.tunnels.path
      mock_outputs_merge_strategy_with_state   = "shallow"
      mock_outputs_allowed_terraform_commands  = ["validate", "plan", "apply", "destroy", "init"]
      mock_outputs = {
        tunnel_id = "MOCK-tunnel-id"
      }
    }
    # Cross-provider: ses_path comes from the parent stack's `values`
    # (computed as stack.aws.path + "/ses").
    dependency "ses" {
      config_path                             = values.ses_path
      mock_outputs_merge_strategy_with_state   = "shallow"
      mock_outputs_allowed_terraform_commands  = ["validate", "plan", "apply", "destroy", "init"]
      mock_outputs = {
        verification_token = "MOCK-verification-token"
        dkim_tokens         = ["MOCK-dkim-1", "MOCK-dkim-2", "MOCK-dkim-3"]
      }
    }
    inputs = {
      tunnel_id           = dependency.tunnels.outputs.tunnel_id
      verification_token = dependency.ses.outputs.verification_token
      dkim_tokens         = dependency.ses.outputs.dkim_tokens
    }
  }
}
