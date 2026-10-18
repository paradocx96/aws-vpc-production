locals {
  eph_from = 1024
  eph_to   = 65535
  anywhere = "0.0.0.0/0"

  # ---------- Public tier: ALB and NAT gateways ----------
  public_nacl_rules = {
    public_in_https  = { nacl = "public", rule = 100, egress = false, proto = "tcp", cidr = local.anywhere, from = 443, to = 443 }
    public_in_http   = { nacl = "public", rule = 110, egress = false, proto = "tcp", cidr = local.anywhere, from = 80, to = 80 }
    public_in_return = { nacl = "public", rule = 120, egress = false, proto = "tcp", cidr = local.anywhere, from = local.eph_from, to = local.eph_to }
    public_in_vpc    = { nacl = "public", rule = 130, egress = false, proto = "-1", cidr = var.vpc_cidr, from = 0, to = 0 }

    public_out_https  = { nacl = "public", rule = 100, egress = true, proto = "tcp", cidr = local.anywhere, from = 443, to = 443 }
    public_out_return = { nacl = "public", rule = 110, egress = true, proto = "tcp", cidr = local.anywhere, from = local.eph_from, to = local.eph_to }
    public_out_vpc    = { nacl = "public", rule = 120, egress = true, proto = "-1", cidr = var.vpc_cidr, from = 0, to = 0 }
  }

  # ---------- Private tier: applications and interface endpoints ----------
  private_nacl_rules = merge(
    {
      private_in_app    = { nacl = "private", rule = 100, egress = false, proto = "tcp", cidr = var.vpc_cidr, from = var.app_port, to = var.app_port }
      private_in_https  = { nacl = "private", rule = 110, egress = false, proto = "tcp", cidr = var.vpc_cidr, from = 443, to = 443 }
      private_in_return = { nacl = "private", rule = 120, egress = false, proto = "tcp", cidr = local.anywhere, from = local.eph_from, to = local.eph_to }

      private_out_https  = { nacl = "private", rule = 100, egress = true, proto = "tcp", cidr = local.anywhere, from = 443, to = 443 }
      private_out_return = { nacl = "private", rule = 150, egress = true, proto = "tcp", cidr = var.vpc_cidr, from = local.eph_from, to = local.eph_to }
    },
    # Database access, but only towards the data subnets
    { for az, cidr in local.data_subnets : "private_out_db_${az}" => {
      nacl = "private", rule = 110 + index(local.azs, az), egress = true, proto = "tcp", cidr = cidr, from = var.db_port, to = var.db_port
    } }
  )

  # ---------- Data tier: only the private subnets may connect ----------
  data_nacl_rules = merge(
    { for az, cidr in local.private_subnets : "data_in_db_${az}" => {
      nacl = "data", rule = 100 + index(local.azs, az), egress = false, proto = "tcp", cidr = cidr, from = var.db_port, to = var.db_port
    } },
    { for az, cidr in local.private_subnets : "data_out_return_${az}" => {
      nacl = "data", rule = 100 + index(local.azs, az), egress = true, proto = "tcp", cidr = cidr, from = local.eph_from, to = local.eph_to
    } }
  )

  nacl_rules = merge(local.public_nacl_rules, local.private_nacl_rules, local.data_nacl_rules)

  nacl_ids = {
    public  = aws_network_acl.public.id
    private = aws_network_acl.private.id
    data    = aws_network_acl.data.id
  }
}

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  tags = { Name = "${var.name}-public-nacl" }
}

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.private : s.id]

  tags = { Name = "${var.name}-private-nacl" }
}

resource "aws_network_acl" "data" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.data : s.id]

  tags = { Name = "${var.name}-data-nacl" }
}

resource "aws_network_acl_rule" "this" {
  for_each = local.nacl_rules

  network_acl_id = local.nacl_ids[each.value.nacl]
  rule_number    = each.value.rule
  egress         = each.value.egress
  protocol       = each.value.proto
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = each.value.from
  to_port        = each.value.to
}
