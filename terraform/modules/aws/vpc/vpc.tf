resource "aws_vpc" "vpc" {
  region     = var.aws_region
  cidr_block = var.vpc_cidr
  tags       = var.tags
}