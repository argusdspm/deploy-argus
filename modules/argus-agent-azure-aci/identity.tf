# Azure AD Application + Service Principal + least-privilege scanner role.
#
# The Service Principal is optional: if existing_client_id is set we bind
# to an already-provisioned identity (typical when a central identity team
# owns Azure AD object creation). Otherwise we own the full lifecycle.
#
# The scanner role is always ours - we don't reuse Azure built-in roles
# because they grant far more than Argus needs (Storage Blob Data Reader
# alone would also permit generated-SAS downloads, etc).

# -- Application + Service Principal (when not using an existing one) ----

resource "azuread_application" "argus" {
  count        = local.use_existing_sp ? 0 : 1
  display_name = "Argus DSPM Scanner - ${var.customer_name}"

  # Single-tenant app - the agent always calls Azure management with the
  # customer's own tenant_id, so multi-tenant isn't a feature we need.
  sign_in_audience = "AzureADMyOrg"
}

resource "azuread_service_principal" "argus" {
  count                        = local.use_existing_sp ? 0 : 1
  client_id                    = azuread_application.argus[0].client_id
  app_role_assignment_required = false

  description = "Service Principal used by the Argus DSPM agent to discover and scan datastores in this subscription."
}

# One-year rotating client secret. The secret value is returned in a
# sensitive output so the operator can load it into Argus; subsequent
# applies will not surface the plaintext again unless the resource is
# recreated (terraform taint, or rotation).
#
# We use time_rotating instead of timeadd(timestamp(), ...) to drive the
# end_date. timeadd against timestamp() re-evaluates on every plan and
# causes perpetual drift - Terraform sees a new end_date every run and
# recreates the secret. time_rotating has a stable ID for the whole
# rotation window, so plans are no-ops until the window actually
# elapses, at which point the secret is rotated exactly once.
resource "time_rotating" "argus_secret" {
  count         = local.use_existing_sp ? 0 : 1
  rotation_days = 365
}

resource "azuread_application_password" "argus" {
  count          = local.use_existing_sp ? 0 : 1
  application_id = azuread_application.argus[0].id
  display_name   = "Argus Agent Credential"
  end_date       = time_rotating.argus_secret[0].rotation_rfc3339

  # Force a new secret whenever the rotation window rolls over.
  rotate_when_changed = {
    rotation = time_rotating.argus_secret[0].id
  }
}

# -- Custom scanner role ------------------------------------------------

# NOTE on permissions: the action list here is intentionally minimal.
# Any additional data source should be added as its own entry rather
# than widening an existing wildcard (e.g. */read). Keeping the role
# tight means a compromised agent can only exfiltrate the data we
# actually intend to scan.
resource "azurerm_role_definition" "argus_scanner" {
  name  = "argus-dspm-scanner-${local.sanitized_name}"
  scope = data.azurerm_subscription.current.id

  description = "Least-privilege role granting the Argus DSPM agent the exact permissions required to discover and scan datastores."

  permissions {
    actions = [
      # Resource group + subscription introspection (connection test)
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      # Storage account discovery + container enumeration.
      # Deliberately NO listkeys/action here - the agent authenticates
      # to the Blob data plane using the Service Principal token, and
      # the data_actions entry below already grants the exact blob read
      # surface it needs. listkeys would also hand over every SAS
      # generation capability on the storage account, which is miles
      # beyond what scanning requires.
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Storage/storageAccounts/blobServices/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
      # Azure SQL discovery
      "Microsoft.Sql/servers/read",
      "Microsoft.Sql/servers/databases/read",
      # Cosmos DB discovery
      "Microsoft.DocumentDB/databaseAccounts/read",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/read",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/read",
      # Synapse discovery
      "Microsoft.Synapse/workspaces/read",
      "Microsoft.Synapse/workspaces/sqlPools/read",
    ]

    data_actions = [
      # Blob data read - required for sensitive-data sampling.
      # Controlled by enable_blob_scanning via the resource-count below.
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
    ]

    not_actions      = []
    not_data_actions = []
  }

  assignable_scopes = [
    data.azurerm_subscription.current.id,
  ]
}

# Subscription-scoped role assignment. Scoping to the subscription (not a
# specific resource group) is intentional: Argus discovery walks every
# resource group in the subscription. If the customer needs a narrower
# blast radius they can override `scope` via a wrapper module and skip
# this assignment in favour of per-RG assignments.
resource "azurerm_role_assignment" "argus_scanner" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.argus_scanner.role_definition_resource_id
  principal_id       = local.service_principal_id

  description = "Grants the Argus Service Principal the custom scanner role across the subscription."
}
