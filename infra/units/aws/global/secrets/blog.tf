# Static token the blog authenticates to Directus with.
#
# Generated here rather than in Directus so the value has a home that survives
# the cluster. Directus is then told to use it: the token is just a string on
# a user record, so it can be set rather than read back.
#
# Read-only by construction — the user it belongs to carries the "Blog read"
# policy and nothing else. It is a token and not the public policy because
# Directus 12 Community allows no row filters on permissions
# (custom_permission_rules_enabled is restricted), so any read grant exposes
# drafts too. Restricting *who* can read is the only control left, and the
# blog only ever queries status = published.
resource "random_password" "blog_directus_token" {
  length  = 48
  special = false
}

# Consumed by k8s/apps/blog-secrets's ExternalSecret, which lands it in the
# blog namespace as DIRECTUS_TOKEN.
resource "aws_secretsmanager_secret" "blog_application_secret" {
  name       = "${var.environment}/fomiller/homelab/blog-application-secret"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "blog_application_secret" {
  secret_id = aws_secretsmanager_secret.blog_application_secret.id
  secret_string = jsonencode({
    "DIRECTUS_TOKEN" = random_password.blog_directus_token.result
  })
}
