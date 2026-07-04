# Everyday admin login so akadmin's bootstrap creds can stay in the drawer.
# Member of the built-in "authentik Admins" superuser group.
data "authentik_group" "admins" {
  name          = "authentik Admins"
  include_users = false
}

resource "random_password" "forrest" {
  length  = 32
  special = false
}

resource "authentik_user" "forrest" {
  username = "forrest"
  name     = "Forrest Miller"
  email    = var.forrest_email
  password = random_password.forrest.result
  groups   = [data.authentik_group.admins.id]
}

# Fetch with:
#   aws secretsmanager get-secret-value --secret-id dev/fomiller/homelab/authentik-forrest-user
# Password changes made later in the authentik UI won't drift this resource —
# the provider never reads passwords back.
resource "aws_secretsmanager_secret" "forrest_user" {
  name       = "dev/fomiller/homelab/authentik-forrest-user"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "forrest_user" {
  secret_id = aws_secretsmanager_secret.forrest_user.id
  secret_string = jsonencode({
    username = authentik_user.forrest.username
    password = random_password.forrest.result
  })
}

# The "invite" for Grayson's Google login (google-source.tf's invite-only
# email_link matching) — no group, since the Cloudflare Access provider's
# authorization flow doesn't restrict by group. The password is a fallback
# only; Grayson is expected to sign in via the Google source.
resource "random_password" "grayson" {
  length  = 32
  special = false
}

resource "authentik_user" "grayson" {
  username = "grayson"
  name     = "Grayson Miller"
  email    = var.grayson_email
  password = random_password.grayson.result
}

# Fetch with:
#   aws secretsmanager get-secret-value --secret-id dev/fomiller/homelab/authentik-grayson-user
resource "aws_secretsmanager_secret" "grayson_user" {
  name       = "dev/fomiller/homelab/authentik-grayson-user"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "grayson_user" {
  secret_id = aws_secretsmanager_secret.grayson_user.id
  secret_string = jsonencode({
    username = authentik_user.grayson.username
    password = random_password.grayson.result
  })
}
