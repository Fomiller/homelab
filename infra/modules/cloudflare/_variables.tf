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

# Optional — Google sign-in for the Cloudflare Access login wall, deferred
# for now (one-time-PIN email login is active in the meantime). Leave unset
# to skip; the google identity provider resource only gets created once
# both are non-empty. Doppler secret names: GOOGLE_OAUTH_CLIENT_ID,
# GOOGLE_OAUTH_CLIENT_SECRET. Redirect URI to register in Google Cloud
# Console: https://<your-zero-trust-team-name>.cloudflareaccess.com/cdn-cgi/access/callback
variable "google_oauth_client_id" {
  type    = string
  default = ""
}

variable "google_oauth_client_secret" {
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
