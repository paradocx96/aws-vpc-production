locals {
  gateway_endpoints = toset(["s3", "dynamodb"])

  # Trim this list to the services you actually use. Each one costs money in every AZ.
  interface_endpoints = toset([
    "ecr.api",        # ECR control plane
    "ecr.dkr",        # ECR Docker registry
    "logs",           # CloudWatch Logs
    "sts",            # IAM role credentials
    "secretsmanager", # Secrets Manager
    "ssm",            # Systems Manager
    "ssmmessages",    # Session Manager
    "ec2messages",    # Systems Manager agent
  ])
}

# ---------- Gateway endpoints: free, route-table based ----------
resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_endpoints

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [for rt in aws_route_table.private : rt.id],
    [aws_route_table.data.id]
  )

  tags = { Name = "${var.name}-${each.key}-gw-endpoint" }
}

# ---------- Interface endpoints: PrivateLink ENIs in the private subnets ----------
resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true # the normal service hostname now resolves to the endpoint

  tags = { Name = "${var.name}-${each.key}-endpoint" }
}
