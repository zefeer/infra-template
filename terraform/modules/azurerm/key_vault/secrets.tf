resource "azurerm_key_vault_key" "vault_key" {
  for_each = var.vault_keys

  key_vault_id = azurerm_key_vault.vault.id
  name         = replace(each.value.key_name, "_", "-")
  key_type     = each.value.key_type
  key_size     = each.value.key_size
  key_opts     = each.value.key_opts
}