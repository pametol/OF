variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile to use for the AWS provider and the in-cluster `aws eks get-token` auth. Leave null to use the default credential chain (env vars, default profile, instance role)."
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "EKS cluster name. Also used for resource naming and the Karpenter discovery tag value."
  type        = string
  default     = "opsfleet-poc"
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across."
  type        = number
  default     = 3
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version (v1.x). Must be compatible with the cluster's Kubernetes version (1.36 needs >= 1.12). Latest releases: https://github.com/aws/karpenter-provider-aws/releases."
  type        = string
  default     = "1.13.0"
}

variable "bootstrap_instance_types" {
  description = "Instance types for the small on-demand managed node group that hosts Karpenter and system add-ons. TEST default is a single cheap t3.medium; for production prefer larger types and multiple options for capacity availability (e.g. [\"m7i.large\", \"m6i.large\"])."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "bootstrap_scaling" {
  description = "Size of the bootstrap/system managed node group. TEST default is a single node; for production use >= 2 (ideally one per AZ) for HA of Karpenter and CoreDNS."
  type = object({
    min_size     = number
    desired_size = number
    max_size     = number
  })
  default = {
    min_size     = 1
    desired_size = 1
    max_size     = 2
  }
}

variable "karpenter_controller_cpu" {
  description = "Karpenter controller CPU request. TEST default is modest; the Karpenter docs recommend 1 (vCPU) for production throughput."
  type        = string
  default     = "500m"
}

variable "karpenter_controller_memory" {
  description = "Karpenter controller memory request/limit. TEST default is modest; the Karpenter docs recommend 1Gi for production."
  type        = string
  default     = "512Mi"
}

variable "nodepool_cpu_limit" {
  description = "Per-NodePool CPU limit (Karpenter stops adding nodes past this). Low TEST cap to bound cost; raise for production."
  type        = string
  default     = "16"
}

variable "nodepool_memory_limit" {
  description = "Per-NodePool memory limit. Low TEST cap to bound cost; raise for production."
  type        = string
  default     = "64Gi"
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS public API endpoint is enabled. Kept on for easy grading; disable for production."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. RESTRICT THIS in real environments."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "create_spot_service_linked_role" {
  description = "Create the EC2 Spot service-linked role (AWSServiceRoleForEC2Spot). REQUIRED for Karpenter to launch Spot instances; without it, Karpenter silently falls back to On-Demand. Set to false if the role already exists in the account (otherwise apply errors with 'role already exists')."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
