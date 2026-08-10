#!/usr/bin/env python3
"""Fail if a Traefik hostname isn't accounted for in the tunnel config.

The tunnel routes only the hostnames listed in protected_hostnames (behind
Cloudflare Access) and public_hostnames (deliberately not). Anything else gets
the catch-all 404. That's the fail-closed half; this is the part that tells you
about it at review time instead of leaving you to notice a 404 in production.

Both sides come from git, so this needs no cluster and no credentials.
"""

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TFVARS = REPO / "infra/units/cloudflare/global/tunnels/_variables.tf"
K8S = REPO / "k8s"

# The tunnel unit only routes this zone, so a Host() rule for anything else
# isn't an exposure decision it can make.
ZONE = "fomiller.com"


def tf_list(name: str) -> list[str]:
    """Pull the default of a list(string) variable out of the .tf file."""
    block = re.search(
        r'variable\s+"%s"\s*\{.*?default\s*=\s*\[(.*?)\]' % re.escape(name),
        TFVARS.read_text(),
        re.DOTALL,
    )
    if not block:
        sys.exit(f"could not find variable {name!r} in {TFVARS}")
    return re.findall(r'"([^"]+)"', block.group(1))


def ingress_hostnames() -> dict[str, list[str]]:
    """Every Host(`...`) in an IngressRoute, mapped to the files declaring it.

    Restricted to files that actually define an IngressRoute — Traefik's own
    chart values carry example rules and a Go template, and neither routes
    anything.
    """
    found: dict[str, list[str]] = {}
    for path in K8S.rglob("*.yaml"):
        text = path.read_text()
        if "kind: IngressRoute" not in text:
            continue
        for host in re.findall(r"Host\(`([^`]+)`\)", text):
            if host.endswith(f".{ZONE}"):
                found.setdefault(host, []).append(str(path.relative_to(REPO)))
    return found


def main() -> int:
    protected = tf_list("protected_hostnames")
    public = tf_list("public_hostnames")
    routed = set(protected) | set(public)
    served = ingress_hostnames()

    # The failure that matters: an app declares a hostname the tunnel won't
    # route. Under the old wildcard this was silent public exposure. Now it's
    # a 404, which is safe but still not what anyone intended.
    unrouted = sorted(set(served) - routed)

    # The reverse is only worth a warning — a hostname can legitimately be
    # listed before its app is merged.
    unserved = sorted(routed - set(served))

    for host in sorted(served):
        if host in protected:
            print(f"  ok       {host}  (behind Access)")
        elif host in public:
            print(f"  PUBLIC   {host}  (deliberately reachable)")

    if unserved:
        print()
        for host in unserved:
            print(f"  warning  {host} is routed but no manifest declares it")

    if unrouted:
        print()
        print("Hostnames served by Traefik but not routed by the tunnel:")
        for host in unrouted:
            print(f"  {host}  ({', '.join(served[host])})")
        print()
        print(
            "Add each to protected_hostnames (behind Access) or, only if it "
            "genuinely cannot use Access, to public_hostnames.\n"
            f"Both live in {TFVARS.relative_to(REPO)}."
        )
        return 1

    print(f"\n{len(protected)} protected, {len(public)} public, none unaccounted for.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
