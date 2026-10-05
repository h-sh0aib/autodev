#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CHECK_ONLY=0
YES=0
SKIP_HERMES=0
SKIP_PACKAGE=0
SKIP_BACKUP=0
CONFIGURE=0

usage() {
  cat <<'EOF'
Usage:
  hermes-autodev update [options]

Safely updates the autonomous development team:
  1. refuses to overwrite a dirty package checkout;
  2. creates a private pre-update backup;
  3. updates Hermes through its supported updater;
  4. fast-forwards this Git checkout;
  5. refreshes profiles while preserving config, auth, sessions, and data;
  6. restarts the GUI when it was running and runs the package doctor.

Options:
  --check          Report available updates without installing anything.
  -y, --yes        Skip the confirmation prompt.
  --skip-hermes    Do not check or update Hermes itself.
  --skip-package   Do not fetch or pull this package repository.
  --no-backup      Skip the pre-update backup.
  --configure      Run the credential/model wizard after updating.
  -h, --help       Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    -y|--yes) YES=1; shift ;;
    --skip-hermes) SKIP_HERMES=1; shift ;;
    --skip-package) SKIP_PACKAGE=1; shift ;;
    --no-backup) SKIP_BACKUP=1; shift ;;
    --configure) CONFIGURE=1; shift ;;
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
command -v git >/dev/null 2>&1 || autodev_die "git is required to update this package."

package_version="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
package_commit="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
dirty="$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal 2>/dev/null || true)"
upstream=""
behind="unknown"
ahead="unknown"

echo "Autonomous dev team update check"
echo "  Package: ${package_version} (${package_commit})"
echo "  Hermes:  $(autodev_hermes_version 2>/dev/null || printf 'not installed')"

if [[ -n "${dirty}" ]]; then
  echo "  Checkout: local changes present"
else
  echo "  Checkout: clean"
fi

if [[ "${SKIP_PACKAGE}" -eq 0 ]]; then
  upstream="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  if [[ -n "${upstream}" ]]; then
    git -C "${ROOT_DIR}" fetch --prune --quiet
    read -r ahead behind < <(git -C "${ROOT_DIR}" rev-list --left-right --count "HEAD...${upstream}")
    echo "  Upstream: ${upstream} (${behind} behind, ${ahead} ahead)"
  else
    echo "  Upstream: not configured; package pull will be skipped"
  fi
fi

if [[ "${SKIP_HERMES}" -eq 0 ]] && command -v hermes >/dev/null 2>&1; then
  hermes update --check || true
fi

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  exit 0
fi

if [[ -n "${dirty}" && "${SKIP_PACKAGE}" -eq 0 ]]; then
  autodev_die "the package checkout has local changes. Commit or stash them explicitly before updating; no automatic stash was performed."
fi

if [[ "${YES}" -ne 1 ]]; then
  autodev_has_tty || autodev_die "a terminal is required for confirmation; pass --yes for unattended updates."
  printf 'Create a backup and update Hermes, the package, and all profiles? [Y/n]: '
  read -r answer
  case "${answer:-yes}" in
    y|Y|yes|YES|Yes) ;;
    *) echo "Update cancelled."; exit 0 ;;
  esac
fi

dashboard_was_running=0
portal_was_running=0
if bash "${ROOT_DIR}/scripts/portal.sh" status >/dev/null 2>&1; then
  portal_was_running=1
fi
if bash "${ROOT_DIR}/scripts/dashboard.sh" status >/dev/null 2>&1; then
  dashboard_was_running=1
fi

if [[ "${SKIP_BACKUP}" -eq 0 ]]; then
  bash "${ROOT_DIR}/scripts/backup-runtime.sh" --quick
fi

if [[ "${SKIP_HERMES}" -eq 0 ]]; then
  command -v hermes >/dev/null 2>&1 || autodev_die "Hermes is not installed; run 'bash ./wizard.sh' first."
  hermes update --backup --yes
fi

if [[ "${SKIP_PACKAGE}" -eq 0 && -n "${upstream}" ]]; then
  git -C "${ROOT_DIR}" pull --ff-only
fi

bash "${ROOT_DIR}/install.sh" -y --no-update-hermes

if [[ "${CONFIGURE}" -eq 1 ]]; then
  bash "${ROOT_DIR}/wizard.sh" --skip-install --skip-project
fi

if [[ "${dashboard_was_running}" -eq 1 ]]; then
  bash "${ROOT_DIR}/scripts/dashboard.sh" restart --no-open
fi

if [[ "${portal_was_running}" -eq 1 ]]; then
  portal_python="$(autodev_state_dir)/portal-venv/bin/python"
  "${portal_python}" -m pip install -r "${ROOT_DIR}/portal/requirements.txt"
  bash "${ROOT_DIR}/scripts/portal.sh" restart
fi

bash "${ROOT_DIR}/scripts/doctor.sh"

new_version="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
new_commit="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
echo "Update complete: autonomous dev team ${new_version} (${new_commit})."
