# Container only. The value is put with the AWS CLI (docs/phase-0.md, step 8),
# so it never passes through Terraform state. In Phase 5 a seed job copies it
# into Conjur, and Ping's containers read it from there.
resource "aws_secretsmanager_secret" "ping_devops" {
  #checkov:skip=CKV2_AWS_57:Ping issues this credential; it rotates by re-registering, not through a rotation Lambda.
  name                    = "${var.project}/ping-devops"
  description             = "Ping Identity DevOps user and key for evaluation licenses."
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 7
}
