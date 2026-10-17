<#
.SYNOPSIS
  Phase 0, step 4: wire the platform repo to the bootstrap stack.

.DESCRIPTION
  Sets the Actions variables that CI reads (Region, state bucket, role ARNs),
  stores the budget email as an Actions secret, creates the foundation
  environment limited to main, and applies the main branch ruleset from
  .github/rulesets/main.json. Safe to run again.

  Needs the GitHub CLI signed in as the repo owner (gh auth login) and the
  bootstrap stack already applied (scripts/phase0-bootstrap.ps1).
#>
[CmdletBinding()]
param(
    [string]$Owner = "AFP9272000",
    [string]$Repo = "eks-secure-gitops"
)

$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][scriptblock]$Command
    )
    $result = & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed with exit code $LASTEXITCODE."
    }
    return $result
}

$root        = Split-Path -Parent $PSScriptRoot
$fullName    = "$Owner/$Repo"
$rulesetFile = Join-Path $root ".github/rulesets/main.json"

foreach ($tool in "gh", "terraform") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not on PATH."
    }
}

# Outputs from the bootstrap stack (remote state).
$json = Invoke-Checked "terraform output" { terraform "-chdir=$root/infra/bootstrap" output -json }
$out  = ($json -join "`n") | ConvertFrom-Json

$variables = [ordered]@{
    AWS_REGION           = $out.aws_region.value
    TF_STATE_BUCKET      = $out.state_bucket.value
    TF_STATE_KMS_KEY_ARN = $out.kms_key_arn.value
    TF_PLAN_ROLE_ARN     = $out.tf_plan_role_arn.value
    TF_APPLY_ROLE_ARN    = $out.tf_apply_role_arn.value
}
foreach ($name in $variables.Keys) {
    Invoke-Checked "gh variable set $name" { gh variable set $name --repo $fullName --body $variables[$name] } | Out-Null
    Write-Host "Variable $name set."
}

$secrets = Invoke-Checked "gh secret list" { gh secret list --repo $fullName --json name --jq ".[].name" }
if ($secrets -notcontains "BUDGET_EMAIL") {
    Write-Host "Paste the email address for budget alerts when gh asks for the secret value."
    Invoke-Checked "gh secret set BUDGET_EMAIL" { gh secret set BUDGET_EMAIL --repo $fullName }
}
else {
    Write-Host "Secret BUDGET_EMAIL already exists. Run 'gh secret set BUDGET_EMAIL --repo $fullName' to change it."
}

# Environment for apply jobs: only main may deploy to it.
Invoke-Checked "create the foundation environment" {
    gh api --method PUT "repos/$fullName/environments/foundation" `
        -F "deployment_branch_policy[protected_branches]=false" `
        -F "deployment_branch_policy[custom_branch_policies]=true"
} | Out-Null
$branches = Invoke-Checked "list branch policies" {
    gh api "repos/$fullName/environments/foundation/deployment-branch-policies" --jq ".branch_policies[].name"
}
if ($branches -notcontains "main") {
    Invoke-Checked "limit the foundation environment to main" {
        gh api --method POST "repos/$fullName/environments/foundation/deployment-branch-policies" -f name=main -f type=branch
    } | Out-Null
}
Write-Host "Environment foundation accepts deployments from main only."

# Main branch ruleset, created or updated in place. Filtering happens in
# PowerShell because Windows PowerShell mangles quotes inside native arguments.
$rulesetsJson = Invoke-Checked "list rulesets" { gh api "repos/$fullName/rulesets" }
$rulesets     = ($rulesetsJson -join "`n") | ConvertFrom-Json
$rulesetId    = ($rulesets | Where-Object { $_.name -eq "main" } | Select-Object -First 1).id
if ($rulesetId) {
    Invoke-Checked "update the main ruleset" { gh api --method PUT "repos/$fullName/rulesets/$rulesetId" --input $rulesetFile } | Out-Null
    Write-Host "Ruleset main updated."
}
else {
    Invoke-Checked "create the main ruleset" { gh api --method POST "repos/$fullName/rulesets" --input $rulesetFile } | Out-Null
    Write-Host "Ruleset main created."
}

Write-Host ""
Write-Host "GitHub is wired. Next: open a pull request (docs/phase-0.md, step 5)."
