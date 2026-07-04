# Single flat stack for every unit homelab deploys. Not split per-provider:
# dependencies here genuinely cross provider boundaries (aws/secrets needs a
# cloudflare/tunnels output, cloudflare/dns needs both cloudflare/tunnels and
# aws/ses outputs, authentik/access needs an aws/secrets output), and
# Terragrunt Stacks can't target a `dependency` at a whole stack — only at a
# unit (https://docs.terragrunt.com/features/stacks/explicit/#known-limitations-of-explicit-stacks).
# One flat stack with `autoinclude` blocks on the units that need them is the
# clean way to express that graph.

locals {
  units_path = find_in_parent_folders("units")
}

# ---- aws -------------------------------------------------------------

unit "s3" {
  source                  = "${local.units_path}/aws/global/s3"
  path                    = "aws/global/s3"
  no_dot_terragrunt_stack = true
}

unit "oidc" {
  source                  = "${local.units_path}/aws/global/oidc"
  path                    = "aws/global/oidc"
  no_dot_terragrunt_stack = true

  autoinclude {
    dependency "s3" {
      config_path                             = unit.s3.path
      mock_outputs_merge_strategy_with_state   = "shallow"
      mock_outputs_allowed_terraform_commands  = ["validate", "plan", "apply", "destroy", "init"]
      mock_outputs = {
        s3_bucket_name_homelab_oidc                = "fomiller-MOCK-homelab-oidc"
        s3_object_id_homelab_openid_configuration = "MOCK-object"
      }
    }
    inputs = {
      s3_bucket_name_homelab_oidc                = dependency.s3.outputs.s3_bucket_name_homelab_oidc
      s3_object_id_homelab_openid_configuration = dependency.s3.outputs.s3_object_id_homelab_openid_configuration
    }
  }
}

unit "iam_roles" {
  source                  = "${local.units_path}/aws/global/iam/roles"
  path                    = "aws/global/iam/roles"
  no_dot_terragrunt_stack = true

  autoinclude {
    dependency "s3" {
      config_path                            = unit.s3.path
      mock_outputs_merge_strategy_with_state  = "shallow"
      mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy", "init"]
      mock_outputs = {
        s3_bucket_name_homelab_oidc = "fomiller-MOCK-homelab-oidc"
      }
    }
    inputs = {
      s3_bucket_name_homelab_oidc = dependency.s3.outputs.s3_bucket_name_homelab_oidc
    }
  }
}

unit "iam_policies" {
  source                  = "${local.units_path}/aws/global/iam/policies"
  path                    = "aws/global/iam/policies"
  no_dot_terragrunt_stack = true

  autoinclude {
    dependency "roles" {
      config_path                             = unit.iam_roles.path
      mock_outputs_merge_strategy_with_state   = "shallow"
      mock_outputs_allowed_terraform_commands  = ["validate", "plan", "apply", "destroy", "init"]
      mock_outputs = {
        iam_role_name_external_secrets = "FomillerExternalSecretsOperator"
        iam_role_name_doppler_operator = "FomillerDopplerOperator"
        iam_role_name_loki             = "FomillerLokiS3Access"
      }
    }
    dependency "s3" {
      config_path                             = unit.s3.path
      mock_outputs_merge_strategy_with_state   = "shallow"
      mock_outputs_allowed_terraform_commands  = ["validate", "plan", "apply", "destroy", "init"]
      mock_outputs = {
        s3_bucket_name_loki_chunks = "fomiller-MOCK-homelab-loki-chunks"
        s3_bucket_name_loki_ruler  = "fomiller-MOCK-homelab-loki-ruler"
        s3_bucket_name_loki_admin  = "fomiller-MOCK-homelab-loki-admin"
      }
    }
    inputs = {
      iam_role_name_external_secrets = dependency.roles.outputs.iam_role_name_external_secrets
      iam_role_name_doppler_operator = dependency.roles.outputs.iam_role_name_doppler_operator
      iam_role_name_loki             = dependency.roles.outputs.iam_role_name_loki
      s3_bucket_name_loki_chunks     = dependency.s3.outputs.s3_bucket_name_loki_chunks
      s3_bucket_name_loki_ruler      = dependency.s3.outputs.s3_bucket_name_loki_ruler
      s3_bucket_name_loki_admin      = dependency.s3.outputs.s3_bucket_name_loki_admin
    }
  }
}

unit "ses" {
  source                  = "${local.units_path}/aws/global/ses"
  path                    = "aws/global/ses"
  no_dot_terragrunt_stack = true
}

# ---- cloudflare --------------------------------------------------------

unit "tunnels" {
  source                  = "${local.units_path}/cloudflare/global/tunnels"
  path                    = "cloudflare/global/tunnels"
  no_dot_terragrunt_stack = true
}

unit "dns" {
  source                  = "${local.units_path}/cloudflare/global/dns"
  path                    = "cloudflare/global/dns"
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
    dependency "ses" {
      config_path                             = unit.ses.path
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

# ---- aws (continued — depends on a cloudflare unit above) --------------

unit "secrets" {
  source                  = "${local.units_path}/aws/global/secrets"
  path                    = "aws/global/secrets"
  no_dot_terragrunt_stack = true

  autoinclude {
    dependency "tunnels" {
      config_path                             = unit.tunnels.path
      mock_outputs_merge_strategy_with_state   = "shallow"
      mock_outputs_allowed_terraform_commands  = ["validate", "plan", "apply", "destroy", "init"]
      mock_outputs = {
        tunnel_token = "MOCK-tunnel-token"
      }
    }
    inputs = {
      tunnel_token = dependency.tunnels.outputs.tunnel_token
    }
  }
}

# ---- authentik -----------------------------------------------------------

unit "access" {
  source                  = "${local.units_path}/authentik/global/access"
  path                    = "authentik/global/access"
  no_dot_terragrunt_stack = true

  autoinclude {
    dependency "secrets" {
      config_path                             = unit.secrets.path
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

# ---- talos -----------------------------------------------------------

unit "cluster" {
  source                  = "${local.units_path}/talos/global/cluster"
  path                    = "talos/global/cluster"
  no_dot_terragrunt_stack = true
}
