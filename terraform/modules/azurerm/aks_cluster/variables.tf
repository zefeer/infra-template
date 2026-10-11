variable "name" {}
variable "k8s_version" {
  default = null
}

variable "rg_name" {}
variable "location" {}
variable "dns_prefix" {
  default = null
}
variable "automatic_upgrade_channel" {
  type    = string
  default = null
}
variable "default_node_pool" {
  type = map(any)
  default = {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }
}

variable "service_principal" {
  # type    = map
  default = {}
}
variable "identity" {
  # type    = map
  default = {
    type = "SystemAssigned"
  }
}

variable "node_pools" {
  type = map(object({
    name                      = optional(string)
    vm_size                   = optional(string, "Standard_D2_v2")
    node_count                = optional(number, 1)
    auto_scaling_enabled      = optional(bool)
    node_labels               = optional(map(string))
    kubelet_config            = optional(object({
      allowed_unsafe_sysctls    = optional(list(string))
      container_log_max_line    = optional(number)
      container_log_max_size_mb = optional(number)
      cpu_cfs_quota_enabled     = optional(bool)
      cpu_cfs_quota_period      = optional(string)
      cpu_manager_policy        = optional(string)
      image_gc_high_threshold   = optional(number)
      image_gc_low_threshold    = optional(number)
      pod_max_pid               = optional(number)
      topology_manager_policy   = optional(string)
    }))
    linux_os_config           = optional(object({
      swap_file_size_mb             = optional(number)
      transparent_huge_page_enabled = optional(bool)
      transparent_huge_page_defrag  = optional(string)
      sysctl_config                 = optional(object({
        fs_aio_max_nr                      = optional(number)
        fs_file_max                        = optional(number)
        fs_inotify_max_user_watches        = optional(number)
        fs_nr_open                         = optional(number)
        kernel_threads_max                 = optional(number)
        net_core_netdev_max_backlog        = optional(number)
        net_core_optmem_max                = optional(number)
        net_core_rmem_default              = optional(number)
        net_core_rmem_max                  = optional(number)
        net_core_somaxconn                 = optional(number)
        net_core_wmem_default              = optional(number)
        net_core_wmem_max                  = optional(number)
        net_ipv4_ip_local_port_range_max   = optional(number)
        net_ipv4_ip_local_port_range_min   = optional(number)
        net_ipv4_neigh_default_gc_thresh1  = optional(number)
        net_ipv4_neigh_default_gc_thresh2  = optional(number)
        net_ipv4_neigh_default_gc_thresh3  = optional(number)
        net_ipv4_tcp_fin_timeout           = optional(number)
        net_ipv4_tcp_keepalive_intvl       = optional(number)
        net_ipv4_tcp_keepalive_probes      = optional(number)
        net_ipv4_tcp_keepalive_time        = optional(number)
        net_ipv4_tcp_max_syn_backlog       = optional(number)
        net_ipv4_tcp_max_tw_buckets        = optional(number)
        net_ipv4_tcp_tw_reuse              = optional(bool)
        net_netfilter_nf_conntrack_buckets = optional(number)
        net_netfilter_nf_conntrack_max     = optional(number)
        vm_max_map_count                   = optional(number)
        vm_swappiness                      = optional(number)
        vm_vfs_cache_pressure              = optional(number)
      }))
    }))
    node_network_profile      = optional(object({
      node_public_ip_tags = optional(map(string))
    }))
    kubelet_disk_type         = optional(string)
    max_pods                  = optional(number)
    tags                      = optional(map(string))
  }))
  default = {}
}

variable "tags" {
  type    = map(any)
  default = {}
}


# Terragrunt specific variables
variable "relative_deployment_path" {}
variable "root_deployments_dir" {}