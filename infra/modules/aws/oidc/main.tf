data "tls_certificate" "open_id_connect_talos" {
  url = "https://${var.s3_bucket_name_homelab_oidc}/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "talos" {
  url             = "https://${var.s3_bucket_name_homelab_oidc}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.open_id_connect_talos.certificates[0].sha1_fingerprint]
}
