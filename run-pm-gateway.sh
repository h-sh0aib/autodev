#!/usr/bin/env bash
set -euo pipefail

if command -v project-manager >/dev/null 2>&1; then
  exec project-manager gateway run
fi

exec "${HOME}/.local/bin/project-manager" gateway run
