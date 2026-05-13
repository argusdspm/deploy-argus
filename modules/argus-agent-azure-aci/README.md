# argus-agent-azure-aci (PREVIEW)

> **PREVIEW STATUS** — This module works against `api.argusdspm.com` but is not yet wired into the Argus dashboard's Deploy Agent flow. Variable interface, defaults, and outputs may change in minor breaking ways before the `v1.x` stable line. Pin `?ref=v0.7.6` in your `source` to insulate yourself from changes.

Terraform module that deploys the Argus DSPM agent on Azure Container Instances. Resource and variable names mirror the AWS modules so operators can move between clouds without re-learning the contract.

## Quickstart

```hcl
module "argus_azure" {
  source = "github.com/argusdspm/deploy-argus//modules/argus-agent-azure-aci?ref=v0.7.6"

  customer_name     = "acme"
  enrollment_token   = var.enrollment_token
  argus_backend_url = "https://api.argusdspm.com"
  azure_region      = "eastus"

  # Opt in per datastore type
  enable_blob_scanning      = true
  enable_azure_sql_scanning = true
}

variable "enrollment_token" {
  type      = string
  sensitive = true
}
```

```bash
terraform init
terraform apply -var enrollment_token="<your-enrollment-token>"
```

## State file warning

The Azure Service Principal's client secret is written to the Terraform state in plaintext (standard behaviour for any Terraform provider that manages credentials). Use a remote backend with encryption at rest — never commit the state file to git, and avoid local `terraform.tfstate` for production:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstateargus"
    container_name       = "state"
    key                  = "argus-agent-azure/terraform.tfstate"
  }
}
```

## Variables

See `variables.tf`. Required: `customer_name`, `enrollment_token`, `argus_backend_url`, `azure_region`. Common opt-ins: `enable_blob_scanning`, `enable_azure_sql_scanning`, `enable_cosmos_db_scanning`, `enable_synapse_scanning`.

## Outputs

See `outputs.tf`. The container fetches its API key from the bootstrap-token exchange at startup; no `agent_id` / `agent_api_key` to hand-wire.

## What gets deployed

- Azure Container Instance running `ghcr.io/argusdspm/argus-agent` (overridable via `agent_container_image`)
- User-assigned Managed Identity with the role assignments needed for the enabled datastore types
- Log Analytics workspace + diagnostic settings

The agent connects outbound to `api.argusdspm.com` only. No inbound ports.
