# projects

One file per Argo CD AppProject, and the ApplicationSet that fills it.

| File | What it generates |
| --- | --- |
| `homelab.yaml` | the cluster's own apps, from `k8s/apps/*/config.json` |
| `services.yaml` | services that live in their own repos |

## Adding a service

Two things, and only one of them is here:

1. The service repo has `argocd.yaml` at its root. golden-argocd generates and
   manages it, so it is already there.
2. `services.yaml` lists the repo's URL.

```yaml
# argocd.yaml, in the service's repo
name: blog
env: prod
namespace: blog
notifications: ""
```

```yaml
# services.yaml
- list:
    elements:
      - repoURL: https://github.com/Fomiller/blog.git
        targetRevision: main
```

The generator is a matrix: the list of repo URLs, then a git generator that
reads `argocd.yaml` out of each of those repos. It runs with
`missingkey=error`, so a field missing from `argocd.yaml` fails the generator
rather than rendering an Application with an empty destination.

## Why those facts live in the service repo

A service's name, environment and namespace are the service's own. homelab
used to keep a copy in `k8s/services/<name>/config.yaml`, which meant two files
to change for one rename and nothing that made them agree.

The deployed versions moved for a stronger reason. `chartVersion` and
`imageTag` used to live in that file, written by Kargo. They now live in the
service's own `argocd/overlays/<env>/`: the image tag in `values.app.yaml`, the
chart version in `kustomization.yaml`. A promotion is a commit to the repo that
built the thing, so what is running is readable next to the code.

## One Application, not two

The overlay is a kustomization inflating two charts from ECR: the service's
own, and `kargo-project-chart`. The workload and the pipeline that promotes it
arrive together, which is why there is no `k8s/kargo/` and no
`kargo-projects.yaml` any more.

Argo CD could not do this before. kustomize shells out to the helm binary,
which never saw Argo CD's registry credentials. It has its own now — see
`k8s/apps/cluster-resources`.

## Removing a service

Delete its line from `services.yaml`. `preserveResourcesOnDeletion: false`
means the workloads go with it, rather than being left running with nothing
tracking them.
