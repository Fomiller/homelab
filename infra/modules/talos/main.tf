# The Talos "Image Factory" builds a custom installer/boot image on demand from
# a "schematic" — a spec of which system extensions (kernel modules/drivers not
# in the default Talos image) to bake in. This resource just registers that
# spec; `data.talos_image_factory_urls` (in _data.tf) turns it into an actual
# downloadable installer image URL. This replaces manually building/hosting a
# custom Talos ISO/image.
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info[*].name
      }
    }
  })
}

# Generates the cluster's entire PKI in one shot: CA certs, aggregator CA,
# service account key, cluster ID/secret, and the join token — everything
# machines need to trust each other and join the cluster. This is the Talos
# equivalent of `kubeadm init` cert generation.
#
# IMPORTANT: this is generated fresh on first `apply` and then persisted in
# Terraform state. If this resource is ever recreated (state loss, moved,
# tainted, etc.) it mints a BRAND NEW cluster identity — existing nodes will
# reject it. Never `terraform destroy`/recreate this against a live cluster
# without importing/matching the existing secrets first.
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Applies the rendered controlplane machine config (data.talos_machine_configuration.controlplane
# in _data.tf) to every controlplane node. `for_each` means each node is tracked
# as its own resource instance, so a config change only touches the nodes that
# changed instead of forcing a full replace.
#
# apply_mode "auto" lets Talos decide whether the change can be applied live
# or requires a reboot; other options are "no-reboot" (fail instead of
# rebooting) and "reboot" (always reboot).
resource "talos_machine_configuration_apply" "controlplane" {
  for_each = toset(var.controlplane_nodes)

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value
  apply_mode                  = var.apply_mode
}

# Same as above, for worker nodes.
resource "talos_machine_configuration_apply" "worker" {
  for_each = toset(var.worker_nodes)

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value
  apply_mode                  = var.apply_mode
}

# Bootstraps etcd on exactly one controlplane node (Talos requirement — you
# bootstrap once, and that node seeds etcd for the others to join). This is a
# one-time action, not idempotent config — Talos itself ignores repeat
# bootstrap calls once the cluster exists, which is why this is safe to leave
# in place permanently rather than something you run-once-then-delete.
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.controlplane_nodes[0]

  depends_on = [talos_machine_configuration_apply.controlplane]
}
