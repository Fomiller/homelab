locals {
  authentik_secrets = jsondecode(data.aws_secretsmanager_secret_version.authentik_secrets.secret_string)
  authentik_url     = "https://authentik.${var.zone_name}"
}

provider "authentik" {
  url   = local.authentik_url
  token = local.authentik_secrets["bootstrap_token"]
}

# Stock flows every fresh authentik install ships with.
data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-provider-invalidation-flow"
}

# RS256-signs the id_token so Cloudflare Access can verify it against the
# JWKS endpoint (config.certs_url in infra/modules/cloudflare) instead of
# falling back to the client-secret-shared HS256 default.
data "authentik_certificate_key_pair" "self_signed" {
  name = "authentik Self-signed Certificate"
}

# Generated here (not left to authentik) so infra/modules/cloudflare can be
# handed the exact value via Doppler — same "dormant IdP" pattern already
# used for Google/GitHub, just self-hosted instead of third-party.
resource "random_password" "cloudflare_access_client_secret" {
  length  = 64
  special = false
}

# The openid/email/profile scope mappings the UI would have auto-selected —
# providers created via the API get none, leaving tokens without email/profile
# claims (Cloudflare Access then fails with "Failed to fetch user/group
# information from the identity provider").
data "authentik_property_mapping_provider_scope" "cloudflare_access" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}

resource "authentik_provider_oauth2" "cloudflare_access" {
  name               = "Cloudflare Access"
  client_id          = "cloudflare-access"
  client_secret      = random_password.cloudflare_access_client_secret.result
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  signing_key        = data.authentik_certificate_key_pair.self_signed.id
  property_mappings  = data.authentik_property_mapping_provider_scope.cloudflare_access.ids

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://${var.cloudflare_team_name}.cloudflareaccess.com/cdn-cgi/access/callback"
    }
  ]
}

resource "authentik_application" "cloudflare_access" {
  name              = "Cloudflare Access"
  slug              = "cloudflare-access"
  protocol_provider = authentik_provider_oauth2.cloudflare_access.id
}
