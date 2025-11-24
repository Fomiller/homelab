resource "aws_secretsmanager_secret" "doppler_operator_creds" {
  name       = "${var.environment}/${var.namespace}/${var.app_prefix}/doppler-operator-creds"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "doppler_operator_creds" {
  secret_id = aws_secretsmanager_secret.doppler_operator_creds.id
  secret_string = jsonencode(tomap({
    "client_id"     = var.doppler_operator_client_id
    "client_secret" = var.doppler_operator_client_secret
    }
  ))
}
