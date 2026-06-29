#!/usr/bin/env bash
set -u

PROJECT_SLUG=""
PM_PROFILE="project-manager"

usage() {
  cat <<'EOF'
Usage:
  scripts/doctor.sh [--project-slug SLUG]

Checks whether the autonomous Hermes dev team package is installed and ready.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-slug)
      PROJECT_SLUG="$2"
      shift 2
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

ok() { printf 'ok   %s\n' "$*"; }
warn() { printf 'warn %s\n' "$*"; }
fail() { printf 'fail %s\n' "$*"; }

status=0

if command -v hermes >/dev/null 2>&1; then
  ok "hermes: $(command -v hermes)"
else
  fail "hermes command not found"
  status=1
fi

for profile in project-manager developer tester; do
  if [[ -d "${HOME}/.hermes/profiles/${profile}" ]]; then
    ok "profile installed: ${profile}"
  else
    fail "profile missing: ${profile}"
    status=1
  fi
done

for profile in project-manager developer tester; do
  env_file="${HOME}/.hermes/profiles/${profile}/.env"
  if [[ -f "${env_file}" ]]; then
    ok "env file exists: ${env_file}"
  else
    warn "env file missing: ${env_file}"
  fi
done

if command -v codex >/dev/null 2>&1; then
  ok "codex: $(command -v codex)"
else
  warn "codex command not found; Developer cannot run Codex until installed/authenticated"
fi

wrapper="${HOME}/.hermes/profiles/developer/bin/codex-network-exec"
if [[ -x "${wrapper}" ]]; then
  ok "codex wrapper executable: ${wrapper}"
else
  fail "codex wrapper missing or not executable: ${wrapper}"
  status=1
fi

if [[ -x "${HOME}/.hermes/scripts/hermes_autodev_watchdog_common.sh" ]]; then
  ok "common watchdog installed"
else
  warn "common watchdog missing; rerun ./install.sh"
fi

if command -v hermes >/dev/null 2>&1; then
  hermes -p "${PM_PROFILE}" gateway status || true
  hermes -p "${PM_PROFILE}" cron status || true
fi

if [[ -n "${PROJECT_SLUG}" ]]; then
  config="${HOME}/.hermes/autodev/projects/${PROJECT_SLUG}.env"
  if [[ -f "${config}" ]]; then
    ok "project config exists: ${config}"
  else
    fail "project config missing: ${config}"
    status=1
  fi
  if command -v hermes >/dev/null 2>&1; then
    hermes -p "${PM_PROFILE}" kanban --board "${PROJECT_SLUG}" stats || status=1
    hermes -p "${PM_PROFILE}" kanban --board "${PROJECT_SLUG}" list || true
  fi
fi

exit "${status}"
