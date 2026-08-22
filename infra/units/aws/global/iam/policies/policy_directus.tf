data "aws_iam_policy_document" "directus_s3" {
  statement {
    sid    = "AllowDirectusListBucket"
    effect = "Allow"

    # Directus uploads files larger than its chunk size as multipart.
    actions = [
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name_directus_uploads}",
    ]
  }

  statement {
    sid    = "AllowDirectusReadWriteObjects"
    effect = "Allow"

    # DeleteObject is what makes deleting a file in the admin app actually
    # remove the object instead of orphaning it.
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = [
      "arn:aws:s3:::${var.s3_bucket_name_directus_uploads}/*",
    ]
  }
}

resource "aws_iam_policy" "directus_s3" {
  name   = "${title(var.namespace)}DirectusS3Access"
  policy = data.aws_iam_policy_document.directus_s3.json
}
