# Everyday admin login so akadmin's bootstrap creds can stay in the drawer.
# Member of the built-in "authentik Admins" superuser group.
data "authentik_group" "admins" {
  name          = "authentik Admins"
  include_users = false
}

# Driven entirely by var.users (defined in aws/global/secrets) — add/remove
# people there, not here. admin = true joins the authentik Admins group;
# everyone else is a bare invite (e.g. Google-source's invite-only
# email_link matching in google-source.tf has nothing to grant beyond that).
# Password changes made later in the authentik UI won't drift this resource —
# the provider never reads passwords back.
resource "authentik_user" "this" {
  for_each = var.user_metadata

  username = each.key
  name     = each.value.name
  email    = each.value.email
  password = var.user_passwords[each.key]
  groups   = each.value.admin ? [data.authentik_group.admins.id] : []
}
