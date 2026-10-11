output "name" {
  value = aws_eks_cluster.eks.name
}

output "role_arn" {
  value = aws_eks_cluster.eks.role_arn
}

output "subnet_ids" {
  value = flatten([for vpc_config in aws_eks_cluster.eks.vpc_config: vpc_config.subnet_ids ])
}