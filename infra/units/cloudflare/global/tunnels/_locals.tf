# Every hostname the tunnel routes, and whether Access sits in front of it.
#
# Locals rather than variables on purpose: which hostnames are public is a
# property of this cluster, not an input. As variables a stack could override
# them, and "what's exposed" would no longer be answerable by reading this file.
#
# A hostname in neither list gets the catch-all 404 from the tunnel and never
# reaches Traefik. scripts/check-ingress-exposure.py fails CI if an IngressRoute
# declares a hostname that isn't in one of these.
locals {
  # Behind the Cloudflare Access login wall. Adding a hostname here is the
  # whole change — the Access apps and the tunnel ingress both build off it.
  #
  # Append, don't insert. Chunking into Access apps is positional, so inserting
  # in the middle reshuffles every app after it.
  protected_hostnames = [
    "home.fomiller.com",
    "argocd.fomiller.com",
    "grafana.fomiller.com",
    "longhorn.fomiller.com",
    "redpanda.fomiller.com",
    "temporal.fomiller.com",
    "netbox.fomiller.com",
    "romm.fomiller.com",
    "supabase.fomiller.com",
    "wiki.fomiller.com",
    "kargo.fomiller.com",
    "cms.fomiller.com",
  ]

  # Reachable without an Access session. Both are deliberate and neither can
  # move behind Access:
  #
  # - authentik is the IdP the Access redirect points at, so gating it on
  #   Access is a loop.
  # - attic is a Nix substituter. Nix can't follow an SSO redirect and can't
  #   set the CF-Access-Client-* headers a service token needs. Its own JWT
  #   auth is the control — an unauthenticated request gets a 401 from Attic.
  #
  # Adding to this list puts something on the public internet.
  public_hostnames = [
    "authentik.fomiller.com",
    "attic.fomiller.com",
  ]

  tunnel_hostnames = concat(local.protected_hostnames, local.public_hostnames)
}
