resource "aws_eip" "eip" {
  for_each = var.public_subnets

  domain = "vpc"
  tags  = var.tags
}
