#!/usr/bin/env bash
# Apply the repository rules the release pipeline expects.
#
# GitHub only exposes branch protection and repository settings to a
# repository admin, so run this once with an admin token:
#
#   gh auth login          # account with admin on the target repo
#   ./scripts/apply-branch-protection.sh [owner/repo]
#
# The defaults match the submission repository.
set -euo pipefail

REPO="${1:-swadhin-biswas/devops-assesment}"
BRANCH="${BRANCH:-main}"

echo "applying repository rules to ${REPO} (${BRANCH})"

# Squash-only merges, delete the branch after merge, allow auto-merge.
gh api -X PATCH "repos/${REPO}" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -F allow_auto_merge=true \
  -F allow_update_branch=true >/dev/null

# Branch protection. The check names are the job names in pr.yml.
gh api -X PUT "repos/${REPO}/branches/${BRANCH}/protection" \
  --input - >/dev/null <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "lint-and-test",
      "lint-containers",
      "image-scan",
      "config-lint"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": true
}
JSON

# Read-only GITHUB_TOKEN by default.
gh api -X PUT "repos/${REPO}/actions/permissions/workflow" \
  -F default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false >/dev/null

echo "done: ${REPO} ${BRANCH} is protected (PR, linear history, 4 required checks, squash-only)"
