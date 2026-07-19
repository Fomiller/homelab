# authentik units. access depends on aws/secrets — a cross-provider edge, so
# its autoinclude reads config_path from values.secrets_path, which the
# parent stack (live/dev/terragrunt.stack.hcl) computes from stack.aws.path
# and threads down (unit.*.path only resolves within this file's own scope).

locals {
  units_path = find_in_parent_folders("units")
}

unit "access" {
  source                  = "${local.units_path}/authentik/global/access"
  path                    = "access"
  no_dot_terragrunt_stack = true

  autoinclude {
    # Cross-provider: secrets_path comes from the parent stack's `values`
    # (computed as stack.aws.path + "/secrets").
    dependency "secrets" {
      config_path                             = values.secrets_path
      mock_outputs_merge_strategy_with_state   = "shallow"
      mock_outputs_allowed_terraform_commands  = ["validate", "plan", "apply", "destroy", "init"]
      mock_outputs = {
        bootstrap_token = "MOCK-bootstrap-token"
        user_metadata = {
          forrest = {
            email = "forrestmillerj@gmail.com"
            name  = "Forrest Miller"
            admin = true
          }
          grayson = {
            email = "millergrayson0@gmail.com"
            name  = "Grayson Miller"
            admin = false
          }
        }
        user_passwords = {
          forrest = "MOCK-forrest-password"
          grayson = "MOCK-grayson-password"
        }
      }
    }
    inputs = {
      authentik_bootstrap_token = dependency.secrets.outputs.bootstrap_token
      user_metadata             = dependency.secrets.outputs.user_metadata
      user_passwords            = dependency.secrets.outputs.user_passwords
    }
  }
}
