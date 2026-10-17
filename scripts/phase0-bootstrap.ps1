<#
.SYNOPSIS
  Phase 0, step 3: build the bootstrap stack from your machine.

.DESCRIPTION
  First run: applies infra/bootstrap on local state, writes infra/backend.hcl,
  then migrates the bootstrap state into the bucket it just created.
  Later runs: plans and applies infra/bootstrap against remote state.
  Both runs refresh the provider lock files for Windows and Linux runners.

  Run from the repo root with AWS credentials for the target account, for
  example after `aws sso login` or with an admin profile in AWS_PROFILE.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][scriptblock]$Command
    )
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed with exit code $LASTEXITCODE."
    }
}

$root       = Split-Path -Parent $PSScriptRoot
$stack      = Join-Path $root "infra/bootstrap"
$foundation = Join-Path $root "infra/foundation"
$override   = Join-Path $stack "backend_override.tf"
$backendHcl = Join-Path $root "infra/backend.hcl"
$oidcVars   = Join-Path $stack "github-oidc.auto.tfvars"

foreach ($tool in "terraform", "aws") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not on PATH. Install it first (docs/phase-0.md, step 1)."
    }
}

# Confirm the target account before anything is created.
$identityJson = aws sts get-caller-identity --output json
if ($LASTEXITCODE -ne 0 -or -not $identityJson) {
    throw "No working AWS credentials. Sign in first, for example with aws sso login."
}
$identity = ($identityJson -join "`n") | ConvertFrom-Json
Write-Host "AWS account: $($identity.Account)"
Write-Host "Caller:      $($identity.Arn)"
$answer = Read-Host "Build the bootstrap stack in this account? Type yes to continue"
if ($answer -ne "yes") {
    Write-Host "Stopped. Nothing was changed."
    exit 0
}

$firstRun = -not (Test-Path $backendHcl)

if ($firstRun) {
    # An account holds one GitHub OIDC provider. Reuse it if another project
    # already created one; the choice is saved in a git-ignored tfvars file.
    if (-not (Test-Path $oidcVars)) {
        $existing = aws iam list-open-id-connect-providers `
            --query "OpenIDConnectProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')].Arn" `
            --output text
        if ($LASTEXITCODE -ne 0) { throw "Listing OIDC providers failed." }
        if ($existing -and $existing.Trim() -ne "" -and $existing.Trim() -ne "None") {
            "existing_github_oidc_provider_arn = `"$($existing.Trim())`"" | Set-Content -Encoding ascii $oidcVars
            Write-Host "Reusing the existing GitHub OIDC provider: $($existing.Trim())"
        }
    }

    Write-Host "First run: applying on local state."
    'terraform { backend "local" {} }' | Set-Content -Encoding ascii $override
    try {
        Invoke-Checked "terraform init (local state)" { terraform "-chdir=$stack" init -input=false }
        Invoke-Checked "terraform apply" { terraform "-chdir=$stack" apply }
        $hcl = terraform "-chdir=$stack" output -raw backend_hcl
        if ($LASTEXITCODE -ne 0) { throw "Reading backend_hcl failed." }
        ($hcl -join "`n") | Set-Content -Encoding ascii $backendHcl
        Write-Host "Wrote $backendHcl"
    }
    finally {
        Remove-Item $override -ErrorAction SilentlyContinue
    }

    Write-Host "Migrating bootstrap state into the state bucket."
    Invoke-Checked "terraform init -migrate-state" {
        terraform "-chdir=$stack" init -input=false -migrate-state -force-copy "-backend-config=$backendHcl"
    }
}
else {
    Invoke-Checked "terraform init" { terraform "-chdir=$stack" init -input=false -reconfigure "-backend-config=$backendHcl" }
    Invoke-Checked "terraform apply" { terraform "-chdir=$stack" apply }
}

# Lock provider hashes for this machine and for the Linux CI runners.
foreach ($dir in $stack, $foundation) {
    Invoke-Checked "terraform providers lock ($dir)" {
        terraform "-chdir=$dir" providers lock -platform=windows_amd64 -platform=linux_amd64
    }
}

Write-Host ""
Write-Host "Bootstrap is done. Commit the two .terraform.lock.hcl files, then run:"
Write-Host "  .\scripts\phase0-configure-github.ps1"
