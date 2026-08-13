#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
YES=0
BACKUP=1
REMOVE_HERMES=0
FULL_HERMES=0
REMOVE_CHECKOUT=0

usage() {
  cat <<'EOF'
Usage:
  hermes-autodev uninstall [options]

Removes the autonomous development team profiles, services, generated project
configuration, watchdogs, and installed lifecycle command. Project repositories
and shared Git/GitHub/GitLab/Codex credentials are never deleted.

By default, a full Hermes backup is created outside HERMES_HOME. Project records,
boards, sessions, auth, and cron state leave the live installation with their
owning profiles and can be recovered from that backup.

Options:
  --dry-run          Print exact targets without changing anything.
  -y, --yes          Skip the typed confirmation.
  --no-backup        Do not create a pre-uninstall backup.
  --remove-hermes    Also uninstall Hermes, preserving other Hermes data.
  --full-hermes      Also uninstall Hermes and all remaining Hermes data.
  --remove-checkout  Delete this package Git checkout as the final step.
  -h, --help         Show this help.

Recommended first command:
  hermes-autodev uninstall --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) YES=1; shift ;;
    --no-backup) BACKUP=0; shift ;;
    --remove-hermes) REMOVE_HERMES=1; shift ;;
    --full-hermes)
      REMOVE_HERMES=1
      FULL_HERMES=1
      shift
      ;;
    --remove-checkout) REMOVE_CHECKOUT=1; shift ;;
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

autodev_require_linux
if [[ "${REMOVE_HERMES}" -eq 1 ]] && ! command -v hermes >/dev/null 2>&1; then
  autodev_die \
    "Hermes removal was requested, but the hermes command is unavailable. Restore it to PATH or omit --remove-hermes/--full-hermes."
fi
HERMES_HOME_DIR="$(readlink -m "${HERMES_HOME:-${HOME}/.hermes}")"
case "${HERMES_HOME_DIR}" in
  /|/home|/root|"$(readlink -m "${HOME}")")
    autodev_die "refusing to use an unsafe HERMES_HOME for removal: ${HERMES_HOME_DIR}"
    ;;
esac
PROJECT_CONFIG_DIR="${HERMES_HOME_DIR}/autodev/projects"

# Hermes creates profile aliases as two-line POSIX wrappers in ~/.local/bin.
# Only recognize that exact shape so fallback cleanup can never remove an
# unrelated executable that happens to share one of the team profile names.
autodev_is_team_profile_wrapper() {
  local profile="$1"
  local wrapper="${HOME}/.local/bin/${profile}"
  local first_line="" exec_line="" command_part="" suffix=""

  [[ " ${AUTODEV_TEAM_PROFILES[*]} " == *" ${profile} "* ]] || return 1
  [[ -f "${wrapper}" && ! -L "${wrapper}" ]] || return 1
  [[ "$(wc -c < "${wrapper}")" -le 8192 ]] || return 1

  IFS= read -r first_line < "${wrapper}" || return 1
  exec_line="$(sed -n '2p' "${wrapper}")"
  [[ "${first_line}" == '#!/bin/sh' ]] || return 1
  [[ -z "$(sed -n '3,$p' "${wrapper}" | tr -d '[:space:]')" ]] || return 1

  suffix=" -p ${profile} \"\$@\""
  [[ "${exec_line}" == exec\ *"${suffix}" ]] || return 1
  command_part="${exec_line#exec }"
  command_part="${command_part%"${suffix}"}"
  command_part="${command_part#\'}"
  command_part="${command_part%\'}"
  [[ "${command_part}" == "hermes" || "${command_part}" == */hermes ]]
}

team_aliases=()
for profile in "${AUTODEV_TEAM_PROFILES[@]}"; do
  if autodev_is_team_profile_wrapper "${profile}"; then
    team_aliases+=("${HOME}/.local/bin/${profile}")
  fi
done

mapfile -t project_configs < <(find "${PROJECT_CONFIG_DIR}" -maxdepth 1 -type f -name '*.env' -print 2>/dev/null | sort)
project_boards=()
for config in "${project_configs[@]}"; do
  board="$(sed -n 's/^HERMES_AUTODEV_BOARD=\([A-Za-z0-9_-][A-Za-z0-9_-]*\)$/\1/p' "${config}" | head -n 1)"
  [[ -n "${board}" && "${board}" != "default" ]] && project_boards+=("${board}")
done

cat <<EOF
Autonomous dev team uninstall preview

Profiles:
  ${AUTODEV_TEAM_PROFILES[*]}
Services:
  Project Manager gateway
  Hermes autonomous-dev dashboard service/background process
Generated state:
  ${HERMES_HOME_DIR}/autodev
  ${HERMES_HOME_DIR}/scripts/hermes_autodev_watchdog_common.sh
  ${HERMES_HOME_DIR}/scripts/autodev_watchdog_*.sh
  $(autodev_install_pointer)
  ${HOME}/.local/bin/hermes-autodev
