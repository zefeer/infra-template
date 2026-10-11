output "id" {
  value = azurerm_kubernetes_cluster.aks.id
}

# output "kubeconfig_vault" {
#   value = "${var.root_deployments_dir}/${var.relative_deployment_path}"
# }

output "k8s_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
  sensitive = false
}

output "k8s_url" {
  value = azurerm_kubernetes_cluster.aks.kube_config[0].host
  sensitive = true
}

output "k8s_user_name" {
  value = azurerm_kubernetes_cluster.aks.kube_config[0].username
  sensitive = true
}

output "k8s_user_token" {
  value = azurerm_kubernetes_cluster.aks.kube_config[0].password
  sensitive = true
}

output "k8s_client_crt" {
  value = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  sensitive = true
}

output "k8s_client_key" {
  value = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  sensitive = true
}

output "k8s_cluster_ca" {
  value = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  sensitive = true
}

output "k8s_kubeconfig" {
  value = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

# output "k8s_cluster_data" {
#   value     = data.ionoscloud_k8s_cluster.k8s_cluster
#   sensitive = true
# }

# output "tls_private_key_main" {
#   value = tls_private_key.main
#   sensitive = true
# }