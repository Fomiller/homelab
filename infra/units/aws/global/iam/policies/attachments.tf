resource "aws_iam_role_policy_attachment" "external_secrets_attachment" {
  policy_arn = aws_iam_policy.external_secrets.arn
  role       = var.iam_role_name_external_secrets
}

resource "aws_iam_role_policy_attachment" "attic_attachment" {
  policy_arn = aws_iam_policy.attic_s3.arn
  role       = var.iam_role_name_attic
}
