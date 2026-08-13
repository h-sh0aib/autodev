#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MODE="quick"
OUTPUT=""

usage() {
  cat <<'EOF'
Usage:
  scripts/backup-runtime.sh [--quick|--full] [--output FILE]

Creates a private lifecycle backup outside HERMES_HOME so it survives a full
Hermes uninstall. Quick is intended for updates; full is used before removal.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) MODE="quick"; shift ;;
    --full) MODE="full"; shift ;;
    --output)
      [[ $# -ge 2 ]] || autodev_die "--output requires a file path."
      OUTPUT="$2"
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

backup_dir="$(autodev_external_state_dir)/backups"
hermes_home_dir="$(readlink -m "${HERMES_HOME:-${HOME}/.hermes}")"
backup_dir="$(readlink -m "${backup_dir}")"
if [[ "${backup_dir}" == "${hermes_home_dir}" ]] || autodev_path_is_within "${backup_dir}" "${hermes_home_dir}"; then
  autodev_die "backup destination must be outside HERMES_HOME: ${backup_dir}"
fi
mkdir -p "${backup_dir}"
chmod 0700 "$(autodev_external_state_dir)" "${backup_dir}" 2>/dev/null || true
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -z "${OUTPUT}" ]]; then
  if command -v hermes >/dev/null 2>&1; then
    OUTPUT="${backup_dir}/hermes-autodev-${MODE}-${timestamp}.zip"
  else
    OUTPUT="${backup_dir}/hermes-autodev-${MODE}-${timestamp}.tar.gz"
  fi
fi

output_abs="$(readlink -m "${OUTPUT}")"
if [[ "${output_abs}" == "${hermes_home_dir}" ]] || autodev_path_is_within "${output_abs}" "${hermes_home_dir}"; then
  autodev_die "backup output must be outside HERMES_HOME: ${output_abs}"
fi
OUTPUT="${output_abs}"
mkdir -p "$(dirname "${OUTPUT}")"
umask 077

if command -v hermes >/dev/null 2>&1; then
  if [[ "${MODE}" == "quick" ]]; then
    hermes backup --quick --label autodev-update --output "${OUTPUT}"
  else
    hermes backup --output "${OUTPUT}"
  fi
elif [[ -d "${hermes_home_dir}" ]]; then
  echo "Hermes CLI is unavailable; creating a filesystem archive instead." >&2
  tar -C "$(dirname "${hermes_home_dir}")" -czf "${OUTPUT}" "$(basename "${hermes_home_dir}")"
else
  autodev_die "no Hermes runtime data exists to back up."
fi

chmod 0600 "${OUTPUT}" || true
printf 'Backup created: %s\n' "${OUTPUT}"
