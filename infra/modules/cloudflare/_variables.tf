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
