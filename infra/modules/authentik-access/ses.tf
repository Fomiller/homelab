# AWS SES so authentik can send real email (invitation-flow prompts, password
# recovery, etc.) instead of the chart's default localhost:25 no-op. Verifies
# the whole zone as a domain identity, so authentik can send FROM any
# @<zone_name> address without a separate identity per sender.

resource "aws_ses_domain_identity" "this" {
  domain = var.zone_name
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

# While the account is in the SES sandbox, delivery only succeeds to
# verified recipient identities — AWS emails each address a confirmation
# link on creation, which the recipient has to click before mail actually
# lands. Add an entry here per person invited while still sandboxed;
# unnecessary once SES production access is granted.
resource "aws_ses_email_identity" "forrest" {
  email = var.forrest_email
}

resource "aws_ses_email_identity" "grayson" {
  email = var.grayson_email
}

resource "cloudflare_dns_record" "ses_verification" {
  zone_id = data.cloudflare_zone.this.id
  name    = "_amazonses.${var.zone_name}"
  type    = "TXT"
  content = aws_ses_domain_identity.this.verification_token
  ttl     = 300
}

# SES always returns exactly 3 DKIM tokens.
resource "cloudflare_dns_record" "ses_dkim" {
  count   = 3
  zone_id = data.cloudflare_zone.this.id
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.zone_name}"
  type    = "CNAME"
  content = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"
  ttl     = 300
  proxied = false
}

# Blocks until Cloudflare's DNS is visible to SES and the domain flips to
# verified — if this times out on first apply (slow propagation), re-running
# the deploy is enough, the DNS records are already in place by then.
resource "aws_ses_domain_identity_verification" "this" {
  domain = aws_ses_domain_identity.this.domain

  depends_on = [cloudflare_dns_record.ses_verification]

  timeouts {
    create = "10m"
  }
}

# SES SMTP has no IRSA/role-based auth path — authentik's Django email
# backend only speaks SMTP, so this is a plain IAM user + long-lived access
# key, scoped to sending from this one verified identity only.
resource "aws_iam_user" "authentik_ses" {
  name = "FomillerAuthentikSes"
}

# Resource = "*" is deliberate, not a lazy wildcard: while the account is in
# the SES sandbox, sending checks IAM authorization against the *recipient*
# identity too (not just the sender), and recipients aren't known ARNs ahead
# of time — scoping this to just the domain identity produces
# "Access denied ... on resource identity/<recipient>" 554s for every send.
data "aws_iam_policy_document" "authentik_ses_send" {
  statement {
    effect    = "Allow"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "authentik_ses_send" {
  name   = "SesSendFromFomillerCom"
  user   = aws_iam_user.authentik_ses.name
  policy = data.aws_iam_policy_document.authentik_ses_send.json
}

resource "aws_iam_access_key" "authentik_ses" {
  user = aws_iam_user.authentik_ses.name
}

# Consumed by k8s/apps/authentik's second ExternalSecret, same
# ClusterSecretStore/aws-clustersecretstore pattern as authentik-secrets.
resource "aws_secretsmanager_secret" "authentik_ses_smtp" {
  name       = "dev/fomiller/homelab/authentik-ses-smtp"
  kms_key_id = data.aws_kms_key.fomiller_master.id
}

resource "aws_secretsmanager_secret_version" "authentik_ses_smtp" {
  secret_id = aws_secretsmanager_secret.authentik_ses_smtp.id
  secret_string = jsonencode({
    host     = "email-smtp.us-east-1.amazonaws.com"
    port     = "587"
    username = aws_iam_access_key.authentik_ses.id
    # SMTP password derived from the IAM secret key via SES's documented
    # v4 signing algorithm — not the raw IAM secret access key.
    password     = aws_iam_access_key.authentik_ses.ses_smtp_password_v4
    from_address = "authentik@${var.zone_name}"
  })
}
