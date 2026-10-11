## Root Kustomization and vars-env data are rendered by a provider-less module, so CI can
## render exactly what this module applies (see terraform/modules/common/flux_bootstrap/modules/root_manifests)

module "flux_root_manifests" {
  source = "./modules/root_manifests"

  flux_namespace                     = var.flux_namespace
  cluster_location                   = local.cluster_location
  k8s_cluster_name                   = var.k8s_cluster_name
  flux_git_repo_path_base            = var.flux_git_repo_path_base
  flux_root_kustomization_components = var.flux_root_kustomization_components
  flux_root_kustomization_prune      = var.flux_root_kustomization_prune
  env_vars_config_map_name           = var.env_vars_config_map_name
}
