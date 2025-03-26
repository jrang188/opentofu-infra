variable "tenancy_ocid" {
  default = ""
  type    = string
}

variable "compartment_ocid" {
  default = ""
  type    = string
}

variable "allowed_ip_address" {
  default = []
  type = list(string)
  sensitive = true
}
