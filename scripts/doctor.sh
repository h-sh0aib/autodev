#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROJECT_SLUG=""
PM_PROFILE="project-manager"

usage() {
  cat <<'EOF'
Usage:
  hermes-autodev doctor [--project-slug SLUG]

Checks the host, Hermes release, team profiles, repository tools, lifecycle
launcher, Project Manager gateway, dashboard GUI, and an optional project.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-slug)
      [[ $# -ge 2 ]] || { echo "--project-slug requires a value." >&2; exit 2; }
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

ok() { printf 'ok    %s\n' "$*"; }
warn() { printf 'warn  %s\n' "$*"; }
fail() { printf 'fail  %s\n' "$*"; }
heading() { printf '\n%s\n' "$*"; }

status=0

profile_model_value() {
  local file="$1"
  local key="$2"
  [[ -f "${file}" ]] || return 1
  autodev_python - "${file}" "${key}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
target = sys.argv[2]
in_model = False
for raw in path.read_text(encoding="utf-8").splitlines():
    if raw.strip() == "model:" and not raw.startswith((" ", "\t")):
        in_model = True
        continue
    if in_model and raw and not raw.startswith((" ", "\t")):
        break
    if in_model:
        match = re.match(r"^\s+([A-Za-z0-9_]+):\s*(.*?)\s*$", raw)
        if match and match.group(1) == target:
            print(match.group(2).strip("'\""))
            break
PY
}

env_file_value() {
  local file="$1"
  local key="$2"
  autodev_dotenv_value "${file}" "${key}"
}

heading "Host"
if [[ "$(uname -s 2>/dev/null || true)" == "Linux" ]]; then
  ok "environment: $(autodev_detect_environment)"
else
  fail "this runtime must be Linux or WSL2"
  status=1
fi
ok "account: $(id -un) (home ${HOME})"
if [[ "$(id -u)" -eq 0 ]]; then
  warn "running agents as root is discouraged; use a dedicated unprivileged account"
fi

for required_command in git curl; do
  if command -v "${required_command}" >/dev/null 2>&1; then
    ok "${required_command}: $(command -v "${required_command}")"
  else
    fail "${required_command} command not found"
    status=1
  fi
done

heading "Hermes and profiles"
if command -v hermes >/dev/null 2>&1; then
  hermes_version="$(autodev_hermes_version || true)"
  if autodev_version_at_least "${hermes_version}" "${AUTODEV_MIN_HERMES_VERSION}"; then
    ok "Hermes ${hermes_version} (required ${AUTODEV_MIN_HERMES_VERSION}+)"
  else
    fail "Hermes ${hermes_version:-unknown}; update to ${AUTODEV_MIN_HERMES_VERSION}+ with 'hermes-autodev update'"
    status=1
  fi
else
  fail "hermes command not found"
  status=1
fi

for profile in "${AUTODEV_TEAM_PROFILES[@]}"; do
  profile_dir="$(autodev_profile_dir "${profile}")"
  profile_config="${profile_dir}/config.yaml"
  if [[ ! -d "${profile_dir}" ]]; then
    fail "profile missing: ${profile}"
    status=1
    continue
  fi

  provider="$(profile_model_value "${profile_config}" provider 2>/dev/null || true)"
  model="$(profile_model_value "${profile_config}" default 2>/dev/null || true)"
  if [[ -n "${provider}" && -n "${model}" ]]; then
    ok "${profile}: ${provider}/${model}"
  else
    fail "${profile}: model provider/default is incomplete"
    status=1
  fi

  case "${provider}" in
    openrouter|openai-codex|anthropic)
      auth_output="$(hermes -p "${profile}" auth status "${provider}" 2>&1 || true)"
      if [[ "${auth_output,,}" =~ logged[[:space:]]+in ]]; then
        ok "${profile}: ${provider} credentials available"
      else
        fail "${profile}: ${provider} is not authenticated; run 'hermes -p ${profile} auth add ${provider}'"
        status=1
      fi
      ;;
  esac

  if [[ ! -f "${profile_dir}/.env" ]]; then
    warn "${profile}: .env has not been created by the wizard"
  fi
done

heading "Development and repository tools"
if command -v codex >/dev/null 2>&1; then
  codex_version="$(codex --version 2>/dev/null || printf 'version unknown')"
  ok "codex: ${codex_version} ($(command -v codex))"
  developer_env="$(autodev_profile_dir developer)/.env"
  configured_codex_home="$(env_file_value "${developer_env}" CODEX_HOME 2>/dev/null || true)"
  configured_openai_key="$(env_file_value "${developer_env}" OPENAI_API_KEY 2>/dev/null || true)"
  codex_login_status=1
  if [[ -n "${configured_codex_home}" ]]; then
    CODEX_HOME="${configured_codex_home}" codex login status >/dev/null 2>&1 && codex_login_status=0
  else
    codex login status >/dev/null 2>&1 && codex_login_status=0
  fi
  if [[ "${codex_login_status}" -eq 0 ]]; then
    ok "Codex login is available"
  elif [[ -n "${configured_openai_key}" ]]; then
    ok "Codex API-key credential is configured for Developer"
  else
    fail "Codex is not authenticated; run 'codex login' or configure OPENAI_API_KEY"
    status=1
  fi
else
  fail "codex command not found; Developer needs Codex installed and authenticated"
  status=1
fi
if command -v gh >/dev/null 2>&1; then
  ok "GitHub CLI: $(command -v gh)"
else
  warn "gh not installed; GitHub token/API fallbacks can still be used"
fi
if command -v glab >/dev/null 2>&1; then
  ok "GitLab CLI: $(command -v glab)"
else
  warn "glab not installed; GitLab token/API fallbacks can still be used"
fi

wrapper="$(autodev_profile_dir developer)/bin/codex-network-exec"
if [[ -x "${wrapper}" ]]; then
  ok "Codex network wrapper installed"
else
  fail "Codex network wrapper missing or not executable; rerun 'hermes-autodev install -y'"
  status=1
fi

heading "Package lifecycle"
launcher="${HOME}/.local/bin/hermes-autodev"
install_state="$(autodev_state_dir)/install.env"
install_pointer="$(autodev_install_pointer)"
if [[ -x "${launcher}" ]]; then
  ok "launcher: ${launcher}"
else
  warn "launcher missing; rerun 'bash ./install.sh -y' (local 'bash ./autodev.sh' still works)"
fi
if [[ -r "${install_state}" ]]; then
  ok "install metadata: ${install_state}"
else
  warn "install metadata missing; update/uninstall will use this checkout only"
fi
if [[ -r "${install_pointer}" ]]; then
  ok "runtime pointer: ${install_pointer}"
else
  warn "runtime pointer missing; custom HERMES_HOME will not be rediscovered in a fresh shell"
fi

heading "Services and GUI"
if command -v hermes >/dev/null 2>&1; then
  if bash "${ROOT_DIR}/scripts/gateway.sh" status; then
    ok "Project Manager gateway is running"
  else
    warn "Project Manager gateway is stopped; start it with 'hermes-autodev gateway start'"
  fi
  hermes -p "${PM_PROFILE}" cron status 2>/dev/null || warn "Hermes cron scheduler is not reporting ready"
fi

dashboard_state="$(autodev_state_dir)/dashboard.env"
if [[ -r "${dashboard_state}" ]]; then
  ok "dashboard configured: ${dashboard_state}"
  if bash "${ROOT_DIR}/scripts/dashboard.sh" status; then
    ok "dashboard is healthy"
  else
    warn "dashboard is stopped or unhealthy; start it with 'hermes-autodev dashboard open'"
  fi
  bash "${ROOT_DIR}/scripts/dashboard.sh" access
else
  warn "dashboard not configured; run 'hermes-autodev dashboard open'"
fi

if [[ -n "${PROJECT_SLUG}" ]]; then
  heading "Project ${PROJECT_SLUG}"
  config="$(autodev_state_dir)/projects/${PROJECT_SLUG}.env"
  if [[ -f "${config}" ]]; then
    ok "project config: ${config}"
    # This owner-only file is generated with shell-safe %q values.
    # shellcheck disable=SC1090
    source "${config}"
    project_scm_provider="${HERMES_AUTODEV_SCM_PROVIDER:-generic}"
    ok "SCM provider: ${project_scm_provider}"
    pm_env="$(autodev_profile_dir "${PM_PROFILE}")/.env"
    case "${project_scm_provider}" in
      gitlab)
        gitlab_token="$(env_file_value "${pm_env}" GITLAB_TOKEN 2>/dev/null || true)"
        gitlab_host="$(env_file_value "${pm_env}" GITLAB_HOST 2>/dev/null || true)"
        gitlab_host="${gitlab_host:-https://gitlab.com}"
        gitlab_host="${gitlab_host#https://}"
        gitlab_host="${gitlab_host#http://}"
        gitlab_host="${gitlab_host%%/*}"
        if command -v glab >/dev/null 2>&1 &&
           glab auth status --hostname "${gitlab_host}" >/dev/null 2>&1; then
          ok "GitLab CLI authenticated for ${gitlab_host}"
        elif [[ -n "${gitlab_token}" ]]; then
          ok "GitLab REST token configured for ${gitlab_host} (glab login unavailable)"
        else
          fail "GitLab credentials missing for ${gitlab_host}; rerun setup or authenticate glab"
          status=1
        fi
        ;;
      github)
        github_token="$(env_file_value "${pm_env}" GITHUB_TOKEN 2>/dev/null || true)"
        if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
          ok "GitHub CLI authenticated"
        elif [[ -n "${github_token}" ]]; then
          ok "GitHub REST token configured (gh login unavailable)"
        else
          fail "GitHub credentials missing; rerun setup or authenticate gh"
          status=1
        fi
        ;;
    esac
    if [[ "$(git -C "${HERMES_AUTODEV_REPO:-}" rev-parse --is-inside-work-tree 2>/dev/null || true)" == "true" ]]; then
      ok "Git checkout: ${HERMES_AUTODEV_REPO}"
    else
      fail "configured repository is missing or not a Git checkout: ${HERMES_AUTODEV_REPO:-unset}"
      status=1
    fi
  else
    fail "project config missing: ${config}"
    status=1
  fi
  if command -v hermes >/dev/null 2>&1; then
    for project_profile in "${AUTODEV_TEAM_PROFILES[@]}"; do
      if hermes -p "${project_profile}" project show "${PROJECT_SLUG}" >/dev/null 2>&1; then
        ok "Hermes GUI project is registered for ${project_profile}"
      else
        fail "Hermes GUI project is missing for ${project_profile}; rerun project setup for ${PROJECT_SLUG}"
        status=1
      fi
    done
    hermes -p "${PM_PROFILE}" kanban --board "${PROJECT_SLUG}" stats || status=1
    hermes -p "${PM_PROFILE}" kanban --board "${PROJECT_SLUG}" list || true
  fi
fi

printf '\nDoctor result: '
if [[ "${status}" -eq 0 ]]; then
  printf 'ready (warnings may identify optional features).\n'
else
  printf 'action required.\n'
fi

exit "${status}"
