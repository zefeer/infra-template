resource "aws_nat_gateway" "ngw" {
  for_each      = var.public_subnets

  allocation_id = lookup(var.eip[each.value.id], "allocation_id", null) 
  subnet_id     = each.value.id

  tags          = var.tags

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  # depends_on = [aws_internet_gateway.example]
}