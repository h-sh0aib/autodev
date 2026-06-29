#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH=""
PROJECT_SLUG=""
PROJECT_NAME=""
PROJECT_DESCRIPTION=""
REPO_URL=""
CREATE_CRON=1
START_GATEWAY=0
CREATE_KICKOFF=1
DELIVER="local"
WATCHDOG_INTERVAL="every 5m"
PM_SWEEP_INTERVAL="every 5m"
PM_PROFILE="project-manager"
DISPATCH_MAX="2"

usage() {
  cat <<'EOF'
Usage:
  scripts/setup-project.sh --project-path PATH [options]

Bootstraps one project for the Hermes autonomous dev team:
  - creates/switches a Kanban board
  - installs a project-specific watchdog wrapper
  - creates or updates watchdog + PM sweep cron jobs
  - creates an idempotent kickoff task for the Project Manager

Options:
  --project-path PATH       Absolute path to the project repository.
  --repo-url URL            Clone URL if PATH does not exist.
  --project-slug SLUG       Board slug. Defaults to basename(PATH).
  --project-name NAME       Human-readable board name.
  --project-description X   Board description.
  --deliver TARGET          PM sweep delivery target. Defaults to local.
  --cron                    Create/resume cron jobs. Default.
  --no-cron                 Skip cron setup.
  --start-gateway           Start the project-manager gateway.
  --no-start-gateway        Do not start the gateway. Default.
  --kickoff                 Create the kickoff Kanban task. Default.
  --no-kickoff              Skip kickoff task creation.
  --watchdog-interval X     Watchdog schedule. Default: every 5m.
  --pm-sweep-interval X     PM sweep schedule. Default: every 5m.
  --dispatch-max N          Max tasks to dispatch per watchdog pass. Default: 2.
  -h, --help                Show this help.

Examples:
  scripts/setup-project.sh --project-path /srv/app --project-slug app --cron
  scripts/setup-project.sh --repo-url git@github.com:org/app.git --project-path /srv/app --start-gateway
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-path)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    --project-slug)
      PROJECT_SLUG="$2"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --project-description)
      PROJECT_DESCRIPTION="$2"
      shift 2
      ;;
    --deliver)
      DELIVER="$2"
      shift 2
      ;;
    --cron)
      CREATE_CRON=1
      shift
      ;;
    --no-cron)
      CREATE_CRON=0
      shift
      ;;
    --start-gateway)
      START_GATEWAY=1
      shift
      ;;
    --no-start-gateway)
      START_GATEWAY=0
      shift
      ;;
    --kickoff)
      CREATE_KICKOFF=1
      shift
      ;;
    --no-kickoff)
      CREATE_KICKOFF=0
      shift
      ;;
    --watchdog-interval)
      WATCHDOG_INTERVAL="$2"
      shift 2
      ;;
    --pm-sweep-interval)
      PM_SWEEP_INTERVAL="$2"
      shift 2
      ;;
    --dispatch-max)
      DISPATCH_MAX="$2"
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

if [[ -z "${PROJECT_PATH}" ]]; then
  echo "--project-path is required." >&2
  usage >&2
  exit 2
fi

