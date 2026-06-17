output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "region" {
  description = "AWS region."
  value       = var.region
}

output "vpc_id" {
  description = "ID of the dedicated VPC."
  value       = module.vpc.vpc_id
}

output "karpenter_node_iam_role_name" {
  description = "IAM role assumed by Karpenter-launched nodes."
  value       = module.karpenter.node_iam_role_name
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
