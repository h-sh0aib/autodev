#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
STATE_DIR="$(autodev_state_dir)"
export HERMES_AUTODEV_STATE_DIR="${STATE_DIR}"
export HERMES_HOME="${HERMES_AUTODEV_HERMES_HOME:-$(autodev_hermes_home)}"
export PYTHONPATH="${ROOT_DIR}${PYTHONPATH:+:${PYTHONPATH}}"
PORTAL_VENV="${STATE_DIR}/portal-venv"
UNIT_DIR="${HOME}/.config/systemd/user"
UNIT_FILE="${UNIT_DIR}/hermes-autodev-portal.service"
ACTION="${1:-help}"
[[ $# -eq 0 ]] || shift

portal_python() {
  if [[ -x "${PORTAL_VENV}/bin/python" ]]; then
    "${PORTAL_VENV}/bin/python" -m portal.cli "$@"
  else
    autodev_python -m portal.cli "$@"
  fi
}

quote_unit() {
  local value="$1"
  [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || autodev_die "service paths cannot contain newlines"
  value="${value//%/%%}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

quote_exec() {
  local value
  value="$(quote_unit "$1")"
  printf '%s' "${value//\$/\$\$}"
}

case "${ACTION}" in
  help|-h|--help)
    cat <<'EOF'
Usage: hermes-autodev portal <action>

  setup --domain team.example.com   Install the web portal and its user service.
  serve --local                    Preview on http://127.0.0.1:8787.
  user USER [--role owner|support|viewer]  Create/reset a login (hidden password prompt).
  start | stop | restart | status   Control the persistent portal service.
  sync                             Retry deliveries and refresh Hermes status.
  projects                         Inspect projects and release evidence as JSON.
  evidence --help                  Record a release check on an exact commit.
  backup /path/portal.sqlite        Create a consistent database snapshot.

Public access uses Caddy HTTPS. The internal Hermes dashboard stays private.
Daily operation is through the website; Linux setup is a one-time operator task.
EOF
    ;;
  setup)
    autodev_require_linux
    autodev_user_systemd_available || autodev_die "a systemd user session is required for production portal hosting"
    domain="${AUTODEV_PORTAL_DOMAIN:-}"
    if [[ "${1:-}" == "--domain" && $# -eq 2 ]]; then
      domain="$2"
    elif [[ $# -ne 0 ]]; then
      autodev_die "usage: hermes-autodev portal setup --domain team.example.com"
    fi
    if [[ -z "${domain}" ]]; then
      autodev_has_tty || autodev_die "supply --domain for non-interactive setup"
      read -r -p "Website address (for example team.example.com): " domain
    fi
    portal_python configure --domain "${domain}"
    autodev_python -m venv "${PORTAL_VENV}"
    "${PORTAL_VENV}/bin/python" -m pip install -r "${ROOT_DIR}/portal/requirements.txt"
    if autodev_has_tty; then
      read -r -p "Owner username to create/reset (blank to keep existing accounts): " username
      [[ -z "${username}" ]] || portal_python user "${username}"
    fi
    mkdir -p "${UNIT_DIR}"
    cat > "${UNIT_FILE}" <<EOF
[Unit]
Description=AutoDev public support portal and private team workspace
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment="PATH=$(quote_unit "${PATH}")"
Environment="HERMES_HOME=$(quote_unit "${HERMES_HOME}")"
Environment="HERMES_AUTODEV_STATE_DIR=$(quote_unit "${STATE_DIR}")"
Environment="PYTHONPATH=$(quote_unit "${ROOT_DIR}")"
ExecStart="$(quote_exec "${PORTAL_VENV}/bin/python")" -m portal.cli serve
WorkingDirectory="$(quote_unit "${ROOT_DIR}")"
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
UMask=0077
NoNewPrivileges=true

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable hermes-autodev-portal.service
    systemctl --user restart hermes-autodev-portal.service
    autodev_warn_linger
    cat <<EOF

Portal service installed. The website becomes reachable after DNS and HTTPS setup:
  1. Point ${domain} to this server.
  2. Install Caddy and configure it using ${STATE_DIR}/Caddyfile.
  3. Allow inbound TCP 80/443 and enable lingering for this Linux account.
  4. Create a login if needed: hermes-autodev portal user owner
  5. Open https://${domain}/team and publish selected projects.

See ${ROOT_DIR}/docs/production-portal.md for exact server commands.
EOF
    ;;
  start|stop|restart|status)
    if [[ "${ACTION}" == "status" && ! -f "${UNIT_FILE}" ]]; then
      echo "Portal service is not installed."
      exit 1
    fi
    systemctl --user "${ACTION}" hermes-autodev-portal.service
    ;;
  uninstall-service)
    if [[ -f "${UNIT_FILE}" ]]; then
      systemctl --user disable --now hermes-autodev-portal.service
      rm -f "${UNIT_FILE}"
      systemctl --user daemon-reload
    fi
    ;;
  *) portal_python "${ACTION}" "$@" ;;
esac
