resource "aws_s3_bucket" "homelab" {
  bucket = "${var.namespace}-${var.environment}-homelab"

  object_lock_enabled = false

  tags = {
    Owner       = "Forrest Miller"
    Email       = "forrestmillerj@gmail.com"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "talos_irsa" {
  bucket = "${var.namespace}-${var.environment}-homelab-oidc"
    
  tags = {
    Owner       = "Forrest Miller"
    Email       = "forrestmillerj@gmail.com"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_ownership_controls" "talos_irsa" {
  bucket = aws_s3_bucket.talos_irsa.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "talos_irsa" {
  bucket = aws_s3_bucket.talos_irsa.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "talos_irsa" {
  depends_on = [
    aws_s3_bucket_ownership_controls.talos_irsa,
    aws_s3_bucket_public_access_block.talos_irsa,
  ]

  bucket = aws_s3_bucket.talos_irsa.id
  acl    = "public-read"
}

resource "aws_s3_object" "talos_irsa_keys_json" {
  bucket = aws_s3_bucket.talos_irsa.id
  key     = ".well-known/jwks.json"
  content = var.oidc_keys
  acl = "public-read"
}

resource "aws_s3_object" "talos_irsa_openid_configuration" {
  bucket = aws_s3_bucket.talos_irsa.id
  key     = ".well-known/openid-configuration"
  content = var.oidc_openid_configuration
  acl = "public-read"
}

resource "aws_s3_bucket" "loki_chunks" {
  bucket = "${var.namespace}-${var.environment}-${var.app_prefix}-chunks"
    
  tags = {
    Owner       = "Forrest Miller"
    Email       = "forrestmillerj@gmail.com"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "loki_ruler" {
  bucket = "${var.namespace}-${var.environment}-${var.app_prefix}-ruler"
    
  tags = {
    Owner       = "Forrest Miller"
    Email       = "forrestmillerj@gmail.com"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "loki_admin" {
  bucket = "${var.namespace}-${var.environment}-${var.app_prefix}-admin"
    
  tags = {
    Owner       = "Forrest Miller"
    Email       = "forrestmillerj@gmail.com"
    Environment = var.environment
  }
}
