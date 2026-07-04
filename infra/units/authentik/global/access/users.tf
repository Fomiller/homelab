# Everyday admin login so akadmin's bootstrap creds can stay in the drawer.
# Member of the built-in "authentik Admins" superuser group.
data "authentik_group" "admins" {
  name          = "authentik Admins"
  include_users = false
}

# Password generated in aws/global/secrets (this unit is authentik-provider
# only, no aws data lookups). Fetch it with:
#   aws secretsmanager get-secret-value --secret-id dev/fomiller/homelab/authentik-forrest-user
# Password changes made later in the authentik UI won't drift this resource —
# the provider never reads passwords back.
resource "authentik_user" "forrest" {
  username = "forrest"
  name     = "Forrest Miller"
  email    = var.forrest_email
  password = var.forrest_password
  groups   = [data.authentik_group.admins.id]
}

# The "invite" for Grayson's Google login (google-source.tf's invite-only
# email_link matching) — no group, since the Cloudflare Access provider's
# authorization flow doesn't restrict by group. The password is a fallback
# only; Grayson is expected to sign in via the Google source. Fetch with:
#   aws secretsmanager get-secret-value --secret-id dev/fomiller/homelab/authentik-grayson-user
resource "authentik_user" "grayson" {
  username = "grayson"
  name     = "Grayson Miller"
  email    = var.grayson_email
  password = var.grayson_password
}
