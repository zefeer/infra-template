variable "debug" {
  default = false
}

# Where is the cluster located. e.g. Azure, Ionos, AWS, Local
variable "cluster_location" {
  description = "Where is the cluster located. e.g. Azure, Ionos, AWS, Local"
  default     = null
}
variable "deployment_location" {
  description = "root directory for deployments"
  type        = string
  default     = ""
}

## Kubernetes provider
variable "k8s_url" {}
variable "k8s_user_token" {
  default = null
}
variable "k8s_user_key" {
  default = null
}
variable "k8s_user_cert" {
  default = null
}
variable "k8s_cluster_ca" {
  default = null
}
variable "k8s_cluster_name" {}
variable "k8s_insecure" {
  default = false
}

## Github provider
variable "github_token" {
  default = null
}

# Flux variables
variable "flux_version" {
  default = null
}
variable "flux_namespace" {
  default = "flux-system"
}
variable "flux_git_organization" {
  default = null
}
variable "flux_git_repository" {
  default = null
}
variable "flux_git_repo_reference_type" {
  default = "branch"
}
variable "flux_git_repo_reference_value" {
  default = "main"
}
variable "flux_git_repo_path_base" {
  default = "" # Path within the git repository where the flux configuration will be located. Default is root of the repository
}
variable "flux_additional_helm_release_options" {
  description = "Additional options for helm release"
  type        = map(any)
  default     = {}
}
variable "flux_root_kustomization_components" {
  type    = string
  default = "[]"
}
variable "flux_root_kustomization_prune" {
  description = "Prune root kustomization"
  type        = bool
  default     = true
}
variable "env_vars_config_map_name" {
  default = "vars-env"
}
