# Kargo Control Plane Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the Kargo control plane and UI running at `kargo.fomiller.com`, gated by Cloudflare Access.

**Architecture:** A new `k8s/apps/kargo/` directory holding a kustomize overlay that inflates the upstream Kargo Helm chart, plus a Traefik IngressRoute and ExternalSecrets. Argo CD picks it up because the `homelab` ApplicationSet globs `k8s/apps/**/config.json`. Exposure is one appended line in the Cloudflare tunnel Terraform.

**Tech Stack:** kustomize 5.8.1 (`helmCharts` inflation), Helm chart `kargo` 1.11.1 from an OCI registry, Argo CD v3.5.1, Traefik IngressRoute CRs, external-secrets with a Doppler backend, Terragrunt/OpenTofu for Cloudflare.

**Spec:** `docs/superpowers/specs/2026-08-15-kargo-install-design.md`

## Global Constraints

- Ticket scope for every commit and the branch: `FOM-144`. Branch `FOM-144` already exists; the worktree is `~/dev/worktrees/homelab/FOM-144`. Run every command from there.
- Chart: name `kargo`, version `1.11.1`, repo `oci://ghcr.io/akuity/kargo-charts`.
- Hostname: `kargo.fomiller.com`. Namespace: `kargo`.
- Never commit a password hash, signing key, or Doppler token. Secret material reaches the cluster only through external-secrets.
- Commit message format: `<type>(FOM-144): <lowercase imperative summary>`, with the `Co-Authored-By: Claude` trailer.
- Do not push or open the PR until Task 7. Do not run `terragrunt apply` at all — that is the user's call after review.

## Environment facts (already verified — do not re-investigate)

These were checked against the live cluster while writing this plan. They are recorded so no task has to spend time rediscovering them.

- Argo CD is `quay.io/argoproj/argocd:v3.5.1`. Its repo-server bundles kustomize `v5.8.1` and helm `v4.2.1`, which is what makes the OCI chart pull work server-side.
- `helm pull --repo oci://... ` fails on its own ("not a valid chart repository"). kustomize special-cases OCI repos and issues a different command. So test rendering only ever through `kustomize build --enable-helm`, never through a bare `helm pull`.
- The live Terragrunt environment is `infra/live/dev` (see `infraDir` in the root `justfile`), not prod.
- The chart creates three namespaces of its own — `kargo-cluster-secrets`, `kargo-shared-resources`, `kargo-system-resources`. The `namespace.yaml` in this plan is only for the release namespace `kargo`. kustomize's namespace transformer does not rename them; that was checked.
- The chart uses cert-manager (a `Certificate`, an `Issuer`, and `cert-manager.io/inject-ca-from`) for the admission webhook's serving cert. cert-manager v1.19.1 is installed with default values, so cainjector is enabled. The render is deterministic — no Helm-generated self-signed cert — so it is safe under GitOps.
- The `kargo-api` Service listens on port 80 and targets container port 8080.

## File structure

| File | Responsibility |
| --- | --- |
| `k8s/apps/kargo/namespace.yaml` | The `kargo` namespace, and only that. |
| `k8s/apps/kargo/values.yaml` | Chart values. Every deviation from chart default, nothing else. |
| `k8s/apps/kargo/kustomization.yaml` | Ties the resources and the chart inflation together. |
| `k8s/apps/kargo/external-secrets.yaml` | The Doppler token, the SecretStore, and the `kargo-api` Secret. Same three-object shape as `k8s/apps/attic/external-secrets.yaml`. |
| `k8s/apps/kargo/ingressroute.yaml` | Traefik routing for `kargo.fomiller.com`. |
| `k8s/apps/kargo/config.json` | ApplicationSet input. Adding this is what makes Argo CD create the Application, so it lands last. |
| `infra/units/cloudflare/global/tunnels/_locals.tf` | Modify: append one hostname to `protected_hostnames`. |

---

### Task 1: Doppler project and secret material

