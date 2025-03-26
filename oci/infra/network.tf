resource "oci_core_virtual_network" "vcn" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "vcn-ussanjose-1"
  dns_label      = "VcnUSSJC1"
}

resource "oci_core_subnet" "public_subnet" {
  cidr_block        = "10.1.10.0/24"
  display_name      = "public-subnet"
  dns_label         = "PublicSubnet"
  security_list_ids = [oci_core_security_list.public_security_list.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.vcn.id
  route_table_id    = oci_core_route_table.route_table.id
  dhcp_options_id   = oci_core_virtual_network.vcn.default_dhcp_options_id
}

resource "oci_core_subnet" "private_subnet" {
  cidr_block        = "10.1.20.0/24"
  display_name      = "private-subnet"
  dns_label         = "PrivateSubnet"
  security_list_ids = [oci_core_security_list.private_security_list.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.vcn.id
  route_table_id    = oci_core_route_table.route_table.id
  dhcp_options_id   = oci_core_virtual_network.vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "vcn-ig"
  vcn_id         = oci_core_virtual_network.vcn.id
}

resource "oci_core_route_table" "route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "vcn-routetable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.internet_gateway.id
  }
}

resource "oci_core_security_list" "public_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "public-vcn-security-list"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  dynamic "ingress_security_rules" {
    for_each = var.allowed_ip_address
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        max = 22
        min = 22
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.allowed_ip_address
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        max = 80
        min = 80
      }
    }
  }


  dynamic "ingress_security_rules" {
    for_each = var.allowed_ip_address
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        max = 443
        min = 443
      }
    }
  }
}

resource "oci_core_security_list" "private_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "private-vcn-security-list"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "10.1.0.0/16"
  }
}
