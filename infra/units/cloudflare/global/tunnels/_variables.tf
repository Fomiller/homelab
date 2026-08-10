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
    "home.fomiller.com",
    "argocd.fomiller.com",
    "grafana.fomiller.com",
    "longhorn.fomiller.com",
    "redpanda.fomiller.com",
    "temporal.fomiller.com",
    "netbox.fomiller.com",
    "romm.fomiller.com",
    "supabase.fomiller.com",
    "wiki.fomiller.com",
  ]
}

# Reachable without an Access session. Both are deliberate and neither can be
# moved behind Access:
#
# - authentik is the IdP the Access redirect points at, so gating it on Access
#   is a loop.
# - attic is a Nix substituter. Nix can't follow an SSO redirect and can't set
#   the CF-Access-Client-* headers a service token needs. Its own JWT auth is
#   the control — an unauthenticated request gets a 401 from Attic itself.
#
# Adding to this list puts something on the public internet. Adding to
# protected_hostnames does not. Anything in neither list gets a 404 from the
# tunnel and is checked by scripts/check-ingress-exposure.py.
variable "public_hostnames" {
  type = list(string)
  default = [
    "authentik.fomiller.com",
    "attic.fomiller.com",
  ]
}

# How many destinations one Access application takes. Over this, the API
# rejects the whole app with "too many destinations for one app", so the list
# above is split across as many apps as it needs. Ordering matters: appending
# to protected_hostnames only ever adds to the last app, while inserting in
# the middle reshuffles every chunk after it.
variable "access_destinations_per_app" {
  type    = number
  default = 5
}

# Optional — authentik as an in-cluster OIDC sign-in option. Leave unset
# until authentik/global/access has created the OAuth2 provider/application
# against a running authentik instance. Doppler secret names:
# AUTHENTIK_OAUTH_CLIENT_ID, AUTHENTIK_OAUTH_CLIENT_SECRET (copied from that
# unit's outputs).
variable "authentik_oauth_client_id" {
  type    = string
  default = ""
}

variable "authentik_oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}