Project configs found: ${#project_configs[@]}
Package boards found: ${#project_boards[@]}
Profile command aliases recognized: ${#team_aliases[@]}
Profile runtime data: removed from live Hermes; retained in the external backup
Backup: $([[ "${BACKUP}" -eq 1 ]] && printf 'full backup outside HERMES_HOME' || printf 'disabled')
Remove Hermes: $([[ "${REMOVE_HERMES}" -eq 1 ]] && printf 'yes' || printf 'no')
Remove package checkout: $([[ "${REMOVE_CHECKOUT}" -eq 1 ]] && printf '%s' "${ROOT_DIR}" || printf 'no')

Always preserved:
  Application project repositories
  Shared Git configuration and SSH keys
  gh, glab, Claude, and Codex logins
EOF

if [[ "${#project_boards[@]}" -gt 0 ]]; then
  printf 'Boards:\n'
  printf '  %s\n' "${project_boards[@]}"
fi
if [[ "${#team_aliases[@]}" -gt 0 ]]; then
  printf 'Profile aliases:\n'
  printf '  %s\n' "${team_aliases[@]}"
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo
  echo "Dry run complete; nothing was changed."
  exit 0
fi

if [[ "${YES}" -ne 1 ]]; then
  autodev_has_tty || autodev_die "a terminal is required for confirmation; pass --yes for unattended removal."
  echo
  printf 'Type uninstall to continue: '
  read -r confirmation
  [[ "${confirmation}" == "uninstall" ]] || { echo "Uninstall cancelled."; exit 0; }
fi

if [[ "${BACKUP}" -eq 1 && -d "${HERMES_HOME_DIR}" ]]; then
  bash "${ROOT_DIR}/scripts/backup-runtime.sh" --full
fi

bash "${ROOT_DIR}/scripts/dashboard.sh" uninstall-service || autodev_die \
  "the dashboard could not be stopped safely; resolve the reported process/service issue and retry."
bash "${ROOT_DIR}/scripts/gateway.sh" stop || autodev_die \
  "the Project Manager gateway could not be stopped safely; resolve it and retry."

for profile in security-tester tester developer frontend-designer project-manager; do
  profile_dir="${HERMES_HOME_DIR}/profiles/${profile}"
  [[ -d "${profile_dir}" ]] || continue
  if command -v hermes >/dev/null 2>&1 && hermes profile delete "${profile}" --yes; then
    continue
  fi
  autodev_path_is_within "${profile_dir}" "${HERMES_HOME_DIR}/profiles" || autodev_die \
    "refusing to remove unexpected profile path: ${profile_dir}"
  rm -rf -- "${profile_dir}"
done

# Current Hermes removes its own aliases during `profile delete`. If Hermes is
# missing or profile deletion failed, remove only wrappers that still match the
# exact Hermes-generated command for the corresponding package profile.
for profile in "${AUTODEV_TEAM_PROFILES[@]}"; do
  if autodev_is_team_profile_wrapper "${profile}"; then
    rm -f -- "${HOME}/.local/bin/${profile}"
  fi
done

scripts_dir="${HERMES_HOME_DIR}/scripts"
if [[ -d "${scripts_dir}" ]]; then
  autodev_path_is_within "${scripts_dir}" "${HERMES_HOME_DIR}" || autodev_die \
    "refusing to clean an unexpected scripts path: ${scripts_dir}"
  find "${scripts_dir}" -maxdepth 1 -type f \
    \( -name 'autodev_watchdog_*.sh' -o -name 'hermes_autodev_watchdog_common.sh' \) \
    -delete
fi

if [[ -d "${HERMES_HOME_DIR}/autodev" ]]; then
  autodev_path_is_within "${HERMES_HOME_DIR}/autodev" "${HERMES_HOME_DIR}" || autodev_die \
    "refusing to remove unexpected state path: ${HERMES_HOME_DIR}/autodev"
  rm -rf -- "${HERMES_HOME_DIR}/autodev"
fi
install_pointer="$(autodev_install_pointer)"
rm -f "${install_pointer}" "${HOME}/.local/bin/hermes-autodev"
rmdir "$(dirname "${install_pointer}")" 2>/dev/null || true

if [[ "${REMOVE_HERMES}" -eq 1 ]] && command -v hermes >/dev/null 2>&1; then
  hermes_args=(--yes)
  [[ "${FULL_HERMES}" -eq 1 ]] && hermes_args+=(--full)
  hermes uninstall "${hermes_args[@]}"
fi

echo "Autonomous dev team package removed."
echo "Backups, if enabled, remain under $(autodev_external_state_dir)/backups."

if [[ "${REMOVE_CHECKOUT}" -eq 1 ]]; then
  root_abs="$(readlink -m "${ROOT_DIR}")"
  home_abs="$(readlink -m "${HOME}")"
  [[ "${root_abs}" != "/" && "${root_abs}" != "${home_abs}" ]] || autodev_die \
    "refusing to delete an unsafe checkout path: ${root_abs}"
  checkout_top="$(git -C "${root_abs}" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -f "${root_abs}/VERSION" && -f "${root_abs}/autodev.sh" && "$(readlink -m "${checkout_top:-/not-this-checkout}")" == "${root_abs}" ]] || autodev_die \
    "refusing to delete a directory that is not the expected package checkout: ${root_abs}"
  echo "Removing package checkout: ${root_abs}"
  rm -rf -- "${root_abs}"
fi
