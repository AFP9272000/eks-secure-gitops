output "lab_zone_id" {
  description = "Route 53 zone for the lab subdomain."
  value       = aws_route53_zone.lab.zone_id
}

output "lab_name_servers" {
  description = "Add these as NS records for the lab subdomain at the parent domain's DNS provider."
  value       = aws_route53_zone.lab.name_servers
}

output "certificate_arn" {
  description = "Validated wildcard certificate, once enable_certificate is true."
  value       = var.enable_certificate ? aws_acm_certificate_validation.wildcard[0].certificate_arn : null
}

output "ecr_repository_urls" {
  description = "Repository URLs by name."
  value       = { for name, repository in aws_ecr_repository.this : name => repository.repository_url }
}

output "evidence_bucket" {
  description = "Bucket for DAST results and release evidence."
  value       = aws_s3_bucket.evidence.bucket
}

output "image_push_role_arn" {
  description = "Role for the app repo's build, mirror and sign workflows."
  value       = aws_iam_role.image_push.arn
}

output "evidence_read_role_arn" {
  description = "Role for the dast-gate check."
  value       = aws_iam_role.evidence_read.arn
}

output "ping_devops_secret_arn" {
  description = "Secrets Manager secret that holds the Ping DevOps credentials."
  value       = aws_secretsmanager_secret.ping_devops.arn
}
