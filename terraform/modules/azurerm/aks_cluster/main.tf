locals {
  dns_prefix = var.dns_prefix != null ? var.dns_prefix : var.name
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.name
  location            = var.location
  resource_group_name = var.rg_name
  dns_prefix          = replace(local.dns_prefix, "_", "-")

  kubernetes_version        = var.k8s_version
  automatic_upgrade_channel = var.automatic_upgrade_channel

  dynamic "default_node_pool" {
    for_each = var.default_node_pool != {} ? [var.default_node_pool] : []
    content {
      name       = default_node_pool.value.name
      node_count = default_node_pool.value.node_count
      vm_size    = default_node_pool.value.vm_size
      orchestrator_version = var.k8s_version
    }
  }
  dynamic "service_principal" {
    for_each = var.service_principal != {} ? [var.service_principal] : []
    content {
      client_id     = try(service_principal.value.client_id, null)
      client_secret = try(service_principal.value.client_secret, null)
    }
  }
  dynamic "identity" {
    for_each = var.identity != {} ? [var.identity] : []
    content {
      type = identity.value.type
      # identity_ids = lookup(identity.value, "identity_ids", {})
    }
  }

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "aks_np" {
  for_each = var.node_pools

  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  name                  = replace(try(each.value.name, each.key), "_", "-")
  vm_size               = try(each.value.vm_size, "Standard_D2_v2")
  node_count            = try(each.value.node_count, 1)
  auto_scaling_enabled  = try(each.value.auto_scaling_enabled, null)
  node_labels           = try(each.value.node_labels, null)
  orchestrator_version  = azurerm_kubernetes_cluster.aks.kubernetes_version
  dynamic "kubelet_config" {
    for_each = try(each.value.kubelet_config, {}) != {} ? [each.value.kubelet_config] : []
    content {
      allowed_unsafe_sysctls    = try(kubelet_config.value.allowed_unsafe_sysctls, null)
      container_log_max_line    = try(kubelet_config.value.container_log_max_line, null)
      container_log_max_size_mb = try(kubelet_config.value.container_log_max_size_mb, null)
      cpu_cfs_quota_enabled     = try(kubelet_config.value.cpu_cfs_quota_enabled, null)
      cpu_cfs_quota_period      = try(kubelet_config.value.cpu_cfs_quota_period, null)
      cpu_manager_policy        = try(kubelet_config.value.cpu_manager_policy, null)
      image_gc_high_threshold   = try(kubelet_config.value.image_gc_high_threshold, null)
      image_gc_low_threshold    = try(kubelet_config.value.image_gc_low_threshold, null)
      pod_max_pid               = try(kubelet_config.value.pod_max_pid, null)
      topology_manager_policy   = try(kubelet_config.value.topology_manager_policy, null)
    }
  }
  dynamic "linux_os_config" {
    for_each = try(each.value.linux_os_config, {}) != {} ? [each.value.linux_os_config] : []
    content {
      swap_file_size_mb             = try(linux_os_config.value.swap_file_size_mb, null)
      transparent_huge_page_enabled = try(linux_os_config.value.transparent_huge_page_enabled, null)
      transparent_huge_page_defrag  = try(linux_os_config.value.transparent_huge_page_defrag, null)
      dynamic "sysctl_config" {
        for_each = try(linux_os_config.value.sysctl_config, {}) != {} ? [linux_os_config.value.sysctl_config] : []
        content {
          fs_aio_max_nr                      = try(sysctl_config.value.fs_aio_max_nr, null)
          fs_file_max                        = try(sysctl_config.value.fs_file_max, null)
          fs_inotify_max_user_watches        = try(sysctl_config.value.fs_inotify_max_user_watches, null)
          fs_nr_open                         = try(sysctl_config.value.fs_nr_open, null)
          kernel_threads_max                 = try(sysctl_config.value.kernel_threads_max, null)
          net_core_netdev_max_backlog        = try(sysctl_config.value.net_core_netdev_max_backlog, null)
          net_core_optmem_max                = try(sysctl_config.value.net_core_optmem_max, null)
          net_core_rmem_default              = try(sysctl_config.value.net_core_rmem_default, null)
          net_core_rmem_max                  = try(sysctl_config.value.net_core_rmem_max, null)
          net_core_somaxconn                 = try(sysctl_config.value.net_core_somaxconn, null)
          net_core_wmem_default              = try(sysctl_config.value.net_core_wmem_default, null)
          net_core_wmem_max                  = try(sysctl_config.value.net_core_wmem_max, null)
          net_ipv4_ip_local_port_range_max   = try(sysctl_config.value.net_ipv4_ip_local_port_range_max, null)
          net_ipv4_ip_local_port_range_min   = try(sysctl_config.value.net_ipv4_ip_local_port_range_min, null)
          net_ipv4_neigh_default_gc_thresh1  = try(sysctl_config.value.net_ipv4_neigh_default_gc_thresh1, null)
          net_ipv4_neigh_default_gc_thresh2  = try(sysctl_config.value.net_ipv4_neigh_default_gc_thresh2, null)
          net_ipv4_neigh_default_gc_thresh3  = try(sysctl_config.value.net_ipv4_neigh_default_gc_thresh3, null)
          net_ipv4_tcp_fin_timeout           = try(sysctl_config.value.net_ipv4_tcp_fin_timeout, null)
          net_ipv4_tcp_keepalive_intvl       = try(sysctl_config.value.net_ipv4_tcp_keepalive_intvl, null)
          net_ipv4_tcp_keepalive_probes      = try(sysctl_config.value.net_ipv4_tcp_keepalive_probes, null)
          net_ipv4_tcp_keepalive_time        = try(sysctl_config.value.net_ipv4_tcp_keepalive_time, null)
          net_ipv4_tcp_max_syn_backlog       = try(sysctl_config.value.net_ipv4_tcp_max_syn_backlog, null)
          net_ipv4_tcp_max_tw_buckets        = try(sysctl_config.value.net_ipv4_tcp_max_tw_buckets, null)
          net_ipv4_tcp_tw_reuse              = try(sysctl_config.value.net_ipv4_tcp_tw_reuse, null)
          net_netfilter_nf_conntrack_buckets = try(sysctl_config.value.net_netfilter_nf_conntrack_buckets, null)
          net_netfilter_nf_conntrack_max     = try(sysctl_config.value.net_netfilter_nf_conntrack_max, null)
          vm_max_map_count                   = try(sysctl_config.value.vm_max_map_count, null)
          vm_swappiness                      = try(sysctl_config.value.vm_swappiness, null)
          vm_vfs_cache_pressure              = try(sysctl_config.value.vm_vfs_cache_pressure, null)
        }
      }
    }
  }
  dynamic "node_network_profile" {
    for_each = try(each.value.node_network_profile, {}) != {} ? [each.value.node_network_profile] : []
    content {
      node_public_ip_tags = try(node_network_profile.value.node_public_ip_tags, null)
    }
  }
  kubelet_disk_type = try(each.value.kubelet_disk_type, null)
  max_pods          = try(each.value.max_pods, null)
  tags              = try(each.value.tags, null)
}


# resource "azurerm_kubernetes_cluster_extension" "aks_extention" {
#   name           = "${replace(var.name, "_", "-")}-flux"
#   cluster_id     = azurerm_kubernetes_cluster.aks.id
#   extension_type = "microsoft.flux"
# }

# # Gitlab configuration

# resource "tls_private_key" "main" {
#   # count = var.bootstrap_flux ? 1 : 0

#   algorithm   = "ECDSA"
#   ecdsa_curve = "P256"
# }

# data "gitlab_project" "main" {
#   path_with_namespace = "${var.flux_git_organization}/${var.flux_git_repository}"
# }

# resource "gitlab_deploy_key" "main" {
#   # count = var.bootstrap_flux ? 1 : 0

#   project  = "${var.flux_git_organization}/${var.flux_git_repository}"
#   title    = replace(var.name, "_", "-")
#   key      = tls_private_key.main.public_key_openssh
#   can_push = true
# }

# locals {
#   git_ssh_addr     = regex("^.*@(?P<hostname>[\\w\\.]*):*(?P<port>[\\d]*).*", data.gitlab_project.main.ssh_url_to_repo)
#   known_hosts_host = "${local.git_ssh_addr.port != "" ? "[" : null}${local.git_ssh_addr.hostname}${local.git_ssh_addr.port != "" ? "]:" : null}${local.git_ssh_addr.port}"
#   known_hosts_key  = tls_private_key.main.public_key_openssh
# }

# data "shell_script" "ssh_keyscan" {
#   lifecycle_commands {
#     read = <<-EOF
#           echo "{\"known_hosts_entry\": \"$(ssh-keyscan -p ${local.git_ssh_addr.port != "" ? local.git_ssh_addr.port : "22"} ${local.git_ssh_addr.hostname} | grep ecdsa-sha2-nistp256)\"}"
#         EOF
#   }
# }


# # Flux configuration

# resource "azurerm_kubernetes_flux_configuration" "fc" {

#   name       = "${replace(var.name, "_", "-")}-fc"
#   cluster_id = azurerm_kubernetes_cluster.aks.id
#   namespace  = var.flux_namespace != null ? var.flux_namespace : "flux-system"
#   scope      = var.flux_scope != null ? var.flux_scope : "cluster"

#   git_repository {
#     url                    = data.gitlab_project.main.ssh_url_to_repo
#     reference_type         = var.flux_git_repo_reference_type != null ? var.flux_git_repo_reference_type : "branch"
#     reference_value        = var.flux_git_repo_reference_value != null ? var.flux_git_repo_reference_value : "main"
#     https_user             = var.flux_git_repo_https_user != null ? var.flux_git_repo_https_user : null
#     https_key_base64       = var.flux_git_repo_https_key_base64 != null ? var.flux_git_repo_https_key_base64 : null
#     ssh_private_key_base64 = var.flux_git_repo_ssh_private_key_base64 != null ? var.flux_git_repo_ssh_private_key_base64 : base64encode(tls_private_key.main.private_key_pem)
#     ssh_known_hosts_base64 = var.flux_git_repo_ssh_known_hosts_base64 != null ? var.flux_git_repo_ssh_known_hosts_base64 : base64encode(data.shell_script.ssh_keyscan.output["known_hosts_entry"])
#   }
#   kustomizations {
#     name                       = var.flux_kustomization_name != null ? var.flux_kustomization_name : "flux-system"
#     path                       = var.flux_kustomization_path != null ? var.flux_kustomization_path : "./clusters/${replace(var.name, "_", "-")}"
#     garbage_collection_enabled = true
#   }

#   depends_on = [
#     azurerm_kubernetes_cluster_extension.aks_extention,
#     tls_private_key.main
#   ]
# }