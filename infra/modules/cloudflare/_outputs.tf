output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "zone_id" {
  value = data.cloudflare_zone.this.id
}

output "tunnel_cname_target" {
  value = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
}
