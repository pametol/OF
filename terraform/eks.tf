module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  endpoint_private_access      = true

  # Authentication is API-only (EKS access entries, no aws-auth ConfigMap).
  # The identity running Terraform is granted cluster-admin so it can apply
  # the Karpenter manifests and so a reviewer can immediately use kubectl.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Managed core add-ons. The Pod Identity Agent + VPC CNI are installed before
  # compute so networking and workload identity are ready when nodes join.
  addons = {
    # CoreDNS is a Deployment, so it needs an explicit toleration to run on the
    # tainted bootstrap nodes (unlike the DaemonSet add-ons below).
    coredns = {
      configuration_values = jsonencode({
        tolerations = [local.system_toleration]
      })
    }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
  }

  # Small on-demand managed node group that hosts Karpenter, CoreDNS and other
  # system pods. Karpenter itself cannot run on nodes it hasn't created yet, so
  # this group breaks the chicken-and-egg. It is tainted system-only (see the
  # taint below + local.system_toleration); all application capacity comes from
  # Karpenter NodePools (see nodepools.tf).
  #
  # Sizing is driven by var.bootstrap_instance_types and var.bootstrap_scaling
  # (TEST defaults: 1x t3.medium). See terraform.tfvars.production.example for
  # production values.
  eks_managed_node_groups = {
    bootstrap = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.bootstrap_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.bootstrap_scaling.min_size
      max_size     = var.bootstrap_scaling.max_size
      desired_size = var.bootstrap_scaling.desired_size

      labels = {
        role = "bootstrap"
      }

      taints = {
        system = {
          key    = local.system_taint_key
          value  = local.system_taint_value
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Tag the node security group so the Karpenter EC2NodeClass can discover it.
  node_security_group_tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })

  tags = local.tags
}
