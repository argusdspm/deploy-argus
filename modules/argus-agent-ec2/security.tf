# Argus Agent EC2 Module - Security (security group + IAM)

# -----------------------------------------------------------------------------
# Security group - outbound HTTPS for control plane + AWS APIs
# -----------------------------------------------------------------------------

resource "aws_security_group" "argus_agent_sg" {
  name        = "argus-agent-sg-${var.customer_name}"
  description = "Argus agent - outbound HTTPS only (data sovereignty: no inbound from provider)."
  vpc_id      = local.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to Argus control plane and AWS APIs."
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for OS package updates."
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS."
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_id != "" ? data.aws_vpc.selected[0].cidr_block : aws_vpc.argus_vpc[0].cidr_block]
    description = "Agent health endpoint - internal VPC only."
  }

  # SSH via EC2 Instance Connect (managed AWS prefix list)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    prefix_list_ids = ["pl-03915406641cb1f53"]
    description     = "SSH via EC2 Instance Connect."
  }

  dynamic "ingress" {
    for_each = var.enable_ssh_access && length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
      description = "SSH for debugging - remove in production."
    }
  }

  tags = merge(local.common_tags, {
    Name = "argus-agent-sg-${var.customer_name}"
  })
}

data "aws_vpc" "selected" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

# -----------------------------------------------------------------------------
# Database egress (conditional)
# -----------------------------------------------------------------------------

resource "aws_security_group_rule" "mysql_egress" {
  count             = var.enable_database_egress && local.rds_enabled ? 1 : 0
  type              = "egress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = length(var.database_egress_cidr_blocks) > 0 ? var.database_egress_cidr_blocks : [local.vpc_cidr]
  security_group_id = aws_security_group.argus_agent_sg.id
  description       = "MySQL/MariaDB egress for RDS scanning."
}

resource "aws_security_group_rule" "postgres_egress" {
  count             = var.enable_database_egress && local.rds_enabled ? 1 : 0
  type              = "egress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = length(var.database_egress_cidr_blocks) > 0 ? var.database_egress_cidr_blocks : [local.vpc_cidr]
  security_group_id = aws_security_group.argus_agent_sg.id
  description       = "PostgreSQL egress for RDS scanning."
}

resource "aws_security_group_rule" "redshift_egress" {
  count             = var.enable_database_egress && local.redshift_enabled ? 1 : 0
  type              = "egress"
  from_port         = 5439
  to_port           = 5439
  protocol          = "tcp"
  cidr_blocks       = length(var.database_egress_cidr_blocks) > 0 ? var.database_egress_cidr_blocks : [local.vpc_cidr]
  security_group_id = aws_security_group.argus_agent_sg.id
  description       = "Redshift egress for data warehouse scanning."
}

# -----------------------------------------------------------------------------
# IAM role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "argus_agent_role" {
  name = "ArgusAgentRole-${var.customer_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-role-${var.customer_name}"
  })
}

resource "aws_iam_instance_profile" "argus_agent_profile" {
  name = "argus-agent-profile-${var.customer_name}"
  role = aws_iam_role.argus_agent_role.name

  tags = merge(local.common_tags, {
    Name = "argus-agent-profile-${var.customer_name}"
  })
}

# -----------------------------------------------------------------------------
# Bootstrap permissions - read enrollment token from SSM
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "argus_agent_ssm_policy" {
  name        = "ArgusAgentSSMPolicy-${var.customer_name}"
  description = "Read the enrollment-token SSM parameter at agent boot."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SSMReadEnrollmentToken"
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = aws_ssm_parameter.enrollment_token.arn
    }]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-ssm-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_ssm_attachment" {
  policy_arn = aws_iam_policy.argus_agent_ssm_policy.arn
  role       = aws_iam_role.argus_agent_role.name
}

# -----------------------------------------------------------------------------
# CloudWatch logs
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "argus_agent_logs_policy" {
  name        = "ArgusAgentLogsPolicy-${var.customer_name}"
  description = "CloudWatch Logs write access for the agent."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudWatchLogsWrite"
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = [
        aws_cloudwatch_log_group.argus_agent_logs.arn,
        "${aws_cloudwatch_log_group.argus_agent_logs.arn}:*"
      ]
    }]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-logs-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_logs_attachment" {
  policy_arn = aws_iam_policy.argus_agent_logs_policy.arn
  role       = aws_iam_role.argus_agent_role.name
}

# -----------------------------------------------------------------------------
# EC2 metadata
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "argus_agent_ec2_policy" {
  name        = "ArgusAgentEC2Policy-${var.customer_name}"
  description = "EC2 describe permissions for the agent's host introspection."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EC2MetadataAccess"
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeRegions",
        "ec2:DescribeAvailabilityZones"
      ]
      Resource = "*"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-ec2-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_ec2_attachment" {
  policy_arn = aws_iam_policy.argus_agent_ec2_policy.arn
  role       = aws_iam_role.argus_agent_role.name
}

