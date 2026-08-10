# The single app became the first chunk. Without this the apply deletes the
# live app and recreates it, which drops the Access session for everyone.
moved {
  from = cloudflare_zero_trust_access_application.protected
  to   = cloudflare_zero_trust_access_application.protected["0"]
}
