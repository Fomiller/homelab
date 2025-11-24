output "s3_bucket_name_homelab_oidc" {
  value = aws_s3_bucket.talos_irsa.id
}