No repo changes. This has to happen first because the API pod will not start without the Secret, and because a missing project is easier to fix now than mid-review.

**Files:** none.

**Interfaces:**
- Consumes: nothing.
- Produces: Doppler project `kargo`, config `dev`, containing `ADMIN_ACCOUNT_PASSWORD_HASH` and `ADMIN_ACCOUNT_TOKEN_SIGNING_KEY`. Task 3's `SecretStore` reads exactly that project and config; Task 3's `ExternalSecret` reads exactly those two key names.

- [ ] **Step 1: Confirm the project does not already exist**

```bash
doppler projects | grep -E '^\s*kargo\s' || echo "not present, continue"
```

Expected: `not present, continue`. If it already exists, skip to Step 3 and just make sure both secrets are set.

- [ ] **Step 2: Create the project**

```bash
doppler projects create kargo
```

Doppler creates `dev`, `stg`, and `prd` configs automatically. Only `dev` is used.

- [ ] **Step 3: Generate and set the two values**

The password is yours to choose — pick one and put it in your password manager first, because only the hash is recoverable afterwards.

```bash
read -rs -p "kargo admin password: " KARGO_ADMIN_PASSWORD; echo
doppler secrets set ADMIN_ACCOUNT_PASSWORD_HASH \
  "$(htpasswd -bnBC 10 "" "$KARGO_ADMIN_PASSWORD" | tr -d ':\n')" \
  --project kargo --config dev
doppler secrets set ADMIN_ACCOUNT_TOKEN_SIGNING_KEY \
  "$(openssl rand -base64 29 | tr -d '=+/')" \
  --project kargo --config dev
unset KARGO_ADMIN_PASSWORD
```

`htpasswd -bnBC 10 "" <password>` emits `:$2y$10$...`; the `tr` strips the leading colon and the trailing newline, leaving a bare bcrypt hash. That is the format Kargo expects.

- [ ] **Step 4: Verify both keys exist without printing their values**

```bash
doppler secrets --project kargo --config dev --only-names
```

Expected: the output lists `ADMIN_ACCOUNT_PASSWORD_HASH` and `ADMIN_ACCOUNT_TOKEN_SIGNING_KEY`.

- [ ] **Step 5: Verify the external-secrets service account can reach the new project**

This is the step most likely to surface a problem. One shared Doppler service account token — stored in AWS Secrets Manager at `dev/fomiller/homelab/doppler-token-sa` — is what every app's `SecretStore` authenticates with. Service accounts hold per-project access grants, so a brand new project is not automatically readable.

In the Doppler dashboard, open the service account used by external-secrets and confirm `kargo` appears in its project access list. Add it if it does not.

Nothing later in this plan can detect this being wrong until the cluster is actually syncing, where it shows up as the `kargo-api` ExternalSecret stuck in `SecretSyncedError`.

- [ ] **Step 6: No commit**

Nothing changed in the repo. Move on.

---

### Task 2: Render the chart

Creates the three files that make `kustomize build` produce Kargo's workloads. Nothing is exposed and Argo CD does not know about the app yet, because `config.json` is deliberately last.

**Files:**
- Create: `k8s/apps/kargo/namespace.yaml`
- Create: `k8s/apps/kargo/values.yaml`
- Create: `k8s/apps/kargo/kustomization.yaml`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a buildable kustomization at `k8s/apps/kargo`. Task 3 and Task 4 append to its `resources` list. `api.secret.name: kargo-api` is the contract Task 3's ExternalSecret has to satisfy — the Secret it creates must be named exactly `kargo-api` in namespace `kargo`.

- [ ] **Step 1: Write the check and watch it fail**

```bash
cd ~/dev/worktrees/homelab/FOM-144
kustomize build --enable-helm k8s/apps/kargo
```

Expected: FAIL with `unable to find one of 'kustomization.yaml' ... in directory` — the directory does not exist yet. This is the red state.

- [ ] **Step 2: Create the namespace**

