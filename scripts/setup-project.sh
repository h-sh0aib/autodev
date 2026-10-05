#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROJECT_PATH=""
PROJECT_SLUG=""
PROJECT_NAME=""
PROJECT_DESCRIPTION=""
REPO_URL=""
SCM_PROVIDER="auto"
CREATE_CRON=1
START_GATEWAY=0
CREATE_KICKOFF=1
DELIVER="local"
WATCHDOG_INTERVAL="every 5m"
PM_SWEEP_INTERVAL="every 5m"
PM_PROFILE="project-manager"
DISPATCH_MAX="2"
NON_INTERACTIVE=0

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
  --project-path PATH       Project repository path (absolute, relative, or ~/...).
  --repo-url URL            Clone URL if PATH does not exist.
  --scm-provider NAME       Repository host: auto, github, gitlab, or generic.
                            Auto-detects GitHub/GitLab from origin when possible.
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
  --non-interactive         Disable Git credential/password prompts while cloning.
  -h, --help                Show this help.

Examples:
  scripts/setup-project.sh --project-path /srv/app --project-slug app --cron
  scripts/setup-project.sh --repo-url git@github.com:org/app.git --project-path /srv/app --start-gateway
  scripts/setup-project.sh --repo-url git@gitlab.com:group/app.git --project-path /srv/app --scm-provider gitlab
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-path|--repo-url|--scm-provider|--project-slug|--project-name|--project-description|--deliver|--watchdog-interval|--pm-sweep-interval|--dispatch-max)
      [[ $# -ge 2 ]] || { echo "$1 requires a value." >&2; exit 2; }
      ;;
  esac
  case "$1" in
    --project-path)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    --scm-provider)
      SCM_PROVIDER="$2"
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
    --non-interactive)
      NON_INTERACTIVE=1
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

if [[ -z "${PROJECT_PATH}" ]]; then
  echo "--project-path is required." >&2
  usage >&2
  exit 2
fi

case "${SCM_PROVIDER}" in
  auto|github|gitlab|generic) ;;
  *)
    echo "--scm-provider must be auto, github, gitlab, or generic: ${SCM_PROVIDER}" >&2
    exit 2
    ;;
esac

if [[ ! "${DISPATCH_MAX}" =~ ^[1-9][0-9]*$ ]]; then
  echo "--dispatch-max must be a positive integer: ${DISPATCH_MAX}" >&2
  exit 2
fi

