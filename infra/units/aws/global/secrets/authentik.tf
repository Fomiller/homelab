# Cookie-signing/unique-user-ID secret — must never change after the first
# install, or every session and user ID gets invalidated.
resource "random_password" "secret_key" {
  length  = 60
  special = false
}

# Password for authentik's own "authentik" postgres user.
resource "random_password" "postgresql_password" {
  length  = 32
  special = false
}

# Bitnami's postgresql subchart also provisions the "postgres" superuser
# alongside the "authentik" app user — both live in the same existingSecret
# so the chart doesn't have to generate either on its own.
resource "random_password" "postgresql_admin_password" {
  length  = 32
  special = false
}

resource "random_password" "bootstrap_password" {
  length  = 32
  special = false
}

# Lets authentik/global/access authenticate to the authentik API once the
# server is up, without a manual UI token step.
resource "random_password" "bootstrap_token" {
  length  = 60
  special = false
}

# Consumed by k8s/apps/authentik's ExternalSecret, same
# ClusterSecretStore/aws-clustersecretstore pattern as the cloudflare tunnel
# and tailscale operator creds. Key names match what both the authentik
# server/worker env vars and the bundled bitnami postgresql chart's
# existingSecret expect (`password` / `postgres-password`).
resource "aws_secretsmanager_secret" "authentik_secrets" {
  name       = "${var.environment}/fomiller/homelab/authentik-secrets"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "authentik_secrets" {
  secret_id = aws_secretsmanager_secret.authentik_secrets.id
  secret_string = jsonencode({
    secret_key          = random_password.secret_key.result
    password            = random_password.postgresql_password.result
    "postgres-password" = random_password.postgresql_admin_password.result
    bootstrap_password  = random_password.bootstrap_password.result
    bootstrap_token     = random_password.bootstrap_token.result
    bootstrap_email     = var.bootstrap_email
  })
}