`k8s/apps/kargo/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
  name: kargo
```

The `Prune=false` annotation matches every other app here. It stops Argo CD deleting the namespace — and everything in it — if the app is ever removed from the ApplicationSet.

- [ ] **Step 3: Write the values**

`k8s/apps/kargo/values.yaml`:

```yaml
api:
  host: kargo.fomiller.com

  # Cloudflare terminates TLS at the edge and the tunnel hands Traefik plain
  # HTTP, so the API server listens for HTTP. terminatedUpstream is separate:
  # it forces the URLs Kargo generates for itself — the token issuer, the base
  # URL — to https, which is what the browser is actually on.
  tls:
    enabled: false
    terminatedUpstream: true

  # Routing is a Traefik IngressRoute, see ingressroute.yaml.
  ingress:
    enabled: false

  # Points at the Secret external-secrets builds. Setting this stops the chart
  # templating its own Secret out of values, which is what keeps the password
  # hash out of git.
  secret:
    name: kargo-api

  adminAccount:
    enabled: true

  # Cloudflare Access is the gate. Kargo's own login is the admin account
  # behind it.
  oidc:
    enabled: false

dex:
  enabled: false

# Nothing pushes git events at Kargo until a Warehouse wants them, and turning
# this on means giving it a hostname and an exposure decision.
externalWebhooksServer:
  enabled: false
```

- [ ] **Step 4: Write the kustomization**

`k8s/apps/kargo/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: kargo

resources:
- namespace.yaml

# The chart is published to OCI only — there's no HTTP repo index. kustomize
# handles the oci:// scheme itself; `helm pull --repo oci://...` does not.
helmCharts:
- name: kargo
  releaseName: kargo
  repo: oci://ghcr.io/akuity/kargo-charts
  includeCRDs: true
  version: 1.11.1
  namespace: kargo
  valuesFile: values.yaml
```

The `namespace: kargo` inside the `helmCharts` entry is not redundant with the top-level one. It sets Helm's `.Release.Namespace`, which the chart bakes into ConfigMap values and webhook client configs. The top-level `namespace:` only stamps `metadata.namespace` afterwards, which would leave those baked-in strings pointing at `default`.

- [ ] **Step 5: Run the check and confirm it renders**

```bash
kustomize build --enable-helm k8s/apps/kargo > /tmp/kargo-render.yaml
echo "exit=$?"
grep -c '^kind: CustomResourceDefinition' /tmp/kargo-render.yaml
```

Expected: `exit=0` and a CRD count of `9`.

- [ ] **Step 6: Assert the three things the values were for**

```bash
grep 'API_SERVER_BASE_URL' /tmp/kargo-render.yaml
grep -c '^kind: Secret$' /tmp/kargo-render.yaml
grep -A3 'name: kargo-api$' /tmp/kargo-render.yaml | grep -c 'namespace: kargo'
```

Expected, in order:

- `API_SERVER_BASE_URL: https://kargo.fomiller.com` — an `http://` here means `terminatedUpstream` did not take, and every token Kargo issues would carry the wrong issuer.
- `0` — `grep -c` exits 1 when it matches nothing, so this line prints `0` and returns non-zero. That is the pass. Any Secret in the output means `api.secret.name` was ignored and a password hash is about to be committed.
- A non-zero count — resources landed in the `kargo` namespace.

- [ ] **Step 7: Commit**

