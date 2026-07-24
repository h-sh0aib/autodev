# Hermes Docs Cross-Reference

This package was shaped around the Hermes documentation and CLI behavior below.

## Installation

Hermes official quick install:

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

The package installer uses this only when `hermes` is missing and `--no-install-hermes` was not passed.

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
- Configure Security Tester to use OpenRouter `moonshotai/kimi-k3`, package its security methodology skill, and keep runtime scanner artifacts outside the distribution.
- Use `distribution_owned` so profile update/install has a clear set of package-owned files.
- Keep runtime `.env`, auth, sessions, logs, caches, `state.db`, and project state out of Git.

Install commands used by `install.sh`:

```bash
hermes profile install ./project-manager --name project-manager --alias
hermes profile install ./frontend-designer --name frontend-designer --alias
hermes profile install ./developer --name developer --alias
hermes profile install ./tester --name tester --alias
hermes profile install ./security-tester --name security-tester --alias
```

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
- Use `--profile project-manager` so the scheduler runs under the PM profile.
- Resolve existing jobs by name and update/resume them to avoid duplicate cron jobs.

The two cron job patterns:

```bash
hermes -p project-manager cron create "every 5m" \
  --name "<Project> autodev watchdog" \
  --deliver local \
  --script autodev_watchdog_<slug>.sh \
  --no-agent \
  --workdir /absolute/path/to/repo \
  --profile project-manager

hermes -p project-manager cron create "every 5m" "<PM sweep prompt>" \
  --name "<Project> autonomous PM sweep" \
  --deliver local \
  --skill codex \
  --skill kanban-codex-lane \
  --script autodev_watchdog_<slug>.sh \
  --workdir /absolute/path/to/repo \
  --profile project-manager
```

## Gateway And Messaging

Referenced docs:

- `website/docs/user-guide/messaging/index.md`
- Multi-profile gateway docs under the Hermes website docs tree
- CLI: `hermes -p project-manager gateway status`
- CLI: `project-manager gateway start`

Package decisions:

- Expose only `project-manager` to owner-facing chat by default.
- Keep Frontend Designer, Developer, Tester, and Security Tester behind Kanban/GitHub.
- Use `gateway start` when the VPS supports user services.
- Provide `run-pm-gateway.sh` as a foreground fallback.
- Rely on the PM gateway to run scheduler and Kanban dispatcher behavior.

## Reusable Project Model

The package intentionally does not ship trial project progress, old Kanban data, runtime cron state, or repo-specific files. For each new project, run:

```bash
./scripts/setup-project.sh --project-path /absolute/path/to/repo --project-slug <slug> --cron --start-gateway
```

That creates runtime state for the project while keeping the package itself generic.

## Security Testing

See [security-testing.md](security-testing.md) for the Security Tester model, pinned standards, authorized-scope requirements, report-only boundaries, optional tools, workflow, evidence handling, and release recommendation rules.
