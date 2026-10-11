variable "name" {}

variable "rg_name" {
  default = null
}
variable "rg_id" {
  default = null
}
variable "location" {}

variable "identifier_uris" {
  type    = list(string)
  default = []
}
variable "sign_in_audience" {
  type    = string
  default = "AzureADMyOrg"
}
variable "app_roles" {
  type    = map(any)
  default = {}
}

variable "required_resource_access" {
  type    = map(any)
  default = {}
}

variable "web" {
  type    = map(any)
  default = {}
}

variable "app_role_assignment_required" {
  type    = bool
  default = false
}
variable "roles_to_assign" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = set(string)
  default = []
}


# Terragrunt specific variables
variable "relative_deployment_path" {}
variable "root_deployments_dir" {}

### variable for vault

variable "create_vault_secrets" {
  type = bool
  default = false
  nullable    = false
}

variable "create_default_vault_secrets" {
  type = bool
  default = true
  nullable    = false
}

variable "vault_mount_path" {
  description = "Mount point for secret in vault."
  type        = string
  default     = "kvv2"
  nullable    = false
}

variable "vault_mount_default_subpath" {
  description = "Mount subpath for default secret in vault."
  type        = string
  default     = "private"
  nullable    = false
}

variable "vault_kv_default_subpath" {
  description = "Default subpath for kv."
  type        = string
  default     = null
}

variable "vault_additional_subpaths" {
  description = "Subpath to secret in moint point."
  type       = list(string)
  default     = []
}
