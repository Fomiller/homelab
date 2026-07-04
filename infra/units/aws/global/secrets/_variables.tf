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

# Sourced from Doppler (project "homelab"), same pattern as the other
# modules. Doppler secret name: AUTHENTIK_BOOTSTRAP_EMAIL.
variable "bootstrap_email" {
  type    = string
  default = "forrestmillerj@gmail.com"
}
