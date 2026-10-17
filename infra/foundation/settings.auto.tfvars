# Non-secret settings for the foundation stack, reviewed in pull requests like
# any other change. budget_email arrives through TF_VAR_budget_email.

lab_domain = "lab.pirlocloudsecurity.com"

# Turn on after `nslookup -type=NS lab.pirlocloudsecurity.com` returns the
# Route 53 name servers (docs/phase-0.md, step 9).
enable_certificate = false

monthly_budget_usd = 40

# Phase 0 exit check: set to 0.01, merge, wait for the email, then remove.
# budget_test_alert_usd = 0.01
