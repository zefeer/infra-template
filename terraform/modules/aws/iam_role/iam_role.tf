resource "aws_iam_role" "iam_role" {
  name        = var.name
  description = var.description

  assume_role_policy  = jsonencode(var.assume_role_policy)
  managed_policy_arns = var.managed_policy_arns
  dynamic "inline_policy" {
    for_each = var.inline_policies
    content {
      name   = inline_policy.key
      policy = jsonencode(inline_policy.value)
    }
  }

  tags          = var.tags
}