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

## [v0.9.0] - 2026-07-30

### Added - permission completeness

The agent's required-permission set is now defined once in the product repo
(`argus_agent/core/verification_permissions.py`) and enforced across every
deployment artifact by a contract test. Auditing this repo against it found real
gaps in all three IaC paths. A control that reads "Not Verified" because we never
requested the permission is our bug, not a customer misconfiguration.

- **Terraform EC2 + Fargate modules**: added `s3:GetBucketLogging`,
  `dynamodb:GetResourcePolicy`, `iam:ListGroupsForUser`,
  `iam:Get/GenerateServiceLastAccessedDetails` and `sts:GetCallerIdentity`.
  Fargate additionally gained `ec2:DescribeRegions` and a new
  `ArgusAccountContext` statement. Both modules now satisfy the full registry
  (51 read + 12 remediation actions).
- **CI permission guard** (`ci/check_permissions.py`, `.github/workflows/permissions-check.yml`).
  The product repo now publishes its permission registry as a machine-readable
  export; this repo vendors a copy (`ci/verification-permissions.json`) and CI
  fails if a module drops a required action, grants a non-existent one, or the
  vendored copy has fallen behind the published registry. The modules stay a
  deliberate superset (Redshift Data API, IAM DB auth, credential retrieval,
  policy simulation); the check enforces the floor, never rewrites the modules.

### Removed - this repo is the Terraform home, not a second policy home

Every deletion here removes a hand-maintained copy of something defined elsewhere.
Copies drift: the ones below already had.

- **`cloudformation/argus-agent-ec2.yml` deleted.** It was a second copy of the
  EC2 template the product serves, and had diverged - it read the enrollment token
  from SSM Parameter Store where the served template uses Secrets Manager, and it
  never received the opt-in SSH parameters. CloudFormation is served by the
  control plane (`/downloads/argus-managed-ec2-v1.yml`); the README now points
  there. This repo remains the home of the Terraform modules.
- **`README.md` inline IAM policy removed**, replaced with a link to the published
  docs. That block granted `s3:GetBucketEncryption` - not a real IAM action, so it
  silently granted nothing - and was missing every `iam:`, `redshift:` and `kms:`
  action, meaning anyone who copied it got an agent that could not discover
  identities at all. The stale Quick-Launch URL alongside it was repointed.
- **`docs/iam-permissions.md` action tables removed** (76 rows). The file is now
  purely the *rationale* for each permission family - why it exists, what breaks
  without it - which is the part that is genuinely useful and not derivable. The
  action lists live in the registry and the generated docs.

### Fixed

- **EC2 module: region-specific prefix list.** The port-22 Instance Connect
  ingress hardcoded `pl-03915406641cb1f53`. Managed prefix list IDs are
  **region-specific**, so that literal only resolves in one region and fails (or
  resolves to something unrelated) anywhere else. Now a
  `data "aws_ec2_managed_prefix_list"` lookup by name against the current region.
- **`s3:DeletePublicAccessBlock` is not a real IAM action.**
  `delete_public_access_block` authorizes against `s3:PutBucketPublicAccessBlock`,
  and `delete_bucket_encryption` against `s3:PutEncryptionConfiguration`. This repo
  never granted the `Delete*` spellings (correctly); the product-side contract test
  now rejects them, since granting one looks like coverage while granting nothing.
- **`docs/iam-permissions.md` KMS section corrected.** It previously stated the
  agent "does not call any KMS action directly", that SSE-KMS reads are
  transparent, and that no IaC change was needed. That is wrong and is why
  `kms:Decrypt` is granted nowhere: reading an SSE-KMS object requires the caller
  to hold `kms:Decrypt` on the key. Tracked for fix product-side.

### Changed - network defaults (BREAKING for existing Terraform users)

The EC2 module opened two inbound ports unconditionally while the managed
CloudFormation template opens none. A customer choosing DIY Terraform - typically
for tighter control - was getting the weaker default. Both are now opt-in, so the
two paths agree:

- **Port 8080** (agent health endpoint, VPC CIDR) is now behind a new
  `enable_health_endpoint` variable, default `false`. The agent polls outbound and
  needs no inbound reachability to run.
- **Port 22 via EC2 Instance Connect** is now behind the existing
  `enable_ssh_access` variable, default `false`, matching the CIDR-based SSH rule
  that was already gated. Session Manager remains the recommended path and needs
  no open port.

**Upgrade impact:** `terraform plan` will show both ingress rules being removed. If
you scrape the health endpoint from inside the VPC, or rely on Instance Connect,
set the corresponding variable to `true`.