# -----------------------------------------------------------------------------
# Secrets Manager - only for customer-side DB credentials (optional).
# Note: the agent's own per-container API key (post-bootstrap) is held
# inside the container; deploy-argus does not pre-stage it.
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "argus_agent_db_secrets_policy" {
  count       = var.db_secrets_arn_pattern != "" ? 1 : 0
  name        = "ArgusAgentDBSecretsPolicy-${var.customer_name}"
  description = "Secrets Manager read for customer-supplied DB credentials."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SecretsManagerDBCredentials"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = var.db_secrets_arn_pattern
    }]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-db-secrets-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_db_secrets_attachment" {
  count      = var.db_secrets_arn_pattern != "" ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_db_secrets_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}

# -----------------------------------------------------------------------------
# Datastore-specific policies (conditional)
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "argus_agent_s3_policy" {
  count       = local.s3_enabled ? 1 : 0
  name        = "ArgusAgentS3Policy-${var.customer_name}"
  description = "S3 read for Argus scanning."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketDiscovery"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation",
          "s3:GetBucketTagging"
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid      = "S3BucketAccess"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketVersioning"]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid    = "S3BucketSecurityMetadata"
        Effect = "Allow"
        # Required for public-bucket detection. Argus uses
        # s3:GetBucketPolicyStatus as the canonical IsPublic signal
        # (collapses policy + PAB into one boolean); without it the
        # agent reports is_public=false for every bucket. ACL +
        # PolicyDocument fallbacks cover legacy ACL grants and
        # remediation preflight respectively.
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:GetBucketPolicyStatus",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetEncryptionConfiguration"
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid    = "S3ObjectReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectTagging"
        ]
        Resource = "arn:aws:s3:::*/*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-s3-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_s3_attachment" {
  count      = local.s3_enabled ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_s3_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}

resource "aws_iam_policy" "argus_agent_rds_policy" {
  count       = local.rds_enabled ? 1 : 0
  name        = "ArgusAgentRDSPolicy-${var.customer_name}"
  description = "RDS describe + IAM DB Auth for Argus scanning."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSDiscovery"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid      = "RDSIAMDBAuth"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = "arn:aws:rds-db:*:${data.aws_caller_identity.current.account_id}:dbuser:*/*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-rds-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_rds_attachment" {
  count      = local.rds_enabled ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_rds_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}

resource "aws_iam_policy" "argus_agent_dynamodb_policy" {
  count       = local.dynamodb_enabled ? 1 : 0
  name        = "ArgusAgentDynamoDBPolicy-${var.customer_name}"
  description = "DynamoDB describe + read for Argus scanning."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBDiscovery"
        Effect = "Allow"
        Action = [
          "dynamodb:ListTables",
          "dynamodb:DescribeTable",
          "dynamodb:ListTagsOfResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBReadAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem"
        ]
        Resource = "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-dynamodb-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_dynamodb_attachment" {
  count      = local.dynamodb_enabled ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_dynamodb_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}

resource "aws_iam_policy" "argus_agent_redshift_policy" {
  count       = local.redshift_enabled ? 1 : 0
  name        = "ArgusAgentRedshiftPolicy-${var.customer_name}"
  description = "Redshift describe + Data API for Argus scanning."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RedshiftDiscovery"
        Effect   = "Allow"
        Action   = ["redshift:DescribeClusters", "redshift:DescribeTags"]
        Resource = "*"
      },
      {
        Sid    = "RedshiftDataAPI"
        Effect = "Allow"
        Action = [
          "redshift-data:ExecuteStatement",
          "redshift-data:GetStatementResult",
          "redshift-data:DescribeStatement",
          "redshift-data:ListTables",
          "redshift-data:ListSchemas",
          "redshift-data:DescribeTable"
        ]
        Resource = "*"
      },
      {
        Sid    = "RedshiftGetCredentials"
        Effect = "Allow"
        Action = [
          "redshift:GetClusterCredentials",
          "redshift:GetClusterCredentialsWithIAM"
        ]
        Resource = [
          "arn:aws:redshift:*:${data.aws_caller_identity.current.account_id}:cluster:*",
          "arn:aws:redshift:*:${data.aws_caller_identity.current.account_id}:dbuser:*/*",
          "arn:aws:redshift:*:${data.aws_caller_identity.current.account_id}:dbname:*/*"
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-redshift-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_redshift_attachment" {
  count      = local.redshift_enabled ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_redshift_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}

