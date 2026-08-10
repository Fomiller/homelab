# Copy these into Doppler (AUTHENTIK_OAUTH_CLIENT_ID / AUTHENTIK_OAUTH_CLIENT_SECRET)
# then re-apply infra/modules/cloudflare to light up authentik as a Cloudflare
# Access sign-in option.
output "client_id" {
  value = authentik_provider_oauth2.cloudflare_access.client_id
}

output "client_secret" {
  value     = random_password.cloudflare_access_client_secret.result
  sensitive = true
}

output "issuer_url" {
  value = "${local.authentik_url}/application/o/${authentik_application.cloudflare_access.slug}/"
}

# The IdP metadata XML pasted into the Identity Center external-IdP wizard.
# Empty until the AWS_SSO_* secrets are set (see aws-sso.tf).
output "aws_sso_saml_metadata" {
  value = try(data.authentik_provider_saml_metadata.aws[0].metadata, "")
}
