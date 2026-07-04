# From aws/global/secrets
variable "authentik_bootstrap_token" {
  type      = string
  sensitive = true
}

variable "forrest_password" {
  type      = string
  sensitive = true
}

variable "grayson_password" {
  type      = string
  sensitive = true
}
