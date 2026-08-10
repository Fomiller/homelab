data "aws_iam_policy_document" "cnpg_backup_s3" {
  statement {
    sid    = "AllowCnpgBackupListBucket"
    effect = "Allow"

    # barman-cloud lists the bucket to find existing base backups and WAL
    # segments, and uploads large base backups as multipart.
    actions = [
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name_cnpg_backups}",
    ]
  }

  statement {
    sid    = "AllowCnpgBackupReadWriteObjects"
    effect = "Allow"

    # DeleteObject is what enforces the retention policy — without it barman
    # uploads forever and never expires anything.
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name_cnpg_backups}/*",
    ]
  }
}

resource "aws_iam_policy" "cnpg_backup_s3" {
  name   = "${title(var.namespace)}CnpgBackupS3Access"
  policy = data.aws_iam_policy_document.cnpg_backup_s3.json
}
