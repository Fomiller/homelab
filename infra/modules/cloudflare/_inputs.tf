# The Cloudflare zone (root domain). fomiller.com's DNS lives in Cloudflare;
# Route 53 stays the registrar only (see aws-org's
# aws_route53domains_registered_domain.fomiller name_server blocks).
variable "zone_name" {
  type    = string
  default = "fomiller.com"
}

variable "tunnel_name" {
  type    = string
  default = "homelab"
}

# Every first-level subdomain (*.fomiller.com) forwards here — Traefik then
# routes by Host header to whichever app's IngressRoute/Ingress matches, so
# exposing a new app is a k8s-only change (new IngressRoute), not a
# Terraform/DNS change. Stuck to one level deep (not e.g. lab.fomiller.com)
# because Cloudflare's free Universal SSL cert only covers the apex and
# *.fomiller.com — a second-level wildcard needs a paid plan (Total TLS).
variable "tunnel_target_service" {
  type    = string
  default = "http://traefik.traefik.svc.cluster.local:80"
}

# Emails allowed through the Cloudflare Access login wall (via one-time-PIN
# for now). Same policy applies to every hostname in var.protected_hostnames.
variable "allowed_emails" {
  type    = list(string)
  default = [
    "forrestmillerj@gmail.com",
    "millergrayson0@gmail.com"
  ]
}

# *.fomiller.com hostnames gated behind Cloudflare Access — add a hostname
# here to bring a new app under the same login wall, no other Terraform
# changes needed.
variable "protected_hostnames" {
  type = list(string)
  default = [
    "argocd.fomiller.com",
    "grafana.fomiller.com",
    "longhorn.fomiller.com",
    "redpanda.fomiller.com",
  ]
}
