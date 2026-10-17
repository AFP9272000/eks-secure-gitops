<#
.SYNOPSIS
  Phase 0, step 10: store the GitHub App credentials for the two workflows
  that open pull requests.

.DESCRIPTION
  Creates the "release" environment in the app repo (digest PRs) and the
  "promotion" environment in the platform repo (prod promotion PRs), limits
  both to main, and stores the App's client ID and private key in each.
  Delete the .pem file afterwards; GitHub keeps the copies the workflows use.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppClientId,
    [Parameter(Mandatory)][string]$PrivateKeyPath,
    [string]$Owner = "AFP9272000",
    [string]$PlatformRepo = "eks-secure-gitops",
    [string]$AppRepo = "crapi-secure-build"
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

if (-not (Test-Path $PrivateKeyPath)) {
    throw "Private key not found: $PrivateKeyPath"
}
$privateKey = Get-Content -Raw $PrivateKeyPath

$targets = @(
    @{ Repo = "$Owner/$AppRepo"; Environment = "release" },
    @{ Repo = "$Owner/$PlatformRepo"; Environment = "promotion" }
)

foreach ($target in $targets) {
    $repo = $target.Repo
    $env  = $target.Environment

    Invoke-Checked "create environment $env in $repo" {
        gh api --method PUT "repos/$repo/environments/$env" `
            -F "deployment_branch_policy[protected_branches]=false" `
            -F "deployment_branch_policy[custom_branch_policies]=true"
    } | Out-Null
    $branches = Invoke-Checked "list branch policies" {
        gh api "repos/$repo/environments/$env/deployment-branch-policies" --jq ".branch_policies[].name"
    }
    if ($branches -notcontains "main") {
        Invoke-Checked "limit $env to main" {
            gh api --method POST "repos/$repo/environments/$env/deployment-branch-policies" -f name=main -f type=branch
        } | Out-Null
    }

    Invoke-Checked "set GH_APP_CLIENT_ID" {
        gh variable set GH_APP_CLIENT_ID --repo $repo --env $env --body $AppClientId
    } | Out-Null
    Invoke-Checked "set GH_APP_PRIVATE_KEY" {
        $privateKey | gh secret set GH_APP_PRIVATE_KEY --repo $repo --env $env
    } | Out-Null
    Write-Host "Environment $env in $repo holds the App credentials and accepts main only."
}

Write-Host ""
Write-Host "Done. Delete $PrivateKeyPath now."
