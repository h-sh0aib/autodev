#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ACTION="${1:-open}"
if [[ $# -gt 0 ]]; then
  shift
fi

STATE_DIR="$(autodev_state_dir)"
HERMES_HOME_DIR="$(autodev_hermes_home)"
STATE_FILE="${STATE_DIR}/dashboard.env"
PID_FILE="${STATE_DIR}/dashboard.pid"
LOG_DIR="${STATE_DIR}/logs"
LOG_FILE="${LOG_DIR}/dashboard.log"
UNIT_NAME="hermes-autodev-dashboard.service"
UNIT_DIR="${HOME}/.config/systemd/user"
UNIT_FILE="${UNIT_DIR}/${UNIT_NAME}"

MODE="auto"
HOST="127.0.0.1"
PORT="9119"
PERSIST="auto"
OPEN_BROWSER="auto"
INSTALL_DEPS=1

if [[ -r "${STATE_FILE}" ]]; then
  # This owner-only file is written below using shell-safe %q values.
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
  MODE="${HERMES_AUTODEV_GUI_MODE:-${MODE}}"
  HOST="${HERMES_AUTODEV_GUI_HOST:-${HOST}}"
  PORT="${HERMES_AUTODEV_GUI_PORT:-${PORT}}"
  PERSIST="${HERMES_AUTODEV_GUI_PERSIST:-${PERSIST}}"
fi

usage() {
  cat <<'EOF'
Usage:
  hermes-autodev dashboard [open|start|stop|restart|status|access|configure|uninstall-service] [options]

Manages the Hermes web dashboard used as the autonomous dev team GUI.
The supported local and SSH modes bind only to 127.0.0.1. Remote users
connect through an SSH tunnel, so API keys and agent controls are never
placed directly on the public network.

Options:
  --mode MODE          auto, local, or ssh. Default: auto.
  --port PORT          Loopback port. Default: 9119.
  --persist            Start at login/boot with a systemd user service.
  --no-persist         Run as a background process only.
  --open               Open a local browser when possible.
  --no-open            Never open a browser.
  --no-install-deps    Do not install missing Hermes web/PTY extras.
  -h, --help           Show this help.

Examples:
  hermes-autodev dashboard open
  hermes-autodev dashboard start --mode ssh --persist --no-open
  hermes-autodev dashboard access
  hermes-autodev dashboard uninstall-service
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || autodev_die "--mode requires a value."
      MODE="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || autodev_die "--port requires a value."
      PORT="$2"
      shift 2
      ;;
    --persist)
      PERSIST=1
      shift
      ;;
    --no-persist)
      PERSIST=0
      shift
      ;;
    --open)
      OPEN_BROWSER=1
      shift
      ;;
    --no-open)
      OPEN_BROWSER=0
      shift
      ;;
    --no-install-deps)
      INSTALL_DEPS=0
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

autodev_require_linux

case "${MODE}" in
  auto)
    case "$(autodev_detect_environment)" in
      *-ssh|container) MODE="ssh" ;;
      *) MODE="local" ;;
    esac
    ;;
  local|ssh) ;;
  *) autodev_die "--mode must be auto, local, or ssh: ${MODE}" ;;
esac

