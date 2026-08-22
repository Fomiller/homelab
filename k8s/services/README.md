# services

One directory per service per environment. Each holds a single `config.json`,
and that file existing is what creates the Argo CD Application — the `services`
ApplicationSet in `k8s/projects/services.yaml` globs `k8s/services/*/config.json`.

Nothing else registers a service. There is no list to add to.

## config.json

```json
{
  "service": "blog",
  "env": "prod",
  "repoURL": "https://github.com/Fomiller/blog.git",
  "targetRevision": "main",
  "namespace": "blog"
}
```

Every key is required. The ApplicationSet runs with `missingkey=error`, so a
missing one fails the generator rather than rendering an Application with an
empty field.

| Key | What it does |
| --- | --- |
| `service` | Names the Application, together with `env`. |
| `env` | Also picks the overlay: the Application syncs `argocd/overlays/<env>` from the service's own repo. |
| `repoURL` | The service's repo, not this one. The `services` AppProject only allows `https://github.com/Fomiller/*`. |
| `targetRevision` | Branch or tag Argo CD tracks. |
| `namespace` | Created by Argo CD if absent, and labelled for the ECR pull secret. |

Directory names are not read. Name them `<service>-<env>` so two environments
of one service do not collide.

## Why the files live here and not in the service repo

The generator has to read them from a repo Argo CD already watches, and it
watches this one. A service repo carries its own overlays and chart; this file
is the cluster's decision to run that service, which belongs with the cluster.

## Removing a service

Delete its directory. `preserveResourcesOnDeletion: false` on the
ApplicationSet means the workloads go with it, rather than being left running
with nothing tracking them.
