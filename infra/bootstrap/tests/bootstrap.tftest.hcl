# Plan-time tests with a mocked AWS provider: no credentials, no AWS calls.
# Run with `terraform -chdir=infra/bootstrap test`.

mock_provider "aws" {
  # Generated policy documents need to be valid JSON for the resources that use them.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "111122223333"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }
}

run "creates_github_oidc_provider_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "The stack must create the GitHub OIDC provider when no existing ARN is given."
  }
}

run "reuses_existing_github_oidc_provider" {
  command = plan

  variables {
    existing_github_oidc_provider_arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "The stack must not create a second GitHub OIDC provider."
  }
}

run "state_bucket_is_locked_down" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "eks-secure-gitops-tfstate-111122223333"
    error_message = "State bucket name must carry the account ID."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State bucket must keep versions."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "State bucket must block every form of public access."
  }

  assert {
    condition     = aws_kms_key.platform.enable_key_rotation
    error_message = "The platform key must rotate."
  }
}

run "plan_role_trusts_pull_requests_and_main_only" {
  command = plan

  assert {
    condition = toset(flatten([
      for c in data.aws_iam_policy_document.tf_plan_trust.statement[0].condition : c.values
      if c.variable == "token.actions.githubusercontent.com:sub"
      ])) == toset([
      "repo:AFP9272000/eks-secure-gitops:pull_request",
      "repo:AFP9272000/eks-secure-gitops:ref:refs/heads/main",
    ])
    error_message = "The plan role must trust only platform repo pull requests and main."
  }
}

run "apply_role_trusts_protected_environments_only" {
  command = plan

  assert {
    condition = toset(flatten([
      for c in data.aws_iam_policy_document.tf_apply_trust.statement[0].condition : c.values
      if c.variable == "token.actions.githubusercontent.com:sub"
      ])) == toset([
      "repo:AFP9272000/eks-secure-gitops:environment:foundation",
      "repo:AFP9272000/eks-secure-gitops:environment:cluster",
    ])
    error_message = "The apply role must trust only the protected GitHub environments."
  }
}
