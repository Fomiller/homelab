output "iam_role_name_external_secrets" {
  value = aws_iam_role.external_secrets.name
}

output "iam_role_name_doppler_operator" {
  value = aws_iam_role.doppler_operator.name
}
