data "aws_iam_policy_document" "loki_s3" {
  statement {
    sid    = "AllowLokiReadWriteChunks"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name_loki_chunks}",
      "arn:aws:s3:::${var.s3_bucket_name_loki_chunks}/*",
    ]
  }

  statement {
    sid    = "AllowLokiRulerBucket"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name_loki_ruler}",
      "arn:aws:s3:::${var.s3_bucket_name_loki_ruler}/*",
    ]
  }

  statement {
    sid    = "AllowLokiAdminBucket"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name_loki_admin}",
      "arn:aws:s3:::${var.s3_bucket_name_loki_admin}/*",
    ]
  }
}

resource "aws_iam_policy" "loki_s3" {
  name   = "${title(var.namespace)}LokiS3Access"
  policy = data.aws_iam_policy_document.loki_s3.json
}
