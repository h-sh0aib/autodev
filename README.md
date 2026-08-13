# Hermes Autonomous Development Team

Reusable Hermes profile package for a five-agent autonomous software team:

- `project-manager`: owns planning, Kanban/repository-host coordination, monitoring, escalation, and status.
- `frontend-designer`: uses Lovable MCP sparingly to provide initial UI guidance for high-value screens.
- `developer`: delegates all implementation, debugging, architecture, tests, and code-aware docs to Codex.
- `tester`: validates user-facing behavior through Playwright and reports defects without editing the app.
- `security-tester`: performs report-only, source-aware, risk-based application security assessment and remediation retesting with the model selected during setup.

The package runs on a local Linux computer, WSL2, or a Linux server reached over SSH, and can be reused across GitHub, GitLab, and generic Git repositories. Project state lives in Hermes Kanban boards, the repository host, and each project repo; runtime secrets and sessions stay under `~/.hermes` and are not part of this package.

Maintainers taking over this package should start with [DEVELOPER_HANDOFF.md](DEVELOPER_HANDOFF.md). The setup/product review and supported-host matrix are in [docs/setup-and-lifecycle-audit.md](docs/setup-and-lifecycle-audit.md).

## Quick Start

Use a dedicated, unprivileged Linux account. The host needs Git, curl, and xz; the wizard installs or updates Hermes itself.

```bash
git clone <this-package-repository-url> hermes-autonomous-dev-team
cd hermes-autonomous-dev-team
bash ./wizard.sh
```

The same command works in a local terminal and in an interactive SSH session. On SSH hosts the wizard configures the browser GUI on `127.0.0.1` and prints an SSH tunnel command—no web control plane is exposed publicly. Native macOS and Windows shells are not supported; use WSL2 on Windows or a Linux host from macOS.

The wizard handles:

- Safe Hermes/profile install or update that preserves existing config, auth, and runtime data by default.
- One-place model/provider and credential entry for all profiles.
- Hermes models through OpenRouter, a ChatGPT/Codex subscription (`openai-codex`), Anthropic API credentials, or supported Claude subscription OAuth.
- Git user name/email.
- GitHub and/or GitLab token placement, including optional `gh`/`glab` CLI login.
- Codex credential setup through `OPENAI_API_KEY`, `CODEX_HOME`, or existing `codex login`.
- Optional Codex CLI installation through OpenAI's official Linux installer.
- Frontend Designer setup with a restricted Lovable MCP tool list and Free-plan credit guardrails.
- A separately selectable Security Tester model with report-only authorization and evidence-handling guardrails.
- Telegram/Signal owner-channel settings for the PM gateway.
- Optional first-project board, watchdog, cron jobs, kickoff task, and gateway start.
- A complete browser GUI with profile switching, chat, Kanban, models, credentials, MCP/skills, and scheduled jobs.
- Local-browser or SSH-tunnel GUI access, with optional service-backed persistence.
- Timestamped setup logs under `~/.hermes/autodev/logs/`.

For a non-interactive client install, prepare a config file:

```bash
cp setup.example.env client.env
nano client.env
bash ./wizard.sh --config client.env --non-interactive
```

Do not commit `client.env`; it contains secrets.

If setup fails, send the latest log from:

```bash
~/.hermes/autodev/logs/
```

The log captures installer, profile, project bootstrap, cron, gateway, and doctor output. Secret prompts are hidden, and log files are created with `0600` permissions.

Running the wizard again is safe: it uses Hermes profile updates and does not reset existing profile settings unless `--force` is explicitly supplied.

## Lower-Level Install

For technical operators who only want to install/update profiles:

```bash
bash ./install.sh -y
```

If Hermes is not installed, the installer downloads the official installer to a temporary file, verifies the download succeeded, and then runs it with profile setup skipped:

```bash
https://hermes-agent.nousresearch.com/install.sh
```

The wizard or installer creates runtime env files at:

```bash
~/.hermes/profiles/project-manager/.env
~/.hermes/profiles/frontend-designer/.env
~/.hermes/profiles/developer/.env
~/.hermes/profiles/tester/.env
~/.hermes/profiles/security-tester/.env
```

