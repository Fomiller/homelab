output "bootstrap_token" {
  value     = random_password.bootstrap_token.result
  sensitive = true
}

output "forrest_password" {
  value     = random_password.forrest.result
  sensitive = true
}

output "grayson_password" {
  value     = random_password.grayson.result
  sensitive = true
}
