# Autonomous Team Package Sync And Productization

This document describes how to treat `/root/hermes-autonomous-dev-team` as the source package for the autonomous development team, while treating `/root/.hermes/profiles/*` as installed runtime state.

## Directory Roles

### Source Package

`/root/hermes-autonomous-dev-team`

This should become the Git repository for the autonomous team package.

Commit:

- `project-manager/SOUL.md`
- `project-manager/config.yaml`
- `project-manager/distribution.yaml`
- `project-manager/skills/**`
- `developer/SOUL.md`
- `developer/config.yaml`
- `developer/distribution.yaml`
- `developer/bin/**`
- `developer/skills/**`
- `tester/SOUL.md`
- `tester/config.yaml`
- `tester/distribution.yaml`
- `tester/skills/**`
- Documentation such as this file
- Reusable scripts that are safe to ship

Do not commit:

- API keys
- OAuth tokens
- Telegram bot tokens
- GitHub tokens
- `.env` files with real secrets
- profile `state.db`
- sessions
- logs
- cache
- generated model catalogs
- runtime process files

### Runtime Profiles

`/root/.hermes/profiles/project-manager`
`/root/.hermes/profiles/developer`
`/root/.hermes/profiles/tester`

These are the installed profiles that Hermes actually runs.

They contain:

- Runtime `SOUL.md`
- Runtime `config.yaml`
- Active skills
- `.env`
- auth files
- cron jobs
- logs
- sessions
- state databases
- caches

Treat these as mutable runtime state, not the Git source of truth.

## Recommended Git Setup

From the source package directory:

```bash
cd /root/hermes-autonomous-dev-team
git init
git add README.md NEXT_STEPS.md SYNC_AND_PRODUCTIZATION.md
git add project-manager developer tester run-pm-gateway.sh
git add disabled-project-manager-skills disabled-developer-skills
git commit -m "chore: initial autonomous Hermes dev team package"
```

Add a remote when ready:

```bash
git remote add origin git@github.com:<org>/<repo>.git
git push -u origin main
```

For a productized version, use a private repository first. Move secrets, client names, and project-specific defaults into templates or environment variables before making it public or selling it.

## Source To Runtime Sync

Use this when you change the source package and want to update installed profiles.

```bash
hermes profile install /root/hermes-autonomous-dev-team/project-manager --name project-manager --alias
hermes profile install /root/hermes-autonomous-dev-team/developer --name developer --alias
hermes profile install /root/hermes-autonomous-dev-team/tester --name tester --alias
```

If profile install overwrites too much runtime state for your setup, sync only the managed files:

```bash
cp /root/hermes-autonomous-dev-team/project-manager/SOUL.md /root/.hermes/profiles/project-manager/SOUL.md
cp /root/hermes-autonomous-dev-team/project-manager/config.yaml /root/.hermes/profiles/project-manager/config.yaml
rsync -a --delete /root/hermes-autonomous-dev-team/project-manager/skills/ /root/.hermes/profiles/project-manager/skills/

cp /root/hermes-autonomous-dev-team/developer/SOUL.md /root/.hermes/profiles/developer/SOUL.md
cp /root/hermes-autonomous-dev-team/developer/config.yaml /root/.hermes/profiles/developer/config.yaml
rsync -a --delete /root/hermes-autonomous-dev-team/developer/bin/ /root/.hermes/profiles/developer/bin/
rsync -a --delete /root/hermes-autonomous-dev-team/developer/skills/ /root/.hermes/profiles/developer/skills/

cp /root/hermes-autonomous-dev-team/tester/SOUL.md /root/.hermes/profiles/tester/SOUL.md
cp /root/hermes-autonomous-dev-team/tester/config.yaml /root/.hermes/profiles/tester/config.yaml
rsync -a --delete /root/hermes-autonomous-dev-team/tester/skills/ /root/.hermes/profiles/tester/skills/
```

Be careful with `--delete`: it makes runtime skills match the source package. Use it only when source is the intended authority.

## Runtime To Source Sync

Use this when you tune the live profiles directly and want to preserve those changes in the package repo.

