data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  state_bucket = "${var.project}-tfstate-${local.account_id}"
}

# One customer managed key encrypts Terraform state, ECR images, DAST evidence
# and Secrets Manager values. The key policy delegates to IAM, so each role's
# own policy decides what it can do with the key.
data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Key policy. Resource "*" means this key only, and IAM policies scope every caller.
  #checkov:skip=CKV_AWS_111:Key policy. Resource "*" means this key only, and IAM policies scope every caller.
  #checkov:skip=CKV_AWS_356:Key policy. Resource "*" means this key only, and IAM policies scope every caller.
  statement {
    sid       = "DelegateToIam"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "platform" {
  description             = "${var.project}: Terraform state, ECR, evidence and secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.project}"
  target_key_id = aws_kms_key.platform.key_id
}

# Terraform state for every stack. S3 native locking (use_lockfile) replaces
# the DynamoDB lock table.
# Access logging is replaced by KMS audit trails; see the checkov skip below.
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Every state read and write calls KMS (bucket keys are off), and CloudTrail records each call with the caller and object ARN.
  #checkov:skip=CKV_AWS_144:Single-Region lab; versioning protects state history.
  #checkov:skip=CKV2_AWS_62:No consumer for state bucket event notifications.
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.platform.arn
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}
