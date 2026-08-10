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
  Holds the NAR/chunk index. Losing it orphans everything in the bucket, which
  is why it's the one piece with backups — see [Backups](#backups).
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

### 3. Mint the tokens

`atticadm` is in the image and reads the signing key from the pod's env. Two
tokens, because the Macs have no business creating or deleting caches:

```sh
# admin — server-side only
kubectl -n attic exec deploy/attic -- atticadm -f /etc/atticd/server.toml \
  make-token --sub admin --validity 1y \
  --pull '*' --push '*' --delete '*' \
  --create-cache '*' --configure-cache '*' --configure-cache-retention '*'

# macs — pull and push on the one cache
kubectl -n attic exec deploy/attic -- atticadm -f /etc/atticd/server.toml \
  make-token --sub macs --validity 1y --pull main --push main
```

Store both in Doppler, project `attic`, config `dev`, as `ATTIC_TOKEN_ADMIN`
and `ATTIC_TOKEN_MACS`. Pipe them in rather than pasting, so they stay out of
your shell history:

```sh
printf '%s' "$TOKEN" | doppler secrets set ATTIC_TOKEN_MACS \
  --project attic --config dev --no-interactive --silent
```

Check a token's scope before trusting it. `--dump-claims` skips signing and
prints what's in it:

```sh
kubectl -n attic exec deploy/attic -- atticadm -f /etc/atticd/server.toml \
  make-token --sub macs --validity 1y --pull main --push main --dump-claims
# {"caches":{"main":{"r":1,"w":1}}}  <- r/w only, no d/cc/cr/cq
```

### 4. Create the cache

The cache is called `main`, not `homelab` — both Macs pull from it, so
`homelab` described where the server runs rather than what's in it.

```sh
attic login fomiller https://attic.fomiller.com "$ATTIC_TOKEN_ADMIN"
attic cache create main
attic cache info main
```

`cache info` prints the public key, `main:...`. Leave the cache private —
that's the default, don't pass `--public`.

If the `attic` CLI isn't installed yet (chicken-and-egg on a fresh machine),
the HTTP API does the same thing. Note the capital G — the field is an
externally-tagged enum and `generate` is rejected:

```sh
curl -sS -X POST -H "Authorization: Bearer $ATTIC_TOKEN_ADMIN" \
  -H 'Content-Type: application/json' \
  -d '{"keypair":"Generate","is_public":false,"store_dir":"/nix/store",
       "priority":41,"upstream_cache_key_names":["cache.nixos.org-1"]}' \
  https://attic.fomiller.com/_api/v1/cache-config/main
```

### 5. Wire up the Nix config

In `~/dev/personal/.nix`, set `atticCache.publicKey` in `flake.nix` to the key
from the previous step. It ships empty on purpose: until it's set, both the
substituter and the `attic-watch-store` launchd agent stay switched off, so
nothing is half-configured against a cache that doesn't exist yet.

### 6. Per-machine setup

Once per Mac:

```sh
just attic-login      # sudo prompt is your Mac login password
just rebuild nimbus
```

`attic-login` pulls `ATTIC_TOKEN_MACS` from Doppler and writes it to two
places, because they have different consumers:

- `~/.config/attic/config.toml` (0600) — the `attic` CLI and the watch-store
  agent read this.
- `/etc/nix/attic-token` (root, 0600) — the nix-darwin activation script in
  `modules/darwin/attic-netrc` reads this.

The activation script is what puts the token in `/nix/var/determinate/netrc`,
which is where the **Nix daemon** looks. Substitution happens in the daemon,
not in your shell, so config.toml alone isn't enough.

Three things to know about that netrc:

- It's Determinate's, not ours. `netrc-file` is set in Determinate's own
  `/etc/nix/nix.conf` **after** the `!include` of `nix.custom.conf`, so it wins
  over anything `determinateNix.customSettings` says. The path can't be moved.
