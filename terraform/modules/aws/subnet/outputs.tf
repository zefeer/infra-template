output "ids" {
  value = [for subnet in aws_subnet.subnet: subnet.id ]
}

output "private_subnets" {
  value = {for index, subnet in aws_subnet.subnet: index => { id = subnet.id, rt_id = aws_route_table.rt[index].id } if subnet.map_public_ip_on_launch == false }
}

output "public_subnets" {
  value = {for index, subnet in aws_subnet.subnet: index => { id = subnet.id, rt_id = aws_route_table.rt[index].id } if subnet.map_public_ip_on_launch == true }
}