```bash
git add k8s/apps/kargo/namespace.yaml k8s/apps/kargo/values.yaml k8s/apps/kargo/kustomization.yaml
git commit -m "feat(FOM-144): add the kargo chart and values" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Wire up the admin secret

Adds the external-secrets objects that turn the Doppler values from Task 1 into the `kargo-api` Secret that Task 2's `api.secret.name` points at.

**Files:**
- Create: `k8s/apps/kargo/external-secrets.yaml`
- Modify: `k8s/apps/kargo/kustomization.yaml` (add to `resources`)
- Reference: `k8s/apps/attic/external-secrets.yaml` is the pattern being copied

**Interfaces:**
- Consumes: Doppler project `kargo`, config `dev`, keys `ADMIN_ACCOUNT_PASSWORD_HASH` and `ADMIN_ACCOUNT_TOKEN_SIGNING_KEY` from Task 1. The `kargo` namespace from Task 2.
- Produces: a Secret named `kargo-api` in namespace `kargo`, holding those two keys. The chart's API Deployment consumes it via `envFrom.secretRef`, so the key names must match Kargo's env var names exactly — they are the env var names, not arbitrary labels.

- [ ] **Step 1: Write the check and watch it fail**

```bash
kustomize build --enable-helm k8s/apps/kargo | grep -c '^kind: ExternalSecret$'
```

Expected: prints `0` and exits non-zero. Red state.

- [ ] **Step 2: Write the external-secrets manifest**

`k8s/apps/kargo/external-secrets.yaml`:

```yaml
---
# Bootstrap credential, terraform-controlled (infra/units/aws/global/secrets
# eso_doppler_sa_token -> AWS Secrets Manager). One shared service account
# reaches every app's Doppler project, so a new project has to be added to its
# access list or this store authenticates but reads nothing.
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: doppler-token-sa
  namespace: kargo
spec:
  refreshInterval: 30s
  secretStoreRef:
    name: aws-clustersecretstore
    kind: ClusterSecretStore
  target:
    name: doppler-token-sa
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: dev/fomiller/homelab/doppler-token-sa
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: doppler-kargo
  namespace: kargo
spec:
  provider:
    doppler:
      auth:
        secretRef:
          dopplerToken:
            name: doppler-token-sa
            key: dopplerToken
      project: kargo
      config: dev
---
# These two key names are Kargo's own env var names — the API Deployment pulls
# this Secret in with envFrom, so renaming either one silently drops it.
#
# Doppler project "kargo" / config "dev" needs:
#   ADMIN_ACCOUNT_PASSWORD_HASH
#     htpasswd -bnBC 10 "" <password> | tr -d ':\n'
#   ADMIN_ACCOUNT_TOKEN_SIGNING_KEY
#     openssl rand -base64 29 | tr -d "=+/"
#
# Rotating the signing key invalidates every token Kargo has issued.
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: kargo-api
  namespace: kargo
spec:
  refreshInterval: 30s
  secretStoreRef:
    kind: SecretStore
    name: doppler-kargo
  target:
    name: kargo-api
    creationPolicy: Owner
  data:
    - secretKey: ADMIN_ACCOUNT_PASSWORD_HASH
      remoteRef:
        key: ADMIN_ACCOUNT_PASSWORD_HASH
    - secretKey: ADMIN_ACCOUNT_TOKEN_SIGNING_KEY
      remoteRef:
        key: ADMIN_ACCOUNT_TOKEN_SIGNING_KEY
```

- [ ] **Step 3: Add it to the kustomization**

In `k8s/apps/kargo/kustomization.yaml`, change:

```yaml
resources:
- namespace.yaml
```

to:

```yaml
resources:
- namespace.yaml
- external-secrets.yaml
```

- [ ] **Step 4: Run the check and confirm it passes**

```bash
kustomize build --enable-helm k8s/apps/kargo > /tmp/kargo-render.yaml
grep -c '^kind: ExternalSecret$' /tmp/kargo-render.yaml
grep -c '^kind: SecretStore$' /tmp/kargo-render.yaml
```

Expected: `2` and `1`.

- [ ] **Step 5: Confirm no secret material got baked into the render**

```bash
grep -c '^kind: Secret$' /tmp/kargo-render.yaml
grep -iE 'PASSWORD_HASH: |SIGNING_KEY: ' /tmp/kargo-render.yaml
```

Expected: `0` from the first (printed, non-zero exit), and no output at all from the second. The ExternalSecret names those keys but must never carry a value beside them.

- [ ] **Step 6: Commit**

```bash
git add k8s/apps/kargo/external-secrets.yaml k8s/apps/kargo/kustomization.yaml
git commit -m "feat(FOM-144): pull the kargo admin secret from doppler" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Route and expose the hostname

