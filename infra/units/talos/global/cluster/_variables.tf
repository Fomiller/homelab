variable "cluster_name" {
  type    = string
  default = "homelab"
}

# The stable, canonical address of the Kubernetes API — baked into every
# node's machine config and into generated certs. Points at the first
# controlplane node; KubePrism (_locals.tf) is what lets other nodes stay
# reachable if this specific node goes down.
variable "cluster_endpoint" {
  type    = string
  default = "https://192.168.0.140:6443"
}

variable "talos_version" {
  type    = string
  default = "v1.11.5"
}

variable "kubernetes_version" {
  type    = string
  default = "v1.34.1"
}

# Disk Talos installs itself onto on each node — must match the actual disk
# device name on the bare-metal boxes (e.g. `lsblk`/`talosctl disks`), not a
# cloud volume ID.
variable "install_disk" {
  type    = string
  default = "/dev/nvme0n1"
}

variable "pod_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

variable "service_cidr" {
  type    = string
  default = "10.96.0.0/12"
}

variable "dns_domain" {
  type    = string
  default = "cluster.local"
}

# External OIDC issuer for Kubernetes service account tokens — see the
# `service-account-issuer` extraArgs in _locals.tf for why this exists.
variable "oidc_issuer_url" {
  type    = string
  default = "https://fomiller-dev-homelab-oidc.s3.us-east-1.amazonaws.com"
}

# Extra SANs for the API server's TLS cert (_locals.tf controlplane_patch).
# Only covers the first CP node today — add the other CP IPs here if you need
# direct HTTPS access to them by IP instead of always going through
# cluster_endpoint/KubePrism.
variable "controlplane_cert_sans" {
  type    = list(string)
  default = ["192.168.0.140"]
}

# Names must match what the Image Factory knows about (see
# data.talos_image_factory_extensions_versions in _data.tf) — this drives
# both the schematic (main.tf) and, indirectly, the kernel modules the
# worker patch assumes are available (_locals.tf).
variable "system_extension_names" {
  type    = list(string)
  default = ["iscsi-tools", "util-linux-tools"]
}

# How talos_machine_configuration_apply (main.tf) applies a changed config:
# "auto" lets Talos pick reboot vs. no-reboot as needed, "no-reboot" fails
# instead of rebooting, "reboot" always reboots.
variable "apply_mode" {
  type    = string
  default = "auto"
}