If `HERMES_HOME` is customized, owner-only metadata in
`~/.config/hermes-autodev/install.env` remembers it, so the installed
`hermes-autodev` command continues to work from fresh shells without requiring
the variable to be exported again.

### Hermes model authentication

The wizard can apply one provider to every Hermes orchestration profile and optionally choose a different model ID for Security Tester:

- `openrouter`: API-billed access through `OPENROUTER_API_KEY`. The packaged defaults are `xiaomi/mimo-v2.5-pro` for the team and `moonshotai/kimi-k3` for Security Tester.
- `openai-codex`: sign in per Hermes profile with a ChatGPT account through Codex device-code OAuth. No OpenRouter key is required for these Hermes model calls. Model access depends on the account's live Codex catalog, and Hermes does not currently document which ChatGPT tiers qualify or exactly how plan quota is counted; the model ID remains editable in the wizard.
- `anthropic`: use `ANTHROPIC_API_KEY`, or let the wizard run Hermes's Anthropic OAuth flow. Hermes currently documents the OAuth path as requiring Claude Max plus extra-usage credits; Claude Pro and the included Max allowance are not used by that provider path.
- `keep`: preserve each installed profile's existing model block.

Subscription authentication is stored per Hermes profile, so an interactive setup authenticates all five profiles. In non-interactive installs, set `HERMES_AUTODEV_AUTH_HERMES_SUBSCRIPTION=0` and authenticate each profile afterward; browser/device OAuth cannot safely be completed from a secrets file. If authentication is deliberately deferred, also set `HERMES_AUTODEV_RUN_DOCTOR=0`, complete the printed logins, and then run `hermes-autodev doctor` so the installation is not mistaken for ready before credentials exist.

The Developer's Codex CLI lane has its own authentication. Its existing `codex login` session (normally under `~/.codex`) or `OPENAI_API_KEY` is still required even when Hermes itself uses another provider.

The Developer lane is intentionally autonomous: its launcher runs Codex with
approval disabled and the `danger-full-access` sandbox policy so package
installation, tests, local services, and Git remotes work. Run this package only
as a dedicated unprivileged account, use trusted project repositories, and give
that account the minimum repository/cloud credentials it needs.

Minimum practical setup also includes:

- Lovable OAuth access if the optional Frontend Designer workflow will be used.
- Codex auth for the server account, usually `codex login` or `OPENAI_API_KEY`.
- `GITHUB_TOKEN` plus `gh` for GitHub issues, pull requests, comments, and CI.
- `GITLAB_TOKEN`, `GITLAB_HOST`, and preferably `glab` for GitLab issues, merge requests, comments, and pipelines. Self-managed GitLab is supported by setting its base URL.
- `TELEGRAM_BOT_TOKEN` and `TELEGRAM_ALLOWED_USERS` only if you want the PM gateway exposed through Telegram.

## Browser GUI

The package uses Hermes' built-in dashboard rather than maintaining a second control plane. It exposes the same five profiles and their configuration, browser chat, Kanban boards, cron jobs, models, API keys, skills, and MCP settings.

After the wizard, use the installed command from any directory. Start it on a
local Linux/WSL2 computer:

```bash
hermes-autodev dashboard open
```

On a remote Linux server, run the same command from the SSH session. It prints a command like this to run in a terminal on your own computer:

```bash
ssh -N -L 9119:127.0.0.1:9119 user@server
```

Then open `http://127.0.0.1:9119` locally. The package deliberately supports loopback binding only; use an SSH tunnel or a trusted VPN instead of exposing the dashboard port to the internet.

Loopback prevents network exposure but is not a per-user boundary: another
account with local access to the same multi-user host may be able to reach a
loopback service. Use a single-tenant host/container or enforce host-level
isolation when local users are not mutually trusted.

Useful controls:

```bash
hermes-autodev dashboard status
hermes-autodev dashboard access
hermes-autodev dashboard restart
hermes-autodev dashboard stop
```

When persistence is selected, a systemd user service is installed. On SSH servers, an administrator may need to enable lingering once with `sudo loginctl enable-linger <user>` so user services survive logout. If a user systemd bus is unavailable, the manager falls back to an owner-scoped background process and records its PID/log under `~/.hermes/autodev/`.

