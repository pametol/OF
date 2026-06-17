locals {
  name = var.cluster_name

  tags = merge(var.tags, {
    Project   = "opsfleet-eks-karpenter-poc"
    ManagedBy = "terraform"
    Env       = "poc"
  })

  # The bootstrap/system node group is tainted so ONLY system components
  # (Karpenter controller, CoreDNS) run there. Application pods carry no
  # matching toleration, so the scheduler can't place them on the bootstrap
  # nodes -> they go Pending -> Karpenter provisions dedicated nodes for them.
  # This cleanly separates "system" capacity from "application" capacity.
  system_taint_key   = "dedicated"
  system_taint_value = "system"

  # Kubernetes-form toleration reused by the Karpenter Helm release and the
  # CoreDNS addon. (DaemonSet add-ons - VPC CNI, kube-proxy, pod-identity-agent
  # - already tolerate all taints, so they need no change.)
  system_toleration = {
    key      = local.system_taint_key
    operator = "Equal"
    value    = local.system_taint_value
    effect   = "NoSchedule"
  }
}
