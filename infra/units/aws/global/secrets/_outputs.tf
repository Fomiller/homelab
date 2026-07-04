output "bootstrap_token" {
  value     = random_password.bootstrap_token.result
  sensitive = true
}

# Echoed back (not sensitive) so authentik/global/access can for_each over
# the same set of people without redeclaring var.users there — Terraform
# won't allow for_each over a sensitive map, so passwords travel separately
# via user_passwords below.
output "user_metadata" {
  value = var.users
}

output "user_passwords" {
  value = {
    for username, user in var.users : username => random_password.user[username].result
  }
  sensitive = true
}
