locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

# ─── INTERNET GATEWAY ─────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

# ─── PUBLIC SUBNETS ───────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # ALB nodes in public subnets — EC2 instances do NOT get public IPs
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-public-${count.index + 1}" }
}

# ─── PRIVATE APP SUBNETS ──────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${local.name_prefix}-private-${count.index + 1}" }
}

# ─── DATABASE SUBNETS ─────────────────────────────────────────────────────────

resource "aws_subnet" "database" {
  count             = length(var.database_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${local.name_prefix}-database-${count.index + 1}" }
}

# ─── ELASTIC IPs for NAT GATEWAYS ─────────────────────────────────────────────

resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]
  tags       = { Name = "${local.name_prefix}-nat-eip-${count.index + 1}" }
}

# ─── NAT GATEWAYS — one per AZ for HA ────────────────────────────────────────

resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.main]
  tags       = { Name = "${local.name_prefix}-nat-${count.index + 1}" }
}

# ─── ROUTE TABLES ─────────────────────────────────────────────────────────────

# Public route table — single, shared (all public subnets route to IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables — one per AZ so each AZ uses its own NAT GW
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = { Name = "${local.name_prefix}-private-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Database subnets — local only, NO internet route
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-database-rt" }
}

resource "aws_route_table_association" "database" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# ─── RDS SUBNET GROUP ─────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = { Name = "${local.name_prefix}-db-subnet-group" }
}

# ─── VPC FLOW LOGS ────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${local.name_prefix}/flow-logs"
  retention_in_days = 30
}

resource "aws_iam_role" "flow_logs" {
  name = "${local.name_prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = { Name = "${local.name_prefix}-vpc-flow-log" }
}

# ─── VPC ENDPOINTS — keep traffic off the internet ────────────────────────────

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.database.id]
  )

  tags = { Name = "${local.name_prefix}-s3-endpoint" }
}

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [var.endpoint_security_group_id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-ssm-endpoint" }
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [var.endpoint_security_group_id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-secretsmanager-endpoint" }
}
