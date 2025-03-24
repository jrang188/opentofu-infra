terraform {
  required_providers {
    oci = {
      source  = "opentofu/oci"
      version = "6.3.0"
    }
  }
}


provider "oci" {
  region              = "us-sanjose-1"
  auth                = "SecurityToken"
  config_file_profile = "DEV"
}
