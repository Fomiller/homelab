# talos cluster

Machine config for the Talos nodes. Node lists and both config patches live in
`_locals.tf`.

## Adding a worker node

1. Add its IP to `local.worker_nodes` in `_locals.tf`.
2. Merge. The apply pushes the worker patch to the new node, which joins.
3. **Label it by hand — this step can't be skipped:**

   ```sh
   kubectl label node <node-name> node-role.kubernetes.io/worker=
   ```

Step 3 is not optional and is not something the apply can do for you.
`worker_patch` declares `node-role.kubernetes.io/worker` in `machine.nodeLabels`,
but the NodeRestriction admission plugin forbids a kubelet from modifying any
`node-role.kubernetes.io/*` label on its own Node, in either direction. Talos's
`NodeApplyController` runs with node identity on workers, so it cannot create
the label. Controlplanes are unaffected — their apply path has controlplane
privileges, which is why they get it from config alone.

Until you run it, the node shows `ROLES <none>` and Talos logs this every ~10
seconds, forever:

```
k8s.NodeApplyController  nodes "<node>" is forbidden:
  is not allowed to modify labels: node-role.kubernetes.io/worker
```

Same log line means the opposite problem if the label is on a node but missing
from `worker_patch` — then Talos is trying to *remove* it. Check which direction
before reaching for `kubectl`.

## Time sync

`machine.time.servers` is pinned to Cloudflare's anycast IPs rather than
`time.cloudflare.com`. During the 2026-08-09 outage every controlplane resolved
that hostname to an address that didn't answer, and Talos's sync controller
resolves once and retries the same address forever. etcd, kubelet and trustd all
gate on time sync, so the cluster stayed down for 40 minutes until someone
rebooted by hand. See [FOM-126](https://linear.app/fomiller/issue/FOM-126).

Talos still uses its built-in default (`time.cloudflare.com`) for the first ~2
seconds of boot, before machine config loads. That's unavoidable from config —
the config is what replaces it. It's also harmless: the interface isn't up yet,
so those lookups fail, and the pinned IPs take over well before anything can
depend on the clock.

Checking a node:

```sh
talosctl -n <ip> get timeservers -o json | jq -c .spec   # want the two IPs
talosctl -n <ip> get timestatus  -o json | jq -c .spec   # want synced: true
```
