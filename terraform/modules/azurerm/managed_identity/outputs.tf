output "id" {
  value = azurerm_user_assigned_identity.uai.id
}
output "client_id" {
  value = azurerm_user_assigned_identity.uai.client_id
}
output "principal_id" {
  value = azurerm_user_assigned_identity.uai.principal_id
}
output "tenant_id" {
  value = azurerm_user_assigned_identity.uai.tenant_id
}