#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG_FILE=""
NON_INTERACTIVE=0
SKIP_INSTALL=0
SKIP_PROJECT=0
FORCE_INSTALL=1
LOG_FILE=""
NO_LOG=0

usage() {
  cat <<'EOF'
Usage:
  ./wizard.sh [options]

Interactive VPS setup wizard for the Hermes autonomous dev team.

Options:
  --config FILE         Load answers from a KEY=value config file.
  --non-interactive     Do not prompt; require config/env values.
  --skip-install        Do not install/update Hermes profiles.
  --skip-project        Configure profiles only; do not bootstrap a project.
  --no-force            Do not pass --force to profile install.
  --log-file FILE       Write setup transcript to FILE.
  --no-log              Do not write a setup transcript.
  -h, --help            Show this help.

Examples:
  ./wizard.sh
  ./wizard.sh --config setup.example.env
  ./wizard.sh --config client.env --non-interactive
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --skip-project)
      SKIP_PROJECT=1
      shift
      ;;
    --no-force)
      FORCE_INSTALL=0
      shift
      ;;
    --log-file)
      LOG_FILE="$2"
      shift 2
      ;;
    --no-log)
      NO_LOG=1
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

start_logging() {
  [[ "${NO_LOG}" -eq 0 ]] || return 0

  if [[ -z "${LOG_FILE}" ]]; then
    local log_dir ts
    log_dir="${HOME}/.hermes/autodev/logs"
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "${log_dir}"
    LOG_FILE="${log_dir}/setup-wizard-${ts}.log"
  else
    mkdir -p "$(dirname "${LOG_FILE}")"
  fi

  touch "${LOG_FILE}"
  chmod 0600 "${LOG_FILE}" || true

  exec > >(tee -a "${LOG_FILE}") 2>&1

  echo "=== Hermes autonomous dev team setup wizard ==="
  echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "User: $(id -un 2>/dev/null || true)"
  echo "Host: $(hostname 2>/dev/null || true)"
  echo "Working directory: $(pwd)"
  echo "Package directory: ${ROOT_DIR}"
  echo "Log file: ${LOG_FILE}"
  echo
}

on_error() {
  local status="$?"
  local line="${BASH_LINENO[0]:-unknown}"
  echo
  echo "ERROR: setup wizard failed at line ${line} with exit status ${status}."
  exit "${status}"
}

on_exit() {
  local status="$?"
  [[ "${NO_LOG}" -eq 0 && -n "${LOG_FILE}" ]] || return 0
  echo
  echo "Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Exit status: ${status}"
  echo "Setup log: ${LOG_FILE}"
}

trap on_error ERR
trap on_exit EXIT
start_logging

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

load_config_file() {
  local file="$1"
  [[ -f "${file}" ]] || { echo "Config file not found: ${file}" >&2; exit 2; }

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -z "${line}" || "${line:0:1}" == "#" ]] && continue
    [[ "${line}" == export\ * ]] && line="${line#export }"
    [[ "${line}" == *"="* ]] || continue

    local key value
    key="$(trim "${line%%=*}")"
    value="${line#*=}"
    value="$(trim "${value}")"

    if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    if [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      export "${key}=${value}"
    fi
  done < "${file}"
}

env_get() {
  local file="$1"
  local key="$2"
  [[ -f "${file}" ]] || return 0
  python3 - "$file" "$key" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
target = sys.argv[2]
for raw in path.read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    if line.startswith("export "):
        line = line[7:].strip()
    key, value = line.split("=", 1)
    if key.strip() != target:
        continue
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        value = value[1:-1]
    print(value)
    break
PY
}

set_default_from_profiles() {
  local var="$1"
  local key="$2"
  shift 2
  [[ -n "${!var-}" ]] && return 0

  local profile value
  for profile in "$@"; do
    value="$(env_get "${HOME}/.hermes/profiles/${profile}/.env" "${key}")"
    if [[ -n "${value}" ]]; then
      printf -v "${var}" '%s' "${value}"
      export "${var}"
      return 0
    fi
  done
}

has_tty() {
  [[ -t 0 && -t 1 ]]
}

