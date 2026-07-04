# Reads the bootstrap token infra/modules/authentik generated and wrote to
# Secrets Manager, so this module doesn't need its own copy of it.
data "aws_secretsmanager_secret" "authentik_secrets" {
  name = "dev/fomiller/homelab/authentik-secrets"
}

data "aws_secretsmanager_secret_version" "authentik_secrets" {
  secret_id = data.aws_secretsmanager_secret.authentik_secrets.id
}
