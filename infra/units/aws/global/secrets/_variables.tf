variable "doppler_operator_client_id" {
  type = string
}

variable "doppler_operator_client_secret" {
  type = string
}

variable "tailscale_operator_client_id" {
  type = string
}

variable "tailscale_operator_client_secret" {
  type = string
}

# Doppler Service Account API token (viewer, all projects) used by
# homepage's ExternalSecret/SecretStore to read the "homepage" project's
# HOMEPAGE_VAR_* secrets directly from Doppler. Doppler secret name:
# ESO_DOPPLER_SA_TOKEN.
variable "eso_doppler_sa_token" {
  type = string
}

# Sourced from Doppler (project "homelab"), same pattern as the other
# modules. Doppler secret name: AUTHENTIK_BOOTSTRAP_EMAIL.
variable "bootstrap_email" {
  type    = string
  default = "forrestmillerj@gmail.com"
}

# Every authentik human user, keyed by username. Add/remove people by
# editing this map — no per-user resource blocks anywhere. admin = true
# joins the built-in "authentik Admins" group in authentik/global/access;
# everyone else gets a bare invite (e.g. Google-source email_link matching).
# Emails here must stay in cloudflare/global/tunnels' allowed_emails list —
# Cloudflare Access matches the email claim authentik sends against that
# policy.
variable "users" {
  type = map(object({
    email = string
    name  = string
    admin = bool
  }))
  default = {
    forrest = {
      email = "forrestmillerj@gmail.com"
      name  = "Forrest Miller"
      admin = true
    }
    grayson = {
      email = "millergrayson0@gmail.com"
      name  = "Grayson Miller"
      admin = false
    }
  }
}
