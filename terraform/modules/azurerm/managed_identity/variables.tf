variable "name" {}
variable "rg_name" {
  default = null
}
variable "location" {}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "dns_zones" {
  type    = list(string)
  default = []
}
variable "role_definition_name" {}
variable "service_account_name" {}
variable "service_account_namespace" {}
variable "audience" {
  type = list(string)
  default = []
}
variable "issuer" {
  type = string
  default = ""
}

variable "vault_mount_path" {
  description = "Mount point for secret in vault."
  type        = string
  default     = "kvv2"
}

variable "relative_deployment_path" {}
variable "root_deployments_dir" {}