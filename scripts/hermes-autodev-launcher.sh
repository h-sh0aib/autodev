#!/usr/bin/env bash
set -euo pipefail

pointer_file="${HOME}/.config/hermes-autodev/install.env"
state_file="${pointer_file}"
if [[ ! -r "${state_file}" ]]; then
  state_file="${HERMES_AUTODEV_STATE_DIR:-${HERMES_HOME:-${HOME}/.hermes}/autodev}/install.env"
fi
if [[ ! -r "${state_file}" ]]; then
  echo "Hermes autonomous dev team install metadata is missing: ${state_file}" >&2
  echo "Run 'bash ./wizard.sh' again from the package checkout." >&2
  exit 1
fi
if [[ ! -O "${state_file}" ]]; then
  echo "Refusing install metadata not owned by the current user: ${state_file}" >&2
  exit 1
fi

# This owner-only file is written by install-team.sh using shell-safe %q values.
# shellcheck disable=SC1090
source "${state_file}"

if [[ -z "${HERMES_HOME:-}" && -n "${HERMES_AUTODEV_HERMES_HOME:-}" ]]; then
  export HERMES_HOME="${HERMES_AUTODEV_HERMES_HOME}"
fi
if [[ -z "${HERMES_AUTODEV_STATE_DIR:-}" && -n "${HERMES_AUTODEV_STATE_DIR_VALUE:-}" ]]; then
  export HERMES_AUTODEV_STATE_DIR="${HERMES_AUTODEV_STATE_DIR_VALUE}"
fi

entrypoint="${HERMES_AUTODEV_PACKAGE_ROOT:-}/autodev.sh"
if [[ ! -r "${entrypoint}" ]]; then
  echo "Package checkout was moved or removed: ${entrypoint}" >&2
  echo "Run 'bash ./wizard.sh' from its new location to repair this launcher." >&2
  exit 1
fi

exec bash "${entrypoint}" "$@"
