provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = local.tags
  }
}

# The helm provider authenticates to the cluster by shelling out to
# `aws eks get-token` at apply time. This avoids storing a long-lived token in
# state and works for any IAM identity that has an EKS access entry (the
# Terraform runner gets cluster-admin via
# enable_cluster_creator_admin_permissions).
#
# Note: the helm provider gracefully defers configuration when the cluster
# endpoint is still unknown on a fresh apply. (The alekc/kubectl provider does
# NOT, which is why Karpenter CRs are delivered via a local Helm chart in
# nodepools.tf rather than kubectl_manifest.)
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = concat(
        ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region],
        var.aws_profile != null ? ["--profile", var.aws_profile] : [],
      )
    }
  }
}
