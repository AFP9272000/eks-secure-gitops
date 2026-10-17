# The first apply runs on local state through a git-ignored backend_override.tf
# (docs/phase-0.md, step 3). After that, this stack's state moves into the
# bucket it creates, and infra/backend.hcl supplies bucket, region and key.
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
