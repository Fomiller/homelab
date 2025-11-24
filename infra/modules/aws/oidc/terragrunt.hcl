include "root" { path = find_in_parent_folders() }

dependency "s3" {
    config_path = "../s3"
    mock_outputs_merge_strategy_with_state = "shallow"
    mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy", "init"]
    mock_outputs = {
        s3_bucket_name_homelab_oidc = "fomiller-MOCK-homelab-oidc"
        s3_object_id_homelab_openid_configuration = "MOCK-object"
    }
}


inputs = {
    s3_bucket_name_homelab_oidc = dependency.s3.outputs.s3_bucket_name_homelab_oidc
    s3_object_id_homelab_openid_configuration = dependency.s3.outputs.s3_object_id_homelab_openid_configuration
}
