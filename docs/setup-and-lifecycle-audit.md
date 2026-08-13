# Setup, GUI, and Lifecycle Audit

Audit target: autonomous development team package 1.5.0. The review covered the
entrypoints, installer, wizard, project bootstrap, watchdog, gateway startup,
diagnostics, documentation, and the supported Hermes lifecycle commands.

## Executive assessment

The original package was functional for an experienced operator on one Linux
VPS, but it was not yet a dependable installable product. Its happy path mixed
installation, configuration, and project bootstrap; it assumed a system
`python3`; it reset distribution-owned profile configuration too readily; and it
had no first-class GUI, update, backup, or uninstall lifecycle.

Version 1.5.0 changes the product boundary. There is now one command router,
preservation-first installation, explicit environment detection, local/SSH GUI
management, service fallbacks, lifecycle metadata, guarded update/uninstall
commands, and a doctor that checks the whole installed system.

## Findings and resolutions

### Critical: repeated setup could reset profile configuration

The wizard previously started with forced profile installation enabled. That
made the easiest documented command the most invasive refresh path and could
replace a user's provider/model configuration.

Resolution:

- Existing distributions use `hermes profile update`, which preserves local
  `config.yaml`, `.env`, auth, sessions, memories, and other user data.
- New installs use the normal distribution installer.
- `--force` is now an explicit repair/reset option and is described as such.
- If a local distribution source must be rebound, the installer snapshots and
  restores `config.yaml` around the forced rebind.

### High: an old Hermes install was accepted indefinitely

The former installer only installed Hermes when the command was absent. An
existing release could lack the dashboard, current profile-update semantics, or
other CLI behavior used by the package.

Resolution:

- Every distribution declares Hermes `>=2026.8.3`, the first stable release
  this package accepts with the current fail-closed dashboard authentication
  and unified machine-level dashboard lifecycle.
- The installer detects semantic versions and upgrades an unsupported release.
- Operators can request an update every run or deliberately suppress an update.
- Downloads use the current official Hermes installer endpoint and a temporary
  file, so HTTP failures are detected before executing anything.

### High: no complete GUI path

The package documented Kanban and gateway commands but did not install, start,
secure, or explain the Hermes web dashboard. This left non-terminal operators
without a usable control plane.

Resolution:

- The wizard configures Hermes' built-in multi-profile dashboard.
- The GUI covers browser chat, profiles, Kanban, cron, API keys, models, skills,
  and MCP configuration without introducing a second source of truth.
- Project bootstrap creates a first-class Hermes Project in every team profile,
  points each at the primary repository, and binds the PM copy to its Kanban
  board. GUI/Desktop project context therefore survives profile switching while
  coordination and deterministic task worktrees remain anchored to the PM board.
- Local, WSL2, SSH, and container environments are detected.
- The manager binds only to `127.0.0.1`. SSH users receive an exact tunnel
  command; public binding is intentionally not offered.
- The dashboard can use a systemd user service and emits a lingering reminder on
  remote hosts. A PID/log-managed background fallback covers hosts without a
  working user systemd bus.

### High: update and uninstall were informal instructions

The prior update path was essentially `git pull` followed by another forced
install. There was no backup, dirty-tree protection, rollback artifact, service
restart, complete removal, or list of data that would survive.

Resolution:

- `update.sh` checks versions, refuses to overwrite a dirty checkout, creates a
  private backup, uses the supported Hermes updater, fast-forwards the package,
  refreshes profiles safely, restores GUI state, and runs diagnostics.
- `uninstall.sh --dry-run` lists exact targets without changes.
- Normal uninstall creates a full backup outside `~/.hermes`, stops services,
  removes only the five known profiles and package-generated state, and
  preserves application repositories and shared developer credentials.
- If Hermes cannot delete a profile itself, fallback cleanup removes only a
  profile-named alias whose contents exactly match Hermes' generated two-line
  wrapper; a same-named unrelated executable is preserved.
- Projects and boards owned by the removed Project Manager profile leave the
  live installation with that profile and remain recoverable from the backup.
- Hermes removal, full Hermes-data removal, and checkout deletion require
  separate explicit flags.

### Medium: local and remote environments were conflated

Prompts and docs assumed a VPS, while interactive behavior only checked some
prompt types for a TTY. Browser startup and long-running-process behavior were
not environment aware.

Resolution:

