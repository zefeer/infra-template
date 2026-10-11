variable "public_subnets" {
  type = set(string)
}
variable "tags" {
  type = map(string)
  default = {}
}
