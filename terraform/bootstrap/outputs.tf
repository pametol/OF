output "bucket_name" {
  description = "Name of the created state bucket."
  value       = aws_s3_bucket.tfstate.id
}

output "backend_config" {
  description = "Paste these values into ../backend.hcl."
  value       = <<-EOT
    bucket = "${aws_s3_bucket.tfstate.id}"
    key    = "eks-karpenter/terraform.tfstate"
    region = "${var.region}"
  EOT
}
