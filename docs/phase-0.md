# Phase 0 runbook: foundations

Phase 0 ends with every later phase running from CI with no static AWS keys. Steps 1 to 7 build and prove that; steps 8 to 11 prepare Ping, DNS, the GitHub App and the budget alert for later phases.

Commands are PowerShell on Windows. Run them from the repo root.

## 1. Install the tools

```powershell
choco install terraform awscli gh -y
terraform version   # 1.16 or later
aws --version       # aws-cli/2.x
gh --version
```

If PowerShell refuses to run the scripts, allow them for the current window only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## 2. Sign in and clone

Bootstrap creates IAM roles and a KMS key, so use administrator credentials for the target account.

```powershell
aws sso login --profile <admin-profile>
$env:AWS_PROFILE = "<admin-profile>"
gh auth login
git clone https://github.com/AFP9272000/eks-secure-gitops.git
cd eks-secure-gitops
```

## 3. Build the bootstrap stack

```powershell
.\scripts\phase0-bootstrap.ps1
```

The script confirms the account, then:

1. Reuses the account's GitHub OIDC provider if another project already created one.
2. Applies `infra/bootstrap` on local state: KMS key, state bucket, OIDC provider, permissions boundary, and the plan and apply roles. Review the plan and type `yes`.
3. Writes `infra/backend.hcl` and migrates the bootstrap state into the new bucket.
4. Locks provider hashes for Windows and the Linux runners in both stacks.

From here on the bootstrap stack runs only from an administrator's machine. CI cannot change the roles it assumes.

## 4. Wire GitHub to the bootstrap stack

```powershell
.\scripts\phase0-configure-github.ps1
```

It sets the Actions variables (Region, state bucket, KMS key, role ARNs), asks for the budget alert email and stores it as the `BUDGET_EMAIL` secret, creates the `foundation` environment limited to `main`, and applies the `main` ruleset: pull requests only, squash merges, no force pushes, code owner review, and three required checks.

## 5. Open the first pull request

The provider lock files from step 3 make a good first change, and the pull request proves CI can plan through OIDC.

```powershell
git switch -c phase0/provider-locks
git add infra/bootstrap/.terraform.lock.hcl infra/foundation/.terraform.lock.hcl
git commit -m "Lock AWS provider hashes for Windows and Linux"
git push -u origin HEAD
gh pr create --fill
gh pr checks --watch
```

Expect three green checks (`static-analysis`, `plan-foundation`, `zizmor`) and a plan comment that ends with `Plan: 42 to add, 0 to change, 0 to destroy.`

## 6. Merge, and CI applies the foundation

```powershell
gh pr merge --squash --delete-branch
gh run watch
```

The merge triggers `terraform-apply`, which assumes the apply role from the `foundation` environment and creates the ECR repositories, evidence bucket, Route 53 zone, budget, Ping DevOps secret and the two workload CI roles. The run log prints the zone's name servers for step 9.

## 7. Prove there is no drift

```powershell
gh workflow run terraform-drift.yml
gh run watch
```

A green run means a second plan reports no changes. This check also runs daily.

## 8. Store the Ping DevOps credentials

Register once: sign in at pingidentity.com (create an account if needed), open **Support and Community**, go to your profile page and select **Register for DevOps Program**. The DevOps user and key arrive by email.

```powershell
@{ user = "<devops user>"; key = "<devops key>" } | ConvertTo-Json -Compress | Set-Content -Encoding ascii ping-devops.json
aws secretsmanager put-secret-value --secret-id eks-secure-gitops/ping-devops --secret-string file://ping-devops.json
Remove-Item ping-devops.json
```

The value goes straight to Secrets Manager and never enters Terraform state.

## 9. Delegate the lab subdomain and turn on the certificate

Read the name servers:

```powershell
terraform -chdir=infra/foundation init -input=false "-backend-config=$PWD\infra\backend.hcl"
terraform -chdir=infra/foundation output lab_name_servers
```

At the DNS provider for `pirlocloudsecurity.com`, add four `NS` records with host `lab`, one per name server. Then confirm the delegation:

```powershell
Resolve-DnsName -Type NS lab.pirlocloudsecurity.com
```

When the answer lists the Route 53 name servers, open a pull request that sets `enable_certificate = true` in `infra/foundation/settings.auto.tfvars`. After the merge, CI requests the wildcard certificate, writes the validation record and waits for issuance.

## 10. Create the GitHub App for pull requests

Two workflows open pull requests in the platform repo: digest PRs from the app repo (Phase 3) and prod promotions (Phase 7). They use a GitHub App because pull requests opened with `GITHUB_TOKEN` do not trigger workflows, so the required checks would never run.

1. Go to **github.com/settings/apps** and select **New GitHub App**.
2. Name it `eks-secure-gitops-bot` (add a suffix if the name is taken). Homepage URL: `https://github.com/AFP9272000/eks-secure-gitops`. Clear **Active** under Webhook.
3. Repository permissions: **Contents** read and write, **Pull requests** read and write.
4. Installation: **Only on this account**. Select **Create GitHub App**.
5. Copy the **Client ID**, then select **Generate a private key**. The `.pem` file downloads.
6. Select **Install App**, choose **Only select repositories**, pick `eks-secure-gitops`, and install.
7. Store the credentials and delete the key file:

```powershell
.\scripts\phase0-github-app.ps1 -AppClientId <client id> -PrivateKeyPath "$HOME\Downloads\<file>.pem"
Remove-Item "$HOME\Downloads\<file>.pem"
```

The script creates the `release` environment in the app repo and the `promotion` environment in the platform repo, both limited to `main`, and stores the client ID and key in each. This key is the only long-lived credential in CI.

## 11. Prove the budget alert

Open a pull request that uncomments `budget_test_alert_usd = 0.01` in `infra/foundation/settings.auto.tfvars`, and merge it. AWS Budgets refreshes spend data up to three times a day, and the email arrives once the month's spend passes $0.01. After it arrives, remove the line in a second pull request.

## Exit criteria

- [ ] `plan-foundation` passes on a pull request through OIDC, and `gh secret list` on both repos shows no AWS access key.
- [ ] `terraform-drift` reports no changes after the foundation apply.
- [ ] The test budget alert email arrives.

Ready for later phases:

- [ ] Ping DevOps credentials stored in `eks-secure-gitops/ping-devops`.
- [ ] `lab.pirlocloudsecurity.com` delegated and the wildcard certificate issued.
- [ ] GitHub App credentials stored in the `release` and `promotion` environments.

Save a screenshot or command output for each item; Phase 9 turns them into the README evidence gallery.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The job's subject claim does not match the role trust. Plans run on pull requests from branches in this repo; applies run in the `foundation` environment on `main`. |
| `EntityAlreadyExists` for the OIDC provider | Create `infra/bootstrap/github-oidc.auto.tfvars` with `existing_github_oidc_provider_arn = "<arn>"` and rerun step 3. |
| `plan-foundation` fails on `terraform init` | Rerun step 4; one of the Actions variables is missing. |
| Scripts are blocked | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` in the same window. |
