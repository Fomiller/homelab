# 32 random bytes, base64-encoded — the credential cloudflared's tunnel
# resource is registered under. Generated here (not in Cloudflare) so the
# same value can be written straight to Secrets Manager for the in-cluster
# cloudflared pods to authenticate with.
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id    = var.cloudflare_account_id
  name          = var.tunnel_name
  config_src    = "cloudflare"
  tunnel_secret = random_id.tunnel_secret.b64_std
}

# config_src = "cloudflare" means ingress rules live here (dashboard/API
# managed) instead of a local config file the cloudflared pod would need —
# the pod only needs a token (see data.cloudflare_zero_trust_tunnel_cloudflared_token
# below).
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = [
      {
        hostname = var.subdomain
        service  = var.tunnel_target_service
      },
      {
        hostname = "*.${var.subdomain}"
        service  = var.tunnel_target_service
      },
      # Required catch-all — must be last, must have no hostname.
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

resource "cloudflare_dns_record" "root" {
  zone_id = data.cloudflare_zone.this.id
  name    = var.subdomain
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = data.cloudflare_zone.this.id
  name    = "*.${var.subdomain}"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Consumed by k8s/apps/cloudflared's ExternalSecret, same
# ClusterSecretStore/aws-clustersecretstore pattern as the tailscale operator
# creds.
resource "aws_secretsmanager_secret" "cloudflare_tunnel_creds" {
  name       = "dev/fomiller/homelab/cloudflare-tunnel-creds"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "cloudflare_tunnel_creds" {
  secret_id = aws_secretsmanager_secret.cloudflare_tunnel_creds.id
  secret_string = jsonencode({
    tunnel_token = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  })
}
