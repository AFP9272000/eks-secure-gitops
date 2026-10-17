variable "project" {
  description = "Name prefix shared with the bootstrap stack."
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

variable "app_repo" {
  description = "Fork of OWASP crAPI that builds, scans and signs images."
  type        = string
  default     = "crapi-secure-build"
}

variable "lab_domain" {
  description = "Subdomain delegated to Route 53 for the lab, for example lab.example.com."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.lab_domain))
    error_message = "lab_domain must be a lowercase DNS name such as lab.example.com."
  }
}

variable "enable_certificate" {
  description = "Request and validate the wildcard ACM certificate. Turn on only after the NS delegation for lab_domain resolves."
  type        = bool
  default     = false
}

variable "budget_email" {
  description = "Address that receives AWS Budgets alerts. Supplied through TF_VAR_budget_email, never committed."
  type        = string
  sensitive   = true
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget for the account, in USD."
  type        = number
  default     = 40
}

variable "budget_test_alert_usd" {
  description = "Optional extra alert at an absolute spend, used once to prove the email path. Leave null in normal use."
  type        = number
  default     = null
}

variable "ecr_repositories" {
  description = "ECR repositories: crapi/* for images built from the fork, mirror/* for third-party images re-signed by the pipeline."
  type        = list(string)
  default = [
    "crapi/chatbot",
    "crapi/community",
    "crapi/gateway-service",
    "crapi/identity",
    "crapi/mailhog",
    "crapi/web",
    "crapi/workshop",
    "mirror/chromadb",
    "mirror/k8s-wait-for",
    "mirror/mongo",
    "mirror/postgres",
    "mirror/secrets-provider",
    "mirror/toolbox",
    "mirror/zap",
  ]
}

variable "ecr_tagged_images_to_keep" {
  description = "Tagged images kept per repository. Untagged signature and attestation artifacts are never expired by rule."
  type        = number
  default     = 10
}
