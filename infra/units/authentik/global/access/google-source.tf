# Google federated login into authentik: users sign in with their Google
# account. email_link matching means a Google login whose email matches an
# existing authentik user just links to it — no invitation needed for
# people who already have a User (e.g. via infra/modules/authentik-access's
# users.tf pattern).
#
# Invite-only: enrollment_flow points at default-source-enrollment, which
# invitation.tf gates with a required Invitation stage — a Google login with
# no matching email and no valid invitation token gets rejected instead of
# auto-creating a User. authentik.fomiller.com sits outside
# protected_hostnames (see infra/modules/cloudflare's locals.authentik_base_url
# comment), so this is the only thing stopping open self-enrollment.
#
# Dormant until the Doppler secrets are set — same deferred pattern as the
# cloudflare module's IdPs. Deliberately NOT reusing GOOGLE_OAUTH_CLIENT_ID/
# GOOGLE_OAUTH_CLIENT_SECRET: those activate the direct Google IdP in
# infra/modules/cloudflare, which would bypass authentik.
# Doppler secret names: AUTHENTIK_GOOGLE_CLIENT_ID, AUTHENTIK_GOOGLE_CLIENT_SECRET.
# Redirect URI to register in Google Cloud Console (APIs & Services >
# Credentials > OAuth client, type "Web application"):
# https://authentik.<zone_name>/source/oauth/callback/google/

data "authentik_flow" "source_authentication" {
  slug = "default-source-authentication"
}

data "authentik_flow" "source_enrollment" {
  slug = "default-source-enrollment"
}

resource "authentik_source_oauth" "google" {
  count               = var.authentik_google_client_id != "" ? 1 : 0
  name                = "Google"
  slug                = "google"
  provider_type       = "google"
  consumer_key        = var.authentik_google_client_id
  consumer_secret     = var.authentik_google_client_secret
  authentication_flow = data.authentik_flow.source_authentication.id
  enrollment_flow     = data.authentik_flow.source_enrollment.id
  user_matching_mode  = "email_link"

  # authentik derives these from provider_type = "google" server-side and
  # always returns them, but the provider schema marks them optional (not
  # computed) — leaving them unset here causes a perpetual no-op diff
  # (apply nulls them, next refresh re-populates them from the API). Pinning
  # them to the values authentik itself returns stops the loop.
  access_token_url  = "https://oauth2.googleapis.com/token"
  authorization_url = "https://accounts.google.com/o/oauth2/v2/auth"
  oidc_jwks_url     = "https://www.googleapis.com/oauth2/v3/certs"
  profile_url       = "https://openidconnect.googleapis.com/v1/userinfo"
}

# The login page only shows source buttons listed on the identification
# stage's `sources` (fresh installs ship it empty), so the stock stage is
# imported under management here. The import block is a no-op once the
# resource is in state. Attribute values mirror the live stage as of import;
# only `sources` and `show_source_labels` differ intentionally.
import {
  to = authentik_stage_identification.default
  id = "d35cc455-d865-4451-ae82-8abdaab30787"
}

resource "authentik_stage_identification" "default" {
  name                      = "default-authentication-identification"
  user_fields               = ["email", "username"]
  case_insensitive_matching = true
  show_matched_user         = true
  pretend_user_exists       = true
  show_source_labels        = true
  sources                   = authentik_source_oauth.google[*].uuid
}
