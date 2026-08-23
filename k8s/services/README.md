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
  "registry": "695434033664.dkr.ecr.us-east-1.amazonaws.com",
  "chartVersion": "0.2.0",
  "namespace": "blog"
}
```

Every key is required. The ApplicationSet runs with `missingkey=error`, so a
missing one fails the generator rather than rendering an Application with an
empty field.

| Key | What it does |
| --- | --- |
| `service` | Names the Application, together with `env`. Also names the chart: `<service>-chart`. |
| `env` | Picks the overlay values file: `argocd/overlays/<env>/values.app.yaml` from the service's own repo. |
| `repoURL` | The service's repo, not this one. Supplies the values files, and nothing else. |
| `targetRevision` | Branch or tag the values are read from. |
| `registry` | OCI registry holding the chart. Must appear in the `services` AppProject `sourceRepos`. |
| `chartVersion` | Chart version to run. **This is the deployed version** — changing it is what releases. |
| `namespace` | Created by Argo CD if absent, and labelled for the ECR pull secret. |

Directory names are not read. Name them `<service>-<env>` so two environments
of one service do not collide.

## Why two sources

The Application pulls the chart straight from ECR and reads its values from the
service's repo. It does not render the repo's kustomize overlay.

That is not a style choice. Argo CD cannot pull a private OCI chart through
kustomize's `helmCharts`: it hands the kustomize helm invocation a fresh empty
`HELM_CONFIG_HOME` and never writes registry credentials into it, so the pull
fails with `basic credential not found` no matter how the repository Secret is
declared. A native Helm source with the same credential works.

The consequence worth knowing: anything that used to sit in the overlay
directory as a plain manifest is no longer rendered. It belongs in the chart.
The Traefik route is the example — see `ingressRoute.host` in the chart's
values.

## Why the files live here and not in the service repo

The generator has to read them from a repo Argo CD already watches, and it
watches this one. A service repo carries its own chart and values; this file is
the cluster's decision to run that service at that version, which belongs with
the cluster.

## Removing a service

Delete its directory. `preserveResourcesOnDeletion: false` on the
ApplicationSet means the workloads go with it, rather than being left running
with nothing tracking them.
