# services

**This directory is on its way out.** The `services` ApplicationSet no longer
reads it. Its files stay only until the last service listed here has moved to
the shape below, and then the directory goes.

## How a service is registered now

Two things, and neither of them is a file here:

1. The service repo has `argocd.yaml` at its root. golden-argocd generates and
   manages it, so it is already there.
2. `k8s/projects/services.yaml` lists the repo's URL.

The ApplicationSet is a matrix: the list of repo URLs, then a git generator
that reads `argocd.yaml` out of each of those repos.

```yaml
# argocd.yaml, in the service's repo
name: blog
env: prod
namespace: blog
notifications: ""
```

```yaml
# k8s/projects/services.yaml
- list:
    elements:
      - repoURL: https://github.com/Fomiller/blog.git
        targetRevision: main
```

The generator runs with `missingkey=error`, so a field missing from
`argocd.yaml` fails the generator rather than rendering an Application with an
empty destination.

## Why the facts moved to the service repo

A service's name, environment and namespace are the service's own. Keeping
homelab's copy of them meant two files to change for one rename, and nothing
that made them agree.

The deployed versions moved for a stronger reason. `chartVersion` and
`imageTag` used to live in this directory, written by Kargo. They now live in
the service's own `argocd/overlays/<env>/`: the image tag in `values.app.yaml`,
the chart version in `kustomization.yaml`. A promotion is a commit to the repo
that built the thing, so what is running is readable next to the code.

## One Application, not two

The overlay is a kustomization inflating two charts from ECR: the service's
own, and `kargo-project-chart`. The workload and the pipeline that promotes it
arrive together, so `k8s/kargo/` has nothing left to do either.

Argo CD could not do this before. kustomize shells out to the helm binary,
which never saw Argo CD's registry credentials. It has its own now — see
`k8s/apps/cluster-resources`.

## Removing a service

Delete its line from `k8s/projects/services.yaml`.
`preserveResourcesOnDeletion: false` means the workloads go with it, rather
than being left running with nothing tracking them.
