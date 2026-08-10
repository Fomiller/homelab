# AWS IAM Identity Center federation. Login starts at the AWS access portal;
# Identity Center redirects here for the SAML assertion and back. Users and
# groups get into Identity Center over SCIM, so nobody is created by hand on
# the AWS side.
#
# Dormant until the Doppler secrets are set — same deferred pattern as
# google-source.tf. The ACS URL, audience, SCIM endpoint and SCIM token only
# exist once Identity Center is enabled and pointed at an external IdP in the
# management account console. README.md has that order.

locals {
  aws_sso_enabled  = var.aws_sso_acs_url != ""
  aws_scim_enabled = var.aws_sso_scim_url != ""
}

# Membership follows the same admin bool that drives authentik Admins in
# users.tf, so people are still managed only in aws/global/secrets' var.users.
# Admins are in both groups — Identity Center shows one role per permission
# set, and picking the weaker one is sometimes what you want.
resource "authentik_group" "aws_admins" {
  name  = "aws-admins"
  users = [for username, user in var.user_metadata : tonumber(authentik_user.this[username].id) if user.admin]
}

resource "authentik_group" "aws_readonly" {
  name  = "aws-readonly"
  users = [for username, user in var.user_metadata : tonumber(authentik_user.this[username].id)]
}

# Like the Cloudflare Access provider in main.tf, an API-created SAML provider
# gets no property mappings unless they're passed — the assertion would carry
# no attributes at all.
data "authentik_property_mapping_provider_saml" "aws" {
  managed_list = [
    "goauthentik.io/providers/saml/email",
    "goauthentik.io/providers/saml/name",
    "goauthentik.io/providers/saml/username",
  ]
}

# The NameID has to equal the SCIM userName, which the stock SCIM user mapping
# sets to the authentik username (not the email). Identity Center matches the
# assertion subject against that value and rejects the login if they differ.
data "authentik_property_mapping_provider_saml" "username" {
  managed = "goauthentik.io/providers/saml/username"
}

resource "authentik_provider_saml" "aws" {
  count = local.aws_sso_enabled ? 1 : 0

  name               = "AWS Identity Center"
  acs_url            = var.aws_sso_acs_url
  audience           = var.aws_sso_audience
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  signing_kp         = data.authentik_certificate_key_pair.self_signed.id
  property_mappings  = data.authentik_property_mapping_provider_saml.aws.ids
  name_id_mapping    = data.authentik_property_mapping_provider_saml.username.id

  # Identity Center only accepts the assertion over HTTP-POST; the provider
  # default is redirect.
  sp_binding     = "post"
  sign_assertion = true
  sign_response  = true
}

data "authentik_property_mapping_provider_scim" "user" {
  managed = "goauthentik.io/providers/scim/user"
}

data "authentik_property_mapping_provider_scim" "group" {
  managed = "goauthentik.io/providers/scim/group"
}

resource "authentik_provider_scim" "aws" {
  count = local.aws_scim_enabled ? 1 : 0

  name                    = "AWS Identity Center"
  url                     = var.aws_sso_scim_url
  token                   = var.aws_sso_scim_token
  property_mappings       = [data.authentik_property_mapping_provider_scim.user.id]
  property_mappings_group = [data.authentik_property_mapping_provider_scim.group.id]

  # Identity Center's SCIM implementation deviates from the spec in ways
  # authentik only works around under this mode.
  compatibility_mode = "aws"

  # Only these two groups are in scope; every other authentik group stays out
  # of Identity Center. Users are scoped separately, by the policy binding on
  # the application below.
  group_filters                 = [authentik_group.aws_admins.id, authentik_group.aws_readonly.id]
  exclude_users_service_account = true
}

resource "authentik_application" "aws" {
  count = local.aws_sso_enabled ? 1 : 0

  name              = "AWS"
  slug              = "aws"
  protocol_provider = authentik_provider_saml.aws[0].id
  meta_launch_url   = var.aws_sso_portal_url

  # SCIM is a backchannel provider — no login flow of its own. It rides on the
  # same application so user scope and access are decided in one place.
  backchannel_providers = [for p in authentik_provider_scim.aws : tonumber(p.id)]
}

# Read back rather than assembled by hand — the XML carries the signing
# certificate. Surfaced as an output (_outputs.tf) because it gets pasted into
# the AWS console.
data "authentik_provider_saml_metadata" "aws" {
  count       = local.aws_sso_enabled ? 1 : 0
  provider_id = tonumber(authentik_provider_saml.aws[0].id)
}

# Doubles as the SCIM user scope: with no binding on the application, the sync
# pushes every authentik user. aws-readonly holds everyone who should reach
# AWS at all, so binding it covers admins too.
resource "authentik_policy_binding" "aws_access" {
  count = local.aws_sso_enabled ? 1 : 0

  target = authentik_application.aws[0].uuid
  group  = authentik_group.aws_readonly.id
  order  = 0
}
