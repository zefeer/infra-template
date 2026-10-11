output "ids" {
  value = {for index, eip in aws_eip.eip: index => eip }
}
output "subnets" {
  value = var.public_subnets
}
