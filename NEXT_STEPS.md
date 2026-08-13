# Next Steps

Use this checklist after cloning the package onto local Linux, WSL2, or a remote Linux host.

## 1. Run The Setup Wizard

```bash
cd hermes-autonomous-dev-team
bash ./wizard.sh
```

This installs or refreshes the `project-manager`, `frontend-designer`, `developer`, `tester`, and `security-tester` profiles, selects the Hermes provider/models, configures profile env files from one place, can set Git identity, can help with GitHub/GitLab/Codex credentials, and can bootstrap the first project.

Every wizard run writes a setup transcript under:

```bash
~/.hermes/autodev/logs/
```

For non-interactive setup:

```bash
cp setup.example.env client.env
nano client.env
bash ./wizard.sh --config client.env --non-interactive
```

## 2. Fill Runtime Credentials

Choose `openrouter`, `openai-codex`, `anthropic`, or `keep` as `HERMES_AUTODEV_MODEL_PROVIDER`. OpenAI Codex and Anthropic OAuth are interactive per-profile subscription sign-ins; API keys remain available for unattended/API-billed setups.

The wizard prompts for the applicable subset of these, or reads them from `client.env`:

```bash
OPENROUTER_API_KEY=...
ANTHROPIC_API_KEY=...
GITHUB_TOKEN=...
GITLAB_HOST=https://gitlab.com
GITLAB_TOKEN=...
OPENAI_API_KEY=...
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USERS=...
```

The wizard writes the right subset into:

```bash
~/.hermes/profiles/project-manager/.env
~/.hermes/profiles/frontend-designer/.env
~/.hermes/profiles/developer/.env
~/.hermes/profiles/tester/.env
~/.hermes/profiles/security-tester/.env
```

Only the Project Manager should receive owner-facing Telegram or Signal gateway credentials unless you intentionally design otherwise.

Lovable uses OAuth rather than a value in these env files. Authenticate the Frontend Designer's `lovable` MCP connection before assigning its first design task. It is optional for projects that do not need initial UI design guidance.

Security Tester uses the separately selected Security Tester model; its source-package default is `moonshotai/kimi-k3` through OpenRouter. Global scanners are optional and are not installed by the package; see [docs/security-testing.md](docs/security-testing.md) before assigning dynamic testing, especially for the required target scope and production restrictions.

## 3. Verify Codex

Authenticate Codex for the server account:

```bash
codex login
codex exec "echo CODEX_OK"
```

On a headless server, `codex login` presents a browser sign-in flow that can be completed from your own computer. `OPENAI_API_KEY` remains the separate usage-billed alternative.

This Codex CLI authentication is separate from the Hermes orchestration provider selection. If Hermes uses `openai-codex`, the wizard also authenticates that provider for every Hermes profile.

## 4. Bootstrap A Project

The wizard can do this interactively. For an existing repo:

```bash
hermes-autodev project \
  --project-path ~/projects/my-project \
  --project-slug my-project \
  --scm-provider auto \
  --cron \
  --start-gateway
```

Clone and bootstrap:

```bash
hermes-autodev install -y \
  --repo-url git@gitlab.com:group/app.git \
  --project-path /srv/app \
  --project-slug app \
  --scm-provider gitlab \
  --cron \
  --start-gateway
```

Use `GITHUB_TOKEN`/`gh` for GitHub or `GITLAB_TOKEN`/`glab` for GitLab. Set `GITLAB_HOST` for self-managed GitLab; `auto` detects GitHub or GitLab from the origin remote.

For additional projects after the first:

```bash
hermes-autodev setup --skip-install
```

## 5. Open The GUI

```bash
hermes-autodev dashboard open
```

On SSH hosts, run the printed `ssh -L` command on your own computer and open the local URL. The dashboard is intentionally bound only to `127.0.0.1`.

## 6. Check Health

```bash
hermes-autodev doctor --project-slug my-project
hermes -p project-manager kanban --board my-project list
hermes -p project-manager cron list --all
hermes-autodev gateway status
```

## 7. Update Or Uninstall

```bash
hermes-autodev update --check
hermes-autodev update
hermes-autodev uninstall --dry-run
```

The uninstaller preserves project repos and shared Git/SSH/GitHub/GitLab/Codex credentials. It backs up before removing package state unless explicitly told not to.

## 8. Push The Package Repo

Keep this package in a private Git repo first. Commit profile distributions, skills, scripts, templates, and docs. Do not commit runtime secrets, sessions, logs, Kanban databases, auth files, or project repos.

To update a client VPS after package changes:

```bash
hermes-autodev update
```
