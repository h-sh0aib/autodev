# Hermes Autonomous Development Team

Reusable Hermes profile package for a four-agent autonomous software team:

- `project-manager`: owns planning, Kanban/GitHub coordination, monitoring, escalation, and status.
- `frontend-designer`: uses Lovable MCP sparingly to provide initial UI guidance for high-value screens.
- `developer`: delegates all implementation, debugging, architecture, tests, and code-aware docs to Codex.
- `tester`: validates user-facing behavior through Playwright and reports defects without editing the app.

The package is designed to be cloned onto a new VPS, installed once, and then reused across many project repositories. Project state lives in Hermes Kanban boards, GitHub, and each project repo; runtime secrets and sessions stay under `~/.hermes` and are not part of this package.

Maintainers taking over this package should start with [DEVELOPER_HANDOFF.md](DEVELOPER_HANDOFF.md).

## Client Setup Wizard

Recommended for non-technical VPS setup:

```bash
git clone git@github.com:<org>/<repo>.git hermes-autonomous-dev-team
cd hermes-autonomous-dev-team
./wizard.sh
```

The wizard handles:

- Hermes profile install/update.
- One-place credential entry for all profiles.
- Git user name/email.
- GitHub token placement and optional `gh` CLI login.
- Codex credential setup through `OPENAI_API_KEY`, `CODEX_HOME`, or existing `codex login`.
- Frontend Designer setup with a restricted Lovable MCP tool list and Free-plan credit guardrails.
- Telegram/Signal owner-channel settings for the PM gateway.
- Optional first-project board, watchdog, cron jobs, kickoff task, and gateway start.
- Timestamped setup logs under `~/.hermes/autodev/logs/`.

For a non-interactive client install, prepare a config file:

```bash
cp setup.example.env client.env
nano client.env
./wizard.sh --config client.env --non-interactive
```

Do not commit `client.env`; it contains secrets.

If setup fails, send the latest log from:

```bash
~/.hermes/autodev/logs/
```

The log captures installer, profile, project bootstrap, cron, gateway, and doctor output. Secret prompts are hidden, and log files are created with `0600` permissions.

## Lower-Level Install

For technical operators who only want to install/update profiles:

```bash
./install.sh -y
```

If Hermes is not installed, the installer uses the official Hermes installer:

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

The wizard or installer creates runtime env files at:

```bash
~/.hermes/profiles/project-manager/.env
~/.hermes/profiles/frontend-designer/.env
~/.hermes/profiles/developer/.env
~/.hermes/profiles/tester/.env
```

Minimum practical setup:

- `OPENROUTER_API_KEY` or another configured Hermes model provider for each profile.
- Lovable OAuth access if the optional Frontend Designer workflow will be used.
- Codex auth for the server account, usually `codex login` or `OPENAI_API_KEY`.
- `GITHUB_TOKEN` if the team should create issues, PRs, comments, or read CI.
- `TELEGRAM_BOT_TOKEN` and `TELEGRAM_ALLOWED_USERS` only if you want the PM gateway exposed through Telegram.

## Bootstrap A Project

For an existing Git repo:

```bash
./scripts/setup-project.sh \
  --project-path /absolute/path/to/project \
  --project-slug my-project \
  --project-name "My Project" \
  --cron \
  --start-gateway
```

For a repo that should be cloned first:

```bash
./install.sh -y \
  --repo-url git@github.com:org/app.git \
  --project-path /srv/app \
  --project-slug app \
  --cron \
  --start-gateway
```

The project setup script creates or updates:

- A Hermes Kanban board for the project.
- The board default workdir pointing at the repo.
- A project env file under `~/.hermes/autodev/projects/<slug>.env`.
- A project watchdog wrapper under `~/.hermes/scripts/`.
- A no-agent watchdog cron job.
- An agent PM sweep cron job.
- An idempotent kickoff task assigned to `project-manager`.

The wizard can run this same bootstrap as part of initial setup. For additional projects later:

```bash
./wizard.sh --skip-install
```

## Multiple Projects

Install the profiles once per VPS. Run `scripts/setup-project.sh` once per project repo.

Each project gets its own:

- Kanban board.
- Default workdir.
- Watchdog wrapper.
- Cron job names.
- Kickoff task.

The same `project-manager`, `frontend-designer`, `developer`, and `tester` profiles can work across multiple boards because Hermes cron and Kanban tasks carry the board/workdir context.

## Gateway

Preferred:

```bash
project-manager gateway start
```

Fallback for containers or VPS environments without a working user systemd bus:

```bash
./run-pm-gateway.sh
```

Only expose the `project-manager` profile through Telegram or other owner-facing chat gateways. Frontend Designer, Developer, and Tester should be driven by Kanban and GitHub, not direct chat.

## Health Check

```bash
./scripts/doctor.sh
./scripts/doctor.sh --project-slug my-project
```

Useful runtime commands:

```bash
hermes -p project-manager kanban --board my-project list
hermes -p project-manager kanban --board my-project stats
hermes -p project-manager cron list --all
hermes -p project-manager gateway status
```

## Updating A Sold Package

Make profile, skill, markdown, or script changes in this package repo, then:

```bash
git add .
git commit -m "update autonomous dev team package"
git push
```

On a client VPS:

```bash
cd hermes-autonomous-dev-team
git pull
./wizard.sh --skip-project
```

That refreshes package-owned profile files and lets the operator update shared credentials without touching profile folders manually. Existing runtime `.env`, auth files, sessions, logs, Kanban boards, and cron state are preserved unless the wizard intentionally updates env keys.

## Hermes Docs Cross-Reference

The package follows these Hermes-supported mechanisms:

- Profile distributions: `hermes profile install <source> --name <profile> --alias`, with `SOUL.md`, `config.yaml`, `distribution.yaml`, `.env.EXAMPLE`, and `skills/` packaged as profile-owned files. The team installer separately copies Developer's Codex launcher because Hermes reserves profile-level `bin/` as runtime-owned.
- MCP: Frontend Designer connects to Lovable over OAuth with only the inspection and tightly budgeted generation tools needed for design handoffs.
- Kanban: one board per project/workstream, created with `hermes kanban boards create ... --default-workdir ... --switch`; workers coordinate through `kanban_*` tools and the PM uses `hermes kanban` for scripts.
- Cron: recurring jobs are created with `hermes cron create`, using `--script --no-agent` for watchdog checks and script-plus-prompt agent jobs for PM sweeps.
- Gateway: `project-manager gateway start` runs the gateway, scheduler, and dispatcher; `gateway run` is the foreground fallback.
- Runtime separation: profile install/update should not commit `.env`, auth, sessions, logs, state databases, or project Kanban state into this package.

See [docs/hermes-docs-cross-reference.md](docs/hermes-docs-cross-reference.md) for the exact documentation and CLI references used.
