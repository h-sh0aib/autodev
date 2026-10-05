# Public portal on a Linux server

The public site shows selected project updates and accepts support tickets. `/team` requires a team login and provides project briefs, ticket handoffs, release evidence and scheduling controls. Everyday use requires only a browser. Server installation, credentials and DNS are a one-time operator responsibility.

Use a dedicated unprivileged account on a single-tenant Linux host with systemd, Python 3.11+ and a domain you control. The portal and Hermes use that same account. Seven named profiles provide durable identities and specialist responsibilities; they do not provide separate OS security boundaries.

## Install and connect a project

As the dedicated account:

```bash
bash ./wizard.sh
hermes-autodev project --project-path /absolute/path/to/product \
  --project-slug product --cron --start-gateway
hermes-autodev portal setup --domain team.example.com
```

The portal setup installs its pinned dependencies into the runtime directory's `portal-venv`, generates `portal.json` and a `Caddyfile`, installs `hermes-autodev-portal.service` as a user service, and prompts for an account. It does not change DNS, install Caddy, or overwrite an existing reverse proxy configuration. It does not require the raw Hermes dashboard to be running.

If Python cannot create a virtual environment on Debian/Ubuntu, have an administrator install `python3-venv` first. The portal command's noninteractive form skips account prompts; create an account separately:

```bash
hermes-autodev portal user owner
hermes-autodev portal user support --role support
hermes-autodev portal user observer --role viewer
```

Passwords are read through hidden prompts and stored as salted scrypt hashes. Re-running `user` resets that account and invalidates its existing sessions. For provisioning, `--password-stdin` reads one line from a secret source; do not put passwords in command arguments, shell history or version control. There are no default accounts, public signup, email reset or MFA integrations.

When upgrading from the five-role package, use `hermes-autodev update --configure` (or rerun `hermes-autodev setup --skip-install --skip-project`) to configure credentials/models for the two new support profiles. Subscription providers require their own per-profile sign-ins.

Existing installations must rerun `hermes-autodev project` for each repository after updating. This registers the project in the portal, installs the corrected watchdog wrapper, and refreshes the recurring PM prompt. Registration preserves publication settings and ticket history. It does not create a duplicate kickoff task.

## Put HTTPS in front of the portal

Point the domain's DNS A/AAAA records at this server. Remove an incorrect AAAA record if the host has no working public IPv6. Install Caddy following its [official installation guide](https://caddyserver.com/docs/install). Caddy obtains and renews certificates for configured domains using [automatic HTTPS](https://caddyserver.com/docs/automatic-https).

On a dedicated server, an administrator can use the generated configuration (replace the account and runtime paths below with the ones printed by setup):

```bash
sudo install -m 0644 /home/autodev/.hermes/autodev/Caddyfile /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl enable --now caddy
sudo systemctl reload caddy
sudo loginctl enable-linger autodev
```

If Caddy already hosts other sites, merge the generated site block into its configuration instead of replacing it. Allow inbound TCP 80 and 443 in the server and cloud firewall, while retaining your SSH access. The generated proxy sends requests only to `127.0.0.1:8787`. Keep port 8787 and the Hermes admin port 9119 private.

Open `https://team.example.com/team`, sign in, and open **View project**. Enable the public project page and write a customer-friendly update. The root page then lists the project and accepts tickets. All projects start private, including previously registered repositories.

The portal validates the configured hostname and request origin, uses Secure/HttpOnly/SameSite session cookies for HTTPS, verifies a per-session CSRF token on authenticated writes, bounds request bodies, and rate-limits login and public intake. Only loopback Caddy proxy headers are trusted. There is no arbitrary terminal or executable endpoint. Public responses use explicit field lists rather than exposing internal task records. Customer text is rendered as text, not HTML.

## Day-to-day use

| Person | Where to go | What they can do |
| --- | --- | --- |
| Customer | `/` | Read shared updates and submit a ticket |
| Ticket holder | Private tracking link | Read support replies, add information, reopen a closed ticket |
| Viewer | `/team` | See internal project/task progress, ticket history and release evidence |
| Support teammate | `/team` | Viewer access plus ticket replies and support handoffs |
| Owner | `/team` | Support access plus briefs, publication and team scheduling controls |

