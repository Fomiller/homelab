# Consumed by k8s/apps/cloudflared's ExternalSecret, same
# ClusterSecretStore/aws-clustersecretstore pattern as the tailscale operator
# creds. tunnel_token is a dependency input from cloudflare/global/tunnels —
# this unit just archives the value Cloudflare issued, it isn't generated here.
resource "aws_secretsmanager_secret" "cloudflare_tunnel_creds" {
  name       = "${var.environment}/fomiller/homelab/cloudflare-tunnel-creds"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "cloudflare_tunnel_creds" {
  secret_id = aws_secretsmanager_secret.cloudflare_tunnel_creds.id
  secret_string = jsonencode({
    tunnel_token = var.tunnel_token
  })
}
