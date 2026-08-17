# Hermes Docs Cross-Reference

This package was shaped around the Hermes documentation and CLI behavior below.

## Installation

Hermes official quick install:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

The package downloads that script to a temporary file before executing it. It is used when Hermes is missing or when an unsupported Hermes release cannot update itself. The package requires Hermes Agent `0.20.0` or newer, first published as [release tag v2026.8.3](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.3), so the GUI relies on the current fail-closed dashboard authentication and unified machine-level lifecycle. Hermes reports the package version (for example, `0.20.2`) from `hermes --version`; the calendar-based value is the Git release tag and must not be used for CLI version comparisons or `hermes_requires`.

## Profile Distributions

Referenced docs:

- `website/docs/user-guide/profile-distributions.md`
- `website/docs/reference/profile-commands.md`
- CLI: `hermes profile install --help`
- CLI: `hermes profile update --help`

Package decisions:

- Ship each role as a profile distribution directory.
- Include `SOUL.md`, `config.yaml`, `distribution.yaml`, `.env.EXAMPLE`, and `skills/`.
- Keep Developer's `codex-network-exec` in the source package and copy it explicitly from `install.sh`; Hermes reserves profile-level `bin/` as runtime-owned and does not copy it from distributions.
- Configure Frontend Designer's Lovable integration as a remote OAuth MCP server with a restricted tool allowlist.
- Keep OpenRouter defaults in source distributions, then let the setup wizard rewrite installed profile model blocks for OpenRouter, `openai-codex`, or Anthropic. Security Tester may use a separately selected model.
- Package Security Tester's security methodology skill and keep runtime scanner artifacts outside the distribution.
- Use `distribution_owned` so profile update/install has a clear set of package-owned files.
- Keep runtime `.env`, auth, sessions, logs, caches, `state.db`, and project state out of Git.
- Use `hermes profile update` for normal refreshes so local `config.yaml`, `.env`, auth, sessions, and memories remain untouched. Reserve forced config replacement for an explicit operator repair/reset.

Install commands used by `install.sh`:

```bash
hermes profile install ./project-manager --name project-manager --alias
hermes profile install ./frontend-designer --name frontend-designer --alias
hermes profile install ./developer --name developer --alias
hermes profile install ./tester --name tester --alias
hermes profile install ./security-tester --name security-tester --alias
```

## Model Providers And Subscription Authentication

Referenced docs:

- [Hermes model providers](https://hermes-agent.nousresearch.com/docs/integrations/providers)
- [OpenAI Codex authentication](https://learn.chatgpt.com/docs/auth)
- CLI: `hermes auth add --help`

Package decisions:

- Offer OpenRouter API-key configuration, OpenAI Codex/ChatGPT OAuth, Anthropic API-key configuration, and Anthropic OAuth in the wizard.
- Run subscription auth separately for all five profiles because Hermes stores provider credentials per profile.
- Keep Developer Codex CLI authentication separate from the Hermes orchestration provider.
- Do not put OAuth tokens in `setup.example.env` or profile distributions.
- Preserve existing installed model blocks when the operator selects `keep`.

## GitLab Repository Hosting

Referenced docs:

- [GitLab CLI authentication](https://docs.gitlab.com/cli/auth/login/)
- [GitLab CLI merge requests](https://docs.gitlab.com/cli/mr/)
- [GitLab CLI CI/CD commands](https://docs.gitlab.com/cli/ci/)

Package decisions:

- Detect GitLab.com and conventional self-managed remotes from `origin`, with
  an explicit `gitlab` override for custom hostnames.
- Store `GITLAB_HOST` and `GITLAB_TOKEN` only in owner-scoped profile env files.
- Prefer `glab` for issues, merge requests, reviews, and pipelines, with a
  GitLab REST API v4 fallback when the CLI is unavailable.
- Keep GitHub and GitLab command paths separate so `gh` is never used against a
  GitLab remote and `glab` is never used against GitHub.

## Kanban

Referenced docs:

- `website/docs/user-guide/features/kanban.md`
- CLI: `hermes kanban --help`
- CLI: `hermes kanban boards create --help`
- CLI: `hermes kanban create --help`

Package decisions:

- Use one Kanban board per project/workstream.
- Set each board's default workdir to that project repo.
- Create an idempotent kickoff task with `--idempotency-key`.
- Assign PM/Frontend Designer/Developer/Tester/Security Tester tasks to the reusable profile names.
- Let the Hermes gateway dispatcher run workers.

Project bootstrap commands use this shape:

```bash
hermes -p project-manager kanban boards create <slug> \
  --name "<Project Name>" \
  --description "<Description>" \
  --default-workdir /absolute/path/to/repo \
  --switch

hermes -p project-manager kanban --board <slug> create \
  "Initialize autonomous development workstream" \
  --assignee project-manager \
  --workspace dir:/absolute/path/to/repo \
  --idempotency-key autodev:<slug>:kickoff
```

## First-Class Projects

Referenced CLI: `hermes project <create|show|add-folder|use|bind-board>`.

Project bootstrap also creates a Hermes Project in the Project Manager
profile, sets the repository as its primary folder, and binds the matching
Kanban board. This is distinct from the package's private project env file:
Hermes Projects drive browser/Desktop session grouping and deterministic
Kanban worktrees, while the env file supplies the watchdog's repository and SCM
context. Re-running setup refreshes the folder/board binding without creating a
duplicate project.

## Cron

Referenced docs:

- `website/docs/user-guide/features/cron.md`
- CLI: `hermes cron create --help`
- CLI: `hermes cron edit --help`
- CLI: `hermes cron resume --help`
- CLI: `hermes cron list --help`

Package decisions:

- Create a no-agent watchdog job for cheap status checks and dispatch passes.
- Create an agent PM sweep job that receives watchdog script output in its prompt.
- Use `--workdir` so project context files are injected.
- Invoke cron commands through `hermes -p project-manager` so jobs are created
  in the Project Manager profile that owns the scheduler. Current Hermes cron
  subcommands no longer accept the former job-level `--profile` option.
- Resolve existing jobs by name and update/resume them to avoid duplicate cron jobs.

The two cron job patterns:

```bash
hermes -p project-manager cron create "every 5m" \
  --name "<Project> autodev watchdog" \
  --deliver local \
  --script autodev_watchdog_<slug>.sh \
  --no-agent \
  --workdir /absolute/path/to/repo

hermes -p project-manager cron create "every 5m" "<PM sweep prompt>" \
  --name "<Project> autonomous PM sweep" \
  --deliver local \
  --skill codex \
  --skill kanban-codex-lane \
  --script autodev_watchdog_<slug>.sh \
  --workdir /absolute/path/to/repo
```

## Gateway And Messaging

Referenced docs:

- `website/docs/user-guide/messaging/index.md`
- Multi-profile gateway docs under the Hermes website docs tree
- CLI: `hermes -p project-manager gateway status`
- CLI: `project-manager gateway start`

Package decisions:

- Expose only `project-manager` to owner-facing chat by default.
- Keep Frontend Designer, Developer, Tester, and Security Tester behind Kanban and the configured repository host.
- Use the package gateway manager, which tries Hermes' managed `gateway start` first.
- Run `run-pm-gateway.sh` under an owner PID/log manager when a user service is unavailable.
- Rely on the PM gateway to run scheduler and Kanban dispatcher behavior.

## Web Dashboard And Remote Access

Referenced docs:

- [Hermes web dashboard](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard)
- CLI: `hermes dashboard --help`

Package decisions:

- Use the machine-level Hermes dashboard as the team GUI. Its profile switcher scopes Config, API Keys, Skills, MCP, Models, and Chat; Kanban and Cron provide the work-management views.
- Install the Hermes `web` and `pty` extras when required so browser chat is present.
- Bind only to `127.0.0.1`. Local users open it directly; remote users forward the loopback port through SSH.
- Offer a systemd user unit for persistence, with a guarded background fallback on hosts without a working user bus.
- Never silently choose `0.0.0.0` or weaken the dashboard authentication gate.

## Updating, Backup, And Uninstall

Referenced docs:

- [Hermes updating and uninstalling](https://hermes-agent.nousresearch.com/docs/getting-started/updating)
- CLI: `hermes update --help`, `hermes backup --help`, `hermes uninstall --help`

Package decisions:

- Use `hermes update --backup --yes` instead of modifying Hermes' managed checkout directly.
- Keep package lifecycle backups outside `~/.hermes` so a full Hermes uninstall cannot remove the recovery artifact.
- Remove profiles through `hermes profile delete`. A full external backup is
  created first because profile deletion permanently removes that profile's
  projects, boards, sessions, auth, and cron data.
- Keep package removal separate from optional Hermes removal because the Hermes installation can serve unrelated profiles.

## Reusable Project Model

The package intentionally does not ship trial project progress, old Kanban data, runtime cron state, or repo-specific files. For each new project, run:

```bash
./scripts/setup-project.sh --project-path /absolute/path/to/repo --project-slug <slug> --scm-provider auto --cron --start-gateway
```

That creates runtime state for the project while keeping the package itself generic. `auto` detects GitHub or GitLab from `origin`; an explicit `github`, `gitlab`, or `generic` value is available for ambiguous or not-yet-cloned projects. The installed role skills use `gh` for GitHub and `glab` for GitLab, including issues, pull/merge requests, reviews, and CI/pipeline status.

## Security Testing

See [security-testing.md](security-testing.md) for Security Tester model selection, pinned standards, authorized-scope requirements, report-only boundaries, optional tools, workflow, evidence handling, and release recommendation rules.
