# Example: EC2 single-instance deployment

Minimal Terraform configuration that deploys the Argus agent on a single EC2 instance using the `argus-agent-ec2` module.

## What this example deploys

- One EC2 instance (`t3.medium` by default) running the agent in Docker under systemd
- Least-privilege IAM role for S3 / Secrets Manager / CloudWatch
- Egress security group (no inbound ports)
- Secrets Manager entry for the agent's per-container API key (minted at bootstrap from the enrollment token)

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - set customer_name, vpc/subnet, etc.

terraform init
terraform apply -var enrollment_token="<your-enrollment-token>"
```

The enrollment token comes from the Argus dashboard: **Settings → Cloud Accounts → your account → Generate Enrollment Token**.

## Verifying the deployment

The Argus dashboard's Cloud Accounts page flips your account to **Connected** within ~60 seconds of agent startup. If it doesn't:

```bash
# CloudWatch log group
aws logs tail /aws/ec2/argus-agent/<your-customer-name> --follow

# Check the EC2 instance reached "running" state with the agent's user_data
aws ec2 describe-instances --filters "Name=tag:Name,Values=argus-agent-*"
```

Common issues: enrollment token expired/rotated, missing outbound to `api.argusdspm.com`, mismatched AWS account (agent's runtime account vs the cloud account it was enrolled for).

See `../../README.md#troubleshooting` for the full list.

## Variables

See `variables.tf`. Most you can leave at defaults. Required: `customer_name`, `vpc_id`, `subnet_id`, `enrollment_token`.

## Cost

Roughly **$30–40/month** for a `t3.medium` running 24/7 plus CloudWatch logs. Scale down to `t3.small` for low-volume accounts; scale up to `t3.large` if scanning datastores in the multi-TB range. For elastic scaling, use the `argus-agent-fargate` module instead.
