# Branch Protection Configuration

To enforce the CI requirements for PR merges, configure the following branch protection rules in your GitHub repository settings:

## Main Branch Protection Rules

Navigate to: `Settings > Branches > Add rule` for `main` branch

### Required Settings:
- ✅ **Require a pull request before merging**
  - ✅ Require approvals: 1
  - ✅ Dismiss stale PR approvals when new commits are pushed
  - ✅ Require review from code owners (if CODEOWNERS file exists)

- ✅ **Require status checks to pass before merging**
  - ✅ Require branches to be up to date before merging
  - Required status checks:
    - `Loan Provider Tests`
    - `Security Checks`
    - `Coverage Report`

- ✅ **Require conversation resolution before merging**
- ✅ **Restrict pushes that create files that exceed 100 MB**
- ✅ **Do not allow bypassing the above settings** (unless admin override needed)

### Optional but Recommended:
- ✅ **Require linear history** (prevents merge commits)
- ✅ **Include administrators** (applies rules to repo admins too)

## Test Branch Protection Rules

Apply similar rules to `test` branch but with relaxed approval requirements for development purposes.

## CLI Command (if using GitHub CLI):

```bash
# Set branch protection for main
gh api repos/:owner/:repo/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["Loan Provider Tests","Security Checks","Coverage Report"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"dismiss_stale_reviews":true,"require_code_owner_reviews":true,"required_approving_review_count":1}' \
  --field restrictions=null
```
