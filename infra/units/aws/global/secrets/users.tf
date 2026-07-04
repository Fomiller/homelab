# Password generation for the authentik_user resources in
# authentik/global/access — that unit is authentik-provider-only, so the
# random values and their Secrets Manager copies live here and get passed
# across as a dependency output (the `users` map, merging var.users with
# each person's generated password). Add/remove people via var.users, not
# by adding resource blocks here.

resource "random_password" "user" {
  for_each = var.users
  length   = 32
  special  = false
}

# Fetch with:
#   aws secretsmanager get-secret-value --secret-id <environment>/fomiller/homelab/authentik-<username>-user
# Password changes made later in the authentik UI won't drift this resource —
# the provider never reads passwords back.
resource "aws_secretsmanager_secret" "user" {
  for_each   = var.users
  name       = "${var.environment}/fomiller/homelab/authentik-${each.key}-user"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "user" {
  for_each  = var.users
  secret_id = aws_secretsmanager_secret.user[each.key].id
  secret_string = jsonencode({
    username = each.key
    password = random_password.user[each.key].result
  })
}
