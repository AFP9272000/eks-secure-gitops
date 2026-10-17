# Everything below comes from the bootstrap stack, looked up by name so the
# two stacks share no state.
data "aws_caller_identity" "current" {}

data "aws_kms_alias" "platform" {
  name = "alias/${var.project}"
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy" "boundary" {
  name = "${var.project}-boundary"
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  kms_key_arn = data.aws_kms_alias.platform.target_key_arn

  app_repo_sub      = "repo:${var.github_owner}/${var.app_repo}"
  platform_repo_sub = "repo:${var.github_owner}/${var.platform_repo}"
}