- `determinate-nixd login` rewrites it for FlakeHub auth and drops the attic
  line. Recovery is `just rebuild <host>` — the activation script re-adds it
  and leaves the FlakeHub entries alone.
- It stays mode 0644 because the nix **client**, not just the daemon, reads it
  for FlakeHub flake fetches. So the push token is readable by any local user.
  That's why it's scoped to one cache with an expiry.

The token can't live in the repo — `/nix/store` is world-readable — so
`just attic-login` is the one manual step per machine. Moving it to sops-nix
would only change where `tokenFile` points in the activation script.

Don't run `attic use`. It rewrites `~/.config/nix/nix.conf` behind
home-manager's back.

### 7. Seed the cache

`watch-store` only uploads paths created *after* it starts, so a fresh cache
stays empty until you happen to rebuild something. Push the existing closures
once:

```sh
attic push fomiller:main ~/.local/state/nix/profiles/home-manager
attic push fomiller:main /nix/var/nix/profiles/system
```

It walks the closure and skips anything already signed by cache.nixos.org, so
most of it never leaves the machine. Measured on nimbus: 100 paths queued out
of 739, 96 uploaded, 4 rejected on size (see below). Expect a non-zero exit
when anything is over the cap.

## Verifying

Cache is actually private:

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://attic.fomiller.com/main/nix-cache-info
# 401 without a token, 200 with one
```

Client wiring on a Mac, all four should hold:

```sh
grep -c '^machine attic.fomiller.com ' /nix/var/determinate/netrc   # 1
nix config show | grep -E '^substituters' | tr ' ' '\n' | grep attic
nix config show | grep -o 'main:[A-Za-z0-9+/=]*'
launchctl list | grep attic-watch-store
```

The substituter must appear in the plain `substituters =` line, not just
`trusted-substituters`. `trusted-substituters` only pre-approves what an
already-trusted user may request; it isn't used on its own.

What's actually in the cache:

```sh
kubectl -n attic exec attic-db-cnpg-1 -c postgres -- \
  psql -U postgres -d attic -tAc \
  "select (select count(*) from object) objects, (select count(*) from nar) nars"
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

Look for "will be fetched" rather than "will be built". During a real switch
the giveaway is `copying path '/nix/store/...' from 'https://attic.fomiller.com/main'`.
The four oversized packages below will still build locally — that's expected,
not a failure.

## Known limitation: 100 MB pushes

Cloudflare caps proxied request bodies at 100 MB on the Free and Pro plans, and
Attic uploads each NAR as a single PUT. Anything larger comes back 413.

Attic skips store paths already signed by cache.nixos.org, so the really big
ones (grafana at 617 MB, apple-sdk at 459 MB, llvm at 384 MB) are never pushed
regardless. What's left is the locally-built set, and four of those are over
the cap. Measured seeding nimbus:

| path | size | result |
| --- | --- | --- |
| claude-code | 318 MB | 502 |
| holmesgpt | 211 MB | 413 |
| raycast | 132 MB | 413 |
| minikube | 111 MB | 413 |

`claude-code` returns 502 rather than 413 because Cloudflare drops the
connection partway through instead of rejecting it up front. Same cause. You
can tell it's Cloudflare and not the origin by the `<center>cloudflare</center>`
footer on the error body.

These four rebuild locally on the second Mac. Everything else substitutes.

Where this bites harder is a large package falling out of the upstream cache
and having to be built locally — the exact case the cache is most useful for.
You'll see a 413 in the watch-store log. Options at that point, roughly in
order of effort:

- `cloudflared access tcp` forwarder on each Mac, with an Access service-token
  policy. Removes the cap and takes the endpoint off the public internet.
- Push over the tailnet from nimbus only, with `api-endpoint` unset so Attic
  derives it from the Host header.
- Split-horizon DNS to the Traefik LoadBalancer plus a cert-manager cert.

## Backups

