# Argus Agent EC2 Module — Main configuration

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Data sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  vpc_id      = var.vpc_id != "" ? var.vpc_id : aws_vpc.argus_vpc[0].id
  subnet_id   = var.subnet_id != "" ? var.subnet_id : aws_subnet.argus_subnet[0].id
  vpc_cidr    = var.vpc_id != "" ? data.aws_vpc.selected[0].cidr_block : aws_vpc.argus_vpc[0].cidr_block
  selected_az = var.availability_zone != "" ? var.availability_zone : data.aws_availability_zones.available.names[0]

  # Datastore opt-in resolution (enable_all overrides individuals)
  s3_enabled       = var.enable_all_datastores || var.enable_s3_scanning
  rds_enabled      = var.enable_all_datastores || var.enable_rds_scanning
  dynamodb_enabled = var.enable_all_datastores || var.enable_dynamodb_scanning
  redshift_enabled = var.enable_all_datastores || var.enable_redshift_scanning
  iam_enabled         = var.enable_iam_discovery
  remediation_enabled = var.enable_remediation

  enabled_datastores = jsonencode({
    s3       = local.s3_enabled
    rds      = local.rds_enabled
    dynamodb = local.dynamodb_enabled
    redshift = local.redshift_enabled
  })

  common_tags = merge({
    Name        = "argus-agent-${var.customer_name}"
    Customer    = var.customer_name
    Environment = var.environment
    Component   = "argus-agent"
    ManagedBy   = "terraform"
    Project     = "argus-dspm"
  }, var.additional_tags)

  # User-data template — the variable map MUST match the placeholders
  # inside user_data.sh exactly. See user_data.sh header for the contract.
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    argus_backend_url      = var.argus_backend_url
    aws_region             = var.aws_region
    enrollment_token_param = aws_ssm_parameter.enrollment_token.name
    aws_role_arn           = "" # same-account model — agent uses its instance profile
    aws_external_id        = "" # not used in same-account model
    agent_image            = var.agent_container_image
  }))
}

# -----------------------------------------------------------------------------
# Network — created only when caller didn't supply vpc_id / subnet_id
# -----------------------------------------------------------------------------

resource "aws_vpc" "argus_vpc" {
  count = var.vpc_id == "" ? 1 : 0

  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "argus-vpc-${var.customer_name}"
  })
}

resource "aws_internet_gateway" "argus_igw" {
  count = var.vpc_id == "" ? 1 : 0

  vpc_id = aws_vpc.argus_vpc[0].id

  tags = merge(local.common_tags, {
    Name = "argus-igw-${var.customer_name}"
  })
}

resource "aws_subnet" "argus_subnet" {
  count = var.subnet_id == "" ? 1 : 0

  vpc_id                  = local.vpc_id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.selected_az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "argus-subnet-${var.customer_name}"
  })
}

resource "aws_route_table" "argus_rt" {
  count = var.vpc_id == "" ? 1 : 0

  vpc_id = aws_vpc.argus_vpc[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.argus_igw[0].id
  }

  tags = merge(local.common_tags, {
    Name = "argus-rt-${var.customer_name}"
  })
}

resource "aws_route_table_association" "argus_rta" {
  count = var.subnet_id == "" ? 1 : 0

  subnet_id      = aws_subnet.argus_subnet[0].id
  route_table_id = aws_route_table.argus_rt[0].id
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "argus_agent_logs" {
  name              = "/argus/agent/${var.customer_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "argus-agent-logs-${var.customer_name}"
  })
}

# -----------------------------------------------------------------------------
# Enrollment token — stored in SSM Parameter Store as SecureString. The
# agent's user_data reads it once at startup and exchanges it for a
# per-container API key via /api/v1/agents/bootstrap. The token itself
# stays in SSM so subsequent host reboots can re-bootstrap if needed.
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "enrollment_token" {
  name        = "/argus/agent/${var.customer_name}/enrollment-token"
  description = "Argus enrollment token. Read by EC2 user_data at boot; exchanged once for a per-container API key."
  type        = "SecureString"
  value       = var.enrollment_token
  overwrite   = true

  tags = merge(local.common_tags, {
    Name = "argus-agent-enrollment-token-${var.customer_name}"
  })
}
