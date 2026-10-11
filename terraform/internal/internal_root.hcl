locals {
  # This block is defining a curl request to retrieve data from a specific URL. 
  # The headers include a Vault request and a Vault token retrieved from an environment variable.
  # curl_request = {
  #   method = "GET"
  #   url    = "${get_env("VAULT_ADDR")}/v1/kvv2/data/private/internal/${basename(get_original_terragrunt_dir())}/kubeconfig_clusteradmin"
  #   headers = [
  #     "X-Vault-Request: true",
  #     "X-Vault-Token: ${get_env("VAULT_TOKEN", "")}"
  #   ]
  # }
  # # This line is executing the previously defined curl request and storing the output in the azure_auth variable.
  # curl_result = run_cmd("--terragrunt-quiet", "curl", "-s", "-H", "${local.curl_request.headers[0]}", "-H", "${local.curl_request.headers[1]}", "${local.curl_request.url}")
  # kubeconfig  = yamldecode(jsondecode(local.curl_result).data.data.kubeconfig)

}


# Default inputs for variables 
inputs = {
  # Resource name. Equals to directory name where configuration files stored.
  # Used if it is not provided by the user
  name = "${basename(get_original_terragrunt_dir())}"
  # Do not confuse with clouds provider location.
  # The location of the k8s cluster e.g. Azure, AWS, Local. If variable is not set, then by default will be used name 
  # of the root deployments directory under the ./terraform e.g. "azure", "aws", "local"
  deployment_location = "${basename(get_parent_terragrunt_dir())}"

  # General
  # k8s_url                 = local.kubeconfig.clusters[0].cluster.server 
  # k8s_user_name           = local.kubeconfig.users[0].name 
  # # k8s_user_token          = local.kubeconfig.users[0].user.token
  # k8s_user_cert           = base64decode(local.kubeconfig.users[0].user.client-certificate-data)
  # k8s_user_key            = base64decode(local.kubeconfig.users[0].user.client-key-data) 
  # k8s_cluster_ca          = base64decode(local.kubeconfig.clusters[0].cluster.certificate-authority-data) 
  # k8s_cluster_name        = local.kubeconfig.clusters[0].name == "cluster.local" ? basename(get_original_terragrunt_dir()) : local.kubeconfig.clusters[0].name
}