- Setup reports `linux-local`, `linux-ssh`, `wsl-local`, `wsl-ssh`, or
  `container` and rejects unsupported native shells early.
- A terminal-less invocation automatically switches to non-interactive behavior
  and points to the config-file workflow.
- Interactivity is captured before setup logging redirects standard output;
  otherwise a real local or SSH terminal would be misclassified as headless.
- Every text, yes/no, and choice prompt has a TTY guard.
- Choice prompts provide a numbered menu while still accepting stable string
  values in config files.
- Root installs remain possible but receive an explicit risk warning; a
  dedicated unprivileged account is the documented default.

### Medium: bootstrap rejected valid Git layouts

The project script required an absolute path and a physical `.git` directory.
That rejected convenient relative/`~/` inputs and valid Git worktrees, whose
`.git` entry is a file.

Resolution:

- Absolute, relative, and `~/` paths are normalized.
- Git itself validates the worktree and supplies the actual checkout root.
- The common watchdog uses the same Git-native validation.
- GitHub, GitLab.com, and self-managed GitLab remain selectable; origin-based
  auto-detection is retained.

### Medium: system Python was an undocumented dependency

Several scripts invoked `python3` directly even though Hermes may have installed
and managed a usable Python environment of its own.

Resolution:

- Shared discovery prefers an explicit override and then the exact interpreter
  reported or launched by Hermes before falling back to system Python.
- Dashboard extras are always checked and installed in Hermes' interpreter,
  avoiding externally managed system-Python failures and false-positive installs
  that the Hermes process could not import.
- Wizard, project rendering, and doctor parsing use that one resolver.
- Missing Python now produces one actionable error instead of a command-not-found
  failure halfway through configuration.
- A stable owner-only install pointer under `~/.config/hermes-autodev` restores
  custom `HERMES_HOME` and state locations in fresh shells; update, doctor, GUI,
  and uninstall no longer depend on a transient export from the install shell.

### Medium: gateway startup was not portable

Project setup called Hermes' service start directly and merely printed a
foreground fallback when user systemd was unavailable.

Resolution:

- `autodev.sh gateway` first uses the supported Hermes service command.
- If it cannot create a managed service, it starts the documented foreground
  runner under a guarded owner PID/log manager.
- Stop/status validate a recorded PID's command before signaling it.

### High: the Developer launcher used a retired Codex CLI argument layout

The previous launcher passed `--ask-for-approval` after `codex exec`. Current
Codex exposes approval policy as a global option, so unattended Developer runs
could fail during argument parsing before reading the task prompt.

Resolution:

- The launcher now uses `codex --ask-for-approval never exec ...` and the
  bundled role instructions use the same current form.
- The wizard can install Codex from OpenAI's official Linux installer and can
  complete ChatGPT browser/device login or API-key login.
- The doctor checks `codex login status` (or the configured API-key path), and
  the lifecycle smoke test executes the installed launcher against a fake CLI.

### Medium: Windows-origin checkouts could break Linux launchers

The extensionless `codex-network-exec` file was not covered by the package's
`*.sh` line-ending rule. A Windows checkout could therefore install a CRLF
shebang onto WSL or a remote Linux host.

Resolution:

- `.gitattributes` pins the extensionless launcher to LF.
- Executable installation normalizes CRLF defensively, so copied archives and
  older Windows clones are repaired during setup.
- The documented bootstrap uses `bash ./wizard.sh`; after setup, the normalized
  `hermes-autodev` command is the only entrypoint users need.

### Medium: configured did not necessarily mean authenticated

The old doctor accepted a provider/model pair without checking its credentials,
and it only warned when Codex was absent.

Resolution:

- Doctor verifies provider auth for all five profiles and Codex CLI auth for
  the Developer lane.
- Project checks validate GitHub/GitLab CLI login or a REST token without
  printing secrets.
- When the wizard's final doctor finds a required failure, setup exits
  nonzero with a repair command instead of announcing a ready installation.

### High: profile credentials and shell state used different file grammars

Profile `.env` files are parsed by Hermes with `python-dotenv`, while package
state files are sourced by Bash. Treating both as shell files corrupted valid
dotenv values containing apostrophes and made uncommon paths or secrets fail in
ways that looked like authentication errors.

Resolution:

- Profile values use dotenv-native single-quote/backslash escaping and a shared
  compatible reader; shell-sourced state continues to use Bash `%q` encoding.
