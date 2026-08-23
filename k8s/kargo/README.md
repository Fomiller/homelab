# kargo

One directory per Kargo project, each holding a single `config.yaml`. That file
existing is what creates the project — the `kargo-projects` ApplicationSet in
`k8s/projects/kargo-projects.yaml` globs `k8s/kargo/*/config.yaml`.

The Application installs `kargo-project-chart` from ECR and takes its values
from the service's own repo at `kargo/values.yaml`. The pipeline — which
artifacts are watched, which files a promotion writes — is therefore described
by the service, next to the thing being promoted. This file only says that the
cluster runs it.

## config.yaml

```yaml
project: blog-delivery
namespace: blog-delivery
repoURL: https://github.com/Fomiller/blog.git
targetRevision: main
registry: 695434033664.dkr.ecr.us-east-1.amazonaws.com
chartVersion: 0.1.1
```

`project` and `namespace` must match: Kargo requires a project's namespace to
carry its name. Neither may collide with the namespace the service itself runs
in, which is why the blog's project is `blog-delivery` and not `blog`.

## Credentials

A Kargo project reads its credentials from its **own** namespace, found by the
`kargo.akuity.io/cred-type` label. They are not inherited from the `kargo`
control-plane namespace.

Each project therefore needs three Secrets, created by an app under
`k8s/apps/` — see `k8s/apps/kargo-blog-creds`:

| cred-type | What it is |
| --- | --- |
| `git` | The `fomiller-kargo-bot` GitHub App. Kargo mints a short-lived token per promotion from the private key. |
| `image` | ECR, for discovering image tags. |
| `helm` | ECR again. Kargo looks up image and chart credentials independently, so one Secret labelled `image` leaves chart discovery unauthenticated. |

## Where promotions land

Into **this** repo, at `k8s/services/<service>-<env>/config.yaml`, not into the
service's repo. Argo CD cannot read a chart version out of a second repo, so
the deployed versions live here; the image tag sits beside the chart version so
a promotion touches one file.
