# The Cloudflare zone authentik is reachable under (authentik.<zone_name>,
# covered by the *.zone_name tunnel wildcard — see cloudflare/global/tunnels).
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

# Optional — Google federated login into authentik (see google-source.tf).
# Leave unset to keep the source dormant. Doppler secret names:
# AUTHENTIK_GOOGLE_CLIENT_ID, AUTHENTIK_GOOGLE_CLIENT_SECRET.
variable "authentik_google_client_id" {
  type    = string
  default = ""
}

variable "authentik_google_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

# AWS IAM Identity Center (see aws-sso.tf). All four come off the Identity
# Center settings page in the management account and have no value until it's
# been enabled there, so they default empty and leave the resources dormant.
# Doppler secret names: AWS_SSO_ACS_URL, AWS_SSO_AUDIENCE, AWS_SSO_PORTAL_URL,
# AWS_SSO_SCIM_URL, AWS_SSO_SCIM_TOKEN.
#
# acs_url and audience come from the "AWS access portal SAML" details shown
# when the identity source is switched to an external IdP:
#   https://<region>.signin.aws.amazon.com/platform/saml/acs/<uuid>
#   https://<region>.signin.aws.amazon.com/platform/saml/<uuid>
variable "aws_sso_acs_url" {
  type    = string
  default = ""
}

variable "aws_sso_audience" {
  type    = string
  default = ""
}

# https://d-xxxxxxxxxx.awsapps.com/start, or the custom subdomain if one is
# set. Only used for the tile on the authentik dashboard — login normally
# starts at this URL, not in authentik.
variable "aws_sso_portal_url" {
  type    = string
  default = ""
}

# Shown once, when automatic provisioning is enabled on that same page.
variable "aws_sso_scim_url" {
  type    = string
  default = ""
}

variable "aws_sso_scim_token" {
  type      = string
  sensitive = true
  default   = ""
}
