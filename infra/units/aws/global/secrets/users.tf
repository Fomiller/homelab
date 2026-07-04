# Password generation for the authentik_user resources in
# authentik/global/access — that unit is authentik-provider-only, so the
# random values and their Secrets Manager copies live here and get passed
# across as dependency inputs (forrest_password/grayson_password).

resource "random_password" "forrest" {
  length  = 32
  special = false
}

# Fetch with:
#   aws secretsmanager get-secret-value --secret-id dev/fomiller/homelab/authentik-forrest-user
# Password changes made later in the authentik UI won't drift this resource —
# the provider never reads passwords back.
resource "aws_secretsmanager_secret" "forrest_user" {
  name       = "${var.environment}/fomiller/homelab/authentik-forrest-user"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "forrest_user" {
  secret_id = aws_secretsmanager_secret.forrest_user.id
  secret_string = jsonencode({
    username = "forrest"
    password = random_password.forrest.result
  })
}

# The "invite" for Grayson's Google login (authentik/global/access's
# invite-only email_link matching) — password is a fallback only; Grayson is
# expected to sign in via the Google source.
resource "random_password" "grayson" {
  length  = 32
  special = false
}

# Fetch with:
#   aws secretsmanager get-secret-value --secret-id dev/fomiller/homelab/authentik-grayson-user
resource "aws_secretsmanager_secret" "grayson_user" {
  name       = "${var.environment}/fomiller/homelab/authentik-grayson-user"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "grayson_user" {
  secret_id = aws_secretsmanager_secret.grayson_user.id
  secret_string = jsonencode({
    username = "grayson"
    password = random_password.grayson.result
  })
}
