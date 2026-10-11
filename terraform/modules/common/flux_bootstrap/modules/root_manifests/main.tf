## Pure rendering of what flux_bootstrap puts into the cluster for Flux: the root Kustomization
## and the vars-env ConfigMap data. No providers, so it can be rendered anywhere (CI included):
##   terraform init -backend=false && terraform apply -auto-approve

locals {
  patch_target_flux_resources        = "HelmRelease|ImagePolicy|ImageRepository|ImageUpdateAutomation|Kustomization|Alert|Provider|Receiver|Bucket|GitRepository|HelmChart|HelmRepository|OCIRepository"
  patch_target_except_flux_resources = "!HelmRelease|!ImagePolicy|!ImageRepository|!ImageUpdateAutomation|!Kustomization|!Alert|!Provider|!Receiver|!Bucket|!GitRepository|!HelmChart|!HelmRepository|!OCIRepository"

  # "../" per path segment of flux_git_repo_path_base, e.g. "flux" -> "../"
  flux_git_path_to_root_from_clusters_dir = "${join("/", [for i in range(0, length(split("/", trim(var.flux_git_repo_path_base, "/")))) : ".."])}/"

  root_kustomization_yaml = templatefile("${path.module}/templates/root-kustomization.yaml.tftpl", {
    flux_namespace                          = var.flux_namespace
    cluster_location                        = var.cluster_location
    cluster_name                            = var.k8s_cluster_name
    flux_git_repo_path_base                 = var.flux_git_repo_path_base
    flux_git_path_to_root_from_clusters_dir = local.flux_git_path_to_root_from_clusters_dir
    patch_target_flux_resources             = local.patch_target_flux_resources
    env_vars_config_map_name                = var.env_vars_config_map_name
    components                              = var.flux_root_kustomization_components
    prune                                   = var.flux_root_kustomization_prune
  })

  vars_env = {
    "cluster_location"                        = var.cluster_location
    "cluster_name"                            = var.k8s_cluster_name
    "base_flux_gitsource_name"                = var.flux_namespace
    "base_flux_gitsource_secret_name"         = "${var.flux_namespace}-auth"
    "patch_target_flux_resources"             = local.patch_target_flux_resources
    "patch_target_except_flux_resources"      = local.patch_target_except_flux_resources
    "flux_git_repo_path_base"                 = var.flux_git_repo_path_base
    "flux_git_path_to_root_from_clusters_dir" = local.flux_git_path_to_root_from_clusters_dir
  }
}
