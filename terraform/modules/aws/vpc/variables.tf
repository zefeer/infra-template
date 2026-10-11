variable "aws_region" {}
variable "vpc_cidr" {}
variable "tags" {
  type = map(string)
  default = {}
}