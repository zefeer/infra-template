variable "eks_cluster_name" {}
variable "name" {}
variable "iam_role_arn" {}
variable "subnet_ids" {
  type = set(string)
}
variable "instance_types" {
  type = set(string)
}
variable "tags" {
  type = map(string)
  default = {}
}