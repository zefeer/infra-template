variable "name" {}
variable "location" {}
variable "tags" {
  type    = map(string)
  default = {}
}
