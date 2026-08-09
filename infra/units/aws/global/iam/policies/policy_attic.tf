data "aws_iam_policy_document" "attic_s3" {
  statement {
    sid    = "AllowAtticListBucket"
    effect = "Allow"

    # ListBucketMultipartUploads is on the bucket, not the object — atticd
    # uploads NAR chunks larger than 8 MiB as multipart.
    actions = [
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name_attic}",
    ]
  }

  statement {
    sid    = "AllowAtticReadWriteObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name_attic}/*",
    ]
  }
}

resource "aws_iam_policy" "attic_s3" {
  name   = "${title(var.namespace)}AtticS3Access"
  policy = data.aws_iam_policy_document.attic_s3.json
}
