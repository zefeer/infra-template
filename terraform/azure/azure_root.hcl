locals {
  AZURE_SUBSCRIPTION_ID = get_env("AZURE_SUBSCRIPTION_ID", "")
  AZURE_TENANT_ID = get_env("AZURE_TENANT_ID", "")
  AZURE_CLIENT_ID = get_env("AZURE_CLIENT_ID", "")
  AZURE_CLIENT_SECRET = get_env("AZURE_CLIENT_SECRET", "")
}


generate "azure_provider" {
  path      = "azure_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
# data "vault_generic_secret" "azure_auth" {
#   path = "kvv2/azure/${compact(split("/", path_relative_to_include()))[0]}/user_account"
# }
provider "azurerm" {
  features {}
  subscription_id   = "${local.AZURE_SUBSCRIPTION_ID}"
  tenant_id         = "${local.AZURE_TENANT_ID}"
  client_id         = "${local.AZURE_CLIENT_ID}"
  client_secret     = "${local.AZURE_CLIENT_SECRET}"
}
provider "azuread" {
  use_cli           = false
  tenant_id         = "${local.AZURE_TENANT_ID}"
  client_id         = "${local.AZURE_CLIENT_ID}"
  client_secret     = "${local.AZURE_CLIENT_SECRET}"
}
EOF
}

# Default inputs for variables 
inputs = {
  # Resource name. Equals to directory name where configuration files stored.
  # Used if it is not provided by the user
  name = "${basename(get_terragrunt_dir())}"
  # Do not confuse with clouds provider location.
  # The location of the k8s cluster e.g. Azure, Ionos, AWS, Local. If variable is not set, then by default will be used name 
  # of the root deployments directory under the ./terraform e.g. "azure", "ionos", "aws", "local"
  deployment_location = "${basename(get_parent_terragrunt_dir())}"

}