prompt_text() {
  local var="$1"
  local label="$2"
  local default="${3:-}"
  local secret="${4:-0}"
  local required="${5:-0}"
  local current="${!var-}"
  [[ -z "${current}" ]] && current="${default}"

  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    if [[ "${required}" -eq 1 && -z "${current}" ]]; then
      echo "Missing required config value: ${var}" >&2
      exit 2
    fi
    printf -v "${var}" '%s' "${current}"
    export "${var}"
    return 0
  fi

  if ! has_tty; then
    echo "No interactive terminal available. Pass --config FILE --non-interactive." >&2
    exit 2
  fi

  local shown answer
  if [[ "${secret}" -eq 1 && -n "${current}" ]]; then
    shown="already set"
  else
    shown="${current}"
  fi

  while true; do
    if [[ -n "${shown}" ]]; then
      printf '%s [%s]: ' "${label}" "${shown}"
    else
      printf '%s: ' "${label}"
    fi

    if [[ "${secret}" -eq 1 ]]; then
      IFS= read -rs answer
      printf '\n'
    else
      IFS= read -r answer
    fi

    [[ -z "${answer}" ]] && answer="${current}"
    if [[ "${required}" -eq 1 && -z "${answer}" ]]; then
      echo "This value is required."
      continue
    fi
    printf -v "${var}" '%s' "${answer}"
    export "${var}"
    return 0
  done
}

prompt_yes_no() {
  local var="$1"
  local label="$2"
  local default="${3:-yes}"
  local current="${!var-}"
  [[ -z "${current}" ]] && current="${default}"

  case "${current,,}" in
    1|yes|y|true|on) current="yes" ;;
    0|no|n|false|off) current="no" ;;
  esac

  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    case "${current,,}" in
      yes|y|1|true|on) printf -v "${var}" '1' ;;
      *) printf -v "${var}" '0' ;;
    esac
    export "${var}"
    return 0
  fi

  local suffix answer
  if [[ "${current}" == "yes" ]]; then
    suffix="Y/n"
  else
    suffix="y/N"
  fi

  while true; do
    printf '%s [%s]: ' "${label}" "${suffix}"
    IFS= read -r answer
    [[ -z "${answer}" ]] && answer="${current}"
    case "${answer,,}" in
      yes|y|1|true|on)
        printf -v "${var}" '1'
        export "${var}"
        return 0
        ;;
      no|n|0|false|off)
        printf -v "${var}" '0'
        export "${var}"
        return 0
        ;;
      *)
        echo "Answer yes or no."
        ;;
    esac
  done
}

