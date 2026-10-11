resource "aws_subnet" "subnet" {
  for_each = var.subnets

  vpc_id     = var.vpc_id
  region     = var.aws_region
  cidr_block = each.value.subnet_cidr
  availability_zone = try(each.value.subnet_az, null)
  map_public_ip_on_launch = try(each.value.public, false)
  tags = merge(each.value.tags, var.tags)
}

resource "aws_route_table" "rt" {
  for_each = var.subnets
  vpc_id = var.vpc_id
  region = var.aws_region
  
  tags = merge(each.value.tags, var.tags)
}


resource "aws_route_table_association" "rta" {
  for_each       = var.subnets

  region         = var.aws_region
  route_table_id = aws_route_table.rt[each.key].id
  subnet_id      = aws_subnet.subnet[each.key].id
}