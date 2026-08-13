---
name: codex
description: "Delegate coding and pull/merge request review to OpenAI Codex CLI."
version: 1.1.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Coding-Agent, Codex, OpenAI, Code-Review, Refactoring]
    related_skills: [claude-code, hermes-agent]
---

# Codex CLI

Delegate coding tasks to [Codex](https://github.com/openai/codex) via the Hermes terminal. Codex is OpenAI's autonomous coding agent CLI.

## When to use

- Building features
- Refactoring
- Pull/merge request reviews
- Batch issue fixing

Requires the codex CLI and a git repository.

## Prerequisites

- Codex installed: `npm install -g @openai/codex`
- OpenAI auth configured: either `OPENAI_API_KEY` or Codex OAuth credentials
  from the Codex CLI login flow
- **Must run inside a git repository** — Codex refuses to run outside one
- Use `pty=true` in terminal calls — Codex is an interactive terminal app

For Hermes itself, `model.provider: openai-codex` uses Hermes-managed Codex
OAuth from `~/.hermes/auth.json` after `hermes auth add openai-codex`. For the
standalone Codex CLI, a valid CLI OAuth session may live under
`~/.codex/auth.json`; do not treat a missing `OPENAI_API_KEY` alone as proof
that Codex auth is missing.

## Network-Enabled Implementation Tasks

For this autonomous development team, broad implementation work should use the
profile wrapper:

```
codex-network-exec /path/to/repo /path/to/prompt.md
```

The wrapper runs Codex with:

```
codex --ask-for-approval never exec --sandbox danger-full-access -C /path/to/repo - < /path/to/prompt.md
```

Use this wrapper for feature work, debugging, tests, builds, Prisma, Playwright,
package installs, repository-host operations, local servers, or anything that could need
network access. This avoids the restricted sandbox issue where Codex launches
with `network: restricted` / `--unshare-net` and cannot reach npm, databases,
browsers, GitHub/GitLab, or local services.

## One-Shot Tasks

```
terminal(command="codex-network-exec ~/project ~/project/.codex-prompts/task.md", workdir="~/project", pty=true)
```

For scratch work (Codex needs a git repo):
```
terminal(command="cd $(mktemp -d) && git init && codex exec 'Build a snake game in Python'", pty=true)
```

## Background Mode (Long Tasks)

```
# Start in background with PTY
terminal(command="codex-network-exec ~/project ~/project/.codex-prompts/task.md", workdir="~/project", background=true, pty=true)
# Returns session_id

# Monitor progress
process(action="poll", session_id="<id>")
process(action="log", session_id="<id>")

# Send input if Codex asks a question
process(action="submit", session_id="<id>", data="yes")

# Kill if needed
process(action="kill", session_id="<id>")
```

## Key Flags

| Flag | Effect |
|------|--------|
| `exec "prompt"` | One-shot execution, exits when done |
| `codex --ask-for-approval never exec --sandbox danger-full-access` | Current network-enabled, non-interactive invocation. Use through `codex-network-exec` for this team. The global approval flag must precede `exec`. |
| `--sandbox workspace-write` | Workspace sandbox that may still restrict network. Use only for small read-only/no-network tasks. |
| `--dangerously-bypass-approvals-and-sandbox` | No sandbox at all. Avoid unless the Project Manager explicitly approves a one-off recovery. |

## Pull And Merge Request Reviews

Detect the repository host, then clone to a temp directory for safe review. GitHub example:

```
terminal(command="REVIEW=$(mktemp -d) && git clone https://github.com/user/repo.git $REVIEW && cd $REVIEW && gh pr checkout 42 && codex review --base origin/main", pty=true)
```

GitLab example:

```
terminal(command="REVIEW=$(mktemp -d) && git clone https://gitlab.com/group/repo.git $REVIEW && cd $REVIEW && glab mr checkout 42 && codex review --base origin/main", pty=true)
```

## Parallel Issue Fixing with Worktrees

```
# Create worktrees
terminal(command="git worktree add -b fix/issue-78 /tmp/issue-78 main", workdir="~/project")
terminal(command="git worktree add -b fix/issue-99 /tmp/issue-99 main", workdir="~/project")

# Launch Codex in each
terminal(command="codex --yolo exec 'Fix issue #78: <description>. Commit when done.'", workdir="/tmp/issue-78", background=true, pty=true)
terminal(command="codex --yolo exec 'Fix issue #99: <description>. Commit when done.'", workdir="/tmp/issue-99", background=true, pty=true)

# Monitor
process(action="list")

# After completion, push and create the host-appropriate pull/merge request
terminal(command="cd /tmp/issue-78 && git push -u origin fix/issue-78")
terminal(command="gh pr create --repo user/repo --head fix/issue-78 --title 'fix: ...' --body '...'")
# On GitLab, use: glab mr create --source-branch fix/issue-78 --title 'fix: ...' --description '...' --yes

# Cleanup
terminal(command="git worktree remove /tmp/issue-78", workdir="~/project")
```

## Batch GitHub Pull Request Reviews

```
# Fetch all PR refs
terminal(command="git fetch origin '+refs/pull/*/head:refs/remotes/origin/pr/*'", workdir="~/project")

# Review multiple PRs in parallel
terminal(command="codex exec 'Review PR #86. git diff origin/main...origin/pr/86'", workdir="~/project", background=true, pty=true)
terminal(command="codex exec 'Review PR #87. git diff origin/main...origin/pr/87'", workdir="~/project", background=true, pty=true)

# Post results
terminal(command="gh pr comment 86 --body '<review>'", workdir="~/project")
```

These refspecs and `gh` commands are GitHub-specific. For GitLab, use `glab mr list`, `glab mr checkout`, and `glab mr note create` rather than GitHub pull refs.

## Rules

1. **Always use `pty=true`** — Codex is an interactive terminal app and hangs without a PTY
2. **Git repo required** — Codex won't run outside a git directory. Use `mktemp -d && git init` for scratch
3. **Use `exec` for one-shots** — `codex exec "prompt"` runs and exits cleanly
4. **Use `codex-network-exec` for building** — it prevents network-restricted sandbox failures
5. **Background for long tasks** — use `background=true` and monitor with `process` tool
6. **Don't interfere** — monitor with `poll`/`log`, be patient with long-running tasks
7. **Parallel is fine** — run multiple Codex processes at once for batch work
