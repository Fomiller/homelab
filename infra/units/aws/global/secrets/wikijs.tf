# Password for the chart's bundled postgres:18 "postgres" user (default
# postgresqlUser — wiki.js uses a single DB role, unlike authentik's
# separate app/superuser split).
resource "random_password" "wikijs_postgresql_password" {
  length  = 32
  special = false
}

# Consumed by k8s/apps/wikijs's ExternalSecret (aws-clustersecretstore).
# Key names match the wiki chart's existingSecret defaults
# (postgresql-username / postgresql-password).
resource "aws_secretsmanager_secret" "wikijs_secrets" {
  name       = "${var.environment}/fomiller/homelab/wikijs-secrets"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "wikijs_secrets" {
  secret_id = aws_secretsmanager_secret.wikijs_secrets.id
  secret_string = jsonencode({
    "postgresql-username" = "postgres"
    "postgresql-password" = random_password.wikijs_postgresql_password.result
  })
}
