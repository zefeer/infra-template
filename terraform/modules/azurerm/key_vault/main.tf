# Vault names should be globally unique.
data "azurerm_resource_group" "rg" {
  name = var.rg_name
}

resource "random_string" "random_suffix" {
  length  = 3
  special = false
  upper   = false
  keepers = {
    resource_group_id = data.azurerm_resource_group.rg.id
  }
}

data "azurerm_client_config" "current" {}

locals {
  # Vault name cannot be longer than 24 characters. And we are adding a random suffix of 4 characters.
  name = length(replace(var.name, "_", "-")) > 20 ? substr(replace(var.name, "_", "-"), 0, 20) : replace(var.name, "_", "-")

  tenant_id = var.tenant_id != null ? var.tenant_id : data.azurerm_client_config.current.tenant_id
  client_id = var.client_id != null ? var.client_id : data.azurerm_client_config.current.client_id
}

resource "azurerm_key_vault" "vault" {
  name                = "${local.name}-${random_string.random_suffix.result}"
  location            = var.location
  resource_group_name = var.rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id



  # enable virtual machines to access this key vault.
  # NB this identity is used in the example /tmp/azure_auth.sh file.
  #    vault is actually using the vault service principal.
  # enabled_for_deployment = false

  sku_name = "standard"

  dynamic "access_policy" {
    for_each = local.access_policies
    content {
      application_id = try(access_policy.value.application_id, null)
      tenant_id      = access_policy.value.tenant_id
      object_id      = access_policy.value.object_id

      certificate_permissions = try(access_policy.value.certificate_permissions, [])
      key_permissions         = try(access_policy.value.key_permissions, [])
      secret_permissions      = try(access_policy.value.secret_permissions, [])
      storage_permissions     = try(access_policy.value.storage_permissions, [])
    }
  }

  # # TODO does this really need to be so broad? can it be limited to the vault vm?
  # network_acls {
  #   default_action = "Allow"
  #   bypass         = "AzureServices"
  # }

  tags = var.tags
}