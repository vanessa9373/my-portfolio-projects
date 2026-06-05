# ============================================================
# Multi-Cloud Architecture — AWS Side
# VPC, Transit Gateway, VPN Gateway, Subnets
# Author: Jenella Awo
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "multi-cloud", ManagedBy = "terraform", Owner = "jenella-v" }
  }
}

data "aws_availability_zones" "available" { state = "available" }

# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = var.aws_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "multi-cloud-aws-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.aws_vpc_cidr, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "multi-cloud-public-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.aws_vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "multi-cloud-private-${count.index + 1}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# --- Transit Gateway ---
resource "aws_ec2_transit_gateway" "main" {
  description = "Multi-cloud transit gateway"
  auto_accept_shared_attachments = "enable"
  tags = { Name = "multi-cloud-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  subnet_ids         = aws_subnet.private[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.main.id
}

# --- VPN Gateway (for Azure connection) ---
resource "aws_vpn_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "multi-cloud-vpn-gw" }
}

resource "aws_customer_gateway" "azure" {
  bgp_asn    = 65515   # Azure default ASN
  ip_address = var.azure_vpn_gateway_ip
  type       = "ipsec.1"
  tags       = { Name = "azure-customer-gw" }
}

resource "aws_vpn_connection" "azure" {
  vpn_gateway_id      = aws_vpn_gateway.main.id
  customer_gateway_id = aws_customer_gateway.azure.id
  type                = "ipsec.1"
  static_routes_only  = true
  tags = { Name = "aws-to-azure-vpn" }
}

resource "aws_vpn_connection_route" "azure_cidr" {
  destination_cidr_block = var.azure_vnet_cidr
  vpn_connection_id      = aws_vpn_connection.azure.id
}

# --- Route Tables ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block         = var.azure_vnet_cidr
    vpn_gateway_id     = aws_vpn_gateway.main.id
  }
  tags = { Name = "multi-cloud-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
