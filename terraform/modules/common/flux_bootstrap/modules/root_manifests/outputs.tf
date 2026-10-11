output "root_kustomization_yaml" {
  description = "Root Flux Kustomization manifest"
  value       = local.root_kustomization_yaml
}

output "vars_env" {
  description = "Data of the vars-env ConfigMap that Flux Kustomizations substitute from"
  value       = local.vars_env
}

output "flux_git_path_to_root_from_clusters_dir" {
  value = local.flux_git_path_to_root_from_clusters_dir
}
