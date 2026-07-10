# Developer Handoff

This file is for the next developer maintaining or extending the Hermes autonomous development team package and setup wizard.

## Goal

This repo packages a reusable Hermes autonomous software development team that can be installed on a VPS and reused across many project repos.

The intended client-facing install flow is:

```bash
git clone git@github.com:<org>/<repo>.git hermes-autonomous-dev-team
cd hermes-autonomous-dev-team
./wizard.sh
```

The package should remain project-neutral. Do not add client names, trial project state, real credentials, hard-coded owner contact details, or app-specific assumptions.

## Repo Layout

- `wizard.sh`: client-facing setup wizard entrypoint.
- `scripts/setup-wizard.sh`: main interactive/non-interactive wizard implementation.
- `install.sh`: lower-level profile installer entrypoint.
- `scripts/install-team.sh`: installs/updates Hermes profiles and the common watchdog helper.
- `scripts/setup-project.sh`: per-project bootstrap; creates board, project watchdog wrapper, cron jobs, kickoff task.
- `scripts/hermes_autodev_watchdog_common.sh`: shared watchdog script copied into `~/.hermes/scripts/`.
- `scripts/doctor.sh`: runtime health check.
- `run-pm-gateway.sh`: foreground gateway fallback for hosts where `gateway start` cannot use user systemd.
- `setup.example.env`: config-file template for non-interactive/client installs.
- `templates/`: PM sweep and kickoff task prompt templates.
- `project-manager/`, `frontend-designer/`, `developer/`, `tester/`: Hermes profile distributions.
- `docs/hermes-docs-cross-reference.md`: why the package uses Hermes profiles, Kanban, cron, and gateway this way.

## Source vs Runtime

Source package:

```bash
hermes-autonomous-dev-team/
```

Runtime state:

```bash
~/.hermes/profiles/project-manager
~/.hermes/profiles/frontend-designer
~/.hermes/profiles/developer
~/.hermes/profiles/tester
~/.hermes/autodev/projects/
~/.hermes/autodev/logs/
~/.hermes/scripts/
```

Commit package files only. Do not commit runtime `.env`, auth files, sessions, logs, state databases, client project repos, Kanban runtime state, or client config files.

Ignored secret/config files include:

```bash
client.env
setup.local.env
*.secrets.env
```

## Wizard Behavior

`./wizard.sh` wraps `scripts/setup-wizard.sh`.

Interactive mode:

```bash
./wizard.sh
```

Non-interactive mode:

```bash
cp setup.example.env client.env
./wizard.sh --config client.env --non-interactive
```

Useful flags:

```bash
./wizard.sh --skip-install
./wizard.sh --skip-project
./wizard.sh --no-force
./wizard.sh --log-file /path/to/setup.log
./wizard.sh --no-log
```

The wizard writes logs by default:

```bash
~/.hermes/autodev/logs/setup-wizard-YYYYMMDDTHHMMSSZ.log
```

Logs are `0600`. They are meant for support, but still treat them as sensitive because external tool output can leak environment details.

## Profile Env Flow

The wizard gathers shared values once and writes the right subset into:

```bash
~/.hermes/profiles/project-manager/.env
~/.hermes/profiles/frontend-designer/.env
~/.hermes/profiles/developer/.env
~/.hermes/profiles/tester/.env
```

Current main env keys:

- `OPENROUTER_API_KEY`: Hermes model provider key.
- `GITHUB_TOKEN`: GitHub issues/PRs/CI integration.
- `OPENAI_API_KEY`: Codex on headless VPSes.
- `CODEX_HOME`: optional Codex auth/config override; blank means `~/.codex`.
- `TELEGRAM_BOT_TOKEN`: PM gateway Telegram bot token.
- `TELEGRAM_ALLOWED_USERS`: allowed Telegram numeric user IDs.
- `SIGNAL_HTTP_URL`, `SIGNAL_ACCOUNT`, `SIGNAL_ALLOWED_USERS`: optional Signal bridge config.
- `HERMES_LOG_LLM_OUTPUTS`, `HERMES_LLM_OUTPUT_LOG_MAX_CHARS`: optional LLM output logging knobs.

When adding/changing an env key, update all relevant places:

1. The profile `.env.EXAMPLE`.
2. The profile `distribution.yaml` `env_requires`.
3. `setup.example.env`.
4. `scripts/setup-wizard.sh` prompts/default loading.
5. `scripts/setup-wizard.sh` `write_profile_env` calls.
6. README/NEXT_STEPS if the key is user-facing.

## Profile Distribution Rules

Each profile distribution should include:

- `SOUL.md`
- `config.yaml`
- `distribution.yaml`
- `.env.EXAMPLE`
- `skills/`

Developer also has a source `bin/codex-network-exec`, but Hermes reserves profile-level `bin/` as runtime-owned. `scripts/install-team.sh` copies that launcher explicitly after installing the profile.

