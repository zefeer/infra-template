output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}
output "application_id" {
  value = azuread_application.adapp.client_id
}
output "client_id" {
  value = azuread_application.adapp.client_id
}
output "object_id" {
  value = azuread_application.adapp.object_id
}
output "application_secret" {
  value = azuread_application_password.app_password.value
  sensitive = true
}
output "sp_object_id" {
  value = azuread_service_principal.app_sp.object_id
}
output "web" {
  value = azuread_application.adapp.web[0]
}

