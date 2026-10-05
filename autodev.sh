#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  hermes-autodev <command> [options]

Commands:
  setup        Run the guided setup wizard (default).
  install      Install or refresh the seven Hermes profiles.
  project      Add or refresh a project workspace and Kanban board.
  dashboard    Start, stop, configure, or inspect the web GUI.
  portal       Host the public support portal and private team workspace.
  support      Inspect, reply to, and hand off support tickets.
  gateway      Start, stop, restart, or inspect the PM gateway.
  doctor       Check package, profile, project, gateway, and GUI health.
  update       Safely update Hermes, this package, and installed profiles.
  uninstall    Preview or remove the autonomous dev team package.
  version      Print the package version and current Git commit.
  help         Show this help.

Examples:
  hermes-autodev setup
  hermes-autodev dashboard open
  hermes-autodev project --project-path ./my-repo
  hermes-autodev update --check
  hermes-autodev uninstall --dry-run
EOF
}

command_name="${1:-setup}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "${command_name}" in
  setup|wizard)
    exec bash "${ROOT_DIR}/wizard.sh" "$@"
    ;;
  install)
    exec bash "${ROOT_DIR}/install.sh" "$@"
    ;;
  project)
    exec bash "${ROOT_DIR}/scripts/setup-project.sh" "$@"
    ;;
  dashboard|gui)
    exec bash "${ROOT_DIR}/dashboard.sh" "$@"
    ;;
  portal|support)
    exec bash "${ROOT_DIR}/scripts/portal.sh" "$@"
    ;;
  gateway)
    exec bash "${ROOT_DIR}/scripts/gateway.sh" "$@"
    ;;
  doctor)
    exec bash "${ROOT_DIR}/scripts/doctor.sh" "$@"
    ;;
  update)
    exec bash "${ROOT_DIR}/update.sh" "$@"
    ;;
  uninstall|remove)
    exec bash "${ROOT_DIR}/uninstall.sh" "$@"
    ;;
  version)
    version="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
    commit="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
    printf 'Hermes Autonomous Development Team %s (%s)\n' "${version}" "${commit}"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: ${command_name}" >&2
    usage >&2
    exit 2
    ;;
esac
