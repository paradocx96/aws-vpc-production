data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name = "opt-in-status"
    values = [
      "opt-in-not-required"
    ]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Maps of AZ name => subnet CIDR
  public_subnets  = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 8, i) }      # /24
  data_subnets    = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 8, i + 10) } # /24
  private_subnets = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 4, i + 1) }  # /20

  nat_count = var.single_nat_gateway ? 1 : var.az_count
}
