terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = ">=15.10.0"
    }
    shell = {
      source  = "scottwinkler/shell"
      version = "1.7.3"
    }
  }
}
provider "gitlab" {
  base_url = var.gitlab_url
  token    = var.gitlab_token
}