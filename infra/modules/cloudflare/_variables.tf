# Sourced from Doppler (project "homelab") via `doppler run --name-transformer
# tf-var`, same as the tailscale/doppler operator creds in
# infra/modules/aws/secrets. Doppler secret names: CLOUDFLARE_API_TOKEN,
# CLOUDFLARE_ACCOUNT_ID.
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type = string
}

# Optional — Google sign-in directly on the Cloudflare Access login wall
# (distinct from AUTHENTIK_GOOGLE_* in infra/modules/authentik-access, which
# federates Google *into* authentik). Leave unset to skip; the google
# identity provider resource only gets created once both are non-empty.
# Doppler secret names: CLOUDFLARE_GOOGLE_CLIENT_ID,
# CLOUDFLARE_GOOGLE_CLIENT_SECRET. Redirect URI to register in Google Cloud
# Console: https://<your-zero-trust-team-name>.cloudflareaccess.com/cdn-cgi/access/callback
variable "cloudflare_google_client_id" {
  type    = string
  default = ""
}

variable "cloudflare_google_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

# Optional — GitHub sign-in, same deal as Google above. Doppler secret
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
# pattern as Google/GitHub above. Leave unset until infra/modules/authentik-access
# has created the OAuth2 provider/application against a running authentik
# instance. Doppler secret names: AUTHENTIK_OAUTH_CLIENT_ID,
# AUTHENTIK_OAUTH_CLIENT_SECRET (copied from that module's outputs).
variable "authentik_oauth_client_id" {
  type    = string
  default = ""
}

variable "authentik_oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}
