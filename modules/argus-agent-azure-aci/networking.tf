# Optional VNet + NSG + delegated ACI subnet.
#
# When enable_vnet_integration = false (default) the Container Instance
# runs on Azure's shared ACI network with a public IP, reaching the Argus
# control plane over HTTPS. That's fine for Blob + Cosmos + management-
# plane scanning because both data planes are internet-routable.
#
# When enable_vnet_integration = true (recommended for Azure SQL / Synapse
# private endpoints) we stand up a dedicated VNet and delegate a subnet
# to Microsoft.ContainerInstance/containerGroups. The ACI then inherits
# the VNet's DNS resolution and routing, which is what lets it reach
# private-endpoint Azure SQL servers.

resource "azurerm_virtual_network" "argus" {
  count               = var.enable_vnet_integration ? 1 : 0
  name                = "vnet-${local.name_prefix}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.argus.location
  resource_group_name = azurerm_resource_group.argus.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "argus_aci" {
  count                = var.enable_vnet_integration ? 1 : 0
  name                 = "snet-aci"
  resource_group_name  = azurerm_resource_group.argus.name
  virtual_network_name = azurerm_virtual_network.argus[0].name
  address_prefixes     = [var.subnet_address_prefix]

  # Delegation is required for ACI to deploy into the subnet. Without
  # it terraform apply succeeds but the container never gets an IP.
  delegation {
    name = "aci-delegation"
    service_delegation {
      name = "Microsoft.ContainerInstance/containerGroups"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

resource "azurerm_network_security_group" "argus" {
  count               = var.enable_vnet_integration ? 1 : 0
  name                = "nsg-${local.name_prefix}"
  location            = azurerm_resource_group.argus.location
  resource_group_name = azurerm_resource_group.argus.name
  tags                = local.common_tags

  # Outbound HTTPS to the Argus control plane + Azure management endpoints
  # is the only mandatory rule. Everything else is an opt-in.
  security_rule {
    name                       = "allow-https-outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # SQL egress — only opened when the customer turns on Azure SQL or
  # Synapse scanning. Azure SQL uses 1433; Synapse-on-demand uses the
  # same port.
  dynamic "security_rule" {
    for_each = var.enable_database_egress ? [1] : []
    content {
      name                       = "allow-sql-outbound"
      priority                   = 200
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "1433"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }

  # Explicitly deny everything else outbound so a compromised agent
  # can't call home to an attacker's endpoint. The implicit Azure
  # default is Allow, which we'd rather override.
  security_rule {
    name                       = "deny-all-outbound"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate the NSG with the ACI subnet. Without this the rules exist but
# have no effect on ACI traffic.
resource "azurerm_subnet_network_security_group_association" "argus_aci" {
  count                     = var.enable_vnet_integration ? 1 : 0
  subnet_id                 = azurerm_subnet.argus_aci[0].id
  network_security_group_id = azurerm_network_security_group.argus[0].id
}
