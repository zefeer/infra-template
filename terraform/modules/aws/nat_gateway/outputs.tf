output "id" {
  value = [ for ngw in aws_nat_gateway.ngw: ngw.id ]
}