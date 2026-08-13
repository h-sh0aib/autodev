#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

INSTALL_HERMES=auto
UPDATE_HERMES=auto
FORCE=0
YES=0
SETUP_PROJECT_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  bash ./install.sh [options]

Installs or safely refreshes these Hermes profiles:
  - project-manager
  - frontend-designer
  - developer
  - tester
  - security-tester

Options:
  --install-hermes        Install Hermes if the hermes command is missing.
  --no-install-hermes     Do not install Hermes automatically.
  --update-hermes         Update Hermes even when its version is supported.
  --no-update-hermes      Never update an existing Hermes installation.
  --force                 Reset package-owned profile config to source defaults.
                          Without this flag, existing config/auth/data are preserved.
  -y, --yes               Skip Hermes profile install confirmations.
  --project-path PATH     Also bootstrap a project board for PATH.
  --project-slug SLUG     Project board slug. Defaults to basename(PATH).
  --project-name NAME     Human-readable board name. Defaults to slug title.
  --project-description X Board description.
  --repo-url URL          Clone URL if --project-path does not exist.
  --scm-provider NAME     Repository host: auto, github, gitlab, or generic.
  --cron                  Create/resume project watchdog and PM sweep cron jobs.
  --no-cron               Do not create project cron jobs.
  --deliver TARGET        PM sweep delivery target, e.g. local or telegram.
  --start-gateway         Start the project-manager gateway after setup.
  --no-start-gateway      Do not start the gateway.
  -h, --help              Show this help.

