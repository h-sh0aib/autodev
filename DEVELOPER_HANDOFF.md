# Developer Handoff

This file is for the next developer maintaining or extending the Hermes autonomous development team package and setup wizard.

## Goal

This repo packages a reusable Hermes autonomous software development team for local Linux, WSL2, and remote Linux/SSH hosts. One installation can be reused across many project repos.

The intended client-facing install flow is:

```bash
git clone <package-repository-url> hermes-autonomous-dev-team
cd hermes-autonomous-dev-team
bash ./wizard.sh
```

The package should remain project-neutral. Do not add client names, trial project state, real credentials, hard-coded owner contact details, or app-specific assumptions.

## Repo Layout

- `wizard.sh`: client-facing setup wizard entrypoint.
- `scripts/setup-wizard.sh`: main interactive/non-interactive wizard implementation.
- `install.sh`: lower-level profile installer entrypoint.
- `scripts/install-team.sh`: installs/updates Hermes profiles and the common watchdog helper.
- `scripts/setup-project.sh`: per-project bootstrap; creates board, project watchdog wrapper, cron jobs, kickoff task.
- `scripts/hermes_autodev_watchdog_common.sh`: shared watchdog script copied into `~/.hermes/scripts/`.
- `autodev.sh` / installed `hermes-autodev`: unified setup, project, GUI, gateway, doctor, update, and uninstall command router.
- `dashboard.sh` / `scripts/dashboard.sh`: loopback-only local/SSH GUI manager.
- `scripts/gateway.sh`: native-service gateway manager with guarded fallback.
- `update.sh`, `uninstall.sh`, and `scripts/backup-runtime.sh`: guarded lifecycle and recovery commands.
- `scripts/doctor.sh`: host/profile/repository/service/GUI health check.
- `run-pm-gateway.sh`: foreground gateway fallback for hosts where `gateway start` cannot use user systemd.
- `setup.example.env`: config-file template for non-interactive/client installs.
- `templates/`: PM sweep and kickoff task prompt templates.
- `project-manager/`, `frontend-designer/`, `developer/`, `tester/`, `security-tester/`: Hermes profile distributions.
- `docs/hermes-docs-cross-reference.md`: why the package uses Hermes profiles, Kanban, cron, and gateway this way.
- `docs/setup-and-lifecycle-audit.md`: audit findings, supported-host matrix, and remaining boundaries.
- `docs/security-testing.md`: Security Tester standards, authorization scope, workflow, optional tooling, evidence handling, and release gate.
- `tests/smoke-lifecycle.sh`: isolated install/rerun/GitLab/bootstrap/uninstall regression test.

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
~/.hermes/profiles/security-tester
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

`bash ./wizard.sh` wraps `scripts/setup-wizard.sh` without depending on archive
executable bits.

Interactive mode:

```bash
bash ./wizard.sh
```

Non-interactive mode:

```bash
cp setup.example.env client.env
bash ./wizard.sh --config client.env --non-interactive
```

Useful flags:

```bash
hermes-autodev setup --skip-install
hermes-autodev setup --skip-project
hermes-autodev setup --no-force
hermes-autodev setup --log-file /path/to/setup.log
hermes-autodev setup --no-log
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
~/.hermes/profiles/security-tester/.env
```

Current main env keys:

- `OPENROUTER_API_KEY`: OpenRouter-backed Hermes models.
- `ANTHROPIC_API_KEY`: optional API-billed Anthropic provider; blank when using Anthropic OAuth.
- `GITHUB_TOKEN`: GitHub issues/pull requests/CI integration.
- `GITLAB_TOKEN`, `GITLAB_HOST`: GitLab issues/merge requests/pipelines, including self-managed GitLab.
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

