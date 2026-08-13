# Sync And Productization

This repo is the source package for the reusable autonomous Hermes development team. Installed profiles and project state under `~/.hermes` are runtime state.

## Source Package

Commit:

- `install.sh`
- `wizard.sh`
- `scripts/`
- `templates/`
- `setup.example.env`
- `docs/`
- `README.md`
- `NEXT_STEPS.md`
- `SYNC_AND_PRODUCTIZATION.md`
- `project-manager/SOUL.md`
- `project-manager/config.yaml`
- `project-manager/distribution.yaml`
- `project-manager/.env.EXAMPLE`
- `project-manager/skills/`
- `frontend-designer/SOUL.md`
- `frontend-designer/config.yaml`
- `frontend-designer/distribution.yaml`
- `frontend-designer/.env.EXAMPLE`
- `frontend-designer/skills/`
- `developer/SOUL.md`
- `developer/config.yaml`
- `developer/distribution.yaml`
- `developer/.env.EXAMPLE`
- `developer/bin/`
- `developer/skills/`
- `tester/SOUL.md`
- `tester/config.yaml`
- `tester/distribution.yaml`
- `tester/.env.EXAMPLE`
- `tester/skills/`
- `security-tester/SOUL.md`
- `security-tester/config.yaml`
- `security-tester/distribution.yaml`
- `security-tester/.env.EXAMPLE`
- `security-tester/skills/`

Do not commit:

- Real `.env` files.
- API keys, OAuth files, Telegram tokens, Signal credentials, or GitHub/GitLab tokens.
- `~/.hermes/profiles/*/state.db`.
- Sessions, logs, caches, process files, model catalogs, or auth files.
- Project repos or project-specific progress data.
- Hermes Kanban runtime databases.

## Runtime Profiles

Hermes installs and runs profiles from:

```bash
~/.hermes/profiles/project-manager
~/.hermes/profiles/frontend-designer
~/.hermes/profiles/developer
~/.hermes/profiles/tester
~/.hermes/profiles/security-tester
```

These directories contain package-owned files plus mutable runtime state. Treat them as installed output, not the long-term source of truth.

Refresh runtime profiles from this package:

```bash
hermes-autodev setup --skip-project
```

Or use the lower-level installer:

```bash
hermes-autodev install -y
```

Or install a single profile with Hermes directly:

```bash
hermes profile install ./project-manager --name project-manager --alias -y
```

For a profile already installed from this distribution, use
`hermes profile update project-manager -y`. Reserve `--force` or
`--force-config` for an intentional repair/reset after taking a backup.

Hermes profile distributions support package-owned files such as `SOUL.md`, `config.yaml`, `distribution.yaml`, `.env.EXAMPLE`, and `skills/`. The team installer separately copies Developer's Codex launcher because Hermes treats profile-level `bin/` as runtime-owned. Runtime `.env` and auth/session data should remain outside Git.

## Runtime To Source Sync

If you tune a live profile directly and want to keep the change, copy only package-owned files back into this repo, inspect the diff, and commit it.

Example:

```bash
cp ~/.hermes/profiles/project-manager/SOUL.md ./project-manager/SOUL.md
cp ~/.hermes/profiles/project-manager/config.yaml ./project-manager/config.yaml
rsync -a --delete ~/.hermes/profiles/project-manager/skills/ ./project-manager/skills/

git status --short
git diff
```

Never copy `.env`, `auth.json`, `state.db`, `sessions`, `logs`, `cache`, or `processes.json` into the package.

Do not mirror a live profile's entire `skills/` directory. Hermes may populate it with the auto-bundled catalog; keep only curated team-owned skills. In particular, do not copy Security Tester scanner caches, vulnerability databases, generated evidence, or temporary tooling into the source package.

## New VPS Workflow

```bash
git clone <package-repository-url> hermes-autonomous-dev-team
cd hermes-autonomous-dev-team
bash ./wizard.sh
```

For non-interactive/client handoff installs:

```bash
cp setup.example.env client.env
nano client.env
bash ./wizard.sh --config client.env --non-interactive
```

Then bootstrap additional projects as needed:

```bash
hermes-autodev setup --skip-install
```

Run the setup script again for more projects. Do not duplicate the profile distributions for each project.

## Project Runtime State

Per-project runtime files are created under:

```bash
~/.hermes/autodev/projects/<slug>.env
~/.hermes/scripts/autodev_watchdog_<slug>.sh
```

Project cron jobs live in the Project Manager profile's Hermes cron state. Project tasks live in Hermes Kanban state. Project code lives in the project repo.

That split is deliberate:

- Package repo: reusable team behavior.
- Runtime Hermes state: installed profiles, cron jobs, boards, secrets, sessions.
- Project repo: application code and project-specific docs.

## Productization Notes

Keep the package private until all personal contact details, client names, trial project references, and secrets are removed. The package should remain generic:

- No hard-coded owner phone numbers or chat IDs.
- No hard-coded project repository path.
- No trial project progress or Kanban state.
- No customer-specific docs or feature lists.
- No real tokens.

Use `README.md` for install instructions, `docs/hermes-docs-cross-reference.md` for Hermes design rationale, and `NEXT_STEPS.md` as the short operational checklist.

## Selling To Non-Technical Clients

Use `wizard.sh` as the client-facing entrypoint. It safely installs or updates all five profiles, selects their Hermes provider/models, can authenticate ChatGPT/Codex or supported Claude subscription access per profile, configures env files from one prompt flow, optionally sets Git identity, writes GitHub/GitLab/Codex/Telegram/Signal values to the right profiles, bootstraps the first project, configures the local/SSH browser GUI, creates watchdog/PM sweep cron jobs, and can start the PM gateway. Security Tester can use a separately selected model while retaining the package's report-only safeguards.

Each wizard run writes a support log under `~/.hermes/autodev/logs/` with `0600` permissions. If a client setup fails, ask for the latest `setup-wizard-*.log` file.

For white-glove installs, pre-fill `client.env` from `setup.example.env` and run:

```bash
bash ./wizard.sh --config client.env --non-interactive
```

For package updates after profile, skill, markdown, or script changes:

```bash
hermes-autodev update
```

If env examples gain new keys, the wizard is the place to add prompts and profile env writes so clients never have to edit profile folders manually.