[[ "${PORT}" =~ ^[0-9]+$ ]] || autodev_die "--port must be numeric: ${PORT}"
(( 10#${PORT} >= 1024 && 10#${PORT} <= 65535 )) || autodev_die "--port must be between 1024 and 65535: ${PORT}"
PORT="$((10#${PORT}))"
HOST="127.0.0.1"

if [[ "${PERSIST}" == "auto" ]]; then
  [[ "${MODE}" == "ssh" ]] && PERSIST=1 || PERSIST=0
fi
autodev_is_true "${PERSIST}" && PERSIST=1 || PERSIST=0

if [[ "${OPEN_BROWSER}" == "auto" ]]; then
  [[ "${MODE}" == "local" ]] && OPEN_BROWSER=1 || OPEN_BROWSER=0
fi
autodev_is_true "${OPEN_BROWSER}" && OPEN_BROWSER=1 || OPEN_BROWSER=0

save_state() {
  mkdir -p "${STATE_DIR}"
  chmod 0700 "${STATE_DIR}" 2>/dev/null || true
  autodev_write_env_file "${STATE_FILE}" \
    "HERMES_AUTODEV_GUI_MODE=${MODE}" \
    "HERMES_AUTODEV_GUI_HOST=${HOST}" \
    "HERMES_AUTODEV_GUI_PORT=${PORT}" \
    "HERMES_AUTODEV_GUI_PERSIST=${PERSIST}"
}

dashboard_url() {
  printf 'http://127.0.0.1:%s' "${PORT}"
}

dashboard_healthy() {
  command -v curl >/dev/null 2>&1 || return 1
  local response
  response="$(curl --fail --silent --show-error --max-time 2 "$(dashboard_url)/api/status" 2>/dev/null || true)"
  [[ "${response}" == *'"version"'* || "${response}" == *'"agent_version"'* || "${response}" == *Hermes* ]]
}

dashboard_port_available() {
  local python_command
  python_command="$(autodev_find_hermes_python || autodev_find_python)" || return 1
  "${python_command}" - "${HOST}" "${PORT}" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    sock.bind((host, port))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PY
}

background_pid_running() {
  [[ -r "${PID_FILE}" ]] || return 1
  local pid
  pid="$(tr -dc '0-9' < "${PID_FILE}")"
  [[ -n "${pid}" ]] || return 1
  autodev_pid_running "${pid}"
}

systemd_unit_installed() {
  [[ -f "${UNIT_FILE}" ]]
}

systemd_unit_active() {
  autodev_user_systemd_available && systemctl --user is-active --quiet "${UNIT_NAME}"
}

ensure_hermes_ready() {
  command -v hermes >/dev/null 2>&1 || autodev_die "hermes is not installed; run 'bash ./wizard.sh' first."
  local version
  version="$(autodev_hermes_version || true)"
  autodev_version_at_least "${version}" "${AUTODEV_MIN_HERMES_VERSION}" || autodev_die \
    "Hermes ${AUTODEV_MIN_HERMES_VERSION}+ is required for the complete multi-profile GUI; found ${version:-unknown}. Run 'hermes-autodev update'."
}

ensure_dashboard_dependencies() {
  local python_command
  python_command="$(autodev_find_hermes_python || autodev_find_python)" || autodev_die \
    "could not locate the Python environment used by Hermes."
  if "${python_command}" -c 'import fastapi, uvicorn, ptyprocess' >/dev/null 2>&1; then
    return 0
  fi

  [[ "${INSTALL_DEPS}" -eq 1 ]] || autodev_die \
    "Hermes dashboard dependencies are missing. Re-run without --no-install-deps."

  echo "Installing Hermes web dashboard and browser-chat dependencies..."
  local project_dir uv_command
  project_dir="$(autodev_hermes_install_dir || true)"
  uv_command="${HERMES_HOME_DIR}/bin/uv"
  [[ -x "${uv_command}" ]] || uv_command="$(command -v uv 2>/dev/null || true)"

  if [[ -n "${uv_command}" && -x "${uv_command}" ]]; then
    if [[ -n "${project_dir}" && -f "${project_dir}/pyproject.toml" ]]; then
      "${uv_command}" pip install --python "${python_command}" -e "${project_dir}[web,pty]"
    else
      "${uv_command}" pip install --python "${python_command}" 'hermes-agent[web,pty]'
    fi
  elif [[ -n "${project_dir}" && -f "${project_dir}/pyproject.toml" ]]; then
    "${python_command}" -m pip install -e "${project_dir}[web,pty]"
  else
    "${python_command}" -m pip install 'hermes-agent[web,pty]'
  fi

  "${python_command}" -c 'import fastapi, uvicorn, ptyprocess' >/dev/null 2>&1 || autodev_die \
    "dashboard dependencies are still unavailable after installation."
}

wait_for_dashboard() {
  local attempt
  for ((attempt = 0; attempt < 30; attempt++)); do
    if dashboard_healthy; then
      return 0
    fi
    sleep 1
  done
  echo "Dashboard did not become healthy. Recent log output:" >&2
  tail -n 30 "${LOG_FILE}" 2>/dev/null || true
  return 1
}

stop_background() {
  if ! background_pid_running; then
    rm -f "${PID_FILE}"
    return 0
  fi

  local pid command_line=""
  pid="$(tr -dc '0-9' < "${PID_FILE}")"
  if [[ -r "/proc/${pid}/cmdline" ]]; then
    command_line="$(tr '\0' ' ' < "/proc/${pid}/cmdline")"
  fi
  if [[ "${command_line}" != *hermes*dashboard* ]]; then
    echo "Refusing to stop PID ${pid}; its command could not be verified as a Hermes dashboard process." >&2
    return 1
  fi

  kill "${pid}" 2>/dev/null || true
  local attempt
  for ((attempt = 0; attempt < 10; attempt++)); do
    autodev_pid_running "${pid}" || break
    sleep 1
  done
  if autodev_pid_running "${pid}"; then
    echo "Dashboard PID ${pid} did not stop after SIGTERM." >&2
    return 1
  fi
  rm -f "${PID_FILE}"
}

stop_dashboard() {
  if systemd_unit_active; then
    systemctl --user stop "${UNIT_NAME}"
  fi
  stop_background
  local attempt
  for ((attempt = 0; attempt < 10; attempt++)); do
    dashboard_healthy || return 0
    sleep 1
  done
  echo "Dashboard still answers at $(dashboard_url), but no package-managed process could be stopped safely." >&2
  echo "Stop the process or user service that owns this port, then retry." >&2
  return 1
}

systemd_quote() {
  local value="$1"
  value="${value//%/%%}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

install_systemd_service() {
  autodev_user_systemd_available || return 1
  local hermes_command path_value unit_temporary
  hermes_command="$(command -v hermes)"
  path_value="$(dirname "${hermes_command}"):${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin"
  mkdir -p "${UNIT_DIR}" || return 1
  unit_temporary="$(mktemp "${UNIT_FILE}.tmp.XXXXXX")" || return 1
  if ! cat > "${unit_temporary}" <<EOF
[Unit]
Description=Hermes Autonomous Development Team Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment="PATH=$(systemd_quote "${path_value}")"
Environment="HERMES_HOME=$(systemd_quote "${HERMES_HOME_DIR}")"
EnvironmentFile="-$(systemd_quote "${HERMES_HOME_DIR}/.env")"
ExecStart="$(systemd_quote "${hermes_command}")" dashboard --host ${HOST} --port ${PORT} --no-open
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
  then
    rm -f "${unit_temporary}"
    return 1
  fi
  chmod 0644 "${unit_temporary}" || { rm -f "${unit_temporary}"; return 1; }
  mv -f -- "${unit_temporary}" "${UNIT_FILE}" || { rm -f "${unit_temporary}"; return 1; }
  systemctl --user daemon-reload || return 1
  if ! systemctl --user enable --now "${UNIT_NAME}"; then
    echo "Could not enable the dashboard user service; falling back to a background process." >&2
    systemctl --user stop "${UNIT_NAME}" >/dev/null 2>&1 || true
    return 1
  fi
  autodev_warn_linger
  return 0
}

start_background() {
  if background_pid_running; then
    return 0
  fi
  mkdir -p "${LOG_DIR}"
  chmod 0700 "${STATE_DIR}" "${LOG_DIR}" 2>/dev/null || true
  umask 077
  nohup "$(command -v hermes)" dashboard --host "${HOST}" --port "${PORT}" --no-open \
    >> "${LOG_FILE}" 2>&1 &
  printf '%s\n' "$!" > "${PID_FILE}"
  chmod 0600 "${PID_FILE}" || true
}

start_dashboard() {
  ensure_hermes_ready
  save_state
  if dashboard_healthy; then
    echo "Dashboard is already available at $(dashboard_url)."
    return 0
  fi
  dashboard_port_available || autodev_die \
    "dashboard port ${PORT} is already in use on ${HOST}. Choose another with '--port PORT'."

  ensure_dashboard_dependencies
  mkdir -p "${LOG_DIR}"
  chmod 0700 "${STATE_DIR}" "${LOG_DIR}" 2>/dev/null || true
  if [[ -d "$(autodev_profile_dir project-manager)" ]]; then
    hermes -p project-manager kanban init >/dev/null 2>&1 || true
  else
    hermes kanban init >/dev/null 2>&1 || true
  fi

  if [[ "${PERSIST}" -eq 1 ]]; then
    if ! install_systemd_service; then
      echo "User systemd is unavailable; using a detached background process instead." >&2
      echo "It survives an ordinary SSH connection loss, but host logout policy may still terminate it and it will not restart after reboot. Use a host/container supervisor or enable a systemd user session for guaranteed persistence." >&2
      start_background
    fi
  else
    start_background
  fi

  wait_for_dashboard
  echo "Dashboard started at $(dashboard_url)."
}

show_access() {
  local url
  url="$(dashboard_url)"
  if [[ "${MODE}" == "ssh" || -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]]; then
    local server_address="your-server" server_port="22" user_name
    user_name="$(id -un)"
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
      # SSH_CONNECTION: client_ip client_port server_ip server_port
      read -r _ _ server_address server_port <<< "${SSH_CONNECTION}"
    fi
    local ssh_target="${user_name}@${server_address}"
    cat <<EOF

GUI access from your computer

Keep this tunnel open in a local terminal:
  ssh -N -p ${server_port} -L ${PORT}:127.0.0.1:${PORT} ${ssh_target}

Then open:
  ${url}

If you normally use an SSH alias, replace ${ssh_target} with that alias.
EOF
  else
    echo "Open ${url}"
  fi
}

open_local_browser() {
  [[ "${OPEN_BROWSER}" -eq 1 ]] || return 0
  local url
  url="$(dashboard_url)"
  if command -v xdg-open >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    xdg-open "${url}" >/dev/null 2>&1 || true
  elif command -v wslview >/dev/null 2>&1; then
    wslview "${url}" >/dev/null 2>&1 || true
  elif grep -qi microsoft /proc/version 2>/dev/null && command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Start-Process '${url}'" >/dev/null 2>&1 || true
  else
    echo "No graphical browser opener was detected. Open ${url} manually."
  fi
}

show_status() {
  local process_status="stopped" service_status="not installed" health="unreachable"
  systemd_unit_installed && service_status="installed"
  systemd_unit_active && { service_status="active"; process_status="running"; }
  background_pid_running && process_status="running"
  dashboard_healthy && health="healthy"
  printf 'Dashboard process: %s\n' "${process_status}"
  printf 'User service:      %s\n' "${service_status}"
  printf 'Health:            %s\n' "${health}"
  printf 'URL:               %s\n' "$(dashboard_url)"
  [[ "${health}" == "healthy" ]]
}

uninstall_service() {
  stop_dashboard || return 1
  if autodev_user_systemd_available; then
    systemctl --user disable "${UNIT_NAME}" >/dev/null 2>&1 || true
  fi
  if [[ -f "${UNIT_FILE}" ]]; then
    rm -f "${UNIT_FILE}"
    autodev_user_systemd_available && systemctl --user daemon-reload || true
  fi
  echo "Autonomous dev dashboard service removed."
}

case "${ACTION}" in
  configure)
    save_state
    echo "Dashboard configured for ${MODE} mode at $(dashboard_url)."
    show_access
    ;;
  start)
    start_dashboard
    show_access
    ;;
  open)
    start_dashboard
    show_access
    open_local_browser
    ;;
  stop)
    stop_dashboard
    echo "Dashboard stopped."
    ;;
  restart)
    stop_dashboard
    start_dashboard
    show_access
    open_local_browser
    ;;
  status)
    show_status
    ;;
  access)
    show_access
    ;;
  uninstall-service)
    uninstall_service
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown dashboard action: ${ACTION}" >&2
    usage >&2
    exit 2
    ;;
esac
