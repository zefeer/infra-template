variable "public_subnets" {
  type = map
}
variable "eip" {
  type = map
}
variable "tags" {
  type = map(string)
  default = {}
}