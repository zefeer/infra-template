
locals {
  vault_result_subpaths = toset(
    compact(
      concat(
        var.vault_additional_subpaths, 
        var.create_default_vault_secrets == true ? [var.vault_kv_default_subpath]: []
      )
    )
  )
}


resource "vault_kv_secret_v2" "kv" {

  depends_on = [
      azuread_application.adapp,
      azuread_application_password.app_password
    ]

  for_each = var.create_vault_secrets ? { for s in sort(local.vault_result_subpaths) : s => s } : {}


  mount               = var.vault_mount_path
  name                = "${each.value}/azuread/${var.name}/auth"
  cas                 = 1
  delete_all_versions = true

  data_json = jsonencode(
    {
      client_id = azuread_application.adapp.client_id
      object_id = azuread_application.adapp.object_id
      application_secret = azuread_application_password.app_password.value
      tenant_id = data.azuread_client_config.current.tenant_id
      subscription_id = data.azurerm_subscription.current.subscription_id
    }
  )
}

