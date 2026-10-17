output "aws_region" {
  description = "Region the platform runs in."
  value       = var.aws_region
}

output "state_bucket" {
  description = "S3 bucket that holds Terraform state for every stack."
  value       = aws_s3_bucket.state.bucket
}

output "kms_key_arn" {
  description = "Customer managed key for state, images, evidence and secrets."
  value       = aws_kms_key.platform.arn
}

output "kms_alias" {
  description = "Alias other stacks use to look up the key."
  value       = aws_kms_alias.platform.name
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider."
  value       = local.github_oidc_provider_arn
}

output "permissions_boundary_arn" {
  description = "Boundary every Terraform-created role must carry."
  value       = aws_iam_policy.boundary.arn
}

output "tf_plan_role_arn" {
  description = "Read-only role for pull request plans and drift checks."
  value       = aws_iam_role.tf_plan.arn
}

output "tf_apply_role_arn" {
  description = "Apply role for protected GitHub environments on main."
  value       = aws_iam_role.tf_apply.arn
}

output "backend_hcl" {
  description = "Contents for infra/backend.hcl. The runbook writes this file for you."
  value       = <<-EOT
    bucket     = "${aws_s3_bucket.state.bucket}"
    region     = "${var.aws_region}"
    kms_key_id = "${aws_kms_key.platform.arn}"
  EOT
}
