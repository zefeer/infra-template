variable "name" {}
variable "description" {}
variable "assume_role_policy" {}
variable "managed_policy_arns" {
  default = []
}
variable "inline_policies" {
  default = {}
}
variable "tags" {}