### Changed - naming convention (BREAKING for existing Terraform users)

Everything Argus creates in a tenant account now carries the `argus` prefix; IAM
roles/policies use PascalCase `Argus*`, all other resources lowercase `argus-*`.
The Fargate module's IAM resources were lowercase (`argus-agent-<customer>-task-s3`)
while the EC2 module already used PascalCase - they now match.

- Fargate module IAM roles/policies renamed to `ArgusAgent<Thing>-${var.customer_name}`
  (e.g. `ArgusAgentTaskRole-`, `ArgusAgentS3Policy-`). The security group is
  deliberately unchanged (non-IAM resources stay lowercase).
- CloudFormation inline policy names renamed from `argus-agent-*` to PascalCase.
- **Upgrade impact:** renaming an IAM role or policy forces replace-and-recreate.
  Run `terraform plan` and expect the agent's roles to be recreated; the agent
  re-enrolls automatically, but the plan is not a no-op. Existing *deployed* stacks
  that you do not re-apply are unaffected.

### Fixed

- `s3:DeletePublicAccessBlock` is **not a real IAM action** and was never granted
  here (correctly). Documented explicitly: `delete_public_access_block` authorizes
  against `s3:PutBucketPublicAccessBlock`, and `delete_bucket_encryption` against
  `s3:PutEncryptionConfiguration`. The product-side contract test now rejects both
  `Delete*` spellings, which look like coverage while granting nothing.
- `docs/iam-permissions.md` relabelled: it is a historical gap analysis, not the
  source of truth. Its "MISSING everywhere" tags described v0.7.6 and are now closed.

## [v0.8.5] - 2026-07-24

Co-released with agent `0.8.5`. Makes Fargate burst autoscaling actually work and completes region/AZ handling on the EC2 module. Builds on the deploy-safety fixes in v0.7.7. Both module fixes below were surfaced by the first live end-to-end deploy to a non-default region and subnet (us-east-2).

### Added
- **Fargate burst autoscaling, opt-in via `enable_burst_autoscaling`** (default `false`, matching the managed CloudFormation template). Gates the burst service + task definition (scale-to-zero), an Application Auto Scaling target, step-scaling policies, and two CloudWatch backlog alarms. A baseline-only deploy provisions and pays for none of it.

### Changed
- **Canonical autoscaler metric contract**: namespace `ArgusDSPM/Agent`, metric `PendingJobs`, single `ClusterName` dimension (the module sets `CLOUDWATCH_METRICS_CLUSTER` to the ECS cluster name), value = total unclaimed backlog. The always-on baseline keeps the stream fed so scaling survives burst scale-to-zero. This replaces a target-tracking policy that watched a metric the agent never published: cloud autoscaling had never actually functioned.
- **Fargate now uses step scaling** (CloudWatch alarms drive scale-out/scale-in) instead of target tracking.
- **Breaking (pre-v1.0): `burst_target_pending_jobs_per_agent` removed**, replaced by `burst_scale_out_backlog` (default 20) and `burst_scale_in_backlog` (default 5), the editable step-scaling triggers. `burst_min_capacity`/`burst_max_capacity` unchanged.

### Fixed
- **EC2 module region hardcoded to `us-east-1`.** `var.aws_region` defaulted to a literal `us-east-1` and set the agent's `AWS_REGION`, so the agent targeted the wrong region on any non-us-east-1 deploy. It now resolves from the configured provider (matching the Fargate module); an explicit `aws_region` still overrides.
- **EC2 instance availability-zone conflict.** The instance pinned the first AZ in the region even when a `subnet_id` in a different AZ was supplied, so `RunInstances` rejected the mismatch. The supplied subnet's AZ now wins; the AZ is only pinned for the module-created subnet.

> Note: the managed one-click template (`argus-managed-fargate-v1.yml`) lives in the Argus backend repo, not here; the matching autoscaling option was added there in the same change.

## [v0.7.7] - 2026-06-15

### Fixed
- **Non-ASCII em dashes** scattered through `.tf`/`.md`/`.yml`/`.sh` files. AWS `CreateSecurityGroup` rejects non-ASCII in security group descriptions, which failed `terraform apply` outright. Replaced with ASCII throughout.

### Added
- **Public-subnet plumbing.** `assign_public_ip` on the Fargate ENI and the matching EC2 user-data path, so public-subnet deploys without a NAT gateway can reach the internet.
- **Fargate region-from-provider.** `aws_region` reads from the configured provider via `data.aws_region.current` instead of a hardcoded default.

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
