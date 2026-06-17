# Karpenter supporting AWS resources: node IAM role + instance profile, the
# controller IAM role, the SQS interruption queue and EventBridge rules, and an
# EKS Pod Identity association for the controller service account.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  namespace = "kube-system"

  # Workload identity via EKS Pod Identity (no per-cluster OIDC trust policy).
  # See README "Pod Identity vs IRSA" for the rationale and the cloud-agnostic
  # trade-off.
  create_pod_identity_association = true

  # Deterministic node role name so the EC2NodeClass can reference it directly.
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${local.name}-karpenter-node"

  # SSM lets you debug Karpenter-launched nodes without SSH/bastion.
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

# CRDs are installed via a dedicated chart so their lifecycle is decoupled from
# the controller (Helm does not upgrade CRDs bundled in the main chart).
resource "helm_release" "karpenter_crd" {
  namespace        = "kube-system"
  name             = "karpenter-crd"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter-crd"
  version          = var.karpenter_version
  create_namespace = false

  depends_on = [module.eks]
}

resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  wait       = true

  values = [
    yamlencode({
      serviceAccount = {
        name = module.karpenter.service_account
      }
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      # Pin the controller to the bootstrap node group so it never schedules
      # onto nodes it manages (which could evict itself during consolidation),
      # and tolerate that group's system-only taint.
      nodeSelector = {
        role = "bootstrap"
      }
      tolerations = [local.system_toleration]
      # Sizing via var.karpenter_controller_cpu/memory (TEST defaults are modest;
      # docs recommend 1 CPU / 1Gi for production). No CPU limit on purpose, to
      # avoid throttling the controller under load.
      controller = {
        resources = {
          requests = { cpu = var.karpenter_controller_cpu, memory = var.karpenter_controller_memory }
          limits   = { memory = var.karpenter_controller_memory }
        }
      }
    })
  ]

  depends_on = [helm_release.karpenter_crd]
}
