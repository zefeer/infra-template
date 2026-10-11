data "azuread_client_config" "current" {}
data "azurerm_subscription" "current" {}

resource "random_uuid" "app_roles_id" {
  for_each = var.app_roles
}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  for_each  = var.required_resource_access
  client_id = data.azuread_application_published_app_ids.well_known.result[each.key]
}

resource "azuread_application" "adapp" {
  display_name     = replace(var.name, "_", "-")
  identifier_uris  = var.identifier_uris
  # logo_image       = filebase64("/path/to/logo.png")
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = var.sign_in_audience

  # api {
  #   mapped_claims_enabled          = true
  #   requested_access_token_version = 2

  #   known_client_applications = [
  #     azuread_application.known1.application_id,
  #     azuread_application.known2.application_id,
  #   ]

  #   oauth2_permission_scope {
  #     admin_consent_description  = "Allow the application to access example on behalf of the signed-in user."
  #     admin_consent_display_name = "Access example"
  #     enabled                    = true
  #     id                         = "96183846-204b-4b43-82e1-5d2222eb4b9b"
  #     type                       = "User"
  #     user_consent_description   = "Allow the application to access example on your behalf."
  #     user_consent_display_name  = "Access example"
  #     value                      = "user_impersonation"
  #   }

  #   oauth2_permission_scope {
  #     admin_consent_description  = "Administer the example application"
  #     admin_consent_display_name = "Administer"
  #     enabled                    = true
  #     id                         = "be98fa3e-ab5b-4b11-83d9-04ba2b7946bc"
  #     type                       = "Admin"
  #     value                      = "administer"
  #   }
  # }

  dynamic "app_role" {
    for_each = var.app_roles

    content {
      allowed_member_types = app_role.value.allowed_member_types
      description          = app_role.value.description
      display_name         = app_role.value.display_name
      enabled              = app_role.value.enabled
      id                   = try(app_role.value.id, random_uuid.app_roles_id[app_role.key].result)
      value                = app_role.value.value
    }
  }

  # feature_tags {
  #   enterprise = true
  #   gallery    = true
  # }

  # optional_claims {
  #   access_token {
  #     name = "myclaim"
  #   }

  #   access_token {
  #     name = "otherclaim"
  #   }

  #   id_token {
  #     name                  = "userclaim"
  #     source                = "user"
  #     essential             = true
  #     additional_properties = ["emit_as_roles"]
  #   }

  #   saml2_token {
  #     name = "samlexample"
  #   }
  # }

  dynamic "required_resource_access" {
    for_each = var.required_resource_access

    content {
      resource_app_id = data.azuread_application_published_app_ids.well_known.result[required_resource_access.key]
      dynamic "resource_access" {
        for_each = required_resource_access.value
        content {
          id   = data.azuread_service_principal.msgraph[required_resource_access.key].oauth2_permission_scope_ids[resource_access.value.id]
          type = resource_access.value.type
        }
      }
    }
  }

  web {
    homepage_url  = try(var.web.homepage_url, null)
    logout_url    = try(var.web.logout_url, null)
    redirect_uris = try(var.web.redirect_uris, null)

    implicit_grant {
      access_token_issuance_enabled = try(var.web.implicit_grant.access_token_issuance_enabled, null)
      id_token_issuance_enabled     = try(var.web.implicit_grant.id_token_issuance_enabled, null)
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      owners
    ]
  }

}

# resource "azuread_application_federated_identity_credential" "fic" {
#   application_object_id = azuread_application.adapp.object_id
#   display_name          = azuread_application.adapp.display_name
#   description           = azuread_application.adapp.description
#   audiences             = ["api://AzureADTokenExchange"]
#   issuer                = "https://token.actions.githubusercontent.com"
#   subject               = "repo:my-organization/my-repo:environment:prod"
# }

resource "azuread_service_principal" "app_sp" {
  client_id                    = azuread_application.adapp.client_id
  app_role_assignment_required = var.app_role_assignment_required
  owners                       = [data.azuread_client_config.current.object_id]
  use_existing   = true
  # feature_tags {
  #   enterprise = true
  #   gallery    = true
  # }

  lifecycle {
    ignore_changes = [
      owners
    ]
  }

}

# resource "azuread_application_registration" "sample_app" {
#   display_name = "venkat-demo-application"
# }
# resource "azuread_service_principal" "azuread_sp" {
#   client_id = azuread_application_registration.sample_app.client_id
#   use_existing   = true
# }
resource "azurerm_role_assignment" "ra" {
  count                = var.app_role_assignment_required ? length(var.roles_to_assign) : 0

  scope                = var.rg_id
  role_definition_name = var.roles_to_assign[count.index]
  principal_id         = azuread_service_principal.app_sp.object_id
}

resource "azuread_application_password" "app_password" {
  application_id = "/applications/${azuread_application.adapp.object_id}"
}