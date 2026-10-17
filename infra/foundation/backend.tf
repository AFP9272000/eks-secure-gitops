# infra/backend.hcl (locally) or -backend-config flags (in CI) supply bucket,
# region and kms_key_id.
terraform {
  backend "s3" {
    key          = "foundation/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
