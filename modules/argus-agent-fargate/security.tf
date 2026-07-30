# Argus Agent Fargate Module — Security (security group + IAM)

# -----------------------------------------------------------------------------
# Security group
# -----------------------------------------------------------------------------

resource "aws_security_group" "argus_agent_sg" {
  name        = "${local.name_prefix}-sg"
  description = "Argus agent - outbound HTTPS only."
  vpc_id      = var.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to Argus control plane and AWS APIs."
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS."
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })
}

resource "aws_security_group_rule" "mysql_egress" {
  count             = var.enable_database_egress && local.rds_enabled ? 1 : 0
  type              = "egress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.argus_agent_sg.id
  description       = "MySQL/MariaDB egress for RDS scanning."
}

resource "aws_security_group_rule" "postgres_egress" {
  count             = var.enable_database_egress && local.rds_enabled ? 1 : 0
  type              = "egress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.argus_agent_sg.id
  description       = "PostgreSQL egress for RDS scanning."
}

resource "aws_security_group_rule" "redshift_egress" {
  count             = var.enable_database_egress && local.redshift_enabled ? 1 : 0
  type              = "egress"
  from_port         = 5439
  to_port           = 5439
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.argus_agent_sg.id
  description       = "Redshift egress for data warehouse scanning."
}

# -----------------------------------------------------------------------------
# Execution role — used by Fargate to pull image, fetch SSM secrets, write logs
# -----------------------------------------------------------------------------

resource "aws_iam_role" "execution" {
  name = "ArgusAgentExecutionRole-${var.customer_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "execution_basic" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "execution_ssm" {
  name        = "ArgusAgentExecutionSSMPolicy-${var.customer_name}"
  description = "Read enrollment-token SSM parameter for Fargate task execution."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SSMReadEnrollmentToken"
      Effect   = "Allow"
      Action   = ["ssm:GetParameters", "ssm:GetParameter"]
      Resource = aws_ssm_parameter.enrollment_token.arn
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "execution_ssm" {
  role       = aws_iam_role.execution.name
  policy_arn = aws_iam_policy.execution_ssm.arn
}

# -----------------------------------------------------------------------------
# Task role — credentials the agent process runs under (datastore scanning)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  name = "ArgusAgentTaskRole-${var.customer_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Datastore scanning policies (conditional)
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "task_s3" {
  count       = local.s3_enabled ? 1 : 0
  name        = "ArgusAgentS3Policy-${var.customer_name}"
  description = "S3 read for Argus scanning."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3BucketDiscovery"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation", "s3:GetBucketTagging"]
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
        # Required for public-bucket detection. See
        # docs/iam-permissions.md → S3 discovery section.
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:GetBucketPolicyStatus",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetEncryptionConfiguration",
          # Access-logging posture. Without it the logging control reads
          # "not verified" for a reason that is ours, not the customer's.
          "s3:GetBucketLogging"
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid      = "S3ObjectReadAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTagging"]
        Resource = "arn:aws:s3:::*/*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_s3" {
  count      = local.s3_enabled ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_s3[0].arn
}

resource "aws_iam_policy" "task_rds" {
  count       = local.rds_enabled ? 1 : 0
  name        = "ArgusAgentRDSPolicy-${var.customer_name}"
  description = "RDS describe + IAM DB Auth for Argus scanning."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RDSDiscovery"
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances", "rds:DescribeDBClusters", "rds:ListTagsForResource"]
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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_rds" {
  count      = local.rds_enabled ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_rds[0].arn
}

