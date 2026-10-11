variable "flux_namespace" {
  type    = string
  default = "flux-system"
}
variable "cluster_location" {
  description = "Where the cluster is located, e.g. internal, azure, aws. Second level under flux/clusters/"
  type        = string
}
variable "k8s_cluster_name" {
  description = "Cluster directory name under flux/clusters/<cluster_location>/"
  type        = string
}
variable "flux_git_repo_path_base" {
  description = "Path within the git repository where the flux configuration is located"
  type        = string
  default     = ""
}
variable "flux_root_kustomization_components" {
  description = "YAML/JSON list rendered as is into spec.components of the root Kustomization"
  type        = string
  default     = "[]"
}
variable "flux_root_kustomization_prune" {
  type    = bool
  default = true
}
variable "env_vars_config_map_name" {
  type    = string
  default = "vars-env"
}
