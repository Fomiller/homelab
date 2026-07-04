# The Cloudflare zone authentik is reachable under (authentik.<zone_name>,
# covered by the same *.zone_name tunnel wildcard as every other app —
# see infra/modules/cloudflare).
variable "zone_name" {
  type    = string
  default = "fomiller.com"
}

# Sourced from Doppler (project "homelab"). This is the Cloudflare Zero Trust
# team name (https://<team>.cloudflareaccess.com), set when Zero Trust was
# first enabled on the account — used to build the OAuth2 redirect URI.
# Doppler secret name: CLOUDFLARE_TEAM_NAME.
variable "cloudflare_team_name" {
  type = string
}
