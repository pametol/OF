data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs = local.azs
  # Roomy /19 private subnets (8190 IPs each) so Karpenter has plenty of room to
  # scale pods/ENIs; smaller /24 public subnets for NAT GWs and load balancers.
  # Private /19s occupy netnums 0-2 (10.0.0.0 - 10.0.95.255), so public /24s
  # start at netnum 96 (10.0.96.0/24, ...) to avoid any overlap.
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 3, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 96)]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true # per-AZ NAT for HA (prod-shaped, costs more)

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter discovers which subnets to launch nodes into via this tag.
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}
