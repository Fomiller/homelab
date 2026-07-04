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