Examples:
  bash ./install.sh -y
  bash ./install.sh -y --project-path /srv/my-app --cron --start-gateway
  bash ./install.sh -y --repo-url git@github.com:org/app.git --project-path /srv/app --cron
  bash ./install.sh -y --repo-url git@gitlab.com:group/app.git --project-path /srv/app --scm-provider gitlab --cron
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
    --update-hermes)
      UPDATE_HERMES=yes
      shift
      ;;
    --no-update-hermes)
      UPDATE_HERMES=no
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
    --project-path|--project-slug|--project-name|--project-description|--repo-url|--scm-provider|--deliver)
      [[ $# -ge 2 ]] || autodev_die "$1 requires a value."
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

autodev_require_linux

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Warning: installing as root places profiles and credentials under /root." >&2
  echo "A dedicated unprivileged Linux account is recommended for autonomous agents." >&2
fi

for required_command in git curl; do
  need_command "${required_command}" || autodev_die \
    "${required_command} is required. On Debian/Ubuntu: sudo apt install git curl xz-utils"
done

install_hermes_official() {
  need_command xz || autodev_die \
    "xz is required by the Hermes installer. On Debian/Ubuntu: sudo apt install xz-utils"

  local installer
  installer="$(mktemp)"
  if ! curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o "${installer}"; then
    rm -f "${installer}"
    autodev_die "failed to download the official Hermes installer."
  fi

  local installer_args=(--skip-setup)
  [[ "${YES}" -eq 1 ]] && installer_args+=(--non-interactive)
  if ! bash "${installer}" "${installer_args[@]}"; then
    rm -f "${installer}"
    autodev_die "the official Hermes installer failed."
  fi
  rm -f "${installer}"
  export PATH="${HOME}/.local/bin:${PATH}"
}

if ! need_command hermes; then
  if [[ "${INSTALL_HERMES}" == "no" ]]; then
    autodev_die "hermes is not installed. Remove --no-install-hermes or install Hermes first."
  fi
  echo "Installing Hermes Agent ${AUTODEV_MIN_HERMES_VERSION}+ using the official installer..."
  install_hermes_official
fi

need_command hermes || autodev_die \
  "hermes is still unavailable after installation. Add ${HOME}/.local/bin to PATH and retry."

installed_hermes_version="$(autodev_hermes_version || true)"
should_update_hermes=0
if [[ "${UPDATE_HERMES}" == "yes" ]]; then
  should_update_hermes=1
elif [[ "${UPDATE_HERMES}" == "auto" ]] && ! autodev_version_at_least \
  "${installed_hermes_version}" "${AUTODEV_MIN_HERMES_VERSION}"; then
  should_update_hermes=1
fi

if [[ "${should_update_hermes}" -eq 1 ]]; then
  echo "Updating Hermes Agent before installing profiles..."
  if ! hermes update --backup --yes; then
    echo "Hermes' updater did not complete; retrying through the official installer." >&2
    install_hermes_official
  fi
fi

installed_hermes_version="$(autodev_hermes_version || true)"
if ! autodev_version_at_least "${installed_hermes_version}" "${AUTODEV_MIN_HERMES_VERSION}"; then
  autodev_die "Hermes ${AUTODEV_MIN_HERMES_VERSION}+ is required; found ${installed_hermes_version:-unknown}."
fi

install_or_update_profile() {
  local profile="$1"
  local source_dir="${ROOT_DIR}/${profile}"
  local profile_dir
  profile_dir="$(autodev_profile_dir "${profile}")"
  local yes_args=()
  [[ "${YES}" -eq 1 ]] && yes_args=(-y)

  if [[ ! -d "${profile_dir}" ]]; then
    hermes profile install "${source_dir}" --name "${profile}" --alias "${yes_args[@]}"
    return 0
  fi

  if [[ "${FORCE}" -eq 1 ]]; then
    hermes profile install "${source_dir}" --name "${profile}" --alias --force "${yes_args[@]}"
    return 0
  fi

  if hermes profile update "${profile}" "${yes_args[@]}"; then
    hermes profile alias "${profile}" --name "${profile}" >/dev/null 2>&1 || true
    return 0
  fi

  echo "Recorded distribution source for ${profile} is unavailable; rebinding it to this checkout while preserving config.yaml." >&2
  local saved_config=""
  if [[ -f "${profile_dir}/config.yaml" ]]; then
    saved_config="$(mktemp)"
    cp "${profile_dir}/config.yaml" "${saved_config}"
  fi
  hermes profile install "${source_dir}" --name "${profile}" --alias --force "${yes_args[@]}"
  if [[ -n "${saved_config}" ]]; then
    install -m 0600 "${saved_config}" "${profile_dir}/config.yaml"
    rm -f "${saved_config}"
  fi
}

package_version="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
echo "Installing autonomous dev team ${package_version} profiles from ${ROOT_DIR}"
for profile in "${AUTODEV_TEAM_PROFILES[@]}"; do
  install_or_update_profile "${profile}"
done

# Hermes reserves profile-level bin/ as runtime-owned, so install the Codex
# launcher explicitly instead of relying on profile distribution copying.
HERMES_HOME_DIR="$(autodev_hermes_home)"
mkdir -p "$(autodev_profile_dir developer)/bin"
autodev_install_executable "${ROOT_DIR}/developer/bin/codex-network-exec" \
  "$(autodev_profile_dir developer)/bin/codex-network-exec"

mkdir -p "${HERMES_HOME_DIR}/scripts" "${HERMES_HOME_DIR}/autodev/projects"
chmod 0700 "${HERMES_HOME_DIR}/autodev" "${HERMES_HOME_DIR}/autodev/projects" 2>/dev/null || true
autodev_install_executable "${ROOT_DIR}/scripts/hermes_autodev_watchdog_common.sh" \
  "${HERMES_HOME_DIR}/scripts/hermes_autodev_watchdog_common.sh"

for profile in "${AUTODEV_TEAM_PROFILES[@]}"; do
  env_example="$(autodev_profile_dir "${profile}")/.env.EXAMPLE"
  env_file="$(autodev_profile_dir "${profile}")/.env"
  if [[ -f "${env_example}" && ! -f "${env_file}" ]]; then
    cp "${env_example}" "${env_file}"
    chmod 0600 "${env_file}" || true
    echo "Created ${env_file} from .env.EXAMPLE; fill credentials before unattended runs."
  fi
done

mkdir -p "${HOME}/.local/bin"
autodev_install_executable "${ROOT_DIR}/scripts/hermes-autodev-launcher.sh" \
  "${HOME}/.local/bin/hermes-autodev"

package_commit="$(git -C "${ROOT_DIR}" rev-parse HEAD 2>/dev/null || printf 'unknown')"
package_branch="$(git -C "${ROOT_DIR}" branch --show-current 2>/dev/null || printf 'unknown')"
install_metadata=(
  "HERMES_AUTODEV_PACKAGE_ROOT=${ROOT_DIR}" \
  "HERMES_AUTODEV_PACKAGE_VERSION=${package_version}" \
  "HERMES_AUTODEV_PACKAGE_COMMIT=${package_commit}" \
  "HERMES_AUTODEV_PACKAGE_BRANCH=${package_branch}" \
  "HERMES_AUTODEV_INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "HERMES_AUTODEV_SCHEMA_VERSION=3" \
  "HERMES_AUTODEV_HERMES_HOME=${HERMES_HOME_DIR}" \
  "HERMES_AUTODEV_STATE_DIR_VALUE=$(autodev_state_dir)"
)
autodev_write_env_file "${HERMES_HOME_DIR}/autodev/install.env" "${install_metadata[@]}"
autodev_write_env_file "$(autodev_install_pointer)" "${install_metadata[@]}"

if [[ "${#SETUP_PROJECT_ARGS[@]}" -gt 0 ]]; then
  bash "${ROOT_DIR}/scripts/setup-project.sh" "${SETUP_PROJECT_ARGS[@]}"
else
  cat <<EOF

Profiles installed or refreshed safely.

Next:
  1. Run the guided setup:
       bash "${ROOT_DIR}/wizard.sh"
  2. Or open the GUI after configuration:
       hermes-autodev dashboard open
  3. Run lifecycle commands from any directory:
       hermes-autodev help
EOF
fi
