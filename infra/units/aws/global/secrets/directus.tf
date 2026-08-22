# KEY identifies this Directus instance and SECRET signs its sessions and
# encrypts stored credentials, so both have to stay stable across restarts —
# that's why they live here instead of the chart's own random generator,
# which rolls on every render.
resource "random_uuid" "directus_key" {}

resource "random_password" "directus_secret" {
  length  = 64
  special = false
}

# Only used the first time Directus boots, to create the admin user. Changing
# it later does nothing; reset the password in the app instead.
resource "random_password" "directus_admin_password" {
  length  = 32
  special = false
}

# Consumed by k8s/apps/directus's ExternalSecret (aws-clustersecretstore).
# Key names match what the chart's deployment reads from the secret named in
# values.yaml applicationSecretName.
resource "aws_secretsmanager_secret" "directus_application_secret" {
  name       = "${var.environment}/fomiller/homelab/directus-application-secret"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "directus_application_secret" {
  secret_id = aws_secretsmanager_secret.directus_application_secret.id
  secret_string = jsonencode({
    "KEY"            = random_uuid.directus_key.result
    "SECRET"         = random_password.directus_secret.result
    "ADMIN_PASSWORD" = random_password.directus_admin_password.result
  })
}
