locals {
  # The location of the k8s cluster e.g. Azure, Ionos, AWS, Local. If variable is not set, then by default will be used name
  # of the root deployments directory under the ./terraform e.g. "azure", "ionos", "aws", "local"
  cluster_location = var.cluster_location != null ? lower(var.cluster_location) : var.deployment_location
}

output "DEBUG_OUTPUTS_00" {
  value = var.debug ? {
    "flux_git_path_to_root_from_clusters_dir" = module.flux_root_manifests.flux_git_path_to_root_from_clusters_dir
  } : null
}