The IngressRoute and the Terraform hostname are one task on purpose. `scripts/check-ingress-exposure.py` fails when a manifest declares a hostname the tunnel does not route, so adding the IngressRoute alone leaves the repo in a state CI rejects. That failure is this task's red state.

**Files:**
- Create: `k8s/apps/kargo/ingressroute.yaml`
- Modify: `k8s/apps/kargo/kustomization.yaml` (add to `resources`)
- Modify: `infra/units/cloudflare/global/tunnels/_locals.tf` (append to `protected_hostnames`)

**Interfaces:**
- Consumes: the `kargo-api` Service on port 80, from the chart inflated in Task 2.
- Produces: `kargo.fomiller.com` present in `protected_hostnames`, which is what gives it a tunnel ingress rule, a DNS record, and a slot in a `cloudflare_zero_trust_access_application`.

- [ ] **Step 1: Establish the current baseline**

```bash
python3 scripts/check-ingress-exposure.py
echo "exit=$?"
```

Expected: `exit=0`, with a summary line reading `10 protected, 2 public, none unaccounted for.`

- [ ] **Step 2: Write the IngressRoute**

`k8s/apps/kargo/ingressroute.yaml`:

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

No middleware here. authentik needed `authentik-forwarded-proto` because it had no way to be told TLS was terminated upstream; Kargo has `api.tls.terminatedUpstream`, already set in Task 2.

- [ ] **Step 3: Add it to the kustomization**

In `k8s/apps/kargo/kustomization.yaml`, change:

```yaml
resources:
- namespace.yaml
- external-secrets.yaml
```

to:

```yaml
resources:
- namespace.yaml
- external-secrets.yaml
- ingressroute.yaml
```

- [ ] **Step 4: Run the exposure check and watch it fail**

```bash
python3 scripts/check-ingress-exposure.py
echo "exit=$?"
```

Expected: `exit=1`, with:

```
Hostnames served by Traefik but not routed by the tunnel:
  kargo.fomiller.com  (k8s/apps/kargo/ingressroute.yaml)
```

This is the red state, and it is the check doing exactly its job.

- [ ] **Step 5: Append the hostname to the Terraform local**

In `infra/units/cloudflare/global/tunnels/_locals.tf`, change the end of the `protected_hostnames` list from:

```hcl
    "wiki.fomiller.com",
  ]
```

to:

```hcl
    "wiki.fomiller.com",
    "kargo.fomiller.com",
  ]
```

Append at the end. The comment above the list says why: the list is chunked into Access applications positionally, so inserting in the middle reshuffles which hostname lands in which app.

- [ ] **Step 6: Run the exposure check and confirm it passes**

```bash
python3 scripts/check-ingress-exposure.py
echo "exit=$?"
```

Expected: `exit=0`, a line reading `  ok       kargo.fomiller.com  (behind Access)`, and a summary of `11 protected, 2 public, none unaccounted for.`

- [ ] **Step 7: Confirm the route survives the build**

```bash
kustomize build --enable-helm k8s/apps/kargo | grep -A6 'kind: IngressRoute'
```

Expected: the IngressRoute appears with `Host(\`kargo.fomiller.com\`)` and service `kargo-api`.

- [ ] **Step 8: Commit**

