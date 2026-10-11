variable "name" {}

variable "rg_name" {}
variable "location" {}

variable "tenant_id" {
  default = null
}
variable "client_id" {
  default = null
}

variable "access_policies" {
  type    = map(any)
  default = {}
}

variable "vault_keys" {
  type    = map(any)
  default = {}
}
variable "vault_secrets" {
  type    = map(any)
  default = {}
}
variable "vault_certificates" {
  type    = map(any)
  default = {}
}

variable "tags" {
  type    = map(any)
  default = {}
}


# Terragrunt specific variables
variable "relative_deployment_path" {}
variable "root_deployments_dir" {}