# Plan-time tests with a mocked AWS provider: no credentials, no AWS calls.
# Run with `terraform -chdir=infra/foundation test`.

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
    target = data.aws_kms_alias.platform
    values = {
      target_key_arn = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
    }
  }

  override_data {
    target = data.aws_iam_openid_connect_provider.github
    values = {
      arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  override_data {
    target = data.aws_iam_policy.boundary
    values = {
      arn = "arn:aws:iam::111122223333:policy/eks-secure-gitops-boundary"
    }
  }
}

variables {
  lab_domain   = "lab.example.com"
  budget_email = "alerts@example.com"
}

run "defaults" {
  command = plan

  variables {
    enable_certificate    = false
    budget_test_alert_usd = null
  }

  assert {
    condition     = length(aws_acm_certificate.wildcard) == 0
    error_message = "The certificate must stay off until the NS delegation resolves."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "Every ECR repository must use immutable tags."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_scanning_configuration[0].scan_on_push])
    error_message = "Every ECR repository must scan on push."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.encryption_configuration[0].encryption_type == "KMS"])
    error_message = "Every ECR repository must use the platform KMS key."
  }

  assert {
    condition     = length(aws_budgets_budget.monthly.notification) == 3
    error_message = "Expected the three standing budget alerts."
  }

  assert {
    condition     = aws_iam_role.image_push.permissions_boundary == "arn:aws:iam::111122223333:policy/eks-secure-gitops-boundary"
    error_message = "The image push role must carry the permissions boundary."
  }

  assert {
    condition     = aws_iam_role.evidence_read.permissions_boundary == "arn:aws:iam::111122223333:policy/eks-secure-gitops-boundary"
    error_message = "The evidence read role must carry the permissions boundary."
  }
}

run "certificate_on" {
  command = plan

  variables {
    enable_certificate = true
  }

  assert {
    condition     = length(aws_acm_certificate.wildcard) == 1
    error_message = "enable_certificate must request the wildcard certificate."
  }

  assert {
    condition     = contains(aws_acm_certificate.wildcard[0].subject_alternative_names, "*.lab.example.com")
    error_message = "The certificate must cover every host under the lab domain."
  }
}

run "budget_test_alert" {
  command = plan

  variables {
    budget_test_alert_usd = 0.01
  }

  assert {
    condition     = length(aws_budgets_budget.monthly.notification) == 4
    error_message = "budget_test_alert_usd must add one absolute-value alert."
  }
}

run "image_push_trusts_app_main_only" {
  command = plan

  assert {
    condition = toset(flatten([
      for c in data.aws_iam_policy_document.image_push_trust.statement[0].condition : c.values
      if c.variable == "token.actions.githubusercontent.com:sub"
    ])) == toset(["repo:AFP9272000/crapi-secure-build:ref:refs/heads/main"])
    error_message = "The image push role must trust only the app repo's main branch."
  }
}

run "evidence_read_trusts_platform_pull_requests_only" {
  command = plan

  assert {
    condition = toset(flatten([
      for c in data.aws_iam_policy_document.evidence_read_trust.statement[0].condition : c.values
      if c.variable == "token.actions.githubusercontent.com:sub"
    ])) == toset(["repo:AFP9272000/eks-secure-gitops:pull_request"])
    error_message = "The evidence read role must trust only platform repo pull requests."
  }
}

run "rejects_bad_lab_domain" {
  command = plan

  variables {
    lab_domain = "Lab.Example.com"
  }

  expect_failures = [var.lab_domain]
}
