# Offsite copy of TREK's backup ZIPs. TREK keeps all its state in one SQLite
# file plus an uploads directory, and its Backup panel bundles both into a ZIP
# on the data PVC. This bucket is a mirror target for that backup category, so
# losing the Longhorn volume doesn't lose the trips.
resource "aws_s3_bucket" "trek_backups" {
  bucket = "${var.namespace}-${var.environment}-${var.app_prefix}-trek-backups"

  tags = {
    Owner       = "Forrest Miller"
    Email       = "forrestmillerj@gmail.com"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "trek_backups" {
  bucket = aws_s3_bucket.trek_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# A mirror's "Sync now" makes the replica MATCH the primary, so it deletes
# objects the PVC no longer has — the same sweep that keeps the copy honest
# will happily follow a bad local prune offsite. Versioning turns those
# deletes into recoverable noncurrent versions.
resource "aws_s3_bucket_versioning" "trek_backups" {
  bucket = aws_s3_bucket.trek_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Only noncurrent versions expire. Current objects are TREK's to prune (the
# Backup panel's keep_days), same reasoning as the attic and cnpg buckets —
# a rule expiring live objects would delete backups TREK still lists.
#
# 90 days is the retention target, and this is the knob that sets it. TREK's
# own keep_days maxes out at 30 and governs the live copy on both sides, since
# the mirror replicates its prunes. What outlives that is the noncurrent
# version each replicated delete leaves behind, so the recoverable window is
# keep_days plus this.
resource "aws_s3_bucket_lifecycle_configuration" "trek_backups" {
  bucket = aws_s3_bucket.trek_backups.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IRSA is how everything else in this cluster reaches S3 (see directus), but
# TREK's S3 driver takes an explicit accessKeyId/secretAccessKey and never
# falls back to the default credential chain, so there is no role to assume.
# Plain IAM user + long-lived key, scoped to this one bucket — same exception
# already made for authentik's SES user.
resource "aws_iam_user" "trek_backups" {
  name = "FomillerTrekS3Backups"
}

data "aws_iam_policy_document" "trek_backups" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.trek_backups.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.trek_backups.arn}/*"]
  }
}

resource "aws_iam_user_policy" "trek_backups" {
  name   = "TrekS3BackupsReadWrite"
  user   = aws_iam_user.trek_backups.name
  policy = data.aws_iam_policy_document.trek_backups.json
}

resource "aws_iam_access_key" "trek_backups" {
  user = aws_iam_user.trek_backups.name
}

# Consumed by k8s/apps/trek's storage-config ExternalSecret, which templates
# these into the storage-config.json TREK seeds its storage backends from.
resource "aws_secretsmanager_secret" "trek_s3_backups" {
  name       = "${var.environment}/fomiller/homelab/trek-s3-backups"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "trek_s3_backups" {
  secret_id = aws_secretsmanager_secret.trek_s3_backups.id
  secret_string = jsonencode({
    endpoint        = "https://s3.${data.aws_region.current.region}.amazonaws.com"
    bucket          = aws_s3_bucket.trek_backups.id
    region          = data.aws_region.current.region
    accessKeyId     = aws_iam_access_key.trek_backups.id
    secretAccessKey = aws_iam_access_key.trek_backups.secret
  })
}
