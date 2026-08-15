# Kargo control plane install

[FOM-144](https://linear.app/fomiller/issue/FOM-144/install-kargo-control-plane-in-the-homelab-cluster)

Stand up the Kargo control plane and UI at `kargo.fomiller.com`, gated by Cloudflare
Access with authentik as the IdP. No promotion pipelines in this change.

## Goal

Kargo running in the cluster, reachable at `kargo.fomiller.com`, admin login working.
That is the whole success criterion. Projects, Warehouses, and Stages are a separate
piece of work that builds on this one.

## Non-goals

- Kargo Projects, Warehouses, Stages, or PromotionTasks
- Git write credentials for Kargo (nothing promotes yet, so nothing needs to commit)
- Argo CD integration wiring (`argocd-update` promotion step RBAC)
- A homepage tile

## Chart

`kargo` 1.11.1 from `oci://ghcr.io/akuity/kargo-charts`.

The chart is published to OCI only — there is no classic HTTP Helm repo index. Verified
locally that kustomize 5.8.1 handles an `oci://` value in `helmCharts[].repo` and pulls
it, so this does not need vendoring into `charts/` the way `charts/argo-cd` and
`charts/tailscale-operator` were. Argo CD's bundled kustomize and helm are newer than the
versions that lacked OCI support, but if the repo-server fails to render, vendoring the
unpacked chart under `k8s/apps/kargo/charts/` is the fallback — `k8s/apps/netbox` already
does exactly that.

## Layout

New directory `k8s/apps/kargo/`, matching the shape every other app in `k8s/apps/` uses.

| File | Purpose |
| --- | --- |
| `config.json` | ApplicationSet input. `appName`/`userGivenName` `kargo`, `srcPath: k8s/apps/kargo`, `destNamespace: default`, `destServer: https://kubernetes.default.svc` — same values every other app uses. |
| `namespace.yaml` | The `kargo` namespace. |
| `kustomization.yaml` | `namespace: kargo`, the `helmCharts` entry, and the other three files as resources. |
| `values.yaml` | Chart values, below. |
| `external-secrets.yaml` | Doppler token plumbing and the `kargo-api` secret. |
| `ingressroute.yaml` | Traefik IngressRoute for `kargo.fomiller.com`. |

The `homelab` ApplicationSet in `k8s/projects/homelab.yaml` globs `k8s/apps/**/config.json`,
so adding `config.json` is what makes the app exist. Nothing else registers it.

## Chart values

Only the values that carry a decision. Everything else stays at chart default.

```yaml
api:
  host: kargo.fomiller.com
  tls:
    enabled: false
    terminatedUpstream: true
  ingress:
    enabled: false
  secret:
    name: kargo-api
  adminAccount:
    enabled: true
  oidc:
    enabled: false
dex:
  enabled: false
externalWebhooksServer:
  enabled: false
```

**`api.tls`.** Cloudflare terminates TLS at the edge and the tunnel hands Traefik plain
HTTP. `enabled: false` makes the API server listen for plain HTTP. `terminatedUpstream:
true` independently forces Kargo's own generated URLs — `API_SERVER_BASE_URL`,
`ADMIN_ACCOUNT_TOKEN_ISSUER` — to `https://`. Without the second flag Kargo would mint
tokens with an `http://` issuer while the browser is on `https://`, which is the same
class of scheme mismatch that forced the `authentik-forwarded-proto` middleware in
`k8s/apps/authentik/ingressroute.yaml`. Kargo has a first-class knob for it, so this one
needs no middleware.

**`api.ingress.enabled: false`.** The repo routes with Traefik `IngressRoute` CRs, not
`Ingress`. Leaving the chart's ingress off also avoids its cert-manager `Issuer`, which
nothing here needs.

**`api.secret.name: kargo-api`.** Setting this stops the chart templating its own Secret
from values, and points the API server at an existing one instead. That is what keeps the
password hash and signing key out of git.

**OIDC and Dex off.** Access is the gate; see below.

**`externalWebhooksServer.enabled: false`.** It exists so Git providers can push events at
Kargo instead of Kargo polling. No Warehouse exists yet, so it would be a public endpoint
with nothing behind it. Turn it on with the first Warehouse that wants it — that needs its
own hostname and its own `protected_hostnames`/`public_hostnames` decision.

## Auth

Cloudflare Access at the edge, Kargo's built-in admin account behind it.

Append `"kargo.fomiller.com"` to `protected_hostnames` in
`infra/units/cloudflare/global/tunnels/_locals.tf`. That single line does everything: the
tunnel ingress rule, the DNS record, and inclusion in a `cloudflare_zero_trust_access_application`.
Append to the end — the list is chunked into Access apps positionally, so inserting in the
middle reshuffles every app after it.

Login is two prompts. Cloudflare Access redirects to authentik for identity, then Kargo
asks for its admin password. Kargo itself has no notion of who you are beyond "admin".

**Rejected: Kargo native OIDC against authentik.** Kargo would see real users and could map
authentik groups onto its admin/user/viewer roles. It needs a new
`authentik_provider_oauth2` and `authentik_application` in
`infra/units/authentik/global/access`, configured as a public client, because Kargo uses
PKCE and sends no client secret. Not worth it for a single-operator cluster with no
Projects yet. This is the upgrade path when Kargo RBAC starts to matter.

**Caveat: the `kargo` CLI cannot log in through Access.** It can't follow the SSO redirect
and can't set the `CF-Access-Client-*` headers a service token needs — the same constraint
that keeps `attic.fomiller.com` in `public_hostnames`. CLI access means
`kubectl port-forward` to `kargo-api`, or minting an Access service token. Acceptable
while the UI is the only consumer.

## Secrets

Follows `k8s/apps/attic/external-secrets.yaml` exactly. Three objects in
`external-secrets.yaml`:

1. `ExternalSecret` `doppler-token-sa` — reads `dev/fomiller/homelab/doppler-token-sa` from
   the `aws-clustersecretstore` ClusterSecretStore, materializing the Doppler service
   account token in the `kargo` namespace.
2. `SecretStore` `doppler-kargo` — Doppler provider, project `kargo`, config `dev`,
   authenticating with the Secret from step 1.
3. `ExternalSecret` `kargo-api` — pulls two keys from that store into a Secret named
   `kargo-api`, which is what `api.secret.name` points at.

The two keys, which must be set in Doppler by hand before the app will start:

- `ADMIN_ACCOUNT_PASSWORD_HASH` — bcrypt hash of the admin password
- `ADMIN_ACCOUNT_TOKEN_SIGNING_KEY` — `openssl rand -base64 29 | tr -d "=+/"`

Rotating the signing key invalidates every issued Kargo token.

Ordering is not a problem worth designing around. The API Deployment mounts the Secret, so
if external-secrets hasn't produced it yet the pod stays pending and starts on its own once
it appears.

## Ingress

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: kargo
  namespace: kargo
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`kargo.fomiller.com`)
      kind: Rule
      services:
        - name: kargo-api
          port: 80
