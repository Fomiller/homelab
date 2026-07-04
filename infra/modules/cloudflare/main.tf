# 32 random bytes, base64-encoded — the credential cloudflared's tunnel
# resource is registered under. Generated here (not in Cloudflare) so the
# same value can be written straight to Secrets Manager for the in-cluster
# cloudflared pods to authenticate with.
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
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = [
      {
        hostname = "*.${var.zone_name}"
        service  = var.tunnel_target_service
      },
      # Required catch-all — must be last, must have no hostname.
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = data.cloudflare_zone.this.id
  name    = "*.${var.zone_name}"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Consumed by k8s/apps/cloudflared's ExternalSecret, same
# ClusterSecretStore/aws-clustersecretstore pattern as the tailscale operator
# creds.
resource "aws_secretsmanager_secret" "cloudflare_tunnel_creds" {
  name       = "dev/fomiller/homelab/cloudflare-tunnel-creds"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "cloudflare_tunnel_creds" {
  secret_id = aws_secretsmanager_secret.cloudflare_tunnel_creds.id
  secret_string = jsonencode({
    tunnel_token = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  })
}

resource "cloudflare_zero_trust_access_identity_provider" "onetimepin" {
  account_id = var.cloudflare_account_id
  name       = "One-time PIN"
  type       = "onetimepin"
  config     = {}
}

# Dormant until cloudflare_google_oauth_client_id/secret are set — kept wired
# in so switching to Google sign-in later is just filling in the Doppler secrets.
resource "cloudflare_zero_trust_access_identity_provider" "google" {
  count      = var.cloudflare_google_oauth_client_id != "" ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = "Google"
  type       = "google"
  config = {
    client_id     = var.cloudflare_google_oauth_client_id
    client_secret = var.cloudflare_google_oauth_client_secret
  }
}

# Dormant until github_oauth_client_id/secret are set — same deferred
# pattern as the google identity provider above.
resource "cloudflare_zero_trust_access_identity_provider" "github" {
  count      = var.github_oauth_client_id != "" ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = "GitHub"
  type       = "github"
  config = {
    client_id     = var.github_oauth_client_id
    client_secret = var.github_oauth_client_secret
  }
}

locals {
  # authentik.<zone_name> is covered by the *.zone_name wildcard tunnel
  # ingress above — it deliberately stays out of var.protected_hostnames,
  # since it's the login page/IdP the Access redirect below depends on and
  # must stay reachable without an Access session already established.
  authentik_base_url = "https://authentik.${var.zone_name}"
}

# Dormant until authentik_oauth_client_id/secret are set — same deferred
# pattern as Google/GitHub above, except this IdP is the in-cluster
# authentik instance (infra/modules/authentik, infra/modules/authentik-access)
# instead of a third party.
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

# One Access application covering every hostname in var.protected_hostnames
# — sits in front of the tunnel at Cloudflare's edge, so unauthenticated
# requests never reach Traefik/the origin at all. `domain` is just the
# primary/display hostname; `destinations` is what's actually enforced
# (self_hosted_domains, the old multi-hostname field, is deprecated).
resource "cloudflare_zero_trust_access_application" "protected" {
  account_id       = var.cloudflare_account_id
  name             = "Homelab Admin Apps"
  domain           = var.protected_hostnames[0]
  type             = "self_hosted"
  session_duration = "168h"
  allowed_idps = concat(
    [cloudflare_zero_trust_access_identity_provider.onetimepin.id],
    cloudflare_zero_trust_access_identity_provider.google[*].id,
    cloudflare_zero_trust_access_identity_provider.github[*].id,
    cloudflare_zero_trust_access_identity_provider.authentik[*].id
  )

  destinations = [
    for hostname in var.protected_hostnames : {
      type = "public"
      uri  = hostname
    }
  ]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow.id
    precedence = 1
  }]
}
