# Example: Azure ACI deployment (PREVIEW)

> **PREVIEW** — The `argus-agent-azure-aci` module is not yet wired into the Argus dashboard's Deploy Agent UI. The module works end-to-end, but expect minor breaking changes before the v1.x stable line. Pin `?ref=v0.7.6` in your `source` to insulate yourself.

Minimal Terraform configuration that deploys the Argus agent on Azure Container Instances using the `argus-agent-azure-aci` module.

## Usage

```bash
az login

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set customer_name, azure_region, datastore opt-ins, etc.

terraform init
terraform apply -var enrollment_token="<your-enrollment-token>"
```

## Verifying

The Argus dashboard's Cloud Accounts page flips your Azure account to **Connected** within ~60 seconds. Logs land in the Log Analytics workspace the module provisions.

```bash
az container logs --resource-group <rg> --name argus-agent-<customer> --follow
```

## Limitations (preview)

- No UI integration — agent must be enrolled via the dashboard's "Add Cloud Account" form, then bootstrap-token-deployed via this module.
- Variable interface may change before stable. Read `CHANGELOG.md` before upgrading the `?ref=` tag.

See `../../modules/argus-agent-azure-aci/README.md` for module-level details.