```

No middleware. `api.tls.terminatedUpstream` handles the scheme, which is the only reason
authentik needed one.

## Verification

- `kustomize build --enable-helm k8s/apps/kargo` renders without error, and the output
  contains the CRDs, the API Deployment, and the IngressRoute.
- The rendered API ConfigMap shows `API_SERVER_BASE_URL: https://kargo.fomiller.com`. This
  is the check that `terminatedUpstream` did its job, and it is worth reading explicitly
  rather than assuming.
- The rendered manifests contain no Secret holding a password hash — that would mean
  `api.secret.name` didn't take.
- `scripts/check-ingress-exposure.py` passes. It fails CI when an IngressRoute declares a
  hostname absent from the two lists in `_locals.tf`, so it is the direct test that the
  Terraform and Kubernetes halves agree.
- `terragrunt plan` on `infra/live/dev/cloudflare/global/tunnels` shows the new
  hostname added to the tunnel config and to one Access application, and nothing else
  changing. In particular no existing Access app should show destinations shifting between
  apps — that would mean the append landed in the wrong place.
- After merge: `kargo.fomiller.com` redirects to authentik, then serves the Kargo login.

## Rollout

One PR, both halves. The Terraform apply and the Argo CD sync are independent — the app
comes up either way, it just isn't reachable until the tunnel knows the hostname, and the
hostname 404s at the tunnel until then. Neither order breaks anything, so splitting the PR
buys nothing.

Doppler values go in before merge, so the app doesn't sit in a crash loop waiting for a
Secret.
