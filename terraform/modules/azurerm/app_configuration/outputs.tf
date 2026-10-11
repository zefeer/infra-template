output "tenant_id" {
  value = azurerm_app_configuration.appconf #.identity[0].tenant_id
}