write_profile_env() {
  local file="$1"
  shift
  local keys="$*"
  mkdir -p "$(dirname "${file}")"
  touch "${file}"
  chmod 0600 "${file}" || true

  AUTODEV_ENV_FILE="${file}" AUTODEV_KEYS="${keys}" python3 <<'PY'
from pathlib import Path
import os
import re

path = Path(os.environ["AUTODEV_ENV_FILE"])
keys = os.environ["AUTODEV_KEYS"].split()
updates = {key: os.environ.get(key, "") for key in keys}
safe = re.compile(r"^[A-Za-z0-9_@%+=:,./-]*$")

def encode(value: str) -> str:
    if value == "":
        return ""
    if safe.match(value):
        return value
    return "'" + value.replace("'", "'\"'\"'") + "'"

lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
seen = set()
out = []

for raw in lines:
    stripped = raw.strip()
    if not stripped or stripped.startswith("#") or "=" not in raw:
        out.append(raw)
        continue
    prefix = ""
    line = raw
    if stripped.startswith("export "):
        before, after = raw.split("export ", 1)
        prefix = before + "export "
        line = after
    key = line.split("=", 1)[0].strip()
    if key in updates:
        out.append(f"{prefix}{key}={encode(updates[key])}")
        seen.add(key)
    else:
        out.append(raw)

missing = [key for key in keys if key not in seen]
if missing and out and out[-1].strip():
    out.append("")
for key in missing:
    out.append(f"{key}={encode(updates[key])}")

path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

repo_slug() {
  local repo="$1"
  repo="${repo##*/}"
  repo="${repo%.git}"
  repo="$(printf '%s' "${repo}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-')"
  repo="${repo#-}"
  repo="${repo%-}"
  printf '%s' "${repo}"
}

maybe_configure_git() {
  prompt_yes_no HERMES_AUTODEV_CONFIGURE_GIT "Configure global Git name/email on this VPS?" "yes"
  [[ "${HERMES_AUTODEV_CONFIGURE_GIT}" == "1" ]] || return 0

  local existing_name existing_email
  existing_name="$(git config --global user.name 2>/dev/null || true)"
  existing_email="$(git config --global user.email 2>/dev/null || true)"
  prompt_text GIT_USER_NAME "Git user.name" "${existing_name}" 0 0
  prompt_text GIT_USER_EMAIL "Git user.email" "${existing_email}" 0 0

  if [[ -n "${GIT_USER_NAME}" ]]; then
    git config --global user.name "${GIT_USER_NAME}"
  fi
  if [[ -n "${GIT_USER_EMAIL}" ]]; then
    git config --global user.email "${GIT_USER_EMAIL}"
  fi
}

maybe_configure_gh_cli() {
  [[ -n "${GITHUB_TOKEN-}" ]] || return 0
  command -v gh >/dev/null 2>&1 || return 0

  prompt_yes_no HERMES_AUTODEV_AUTH_GH "Use GITHUB_TOKEN to authenticate the GitHub CLI too?" "no"
  [[ "${HERMES_AUTODEV_AUTH_GH}" == "1" ]] || return 0

  if gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is already authenticated."
    return 0
  fi

  if printf '%s\n' "${GITHUB_TOKEN}" | gh auth login --with-token; then
    echo "GitHub CLI authenticated."
  else
    echo "Warning: GitHub CLI authentication failed. Profile env files still contain GITHUB_TOKEN." >&2
  fi
}

maybe_generate_ssh_key() {
  local repo="${HERMES_AUTODEV_REPO_URL-}"
  [[ "${repo}" == git@* || "${repo}" == ssh://* ]] || return 0
  [[ ! -f "${HOME}/.ssh/id_ed25519.pub" ]] || return 0

  prompt_yes_no HERMES_AUTODEV_GENERATE_SSH_KEY "Repo URL uses SSH, but no id_ed25519 key exists. Generate one?" "yes"
  [[ "${HERMES_AUTODEV_GENERATE_SSH_KEY}" == "1" ]] || return 0

  mkdir -p "${HOME}/.ssh"
  chmod 0700 "${HOME}/.ssh"
  local comment="${GIT_USER_EMAIL:-hermes-autodev@$(hostname)}"
  ssh-keygen -t ed25519 -C "${comment}" -f "${HOME}/.ssh/id_ed25519" -N ""
  echo
  echo "Add this public key to GitHub/GitLab before cloning private SSH repos:"
  echo
  cat "${HOME}/.ssh/id_ed25519.pub"
  echo
}

maybe_verify_codex() {
  command -v codex >/dev/null 2>&1 || {
    echo "Warning: codex command not found. Install/authenticate Codex before assigning Developer tasks." >&2
    return 0
  }

  prompt_yes_no HERMES_AUTODEV_VERIFY_CODEX "Run a quick Codex auth smoke test now?" "no"
  [[ "${HERMES_AUTODEV_VERIFY_CODEX}" == "1" ]] || return 0

  if codex exec "echo CODEX_OK"; then
    echo "Codex smoke test passed."
  else
    echo "Warning: Codex smoke test failed. Set OPENAI_API_KEY or run codex login before using Developer." >&2
  fi
}

bootstrap_project() {
  [[ "${SKIP_PROJECT}" -eq 0 ]] || return 0

  local default_bootstrap="no"
  if [[ -n "${HERMES_AUTODEV_PROJECT_PATH-}" || -n "${HERMES_AUTODEV_REPO_URL-}" ]]; then
    default_bootstrap="yes"
  fi

  prompt_yes_no HERMES_AUTODEV_BOOTSTRAP_PROJECT "Bootstrap a project board, watchdog, cron jobs, and kickoff task now?" "${default_bootstrap}"
  [[ "${HERMES_AUTODEV_BOOTSTRAP_PROJECT}" == "1" ]] || return 0

  if [[ "${NON_INTERACTIVE}" -eq 1 && -z "${HERMES_AUTODEV_PROJECT_PATH-}" && -z "${HERMES_AUTODEV_REPO_URL-}" ]]; then
    echo "Non-interactive project bootstrap requires HERMES_AUTODEV_PROJECT_PATH or HERMES_AUTODEV_REPO_URL." >&2
    exit 2
  fi

  prompt_text HERMES_AUTODEV_REPO_URL "Project git clone URL (optional if repo already exists)" "${HERMES_AUTODEV_REPO_URL-}" 0 0

  local slug_default path_default
  slug_default="${HERMES_AUTODEV_PROJECT_SLUG-}"
  if [[ -z "${slug_default}" && -n "${HERMES_AUTODEV_REPO_URL-}" ]]; then
    slug_default="$(repo_slug "${HERMES_AUTODEV_REPO_URL}")"
  fi
  if [[ -z "${slug_default}" ]]; then
    slug_default="my-project"
  fi

  path_default="${HERMES_AUTODEV_PROJECT_PATH-}"
  if [[ -z "${path_default}" && -n "${slug_default}" ]]; then
    path_default="${HOME}/projects/${slug_default}"
  fi

  prompt_text HERMES_AUTODEV_PROJECT_PATH "Absolute project repo path" "${path_default}" 0 1
  prompt_text HERMES_AUTODEV_PROJECT_SLUG "Project board slug" "${slug_default}" 0 1
  prompt_text HERMES_AUTODEV_PROJECT_NAME "Human-readable project name" "${HERMES_AUTODEV_PROJECT_NAME-}" 0 0
  prompt_text HERMES_AUTODEV_PROJECT_DESCRIPTION "Project description" "${HERMES_AUTODEV_PROJECT_DESCRIPTION-}" 0 0
  prompt_text HERMES_AUTODEV_DELIVER "PM sweep delivery target (local, telegram, signal:+number)" "${HERMES_AUTODEV_DELIVER:-local}" 0 0
  prompt_yes_no HERMES_AUTODEV_CREATE_CRON "Create/resume watchdog and PM sweep cron jobs?" "${HERMES_AUTODEV_CREATE_CRON:-yes}"
  prompt_yes_no HERMES_AUTODEV_START_GATEWAY "Start the Project Manager gateway now?" "${HERMES_AUTODEV_START_GATEWAY:-yes}"

  maybe_generate_ssh_key

  local args=(--project-path "${HERMES_AUTODEV_PROJECT_PATH}" --project-slug "${HERMES_AUTODEV_PROJECT_SLUG}")
  [[ -n "${HERMES_AUTODEV_REPO_URL-}" ]] && args+=(--repo-url "${HERMES_AUTODEV_REPO_URL}")
  [[ -n "${HERMES_AUTODEV_PROJECT_NAME-}" ]] && args+=(--project-name "${HERMES_AUTODEV_PROJECT_NAME}")
  [[ -n "${HERMES_AUTODEV_PROJECT_DESCRIPTION-}" ]] && args+=(--project-description "${HERMES_AUTODEV_PROJECT_DESCRIPTION}")
  [[ -n "${HERMES_AUTODEV_DELIVER-}" ]] && args+=(--deliver "${HERMES_AUTODEV_DELIVER}")
  if [[ "${HERMES_AUTODEV_CREATE_CRON}" == "1" ]]; then
    args+=(--cron)
  else
    args+=(--no-cron)
  fi
  if [[ "${HERMES_AUTODEV_START_GATEWAY}" == "1" ]]; then
    args+=(--start-gateway)
  else
    args+=(--no-start-gateway)
  fi

  "${ROOT_DIR}/scripts/setup-project.sh" "${args[@]}"
}

if [[ -n "${CONFIG_FILE}" ]]; then
  load_config_file "${CONFIG_FILE}"
fi

case "${HERMES_AUTODEV_FORCE_PROFILE_INSTALL:-}" in
  0|no|No|NO|false|False|FALSE)
    FORCE_INSTALL=0
    ;;
esac

echo "Hermes autonomous dev team setup wizard"
echo

if [[ "${SKIP_INSTALL}" -eq 0 ]]; then
  install_args=(-y)
  [[ "${FORCE_INSTALL}" -eq 1 ]] && install_args+=(--force)
  if [[ "${HERMES_AUTODEV_INSTALL_HERMES:-1}" =~ ^(0|no|false)$ ]]; then
    install_args+=(--no-install-hermes)
  fi
  "${ROOT_DIR}/install.sh" "${install_args[@]}"
fi

set_default_from_profiles OPENROUTER_API_KEY OPENROUTER_API_KEY project-manager frontend-designer developer tester
set_default_from_profiles GITHUB_TOKEN GITHUB_TOKEN project-manager developer tester
set_default_from_profiles TELEGRAM_BOT_TOKEN TELEGRAM_BOT_TOKEN project-manager
set_default_from_profiles TELEGRAM_ALLOWED_USERS TELEGRAM_ALLOWED_USERS project-manager
set_default_from_profiles SIGNAL_HTTP_URL SIGNAL_HTTP_URL project-manager
set_default_from_profiles SIGNAL_ACCOUNT SIGNAL_ACCOUNT project-manager
set_default_from_profiles SIGNAL_ALLOWED_USERS SIGNAL_ALLOWED_USERS project-manager
set_default_from_profiles CODEX_HOME CODEX_HOME developer
set_default_from_profiles OPENAI_API_KEY OPENAI_API_KEY developer
set_default_from_profiles HERMES_LOG_LLM_OUTPUTS HERMES_LOG_LLM_OUTPUTS project-manager frontend-designer developer tester
set_default_from_profiles HERMES_LLM_OUTPUT_LOG_MAX_CHARS HERMES_LLM_OUTPUT_LOG_MAX_CHARS project-manager frontend-designer developer tester
HERMES_LOG_LLM_OUTPUTS="${HERMES_LOG_LLM_OUTPUTS:-0}"
HERMES_LLM_OUTPUT_LOG_MAX_CHARS="${HERMES_LLM_OUTPUT_LOG_MAX_CHARS:-20000}"
export HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS

echo
echo "Profile credentials"
prompt_text OPENROUTER_API_KEY "OpenRouter API key for Hermes profiles" "${OPENROUTER_API_KEY-}" 1 0
prompt_text GITHUB_TOKEN "GitHub token for issues/PRs/CI (optional)" "${GITHUB_TOKEN-}" 1 0
prompt_text OPENAI_API_KEY "OpenAI API key for Codex on this VPS (optional if using codex login)" "${OPENAI_API_KEY-}" 1 0
prompt_text CODEX_HOME "Codex auth/config directory override (blank uses ~/.codex)" "${CODEX_HOME-}" 0 0

echo
echo "Owner messaging"
prompt_text TELEGRAM_BOT_TOKEN "Telegram bot token for PM gateway (optional)" "${TELEGRAM_BOT_TOKEN-}" 1 0
prompt_text TELEGRAM_ALLOWED_USERS "Telegram allowed user IDs, comma-separated (optional)" "${TELEGRAM_ALLOWED_USERS-}" 0 0
prompt_text SIGNAL_HTTP_URL "Signal REST bridge URL (optional)" "${SIGNAL_HTTP_URL-}" 0 0
prompt_text SIGNAL_ACCOUNT "Signal account identifier (optional)" "${SIGNAL_ACCOUNT-}" 0 0
prompt_text SIGNAL_ALLOWED_USERS "Signal allowed users (optional)" "${SIGNAL_ALLOWED_USERS-}" 0 0

write_profile_env "${HOME}/.hermes/profiles/project-manager/.env" \
  OPENROUTER_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS GITHUB_TOKEN \
  SIGNAL_HTTP_URL SIGNAL_ACCOUNT SIGNAL_ALLOWED_USERS \
  HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS
write_profile_env "${HOME}/.hermes/profiles/frontend-designer/.env" \
  OPENROUTER_API_KEY \
  HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS
write_profile_env "${HOME}/.hermes/profiles/developer/.env" \
  OPENROUTER_API_KEY GITHUB_TOKEN CODEX_HOME OPENAI_API_KEY \
  HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS
write_profile_env "${HOME}/.hermes/profiles/tester/.env" \
  OPENROUTER_API_KEY GITHUB_TOKEN \
  HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS

echo "Profile env files updated under ~/.hermes/profiles/*/.env"

maybe_configure_git
maybe_configure_gh_cli
maybe_verify_codex
bootstrap_project

prompt_yes_no HERMES_AUTODEV_RUN_DOCTOR "Run setup doctor now?" "${HERMES_AUTODEV_RUN_DOCTOR:-yes}"
if [[ "${HERMES_AUTODEV_RUN_DOCTOR}" == "1" ]]; then
  if [[ -n "${HERMES_AUTODEV_PROJECT_SLUG-}" && "${HERMES_AUTODEV_BOOTSTRAP_PROJECT:-0}" == "1" ]]; then
    "${ROOT_DIR}/scripts/doctor.sh" --project-slug "${HERMES_AUTODEV_PROJECT_SLUG}" || true
  else
    "${ROOT_DIR}/scripts/doctor.sh" || true
  fi
fi

cat <<'EOF'

Setup wizard complete.

For future package updates:
  git pull
  ./install.sh -y --force

For another project on this VPS:
  ./wizard.sh --skip-install
EOF
