locals {
  # Detect AWS region from a deployment path component matching a standard region pattern.
  # e.g. path "sandbox/us-east-1/compute_stack/main" → aws_region = "us-east-1"
  # Falls back to AWS_DEFAULT_REGION env var, then "us-east-1".
  # _path_parts_aws = compact(split("/", path_relative_to_include()))
  # _region_matches = [for p in local._path_parts_aws : p
  #   if length(regexall("^(us|eu|ap|sa|ca|me|af|il)-[a-z]+-[0-9]+$", p)) > 0]
  # aws_region = length(local._region_matches) > 0 ? local._region_matches[0] : get_env("AWS_DEFAULT_REGION", "us-east-1")
#   vault_data = <<EOF
# data "vault_generic_secret" "aws_auth" {
#   path = "kvv2/aws/${compact(split("/", path_relative_to_include()))[0]}/user_account"
# }
# EOF
#   privider_aws = <<EOF
# provider "aws" {
#   region     = "${local.aws_region}"
#   access_key = try(data.vault_generic_secret.aws_auth.data["ACCESS_KEY_ID"], get_env("AWS_ACCESS_KEY_ID", ""))
#   secret_key = try(data.vault_generic_secret.aws_auth.data["SECRET_ACCESS_KEY"], get_env("AWS_SECRET_ACCESS_KEY", ""))
# }
# EOF
  aws_region = try(read_terragrunt_config(find_in_parent_folders("account_root.hcl")).inputs.aws_region, get_env("AWS_DEFAULT_REGION", "us-east-1"))
  # read_child = read_terragrunt_config(find_in_parent_folders("account_root.hcl"))
  # # read_child = include.account_root.inputs.aws_region
  # debug = run_cmd("echo", "aws_root -- read_child = ${local.read_child.inputs.aws_region}")
  # debug_aws_region = run_cmd("echo", "aws_root -- aws_region = ${local.aws_region}")
}

generate "aws_provider" {
  path      = "aws_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
# data "vault_generic_secret" "aws_auth" {
#   path = "kvv2/aws/${compact(split("/", path_relative_to_include()))[0]}/user_account"
# }
provider "aws" {
  region     = "${local.aws_region}"
  access_key = "${get_env("AWS_ACCESS_KEY_ID", "")}"
  secret_key = "${get_env("AWS_SECRET_ACCESS_KEY", "")}"
}
EOF
}

# Default inputs for variables
inputs = {
  # Resource name. Equals to directory name where configuration files stored.
  # Used if it is not provided by the user
  name = "${basename(get_terragrunt_dir())}"
  # Do not confuse with clouds provider location.
  # The location of the k8s cluster e.g. Azure, AWS, Local. If variable is not set, then by default will be used name
  # of the root deployments directory under the ./terraform e.g. "azure", "aws", "local"
  deployment_location = "${basename(get_parent_terragrunt_dir())}"
  # AWS region resolved from deployment path or AWS_DEFAULT_REGION env var
  # aws_region = "${get_env("AWS_REGION", "us-east-1")}"
}
