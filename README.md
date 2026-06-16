# Argus DSPM - Deployment Modules

Customer-facing infrastructure-as-code for deploying the Argus DSPM agent into your own cloud account. Your sensitive data never leaves your environment - only metadata and findings summaries are sent to the Argus control plane.

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

You will also need an **enrollment token** from the Argus dashboard (Settings → Cloud Accounts → Generate Enrollment Token). Keep it secret - it is reusable and bootstraps any number of agents into the cloud account it was issued for.

## Modules

| Path | Topology | Status |
|---|---|---|
| `modules/argus-agent-ec2` | Single EC2 instance, agent in Docker under systemd | Stable |
| `modules/argus-agent-fargate` | ECS Fargate service (baseline + autoscaled burst) | Stable |
| `modules/argus-agent-azure-aci` | Azure Container Instances | **Preview** - module works but no UI integration in v0.7.6; expect minor breaking changes |

All modules pull the agent image from the public registry `ghcr.io/argusdspm/argus-agent:stable`. No AWS ECR authentication required.

## Terraform - copy-paste

The module assumes you already have an `aws` provider configured. In a fresh
project, drop the following in a `providers.tf` next to your `main.tf`:

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-2" # match the region you want the agent to run in
}
```

Then `main.tf`:

```hcl
module "argus" {
  source            = "github.com/argusdspm/deploy-argus//modules/argus-agent-fargate?ref=v0.7.7"
  customer_name     = "production"
  enrollment_token  = var.enrollment_token
  argus_backend_url = "https://api.argusdspm.com"
  vpc_id            = "vpc-xxxxxxxx"
  subnet_ids        = ["subnet-aaaa", "subnet-bbbb"]

  # Set true when your subnets are public (default-VPC style) and have no NAT
  # gateway. Leave false (the default) when running in private subnets that
  # reach the internet via NAT.
  assign_public_ip = false

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

The module reads the AWS region from the configured provider via
`data.aws_region.current`. Set `aws_region` explicitly only if you want a
different region than the provider.

For the EC2 module, replace `argus-agent-fargate` with `argus-agent-ec2` and follow `examples/ec2-basic`.

## ECS task JSON - manual task definition

For teams that manage ECS tasks directly (console, CDK, custom CLI) without
Terraform. You bring an ECS cluster, two IAM roles, a security group, and an
AWS Secrets Manager secret holding the enrollment token; the snippet is just
the task definition itself.

**1. Store the enrollment token in Secrets Manager:**

```bash
aws secretsmanager create-secret \
  --name argus-agent/enrollment-token \
  --secret-string "<paste-token-here>"
```

Note the returned `ARN` - the task definition references it.

**2. Create two IAM roles:**

- An **execution role** (used by ECS to read the secret + ship logs).
- A **task role** (the agent process identity for datastore scan).

Trust policy for both: `ecs-tasks.amazonaws.com`. Permissions are in the
[IAM policy](#iam-policy) section below.

**3. Task definition** (replace the four `<...>` placeholders):

```json
{
  "family": "argus-agent",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512", "memory": "1024",
  "executionRoleArn": "<EXEC_ROLE_ARN>",
  "taskRoleArn": "<TASK_ROLE_ARN>",
  "containerDefinitions": [{
    "name": "argus-agent",
    "image": "ghcr.io/argusdspm/argus-agent:stable",
    "essential": true,
    "environment": [
      {"name": "ARGUS_BACKEND_URL", "value": "https://api.argusdspm.com"},
      {"name": "CLOUD_PROVIDER", "value": "aws"},
      {"name": "ENROLLMENT_POOL", "value": "baseline"}
    ],
    "secrets": [
      {"name": "ENROLLMENT_TOKEN", "valueFrom": "<TOKEN_SECRET_ARN>"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/argus-agent",
        "awslogs-region": "<REGION>",
        "awslogs-stream-prefix": "agent",
        "awslogs-create-group": "true"
      }
    }
  }]
}
```

**4. Register + run:**

```bash
aws ecs register-task-definition --cli-input-json file://task.json
aws ecs run-task \
  --cluster <YOUR_CLUSTER> \
  --task-definition argus-agent \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<SUBNET>],securityGroups=[<SG>],assignPublicIp=ENABLED}"
```

> **Note:** the `awslogs-group` value, the secret ARN in `secrets[]`, and the
> log-group ARN pattern in the execution role's IAM policy must all agree on
> the same names. The task definition uses `awslogs-create-group: true` so the
> log group does not need to exist before first run, but the execution role
> must allow `logs:CreateLogGroup` on the matching ARN pattern.

## IAM policy

The DIY paths above need two separate IAM policies on two separate roles. Mixing
them onto one role works but breaks least-privilege.

**Attach to the EXECUTION role** (alongside AWS-managed
`AmazonECSTaskExecutionRolePolicy`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadEnrollmentTokenSecret",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "<TOKEN_SECRET_ARN>"
    },
    {
      "Sid": "CloudWatchLogsForAgentTaskDef",
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "<LOG_GROUP_ARN_PATTERN>"
    }
  ]
}
```

`<LOG_GROUP_ARN_PATTERN>` should match the `awslogs-group` you set on the task
definition. Use a literal ARN (`arn:aws:logs:us-east-2:123456789012:log-group:/ecs/argus-agent:*`)
or a wildcard if you anticipate multiple log groups under the same prefix.

**Attach to the TASK role** (the agent process identity):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ArgusDiscoveryRead",
      "Effect": "Allow",
      "Action": [
        "s3:ListAllMyBuckets", "s3:GetBucketLocation", "s3:GetBucketTagging",
        "s3:GetBucketPolicy", "s3:GetBucketAcl", "s3:GetBucketEncryption",
        "s3:GetBucketPublicAccessBlock", "s3:GetBucketVersioning",
        "s3:ListBucket", "s3:GetObject",
        "rds:DescribeDBInstances", "rds:DescribeDBClusters", "rds:ListTagsForResource",
        "dynamodb:ListTables", "dynamodb:DescribeTable", "dynamodb:ListTagsOfResource",
        "ec2:DescribeVolumes", "ec2:DescribeRegions",
        "sts:GetCallerIdentity", "ssm:GetParameter"
      ],
      "Resource": "*"
    }
  ]
}
```

For least-privilege at scale, narrow the `Resource` on per-service Sids
(e.g. restrict S3 actions to specific bucket ARNs). The wildcard above is
the recommended starting point for first-deploy validation.

## CloudFormation - one-click EC2

Open this URL in a browser logged into the target AWS account:

```
https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/quickcreate?templateURL=https%3A%2F%2Fargusdspm.com%2Fdownloads%2Fcfn%2Fargus-managed-v1.yml&stackName=argus-agent&param_Region=us-east-1
```

The console form will pre-fill stack name and region. **Paste your enrollment token into the `EnrollmentToken` field manually** - it is deliberately not included in the URL to keep the secret out of browser history. Click **Create stack**.

You can also download `cloudformation/argus-agent-ec2.yml` from this repo and upload it directly via the CloudFormation console.

## What gets deployed

- **EC2 / Fargate**: agent container running with a least-privilege task role (S3 read, RDS describe, etc. - only the datastore types you opt in to). The enrollment token sits encrypted in SSM Parameter Store; the agent reads it once at boot and exchanges it for a per-container API key via `/api/v1/agents/bootstrap`.
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

MIT - see `LICENSE`.
