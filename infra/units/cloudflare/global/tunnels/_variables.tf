# Sourced from Doppler (project "homelab") via `doppler run --name-transformer
# tf-var`, same as the tailscale/doppler operator creds in
# infra/units/aws/global/secrets. Doppler secret names: CLOUDFLARE_API_TOKEN,
# CLOUDFLARE_ACCOUNT_ID.
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type = string
}

# fomiller.com's DNS lives in cloudflare/global/dns; this unit only needs the
# name for the tunnel's ingress hostname pattern and the authentik IdP's URLs.
variable "zone_name" {
  type    = string
  default = "fomiller.com"
}

variable "tunnel_name" {
  type    = string
  default = "homelab"
}

# Every first-level subdomain (*.fomiller.com) forwards here — Traefik then
# routes by Host header to whichever app's IngressRoute/Ingress matches, so
# exposing a new app is a k8s-only change (new IngressRoute), not a
# Terraform/DNS change. Stuck to one level deep (not e.g. lab.fomiller.com)
# because Cloudflare's free Universal SSL cert only covers the apex and
# *.fomiller.com — a second-level wildcard needs a paid plan (Total TLS).
variable "tunnel_target_service" {
  type    = string
  default = "http://traefik.traefik.svc.cluster.local:80"
}

# Emails allowed through the Cloudflare Access login wall (via authentik).
# Same policy applies to every hostname in var.protected_hostnames.
variable "allowed_emails" {
  type = list(string)
  default = [
    "forrestmillerj@gmail.com",
    "millergrayson0@gmail.com"
  ]
}

# *.fomiller.com hostnames gated behind Cloudflare Access — add a hostname
# here to bring a new app under the same login wall, no other Terraform
# changes needed.
variable "protected_hostnames" {
  type = list(string)
  default = [
    "argocd.fomiller.com",
    "grafana.fomiller.com",
    "longhorn.fomiller.com",
    "redpanda.fomiller.com",
  ]
}

# Optional — GitHub sign-in, same deferred pattern. Doppler secret
# names: GITHUB_OAUTH_CLIENT_ID, GITHUB_OAUTH_CLIENT_SECRET. Redirect URI to
# register in GitHub (Settings > Developer settings > OAuth Apps):
# https://<your-zero-trust-team-name>.cloudflareaccess.com/cdn-cgi/access/callback
variable "github_oauth_client_id" {
  type    = string
  default = ""
}

variable "github_oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

# Optional — authentik as an in-cluster OIDC sign-in option, same deferred
# pattern as Google/GitHub above. Leave unset until authentik/global/access
# has created the OAuth2 provider/application against a running authentik
# instance. Doppler secret names: AUTHENTIK_OAUTH_CLIENT_ID,
# AUTHENTIK_OAUTH_CLIENT_SECRET (copied from that unit's outputs).
variable "authentik_oauth_client_id" {
  type    = string
  default = ""
}

variable "authentik_oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}