## GitHub And GitLab Projects

Project bootstrap records the origin URL and SCM provider in `~/.hermes/autodev/projects/<slug>.env`. With `--scm-provider auto`, standard GitHub and GitLab remote URLs are detected automatically; pass `gitlab` explicitly for a self-managed hostname that does not contain `gitlab`.

Project Manager, Developer, Tester, and Security Tester include host-aware instructions and a GitLab workflow skill. They use `gh` plus pull requests for GitHub, `glab` plus merge requests for GitLab, and do not mix the two CLIs. The GitLab workflow covers project context, issues, confidential issues, merge-request creation/review/merge, pipeline status, and a GitLab API v4 fallback.

The wizard can authenticate the CLI when a token is supplied. You can also authenticate later:

```bash
printf '%s\n' "$GITLAB_TOKEN" | glab auth login --hostname gitlab.com --stdin
glab auth status --hostname gitlab.com
```

## Security Testing

The `security-tester` profile uses the provider/model selected by the wizard; its source-package default remains Kimi K3 through OpenRouter. It is source-aware and can perform safe static, dependency, secret, configuration, infrastructure, API, and explicitly authorized dynamic testing. It never edits the application or applies fixes; confirmed findings go to `developer` for Codex remediation and return to `security-tester` for retesting. The selected provider/model must remain fixed during an individual assessment rather than silently falling back.

Its pinned baseline is OWASP ASVS 5.0.0, WSTG 4.2, OWASP Top 10:2025, API Security Top 10:2023, and NIST SSDF 1.1. Authenticated business products default to ASVS Level 2. Mobile and LLM/agent guidance is added only when relevant, with the exact stable version recorded in the report.

Dynamic tests require an exact authorized target and scope. Production, third-party, destructive, brute-force, denial-of-service, and bulk-data techniques are out of scope by default. Security artifacts must stay outside the application repo and sensitive proof must be redacted/restricted.

The package does not install global scanners. The profile can use existing tools such as Gitleaks, OSV-Scanner, Semgrep, Trivy/Checkov, and OWASP ZAP baseline mode; missing tools must be reported as coverage gaps.

See [docs/security-testing.md](docs/security-testing.md) for the task scope template, workflow, standards, optional tools, evidence policy, and release gate.

## Bootstrap A Project

For an existing Git repo:

```bash
hermes-autodev project \
  --project-path ~/projects/my-project \
  --project-slug my-project \
  --project-name "My Project" \
  --scm-provider auto \
  --cron \
  --start-gateway
```

For a repo that should be cloned first:

```bash
hermes-autodev install -y \
  --repo-url git@gitlab.com:group/app.git \
  --project-path /srv/app \
  --project-slug app \
  --scm-provider gitlab \
  --cron \
  --start-gateway
```

The project setup script creates or updates:

- A first-class Hermes Project linked to the repository in every team profile,
  with the Project Manager copy bound to the coordination board. This preserves
  GUI/Desktop session grouping while switching roles and keeps task worktrees
  deterministic.
- A Hermes Kanban board for the project.
- The board default workdir pointing at the repo.
- A project env file under `~/.hermes/autodev/projects/<slug>.env`.
- The detected or selected SCM provider and origin URL in that project env file.
- A project watchdog wrapper under `~/.hermes/scripts/`.
- A no-agent watchdog cron job.
- An agent PM sweep cron job.
- An idempotent kickoff task assigned to `project-manager`.

The wizard can run this same bootstrap as part of initial setup. For additional projects later:

```bash
hermes-autodev setup --skip-install
```

## Multiple Projects

Install the profiles once per VPS. Run `scripts/setup-project.sh` once per project repo.

Each project gets its own:

- Kanban board.
- Default workdir.
- Watchdog wrapper.
- Cron job names.
- Kickoff task.

The same `project-manager`, `frontend-designer`, `developer`, `tester`, and `security-tester` profiles can work across multiple boards because Hermes cron and Kanban tasks carry the board/workdir context.

