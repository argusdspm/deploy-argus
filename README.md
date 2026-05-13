# Argus DSPM — Deployment Modules

Customer-facing infrastructure-as-code for deploying the Argus DSPM agent into your own cloud account. Your sensitive data never leaves your environment — only metadata and findings summaries are sent to the Argus control plane.

This repo contains:
- **Terraform modules** for AWS EC2, AWS Fargate, and (preview) Azure ACI.
- **CloudFormation template** for one-click AWS EC2 deploy via CFN Quick-Launch.
- **Examples** showing minimal usage for each module.

## Prerequisites

| Cloud | Tools | Auth |
|---|---|---|
| AWS (Terraform) | `terraform >= 1.5`, AWS CLI | Standard AWS credentials in your shell |
| AWS (CloudFormation) | A web browser | AWS console sign-in |
| Azure (preview) | `terraform >= 1.5`, `az` CLI | `az login` |

You will also need an **enrollment token** from the Argus dashboard (Settings → Cloud Accounts → Generate Enrollment Token). Keep it secret — it is reusable and bootstraps any number of agents into the cloud account it was issued for.

## Modules

| Path | Topology | Status |
|---|---|---|
| `modules/argus-agent-ec2` | Single EC2 instance, agent in Docker under systemd | Stable |
| `modules/argus-agent-fargate` | ECS Fargate service (baseline + autoscaled burst) | Stable |
| `modules/argus-agent-azure-aci` | Azure Container Instances | **Preview** — module works but no UI integration in v0.7.6; expect minor breaking changes |

All modules pull the agent image from the public registry `ghcr.io/argusdspm/argus-agent:stable`. No AWS ECR authentication required.

## Terraform — copy-paste

```hcl
module "argus" {
  source            = "github.com/argusdspm/deploy-argus//modules/argus-agent-fargate?ref=v0.7.6"
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
terraform apply -var enrollment_token="<your-enrollment-token>"
```

For the EC2 module, replace `argus-agent-fargate` with `argus-agent-ec2` and follow `examples/ec2-basic`.

## CloudFormation — one-click EC2

Open this URL in a browser logged into the target AWS account:

```
https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/quickcreate?templateURL=https%3A%2F%2Fargusdspm.com%2Fdownloads%2Fcfn%2Fargus-managed-v1.yml&stackName=argus-agent&param_Region=us-east-1
```

The console form will pre-fill stack name and region. **Paste your enrollment token into the `EnrollmentToken` field manually** — it is deliberately not included in the URL to keep the secret out of browser history. Click **Create stack**.

You can also download `cloudformation/argus-agent-ec2.yml` from this repo and upload it directly via the CloudFormation console.

## What gets deployed

- **EC2 / Fargate**: agent container running with a least-privilege task role (S3 read, RDS describe, etc. — only the datastore types you opt in to). The enrollment token sits encrypted in SSM Parameter Store; the agent reads it once at boot and exchanges it for a per-container API key via `/api/v1/agents/bootstrap`.
- **Networking**: outbound HTTPS to `api.argusdspm.com` only. No inbound ports.
- **Secrets**: only the enrollment token is provisioned by Terraform. The post-exchange per-container API key lives inside the running container and is not persisted by the IaC.

The agent never accepts inbound connections from the Argus control plane. All data flow is agent-initiated outbound.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `terraform init` fails fetching the module | Network can't reach `github.com` | Mirror the module to your internal git or download a release tarball |
| Agent container restart-loops with `401 Unauthorized` | Enrollment token expired or rotated | Generate a new token in the Argus dashboard, redeploy |
| Agent logs show `cross-account mismatch` | Agent is running in an AWS account that doesn't match the cloud account it was enrolled for | Confirm the AWS account ID in the agent's IAM role matches the cloud account in the Argus dashboard |
| Cloud account never flips to "Connected" in dashboard | Agent can't reach `api.argusdspm.com` | Check NAT gateway / VPC endpoints / security group egress rules |

Detailed logs live at `/aws/ec2/argus-agent/*` (CloudWatch) for EC2 and `/ecs/argus-agent-baseline` / `/ecs/argus-agent-burst` for Fargate.

## Versioning

Every release is tagged with full semver (`vX.Y.Z`). Pin the tag in your `source = "...?ref=vX.Y.Z"` to avoid breaking changes mid-flight. Pre-v1.0 the tag tracks the agent version; v1.0.0 ships when agent + backend co-release stable. Full policy in `CHANGELOG.md`.

| Tag | Argus agent image | Notes |
|---|---|---|
| `v0.7.5` | `ghcr.io/argusdspm/argus-agent:stable` | Initial public release |
| `v0.7.6` | `ghcr.io/argusdspm/argus-agent:stable` | IAM permission completion: adds the S3 + IAM + Redshift Serverless + CloudWatch read actions the agent has always needed but the IaC never granted. Two new opt-in vars: `enable_iam_discovery`, `enable_remediation`. Backwards-compatible. |

See `CHANGELOG.md` for what changed in each release and `COMPATIBILITY.md` for the deploy-argus ↔ argus version matrix.

## Support

- Issues: https://github.com/argusdspm/deploy-argus/issues
- Docs: https://docs.argusdspm.com
- Status: https://status.argusdspm.com

## License

MIT — see `LICENSE`.
