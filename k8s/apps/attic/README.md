# attic

Self-hosted Nix binary cache. [FOM-124](https://linear.app/fomiller/issue/FOM-124/set-up-attic-nix-binary-cache-in-homelab).

`attic watch-store` runs on both Macs and pushes newly-built store paths here,
so a plain `home-manager switch` populates the cache with no extra step. Both
machines also use it as a Nix substituter.

## How it fits together

```
home-manager switch -> /nix/store -> attic watch-store -> atticd -> S3
                                                            |
                                                        Postgres
                                                     (chunk metadata)
```

- **atticd** — one replica, monolithic mode, so the garbage collector runs
  in-process. That's why the Deployment uses `Recreate`.
- **Postgres** — CloudNativePG `Cluster` (`attic-db-cnpg`), single instance on Longhorn.
  Holds the NAR/chunk index. Losing it orphans everything in the bucket.
- **S3** — `fomiller-dev-homelab-attic`, created in
  `infra/units/aws/global/s3`. Access is IRSA, no static keys: the
  `attic` ServiceAccount carries the role annotation and
  `amazon-eks-pod-identity-webhook` injects the web-identity credentials.
- **Ingress** — Traefik IngressRoute on `attic.fomiller.com`, reached through
  the existing Cloudflare Tunnel wildcard. No terraform change was needed;
  `*.fomiller.com` DNS and the tunnel's wildcard ingress already cover it.

## Why it's on the public internet

`attic.fomiller.com` is deliberately **not** in `var.protected_hostnames`
(`infra/units/cloudflare/global/tunnels`). The Access app in front of those
hostnames does a browser SSO redirect against authentik, and Nix can't follow
one. Access service tokens don't help either — they need `CF-Access-Client-Id`
and `CF-Access-Client-Secret` request headers, and Nix has no way to set
headers on a substituter.

Tailscale was the original plan and doesn't work: the work Mac is on the work
tailnet, and macOS runs one tailnet profile at a time.

So the endpoint is public and Attic's own JWT auth is what guards it. The cache
is **private**, so an unauthenticated request gets a 401. Tokens are per-machine
and scoped to the single cache.

## Bootstrap

Order matters — `cloudnative-pg` must sync before this app, or the `Cluster`
resource has no CRD to validate against. ArgoCD retries, so it converges on its
own, but it'll look broken for a minute.

### 1. Generate the JWT signing key

```sh
nix run nixpkgs#openssl -- genrsa -traditional 4096 | base64 | tr -d '\n'
```

Put it in Doppler, project `attic`, config `dev`, as
`ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64`. That's the only secret this app
needs — Postgres credentials come from CNPG's generated `attic-db-cnpg-app` Secret
and S3 comes from IRSA.

Rotating this key invalidates every token ever minted, including the netrc
entries on both Macs.

### 2. Let ArgoCD sync, then check it came up

```sh
kubectl -n attic get pods
kubectl -n attic logs deploy/attic
```

Expect `Starting API server...` and `Listening on...`. Migrations run at
startup; the startup probe allows 5 minutes.

### 3. Mint an admin token

`atticadm` is in the image and reads the signing key from the pod's env.

```sh
kubectl -n attic exec deploy/attic -- /bin/atticadm -f /etc/atticd/server.toml \
  make-token --sub admin --validity '1h' \
  --create-cache 'homelab' --configure-cache 'homelab' \
  --push 'homelab' --pull 'homelab'
```

### 4. Create the cache

```sh
attic login fomiller https://attic.fomiller.com '<admin token>'
attic cache create homelab
attic cache info homelab
```

`cache info` prints the public key, `homelab:...`. Leave the cache private —
that's the default, don't pass `--public`.

### 5. Wire up the Nix config

In `~/dev/personal/.nix`, set `atticCache.publicKey` in `flake.nix` to the key
from the previous step. It ships empty on purpose: until it's set, both the
substituter and the `attic-watch-store` launchd agent stay switched off, so
nothing is half-configured against a cache that doesn't exist yet.

### 6. Per-machine setup

Once per Mac. Neither step can be committed — both handle credentials.

Mint a token for the machine:

```sh
kubectl -n attic exec deploy/attic -- /bin/atticadm -f /etc/atticd/server.toml \
  make-token --sub nimbus --validity '1y' --push 'homelab' --pull 'homelab'
```

Log the client in, which writes `~/.config/attic/config.toml` (0600). This is
what `attic watch-store` authenticates with:

```sh
attic login fomiller https://attic.fomiller.com '<machine token>'
```

Then give the **Nix daemon** the same token. Substitution happens in the daemon,
not in your shell, so the client's config.toml isn't enough:

```sh
sudo tee -a /nix/var/determinate/netrc >/dev/null <<EOF
machine attic.fomiller.com login attic password <machine token>
EOF
```

Two things to know about that file:

- It's Determinate's, not ours. `netrc-file` is pinned to it in Determinate's
  own `/etc/nix/nix.conf` and the nix-darwin module asserts against overriding
  it, so this is the only place the daemon will look.
- It's mode 0644 and `determinate-nixd login` rewrites it for FlakeHub auth. If
  pulls start 401-ing, check the attic line is still there.

Finally apply, and don't run `attic use` — it rewrites `~/.config/nix/nix.conf`
behind home-manager's back:

```sh
just switch nimbus
```

## Verifying

Cache is actually private:

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://attic.fomiller.com/homelab/nix-cache-info
# 401
```

Push path works end to end:

```sh
just switch nimbus
tail -f ~/Library/Logs/attic-watch-store.log
```

Second machine substitutes rather than rebuilding — on flock, after nimbus has
pushed:

```sh
nix build .#homeConfigurations.flock.activationPackage --dry-run
```

Look for "will be fetched" rather than "will be built", and
`nix config show | grep substituters` should list `attic.fomiller.com` in the
plain `substituters =` line, not just `trusted-substituters`.

## Known limitation: 100 MB pushes

Cloudflare caps proxied request bodies at 100 MB on the Free and Pro plans, and
Attic uploads each NAR as a single PUT. Anything larger comes back 413.

In practice this is narrow. Attic skips store paths already signed by
cache.nixos.org, so the big ones (grafana at 617 MB, apple-sdk at 459 MB, llvm
at 384 MB, go at 213 MB) are never pushed regardless. Of the 34 locally-built
paths in the current home-manager closure, totalling 217 MB, exactly one is over
the cap: **raycast at 132 MB**. It won't cache.

Where this could bite harder is a large package that falls out of the upstream
cache and has to be built locally — the exact case the cache is most useful for.
If that happens you'll see a 413 in the watch-store log. Options at that point,
roughly in order of effort:

- `cloudflared access tcp` forwarder on each Mac, with an Access service-token
  policy. Removes the cap and takes the endpoint off the public internet.
- Push over the tailnet from nimbus only, with `api-endpoint` unset so Attic
  derives it from the Host header.
- Split-horizon DNS to the Traefik LoadBalancer plus a cert-manager cert.

## Operations

**Bumping the image.** `ghcr.io/zhaofengli/attic` publishes no release tags,
only `:latest` and per-commit SHAs, so `deployment.yaml` pins a digest:

```sh
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:zhaofengli/attic:pull&service=ghcr.io" \
  | jq -r .token)
curl -sI -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
  https://ghcr.io/v2/zhaofengli/attic/manifests/latest | grep -i docker-content-digest
```

**Garbage collection** runs every 12 hours in-process. To force one, restart
the pod — or run it standalone with `atticd --mode garbage-collector-once`.

**Changing chunking parameters** in `server.toml` will shift the
content-defined cutpoints, so existing chunks stop matching new ones and the
dedup ratio degrades until the cache turns over. Don't, unless you mean it.

## Troubleshooting

**`Bad Host` from atticd.** `allowed-hosts` in `server.toml` only permits
`attic.fomiller.com`. Anything reaching the pod with a different Host header is
rejected before routing — which is why the kubelet probes set an explicit Host
header.

**401 on pull, 200 in the browser.** The daemon's netrc is missing the attic
line, or the token expired. See per-machine setup above.

**Pod crashlooping on S3.** Check the IRSA wiring — the role's trust policy pins
`sub` to `system:serviceaccount:attic:attic`, so renaming the ServiceAccount or
the namespace breaks `AssumeRoleWithWebIdentity`.

```sh
kubectl -n attic get sa attic -o yaml   # role-arn annotation present?
kubectl -n attic exec deploy/attic -- env | grep AWS_   # webhook injected?
```

**`no matches for kind "Cluster"`.** The `cloudnative-pg` app hasn't synced yet.

**watch-store agent flapping.** It's `KeepAlive` with a 300s `ThrottleInterval`.
Usually it means `attic login` hasn't been run on that machine.

```sh
launchctl list | grep attic
tail ~/Library/Logs/attic-watch-store.log
```
