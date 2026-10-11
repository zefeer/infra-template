locals {
  # access policy for the user that is currently running terraform.
  # Full access
  default_access_policies = {
    current_user = {
      tenant_id = data.azurerm_client_config.current.tenant_id
      object_id = data.azurerm_client_config.current.object_id

      certificate_permissions = [
        "Backup", "Create", "Delete", "DeleteIssuers", "Get", "GetIssuers", "Import", "List", "ListIssuers", "ManageContacts",
        "ManageIssuers", "Purge", "Recover", "Restore", "SetIssuers", "Update"
      ]
      key_permissions = [
        "Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import", "List", "Purge", "Recover", "Restore",
        "Sign", "UnwrapKey", "Update", "Verify", "WrapKey", "Release", "Rotate", "GetRotationPolicy", "SetRotationPolicy"
      ]
      secret_permissions = [
        "Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"
      ]
      storage_permissions = [
        "Backup", "Delete", "DeleteSAS", "Get", "SetSAS", "List", "ListSAS", "Purge", "Recover", "RegenerateKey",
        "Restore", "Set", "SetSAS", "Update"
      ]
    },
    devops_group = {
      tenant_id = data.azurerm_client_config.current.tenant_id
      object_id = "0b90fb72-0383-4b01-8952-4bd23490b530"

      certificate_permissions = [
        "Get", "List"
      ]
      key_permissions = [
        "Get", "List"
      ]
      secret_permissions = [
        "Get", "List"
      ]
      storage_permissions = [
        "Get", "List"
      ]
    }
  }
  access_policies = merge(
    var.access_policies,
    local.default_access_policies
  )
}

# resource "azurerm_key_vault_access_policy" "access_policy" {
#   for_each = var.access_policies

#   key_vault_id = azurerm_key_vault.vault.id

#   application_id = try(each.value.application_id, null)
#   tenant_id      = each.value.tenant_id
#   object_id      = each.value.object_id

#   certificate_permissions = try(each.value.certificate_permissions, [])
#   key_permissions         = try(each.value.key_permissions, [])
#   secret_permissions      = try(each.value.secret_permissions, [])
#   storage_permissions     = try(each.value.storage_permissions, [])
# }