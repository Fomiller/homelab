locals {
  controlplane_nodes = ["192.168.0.140", "192.168.0.192", "192.168.0.196"]
  worker_nodes       = ["192.168.0.212", "192.168.0.197", "192.168.0.181", "192.168.0.179", "192.168.0.213"]

  # Machine config patch shared by controlplane and worker nodes. Talos
  # machine config is normally generated whole (`talosctl gen config`) then
  # "patched" — merging this map with the generated defaults is the
  # Terraform-provider equivalent of a `--config-patch` file.
  common_machine_patch = {
    machine = {
      # IPs, not time.cloudflare.com, so DNS is out of the boot path.
      #
      # After the 2026-08-09 outage all three controlplanes resolved that
      # hostname to 139.78.100.163 (Oklahoma State, not Cloudflare) and every
      # NTP query timed out. Talos's sync controller resolves once and retries
      # the same address forever, so the cluster sat at synced:false for 40
      # minutes. etcd, kubelet and trustd are all gated on time sync, so
      # nothing came up until someone rebooted by hand.
      #
      # Both addresses are Cloudflare on purpose. A second provider would
      # survive Cloudflare being unreachable, but Cloudflare and Google smear
      # leap seconds differently, and mixing them makes the sources disagree
      # for a day around a leap second. One provider, two anycast addresses.
      time = {
        servers = [
          "162.159.200.123",
          "162.159.200.1",
        ]
      }
      kubelet = {
        # Applies the container runtime's default seccomp profile to every pod
        # instead of running unconfined — a security hardening default.
        defaultRuntimeSeccompProfileEnabled = true
        # Talos normally watches /etc/kubernetes/manifests for static pods to
        # run; disabling this means only pods you explicitly define via the
        # `machine.pods` field (unused here) run as static pods. Off by
        # default in this config since nothing uses that directory.
        disableManifestsDirectory = true
      }
      install = {
        disk = var.install_disk
        # The custom installer image built by the Image Factory (see main.tf
        # / _data.tf) — has the iscsi/util-linux extensions baked in, unlike
        # the stock Talos installer.
        image = data.talos_image_factory_urls.this.urls.installer
        # false = don't wipe the install disk on every apply. Only relevant
        # the first time Talos installs itself to disk.
        wipe = false
      }
      features = {
        rbac           = true # Enable Kubernetes RBAC (default in modern Talos, explicit here).
        stableHostname = true # Hostname stays consistent across reboots instead of being regenerated.
        # Extended Key Usage check on client certs presented to apid (the
        # Talos API daemon) — rejects certs that aren't actually meant for
        # client auth, tightening the Talos API's own TLS trust.
        apidCheckExtKeyUsage = true
        # XFS project quota support on the ephemeral partition/user disks —
        # needed for some CSI drivers (e.g. Longhorn) to enforce volume size
        # limits at the filesystem level.
        diskQuotaSupport = true
        # KubePrism: a local load-balancing proxy each node runs so the
        # kubelet/pods can reach the API server via 127.0.0.1:<port> instead
        # of a single hardcoded controlplane IP — gives basic control-plane HA
        # without needing an external LB in front of the API servers.
        kubePrism = {
          enabled = true
          port    = 7445
        }
        # Talos runs a local DNS resolver on the host and forwards the
        # cluster's CoreDNS queries through it — lets pods resolve
        # hostnames/upstreams via whatever DNS the host itself is configured
        # with.
        hostDNS = {
          enabled              = true
          forwardKubeDNSToHost = true
        }
      }
    }
    cluster = {
      network = {
        dnsDomain      = var.dns_domain
        podSubnets     = [var.pod_cidr]
        serviceSubnets = [var.service_cidr]
      }
      # Cluster membership discovery — how nodes find each other besides the
      # static node list you gave Terraform.
      discovery = {
        enabled = true
        registries = {
          # Disabled: don't use the k8s API itself as a discovery source
          # (chicken-and-egg risk before the API is up, and one less thing
          # depending on API availability).
          kubernetes = { disabled = true }
          # Enabled with defaults: use Sidero's hosted discovery service
          # instead, purely for peer discovery/handshake — no cluster secrets
          # are exposed to it (traffic is encrypted, discovery service only
          # brokers connection info).
          service = {}
        }
      }
    }
  }

  # Controlplane-only patch, merged on top of the common patch above.
  controlplane_patch = yamlencode(merge(local.common_machine_patch, {
    machine = merge(local.common_machine_patch.machine, {
      nodeLabels = {
        # Marks controlplane nodes so cloud/external LB integrations skip them
        # when picking backend targets — standard k8s well-known label, not
        # Talos-specific, just applied here via machine config instead of
        # `kubectl label`.
        "node.kubernetes.io/exclude-from-external-load-balancers" = ""
        # Controlplane nodes are schedulable (allowSchedulingOnControlPlanes
        # below), so label them "worker" too — ROLES then shows
        # "control-plane,worker" instead of just "control-plane", reflecting
        # that they actually run workload pods.
        "node-role.kubernetes.io/worker" = ""
      }
      # Same iSCSI/nbd kernel modules as workers — controlplane nodes are now
      # schedulable (see cluster.allowSchedulingOnControlPlanes below) and run
      # Longhorn replicas too, so they need the same storage module support.
      kernel = {
        modules = [
          { name = "nbd" },
          { name = "iscsi_tcp" },
          { name = "iscsi_generic" },
          { name = "configfs" },
        ]
      }
    })
    cluster = merge(local.common_machine_patch.cluster, {
      # Set when only 2 worker nodes existed and the 3 controlplanes sat idle
      # while those 2 got overloaded (root cause of a kubelet
      # health-check-timeout / NodeNotReady flapping incident). There are 5
      # workers now, so this is less load-bearing than it was, but turning it
      # off would evict whatever currently runs on the controlplanes.
      allowSchedulingOnControlPlanes = true
      apiServer = {
        # Extra SANs so the API server's TLS cert is valid when reached via
        # these IPs (needed since cluster_endpoint / kubePrism etc. all
        # ultimately point back at this node).
        certSANs = var.controlplane_cert_sans
        # PSP was removed from upstream Kubernetes; this just disables the
        # legacy Talos-managed PSP manifests. Pod Security Admission is the
        # replacement, and Talos already ships a PodSecurity admissionControl
        # plugin by default (baseline/restricted, kube-system exempted —
        # byte-identical to what used to be declared here explicitly). Don't
        # redeclare it: this field is a list of unstructured plugin configs,
        # and merging a patch with the same content as the default appends
        # into its nested arrays instead of replacing them — e.g.
        # `exemptions.namespaces` ends up `["kube-system", "kube-system"]`,
        # which kube-apiserver's own PodSecurityConfiguration validation
        # rejects as a duplicate, crash-looping the API server.
        disablePodSecurityPolicy = true
        # Audit every request at "Metadata" level (who/what/when, not full
        # request/response bodies) — lightweight audit trail without the
        # storage/perf cost of full-body logging.
        auditPolicy = {
          apiVersion = "audit.k8s.io/v1"
          kind       = "Policy"
          rules      = [{ level = "Metadata" }]
        }
        # Points the API server at your own OIDC-compatible issuer (an S3
        # static site hosting the OIDC discovery doc/JWKS — see cp1/jwks.json
        # and cp1/openid-configuration) instead of the default cluster-local
        # issuer. Needed for things like IRSA-style workload identity that
        # expect a real, externally-resolvable issuer URL.
        extraArgs = {
          "service-account-issuer" = var.oidc_issuer_url
        }
      }
    })
  }))

  # Worker-only patch, merged on top of the common patch above.
  worker_patch = yamlencode(merge(local.common_machine_patch, {
    machine = merge(local.common_machine_patch.machine, {
      nodeLabels = {
        # Declared here but NOT applied by Talos on workers. NodeRestriction
        # forbids a kubelet from modifying node-role.kubernetes.io/* on its own
        # Node, and NodeApplyController runs with node identity here. It's
        # declared anyway so Talos doesn't try to *remove* a label that was set
        # out-of-band, which is its own forbidden-error loop.
        #
        # A new worker still needs `kubectl label node <name>
        # node-role.kubernetes.io/worker=` once. See README.md.
        "node-role.kubernetes.io/worker" = ""
      }
      # Kernel modules workers need for iSCSI-backed storage (Longhorn etc.)
      # and network block devices — not loaded by default in the stock Talos
      # kernel.
      kernel = {
        modules = [
          { name = "nbd" },
          { name = "iscsi_tcp" },
          { name = "iscsi_generic" },
          { name = "configfs" },
        ]
      }
    })
    cluster = merge(local.common_machine_patch.cluster, {
      # Workers don't run the API server, but this apiServer.extraArgs block
      # still needs to match the controlplane's issuer setting — Talos
      # validates cluster-wide config consistency across node types for
      # anything under `cluster.*`.
      apiServer = {
        extraArgs = {
          "service-account-issuer" = var.oidc_issuer_url
        }
      }
    })
  }))
}
