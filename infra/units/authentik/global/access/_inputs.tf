# From aws/global/secrets
variable "authentik_bootstrap_token" {
  type      = string
  sensitive = true
}

# Both keyed by username, from aws/global/secrets — see var.users there for
# the single source of truth on who gets an account. Split in two because
# Terraform won't allow for_each over a sensitive map: user_metadata drives
# for_each, user_passwords is looked up per-key.
variable "user_metadata" {
  type = map(object({
    email = string
    name  = string
    admin = bool
  }))
}

variable "user_passwords" {
  type      = map(string)
  sensitive = true
}
