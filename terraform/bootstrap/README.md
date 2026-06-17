# bootstrap - Terraform state bucket

Creates the S3 bucket that the root module uses as its remote backend. This is
a one-time step that runs with a **local** state file (it can't store its own
state in the bucket it is about to create).

```bash
cd bootstrap

terraform init
terraform apply -var="bucket_name=opsfleet-poc-tfstate-<ACCOUNT_ID>"

# Copy the printed backend_config into ../backend.hcl
terraform output backend_config
```

Notes:
- The bucket has versioning, KMS (SSE) encryption, and a public-access block.
- `prevent_destroy` guards against accidental deletion of state history. Remove
  that lifecycle block if you intentionally want to tear it down.
- The root module uses **native S3 locking** (`use_lockfile = true`), so no
  DynamoDB lock table is needed.
