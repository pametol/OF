variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket name for the root module's Terraform state."
  type        = string
}
