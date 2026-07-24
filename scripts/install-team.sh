#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

INSTALL_HERMES=auto
FORCE=0
YES=0
SETUP_PROJECT_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [options]

Installs the reusable Hermes autonomous development team profiles:
  - project-manager
  - frontend-designer
  - developer
  - tester
  - security-tester

Options:
  --install-hermes        Install Hermes if the hermes command is missing.
  --no-install-hermes     Do not install Hermes automatically.
  --force                 Reinstall profiles with --force.
  -y, --yes               Skip Hermes profile install confirmations.
  --project-path PATH     Also bootstrap a project board for PATH.
  --project-slug SLUG     Project board slug. Defaults to basename(PATH).
  --project-name NAME     Human-readable board name. Defaults to slug title.
  --project-description X Board description.
  --repo-url URL          Clone URL if --project-path does not exist.
  --cron                  Create/resume project watchdog and PM sweep cron jobs.
  --no-cron               Do not create project cron jobs.
  --deliver TARGET        PM sweep delivery target, e.g. local, telegram,
                          signal:+15551234567. Defaults to local.
  --start-gateway         Start the project-manager gateway after setup.
  --no-start-gateway      Do not start the gateway.
  -h, --help              Show this help.

Examples:
  ./install.sh -y
  ./install.sh -y --project-path /srv/my-app --cron --start-gateway
  ./install.sh -y --repo-url git@github.com:org/app.git --project-path /srv/app --cron
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-hermes)
      INSTALL_HERMES=yes
      shift
      ;;
    --no-install-hermes)
      INSTALL_HERMES=no
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -y|--yes)
      YES=1
      shift
      ;;
    --project-path|--project-slug|--project-name|--project-description|--repo-url|--deliver)
      SETUP_PROJECT_ARGS+=("$1" "$2")
      shift 2
      ;;
    --cron|--no-cron|--start-gateway|--no-start-gateway)
      SETUP_PROJECT_ARGS+=("$1")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

need_command() {
  command -v "$1" >/dev/null 2>&1
}

if ! need_command hermes; then
  if [[ "${INSTALL_HERMES}" == "no" ]]; then
    echo "hermes command not found. Install Hermes first or pass --install-hermes." >&2
    exit 1
  fi
  echo "Installing Hermes Agent using the official installer..."
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
  export PATH="${HOME}/.local/bin:${PATH}"
fi

if ! need_command hermes; then
  echo "hermes command still not found after install attempt. Reload your shell and retry." >&2
  exit 1
fi

profile_install_args=()
if [[ "${FORCE}" -eq 1 ]]; then
  profile_install_args+=(--force)
fi
if [[ "${YES}" -eq 1 ]]; then
  profile_install_args=(-y "${profile_install_args[@]}")
fi

echo "Installing autonomous dev team profiles from ${ROOT_DIR}"
hermes profile install "${ROOT_DIR}/project-manager" --name project-manager --alias "${profile_install_args[@]}"
hermes profile install "${ROOT_DIR}/frontend-designer" --name frontend-designer --alias "${profile_install_args[@]}"
hermes profile install "${ROOT_DIR}/developer" --name developer --alias "${profile_install_args[@]}"
hermes profile install "${ROOT_DIR}/tester" --name tester --alias "${profile_install_args[@]}"
hermes profile install "${ROOT_DIR}/security-tester" --name security-tester --alias "${profile_install_args[@]}"

# Hermes reserves profile-level bin/ as runtime-owned, so install the Codex
# launcher explicitly instead of relying on profile distribution copying.
mkdir -p "${HOME}/.hermes/profiles/developer/bin"
install -m 0755 "${ROOT_DIR}/developer/bin/codex-network-exec" \
  "${HOME}/.hermes/profiles/developer/bin/codex-network-exec"

mkdir -p "${HOME}/.hermes/scripts" "${HOME}/.hermes/autodev/projects"
install -m 0755 "${ROOT_DIR}/scripts/hermes_autodev_watchdog_common.sh" \
  "${HOME}/.hermes/scripts/hermes_autodev_watchdog_common.sh"

for profile in project-manager frontend-designer developer tester security-tester; do
  env_example="${HOME}/.hermes/profiles/${profile}/.env.EXAMPLE"
  env_file="${HOME}/.hermes/profiles/${profile}/.env"
  if [[ -f "${env_example}" && ! -f "${env_file}" ]]; then
    cp "${env_example}" "${env_file}"
    chmod 0600 "${env_file}" || true
    echo "Created ${env_file} from .env.EXAMPLE; fill credentials before unattended runs."
  fi
done

if [[ "${#SETUP_PROJECT_ARGS[@]}" -gt 0 ]]; then
  "${ROOT_DIR}/scripts/setup-project.sh" "${SETUP_PROJECT_ARGS[@]}"
else
  cat <<EOF

Profiles installed.

Next:
  1. Run the client setup wizard to configure credentials and optional project bootstrap:
       ${ROOT_DIR}/wizard.sh
  2. Or bootstrap a project directly:
       ${ROOT_DIR}/scripts/setup-project.sh \\
         --project-path /absolute/path/to/repo \\
         --project-slug my-project \\
         --cron \\
         --start-gateway
EOF
fi
