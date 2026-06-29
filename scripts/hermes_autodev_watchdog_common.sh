#!/usr/bin/env bash
set -u

BOARD="${HERMES_AUTODEV_BOARD:-}"
PM_PROFILE="${HERMES_AUTODEV_PM_PROFILE:-project-manager}"
REPO="${HERMES_AUTODEV_REPO:-}"
DISPATCH_MAX="${HERMES_AUTODEV_DISPATCH_MAX:-2}"

say() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

if [[ -z "${BOARD}" ]]; then
  say "autodev watchdog: HERMES_AUTODEV_BOARD is not set"
  exit 2
fi

if [[ -z "${REPO}" ]]; then
  say "autodev watchdog: HERMES_AUTODEV_REPO is not set"
  exit 2
fi

say "autodev watchdog: board=${BOARD} repo=${REPO} profile=${PM_PROFILE}"

say "gateway status:"
hermes -p "${PM_PROFILE}" gateway status 2>&1 || true

say "cron status:"
hermes -p "${PM_PROFILE}" cron status 2>&1 || true

say "kanban diagnostics:"
hermes -p "${PM_PROFILE}" kanban --board "${BOARD}" diagnostics 2>&1 || true

say "kanban stats:"
hermes -p "${PM_PROFILE}" kanban --board "${BOARD}" stats 2>&1 || true

say "kanban tasks:"
hermes -p "${PM_PROFILE}" kanban --board "${BOARD}" list 2>&1 || true

say "dispatcher pass:"
hermes -p "${PM_PROFILE}" kanban --board "${BOARD}" dispatch --max "${DISPATCH_MAX}" 2>&1 || true

if [[ -d "${REPO}/.git" ]]; then
  say "git status:"
  git -C "${REPO}" status --short --branch 2>&1 || true
  say "recent commits:"
  git -C "${REPO}" log --oneline -8 2>&1 || true
else
  say "git status: ${REPO} is not a git repository"
fi