case "${PROJECT_PATH}" in
  "~") PROJECT_PATH="${HOME}" ;;
  \~/*) PROJECT_PATH="${HOME}/${PROJECT_PATH:2}" ;;
esac
if [[ "${PROJECT_PATH}" != /* ]]; then
  PROJECT_PATH="${PWD}/${PROJECT_PATH}"
fi
PROJECT_PATH="$(readlink -m "${PROJECT_PATH}")"

if ! command -v hermes >/dev/null 2>&1; then
  echo "hermes command not found. Run 'bash ./install.sh' first." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git command not found. Install Git and retry." >&2
  exit 1
fi

if [[ -e "${PROJECT_PATH}" && ! -d "${PROJECT_PATH}" ]]; then
  echo "Project path exists but is not a directory: ${PROJECT_PATH}" >&2
  exit 1
fi

clone_required=0
if [[ ! -d "${PROJECT_PATH}" ]]; then
  [[ -n "${REPO_URL}" ]] || autodev_die \
    "project path does not exist and --repo-url was not provided: ${PROJECT_PATH}"
  mkdir -p "$(dirname "${PROJECT_PATH}")"
  clone_required=1
elif [[ "$(git -C "${PROJECT_PATH}" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" &&
        -n "${REPO_URL}" &&
        -z "$(find "${PROJECT_PATH}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  # Pre-created empty targets are common on servers where an administrator
  # prepared ownership/permissions before handing setup to an unprivileged user.
  clone_required=1
fi

if [[ "${clone_required}" -eq 1 ]]; then
  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    if [[ "${REPO_URL}" == git@* || "${REPO_URL}" == ssh://* ]]; then
      GIT_TERMINAL_PROMPT=0 \
        git -c core.sshCommand="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=15" \
        clone "${REPO_URL}" "${PROJECT_PATH}"
    else
      GIT_TERMINAL_PROMPT=0 git clone "${REPO_URL}" "${PROJECT_PATH}"
    fi
  else
    git clone "${REPO_URL}" "${PROJECT_PATH}"
  fi
fi

if [[ "$(git -C "${PROJECT_PATH}" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]]; then
  echo "Project path must be a git repository: ${PROJECT_PATH}" >&2
  exit 1
fi

# Normalize subdirectory inputs and Git worktrees to the actual checkout root.
PROJECT_PATH="$(git -C "${PROJECT_PATH}" rev-parse --show-toplevel)"
PROJECT_PATH="$(readlink -f "${PROJECT_PATH}")"

REMOTE_URL="$(git -C "${PROJECT_PATH}" remote get-url origin 2>/dev/null || true)"
if [[ -z "${REMOTE_URL}" ]]; then
  REMOTE_URL="${REPO_URL}"
fi
REMOTE_HOST="$(autodev_remote_host "${REMOTE_URL}" 2>/dev/null || true)"

if [[ "${SCM_PROVIDER}" == "auto" ]]; then
  configured_gitlab_host="${GITLAB_HOST:-}"
  configured_gitlab_host="$(autodev_remote_host "${configured_gitlab_host}" 2>/dev/null || true)"
  if [[ -n "${REMOTE_HOST}" && -n "${configured_gitlab_host}" && "${REMOTE_HOST}" == "${configured_gitlab_host}" ]]; then
    SCM_PROVIDER="gitlab"
  else
    case "${REMOTE_HOST}" in
      github.com|github.*|*.github.*) SCM_PROVIDER="github" ;;
      gitlab.com|gitlab.*|*.gitlab.*) SCM_PROVIDER="gitlab" ;;
      *) SCM_PROVIDER="generic" ;;
    esac
  fi
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

HERMES_HOME_DIR="$(autodev_hermes_home)"
mkdir -p "${HERMES_HOME_DIR}/scripts" "${HERMES_HOME_DIR}/autodev/projects"
chmod 0700 "${HERMES_HOME_DIR}/autodev" "${HERMES_HOME_DIR}/autodev/projects" 2>/dev/null || true
autodev_install_executable "${ROOT_DIR}/scripts/hermes_autodev_watchdog_common.sh" \
  "${HERMES_HOME_DIR}/scripts/hermes_autodev_watchdog_common.sh"

PROJECT_CONFIG="${HERMES_HOME_DIR}/autodev/projects/${PROJECT_SLUG}.env"
autodev_write_env_file "${PROJECT_CONFIG}" \
  "HERMES_AUTODEV_BOARD=${PROJECT_SLUG}" \
  "HERMES_AUTODEV_PROJECT_NAME=${PROJECT_NAME}" \
  "HERMES_AUTODEV_REPO=${PROJECT_PATH}" \
  "HERMES_AUTODEV_REMOTE_URL=${REMOTE_URL}" \
  "HERMES_AUTODEV_REMOTE_HOST=${REMOTE_HOST}" \
  "HERMES_AUTODEV_SCM_PROVIDER=${SCM_PROVIDER}" \
  "HERMES_AUTODEV_PM_PROFILE=${PM_PROFILE}" \
  "HERMES_AUTODEV_DISPATCH_MAX=${DISPATCH_MAX}"

WATCHDOG_SCRIPT="autodev_watchdog_${PROJECT_SLUG}.sh"
WATCHDOG_PATH="${HERMES_HOME_DIR}/scripts/${WATCHDOG_SCRIPT}"
WATCHDOG_TEMP="$(mktemp)"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\nset -a\n'
  printf 'source %q\n' "${PROJECT_CONFIG}"
  printf 'set +a\n'
  printf 'exec %q\n' "${HERMES_HOME_DIR}/scripts/hermes_autodev_watchdog_common.sh"
} > "${WATCHDOG_TEMP}"
autodev_install_executable "${WATCHDOG_TEMP}" "${WATCHDOG_PATH}"
rm -f "${WATCHDOG_TEMP}"

render_template() {
  local template="$1"
  autodev_python - "$template" "${PROJECT_NAME}" "${PROJECT_SLUG}" "${PROJECT_PATH}" "${SCM_PROVIDER}" "${REMOTE_URL}" <<'PY'
from pathlib import Path
import sys

template, project_name, board_slug, project_path, scm_provider, remote_url = sys.argv[1:7]
text = Path(template).read_text(encoding="utf-8")
text = text.replace("{{PROJECT_NAME}}", project_name)
text = text.replace("{{BOARD_SLUG}}", board_slug)
text = text.replace("{{PROJECT_PATH}}", project_path)
text = text.replace("{{SCM_PROVIDER}}", scm_provider)
text = text.replace("{{REMOTE_URL}}", remote_url)
print(text)
PY
}

job_id_by_name() {
  local name="$1"
  local jobs_file
  jobs_file="$(autodev_profile_dir "${PM_PROFILE}")/cron/jobs.json"
  [[ -f "${jobs_file}" ]] || return 1
  autodev_python - "$jobs_file" "$name" <<'PY'
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
      --workdir "${PROJECT_PATH}"
    hermes -p "${PM_PROFILE}" cron resume "${job_id}" || true
  else
    hermes -p "${PM_PROFILE}" cron create "${WATCHDOG_INTERVAL}" \
      --name "${name}" \
      --deliver local \
      --script "${WATCHDOG_SCRIPT}" \
      --no-agent \
      --workdir "${PROJECT_PATH}"
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
      --workdir "${PROJECT_PATH}"
    hermes -p "${PM_PROFILE}" cron resume "${job_id}" || true
  else
    hermes -p "${PM_PROFILE}" cron create "${PM_SWEEP_INTERVAL}" "${prompt}" \
      --name "${name}" \
      --deliver "${DELIVER}" \
      --skill codex \
      --skill kanban-codex-lane \
      --script "${WATCHDOG_SCRIPT}" \
      --workdir "${PROJECT_PATH}"
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

# Register the workspace in each profile's first-class Projects store. The
# dashboard is profile-aware, so this keeps project/session context available
# when an operator switches roles. The PM copy alone binds the coordination
# board; task dispatch supplies the workspace to the other profiles.
for project_profile in "${AUTODEV_TEAM_PROFILES[@]}"; do
  if hermes -p "${project_profile}" project show "${PROJECT_SLUG}" >/dev/null 2>&1; then
    hermes -p "${project_profile}" project restore "${PROJECT_SLUG}" >/dev/null
    hermes -p "${project_profile}" project rename "${PROJECT_SLUG}" "${PROJECT_NAME}" >/dev/null
    hermes -p "${project_profile}" project add-folder "${PROJECT_SLUG}" "${PROJECT_PATH}" --primary >/dev/null
    if [[ "${project_profile}" == "${PM_PROFILE}" ]]; then
      hermes -p "${project_profile}" project bind-board "${PROJECT_SLUG}" "${PROJECT_SLUG}" >/dev/null
    fi
    hermes -p "${project_profile}" project use "${PROJECT_SLUG}" >/dev/null
  else
    project_create_args=(
      -p "${project_profile}" project create "${PROJECT_NAME}"
      --slug "${PROJECT_SLUG}"
      --primary "${PROJECT_PATH}"
      --description "${PROJECT_DESCRIPTION}"
    )
    if [[ "${project_profile}" == "${PM_PROFILE}" ]]; then
      project_create_args+=(--board "${PROJECT_SLUG}")
    fi
    project_create_args+=(--use)
    hermes "${project_create_args[@]}" >/dev/null
  fi
done

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

# Registration is local/stdlib-only and preserves the owner's publication choice.
bash "${ROOT_DIR}/scripts/portal.sh" register \
  --slug "${PROJECT_SLUG}" --name "${PROJECT_NAME}" --repo "${PROJECT_PATH}"

if [[ "${START_GATEWAY}" -eq 1 ]]; then
  bash "${ROOT_DIR}/scripts/gateway.sh" start
fi

cat <<EOF

Project bootstrap complete.

Board:       ${PROJECT_SLUG}
GUI project: ${PROJECT_SLUG} (all seven profiles)
Project:     ${PROJECT_NAME}
Repository:  ${PROJECT_PATH}
Remote:      ${REMOTE_URL:-not configured}
Remote host: ${REMOTE_HOST:-not configured}
SCM host:    ${SCM_PROVIDER}
Config:      ${PROJECT_CONFIG}
Watchdog:    ${WATCHDOG_PATH}

Useful commands:
  hermes -p ${PM_PROFILE} kanban --board ${PROJECT_SLUG} list
  hermes -p ${PM_PROFILE} kanban --board ${PROJECT_SLUG} stats
  hermes -p ${PM_PROFILE} cron list --all
  hermes-autodev gateway status
  hermes-autodev dashboard open
EOF