resource "aws_iam_policy" "task_dynamodb" {
  count       = local.dynamodb_enabled ? 1 : 0
  name        = "ArgusAgentDynamoDBPolicy-${var.customer_name}"
  description = "DynamoDB describe + read for Argus scanning."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBDiscovery"
        Effect = "Allow"
        # GetResourcePolicy: DynamoDB resource-based policies (2024+) can share a
        # table with Principal:"*". Without it we assert "private" on faith.
        Action   = ["dynamodb:ListTables", "dynamodb:DescribeTable", "dynamodb:ListTagsOfResource", "dynamodb:GetResourcePolicy"]
        Resource = "*"
      },
      {
        Sid      = "DynamoDBReadAccess"
        Effect   = "Allow"
        Action   = ["dynamodb:Scan", "dynamodb:Query", "dynamodb:GetItem", "dynamodb:BatchGetItem"]
        Resource = "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_dynamodb" {
  count      = local.dynamodb_enabled ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_dynamodb[0].arn
}

resource "aws_iam_policy" "task_redshift" {
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
        Action = ["redshift:GetClusterCredentials", "redshift:GetClusterCredentialsWithIAM"]
        Resource = [
          "arn:aws:redshift:*:${data.aws_caller_identity.current.account_id}:cluster:*",
          "arn:aws:redshift:*:${data.aws_caller_identity.current.account_id}:dbuser:*/*",
          "arn:aws:redshift:*:${data.aws_caller_identity.current.account_id}:dbname:*/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_redshift" {
  count      = local.redshift_enabled ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_redshift[0].arn
}

resource "aws_iam_policy" "task_db_secrets" {
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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_db_secrets" {
  count      = var.db_secrets_arn_pattern != "" ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_db_secrets[0].arn
}

resource "aws_iam_policy" "task_cloudwatch" {
  count       = var.enable_burst_autoscaling ? 1 : 0
  name        = "ArgusAgentCloudWatchPolicy-${var.customer_name}"
  description = "CloudWatch metric publish for the agent's ArgusDSPM/Agent PendingJobs gauge."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "CloudWatchMetricPublish"
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "cloudwatch:namespace" = "ArgusDSPM/Agent"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_cloudwatch" {
  count      = var.enable_burst_autoscaling ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_cloudwatch[0].arn
}

# -----------------------------------------------------------------------------
# Redshift Serverless — discovery + temporary credentials
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "task_redshift_serverless" {
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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_redshift_serverless" {
  count      = local.redshift_enabled ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_redshift_serverless[0].arn
}

# -----------------------------------------------------------------------------
# IAM discovery — §11 Identity & Access in the Argus UI
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "task_iam_discovery" {
  count       = local.iam_enabled ? 1 : 0
  name        = "ArgusAgentIAMDiscoveryPolicy-${var.customer_name}"
  description = "IAM read-only for identity discovery + policy analysis. Get*PolicyVersion + Get*Policy actions are required by the wildcard-inline over-privilege detector."

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
          # Group membership - without it an identity's effective permissions
          # via its groups are invisible to the access graph.
          "iam:ListGroupsForUser",
          "iam:ListGroupPolicies",
          "iam:GetGroupPolicy",
          "iam:ListAttachedGroupPolicies",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:GenerateCredentialReport",
          "iam:GetCredentialReport",
          # Permission-usage history, which drives over-provisioning detection
          # (granted vs actually used).
          "iam:GetServiceLastAccessedDetails",
          "iam:GenerateServiceLastAccessedDetails",
          "iam:SimulatePrincipalPolicy"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_iam_discovery" {
  count      = local.iam_enabled ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_iam_discovery[0].arn
}

# -----------------------------------------------------------------------------
# CloudWatch read — bucket-size / object-count estimation
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "task_cloudwatch_read" {
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
      },
      {
        # Region enumeration + the cross-account guard. Fargate has no instance
        # metadata policy (unlike the EC2 module), so these live here. Without
        # sts:GetCallerIdentity the agent refuses to persist scan results.
        Sid      = "ArgusAccountContext"
        Effect   = "Allow"
        Action   = ["ec2:DescribeRegions", "sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_cloudwatch_read" {
  count      = local.s3_enabled ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_cloudwatch_read[0].arn
}

# -----------------------------------------------------------------------------
# Remediation — S3 + IAM write
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "task_s3_remediation" {
  count       = local.remediation_enabled && local.s3_enabled ? 1 : 0
  name        = "ArgusAgentS3RemediationPolicy-${var.customer_name}"
  description = "S3 write actions for remediation: block public access, encryption, versioning, policy."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3RemediationActions"
        Effect = "Allow"
        # Note: boto3 delete_public_access_block / delete_bucket_encryption
        # authorize against the s3:Put* actions below — there is no separate
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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_s3_remediation" {
  count      = local.remediation_enabled && local.s3_enabled ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_s3_remediation[0].arn
}

resource "aws_iam_policy" "task_iam_remediation" {
  count       = local.remediation_enabled && local.iam_enabled ? 1 : 0
  name        = "ArgusAgentIAMRemediationPolicy-${var.customer_name}"
  description = "IAM write actions for remediation: disable stale keys, attach/detach policies, enforce MFA."

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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_iam_remediation" {
  count      = local.remediation_enabled && local.iam_enabled ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_iam_remediation[0].arn
}