Only Postgres is backed up. The NARs in S3 are already durable, and rebuilding
a lost store path is cheap — losing the metadata is what orphans the bucket.
[FOM-127](https://linear.app/fomiller/issue/FOM-127).

Backups go to `s3://fomiller-dev-homelab-cnpg-backups/attic-db-cnpg` via the
`barman-cloud` CNPG-I plugin (`objectstore.yaml`), not the in-tree
`spec.backup.barmanObjectStore`, which is deprecated on CNPG 1.30. Credentials
are IRSA — the role's trust policy pins `sub` to
`system:serviceaccount:attic:attic-db-cnpg`, so **renaming the cluster breaks
the backups**.

- Base backup nightly at 02:30 (`scheduledbackup.yaml`). The schedule is a
  6-field cron because CNPG includes seconds — `0 30 2 * * *` is 02:30, not
  30 seconds past 02:00.
- WAL archived continuously, because the cluster sets `isWALArchiver: true`.
  Without it you could only restore to the last base backup.
- Retention 30d, enforced by barman. That's why the bucket has no lifecycle
  rule: S3 expiring a WAL segment a base backup still needs would leave a
  backup that restores to nothing.

**Check it's healthy.**

```sh
kubectl -n attic get scheduledbackup,backup
kubectl -n attic exec attic-db-cnpg-1 -c postgres -- \
  psql -U postgres -tAc \
  'select archived_count, failed_count, last_archived_wal, last_failed_time from pg_stat_archiver'
```

A non-zero `failed_count` isn't automatically a problem — compare
`last_failed_time` against `last_archived_time`. Failures that all predate the
last success are historical and the counter just never resets.

**Trigger one by hand.**

```sh
kubectl -n attic create -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: attic-db-cnpg-manual-1
  namespace: attic
spec:
  cluster:
    name: attic-db-cnpg
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
```

ArgoCD prunes the `Backup` object afterwards, since it isn't in git. The
backup in S3 is unaffected — check there rather than in the cluster:

```sh
kubectl -n attic exec attic-db-cnpg-1 -c postgres -- \
  barman-cloud-backup-list --cloud-provider aws-s3 \
  s3://fomiller-dev-homelab-cnpg-backups/attic-db-cnpg attic-db-cnpg
```

**Restore** into a new cluster. Never restore over the live one — recovery
bootstraps an empty cluster, so pointing it at the running PVC loses the thing
you're trying to recover.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: attic-db-cnpg-restore
  namespace: attic
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie
  storage:
    size: 3Gi
    storageClass: longhorn
  serviceAccountTemplate:
    metadata:
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::695434033664:role/FomillerCnpgBackupS3Access
  bootstrap:
    recovery:
      source: attic-db-cnpg
      # add `recoveryTarget: {targetTime: "..."}` for point-in-time
  externalClusters:
  - name: attic-db-cnpg
    plugin:
      name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: attic-db-backup
        serverName: attic-db-cnpg
```

The IRSA annotation matters here too: the restore cluster's ServiceAccount is
named after *it*, so it won't match the role's trust policy. Either widen the
trust policy or restore under a name the policy already allows.

Then check the schema came back before pointing atticd at it:

```sh
kubectl -n attic exec attic-db-cnpg-restore-1 -c postgres -- \
  psql -U postgres -d attic -tAc '\dt'
```

> The restore path above is written from the plugin's API, not from a drill.
> Run it once against a scratch cluster before you need it.

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
line, or the token expired. Usually `determinate-nixd login` rewrote the file.

```sh
grep -c '^machine attic.fomiller.com ' /nix/var/determinate/netrc   # want 1
just rebuild <host>                                                # re-adds it
```

If it's still missing after a rebuild, the bootstrap file is gone — check
`sudo test -r /etc/nix/attic-token` and rerun `just attic-login`.

**`Sorry, try again` during `just attic-login`.** That's `sudo` asking for your
Mac login password, not a new one and not the attic token. `sudo -v` on its own
tells you whether it's the recipe or your password.

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
