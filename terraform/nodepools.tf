# Karpenter v1 resources (EC2NodeClass + per-arch NodePools) are delivered via a
# small local Helm chart rather than the alekc/kubectl provider.
#
# Why: kubectl_manifest configures its provider eagerly and fails at PLAN time
# on a fresh build ("no configuration has been provided") because the cluster
# endpoint is not known until apply. The Helm provider defers configuration
# until apply, so this delivers the same CRs in a single `terraform apply`.
#
# The chart templates live in ./charts/karpenter-resources. All cluster-specific
# values (node IAM role, discovery tag, tags, architectures) are passed in here.
resource "helm_release" "karpenter_resources" {
  namespace = "kube-system"
  name      = "karpenter-resources"
  chart     = "${path.module}/charts/karpenter-resources"

  # No long-running workloads in this chart (cluster-scoped CRs only), so there
  # is nothing for Helm to wait on.
  wait = false

  values = [
    yamlencode({
      nodeRole      = module.karpenter.node_iam_role_name
      discoveryTag  = local.name
      architectures = ["amd64", "arm64"]
      tags          = merge(local.tags, { "karpenter.sh/discovery" = local.name })
      limits = {
        cpu    = var.nodepool_cpu_limit
        memory = var.nodepool_memory_limit
      }
    })
  ]

  # CRDs must exist (karpenter_crd) and the controller must be running
  # (karpenter) before the custom resources are applied.
  depends_on = [helm_release.karpenter]
}
