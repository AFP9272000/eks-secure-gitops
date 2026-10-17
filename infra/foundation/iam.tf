# Roles for GitHub Actions jobs outside Terraform. Both carry the permissions
# boundary, which the apply role must attach to any role it creates.

################################################################################
# Image push: build, mirror and sign workflows on the app repo's main branch
################################################################################

data "aws_iam_policy_document" "image_push_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.app_repo_sub}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "image_push" {
  name                 = "${var.project}-image-push"
  description          = "Pushes and signs images in project ECR repositories from the app repo's main branch."
  assume_role_policy   = data.aws_iam_policy_document.image_push_trust.json
  permissions_boundary = data.aws_iam_policy.boundary.arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "image_push" {
  statement {
    sid       = "RegistryLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushToProjectRepositories"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for repository in aws_ecr_repository.this : repository.arn]
  }
}

resource "aws_iam_role_policy" "image_push" {
  name   = "ecr-push"
  role   = aws_iam_role.image_push.id
  policy = data.aws_iam_policy_document.image_push.json
}

################################################################################
# Evidence read: the dast-gate check on platform repo pull requests
################################################################################

data "aws_iam_policy_document" "evidence_read_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.platform_repo_sub}:pull_request"]
    }
  }
}

resource "aws_iam_role" "evidence_read" {
  name                 = "${var.project}-evidence-read"
  description          = "Reads DAST results for the prod promotion check."
  assume_role_policy   = data.aws_iam_policy_document.evidence_read_trust.json
  permissions_boundary = data.aws_iam_policy.boundary.arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "evidence_read" {
  statement {
    sid       = "ReadDastResults"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.evidence.arn}/dast/*"]
  }

  statement {
    sid       = "ListDastResults"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.evidence.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["dast/*"]
    }
  }

  statement {
    sid       = "DecryptEvidence"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "evidence_read" {
  name   = "dast-evidence-read"
  role   = aws_iam_role.evidence_read.id
  policy = data.aws_iam_policy_document.evidence_read.json
}
