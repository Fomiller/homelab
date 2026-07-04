# The Cloudflare zone (root domain). fomiller.com's DNS lives in Cloudflare;
# Route 53 stays the registrar only (see aws-org's
# aws_route53domains_registered_domain.fomiller name_server blocks).
variable "zone_name" {
  type    = string
  default = "fomiller.com"
}

# Base hostname the tunnel owns within the zone — both the bare name and
# every subdomain under it (*.lab.fomiller.com) route through the tunnel.
# Keeps the rest of fomiller.com's namespace free for anything else.
variable "subdomain" {
  type    = string
  default = "lab.fomiller.com"
}

variable "tunnel_name" {
  type    = string
  default = "homelab"
}

# Every hostname under var.subdomain forwards here — Traefik then routes by
# Host header to whichever app's IngressRoute/Ingress matches, so exposing a
# new app is a k8s-only change (new IngressRoute), not a Terraform/DNS change.
variable "tunnel_target_service" {
  type    = string
  default = "http://traefik.traefik.svc.cluster.local:80"
}
