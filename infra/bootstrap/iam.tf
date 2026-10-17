locals {
  iam_prefix       = "arn:${local.partition}:iam::${local.account_id}"
  project_roles    = "${local.iam_prefix}:role/${var.project}-*"
  project_policies = "${local.iam_prefix}:policy/${var.project}-*"
  terraform_roles  = "${local.iam_prefix}:role/${var.project}-tf-*"
}

################################################################################
# Permissions boundary
#
# Every role the apply role creates must carry this boundary. It is a ceiling,
# not a grant: a bounded role can never write IAM, touch Organizations or change
# account settings, whatever its own policies say. That closes the classic
# escalation path where CI creates a new admin role and uses it.
################################################################################

data "aws_iam_policy_document" "boundary" {
  #checkov:skip=CKV_AWS_109:Permissions boundary. It caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_111:Permissions boundary. It caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_356:Permissions boundary. It caps permissions and grants nothing on its own.
  #checkov:skip=CKV2_AWS_40:Permissions boundary. It caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_107:Permissions boundary. It caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_108:Permissions boundary. It caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_110:Permissions boundary. It removes IAM writes, the escalation path this check looks for.
  statement {
    sid         = "CeilingForServiceActions"
    effect      = "Allow"
    not_actions = ["iam:*", "organizations:*", "account:*"]
    resources   = ["*"]
  }

  statement {
    sid       = "CeilingForIdentityReads"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*", "iam:CreateServiceLinkedRole"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${var.project}-boundary"
  description = "Ceiling for every role the Terraform apply role creates: no IAM writes, no Organizations or account changes."
  policy      = data.aws_iam_policy_document.boundary.json
}

################################################################################
# Plan role: pull requests and scheduled drift checks
#
# Read-only. Pull request plans run with -lock=false, so this role never writes
# state. Object reads are limited to the state bucket.
################################################################################

data "aws_iam_policy_document" "tf_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.platform_repo_sub}:pull_request",
        "${local.platform_repo_sub}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "tf_plan" {
  name                 = "${var.project}-tf-plan"
  description          = "Terraform plans from pull requests and drift checks. Read-only."
  assume_role_policy   = data.aws_iam_policy_document.tf_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "tf_plan_read_only" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "tf_plan" {
  statement {
    sid       = "DecryptState"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.platform.arn]
  }

  statement {
    sid           = "DenyObjectReadsOutsideState"
    effect        = "Deny"
    actions       = ["s3:GetObject", "s3:GetObjectVersion"]
    not_resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role_policy" "tf_plan" {
  name   = "state-access"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.tf_plan.json
}

################################################################################
# Apply role: protected GitHub environments on main only
#
# PowerUserAccess covers every service except IAM, Organizations and account.
# IAM is granted narrowly below: project-prefixed roles and policies only, and
# every new role must carry the boundary. Explicit denies stop the role from
# changing itself, the plan role, the boundary, the state bucket or the key.
################################################################################

data "aws_iam_policy_document" "tf_apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for env in var.apply_environments : "${local.platform_repo_sub}:environment:${env}"]
    }
  }
}

resource "aws_iam_role" "tf_apply" {
  name                 = "${var.project}-tf-apply"
  description          = "Terraform applies from protected GitHub environments on main."
  assume_role_policy   = data.aws_iam_policy_document.tf_apply_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "tf_apply_power_user" {
  role       = aws_iam_role.tf_apply.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "tf_apply" {
  #checkov:skip=CKV_AWS_109:IAM writes are limited to project-prefixed roles and policies, and new roles must carry the boundary.
  #checkov:skip=CKV_AWS_111:IAM writes are limited to project-prefixed roles and policies, and new roles must carry the boundary.
  #checkov:skip=CKV_AWS_356:Resource "*" appears only on reads, service-linked roles scoped by service name, and explicit denies.
  #checkov:skip=CKV2_AWS_40:Full IAM is not granted; IAM writes are limited to project-prefixed resources.
  statement {
    sid       = "ReadIdentity"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid       = "CreateRolesOnlyWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = [local.project_roles]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary.arn]
    }
  }

  statement {
    sid = "ManageProjectRoles"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:AttachRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:TagRole",
      "iam:UntagInstanceProfile",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
    ]
    resources = [
      local.project_roles,
      "${local.iam_prefix}:instance-profile/${var.project}-*",
    ]
  }

  statement {
    sid = "ManageProjectPolicies"
    actions = [
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [local.project_policies]
  }

  statement {
    sid       = "PassProjectRolesToServices"
    actions   = ["iam:PassRole"]
    resources = [local.project_roles]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "eks.amazonaws.com", "pods.eks.amazonaws.com"]
    }
  }

  statement {
    sid       = "ServiceLinkedRolesForEks"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "autoscaling.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "eks.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "spot.amazonaws.com",
      ]
    }
  }

  statement {
    sid         = "DenyChangesToTerraformRolesAndBoundary"
    effect      = "Deny"
    not_actions = ["iam:Get*", "iam:List*"]
    resources   = [local.terraform_roles, aws_iam_policy.boundary.arn]
  }

  statement {
    sid       = "DenyRolesWithoutBoundary"
    effect    = "Deny"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary.arn]
    }
  }

  statement {
    sid       = "DenyBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyRoleChaining"
    effect    = "Deny"
    actions   = ["sts:AssumeRole"]
    resources = ["*"]
  }

  statement {
    sid    = "ProtectPlatformKey"
    effect = "Deny"
    actions = [
      "kms:DisableKey",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
    ]
    resources = [aws_kms_key.platform.arn]
  }

  statement {
    sid    = "ProtectStateBucket"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
    ]
    resources = [aws_s3_bucket.state.arn]
  }
}

resource "aws_iam_role_policy" "tf_apply" {
  name   = "scoped-iam-and-guardrails"
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.tf_apply.json
}
