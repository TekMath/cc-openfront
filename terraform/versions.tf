terraform {
  required_version = ">= 1.5"

  required_providers {
    clevercloud = {
      source  = "CleverCloud/clevercloud"
      version = "~> 2.3"
    }
  }
}
