variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

# The Cloudflare zone (root domain). fomiller.com's DNS lives in Cloudflare;
# Route 53 stays the registrar only (see aws-org's
# aws_route53domains_registered_domain.fomiller name_server blocks).
variable "zone_name" {
  type    = string
  default = "fomiller.com"
}
