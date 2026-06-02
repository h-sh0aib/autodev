# Hermes Autonomous Development Team

This directory contains three Hermes profile distributions:

- `project-manager`: coordinates the team, monitors Kanban/GitHub, and is the only profile intended for Telegram exposure.
- `developer`: delegates all coding, architecture planning, debugging, and tests to Codex.
- `tester`: validates PRs with Playwright and human-style product testing.

Hermes Kanban is the agent coordination layer. GitHub Issues and PRs are the engineering source of truth.

## Install Profiles

After Hermes is installed:

```bash
hermes profile install /root/hermes-autonomous-dev-team/project-manager --name project-manager --alias
hermes profile install /root/hermes-autonomous-dev-team/developer --name developer --alias
hermes profile install /root/hermes-autonomous-dev-team/tester --name tester --alias
```

## Telegram PM Gateway

Fill the PM profile environment file:

```bash
cp /root/.hermes/profiles/project-manager/.env.EXAMPLE /root/.hermes/profiles/project-manager/.env
```

Then set:

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USERS=...
```

Start the PM gateway:

```bash
project-manager gateway start
```

If the host does not expose a user systemd bus, run the foreground gateway:

```bash
/root/hermes-autonomous-dev-team/run-pm-gateway.sh
```

The Developer and Tester profiles should not be exposed to Telegram unless you intentionally give them their own separate bot tokens.
