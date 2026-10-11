variable "name" {}

variable "rg_name" {}
variable "location" {}

variable "tags" {
  type    = map(any)
  default = {}
}


# Terragrunt specific variables
variable "relative_deployment_path" {}
variable "root_deployments_dir" {}