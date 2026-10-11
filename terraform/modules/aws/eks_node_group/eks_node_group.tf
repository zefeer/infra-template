resource "aws_eks_node_group" "eks_ng" {
  cluster_name    = var.eks_cluster_name
  node_group_name = var.name
  node_role_arn   = var.iam_role_arn
  subnet_ids      = var.subnet_ids

  instance_types  = var.instance_types

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  # depends_on = [
  #   aws_iam_role_policy_attachment.example-AmazonEKSWorkerNodePolicy,
  #   aws_iam_role_policy_attachment.example-AmazonEKS_CNI_Policy,
  #   aws_iam_role_policy_attachment.example-AmazonEC2ContainerRegistryReadOnly,
  # ]
  tags          = var.tags
}