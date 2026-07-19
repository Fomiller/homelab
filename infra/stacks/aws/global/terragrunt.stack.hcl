# aws units. iam_policies depends on both s3 and iam_roles; oidc depends on
# s3. secrets depends on cloudflare/tunnels — a cross-provider edge, so its
# autoinclude reads config_path from values.tunnels_path, which the parent
# stack (live/dev/terragrunt.stack.hcl) computes from stack.cloudflare.path
# and threads down (unit.*.path only resolves within this file's own scope).

locals {
  units_path = find_in_parent_folders("units")
}

unit "s3" {
  source                  = "${local.units_path}/aws/global/s3"
  path                    = "s3"
  no_dot_terragrunt_stack = true
}

unit "oidc" {
  source                  = "${local.units_path}/aws/global/oidc"
  path                    = "oidc"
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
  path                    = "iam/roles"
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
  path                    = "iam/policies"
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
  path                    = "ses"
  no_dot_terragrunt_stack = true
}

unit "secrets" {
  source                  = "${local.units_path}/aws/global/secrets"
  path                    = "secrets"
  no_dot_terragrunt_stack = true

  autoinclude {
    # Cross-provider: tunnels_path comes from the parent stack's `values`
    # (computed as stack.cloudflare.path + "/tunnels").
    dependency "tunnels" {
      config_path                             = values.tunnels_path
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
