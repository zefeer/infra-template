resource "azurerm_kubernetes_cluster_extension" "aks_ext" {
  name           = "example-ext"
  cluster_id     = azurerm_kubernetes_cluster.test.id
  extension_type = "microsoft.flux"
}

resource "azurerm_kubernetes_flux_configuration" "example" {
  name       = "example-fc"
  cluster_id = azurerm_kubernetes_cluster.test.id
  namespace  = "flux"

  git_repository {
    url             = "https://github.com/Azure/arc-k8s-demo"
    reference_type  = "branch"
    reference_value = "main"
  }

  kustomizations {
    name = "kustomization-1"
  }

  depends_on = [
    azurerm_kubernetes_cluster_extension.example
  ]
}