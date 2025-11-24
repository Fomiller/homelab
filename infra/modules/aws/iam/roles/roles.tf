resource "aws_iam_role" "doppler_operator" {
  name               = "${title(var.namespace)}DopplerOperator"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role" "external_secrets_irsa" {
  name               = "${title(var.namespace)}ExternalSecretsOperator"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.s3_bucket_name_homelab_oidc}"
        }
        Condition = {
          StringEquals = {
            "${var.s3_bucket_name_homelab_oidc}:aud": "sts.amazonaws.com",
            "${var.s3_bucket_name_homelab_oidc}:sub": "system:serviceaccount:external-secrets:external-secrets"
          }
        }
      }
    ]
  })
}