```bash
cp /root/.hermes/profiles/project-manager/SOUL.md /root/hermes-autonomous-dev-team/project-manager/SOUL.md
cp /root/.hermes/profiles/project-manager/config.yaml /root/hermes-autonomous-dev-team/project-manager/config.yaml
rsync -a --delete /root/.hermes/profiles/project-manager/skills/ /root/hermes-autonomous-dev-team/project-manager/skills/

cp /root/.hermes/profiles/developer/SOUL.md /root/hermes-autonomous-dev-team/developer/SOUL.md
cp /root/.hermes/profiles/developer/config.yaml /root/hermes-autonomous-dev-team/developer/config.yaml
rsync -a --delete /root/.hermes/profiles/developer/bin/ /root/hermes-autonomous-dev-team/developer/bin/
rsync -a --delete /root/.hermes/profiles/developer/skills/ /root/hermes-autonomous-dev-team/developer/skills/

cp /root/.hermes/profiles/tester/SOUL.md /root/hermes-autonomous-dev-team/tester/SOUL.md
cp /root/.hermes/profiles/tester/config.yaml /root/hermes-autonomous-dev-team/tester/config.yaml
rsync -a --delete /root/.hermes/profiles/tester/skills/ /root/hermes-autonomous-dev-team/tester/skills/
```

Before committing, inspect diffs carefully:

```bash
cd /root/hermes-autonomous-dev-team
git status --short
git diff
```

Never copy runtime `.env`, `auth.json`, `state.db`, `sessions`, `logs`, `cache`, or `processes.json` into the source package.

## Server Reproduction Workflow

On a new server:

1. Install Hermes Agent.
2. Clone the autonomous team package:

```bash
git clone git@github.com:<org>/<repo>.git /root/hermes-autonomous-dev-team
```

3. Install the profiles:

```bash
hermes profile install /root/hermes-autonomous-dev-team/project-manager --name project-manager --alias
hermes profile install /root/hermes-autonomous-dev-team/developer --name developer --alias
hermes profile install /root/hermes-autonomous-dev-team/tester --name tester --alias
```

4. Configure secrets in runtime `.env` files only:

```bash
cp /root/.hermes/profiles/project-manager/.env.EXAMPLE /root/.hermes/profiles/project-manager/.env
cp /root/.hermes/profiles/developer/.env.EXAMPLE /root/.hermes/profiles/developer/.env
cp /root/.hermes/profiles/tester/.env.EXAMPLE /root/.hermes/profiles/tester/.env
```

5. Add required credentials:

- Project Manager: Telegram bot token, allowed users, model provider key, GitHub token if needed.
- Developer: model provider key, GitHub token if needed, Codex auth or `CODEX_HOME`.
- Tester: model provider key, GitHub token if needed.

6. Authenticate any provider-specific tools:

```bash
project-manager setup
developer setup
tester setup
```

7. Verify Codex for Developer:

```bash
developer -z "Run codex --version and report whether codex-network-exec exists. Do not edit files."
```

8. Start the PM gateway only when ready:

```bash
project-manager gateway start
```

## Productization Notes

To make this reusable for other projects or companies, separate the package into layers:

### Core Team Package

Reusable across customers:

- Project Manager role contract
- Developer Codex-only contract
- Tester Playwright-only contract
- Codex network wrapper
- PM monitoring rules
- Kanban operating rules
- Generic scripts and documentation

### Project Template

Specific to one software project:

- Project workspace path
- GitHub repo
- acceptance criteria defaults
- domain-specific quality bar
- testing personas
- deployment commands
- model/provider preferences

### Customer Runtime

Never committed:

- credentials
- tokens
- chat IDs
- customer data
- logs
- sessions
- local task state

## Suggested Package Variables

Replace hardcoded paths with template variables before selling or distributing:

- `AUTODEV_PROJECT_ROOT`
- `AUTODEV_GITHUB_REPO`
- `AUTODEV_KANBAN_BOARD`
- `AUTODEV_PM_PROFILE`
- `AUTODEV_DEVELOPER_PROFILE`
- `AUTODEV_TESTER_PROFILE`
- `AUTODEV_MODEL`
- `AUTODEV_PROVIDER`
- `AUTODEV_ALLOWED_USER_IDS`

## Usage Logs

Hermes session-level token usage is available through:

```bash
hermes -p project-manager insights --days 7
hermes -p developer insights --days 7
hermes -p tester insights --days 7
```

The local Hermes patch also writes per-LLM-call rows to:

```text
/root/.hermes/profiles/<profile>/logs/llm-usage.jsonl
```

Each row includes profile, session id, model, provider, input tokens, output tokens, cache tokens, reasoning tokens, latency, and estimated cost metadata when available.

For productization, either upstream this patch into your Hermes fork or provide it as a documented patch step for every deployment.

## Operational Rule

Do not edit runtime profiles directly for long-term behavior unless you immediately sync the change back to `/root/hermes-autonomous-dev-team` and commit it.

Runtime is where the team runs. Source is where the team is defined.
