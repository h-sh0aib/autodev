---
name: kanban-codex-lane
description: Use when a Hermes Kanban worker must route implementation, debugging, refactoring, tests, or code-aware documentation through Codex CLI while Hermes keeps ownership of task lifecycle, monitoring, verification, and handoff.
version: 1.1.0
author: Hermes autonomous development team
license: Private
metadata:
  hermes:
    tags: [kanban, codex, autonomous-development, software-engineering]
    related_skills: [kanban-worker, codex]
---

# Kanban Codex Lane

## Purpose

This skill defines the Hermes plus Codex operating pattern for the autonomous development team.

Hermes owns the Kanban task lifecycle, task comments, heartbeats, blocker handling, GitHub coordination, final review, test evidence, and completion handoff. Codex owns code-aware work: architecture planning, source edits, debugging, refactoring, tests, build fixes, and code behavior documentation.

Codex output is not a task-completion signal by itself. Treat Codex results as an implementation artifact that still needs review, verification, and a Kanban handoff from the Hermes worker.

## Required Use

Use Codex for any task that changes or reasons deeply about source code, tests, build scripts, migrations, generated code, deployment config, or implementation behavior.

Do not use Codex for:

- Pure PM coordination.
- Pure Tester report writing.
- Reading Kanban/GitHub context.
- Posting comments, heartbeats, or handoffs.
- Human escalation.

Do not manually implement code changes as a fallback after a Codex failure. Repair the Codex invocation, narrow the prompt, feed exact failures back to Codex, or block with the concrete infrastructure issue.

## Default Invocation

Use the network-enabled wrapper installed with the Developer profile:

```bash
codex-network-exec /absolute/path/to/repo /absolute/path/to/prompt.md
```

If it is not on `PATH`, use the profile path:

```bash
~/.hermes/profiles/developer/bin/codex-network-exec /absolute/path/to/repo /absolute/path/to/prompt.md
```

This wrapper is the default because implementation often needs package registries, browser tooling, Git remotes, local servers, databases, or documentation access that can fail under a restricted Codex sandbox.

## Prompt Construction

Use `templates/autodev-codex-lane-prompt.md` as the base structure. Every Codex prompt must include:

- Kanban task id, title, body, and acceptance criteria.
- Repository path and intended branch or PR strategy.
- Product goal and observable user-facing behavior.
- Relevant project docs, existing decisions, and known constraints.
- Explicit instruction that Hermes owns Kanban and messaging.
- Allowed and forbidden areas of the repository.
- Required validation commands and expected evidence.
- A request for changed files, tests run, risks, and follow-up work.

Keep prompts specific enough that Codex can work without guessing, but do not hard-code project-specific assumptions in this reusable skill.

## Monitoring

For long-running Codex work:

- Post a Kanban heartbeat before launch with the prompt purpose and expected validation.
- Monitor Codex output periodically.
- Feed exact failures back to Codex rather than summarizing vaguely.
- Stop and block if Codex cannot authenticate, cannot access required dependencies, requests secrets, or repeatedly fails for the same infrastructure reason.
- Keep the Project Manager informed when the task is stale, blocked, or at risk.

## Review And Verification

Before accepting Codex output:

- Inspect `git status --short --branch`.
- Review changed files and diffs for scope, secrets, unrelated churn, and placeholder behavior.
- Run the repository's relevant validation commands.
- Confirm the work matches the Kanban acceptance criteria.
- Open or update the GitHub PR when code changed.
- Hand off to Tester for user-facing behavior.

Distinguish Codex-run validation from Hermes/Developer-run validation in handoffs.

## Completion Metadata

When completing or blocking a task that used Codex, include:

```json
{
  "codex_lane": {
    "used": true,
    "command": "codex-network-exec /repo /prompt.md",
    "result": "completed | partial | blocked | failed",
    "changed_files": ["path/example.ts"],
    "tests_run": [
      {"command": "npm test", "exit_code": 0, "owner": "codex-or-hermes"}
    ],
    "pr": "https://github.com/org/repo/pull/123",
    "risks": [],
    "blocker": ""
  }
}
```

If Codex was not used, explicitly state why. For Developer implementation work, "manual edit was faster" is not an acceptable reason.

## Common Pitfalls

- Starting implementation with `codex exec --full-auto` instead of the network-enabled wrapper.
- Accepting Codex self-report without reviewing diffs and running validation.
- Letting Codex call Hermes Kanban or messaging commands.
- Treating a restricted-sandbox network failure as permission to code manually.
- Omitting the real acceptance criteria from the prompt.
- Sending Tester defects back to Codex without exact reproduction steps and evidence.