if [[ "${PROJECT_PATH}" != /* ]]; then
  echo "--project-path must be absolute: ${PROJECT_PATH}" >&2
  exit 2
fi

if ! command -v hermes >/dev/null 2>&1; then
  echo "hermes command not found. Run ./install.sh first." >&2
  exit 1
fi

if [[ ! -d "${PROJECT_PATH}" ]]; then
  if [[ -z "${REPO_URL}" ]]; then
    echo "Project path does not exist and --repo-url was not provided: ${PROJECT_PATH}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "${PROJECT_PATH}")"
  git clone "${REPO_URL}" "${PROJECT_PATH}"
fi

if [[ ! -d "${PROJECT_PATH}/.git" ]]; then
  echo "Project path must be a git repository: ${PROJECT_PATH}" >&2
  exit 1
fi

if [[ -z "${PROJECT_SLUG}" ]]; then
  PROJECT_SLUG="$(basename "${PROJECT_PATH}")"
fi

PROJECT_SLUG="$(printf '%s' "${PROJECT_SLUG}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-')"
PROJECT_SLUG="${PROJECT_SLUG#-}"
PROJECT_SLUG="${PROJECT_SLUG%-}"

if [[ -z "${PROJECT_SLUG}" ]]; then
  echo "Project slug resolved to empty. Pass --project-slug." >&2
  exit 2
fi

if [[ -z "${PROJECT_NAME}" ]]; then
  PROJECT_NAME="$(printf '%s' "${PROJECT_SLUG}" | tr '_-' '  ')"
fi

if [[ -z "${PROJECT_DESCRIPTION}" ]]; then
  PROJECT_DESCRIPTION="Autonomous development workstream for ${PROJECT_NAME}."
fi

mkdir -p "${HOME}/.hermes/scripts" "${HOME}/.hermes/autodev/projects"
install -m 0755 "${ROOT_DIR}/scripts/hermes_autodev_watchdog_common.sh" \
  "${HOME}/.hermes/scripts/hermes_autodev_watchdog_common.sh"

PROJECT_CONFIG="${HOME}/.hermes/autodev/projects/${PROJECT_SLUG}.env"
{
  printf 'HERMES_AUTODEV_BOARD=%q\n' "${PROJECT_SLUG}"
  printf 'HERMES_AUTODEV_PROJECT_NAME=%q\n' "${PROJECT_NAME}"
  printf 'HERMES_AUTODEV_REPO=%q\n' "${PROJECT_PATH}"
  printf 'HERMES_AUTODEV_PM_PROFILE=%q\n' "${PM_PROFILE}"
  printf 'HERMES_AUTODEV_DISPATCH_MAX=%q\n' "${DISPATCH_MAX}"
} > "${PROJECT_CONFIG}"
chmod 0600 "${PROJECT_CONFIG}" || true

WATCHDOG_SCRIPT="autodev_watchdog_${PROJECT_SLUG}.sh"
WATCHDOG_PATH="${HOME}/.hermes/scripts/${WATCHDOG_SCRIPT}"
cat > "${WATCHDOG_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "${PROJECT_CONFIG}"
exec "${HOME}/.hermes/scripts/hermes_autodev_watchdog_common.sh"
EOF
chmod 0755 "${WATCHDOG_PATH}"

render_template() {
  local template="$1"
  python3 - "$template" "${PROJECT_NAME}" "${PROJECT_SLUG}" "${PROJECT_PATH}" <<'PY'
from pathlib import Path
import sys

template, project_name, board_slug, project_path = sys.argv[1:5]
text = Path(template).read_text(encoding="utf-8")
text = text.replace("{{PROJECT_NAME}}", project_name)
text = text.replace("{{BOARD_SLUG}}", board_slug)
text = text.replace("{{PROJECT_PATH}}", project_path)
print(text)
PY
}

job_id_by_name() {
  local name="$1"
  local jobs_file="${HOME}/.hermes/profiles/${PM_PROFILE}/cron/jobs.json"
  [[ -f "${jobs_file}" ]] || return 1
  python3 - "$jobs_file" "$name" <<'PY'
import json
import sys
from pathlib import Path

jobs_file = Path(sys.argv[1])
name = sys.argv[2]
data = json.loads(jobs_file.read_text(encoding="utf-8"))
for job in data.get("jobs", []):
    if job.get("name") == name:
        print(job.get("id", ""))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

create_or_update_watchdog_job() {
  local name="$1"
  local job_id=""
  if job_id="$(job_id_by_name "${name}")"; then
    hermes -p "${PM_PROFILE}" cron edit "${job_id}" \
      --schedule "${WATCHDOG_INTERVAL}" \
      --deliver local \
      --script "${WATCHDOG_SCRIPT}" \
      --no-agent \
      --workdir "${PROJECT_PATH}" \
      --profile "${PM_PROFILE}"
    hermes -p "${PM_PROFILE}" cron resume "${job_id}" || true
  else
    hermes -p "${PM_PROFILE}" cron create "${WATCHDOG_INTERVAL}" \
      --name "${name}" \
      --deliver local \
      --script "${WATCHDOG_SCRIPT}" \
      --no-agent \
      --workdir "${PROJECT_PATH}" \
      --profile "${PM_PROFILE}"
  fi
}

create_or_update_pm_sweep_job() {
  local name="$1"
  local prompt="$2"
  local job_id=""
  if job_id="$(job_id_by_name "${name}")"; then
    hermes -p "${PM_PROFILE}" cron edit "${job_id}" \
      --schedule "${PM_SWEEP_INTERVAL}" \
      --prompt "${prompt}" \
      --deliver "${DELIVER}" \
      --skill codex \
      --skill kanban-codex-lane \
      --script "${WATCHDOG_SCRIPT}" \
      --agent \
      --workdir "${PROJECT_PATH}" \
      --profile "${PM_PROFILE}"
    hermes -p "${PM_PROFILE}" cron resume "${job_id}" || true
  else
    hermes -p "${PM_PROFILE}" cron create "${PM_SWEEP_INTERVAL}" "${prompt}" \
      --name "${name}" \
      --deliver "${DELIVER}" \
      --skill codex \
      --skill kanban-codex-lane \
      --script "${WATCHDOG_SCRIPT}" \
      --workdir "${PROJECT_PATH}" \
      --profile "${PM_PROFILE}"
  fi
}

echo "Creating or updating Kanban board ${PROJECT_SLUG}"
if ! hermes -p "${PM_PROFILE}" kanban boards create "${PROJECT_SLUG}" \
  --name "${PROJECT_NAME}" \
  --description "${PROJECT_DESCRIPTION}" \
  --default-workdir "${PROJECT_PATH}" \
  --switch >/dev/null 2>&1; then
  hermes -p "${PM_PROFILE}" kanban boards set-default-workdir "${PROJECT_SLUG}" "${PROJECT_PATH}"
  hermes -p "${PM_PROFILE}" kanban boards switch "${PROJECT_SLUG}"
fi

if [[ "${CREATE_KICKOFF}" -eq 1 ]]; then
  kickoff_body="$(render_template "${ROOT_DIR}/templates/kickoff-task.md")"
  hermes -p "${PM_PROFILE}" kanban --board "${PROJECT_SLUG}" create \
    "Initialize autonomous development workstream" \
    --body "${kickoff_body}" \
    --assignee "${PM_PROFILE}" \
    --workspace "dir:${PROJECT_PATH}" \
    --idempotency-key "autodev:${PROJECT_SLUG}:kickoff" >/dev/null
  echo "Kickoff task ensured on board ${PROJECT_SLUG}."
fi

if [[ "${CREATE_CRON}" -eq 1 ]]; then
  pm_prompt="$(render_template "${ROOT_DIR}/templates/pm-sweep-prompt.md")"
  create_or_update_watchdog_job "${PROJECT_NAME} autodev watchdog"
  create_or_update_pm_sweep_job "${PROJECT_NAME} autonomous PM sweep" "${pm_prompt}"
  echo "Cron jobs ensured for ${PROJECT_SLUG}."
fi

if [[ "${START_GATEWAY}" -eq 1 ]]; then
  if ! hermes -p "${PM_PROFILE}" gateway start; then
    echo "Warning: gateway start failed. On VPS/container hosts without user systemd, run this foreground fallback:" >&2
    echo "  ${ROOT_DIR}/run-pm-gateway.sh" >&2
  fi
fi

cat <<EOF

Project bootstrap complete.

Board:       ${PROJECT_SLUG}
Project:     ${PROJECT_NAME}
Repository:  ${PROJECT_PATH}
Config:      ${PROJECT_CONFIG}
Watchdog:    ${WATCHDOG_PATH}

Useful commands:
  hermes -p ${PM_PROFILE} kanban --board ${PROJECT_SLUG} list
  hermes -p ${PM_PROFILE} kanban --board ${PROJECT_SLUG} stats
  hermes -p ${PM_PROFILE} cron list --all
  hermes -p ${PM_PROFILE} gateway status
EOF
