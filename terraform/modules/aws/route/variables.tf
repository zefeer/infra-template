variable "private_cidrs" {}
variable "public_cidrs" {}
variable "public_subnets" {
  type = map
}
variable "private_subnets" {
  type = map
}
variable "igw" {
}
variable "ngw" {
  type = list
  default = []
}