The source distributions retain their OpenRouter defaults, including `moonshotai/kimi-k3` for Security Tester. The wizard rewrites installed model blocks when the operator selects OpenRouter, `openai-codex`, or Anthropic and lets Security Tester use a separate model ID. Its `security-testing` skill pins the reproducible OWASP/NIST baseline and report-only safety boundaries. Keep source-default changes explicit and update profile versions and user documentation when changing them.

Subscription credentials are per-profile Hermes auth state, not env-file values. `scripts/setup-wizard.sh` runs `hermes -p <profile> auth add openai-codex` or `hermes -p <profile> auth add anthropic --type oauth` for all five profiles when requested. The Developer's Codex CLI login remains a separate authentication concern.

Developer also has a source `bin/codex-network-exec`, but Hermes reserves profile-level `bin/` as runtime-owned. `scripts/install-team.sh` copies that launcher explicitly after installing the profile.

The `distribution.yaml` `distribution_owned` list controls package-owned files. Runtime secrets and sessions should remain untouched by profile updates.

The live Frontend Designer may contain Hermes's full auto-bundled skill catalog. Do not copy that catalog wholesale into this repo; its source distribution intentionally keeps only the Kanban worker and native MCP guidance it needs.
Apply the same curation principle to Security Tester: retain its team-owned security methodology and do not mirror runtime caches, downloaded scanners, scan databases, or generated evidence into this package.

Refresh installed profiles from the package:

```bash
bash ./install.sh -y
```

Client-friendly refresh:

```bash
hermes-autodev setup --skip-project
```

## Project Bootstrap Flow

Per-project setup is in `scripts/setup-project.sh`.

It creates or updates:

- First-class Hermes Project with the repository as primary folder and the
  matching Kanban board bound for GUI/Desktop session grouping.
- Hermes Kanban board.
- Board default workdir.
- `~/.hermes/autodev/projects/<slug>.env`.
- Detected/selected SCM provider and origin URL in that project env file.
- `~/.hermes/scripts/autodev_watchdog_<slug>.sh`.
- No-agent watchdog cron job.
- Agent PM sweep cron job.
- Idempotent kickoff task.

The wizard calls `setup-project.sh` when project bootstrap is enabled.

Cron/watchdog jobs do not run unless the Project Manager gateway is running. Use the portable manager:

```bash
hermes-autodev gateway start
hermes-autodev gateway status
```

It tries Hermes' managed service first and then a guarded detached fallback.
The fallback survives an ordinary SSH connection loss, but logind policy may
still end it and it does not restart after reboot; use a host/container
supervisor if a systemd user service is unavailable and persistence is required.

## External Things The Wizard Cannot Fully Automate

The wizard can collect and place credentials, but clients still need to create or provide:

- The selected model-provider account, subscription, or API billing. Browser/device OAuth still needs an interactive operator.
- GitHub and/or GitLab token with the project permissions the team needs.
- `gh` for the complete GitHub workflow and `glab` for the complete GitLab workflow.
- Telegram bot token and allowed user IDs.
- SSH key authorization on GitHub/GitLab if using private SSH repos.
- Billing/account setup for providers.
- Lovable OAuth access if the Frontend Designer workflow will be used.
- Browser-based `codex login` if not using `OPENAI_API_KEY`.
- Any optional security scanners desired on that VPS. The package deliberately does not install global scanner binaries.

For non-technical clients, prefer an existing `codex login` or `OPENAI_API_KEY` for the Developer lane and HTTPS Git remotes with the appropriate GitHub/GitLab token unless SSH has been preconfigured.

## Updating The Sold Package

After changing profiles, skills, docs, scripts, or wizard behavior:

```bash
cd /root/hermes-autonomous-dev-team
bash -n install.sh wizard.sh run-pm-gateway.sh scripts/*.sh
python3 -c "import yaml, pathlib; [yaml.safe_load(p.read_text()) for p in list(pathlib.Path('.').glob('*/config.yaml'))+list(pathlib.Path('.').glob('*/distribution.yaml'))]; print('yaml ok')"
python3 -c "import yaml, pathlib; [yaml.safe_load(p.read_text())['model'] for p in pathlib.Path('.').glob('*/config.yaml')]; print('model blocks ok')"
rg -n "${CLIENT_SECRET_SCAN_PATTERN:?set this to known client names, paths, and contact markers}" . -g '!*.git/**'
git status --short
git diff
git add .
git commit -m "update autonomous dev team package"
git push
```

On an installed host:

```bash
hermes-autodev update
```

If project cron templates changed and existing projects should receive the new prompt/script names, rerun:

```bash
./scripts/setup-project.sh --project-path /absolute/path/to/repo --project-slug <slug> --cron
```

`setup-project.sh` updates/resumes jobs by name instead of creating duplicates.

## Validation Checklist

Before handing off a build:

```bash
bash -n autodev.sh install.sh wizard.sh dashboard.sh update.sh uninstall.sh run-pm-gateway.sh scripts/*.sh scripts/lib/*.sh tests/*.sh
python3 -c "import yaml, pathlib; [yaml.safe_load(p.read_text()) for p in list(pathlib.Path('.').glob('*/config.yaml'))+list(pathlib.Path('.').glob('*/distribution.yaml'))]; print('yaml ok')"
python3 -c "import yaml, pathlib; [yaml.safe_load(p.read_text())['model'] for p in pathlib.Path('.').glob('*/config.yaml')]; print('model blocks ok')"
hermes-autodev setup --help
hermes-autodev install --help
./scripts/setup-project.sh --help
./tests/smoke-lifecycle.sh
hermes-autodev doctor
hermes-autodev update --check
hermes-autodev uninstall --dry-run
```

Safe non-interactive wizard smoke test:

```bash
bash ./wizard.sh --config setup.example.env --non-interactive --skip-install --skip-project
```

Do not run a live project bootstrap test against a client project unless you intend to create or update Hermes board/cron runtime state.

## Current Design Decisions

- One reusable profile team per VPS.
- One Kanban board per project/workstream.
- PM is the only owner-facing gateway profile by default.
- Frontend Designer is optional per task, uses Lovable only for high-value UI guidance, and must stay within its explicit credit budget.
- Developer must route implementation through Codex.
- Tester is report-only and validates through Playwright/browser behavior.
- Security Tester uses the setup-selected provider/model, is source-aware but report-only, requires exact authorization for dynamic targets, and gates confirmed critical/high findings through Developer remediation and independent retesting.
- Repository-host behavior is selected from each project's origin: `gh`/pull requests on GitHub, `glab`/merge requests on GitLab, and local Git plus Kanban for generic hosts.
- Watchdog cron uses `--no-agent`; PM sweep cron uses script output plus an agent prompt.
- Runtime project setup is separate from package installation so multiple projects can share the same team.

## Common Pitfalls

- Forgetting to update `setup.example.env` after adding wizard variables.
- Adding env keys to `.env.EXAMPLE` but not writing them in `write_profile_env`.
- Hard-coding `/root`, a phone number, repo path, board slug, or client name into profile instructions.
- Editing installed profiles under `~/.hermes` and forgetting to copy package-owned changes back into this repo.
- Copying auto-bundled runtime skills into a source distribution instead of retaining its curated skill set.
- Giving Security Tester a production URL without exact written scope, rate limits, test identities/data, exclusions, window, and stop conditions.
- Exposing the dashboard on `0.0.0.0` instead of preserving loopback + SSH/VPN access.
- Assuming PID fallbacks survive reboot; only a real host/container supervisor provides that guarantee.
- Committing `client.env` or real `.env` files.
- Treating old runtime logs/sessions on a trial VPS as package content.

## Package Repository Remote Status

This repo tracks an `origin/main` remote. Verify the current destination before publishing:

```bash
git remote -v
```

To publish committed updates:

```bash
git push origin main
```
