# Standard kubeconfig — same as you'd get from `talosctl kubeconfig`.
output "kubeconfig" {
  value     = data.talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

# Talos API client config (talosctl's equivalent of a kubeconfig) — needed to
# run any `talosctl` command against these nodes.
output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

# The generated cluster PKI/secrets bundle (see talos_machine_secrets in
# main.tf). Exposed so it can be captured/imported elsewhere if this module's
# state ever needs to be rebuilt without minting a new cluster identity.
output "machine_secrets" {
  value     = talos_machine_secrets.this.machine_secrets
  sensitive = true
}

# Not sensitive — just an identifier for the Image Factory schematic (main.tf),
# useful for manually re-deriving the installer image URL or debugging what
# extensions a given schematic bundles.
output "schematic_id" {
  value = talos_image_factory_schematic.this.id
}

# The custom installer image URL nodes are configured to install from
# (_locals.tf machine.install.image) — handy for cross-checking against
# what's actually running on a node.
output "installer_image" {
  value = data.talos_image_factory_urls.this.urls.installer
}
