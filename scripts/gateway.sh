#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ACTION="${1:-status}"
PROFILE="project-manager"
STATE_DIR="$(autodev_state_dir)"
PID_FILE="${STATE_DIR}/pm-gateway.pid"
LOG_FILE="${STATE_DIR}/logs/pm-gateway.log"

usage() {
  cat <<'EOF'
Usage:
  hermes-autodev gateway [start|stop|restart|status]

Uses Hermes' native gateway service when available. On Linux hosts without a
working user service manager, start falls back to a nohup-managed process that
normally survives an ordinary SSH disconnect, subject to the host's logout
policy. The fallback does not restart after reboot.
EOF
}

fallback_running() {
  [[ -r "${PID_FILE}" ]] || return 1
  local pid
  pid="$(tr -dc '0-9' < "${PID_FILE}")"
  [[ -n "${pid}" ]] && autodev_pid_running "${pid}"
}

stop_fallback() {
  if ! fallback_running; then
    rm -f "${PID_FILE}"
    return 0
  fi
  local pid command_line=""
  pid="$(tr -dc '0-9' < "${PID_FILE}")"
  if [[ -r "/proc/${pid}/cmdline" ]]; then
    command_line="$(tr '\0' ' ' < "/proc/${pid}/cmdline")"
  fi
  if [[ "${command_line}" != *gateway*run* ]]; then
    echo "Refusing to stop PID ${pid}; its command could not be verified as a Hermes gateway process." >&2
    return 1
  fi
  kill "${pid}" 2>/dev/null || true
  local attempt
  for ((attempt = 0; attempt < 10; attempt++)); do
    autodev_pid_running "${pid}" || break
    sleep 1
  done
  if autodev_pid_running "${pid}"; then
    echo "Gateway PID ${pid} did not stop after SIGTERM." >&2
    return 1
  fi
  rm -f "${PID_FILE}"
}

start_gateway() {
  command -v hermes >/dev/null 2>&1 || autodev_die "hermes is not installed."
  if hermes -p "${PROFILE}" gateway start; then
    autodev_warn_linger
    return 0
  fi

  if fallback_running; then
    echo "Project Manager gateway fallback is already running."
    return 0
  fi

  echo "Hermes could not start a managed gateway service; using the background fallback." >&2
  mkdir -p "$(dirname "${LOG_FILE}")"
  chmod 0700 "${STATE_DIR}" "$(dirname "${LOG_FILE}")" 2>/dev/null || true
  umask 077
  nohup bash "${ROOT_DIR}/run-pm-gateway.sh" >> "${LOG_FILE}" 2>&1 &
  printf '%s\n' "$!" > "${PID_FILE}"
  chmod 0600 "${PID_FILE}" || true
  sleep 2
  if ! fallback_running; then
    echo "Gateway fallback exited during startup. Recent log output:" >&2
    tail -n 30 "${LOG_FILE}" 2>/dev/null || true
    return 1
  fi
  echo "Project Manager gateway running in the background (PID $(cat "${PID_FILE}"))."
  echo "The fallback survives an ordinary SSH connection loss, but host logout policy may terminate it and it does not restart after reboot. Use a host/container supervisor for guaranteed persistence." >&2
}

stop_gateway() {
  if command -v hermes >/dev/null 2>&1 && [[ -d "$(autodev_profile_dir "${PROFILE}")" ]]; then
    local stop_output stop_status=0
    stop_output="$(hermes -p "${PROFILE}" gateway stop 2>&1)" || stop_status=$?
    if [[ "${stop_status}" -ne 0 ]] &&
       [[ ! "${stop_output,,}" =~ (stopped|not[[:space:]]+running|inactive|already[[:space:]]+stopped) ]]; then
      printf '%s\n' "${stop_output}" >&2
      echo "Hermes could not confirm that the managed Project Manager gateway stopped." >&2
      return 1
    fi
  fi
  stop_fallback
  if show_status >/dev/null 2>&1; then
    echo "Project Manager gateway still reports as running after the stop request." >&2
    return 1
  fi
  echo "Project Manager gateway stopped."
}

show_status() {
  local status=1
  if command -v hermes >/dev/null 2>&1 && [[ -d "$(autodev_profile_dir "${PROFILE}")" ]]; then
    local native_output native_status=0
    native_output="$(hermes -p "${PROFILE}" gateway status 2>&1)" || native_status=$?
    printf '%s\n' "${native_output}"
    if [[ "${native_status}" -eq 0 ]] &&
       [[ ! "${native_output,,}" =~ (stopped|not[[:space:]]+running|inactive|failed) ]]; then
      status=0
    fi
  else
    echo "Project Manager profile is not installed."
  fi
  if fallback_running; then
    echo "Background fallback: running (PID $(cat "${PID_FILE}"))"
    status=0
  else
    echo "Background fallback: stopped"
  fi
  return "${status}"
}

case "${ACTION}" in
  start) start_gateway ;;
  stop) stop_gateway ;;
  restart)
    stop_gateway
    start_gateway
    ;;
  status) show_status ;;
  -h|--help|help) usage ;;
  *)
    echo "Unknown gateway action: ${ACTION}" >&2
    usage >&2
    exit 2
    ;;
esac
