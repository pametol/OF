# Partial backend configuration.
#
# The S3 bucket must exist BEFORE `terraform init` (chicken-and-egg). Create it
# once with the ./bootstrap module, then initialise this root module with:
#
#   terraform init -backend-config=backend.hcl
#
# See backend.hcl.example for the values to provide.
terraform {
  backend "s3" {
    encrypt = true
    # Native S3 state locking (Terraform >= 1.10). No DynamoDB table required.
    use_lockfile = true
  }
}
