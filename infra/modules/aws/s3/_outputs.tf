output "s3_bucket_name_homelab_oidc" {
  value = aws_s3_bucket.talos_irsa.id
}

output "s3_object_id_homelab_openid_configuration" {
  value = aws_s3_object.talos_irsa_openid_configuration.id
}

output "s3_bucket_name_loki_chunks" {
  value = aws_s3_bucket.loki_chunks.id
}

output "s3_bucket_name_loki_ruler" {
  value = aws_s3_bucket.loki_ruler.id
}

output "s3_bucket_name_loki_admin" {
  value = aws_s3_bucket.loki_admin.id
}
