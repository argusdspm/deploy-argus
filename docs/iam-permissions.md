# Argus Agent - IAM permission rationale

> **This is not the source of truth for the permission set.** The canonical set lives in the
> product repo at `argus_agent/core/verification_permissions.py` (`SIGNAL_PERMISSIONS` +
> `REMEDIATION_PERMISSIONS`), and a contract test (`backend/tests/test_iam_policy_contract.py`)
> fails the build if any deployment artifact is short a grant. Update the registry first; the
> IaC follows.
>
> For the actual policy JSON to copy, see
> **[IAM permissions](https://argusdspm.com/docs/deploy/iam/)**.

This document explains **why** each family of permissions exists and what breaks without it. It
deliberately no longer lists the actions themselves: it used to, the list drifted, and a
hand-maintained copy of a generated set is exactly the failure this repository is trying to stop
repeating.

---

## STS - assumed-role chaining

The Local and cross-account paths assume a role inside the target account. `sts:AssumeRole` is
granted on the *calling* principal, not here.

`sts:GetCallerIdentity` backs the cross-account guard: the agent asserts it is running inside the
account that was registered before it persists any scan result. Worth knowing that AWS requires
**no permission** for this call - it succeeds even against an explicit `Deny`, because the same
information is returned when access is denied. It is listed in our policies for completeness, but
its absence breaks nothing.

## S3 - discovery and scan

Public-exposure detection is the headline finding, and it needs four reads working together:
`GetBucketPolicyStatus` (the canonical `IsPublic` signal, which collapses policy and PAB into one
boolean), `GetBucketPublicAccessBlock`, `GetBucketAcl` for legacy ACL grants, and `GetBucketPolicy`
for remediation preflight.

Without them every call returns `AccessDenied`, the collector swallows it, and the agent reports
`is_public=false` for **every** bucket - silently failing the product's flagship finding. The QA
pass that drove the original audit caught this with a fixture bucket made public via bucket policy
rather than ACL: the agent reported it private.

`GetEncryptionConfiguration` is the IAM action behind the `GetBucketEncryption` API. `s3:GetBucketEncryption`
is **not a real action**; IAM accepts unknown-but-well-formed actions silently, so granting that
spelling grants nothing at all.

`GetBucketLogging` and `GetBucketVersioning` back the access-logging and recovery posture controls.
Without them those controls read "Not Verified" - a gap that is our fault, not the customer's.

## S3 - remediation (write)

Only needed when remediation execution is enabled; a read-only deployment can omit the whole
statement without affecting discovery or compliance.

Note there is **no `s3:DeletePublicAccessBlock` and no `s3:DeleteBucketEncryption` IAM action**.
`delete_public_access_block` authorizes against `s3:PutBucketPublicAccessBlock`, and
`delete_bucket_encryption` against `s3:PutEncryptionConfiguration`. Granting a `Delete*` spelling
looks like coverage while granting nothing. The contract test rejects both.

## IAM - identity discovery (read)

This family powers the entire Identity and Access surface: the identity inventory, the access
graph, blast radius, credential hygiene, and every IAM recommendation. Without it those pages are
empty on a fresh customer onboarding.

Three that are easy to miss because their absence degrades quietly rather than erroring:
- `ListGroupsForUser` - group-derived effective permissions are invisible to the access graph.
- `GetServiceLastAccessedDetails` / `GenerateServiceLastAccessedDetails` - over-provisioning
  detection compares permissions granted against permissions actually used; without these it has
  only half the comparison.

The AWS-managed `IAMReadOnlyAccess` policy covers the whole read set if you prefer attaching that
to targeted grants.

## IAM - remediation and preflight (write + simulate)

`SimulatePrincipalPolicy` backs the remediation preflight check, which verifies a fix will actually
apply before it is attempted. The attach/detach pair must be granted symmetrically: an earlier
version granted `Detach*` but not `Attach*`, so rollback would have failed.

## RDS

`DescribeDBInstances` / `DescribeDBClusters` carry `PubliclyAccessible`, `StorageEncrypted` and
backup retention in one payload; there is no per-signal API to split them further.

IAM database authentication uses `rds-db:connect`, which is an IAM-level action rather than an RDS
API action.

## DynamoDB

`DescribeTable` covers encryption posture (DynamoDB encrypts every table at rest unconditionally,
so this is a platform guarantee rather than a per-table toggle).

`GetResourcePolicy` is required for public-exposure detection. DynamoDB has no public endpoint, but
since 2024 it supports **resource-based policies**, and a policy with `Principal: "*"` shares a
table exactly the way an S3 bucket policy does. Without this read the agent cannot distinguish "not
shared" from "could not look", and would be asserting private on faith.

## Redshift

Provisioned clusters and Serverless workgroups are separate APIs with separate permissions
(`redshift:*` vs `redshift-serverless:*`). Granting only one leaves the other undiscoverable, which
is a silent gap rather than an error.

## KMS

**Corrected 2026-07-30.** An earlier version of this document stated that the agent "does not call
any KMS action directly", that SSE-KMS reads are transparent, and that no IaC change was needed.
**That is wrong, and it is why `kms:Decrypt` was granted nowhere.**

Reading an object encrypted with SSE-KMS requires the **caller** to hold `kms:Decrypt` on the key.
It is not transparent. For a customer-managed key (CMK) with the default key policy - which
includes an `Enable IAM User Permissions` statement delegating to the account root - granting
`kms:Decrypt` in the agent's IAM policy is sufficient and needs no customer action. A key whose
owner removed that delegation additionally needs the agent's role named in the **key policy**.

The consequence of the missing grant is worse than a permission error: the sampling path currently
skips objects it cannot read, so a CMK-encrypted bucket reports **zero findings** and its
content-derived compliance controls **pass**. That is a false negative on exactly the buckets
customers put their most sensitive data in.

Tracked in the product plan (`2026-07-30-docs-handoff-outstanding-issues.md`, issue 4) with the
full fix: grant the permission, make the read failure surface as an explicit verification error
instead of a silent skip, and document the key-policy step for locked-down keys.

## CloudWatch

`PutMetricData` (scoped to the `ArgusDSPM/Agent` namespace) is the agent's own telemetry.

`GetMetricStatistics` is a read used to size S3 buckets. Without it, bucket discovery falls back to
a full paginated object listing to compute size, which is roughly 30x slower on multi-thousand-object
buckets.

## EC2

Region enumeration (`DescribeRegions`) determines what the agent scans; on the EC2 deployment path
the instance-metadata reads additionally identify the host. `DescribeVolumes` supports EBS-attached
datastore context.

## SSM

Two unrelated uses: reading the enrollment token parameter on deployment paths that store it in
Parameter Store, and the AWS-managed `AmazonSSMManagedInstanceCore` policy that lets operators
reach an EC2 host over Session Manager without opening SSH.

## ECS task execution (Fargate only)

The Fargate module attaches the AWS-managed `AmazonECSTaskExecutionRolePolicy` to the **execution**
role, which is distinct from the agent's task role. It covers the image pull and the CloudWatch
Logs writes the Fargate platform itself performs. The agent process never assumes that role.
