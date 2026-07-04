# Looks up the actual installable version string for each extension name in
# var.system_extension_names (e.g. "iscsi-tools" -> "siderolabs/iscsi-tools:v0.1.4"),
# pinned to this talos_version. Feeds into the schematic in main.tf — the
# schematic itself just lists extension names, this resolves them to real
# image references the Image Factory can build with.
data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = var.system_extension_names
  }
}

# Given the schematic id (main.tf) + talos_version + platform, returns the
# actual installer image URL for that combination — this is what gets set as
# `machine.install.image` in the machine config (_locals.tf) so newly-installed
# nodes get the extensions baked in. platform = "metal" because these are bare
# metal boxes, not a cloud provider VM image.
data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "metal"
}

# Renders the full controlplane machine config YAML (the equivalent of
# `talosctl gen config` + patches) using the secrets from main.tf and the
# patch in _locals.tf. This is a data source, not a resource — the actual
# node-side effect happens in talos_machine_configuration_apply (main.tf).
# Nothing here talks to a node; it's pure local rendering.
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.controlplane_patch]
}

# Same rendering, for worker nodes.
data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.worker_patch]
}

# Renders a `talosconfig` file (the Talos API client config — think kubeconfig,
# but for talking to the Talos API/apid on port 50000 instead of the k8s API).
# `endpoints` is where talosctl connects to issue commands; `nodes` is the
# default set of nodes a command targets when you don't pass `-n` explicitly.
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = var.controlplane_nodes
  nodes                = concat(var.controlplane_nodes, var.worker_nodes)
}

# Fetches the kubeconfig for the cluster straight from a controlplane node's
# Talos API — no separate `talosctl kubeconfig` step needed. depends_on
# bootstrap because the kubeconfig doesn't exist/isn't meaningful until etcd
# has actually been bootstrapped.
data "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.controlplane_nodes[0]

  depends_on = [talos_machine_bootstrap.this]
}
