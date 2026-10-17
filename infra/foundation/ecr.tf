# Images live here by digest. Tags are immutable, every push is scanned, and
# Cosign v3 stores signatures and SBOM attestations next to each image as OCI
# 1.1 referrers.
resource "aws_ecr_repository" "this" {
  for_each = toset(var.ecr_repositories)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = local.kms_key_arn
  }
}

# Expire only tagged images. Signatures and attestations are untagged
# referrers, and an age-based untagged rule would strip signatures from
# images that are still running, which Kyverno would then refuse.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the newest ${var.ecr_tagged_images_to_keep} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.ecr_tagged_images_to_keep
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
