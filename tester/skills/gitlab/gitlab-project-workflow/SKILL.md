---
name: gitlab-project-workflow
description: "Use for GitLab repository authentication, issues, merge requests, review notes, and CI/CD pipeline management through glab or the GitLab REST API."
version: 1.0.0
author: Hermes autonomous development team
license: Private
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [GitLab, Issues, Merge-Requests, CI/CD, Git, Automation]
---

# GitLab Project Workflow

Use this skill only when the repository remote is GitLab. It does not override the role's read-only, report-only, approval, or security boundaries.

## Detect The Repository Host

Inspect the actual remote before using a hosting CLI:

```bash
REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
case "$REMOTE_URL" in
  *://*) REMOTE_AUTHORITY="${REMOTE_URL#*://}"; REMOTE_AUTHORITY="${REMOTE_AUTHORITY%%/*}"; REMOTE_AUTHORITY="${REMOTE_AUTHORITY##*@}" ;;
  *@*:*) REMOTE_AUTHORITY="${REMOTE_URL#*@}"; REMOTE_AUTHORITY="${REMOTE_AUTHORITY%%:*}" ;;
  *) REMOTE_AUTHORITY="" ;;
esac
REMOTE_HOST="${REMOTE_AUTHORITY%%:*}"
case "${REMOTE_HOST,,}" in
  github.com|github.*|*.github.*) SCM_PROVIDER=github ;;
  gitlab.com|gitlab.*|*.gitlab.*) SCM_PROVIDER=gitlab ;;
  *) SCM_PROVIDER=generic ;;
esac
printf 'remote=%s\nhost=%s\nprovider=%s\n' "$REMOTE_URL" "$REMOTE_HOST" "$SCM_PROVIDER"
```

For a self-managed GitLab hostname that does not contain `gitlab`, use the project's configured `HERMES_AUTODEV_SCM_PROVIDER=gitlab` value or explicit task context. Never run `gh` against GitLab or `glab` against GitHub.

## Authentication

Prefer `glab`. It detects nested namespaces and the GitLab hostname from the current repository remote.

```bash
glab --version
glab auth status
glab repo view
```

The setup wizard can provide:

- `GITLAB_TOKEN`: GitLab access token used by `glab` and REST fallbacks.
- `GITLAB_HOST`: GitLab base URL, defaulting to `https://gitlab.com`.

Manual token login:

```bash
GITLAB_HOSTNAME="${GITLAB_HOST:-https://gitlab.com}"
GITLAB_HOSTNAME="${GITLAB_HOSTNAME#https://}"
GITLAB_HOSTNAME="${GITLAB_HOSTNAME#http://}"
GITLAB_HOSTNAME="${GITLAB_HOSTNAME%%/*}"
printf '%s\n' "$GITLAB_TOKEN" | glab auth login --hostname "$GITLAB_HOSTNAME" --stdin
```

Never print a token, add it to a Git remote URL, commit it, paste it into an issue/MR, or place it in a shell history command. Use the narrowest token and project access appropriate to the task.

## Repository And Issue Context

Run commands inside the target repository, or pass `--repo GROUP/NAMESPACE/PROJECT`.

```bash
glab repo view
glab issue list --opened --per-page 50
glab issue view 42
glab issue create --title "Bug: concise outcome" \
  --description "Impact, reproduction, expected behavior, acceptance criteria." \
  --label bug --yes
glab issue note 42 --message "Status update with Kanban task link."
glab issue close 42
```

Use confidential issues for sensitive security findings only when project policy and access controls make that appropriate:

```bash
glab issue create --confidential --title "Security finding" \
  --description "Redacted summary and restricted evidence link." --yes
```

Do not put live secrets, customer data, or unnecessary exploit detail in GitLab.

## Branch And Merge Request Lifecycle

Follow project conventions and protected-branch rules.

```bash
git fetch origin --prune
git switch -c fix/issue-42
# Make and validate the authorized changes.
git status --short
git diff --check
git push -u origin HEAD

glab mr create --fill --fill-commit-body --yes
glab mr view
glab mr diff
```

For explicit metadata:

```bash
glab mr create \
  --title "fix: concise outcome" \
  --description "Summary, issue/Kanban links, validation, risks." \
  --target-branch main \
  --remove-source-branch \
  --yes
```

Link the MR to its issue using GitLab closing syntax such as `Closes #42` when closure is intended. Link both records back to the Hermes Kanban task.

Review and status notes:

```bash
glab mr note create 123 --message "Validation result and evidence link." --resolvable=false
glab mr approve 123
glab mr update 123 --ready --yes
```

Approval and merge are state-changing actions. Perform them only when the role is allowed, required reviews and tests have passed, and project policy or the human owner authorizes the action.

```bash
glab mr merge 123 --squash --remove-source-branch --yes
```

## GitLab CI/CD

Check the pipeline for the current branch or MR rather than treating a successful local test as sufficient CI evidence.

```bash
glab ci status
glab ci status --wait
glab ci list --ref "$(git branch --show-current)" --per-page 20
glab ci get --merge-request 123 --with-job-details
glab ci get --merge-request 123 --status failed --with-job-details
```

Record the pipeline ID, commit SHA, status, failed job names, and relevant redacted log excerpts. Do not expose protected variables or secrets from job logs. Do not retry, cancel, or trigger pipelines unless the task and role authorize that state change.

## REST Fallback

If `glab` is unavailable, use GitLab API v4 with the configured host and token. URL-encode the full namespace/project path, including subgroups.

```bash
GITLAB_API="${GITLAB_HOST:-https://gitlab.com}"
GITLAB_API="${GITLAB_API%/}/api/v4"
REMOTE_URL="$(git remote get-url origin)"
case "$REMOTE_URL" in
  *://*) REMOTE_PATH="${REMOTE_URL#*://}"; PROJECT_PATH="${REMOTE_PATH#*/}" ;;
  *:*) PROJECT_PATH="${REMOTE_URL#*:}" ;;
  *) PROJECT_PATH="$REMOTE_URL" ;;
esac
PROJECT_PATH="${PROJECT_PATH#/}"
PROJECT_PATH="${PROJECT_PATH%.git}"
# GitLab namespace/project paths use URL-safe slug characters; only the path
# separators need escaping for the API's :id segment.
PROJECT_ID="${PROJECT_PATH//\//%2F}"

curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_API/projects/$PROJECT_ID"
```

Useful endpoints:

- `GET /projects/:id/issues`
- `POST /projects/:id/issues`
- `POST /projects/:id/issues/:issue_iid/notes`
- `GET /projects/:id/merge_requests`
- `POST /projects/:id/merge_requests`
- `POST /projects/:id/merge_requests/:mr_iid/notes`
- `GET /projects/:id/pipelines?ref=<branch>`

Build JSON bodies with a JSON-aware tool; do not interpolate untrusted issue text directly into shell-quoted JSON.

## Completion Evidence

A GitLab-backed handoff should include:

- GitLab project and issue link.
- Branch and commit SHA.
- Merge request link and current state.
- Pipeline ID/status and relevant validation.
- Review or testing evidence.
- Known risks and unresolved discussions.
- Hermes Kanban task link.