# -----------------------------------------------------------------------------
# Redshift Serverless - discovery + temporary credentials
# Provisioned Redshift is covered above; Serverless workgroups use a
# separate IAM namespace (redshift-serverless:*).
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "argus_agent_redshift_serverless_policy" {
  count       = local.redshift_enabled ? 1 : 0
  name        = "ArgusAgentRedshiftServerlessPolicy-${var.customer_name}"
  description = "Redshift Serverless describe + IAM-DB-Auth credentials."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RedshiftServerlessDiscovery"
        Effect = "Allow"
        Action = [
          "redshift-serverless:ListWorkgroups",
          "redshift-serverless:GetWorkgroup",
          "redshift-serverless:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid      = "RedshiftServerlessCredentials"
        Effect   = "Allow"
        Action   = ["redshift-serverless:GetCredentials"]
        Resource = "arn:aws:redshift-serverless:*:${data.aws_caller_identity.current.account_id}:workgroup/*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-redshift-serverless-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_redshift_serverless_attachment" {
  count      = local.redshift_enabled ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_redshift_serverless_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}

# -----------------------------------------------------------------------------
# IAM discovery - §11 Identity & Access in the Argus UI
# Read-only. The GetPolicyVersion + Get{User,Role,Group}Policy actions
# are required by the wildcard-inline over-privilege detector; without
# them Argus only matches AWS-managed admin ARNs and misses custom
# wildcard policies entirely.
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "argus_agent_iam_discovery_policy" {
  count       = local.iam_enabled ? 1 : 0
  name        = "ArgusAgentIAMDiscoveryPolicy-${var.customer_name}"
  description = "IAM read-only for Argus identity discovery + policy analysis."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMDiscovery"
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:GetUser",
          "iam:ListMFADevices",
          "iam:ListAccessKeys",
          "iam:GetAccessKeyLastUsed",
          "iam:ListUserTags",
          "iam:ListUserPolicies",
          "iam:GetUserPolicy",
          "iam:ListAttachedUserPolicies",
          "iam:ListRoles",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListGroups",
          "iam:ListGroupPolicies",
          "iam:GetGroupPolicy",
          "iam:ListAttachedGroupPolicies",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:GenerateCredentialReport",
          "iam:GetCredentialReport",
          "iam:SimulatePrincipalPolicy"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-iam-discovery-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_iam_discovery_attachment" {
  count      = local.iam_enabled ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_iam_discovery_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}

# -----------------------------------------------------------------------------
# CloudWatch read - bucket-size / object-count estimation
# Without this, S3 discovery falls back to a full paginated list to
# compute size, which is ~30× slower on multi-thousand-object buckets.
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "argus_agent_cloudwatch_read_policy" {
  count       = local.s3_enabled ? 1 : 0
  name        = "ArgusAgentCloudWatchReadPolicy-${var.customer_name}"
  description = "CloudWatch read for fast S3 size/count estimation."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchReadForS3Stats"
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricStatistics"]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-cloudwatch-read-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_cloudwatch_read_attachment" {
  count      = local.s3_enabled ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_cloudwatch_read_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}

# -----------------------------------------------------------------------------
# Remediation - write actions across S3 + IAM
# Enabled only when var.enable_remediation = true AND Tenant Settings →
# Remediation is enabled at the application layer (both gates required).
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "argus_agent_s3_remediation_policy" {
  count       = local.remediation_enabled && local.s3_enabled ? 1 : 0
  name        = "ArgusAgentS3RemediationPolicy-${var.customer_name}"
  description = "S3 write for Argus remediation (block public access, encryption, versioning, policy)."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3RemediationActions"
        Effect = "Allow"
        # Note: boto3 delete_public_access_block / delete_bucket_encryption
        # authorize against the s3:Put* actions below - there is no separate
        # s3:Delete* IAM action for those two operations.
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:PutEncryptionConfiguration",
          "s3:PutBucketVersioning",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy"
        ]
        Resource = "arn:aws:s3:::*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-s3-remediation-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_s3_remediation_attachment" {
  count      = local.remediation_enabled && local.s3_enabled ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_s3_remediation_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}

resource "aws_iam_policy" "argus_agent_iam_remediation_policy" {
  count       = local.remediation_enabled && local.iam_enabled ? 1 : 0
  name        = "ArgusAgentIAMRemediationPolicy-${var.customer_name}"
  description = "IAM write for Argus remediation (disable stale keys, remove over-privileged policies, enforce MFA)."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMRemediationActions"
        Effect = "Allow"
        Action = [
          "iam:UpdateAccessKey",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "argus-agent-iam-remediation-policy-${var.customer_name}"
  })
}

resource "aws_iam_role_policy_attachment" "argus_agent_iam_remediation_attachment" {
  count      = local.remediation_enabled && local.iam_enabled ? 1 : 0
  policy_arn = aws_iam_policy.argus_agent_iam_remediation_policy[0].arn
  role       = aws_iam_role.argus_agent_role.name
}
