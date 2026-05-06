# Argus Agent EC2 Module — Security (security group + IAM)

# -----------------------------------------------------------------------------
# Security group — outbound HTTPS for control plane + AWS APIs
# -----------------------------------------------------------------------------

resource "aws_security_group" "argus_agent_sg" {
  name        = "argus-agent-sg-${var.customer_name}"
  description = "Argus agent — outbound HTTPS only (data sovereignty: no inbound from provider)."
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
    description = "Agent health endpoint — internal VPC only."
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
      description = "SSH for debugging — remove in production."
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
# Bootstrap permissions — read enrollment token from SSM
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
# Secrets Manager — only for customer-side DB credentials (optional).
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
