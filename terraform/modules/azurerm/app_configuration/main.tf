# resource "azurerm_resource_provider_registration" "rpr" {
#   name = "Microsoft.AppConfiguration"
# }

resource "azurerm_user_assigned_identity" "uai" {
  name                = replace(var.name, "_", "-")
  resource_group_name = var.rg_name
  location            = var.location
}

# resource "azurerm_app_configuration" "appconf" {
#   name                = replace(var.name, "_", "-")
#   resource_group_name = var.rg_name
#   location            = var.location
# }

resource "azurerm_app_configuration" "appconf" {
  name                       = replace(var.name, "_", "-")
  resource_group_name        = var.rg_name
  location                   = var.location
  sku                        = "standard"
  local_auth_enabled         = true
  public_network_access      = "Enabled"
  purge_protection_enabled   = false
  soft_delete_retention_days = 1

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.uai.id,
    ]
  }

  # encryption {
  #   key_vault_key_identifier = azurerm_key_vault_key.example.id
  #   identity_client_id       = azurerm_user_assigned_identity.example.client_id
  # }

  tags = var.tags

  depends_on = [
    azurerm_user_assigned_identity.uai
    # azurerm_key_vault_access_policy.server,
  ]
}
