output "iam_role_name_external_secrets" {
  value = aws_iam_role.external_secrets_irsa.name
}

output "iam_role_name_doppler_operator" {
  value = aws_iam_role.doppler_operator.name
}

output "iam_role_name_loki" {
  value = aws_iam_role.loki_irsa.name
}

output "iam_role_name_attic" {
  value = aws_iam_role.attic_irsa.name
}

output "iam_role_name_cnpg_backup" {
  value = aws_iam_role.cnpg_backup_irsa.name
}

output "iam_role_name_directus" {
  value = aws_iam_role.directus_irsa.name
}
