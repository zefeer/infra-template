include "tf_root" {
  path = find_in_parent_folders("root.hcl")
}
include "internal_root" {
  path = find_in_parent_folders("internal_root.hcl")
}

locals {
  kubeconfig = yamldecode(file("~/.kube/config"))
}

inputs = {
  # General
  k8s_cluster_name = "example-cluster" #basename(get_terragrunt_dir())
  k8s_url          = local.kubeconfig.clusters[0].cluster.server
  k8s_user_name    = local.kubeconfig.users[0].name
  k8s_user_cert    = base64decode(local.kubeconfig.users[0].user.client-certificate-data)
  k8s_user_key     = base64decode(local.kubeconfig.users[0].user.client-key-data)
  k8s_cluster_ca   = base64decode(local.kubeconfig.clusters[0].cluster.certificate-authority-data)

  # Flux bootstrap
  install_flux = true

  flux_version                       = "2.9.6" # Flux version, not chart version. Module will find the chart version based on this value
  flux_git_organization              = "CHANGE-ME-github-org"
  flux_git_repository                = "infra-template"
  flux_git_repo_reference_type       = "branch"
  flux_git_repo_reference_value      = "main"
  flux_git_repo_path_base            = "flux" # Path within the git repository where the flux configuration will be located. Default is root of the repository
  flux_root_kustomization_components = "[]"
}