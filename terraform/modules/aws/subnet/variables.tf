variable "aws_region" {}
variable "subnets" {
  type = map(object({
    subnet_cidr = string
    subnet_az   = optional(string)
    public      = optional(bool, false)
    tags        = optional(map(string), {})
  }))
  default = {}
}
variable "vpc_id" {}
variable "tags" {
  type = map(string)
  default = {}
}