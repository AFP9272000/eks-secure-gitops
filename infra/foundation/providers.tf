provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      Stack     = "foundation"
      ManagedBy = "terraform"
      Repo      = "${var.github_owner}/${var.platform_repo}"
    }
  }
}
