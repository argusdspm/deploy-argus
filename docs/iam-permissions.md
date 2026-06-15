# Argus Agent - IAM Permissions Reference

**Status:** Canonical inventory of every AWS action the Argus DSPM agent
performs in production. The CloudFormation template + Terraform modules in
this repository must stay in sync with this list. When you add a new agent
capability, update both this doc and the IaC.

**Last reviewed:** 2026-05-13 (v0.7.6 prep)

---

## How to read this doc

Each table lists:
- **Action** - the AWS API action name (the `Service:OperationName` form
  used in an IAM policy `Action` field).
- **Used by** - the agent code path that needs it.
- **Where it lives in IaC** - `cf` (CloudFormation), `tf-ec2`
  (`modules/argus-agent-ec2/security.tf`), `tf-fargate`
  (`modules/argus-agent-fargate/security.tf`), or `MISSING` if the action is
  required by product code but absent from one or more IaC artifacts.

The "MISSING" tag is the actionable signal - every row marked MISSING needs
a corresponding patch in the IaC before the next release.

---

## STS (assumed-role chaining)

| Action | Used by | IaC |
|---|---|---|
| `sts:AssumeRole` | Agent → customer cross-account role (when `AWS_ROLE_ARN` env var is set) | cf, tf-ec2, tf-fargate ✓ |
| `sts:GetCallerIdentity` | Account-ID resolution at boot, cross-account guard, remediation preflight | cf, tf-ec2, tf-fargate ✓ (implicit via assume) |

