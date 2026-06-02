# Activation Steps

The local Hermes install and profiles are initialized. The remaining work is secret/auth setup.

## Required Credentials

Edit `/root/.hermes/profiles/project-manager/.env` and set:

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USERS=...
```

Also configure a model provider for each profile, for example by exporting API keys in each profile `.env` or running:

```bash
project-manager setup
developer setup
tester setup
```

For GitHub issue and PR operations, configure GitHub auth with either `GITHUB_TOKEN` in each profile `.env` or the bundled GitHub auth flow.

For Developer's Codex-only workflow, authenticate Codex for the Developer profile:

```bash
developer auth
```

## Start Project Manager Gateway

If user systemd is available on the host:

```bash
project-manager gateway start
```

If running in a container or environment without a user systemd bus:

```bash
/root/hermes-autonomous-dev-team/run-pm-gateway.sh
```

Only the Project Manager profile should receive the Telegram bot token. Developer and Tester should operate through Hermes Kanban and GitHub, not through direct Telegram exposure.

