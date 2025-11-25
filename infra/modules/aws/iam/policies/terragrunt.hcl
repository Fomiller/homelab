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
        iam_role_name_loki = "FomillerLokiS3Access"
    }
}

dependency "s3" {
    config_path = "../../s3/"
    mock_outputs_merge_strategy_with_state = "shallow"
    mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy", "init"]
    mock_outputs = {
        s3_bucket_name_loki_chunks = "fomiller-MOCK-homelab-loki-chunks"
        s3_bucket_name_loki_ruler = "fomiller-MOCK-homelab-loki-ruler"
        s3_bucket_name_loki_admin = "fomiller-MOCK-homelab-loki-admin"
    }
}


inputs = {
    iam_role_name_external_secrets = dependency.roles.outputs.iam_role_name_external_secrets
    iam_role_name_doppler_operator = dependency.roles.outputs.iam_role_name_doppler_operator
    iam_role_name_loki = dependency.roles.outputs.iam_role_name_loki
    s3_bucket_name_loki_chunks = dependency.s3.outputs.s3_bucket_name_loki_chunks
    s3_bucket_name_loki_ruler = dependency.s3.outputs.s3_bucket_name_loki_ruler
    s3_bucket_name_loki_admin = dependency.s3.outputs.s3_bucket_name_loki_admin
}
