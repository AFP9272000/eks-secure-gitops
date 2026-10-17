# The lab subdomain is delegated to this zone with NS records at the parent
# domain's DNS provider. ExternalDNS writes records here from Phase 2 on.
resource "aws_route53_zone" "lab" {
  #checkov:skip=CKV2_AWS_38:DNSSEC needs a DS record at the parent domain's provider; tracked as a stretch goal.
  #checkov:skip=CKV2_AWS_39:Query logging adds a log group with no consumer in this lab.
  name    = var.lab_domain
  comment = "Lab subdomain for ${var.project}"
}

# One wildcard certificate covers argocd, sso and crapi-staging behind a single
# ALB. It lives here, not in the cluster stack, so rebuilds skip DNS validation.
# It stays off until the NS delegation resolves, because validation waits on it.
resource "aws_acm_certificate" "wildcard" {
  #checkov:skip=CKV2_AWS_71:One wildcard certificate serves every host behind the single lab ALB.
  count = var.enable_certificate ? 1 : 0

  domain_name               = var.lab_domain
  subject_alternative_names = ["*.${var.lab_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = var.enable_certificate ? {
    for option in aws_acm_certificate.wildcard[0].domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}

  # The apex and the wildcard share one validation record.
  allow_overwrite = true
  zone_id         = aws_route53_zone.lab.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

resource "aws_acm_certificate_validation" "wildcard" {
  count = var.enable_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}