- Regression coverage round-trips spaces, apostrophes, dollar-safe values, and
  a custom `HERMES_HOME` whose path contains both spaces and an apostrophe.
- Credential, model, project-state, launcher, and service-unit updates publish
  through same-directory temporary files so an interrupted SSH session cannot
  expose a partially written configuration.

### Medium: repository-host detection inspected the whole remote URL

A GitLab repository path containing text such as `github.com-mirror` could be
mistaken for GitHub because the former detector searched the full remote.

Resolution:

- Project bootstrap now parses and records the remote hostname separately.
- Provider detection compares only that hostname, including the configured
  self-managed GitLab host; GitHub/GitLab workflow guidance does the same.
- The lifecycle test uses an adversarial GitLab path containing `github.com`.

### Medium: GUI project context existed only for Project Manager

Hermes Projects are profile-scoped. Registering a repository only under the PM
meant the project disappeared from the dashboard when the operator switched to
Developer, Tester, Security Tester, or Frontend Designer.

Resolution:

- Project bootstrap idempotently registers the same repository and project slug
  in all five profiles.
- The PM copy remains the sole Kanban-board binding and coordination owner.
- Doctor verifies all five GUI registrations.

## Supported operating matrix

| Host | Setup | GUI access | Persistence |
| --- | --- | --- | --- |
| Linux desktop/laptop | interactive or config file | local loopback browser | optional user service |
| WSL2 | interactive or config file | Windows browser through loopback | optional user service/background fallback |
| Linux over SSH | interactive or config file | SSH local-forward tunnel | user service with lingering, or fallback |
| Linux container (advanced) | config file recommended | tunnel from inside its network namespace | container supervisor |

Native macOS and native Windows shells are outside this release's support
boundary. A macOS user can operate a remote Linux installation over SSH; a
Windows user can use WSL2 or SSH.

## Remaining boundaries

- Installing system prerequisites still belongs to the operating system. The
  package reports the Debian/Ubuntu command but does not silently run `sudo` or
  mutate firewall policy.
- OAuth requires an interactive browser/device authorization step. It cannot be
  made safely unattended by placing subscription credentials in a config file.
- A remotely reachable dashboard should remain behind SSH or a trusted VPN. If
  an operator intentionally publishes it through a reverse proxy, TLS and strong
  authentication are their deployment responsibility.
- The dashboard intentionally binds to container loopback too. Ordinary
  `docker -p` forwarding cannot reach that listener; container deployments need
  an in-namespace tunnel or an explicitly designed authenticated proxy.
- Loopback is host-local, not user-local. A multi-user host needs operating
  system isolation or a single-tenant container/VM; the SSH tunnel alone does
  not prevent another local account from connecting to the listener.
- The Developer launcher deliberately uses Codex with approval disabled and
  `danger-full-access`. The dedicated unprivileged account and least-privilege
  repository/cloud credentials are security boundaries, not optional polish.
- Application repositories and repository-host accounts are deliberately not
  uninstalled with the agent package.

## Automated validation

- `tests/static-checks.sh` parses every shell entrypoint, runs ShellCheck when
  available, loads all YAML, verifies the minimum Hermes contract, and scans
  every tracked or unignored text file for whitespace and line-ending defects.
- `tests/smoke-lifecycle.sh` uses isolated temporary homes and fake credentials;
  it exercises safe setup reruns, subscription configuration, GitLab/self-hosted
  hostname detection, linked worktrees, all-profile GUI project registration,
  an actual loopback HTTP health check, SSH/IPv6 access instructions, a real
  fast-forward Git update, external backup, and uninstall preservation.
- The uninstall test deliberately makes Hermes profile deletion fail once to
  verify guarded directory and alias cleanup. Application repositories and a
  linked worktree must still exist afterward.
- `.gitlab-ci.yml` repeats static checks with pinned ShellCheck 0.11.0 and runs
  the lifecycle suite in Debian for pushes and merge requests.

The suite intentionally does not authenticate to a real paid model account,
change a user's live Hermes installation, enable lingering, or install a real
systemd service. Those operations require operator-owned credentials or host
state and remain explicit acceptance checks on the target machine.

## Acceptance commands

```bash
bash ./wizard.sh
hermes-autodev dashboard status
hermes-autodev doctor
hermes-autodev update --check
hermes-autodev uninstall --dry-run
```

For unattended provisioning, copy `setup.example.env`, fill it outside source
control, and run `bash ./wizard.sh --config client.env --non-interactive`.