Git worktrees are supported; project setup resolves the checkout root through Git rather than requiring a `.git` directory.

## Project Manager Gateway

Use the package manager so the gateway also works on hosts without a user systemd bus:

```bash
hermes-autodev gateway start
hermes-autodev gateway status
hermes-autodev gateway stop
```

Only expose the `project-manager` profile through Telegram or other owner-facing chat gateways. Frontend Designer, Developer, Tester, and Security Tester should be driven by Kanban and the configured repository host, not direct chat.

## Health Check

```bash
hermes-autodev doctor
hermes-autodev doctor --project-slug my-project
```

Useful runtime commands:

```bash
hermes -p project-manager kanban --board my-project list
hermes -p project-manager kanban --board my-project stats
hermes -p project-manager cron list --all
hermes-autodev gateway status
```

## Updating

Make profile, skill, markdown, or script changes in this package repo, then:

```bash
git add .
git commit -m "update autonomous dev team package"
git push
```

On an installed Linux host:

```bash
hermes-autodev update
```

The updater creates a Hermes backup, updates Hermes through its supported updater, fast-forwards this Git checkout, refreshes all five profiles without resetting their configuration/auth/data, restarts the GUI if it was running, and runs the doctor. It refuses to pull over a dirty checkout, so local package changes cannot be silently overwritten.

Preview versions without changing anything:

```bash
hermes-autodev update --check
```

## Uninstalling

Always preview first:

```bash
hermes-autodev uninstall --dry-run
hermes-autodev uninstall
```

The default uninstall makes a full backup outside `~/.hermes`, stops
package-managed services, and removes the five package profiles plus generated
scripts/state. Package projects and boards leave the live Hermes installation
with their owning profile but remain recoverable from that backup. It does not
delete project repositories, shared Git/SSH configuration, `gh`/`glab`
authentication, or Claude/Codex CLI authentication.

Optional flags can uninstall Hermes itself or remove the package checkout.
These are explicit because Hermes may be shared with unrelated profiles. Use
`hermes-autodev uninstall --help` for the exact behavior, backup location, and
destructive options.

## Package Validation

Run the release checks locally with:

```bash
bash tests/static-checks.sh
bash tests/smoke-lifecycle.sh
```

The lifecycle suite uses temporary homes, a fake Hermes/Codex installation,
real Git repositories and a real loopback HTTP service. It covers safe reruns,
subscription configuration, GitLab hostname detection, linked worktrees, all
five GUI project registrations, dashboard start/health/stop, custom
`HERMES_HOME` rediscovery (including spaces and apostrophes), a fast-forward
package update, backup, and guarded uninstall fallback/alias cleanup. The
included `.gitlab-ci.yml` runs these checks for GitLab pushes and merge requests,
with ShellCheck 0.11.0 in a pinned-version image.

## Hermes Docs Cross-Reference

The package follows these Hermes-supported mechanisms:

- Profile distributions: `hermes profile install <source> --name <profile> --alias`, with `SOUL.md`, `config.yaml`, `distribution.yaml`, `.env.EXAMPLE`, and `skills/` packaged as profile-owned files. The team installer separately copies Developer's Codex launcher because Hermes reserves profile-level `bin/` as runtime-owned.
- MCP: Frontend Designer connects to Lovable over OAuth with only the inspection and tightly budgeted generation tools needed for design handoffs.
- Kanban: one board per project/workstream, created with `hermes kanban boards create ... --default-workdir ... --switch`; workers coordinate through `kanban_*` tools and the PM uses `hermes kanban` for scripts.
- Cron: recurring jobs are created with `hermes cron create`, using `--script --no-agent` for watchdog checks and script-plus-prompt agent jobs for PM sweeps.
- Gateway: `project-manager gateway start` runs the gateway, scheduler, and dispatcher; `gateway run` is the foreground fallback.
- Runtime separation: profile install/update should not commit `.env`, auth, sessions, logs, state databases, or project Kanban state into this package.

See [docs/hermes-docs-cross-reference.md](docs/hermes-docs-cross-reference.md) for the exact Hermes documentation and CLI references used, and [docs/security-testing.md](docs/security-testing.md) for the Security Tester operating baseline.