```bash
git add k8s/apps/kargo/ingressroute.yaml k8s/apps/kargo/kustomization.yaml infra/units/cloudflare/global/tunnels/_locals.tf
git commit -m "feat(FOM-144): route kargo.fomiller.com behind access" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Register the app with Argo CD

`config.json` last, so that the moment Argo CD sees it, everything it needs is already in the branch.

**Files:**
- Create: `k8s/apps/kargo/config.json`
- Reference: `k8s/projects/homelab.yaml` is the ApplicationSet that consumes it

**Interfaces:**
- Consumes: the complete `k8s/apps/kargo` directory from Tasks 2 through 4.
- Produces: an Argo CD Application named `kargo` in the `homelab` project, syncing `k8s/apps/kargo` with automated prune and self-heal.

- [ ] **Step 1: Confirm the ApplicationSet would not pick it up yet**

```bash
ls k8s/apps/*/config.json | wc -l
ls k8s/apps/kargo/config.json 2>&1
```

Expected: a count of existing apps, then `No such file or directory`. Red state.

- [ ] **Step 2: Write config.json**

`k8s/apps/kargo/config.json`:

```json
{
  "appName": "kargo",
  "userGivenName": "kargo",
  "destNamespace": "kargo",
  "destServer": "https://kubernetes.default.svc",
  "srcPath": "k8s/apps/kargo",
  "srcRepoURL": "https://github.com/Fomiller/homelab.git",
  "srcTargetRevision": "main",
  "labels": null,
  "annotations": null
}
```

`destNamespace` is `kargo`, matching `k8s/apps/attic/config.json`, which is the closest precedent — a self-contained app in its own namespace.

- [ ] **Step 3: Confirm it parses and matches the glob**

```bash
python3 -c "import json; print(json.load(open('k8s/apps/kargo/config.json'))['srcPath'])"
```

Expected: `k8s/apps/kargo`. The ApplicationSet's git file generator globs `k8s/apps/**/config.json`, so a malformed file breaks generation for the whole set, not just this app. That is why this is worth checking rather than eyeballing.

- [ ] **Step 4: Full render, one more time, from clean**

```bash
rm -rf k8s/apps/kargo/charts
kustomize build --enable-helm k8s/apps/kargo > /tmp/kargo-render.yaml
echo "exit=$?"
grep '^kind:' /tmp/kargo-render.yaml | sort | uniq -c | sort -rn | head
```

Deleting `charts/` first proves the build works from a cold pull, the way Argo CD's repo-server will do it. Expected: `exit=0`, and the kind summary includes 9 CRDs, 4 Namespaces (the chart's three plus ours), 2 ExternalSecrets, 1 IngressRoute, and 3 Deployments — api, controller, management-controller.

- [ ] **Step 5: Make sure the pulled chart is not about to be committed**

```bash
git status --porcelain k8s/apps/kargo/
grep -n 'charts' .gitignore
```

Expected: `config.json` shows as untracked and `charts/` does not appear at all. If `charts/` does show up, stop and add it to `.gitignore` before committing — the netbox app vendors its chart deliberately, but this one must not.

- [ ] **Step 6: Commit**

```bash
git add k8s/apps/kargo/config.json
git commit -m "feat(FOM-144): register kargo with the homelab applicationset" -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Plan the Terraform

Read-only confirmation that the one appended line does what the spec says and nothing more. No apply.

**Files:** none modified.

**Interfaces:**
- Consumes: the `_locals.tf` change from Task 4.
- Produces: a reviewed plan, and a decision to proceed or not.

- [ ] **Step 1: Run the plan**

```bash
cd ~/dev/worktrees/homelab/FOM-144
just plan-all 2>&1 | tee /tmp/kargo-tf-plan.txt
```

This runs `terragrunt stack run plan` against `infra/live/dev` under `doppler run`. It is read-only.

If it fails on AWS credentials, the SSO profile was dropped — `doppler run` needs `--preserve-env` to keep `AWS_PROFILE`. Re-run the underlying command with that flag rather than editing the justfile.

- [ ] **Step 2: Check the tunnel ingress diff**

```bash
grep -n 'kargo.fomiller.com' /tmp/kargo-tf-plan.txt
```

Expected: `kargo.fomiller.com` appears as an addition in the `cloudflare_zero_trust_tunnel_cloudflared_config` ingress list and in one `cloudflare_zero_trust_access_application`'s destinations.

- [ ] **Step 3: Check that no Access app got reshuffled**

