resource "azurerm_user_assigned_identity" "uai" {
  location            = var.location
  name                = replace(var.name, "_", "-")
  resource_group_name = var.rg_name
  tags                = var.tags
}

data "azurerm_dns_zone" "get_zone" {
  count               = length(var.dns_zones)
  name                = var.dns_zones[count.index]
  resource_group_name = var.rg_name
}

resource "azurerm_role_assignment" "ra" {
  count                = length(data.azurerm_dns_zone.get_zone)
  scope                = data.azurerm_dns_zone.get_zone[count.index].id
  role_definition_name = var.role_definition_name
  principal_id         = azurerm_user_assigned_identity.uai.principal_id
}

resource "azurerm_federated_identity_credential" "fic" {
  name                = var.name
  resource_group_name = var.rg_name
  audience            = var.audience
  issuer              = var.issuer
  parent_id           = azurerm_user_assigned_identity.uai.id
  subject             = "system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"
}

resource "vault_kv_secret_v2" "uai_output" {
  mount               = var.vault_mount_path
  name                = "${var.root_deployments_dir}/${var.relative_deployment_path}"
  cas                 = 1
  delete_all_versions = true
  data_json = jsonencode(
    {
      id = azurerm_user_assigned_identity.uai.id
      client_id = azurerm_user_assigned_identity.uai.client_id
      principal_id = azurerm_user_assigned_identity.uai.principal_id
      tenant_id = azurerm_user_assigned_identity.uai.tenant_id
    }
  )
}