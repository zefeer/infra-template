terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.0.0"
    }
  }
}