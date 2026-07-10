---
name: project-kickoff
description: Generic Project Manager workflow for starting a new software project after the autonomous dev team package has created the Hermes Kanban board, watchdog, and cron sweep.
version: 1.2.0
metadata:
  triggers:
    - A new project board has an "Initialize autonomous development workstream" task
    - User sends requirements documents, a repo URL, or a product brief
    - User says "new project", "fresh start", "kick off", or "start building"
  related_skills: [kanban-orchestrator, kanban-worker, kanban-codex-lane]
---

# Project Kickoff

Use this workflow as the `project-manager` profile when starting a new project. The reusable package handles installation, profile setup, board creation, watchdog scripts, and recurring PM cron. Your job is to convert the project brief into durable project context and a small number of high-quality Frontend Designer, Developer, and Tester tasks.

## 1. Confirm The Workstream

Before assigning work:

- Confirm the active Kanban board and repository path.
- Read the kickoff task body, repo README, existing `AGENTS.md`, and any supplied requirements.
- Check `hermes profile list` and confirm `project-manager`, `frontend-designer`, `developer`, and `tester` exist.
- Check `hermes kanban --board <board> stats` and `hermes cron list --all` to verify the board and autonomous checks are installed.
- Record any missing credentials, model-provider setup, GitHub auth, deployment accounts, or external provider dependencies as blockers.

Do not assume the project directory is clean. If an old project with the same name exists, archive rather than delete, and ask before destructive service or data changes.

## 2. Parse Requirements

If the user provided documents, parse them fully before planning. Preserve originals under the project's docs area when appropriate.

Capture:

- Product goal and target users.
- Must-have workflows and acceptance criteria.
- Non-functional requirements: security, performance, deployment, localization, accessibility, observability, and data retention.
- External integrations and credentials needed.
- Explicit exclusions or deferred features.
- Ambiguities that require owner input.

If requirements conflict, record the conflict and choose the most conservative production-safe interpretation until the owner clarifies.

## 3. Create Project Context

Ensure the project has durable context files for future agents. For existing repos, update rather than overwrite.

Recommended files:

- `AGENTS.md`: repo-specific instructions injected into Hermes/Codex work.
- `docs/ARCHITECTURE.md`: system shape, data model, boundaries, integrations.
- `docs/BUILD_SPEC.md`: scope, quality gates, risks, acceptance criteria.
- `docs/DECISIONS.md`: stack and product decisions.
- `PROGRESS.md`: high-level progress tracker and open blockers.
- `.env.example`: placeholders only, never real secrets.

The `AGENTS.md` is the most important file because it shapes every Developer and Tester run.

## 4. Route Work

Create one product-level Developer implementation task by default. Before it, create one Frontend Designer task only when a high-impact UI surface has real layout, hierarchy, or visual ambiguity. Split other work only when there is a real boundary:

- Independent modules can run safely in parallel.
- A credential or external dependency blocks only part of the work.
- The first Codex run failed and the work needs narrowing.
- Tester found a focused defect.

Frontend Designer task requirements, when design guidance is warranted:

- Assign to `frontend-designer` and make the Developer task depend on its handoff.
- Ask for one to three representative screens or states, not an exhaustive app design.
- Allow at most one Lovable `create_project` call and no follow-up `send_message` by default.
- Forbid repository writes, deployment, database enablement, SQL, and workspace-setting changes.
- Require project/preview URLs, screen inventory, design direction, implementation notes, accessibility/responsive guidance, and exact credit-consuming call counts.

Developer task requirements:

- Assign to `developer`.
- Use workspace `dir:<absolute-project-path>`.
- Include product goal, acceptance criteria, relevant docs, constraints, and validation commands.
- Include the Frontend Designer handoff when one exists.
- State clearly that all coding, debugging, tests, and docs about implementation must go through Codex using `codex-network-exec`.
- Require branch/PR/test evidence and a Codex usage summary.

Tester task requirements:

- Assign to `tester` only after there is a usable build, PR, or deployment target.
- Require Playwright/browser validation from a real user perspective.
- Forbid repo writes, dependency installs, source inspection, database inspection, and attempted fixes.
- Require screenshots/traces/reproduction steps and a pass/fail recommendation.

## 5. Monitor

The package's recurring watchdog and PM sweep should already exist for this project. Use them; do not rely on memory or promises to check later.

Useful commands:

```bash
hermes -p project-manager kanban --board <board> list
hermes -p project-manager kanban --board <board> stats
hermes -p project-manager kanban --board <board> dispatch --max 2
hermes -p project-manager cron list --all
hermes -p project-manager gateway status
```

If a worker is stale, crashed, looping, or blocked:

- Comment on the task with the exact status request.
- Check GitHub branches, commits, PRs, and CI for objective progress.
- Narrow the next Developer task if Codex needs a smaller target.
- Escalate to the owner only for credentials, billing, product direction, legal/business constraints, or destructive production actions.

## 6. Completion Gate

Do not mark project work ready until:

- Requested workflows are implemented through the real product surface.
- Relevant build/lint/typecheck/test commands pass.
- User-facing changes have Playwright evidence from Tester.
- Critical and high-severity defects are fixed and re-tested.
- External provider workflows are either proven through the real user path or recorded as release blockers.
- GitHub issues/PRs and Kanban tasks reflect the actual state.

## Pitfalls

- Do not create fake phased work when one product-level Codex task is enough.
- Do not let Tester debug or fix code.
- Do not accept seeded OTPs, console logs, or database lookups as proof of a real customer login path.
- Do not put secrets into Kanban, prompts, GitHub, or docs.
- Do not unblock auth/access failures without verifying the same failing command or a direct equivalent.
