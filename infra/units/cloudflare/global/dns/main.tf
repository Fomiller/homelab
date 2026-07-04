resource "cloudflare_dns_record" "wildcard" {
  zone_id = data.cloudflare_zone.this.id
  name    = "*.${var.zone_name}"
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Verification/DKIM records for the SES domain identity in aws/global/ses —
# that unit's aws_ses_domain_identity_verification polls for this record to
# exist, so it fails-and-retries on a from-scratch first apply (this unit
# hasn't run yet the first time through); a re-run succeeds once this has.
resource "cloudflare_dns_record" "ses_verification" {
  zone_id = data.cloudflare_zone.this.id
  name    = "_amazonses.${var.zone_name}"
  type    = "TXT"
  content = var.verification_token
  ttl     = 300
}

# SES always returns exactly 3 DKIM tokens.
resource "cloudflare_dns_record" "ses_dkim" {
  count   = 3
  zone_id = data.cloudflare_zone.this.id
  name    = "${var.dkim_tokens[count.index]}._domainkey.${var.zone_name}"
  type    = "CNAME"
  content = "${var.dkim_tokens[count.index]}.dkim.amazonses.com"
  ttl     = 300
  proxied = false
}
