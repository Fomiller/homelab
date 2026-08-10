# 32 random bytes, base64-encoded — the credential cloudflared's tunnel
# resource is registered under. Generated here (not in Cloudflare) so the
# same value can be written to Secrets Manager (aws/global/secrets) for the
# in-cluster cloudflared pods to authenticate with.
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id    = var.cloudflare_account_id
  name          = var.tunnel_name
  config_src    = "cloudflare"
  tunnel_secret = random_id.tunnel_secret.b64_std
}

# config_src = "cloudflare" means ingress rules live here (dashboard/API
# managed) instead of a local config file the cloudflared pod would need —
# the pod only needs a token (see data.cloudflare_zero_trust_tunnel_cloudflared_token
# below).
#
# One rule per hostname rather than a *.zone_name wildcard. The wildcard made
# the tunnel fail open: anything Traefik answered for was public the moment
# its DNS record existed, and Access only covered what someone remembered to
# add to protected_hostnames. FOM-128 was that going wrong — an API error left
# one hostname off the list and it served traffic unauthenticated for days.
#
# Now a hostname nobody listed gets the catch-all 404 and never reaches
# Traefik at all.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = concat(
      [
        for hostname in local.tunnel_hostnames : {
          hostname = hostname
          service  = var.tunnel_target_service
        }
      ],
      # Required catch-all — must be last, must have no hostname.
      [{
        service = "http_status:404"
      }],
    )
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

locals {
  # authentik.<zone_name> is routed by the tunnel via local.public_hostnames
  # and deliberately stays out of local.protected_hostnames — it's the login
  # page/IdP the Access redirect below depends on, so it has to be reachable
  # without an Access session already established.
  authentik_base_url = "https://authentik.${var.zone_name}"
}

# Dormant until authentik_oauth_client_id/secret are set — created once
# authentik/global/access has provisioned the OAuth2 client for this app.
resource "cloudflare_zero_trust_access_identity_provider" "authentik" {
  count      = var.authentik_oauth_client_id != "" ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = "authentik"
  type       = "oidc"
  # No issuer_url — the provider schema only allows it for type "saml";
  # Cloudflare's generic OIDC config needs just the three endpoint URLs.
  config = {
    client_id     = var.authentik_oauth_client_id
    client_secret = var.authentik_oauth_client_secret
    auth_url      = "${local.authentik_base_url}/application/o/authorize/"
    token_url     = "${local.authentik_base_url}/application/o/token/"
    certs_url     = "${local.authentik_base_url}/application/o/cloudflare-access/jwks/"
    scopes        = ["openid", "email", "profile"]
  }
}

resource "cloudflare_zero_trust_access_policy" "allow" {
  account_id = var.cloudflare_account_id
  name       = "Allow homelab admins"
  decision   = "allow"
  include = [
    for email in var.allowed_emails : { email = { email = email } }
  ]
}

# Access applications sit in front of the protected hostnames at Cloudflare's
# edge, so unauthenticated requests never reach Traefik/the origin at all.
# `domain` is just the primary/display hostname; `destinations` is what's
# actually enforced (self_hosted_domains, the old multi-hostname field, is
# deprecated).
#
# Split across several apps because one app only takes
# var.access_destinations_per_app destinations. Going over doesn't partially
# apply — the whole request fails and the hostname stays unprotected, which
# fails open, since the tunnel's *.zone_name ingress routes it regardless.
locals {
  protected_hostname_chunks = {
    for i, chunk in chunklist(local.protected_hostnames, var.access_destinations_per_app) :
    tostring(i) => chunk
  }
}

resource "cloudflare_zero_trust_access_application" "protected" {
  for_each = local.protected_hostname_chunks

  account_id       = var.cloudflare_account_id
  name             = "Homelab Admin Apps ${tonumber(each.key) + 1}"
  domain           = each.value[0]
  type             = "self_hosted"
  session_duration = "168h"
  allowed_idps     = cloudflare_zero_trust_access_identity_provider.authentik[*].id

  destinations = [
    for hostname in each.value : {
      type = "public"
      uri  = hostname
    }
  ]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow.id
    precedence = 1
  }]
}
