# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/).

## Versioning policy

`deploy-argus` tracks the Argus agent it deploys. Tags are full semver (`vX.Y.Z`), matching `argus_agent/__version__.py` in the main repo. The current `v0.7.6` tag aligns with agent `0.7.5+` (v0.7.6 is a deploy-argus-only bump - agent code unchanged from v0.7.5; this release plugs the IAM permission gaps the agent always needed).

- **Pre-v1.0 (current):** versions move with the agent. The agent and `deploy-argus` co-tag on every customer-visible IaC change. No long-term backwards-compat guarantees while either side is pre-v1.
- **v1.0.0:** ships when the Argus backend + agent + `deploy-argus` co-release v1.0 stable. The module interface (variables, outputs) locks at that point.
- **Post-v1.0:**
  - **Major (`X.0.0`):** breaking module interface changes - variable rename or removal, module deletion, customer must edit Terraform.
  - **Minor (`x.Y.0`):** new modules, new optional variables, new providers, new optional outputs (backwards-compatible additions).
  - **Patch (`x.y.Z`):** doc fixes, default-value tweaks, internal refactors that don't change the module interface.

When in doubt, bump minor.

## [v0.7.6] - 2026-05-13

### Added
- `docs/iam-permissions.md` - canonical inventory of every AWS API action the Argus agent calls in production, with a gap analysis driving the IaC changes below.
- **CloudFormation (`cloudformation/argus-agent-ec2.yml`)**:
  - `argus-agent-s3-scan`: `s3:GetBucketAcl`, `s3:GetBucketPolicy`, `s3:GetBucketPolicyStatus`, `s3:GetBucketPublicAccessBlock`, `s3:GetEncryptionConfiguration` - required for public-bucket detection (without these the agent silently reports `is_public=false` on every bucket).
  - `argus-agent-iam-discovery`: 23 IAM read actions covering users/roles/groups, attached + inline policy documents, MFA devices, access keys, credential reports, `iam:SimulatePrincipalPolicy`. Required for §11 Identity & Access in the UI and for the wildcard-inline over-privilege detector.
  - `argus-agent-redshift-serverless`: discovery + IAM-DB-Auth for Redshift Serverless workgroups.
  - `argus-agent-cloudwatch-read`: `cloudwatch:GetMetricStatistics` for fast S3 size/count estimation.
  - `argus-agent-s3-remediation` + `argus-agent-iam-remediation`: write actions for the remediation workflows (block public access, encryption, versioning, policy restriction, disable stale access keys, remove over-privileged policies, enforce MFA). Both can be commented out for read-only tenants.
- **Terraform EC2 module (`modules/argus-agent-ec2/`)**:
  - New variables `enable_iam_discovery` (default `false`) and `enable_remediation` (default `false`).
  - Same S3 / IAM / Redshift Serverless / CloudWatch / remediation policies added as separate `aws_iam_policy` resources, each gated by its respective `local.*_enabled` flag.
- **Terraform Fargate module (`modules/argus-agent-fargate/`)**:
  - Same variables and same policy set as EC2 module, scoped to the `task` role.

### Why
A QA pass against the Argus repo's `qa/2026-05-07-wave-fixes` branch surfaced that the previous IaC shipped **zero** `iam:*` actions and was missing the S3 actions needed for public-bucket detection. Customers following the canonical setup ended up with a role that couldn't detect publicly-exposed buckets and couldn't populate the Identity & Access UI. The gap analysis lives in `docs/iam-permissions.md`; each new IaC line ties back to a row in that table.

### Backwards compatibility
- All new permissions are additive - existing customer deployments continue to work, they just become functional in more sections of the Argus UI after the upgrade.
- `enable_iam_discovery` and `enable_remediation` default to `false` to preserve the current behavior on `terraform plan` against an existing deployment. Customers opt in.

### Upgrade steps
1. `terraform get -update && terraform apply` (EC2 / Fargate).
2. Optionally flip `enable_iam_discovery = true` to populate §11 Identity & Access.
3. Optionally flip `enable_remediation = true` and toggle Tenant Settings → Remediation in the Argus UI to unblock §13 Remediation workflows.
4. CFN customers: re-deploy the stack with the updated template; no parameter changes required.

## [v0.7.5] - 2026-05-05

Initial public release. Repo rebuilt from scratch from the Argus internal `terraform/` directory; preserves the prior repo state on the `legacy-archive` branch for reference.

### Added
- `modules/argus-agent-ec2` - EC2 module (single-instance, Docker under systemd, public-image pull from `ghcr.io/argusdspm/argus-agent:stable`).
- `modules/argus-agent-fargate` - Fargate module with baseline + autoscaled burst services.
- `modules/argus-agent-azure-aci` - Azure Container Instances module. **Preview**, no UI integration in this release.
- `cloudformation/argus-agent-ec2.yml` - CloudFormation template for one-click EC2 deploy via CFN Quick-Launch.
- `examples/ec2-basic`, `examples/fargate`, `examples/azure-aci` - minimal usage examples for each module.
- `.github/workflows/` - `terraform-validate` (fmt + validate per module) and `cfn-lint` (CloudFormation linting).
- `COMPATIBILITY.md` - deploy-argus ↔ argus version matrix.

### Changed (vs prior repo state on `legacy-archive`)
- Public-registry image (`ghcr.io/argusdspm/argus-agent`) replaces the prior ECR-pull pattern. No customer-side ECR authentication required.
- Environment variable `ARGUS_BACKEND_URL` replaces the legacy `SAAS_API_URL`.
- Repo layout now follows HashiCorp / community conventions: `modules/`, `cloudformation/`, `examples/` at the top level.

### Removed
- `cloudformation/customer-deployment-role.yml` - provider-side cross-account assume-role pattern. Conflicts with the data-sovereignty model (agent runs entirely in customer's account; no inbound provider access).
- `scripts/customer-onboarding.sh` - superseded by the CFN Quick-Launch flow and the in-product Deploy Agent drawer.
- Three legacy validate scripts (`validate-deployment.sh`, `validate-deployment-fixed.sh`, `quick-validate.sh`).