```bash
grep -c 'must be replaced\|forces replacement' /tmp/kargo-tf-plan.txt
grep -E '^\s+# cloudflare_zero_trust_access_application' /tmp/kargo-tf-plan.txt
```

Expected: `0` replacements, and only the last Access application in the chunked set showing as changed. An existing hostname moving between applications means the append landed in the wrong place — go back to Task 4 Step 5 and fix it before continuing.

- [ ] **Step 4: No commit**

Nothing changed. If the plan looks wrong, fix the Terraform and amend Task 4's commit.

---

### Task 7: Open the pull request

**Files:** none.

**Interfaces:**
- Consumes: all four commits from Tasks 2 through 5, plus the design doc commit already on the branch.
- Produces: a PR for review.

- [ ] **Step 1: Ask before pushing**

Pushing and opening a PR needs explicit user approval. Ask, and wait.

- [ ] **Step 2: Review what is about to go out**

```bash
git log --oneline main..HEAD
git diff --stat main..HEAD
```

Expected: five commits, and a diff touching only `docs/superpowers/`, `k8s/apps/kargo/`, and one line of `infra/units/cloudflare/global/tunnels/_locals.tf`.

- [ ] **Step 3: Push**

```bash
git push -u origin FOM-144
```

- [ ] **Step 4: Open the PR**

The change is a migration-shaped one — it spans Kubernetes and Terraform, and it has a manual prerequisite — so it earns the full description tier.

```bash
gh pr create --title "feat(FOM-144): install the kargo control plane" --body "$(cat <<'BODY'
Installs Kargo and puts its UI at kargo.fomiller.com behind Cloudflare Access. No promotion pipelines yet.

## Summary

- New `k8s/apps/kargo/` app. Chart `kargo` 1.11.1, pulled from `oci://ghcr.io/akuity/kargo-charts`.
- Traefik IngressRoute for `kargo.fomiller.com`, pointed at the `kargo-api` Service.
- `kargo.fomiller.com` appended to `protected_hostnames`, so Access gates it with authentik as the IdP.
- Admin password hash and token signing key come from Doppler through external-secrets. Nothing secret is in the repo.

## Why

Groundwork for staged promotion. This PR only stands up the control plane — Projects, Warehouses, and Stages land separately, once there is something worth promoting.

## Note

- Doppler project `kargo`, config `dev`, already holds `ADMIN_ACCOUNT_PASSWORD_HASH` and `ADMIN_ACCOUNT_TOKEN_SIGNING_KEY`. The API pod will not start without them.
- The Terraform half needs an apply. Until then the hostname 404s at the tunnel. The app syncs fine either way, so the order does not matter.
- `api.tls.terminatedUpstream: true` is what makes Kargo generate `https://` URLs while serving plain HTTP. It replaces the header-rewrite middleware authentik needed for the same problem.
- The `kargo` CLI cannot log in through Access — it cannot follow the SSO redirect. Use a port-forward. Native OIDC to authentik is the fix if that starts to hurt.

[FOM-144](https://linear.app/fomiller/issue/FOM-144/install-kargo-control-plane-in-the-homelab-cluster)
BODY
)"
```

- [ ] **Step 5: Post-merge verification**

After the PR merges and the Terraform is applied:

```bash
kubectl -n kargo get externalsecret
kubectl -n kargo get pods
```

Expected: both ExternalSecrets `SecretSynced`, and the api, controller, and management-controller pods `Running`.

If `kargo-api` shows `SecretSyncedError`, the Doppler service account cannot read the `kargo` project — go back to Task 1 Step 5.

Then open `https://kargo.fomiller.com`. Expected: an authentik login, then Kargo's own login, then the UI with an empty project list.

If the UI shell loads but every API call fails, the first thing to check is whether Traefik is downgrading the Connect RPC calls. The container port is named `h2c`; connect-go serves the same protocol over HTTP/1.1, so it should work as routed, but that is the place to look.
