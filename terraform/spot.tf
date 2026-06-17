# EC2 Spot service-linked role.
#
# Karpenter launches Spot capacity via the EC2 CreateFleet API, which requires
# the account to have the AWSServiceRoleForEC2Spot service-linked role. Fresh
# accounts often don't have it, so Karpenter's Spot launches fail and it falls
# back to On-Demand (visible as `karpenter.sh/capacity-type: on-demand` on every
# node despite the NodePool allowing Spot).
#
# This creates the role once. If it already exists in your account, set
# `create_spot_service_linked_role = false` to avoid an "already exists" error
# (or import it: `terraform import aws_iam_service_linked_role.spot[0] <arn>`).
resource "aws_iam_service_linked_role" "spot" {
  count            = var.create_spot_service_linked_role ? 1 : 0
  aws_service_name = "spot.amazonaws.com"
  description      = "EC2 Spot SLR (managed by opsfleet-poc Terraform)"
}
