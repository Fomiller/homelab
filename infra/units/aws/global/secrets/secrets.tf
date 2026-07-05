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

resource "aws_secretsmanager_secret" "tailscale_operator_creds" {
  name       = "${var.environment}/${var.namespace}/${var.app_prefix}/tailscale-operator-creds"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "tailscale_operator_creds" {
  secret_id = aws_secretsmanager_secret.tailscale_operator_creds.id
  secret_string = jsonencode(tomap({
    "client_id"     = var.tailscale_operator_client_id
    "client_secret" = var.tailscale_operator_client_secret
    }
  ))
}

# Consumed by k8s/apps/homepage's ExternalSecret (aws-clustersecretstore),
# which materializes it as the doppler-token-sa Secret that homepage's own
# doppler-homepage SecretStore reads to reach the "homepage" Doppler project
# directly. Key name "dopplerToken" matches what the ESO Doppler provider
# expects in secretRef.dopplerToken.key.
resource "aws_secretsmanager_secret" "doppler_sa_token" {
  name       = "${var.environment}/${var.namespace}/${var.app_prefix}/doppler-token-sa"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "doppler_sa_token" {
  secret_id = aws_secretsmanager_secret.doppler_sa_token.id
  secret_string = jsonencode({
    dopplerToken = var.eso_doppler_sa_token
  })
}
