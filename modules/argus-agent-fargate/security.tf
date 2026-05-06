# Argus Agent Fargate Module — Security (security group + IAM)

# -----------------------------------------------------------------------------
# Security group
# -----------------------------------------------------------------------------

resource "aws_security_group" "argus_agent_sg" {
  name        = "${local.name_prefix}-sg"
  description = "Argus agent — outbound HTTPS only."
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
  name = "${local.name_prefix}-execution"

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
  name        = "${local.name_prefix}-execution-ssm"
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
  name = "${local.name_prefix}-task"

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
  name        = "${local.name_prefix}-task-s3"
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
  name        = "${local.name_prefix}-task-rds"
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
  name        = "${local.name_prefix}-task-dynamodb"
  description = "DynamoDB describe + read for Argus scanning."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoDBDiscovery"
        Effect   = "Allow"
        Action   = ["dynamodb:ListTables", "dynamodb:DescribeTable", "dynamodb:ListTagsOfResource"]
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
  name        = "${local.name_prefix}-task-redshift"
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
  name        = "${local.name_prefix}-task-db-secrets"
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
  name        = "${local.name_prefix}-task-cloudwatch"
  description = "CloudWatch metric publish for the agent's argus_pending_jobs gauge."

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
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_cloudwatch.arn
}