The `distribution.yaml` `distribution_owned` list controls package-owned files. Runtime secrets and sessions should remain untouched by profile updates.

The live Frontend Designer may contain Hermes's full auto-bundled skill catalog. Do not copy that catalog wholesale into this repo; its source distribution intentionally keeps only the Kanban worker and native MCP guidance it needs.

Refresh installed profiles from the package:

```bash
./install.sh -y --force
```

Client-friendly refresh:

```bash
./wizard.sh --skip-project
```

## Project Bootstrap Flow

Per-project setup is in `scripts/setup-project.sh`.

It creates or updates:

- Hermes Kanban board.
- Board default workdir.
- `~/.hermes/autodev/projects/<slug>.env`.
- `~/.hermes/scripts/autodev_watchdog_<slug>.sh`.
- No-agent watchdog cron job.
- Agent PM sweep cron job.
- Idempotent kickoff task.

The wizard calls `setup-project.sh` when project bootstrap is enabled.

Cron/watchdog jobs do not run unless the Project Manager gateway is running. `setup-project.sh --start-gateway` tries:

```bash
hermes -p project-manager gateway start
```

If that fails on VPS/container hosts without user systemd, tell clients to run:

```bash
./run-pm-gateway.sh
```

For production client installs, consider adding a system service wrapper later so the fallback gateway starts on boot.

## External Things The Wizard Cannot Fully Automate

The wizard can collect and place credentials, but clients still need to create or provide:

- OpenRouter/OpenAI API key.
- GitHub token.
- Telegram bot token and allowed user IDs.
- SSH key authorization on GitHub/GitLab if using private SSH repos.
- Billing/account setup for providers.
- Lovable OAuth access if the Frontend Designer workflow will be used.
- Browser-based `codex login` if not using `OPENAI_API_KEY`.

For non-technical clients, prefer `OPENAI_API_KEY` for Codex and HTTPS Git remotes with `GITHUB_TOKEN` unless SSH has been preconfigured.

## Updating The Sold Package

After changing profiles, skills, docs, scripts, or wizard behavior:

```bash
cd /root/hermes-autonomous-dev-team
bash -n install.sh wizard.sh run-pm-gateway.sh scripts/*.sh
python3 -c "import yaml, pathlib; [yaml.safe_load(p.read_text()) for p in list(pathlib.Path('.').glob('*/config.yaml'))+list(pathlib.Path('.').glob('*/distribution.yaml'))]; print('yaml ok')"
rg -n "${CLIENT_SECRET_SCAN_PATTERN:?set this to known client names, paths, and contact markers}" . -g '!*.git/**'
git status --short
git diff
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

If project cron templates changed and existing projects should receive the new prompt/script names, rerun:

```bash
./scripts/setup-project.sh --project-path /absolute/path/to/repo --project-slug <slug> --cron
```

`setup-project.sh` updates/resumes jobs by name instead of creating duplicates.

## Validation Checklist

Before handing off a build:

```bash
bash -n install.sh wizard.sh run-pm-gateway.sh scripts/*.sh
python3 -c "import yaml, pathlib; [yaml.safe_load(p.read_text()) for p in list(pathlib.Path('.').glob('*/config.yaml'))+list(pathlib.Path('.').glob('*/distribution.yaml'))]; print('yaml ok')"
./wizard.sh --help
./install.sh --help
./scripts/setup-project.sh --help
./scripts/doctor.sh
```

Safe non-interactive wizard smoke test:

```bash
./wizard.sh --config setup.example.env --non-interactive --skip-install --skip-project
```

Do not run a live project bootstrap test against a client project unless you intend to create or update Hermes board/cron runtime state.

## Current Design Decisions

- One reusable profile team per VPS.
- One Kanban board per project/workstream.
- PM is the only owner-facing gateway profile by default.
- Frontend Designer is optional per task, uses Lovable only for high-value UI guidance, and must stay within its explicit credit budget.
- Developer must route implementation through Codex.
- Tester is report-only and validates through Playwright/browser behavior.
- Watchdog cron uses `--no-agent`; PM sweep cron uses script output plus an agent prompt.
- Runtime project setup is separate from package installation so multiple projects can share the same team.

## Common Pitfalls

- Forgetting to update `setup.example.env` after adding wizard variables.
- Adding env keys to `.env.EXAMPLE` but not writing them in `write_profile_env`.
- Hard-coding `/root`, a phone number, repo path, board slug, or client name into profile instructions.
- Editing installed profiles under `~/.hermes` and forgetting to copy package-owned changes back into this repo.
- Copying auto-bundled runtime skills into a source distribution instead of retaining its curated skill set.
- Assuming `gateway start` works on every VPS; keep `run-pm-gateway.sh` documented.
- Committing `client.env` or real `.env` files.
- Treating old runtime logs/sessions on a trial VPS as package content.

## GitHub Remote Status

This repo tracks an `origin/main` remote. Verify the current destination before publishing:

```bash
git remote -v
```

To publish committed updates:

```bash
git push origin main
```