**Give the team a brief** accepts plain-language outcomes and sends a durable task to the PM. **Pause scheduling** stops the shared PM gateway/scheduler across all projects; it is not an emergency kill switch. Already-running workers or cron executions may continue. **Start the team** resumes new scheduling. Only this package's PM gateway should dispatch the boards; a second independently running gateway could keep scheduling work.

Customers receive a random private tracking link with a secret in its URL fragment. The fragment is not sent in HTTP URLs or access logs. The customer must save it; anyone holding it can access that conversation. Only its hash is stored, so the operator cannot recover a lost secret. Replies are delivered on the tracking page; email notifications, inbound email, attachments and third-party helpdesks are not implemented. Optional email addresses are contact information only.

Publication exposes only the chosen project name, owner's summary, synchronization time and readiness indication. It never exposes internal titles, repository paths, gate references or customer conversations. Ticket tracking remains available after a project is made private, but new public submissions for that project stop.

## Services, health and recovery

```bash
hermes-autodev portal status
hermes-autodev portal restart
hermes-autodev gateway status
hermes-autodev doctor --project-slug product
curl --fail http://127.0.0.1:8787/healthz
journalctl --user -u hermes-autodev-portal.service -n 100
```

`/healthz` verifies the web process/database, not model-provider availability. The workspace separately shows delivery failures and stale Hermes snapshots. The bridge retries deliveries with exponential backoff, capped at 15 minutes, using the same idempotency key after a lost response or restart. It never marks a ticket resolved merely because Hermes accepted a task.

`hermes-autodev portal sync` runs a manual synchronization pass. A file lock prevents overlap with the service worker. `hermes-autodev portal projects` shows synchronization/evidence details as JSON. The service normally refreshes every 30 seconds plus command execution time; snapshots older than three minutes cannot indicate readiness.

After installation, verify persistence on the real server: disconnect SSH, revisit the website, reboot during an agreed window, and check both portal and PM gateway health. The PM gateway must use a real systemd service in production; its documented background fallback does not survive reboot. HTTPS certificate issuance, live model behavior and boot persistence cannot be verified merely by the local fake-Hermes tests.

The SQLite store lives at `~/.hermes/autodev/portal.sqlite` (or the configured state root). Back up the database with SQLite's online backup API:

```bash
hermes-autodev portal backup /safe/external/location/portal-2026-10-04.sqlite
```

Lifecycle update/uninstall backups also create a consistent `.portal.sqlite` sidecar beside the Hermes archive, including when the portal has a custom state directory. Keep both artifacts, `portal.json`, the Caddy configuration, the profile/project state and provider credentials in your normal protected backup system. The portal virtual environment can be rebuilt from `portal/requirements.txt`.

To restore a portal snapshot, stop the portal **and any agents writing support/evidence**, preserve the current database and its `-wal`/`-shm` files, then replace the database with the snapshot using mode `0600`. Remove the old WAL/SHM sidecars only after stopping writers. Start the service and verify tickets and account access. Restoring an old database can restore unexpired login sessions; revoke them by resetting accounts or clearing the `sessions` table offline. Existing tracking links remain valid for tickets in that backup.

`hermes-autodev update` refreshes portal dependencies and restarts it if it was running. Uninstall stops its user service and removes package runtime state after backup; project repositories stay intact. A system-level Caddy configuration and DNS are operator-owned and remain; remove the site's proxy block when retiring it. Custom state roots follow the package's existing retention behavior.

## Local preview and tests

The complete Hermes installation lifecycle targets Linux. The portal itself can be developed on macOS using its Python module directly:

```bash
python3 -m venv /tmp/autodev-test-venv
/tmp/autodev-test-venv/bin/pip install -r portal/requirements-dev.txt
/tmp/autodev-test-venv/bin/python -m playwright install chromium
AUTODEV_BROWSER_TESTS=1 /tmp/autodev-test-venv/bin/python -m pytest -q tests/test_portal.py tests/test_portal_browser.py
```

For a local preview, set `HERMES_AUTODEV_STATE_DIR` to a private scratch directory, use `python -m portal.cli register` and `user` to prepare it, then `python -m portal.cli serve --local`. This binds only loopback and deliberately uses HTTP cookies for local development. HTTPS is mandatory for a public origin.

The integration uses Hermes' documented [Kanban CLI and named profiles](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban), and the web process follows FastAPI's [ASGI server deployment model](https://fastapi.tiangolo.com/deployment/manually/). Runtime requirements are pinned to tested versions; review and retest upgrades intentionally.
