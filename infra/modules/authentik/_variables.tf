# Sourced from Doppler (project "homelab"), same pattern as the other
# modules. Doppler secret name: AUTHENTIK_BOOTSTRAP_EMAIL.
variable "bootstrap_email" {
  type    = string
  default = "forrestmillerj@gmail.com"
}
