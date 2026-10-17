# GitHub Actions authenticates to AWS with short-lived OIDC tokens. An account
# holds one provider per URL, so reuse an existing one when it is already there.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.existing_github_oidc_provider_arn == "" ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  github_oidc_provider_arn = (
    var.existing_github_oidc_provider_arn != ""
    ? var.existing_github_oidc_provider_arn
    : aws_iam_openid_connect_provider.github[0].arn
  )

  # Subject claim prefix for jobs in the platform repo.
  platform_repo_sub = "repo:${var.github_owner}/${var.platform_repo}"
}