`sts:AssumeRole` is configured on the trust policy of the customer role
(not in the agent's permissions). The agent's own role gets these for
free.

---

## S3 - discovery + scan (read-only)

| Action | Used by | IaC |
|---|---|---|
| `s3:ListAllMyBuckets` | `list_buckets` at discovery start | cf, tf-ec2, tf-fargate ✓ |
| `s3:GetBucketLocation` | resolve a bucket's region before any per-bucket call | cf, tf-ec2, tf-fargate ✓ |
| `s3:GetBucketTagging` | bucket-level tags, used for owner detection | cf, tf-ec2, tf-fargate ✓ |
| `s3:GetBucketVersioning` | versioning status surfaced in datastore metadata | cf, tf-ec2, tf-fargate ✓ |
| `s3:ListBucket` | object enumeration (`list_objects_v2`) - drives sampling | cf, tf-ec2, tf-fargate ✓ |
| `s3:GetObject` | content sampling for sensitive-data detection | cf, tf-ec2, tf-fargate ✓ |
| `s3:GetObjectVersion` | versioned-object sampling | cf, tf-ec2, tf-fargate ✓ |
| `s3:GetObjectTagging` | object-level tags propagated to findings | cf, tf-ec2, tf-fargate ✓ |
| `s3:GetBucketAcl` | public-bucket detection (legacy ACL grants) | **MISSING in cf, tf-ec2, tf-fargate** |
| `s3:GetBucketPolicy` | bucket-policy inspection for remediation preflight + agent self-check | **MISSING in cf, tf-ec2, tf-fargate** |
| `s3:GetBucketPolicyStatus` | **canonical** public-bucket signal (collapses policy + PAB into one bool); added in fix B-S12-1 | **MISSING in cf, tf-ec2, tf-fargate** |
| `s3:GetBucketPublicAccessBlock` | PAB inspection for public-bucket detection | **MISSING in cf, tf-ec2, tf-fargate** |
| `s3:GetEncryptionConfiguration` (alias of `s3:GetBucketEncryption`) | encryption-at-rest status surfaced in datastore metadata | **MISSING in cf, tf-ec2, tf-fargate** |

> **Why this matters:** without `GetBucketAcl`/`GetBucketPolicy`/`GetBucketPolicyStatus`/`GetBucketPublicAccessBlock`,
> every public-bucket detection call returns `AccessDenied` and the agent
> reports `is_public=false` for every bucket - silently failing the
> headline "publicly-exposed sensitive data" finding. The QA pass that
> drove this audit caught the gap via a fixture bucket made public via
> bucket-policy (not ACL); the agent reported it private. After fix
> B-S12-1 the agent now uses `GetBucketPolicyStatus`, which AWS denies
> without the action explicitly granted.

---

## S3 - remediation (write)

| Action | Used by | IaC |
|---|---|---|
| `s3:PutBucketPublicAccessBlock` | `block_public_access` remediation + rollback (boto3 `delete_public_access_block` authorizes against this Put action) | **MISSING everywhere** |
| `s3:PutEncryptionConfiguration` | `enable_encryption` remediation + rollback (boto3 `delete_bucket_encryption` authorizes against this Put action) | **MISSING everywhere** |
| `s3:PutBucketVersioning` | `enable_versioning` remediation step (also covers rollback - versioning state mutates in place) | **MISSING everywhere** |
| `s3:PutBucketPolicy` | `restrict_bucket_policy` remediation step (write the stricter policy) | **MISSING everywhere** |
| `s3:DeleteBucketPolicy` | `restrict_bucket_policy` (when stricter policy is empty) | **MISSING everywhere** |

The canonical reference for what each remediation action needs is
`argus_agent/remediation/providers/aws_provider.py:39 - ACTION_IAM_PERMISSIONS`.

---

## IAM - discovery (read)

| Action | Used by | IaC |
|---|---|---|
| `iam:ListUsers` | discover IAM users | **MISSING everywhere** |
| `iam:GetUser` | per-user details + tags | **MISSING everywhere** |
| `iam:ListMFADevices` | `has_mfa` derivation | **MISSING everywhere** |
| `iam:ListAccessKeys` | access-key inventory per user | **MISSING everywhere** |
| `iam:GetAccessKeyLastUsed` | `last_activity_at` derivation, `unused_access_key` recommendation | **MISSING everywhere** |
| `iam:ListUserTags` | owner-email + custom-tag surfaces | **MISSING everywhere** |
| `iam:ListUserPolicies` | inline-policy names per user | **MISSING everywhere** |
| `iam:GetUserPolicy` | inline-policy DOCUMENTS - needed by B-S11-1 wildcard detector | **MISSING everywhere** |
| `iam:ListAttachedUserPolicies` | attached policy ARNs per user | **MISSING everywhere** |
| `iam:ListRoles` | discover IAM roles | **MISSING everywhere** |
| `iam:GetRole` | per-role details + trust policy | **MISSING everywhere** |
| `iam:ListRolePolicies` | inline-policy names per role | **MISSING everywhere** |
| `iam:GetRolePolicy` | inline-policy DOCUMENTS (B-S11-1 detector) | **MISSING everywhere** |
| `iam:ListAttachedRolePolicies` | attached policy ARNs per role | **MISSING everywhere** |
| `iam:ListGroups` | discover IAM groups | **MISSING everywhere** |
| `iam:ListGroupPolicies` | inline-policy names per group | **MISSING everywhere** |
| `iam:GetGroupPolicy` | inline-policy DOCUMENTS | **MISSING everywhere** |
| `iam:ListAttachedGroupPolicies` | attached policy ARNs per group | **MISSING everywhere** |
| `iam:GetPolicy` | customer-managed policy metadata (default version ID) | **MISSING everywhere** |
| `iam:GetPolicyVersion` | customer-managed policy DOCUMENT - required by B-S11-1 over-privilege detector | **MISSING everywhere** |
| `iam:GenerateCredentialReport` | trigger fresh credential report | **MISSING everywhere** |
| `iam:GetCredentialReport` | password_age, password_last_used, mfa_active per user | **MISSING everywhere** |

> **Why this matters:** the current IaC ships **zero** `iam:*` actions, so
> §11 Identity & Access discovery is completely broken on a fresh customer
> onboarding. AWS has a managed policy `IAMReadOnlyAccess` that covers
> every action in this section; attaching it is the simplest fix. (Custom
> policies in the next section need more targeted grants.)

---

## IAM - remediation + preflight (write + simulate)

| Action | Used by | IaC |
|---|---|---|
| `iam:SimulatePrincipalPolicy` | preflight credential check before any remediation step | **MISSING everywhere** |
| `iam:UpdateAccessKey` | `disable_access_key` remediation step (Status=Inactive/Active) | **MISSING everywhere** |
| `iam:DetachUserPolicy` / `iam:DetachRolePolicy` | `remove_iam_policy` remediation step | **MISSING everywhere** |
| `iam:AttachUserPolicy` / `iam:AttachRolePolicy` | rollback for `remove_iam_policy` | **MISSING everywhere** |
| `iam:PutUserPolicy` | `enforce_mfa` remediation step (writes `ArgusEnforceMFA` inline policy) | **MISSING everywhere** |
| `iam:DeleteUserPolicy` | rollback for `enforce_mfa` | **MISSING everywhere** |

---

## RDS

| Action | Used by | IaC |
|---|---|---|
| `rds:DescribeDBInstances` | discovery enumeration | cf, tf-ec2, tf-fargate ✓ |
| `rds:DescribeDBClusters` | Aurora-cluster enumeration | cf, tf-ec2, tf-fargate ✓ |
| `rds:ListTagsForResource` | RDS tag inspection | cf, tf-ec2, tf-fargate ✓ |
| `rds-db:connect` | IAM-DB-auth on RDS scan path | cf, tf-ec2, tf-fargate ✓ |

`rds:GenerateDBAuthToken` is a client-side token-generation call (not an
AWS API action) - no IAM permission required beyond `rds-db:connect`.

---

## DynamoDB

| Action | Used by | IaC |
|---|---|---|
| `dynamodb:ListTables` | discovery enumeration | cf, tf-ec2, tf-fargate ✓ |
| `dynamodb:DescribeTable` | per-table metadata | cf, tf-ec2, tf-fargate ✓ |
| `dynamodb:ListTagsOfResource` | table tag inspection | cf, tf-ec2, tf-fargate ✓ |
| `dynamodb:Scan` | content sampling for sensitive-data detection | cf, tf-ec2, tf-fargate ✓ |
| `dynamodb:Query` | targeted item sampling | cf, tf-ec2, tf-fargate ✓ |
| `dynamodb:GetItem` | single-item lookups | cf, tf-ec2, tf-fargate ✓ |
| `dynamodb:BatchGetItem` | batched sampling | cf, tf-ec2, tf-fargate ✓ |

DynamoDB coverage is complete.

---

## Redshift

| Action | Used by | IaC |
|---|---|---|
| `redshift:DescribeClusters` | provisioned Redshift discovery | cf, tf-ec2, tf-fargate ✓ |
| `redshift:DescribeTags` | cluster tag inspection | cf, tf-ec2, tf-fargate ✓ |
| `redshift:GetClusterCredentials` | temporary credentials for connection | cf, tf-ec2, tf-fargate ✓ |
| `redshift:GetClusterCredentialsWithIAM` | IAM-DB-auth flavor | cf, tf-ec2, tf-fargate ✓ |
| `redshift-serverless:ListWorkgroups` | Redshift Serverless discovery | **MISSING in cf, tf-ec2, tf-fargate** |
| `redshift-serverless:GetWorkgroup` | Serverless workgroup detail | **MISSING in cf, tf-ec2, tf-fargate** |
| `redshift-serverless:ListTagsForResource` | Serverless tag inspection | **MISSING in cf, tf-ec2, tf-fargate** |
| `redshift-serverless:GetCredentials` | Serverless temporary credentials | **MISSING in cf, tf-ec2, tf-fargate** |

> **Why this matters:** the QA seed always has a Redshift Serverless
> workgroup (see `argus-test` account in us-east-2). Provisioned-cluster
> coverage is fine; Serverless calls return AccessDenied today.

---

## Secrets Manager

| Action | Used by | IaC |
|---|---|---|
| `secretsmanager:GetSecretValue` | retrieve customer-stored DB credentials | cf, tf-ec2, tf-fargate ✓ |
| `secretsmanager:DescribeSecret` | secret metadata (rotation, KMS key) | cf, tf-ec2, tf-fargate ✓ |

Secrets Manager coverage is complete.

---

## KMS

The agent does **not** call any KMS action directly. SSE-KMS object reads
are transparent - `s3:GetObject` triggers the KMS decrypt under the hood,
and the customer's KMS-key resource policy must grant the agent's role
`kms:Decrypt` separately. **This is a customer responsibility**, documented
in the README: "If your buckets use SSE-KMS, attach the agent role as a
key user on the relevant KMS keys."

No IaC change needed here, but the README should reinforce this for ops
teams seeing AccessDenied on KMS-protected buckets.

---

## CloudWatch

| Action | Used by | IaC |
|---|---|---|
| `cloudwatch:PutMetricData` (namespace `ArgusDSPM/Agent`) | agent health/throughput metrics | cf, tf-ec2, tf-fargate ✓ |
| `cloudwatch:GetMetricStatistics` | bucket size + object count estimation (avoids slow `list_objects_v2` for inventory) | **MISSING in cf, tf-ec2, tf-fargate** |

> **Why this matters:** without `GetMetricStatistics`, every S3 bucket
> discovery falls back to a full paginated list to compute size, which is
> ~30x slower on multi-thousand-object buckets.

---

## EC2

| Action | Used by | IaC |
|---|---|---|
| `ec2:DescribeInstances` | host-level metadata (used by EC2 deployment shape only) | cf, tf-ec2, tf-fargate ✓ |
| `ec2:DescribeInstanceAttribute` | host security-group lookup | cf, tf-ec2, tf-fargate ✓ |
| `ec2:DescribeRegions` | region enumeration for discovery (avoids hardcoding region list in agent) | cf, tf-ec2, tf-fargate ✓ |
| `ec2:DescribeAvailabilityZones` | AZ detail for diagnostics | cf, tf-ec2, tf-fargate ✓ |

EC2 coverage is complete.

---

## SSM

| Action | Used by | IaC |
|---|---|---|
| `ssm:GetParameter` / `ssm:GetParameters` | retrieve enrollment token + backend URL from Parameter Store (when configured) | cf, tf-ec2, tf-fargate ✓ |

SSM coverage is complete.

---

## ECS task-execution (Fargate only)

The Fargate module attaches the AWS-managed
`AmazonECSTaskExecutionRolePolicy` to the task-execution role (separate
from the agent's task role). This covers ECR pull + CloudWatch Logs writes
that the Fargate platform itself needs. No change required.

---

## Summary of gaps (what v0.7.6 must add)

### S3
- `s3:GetBucketAcl`
- `s3:GetBucketPolicy`
- `s3:GetBucketPolicyStatus`
- `s3:GetBucketPublicAccessBlock`
- `s3:GetEncryptionConfiguration`
- `s3:PutBucketPublicAccessBlock` (covers remediation and rollback via boto3 `delete_public_access_block`)
- `s3:PutEncryptionConfiguration` (covers remediation and rollback via boto3 `delete_bucket_encryption`)
- `s3:PutBucketVersioning`
- `s3:PutBucketPolicy` + `s3:DeleteBucketPolicy`

### IAM
All 22 read actions (or attach `IAMReadOnlyAccess` managed policy).
All 6 remediation/preflight write actions.

### Redshift Serverless
- `redshift-serverless:ListWorkgroups`
- `redshift-serverless:GetWorkgroup`
- `redshift-serverless:ListTagsForResource`
- `redshift-serverless:GetCredentials`

### CloudWatch
- `cloudwatch:GetMetricStatistics`

### Total new actions to add: ~38

---

## Verification checklist (run before tagging v0.7.6)

1. Deploy the updated CFN template to a clean AWS account via
   QuickLaunch.
2. Roll the agent out via the EC2 module + the Fargate module on a
   second/third account.
3. Run the QA fixture seed (`scripts/test/qa_seed.py seed --tier minimal`)
   in each account.
4. Trigger datastore discovery → confirm:
   - All 5 seeded S3 buckets show `is_public=true` for the public one.
   - DynamoDB tables enumerate.
   - Redshift Serverless workgroup enumerates.
5. Trigger IAM discovery → confirm all 6 seeded fixtures land with
   correct `is_over_privileged`, `is_external`, `has_mfa` flags.
6. Trigger one remediation workflow against the public bucket → confirm
   no `AccessDenied` in `execution_logs`, dry_run path completes.
7. `aws iam simulate-principal-policy` from outside, asserting each new
   action is allowed - catches policy regressions in future bumps.

---

## Change history

- 2026-05-13 - v0.7.6 prep: initial canonical inventory + gap analysis
  driven by the QA pass that landed fixes B-S5.3-1 / B-S11-1 / B-S12-1
  in the Argus repo. Cross-reference:
  `argus/.claude/code-reviews/2026-05-09-qa-sec5-7-findings.md`.
