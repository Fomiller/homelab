resource "aws_s3_bucket" "homelab" {
  bucket = "${var.namespace}-${var.environment}-homelab"

  object_lock_enabled = false

  tags = {
    Owner       = "Forrest Miller"
    Email       = "forrestmillerj@gmail.com"
    Environment = var.environment
  }
}

