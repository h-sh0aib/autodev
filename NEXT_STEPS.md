# Next Steps

Use this checklist after cloning the package onto a VPS.

## 1. Run The Setup Wizard

```bash
cd hermes-autonomous-dev-team
./wizard.sh
```

This installs or refreshes the `project-manager`, `frontend-designer`, `developer`, and `tester` profiles, configures profile env files from one place, can set Git identity, can help with GitHub/Codex credentials, and can bootstrap the first project.

Every wizard run writes a setup transcript under:

```bash
~/.hermes/autodev/logs/
```

For non-interactive setup:

```bash
cp setup.example.env client.env
nano client.env
./wizard.sh --config client.env --non-interactive
```

## 2. Fill Runtime Credentials

The wizard prompts for these, or reads them from `client.env`:

```bash
OPENROUTER_API_KEY=...
GITHUB_TOKEN=...
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
```

Only the Project Manager should receive owner-facing Telegram or Signal gateway credentials unless you intentionally design otherwise.

Lovable uses OAuth rather than a value in these env files. Authenticate the Frontend Designer's `lovable` MCP connection before assigning its first design task. It is optional for projects that do not need initial UI design guidance.

## 3. Verify Codex

Authenticate Codex for the server account:

```bash
codex login
codex exec "echo CODEX_OK"
```

For headless servers, prefer `OPENAI_API_KEY` in `~/.hermes/profiles/developer/.env` if browser OAuth is impractical.

## 4. Bootstrap A Project

The wizard can do this interactively. For an existing repo:

```bash
./scripts/setup-project.sh \
  --project-path /absolute/path/to/repo \
  --project-slug my-project \
  --cron \
  --start-gateway
```

Clone and bootstrap:

```bash
./install.sh -y \
  --repo-url git@github.com:org/app.git \
  --project-path /srv/app \
  --project-slug app \
  --cron \
  --start-gateway
```

For additional projects after the first:

```bash
./wizard.sh --skip-install
```

## 5. Check Health

```bash
./scripts/doctor.sh --project-slug my-project
hermes -p project-manager kanban --board my-project list
hermes -p project-manager cron list --all
hermes -p project-manager gateway status
```

## 6. Push The Package Repo

Keep this package in a private Git repo first. Commit profile distributions, skills, scripts, templates, and docs. Do not commit runtime secrets, sessions, logs, Kanban databases, auth files, or project repos.

To update a client VPS after package changes:

```bash
git pull
./wizard.sh --skip-project
```
