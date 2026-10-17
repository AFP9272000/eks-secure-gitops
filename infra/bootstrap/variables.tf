variable "project" {
  description = "Name prefix for every resource in this platform."
  type        = string
  default     = "eks-secure-gitops"
}

variable "aws_region" {
  description = "AWS Region for the platform."
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub account that owns the platform and app repos."
  type        = string
  default     = "AFP9272000"
}

variable "platform_repo" {
  description = "Repo that holds Terraform, GitOps config and policies."
  type        = string
  default     = "eks-secure-gitops"
}

variable "apply_environments" {
  description = "GitHub environments in the platform repo whose jobs may assume the apply role. Each one is limited to the main branch in GitHub."
  type        = list(string)
  default     = ["foundation", "cluster"]
}

variable "existing_github_oidc_provider_arn" {
  description = "ARN of an existing token.actions.githubusercontent.com OIDC provider in this account. Leave empty to create one."
  type        = string
  default     = ""
}
