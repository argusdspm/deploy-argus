# Quickstart

Five-minute path to a running agent. For full options see [README.md](README.md).

## Prerequisites

- An Argus account (https://app.argusdspm.com).
- An **enrollment token** for the cloud account you're enrolling. Generate at: dashboard → Cloud Accounts → your account → Generate Enrollment Token. **Treat it like a password** — it is reusable and bootstraps any number of agents.
- For Terraform paths: `terraform >= 1.5` and AWS / Azure credentials in your shell.

## AWS — one-click via CloudFormation

Sign in to the AWS console for the target account, then open:

```
https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/quickcreate?templateURL=https%3A%2F%2Fargusdspm.com%2Fdownloads%2Fcfn%2Fargus-managed-v1.yml&stackName=argus-agent&param_Region=us-east-1
```

Paste your enrollment token into the `EnrollmentToken` field, then **Create stack**. Done in ~5 minutes.

## AWS — Fargate via Terraform

```hcl
# argus.tf
module "argus" {
  source            = "github.com/argusdspm/deploy-argus//modules/argus-agent-fargate?ref=v1.0"
  customer_name     = "production"
  enrollment_token  = var.enrollment_token
  argus_backend_url = "https://api.argusdspm.com"
  vpc_id            = "vpc-xxxxxxxx"
  subnet_ids        = ["subnet-aaaa", "subnet-bbbb"]

  enable_s3_scanning = true
}

variable "enrollment_token" {
  type      = string
  sensitive = true
}
```

```bash
terraform init
terraform apply -var enrollment_token="<paste-enrollment-token>"
```

Watch the Argus dashboard — your cloud account flips to **Connected** within ~60 seconds of agent startup.

## AWS — single EC2 host via Terraform

See `examples/ec2-basic/` for a minimal config. Same pattern as Fargate above, swap the module source to `argus-agent-ec2`.

## Azure ACI (preview)

See `examples/azure-aci/` and `modules/argus-agent-azure-aci/README.md`. Module works but no UI integration in v1.0 — expect minor breaking changes before stable.

## Verify

The dashboard's Cloud Accounts page shows the connection chip flipping to **Connected** once the agent's first heartbeat lands. The Agents page lists the new agent with its runtime kind (EC2 / Fargate / etc.) and last-seen timestamp.

If it doesn't connect within 5 minutes, see `Troubleshooting` in [README.md](README.md).
