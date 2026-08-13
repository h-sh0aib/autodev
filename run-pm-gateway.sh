#!/usr/bin/env bash
set -euo pipefail

if ! command -v hermes >/dev/null 2>&1; then
  echo "hermes is not available on PATH; rerun the setup wizard." >&2
  exit 1
fi

exec hermes -p project-manager gateway run
