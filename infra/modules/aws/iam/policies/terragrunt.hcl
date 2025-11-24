include "root" {
  path = find_in_parent_folders()
}
dependency "roles" {
    config_path = "../roles"
    mock_outputs_merge_strategy_with_state = "shallow"
    mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy", "init"]
    mock_outputs = {
        iam_role_name_external_secrets = "FomillerExternalSecretsOperator"
        iam_role_name_doppler_operator = "FomillerDopplerOperator"
    }
}


inputs = {
    iam_role_name_external_secrets = dependency.roles.outputs.iam_role_name_external_secrets
    iam_role_name_doppler_operator = dependency.roles.outputs.iam_role_name_doppler_operator
}
