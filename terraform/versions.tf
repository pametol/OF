terraform {
  # >= 1.10 enables native S3 state locking (use_lockfile), removing the need
  # for a DynamoDB lock table.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Pinned to 2.x: provider 3.x switched the kubernetes{} block to attribute
    # syntax; providers.tf uses the 2.x block form. Karpenter CRs (EC2NodeClass
    # / NodePool) are delivered via a local Helm chart (see nodepools.tf), so no
    # third-party kubectl provider is needed.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}
