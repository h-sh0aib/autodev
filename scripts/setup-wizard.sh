#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
HERMES_HOME_DIR="$(autodev_hermes_home)"

CONFIG_FILE=""
NON_INTERACTIVE=0
SKIP_INSTALL=0
SKIP_PROJECT=0
SKIP_GUI=0
FORCE_INSTALL=0
FORCE_INSTALL_EXPLICIT=0
LOG_FILE=""
NO_LOG=0
WIZARD_HAS_TTY=0
[[ -t 0 && -t 1 ]] && WIZARD_HAS_TTY=1

TEAM_PROFILES=("${AUTODEV_TEAM_PROFILES[@]}")
PREINSTALL_MODEL_BLOCKS=()
PREINSTALL_PM_PROVIDER=""
PREINSTALL_PM_MODEL=""
PREINSTALL_SECURITY_PROVIDER=""
PREINSTALL_SECURITY_MODEL=""

usage() {
  cat <<'EOF'
Usage:
  bash ./wizard.sh [options]

Modern setup wizard for a local Linux computer, WSL2, or remote Linux host.

Options:
  --config FILE         Load answers from a KEY=value config file.
  --non-interactive     Do not prompt; require config/env values.
  --skip-install        Do not install/update Hermes profiles.
  --skip-project        Configure profiles only; do not bootstrap a project.
  --skip-gui            Do not configure the Hermes web dashboard.
  --force               Reset package-owned profile config to source defaults.
                        Existing config/auth/data are preserved by default.
  --no-force            Preserve existing profile settings (the default).
  --log-file FILE       Write setup transcript to FILE.
  --no-log              Do not write a setup transcript.
  -h, --help            Show this help.

Examples:
  bash ./wizard.sh
  bash ./wizard.sh --config setup.example.env
  bash ./wizard.sh --config client.env --non-interactive
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { echo "--config requires a file path." >&2; exit 2; }
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
    --skip-gui)
      SKIP_GUI=1
      shift
      ;;
    --force)
      FORCE_INSTALL=1
      FORCE_INSTALL_EXPLICIT=1
      shift
      ;;
    --no-force)
      FORCE_INSTALL=0
      FORCE_INSTALL_EXPLICIT=1
      shift
      ;;
    --log-file)
      [[ $# -ge 2 ]] || { echo "--log-file requires a file path." >&2; exit 2; }
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
    log_dir="${HERMES_HOME_DIR}/autodev/logs"
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "${log_dir}"
    chmod 0700 "${HERMES_HOME_DIR}/autodev" "${log_dir}" 2>/dev/null || true
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

section() {
  printf '\n== %s ==\n' "$1"
}

load_config_file() {
  local file="$1"
  [[ -f "${file}" ]] || { echo "Config file not found: ${file}" >&2; exit 2; }
  if ! chmod 0600 "${file}" 2>/dev/null; then
    echo "Warning: could not restrict setup config permissions to owner-only: ${file}" >&2
  fi

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

    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    case "${key}" in
      HERMES_AUTODEV_INSTALL_HERMES|HERMES_AUTODEV_UPDATE_HERMES|\
      HERMES_AUTODEV_FORCE_PROFILE_INSTALL|HERMES_AUTODEV_MODEL_PROVIDER|\
      HERMES_AUTODEV_HERMES_MODEL|HERMES_AUTODEV_SECURITY_MODEL|\
      HERMES_AUTODEV_AUTH_HERMES_SUBSCRIPTION|HERMES_AUTODEV_SCM_PROVIDER|\
      HERMES_AUTODEV_AUTH_GH|HERMES_AUTODEV_AUTH_GLAB|\
      HERMES_AUTODEV_CONFIGURE_GIT|HERMES_AUTODEV_INSTALL_CODEX|\
      HERMES_AUTODEV_AUTH_CODEX|HERMES_AUTODEV_VERIFY_CODEX|\
      HERMES_AUTODEV_BOOTSTRAP_PROJECT|\
      HERMES_AUTODEV_REPO_URL|HERMES_AUTODEV_PROJECT_PATH|\
      HERMES_AUTODEV_PROJECT_SLUG|HERMES_AUTODEV_PROJECT_NAME|\
      HERMES_AUTODEV_PROJECT_DESCRIPTION|HERMES_AUTODEV_DELIVER|\
      HERMES_AUTODEV_CREATE_CRON|HERMES_AUTODEV_START_GATEWAY|\
      HERMES_AUTODEV_GENERATE_SSH_KEY|HERMES_AUTODEV_GUI_MODE|\
      HERMES_AUTODEV_GUI_PORT|HERMES_AUTODEV_GUI_PERSIST|\
      HERMES_AUTODEV_GUI_START|HERMES_AUTODEV_RUN_DOCTOR|\
      HERMES_AUTODEV_SETUP_PORTAL|AUTODEV_PORTAL_DOMAIN|\
      AUTODEV_PYTHON|OPENROUTER_API_KEY|ANTHROPIC_API_KEY|\
      GITHUB_TOKEN|GITLAB_TOKEN|GITLAB_HOST|OPENAI_API_KEY|CODEX_HOME|\
      TELEGRAM_BOT_TOKEN|TELEGRAM_ALLOWED_USERS|SIGNAL_HTTP_URL|SIGNAL_ACCOUNT|\
      SIGNAL_ALLOWED_USERS|GIT_USER_NAME|GIT_USER_EMAIL|HERMES_LOG_LLM_OUTPUTS|\
      HERMES_LLM_OUTPUT_LOG_MAX_CHARS)
        export "${key}=${value}"
        ;;
      *)
        echo "Ignoring unsupported setup config key: ${key}" >&2
        ;;
    esac
  done < "${file}"
}

validate_boolean_config() {
  local key value
  for key in "$@"; do
    [[ -v "${key}" ]] || continue
    value="${!key}"
    [[ -z "${value}" ]] && continue
    case "${value,,}" in
      1|yes|y|true|on|0|no|n|false|off) ;;
      *)
        echo "Invalid boolean for ${key}: ${value}. Use yes/no, true/false, or 1/0." >&2
        exit 2
        ;;
    esac
  done
}

env_get() {
  local file="$1"
  local key="$2"
  autodev_dotenv_value "${file}" "${key}" 2>/dev/null || true
}

set_default_from_profiles() {
  local var="$1"
  local key="$2"
  shift 2
  [[ -n "${!var-}" ]] && return 0

  local profile value
  for profile in "$@"; do
    value="$(env_get "$(autodev_profile_dir "${profile}")/.env" "${key}")"
    if [[ -n "${value}" ]]; then
      printf -v "${var}" '%s' "${value}"
      export "${var?}"
      return 0
    fi
  done
}

has_tty() {
  [[ "${WIZARD_HAS_TTY}" -eq 1 ]]
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
    export "${var?}"
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
    export "${var?}"
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
    *)
      if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
        echo "Invalid boolean for ${var}: ${current}. Use yes/no, true/false, or 1/0." >&2
        exit 2
      fi
      echo "Ignoring invalid ${var} value '${current}' and using the prompt default." >&2
      case "${default,,}" in
        0|no|n|false|off) current="no" ;;
        *) current="yes" ;;
      esac
      ;;
  esac

  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    case "${current,,}" in
      yes|y|1|true|on) printf -v "${var}" '1' ;;
      no|n|0|false|off) printf -v "${var}" '0' ;;
    esac
    export "${var?}"
    return 0
  fi

  if ! has_tty; then
    echo "No interactive terminal available. Pass --config FILE --non-interactive." >&2
    exit 2
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
        export "${var?}"
        return 0
        ;;
      no|n|0|false|off)
        printf -v "${var}" '0'
        export "${var?}"
        return 0
        ;;
      *)
        echo "Answer yes or no."
        ;;
    esac
  done
}

prompt_choice() {
  local var="$1"
  local label="$2"
  local default="$3"
  shift 3
  local choices=("$@")
  local current="${!var-}"
  [[ -z "${current}" ]] && current="${default}"

  local choice valid=0 answer
  for choice in "${choices[@]}"; do
    if [[ "${current,,}" == "${choice,,}" ]]; then
      current="${choice}"
      valid=1
      break
    fi
  done

  if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
    if [[ "${valid}" -ne 1 ]]; then
      echo "Invalid ${var}: ${current}. Allowed values: ${choices[*]}" >&2
      exit 2
    fi
    printf -v "${var}" '%s' "${current}"
    export "${var?}"
    return 0
  fi

  if ! has_tty; then
    echo "No interactive terminal available. Pass --config FILE --non-interactive." >&2
    exit 2
  fi

  [[ "${valid}" -eq 1 ]] || current="${default}"
  while true; do
    printf '%s\n' "${label}"
    local index
    for index in "${!choices[@]}"; do
      printf '  %d) %s\n' "$((index + 1))" "${choices[$index]}"
    done
    printf 'Selection [%s]: ' "${current}"
    IFS= read -r answer
    [[ -z "${answer}" ]] && answer="${current}"

    if [[ "${answer}" =~ ^[0-9]+$ ]] &&
       (( 10#${answer} >= 1 && 10#${answer} <= ${#choices[@]} )); then
      answer="${choices[$((10#${answer} - 1))]}"
    fi

    valid=0
    for choice in "${choices[@]}"; do
      if [[ "${answer,,}" == "${choice,,}" ]]; then
        answer="${choice}"
        valid=1
        break
      fi
    done
    if [[ "${valid}" -eq 1 ]]; then
      printf -v "${var}" '%s' "${answer}"
      export "${var?}"
      return 0
    fi
    echo "Choose one of: ${choices[*]}"
  done
}

write_profile_env() {
  local file="$1"
  shift
  local keys="$*"
  mkdir -p "$(dirname "${file}")"
  touch "${file}"
  chmod 0600 "${file}" || true

  AUTODEV_ENV_FILE="${file}" AUTODEV_KEYS="${keys}" autodev_python <<'PY'
from pathlib import Path
import os
import re
import tempfile

path = Path(os.environ["AUTODEV_ENV_FILE"])
keys = os.environ["AUTODEV_KEYS"].split()
updates = {key: os.environ.get(key, "") for key in keys}
safe = re.compile(r"^[A-Za-z0-9_@%+=:,./-]*$")

def encode(value: str) -> str:
    if value == "":
        return ""
    if safe.match(value):
        return value
    # Hermes reads profile files with python-dotenv, whose single-quoted form
    # supports backslash escapes for backslash and apostrophe.
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"

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

payload = "\n".join(out) + "\n"
fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
finally:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
PY
}

profile_model_value() {
  local file="$1"
  local key="$2"
  [[ -f "${file}" ]] || return 0
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
    if not in_model:
        continue
    match = re.match(r"^\s+([A-Za-z0-9_]+):\s*(.*?)\s*$", raw)
    if not match or match.group(1) != target:
        continue
    value = match.group(2)
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        value = value[1:-1]
    print(value)
    break
PY
}

profile_model_block() {
  local file="$1"
  [[ -f "${file}" ]] || return 0
  autodev_python - "${file}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
start = None
end = None
for index, raw in enumerate(lines):
    if raw == "model:":
        start = index
        break
if start is None:
    raise SystemExit(0)
for index in range(start + 1, len(lines)):
    if lines[index] and not lines[index].startswith((" ", "\t")):
        end = index
        break
if end is None:
    end = len(lines)
print("\n".join(lines[start:end]))
PY
}

capture_preinstall_models() {
  local profile config
  PREINSTALL_MODEL_BLOCKS=()
  for profile in "${TEAM_PROFILES[@]}"; do
    config="$(autodev_profile_dir "${profile}")/config.yaml"
    PREINSTALL_MODEL_BLOCKS+=("$(profile_model_block "${config}")")
  done

  PREINSTALL_PM_PROVIDER="$(profile_model_value "$(autodev_profile_dir project-manager)/config.yaml" provider)"
  PREINSTALL_PM_MODEL="$(profile_model_value "$(autodev_profile_dir project-manager)/config.yaml" default)"
  PREINSTALL_SECURITY_PROVIDER="$(profile_model_value "$(autodev_profile_dir security-tester)/config.yaml" provider)"
  PREINSTALL_SECURITY_MODEL="$(profile_model_value "$(autodev_profile_dir security-tester)/config.yaml" default)"
}

restore_profile_model_block() {
  local profile="$1"
  local block="$2"
  local file
  file="$(autodev_profile_dir "${profile}")/config.yaml"
  [[ -n "${block}" && -f "${file}" ]] || return 1

  AUTODEV_MODEL_BLOCK="${block}" autodev_python - "${file}" <<'PY'
from pathlib import Path
import os
import stat
import sys
import tempfile

path = Path(sys.argv[1])
block = os.environ["AUTODEV_MODEL_BLOCK"].splitlines()
lines = path.read_text(encoding="utf-8").splitlines()
start = None
end = None
for index, raw in enumerate(lines):
    if raw == "model:":
        start = index
        break
if start is None:
    raise SystemExit(f"top-level model block not found in {path}")
for index in range(start + 1, len(lines)):
    if lines[index] and not lines[index].startswith((" ", "\t")):
        end = index
        break
if end is None:
    end = len(lines)
payload = "\n".join(lines[:start] + block + lines[end:]) + "\n"
mode = stat.S_IMODE(path.stat().st_mode)
fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, mode)
    os.replace(temporary, path)
finally:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
PY
}

write_profile_model() {
  local profile="$1"
  local provider="$2"
  local model="$3"
  local file
  file="$(autodev_profile_dir "${profile}")/config.yaml"

  [[ -f "${file}" ]] || {
    echo "Profile config missing; cannot configure model: ${file}" >&2
    return 1
  }

  autodev_python - "${file}" "${provider}" "${model}" <<'PY'
from pathlib import Path
import json
import os
import stat
import sys
import tempfile

path = Path(sys.argv[1])
provider = sys.argv[2]
model = sys.argv[3]
lines = path.read_text(encoding="utf-8").splitlines()

start = None
end = None
for index, raw in enumerate(lines):
    if raw == "model:":
        start = index
        break
if start is None:
    raise SystemExit(f"top-level model block not found in {path}")
for index in range(start + 1, len(lines)):
    raw = lines[index]
    if raw and not raw.startswith((" ", "\t")):
        end = index
        break
if end is None:
    end = len(lines)

body = lines[start + 1:end]
child_indents = [
    len(raw) - len(raw.lstrip(" \t"))
    for raw in body
    if raw.strip() and not raw.lstrip().startswith("#")
]
child_indent = min(child_indents, default=2)
indent = " " * child_indent
managed = {"default", "model", "provider", "base_url", "api_mode"}
preserved = []
index = 0
while index < len(body):
    raw = body[index]
    stripped = raw.lstrip(" \t")
    width = len(raw) - len(stripped)
    key = stripped.split(":", 1)[0] if ":" in stripped else ""
    if width == child_indent and key in managed:
        index += 1
        while index < len(body):
            continuation = body[index]
            if not continuation.strip():
                index += 1
                continue
            continuation_width = len(continuation) - len(continuation.lstrip(" \t"))
            if continuation_width <= child_indent:
                break
            index += 1
        continue
    preserved.append(raw)
    index += 1

block = [
    "model:",
    f"{indent}default: {json.dumps(model)}",
    f"{indent}provider: {json.dumps(provider)}",
]
if provider == "openrouter":
    block.extend([
        f'{indent}base_url: "https://openrouter.ai/api/v1"',
        f'{indent}api_mode: "chat_completions"',
    ])
block.extend(preserved)

updated = lines[:start] + block + lines[end:]
payload = "\n".join(updated) + "\n"
mode = stat.S_IMODE(path.stat().st_mode)
fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, mode)
    os.replace(temporary, path)
finally:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
PY
}

configure_profile_models() {
  if [[ "${HERMES_AUTODEV_MODEL_PROVIDER}" == "keep" ]]; then
    local index profile restored=0
    for index in "${!TEAM_PROFILES[@]}"; do
      profile="${TEAM_PROFILES[$index]}"
      if restore_profile_model_block "${profile}" "${PREINSTALL_MODEL_BLOCKS[$index]-}"; then
        restored=$((restored + 1))
      fi
    done
    if [[ "${restored}" -gt 0 ]]; then
      echo "Restored the pre-install model configuration for ${restored} Hermes profile(s)."
    else
      echo "No pre-install model configuration was found; keeping the installed source defaults."
    fi
    return 0
  fi

  local profile model
  for profile in "${TEAM_PROFILES[@]}"; do
    model="${HERMES_AUTODEV_HERMES_MODEL}"
    if [[ "${profile}" == "security-tester" ]]; then
      model="${HERMES_AUTODEV_SECURITY_MODEL}"
    fi
    write_profile_model "${profile}" "${HERMES_AUTODEV_MODEL_PROVIDER}" "${model}"
  done
  echo "Hermes profiles configured for ${HERMES_AUTODEV_MODEL_PROVIDER} (${HERMES_AUTODEV_HERMES_MODEL})."
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
  prompt_yes_no HERMES_AUTODEV_CONFIGURE_GIT "Configure Git name/email for this Linux account?" "yes"
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

gitlab_hostname() {
  local value="${1:-https://gitlab.com}"
  value="${value#https://}"
  value="${value#http://}"
  value="${value%%/*}"
  printf '%s' "${value}"
}

normalize_gitlab_host() {
  local value="${GITLAB_HOST:-https://gitlab.com}"
  value="$(trim "${value}")"
  value="${value%/}"
  case "${value}" in
    http://*|https://*) ;;
    *) value="https://${value}" ;;
  esac
  [[ "${value}" =~ ^https?://[^/?#[:space:]]+(/[^?#[:space:]]*)?$ ]] || autodev_die \
    "GitLab base URL must contain a hostname and optional path, without credentials, query, or fragment: ${value}"
  GITLAB_HOST="${value}"
  export GITLAB_HOST
}

maybe_configure_glab_cli() {
  [[ -n "${GITLAB_TOKEN-}" ]] || return 0
  if ! command -v glab >/dev/null 2>&1; then
    echo "Warning: glab is not installed. GitLab API access can use GITLAB_TOKEN, but install glab for the full issue/MR/CI workflow." >&2
    return 0
  fi

  prompt_yes_no HERMES_AUTODEV_AUTH_GLAB "Use GITLAB_TOKEN to authenticate the GitLab CLI too?" "yes"
  [[ "${HERMES_AUTODEV_AUTH_GLAB}" == "1" ]] || return 0

  local hostname
  hostname="$(gitlab_hostname "${GITLAB_HOST:-https://gitlab.com}")"
  if glab auth status --hostname "${hostname}" >/dev/null 2>&1; then
    echo "GitLab CLI is already authenticated for ${hostname}."
    return 0
  fi

  if printf '%s\n' "${GITLAB_TOKEN}" | glab auth login --hostname "${hostname}" --stdin; then
    echo "GitLab CLI authenticated for ${hostname}."
  else
    echo "Warning: GitLab CLI authentication failed. Profile env files still contain GITLAB_TOKEN." >&2
  fi
}

maybe_authenticate_hermes_subscription() {
  case "${HERMES_AUTODEV_MODEL_PROVIDER}" in
    openai-codex|anthropic) ;;
    *) return 0 ;;
  esac

  local auth_default="yes"
  [[ "${NON_INTERACTIVE}" -eq 0 ]] || auth_default="no"
  if [[ "${HERMES_AUTODEV_MODEL_PROVIDER}" == "anthropic" && -n "${ANTHROPIC_API_KEY-}" ]]; then
    auth_default="no"
  fi
  prompt_yes_no HERMES_AUTODEV_AUTH_HERMES_SUBSCRIPTION \
    "Authenticate the selected subscription for every Hermes profile now?" \
    "${auth_default}"
  if [[ "${NON_INTERACTIVE}" -eq 1 && "${HERMES_AUTODEV_AUTH_HERMES_SUBSCRIPTION}" == "1" ]]; then
    echo "Subscription OAuth cannot run inside --non-interactive setup." >&2
    echo "Set HERMES_AUTODEV_AUTH_HERMES_SUBSCRIPTION=0, then run the printed per-profile auth commands." >&2
    exit 2
  fi
  if [[ "${HERMES_AUTODEV_AUTH_HERMES_SUBSCRIPTION}" != "1" ]]; then
    if [[ "${HERMES_AUTODEV_MODEL_PROVIDER}" == "anthropic" && -n "${ANTHROPIC_API_KEY-}" ]]; then
      echo "Claude subscription authentication skipped; Hermes profiles can use ANTHROPIC_API_KEY."
      return 0
    fi
    echo "Subscription authentication skipped. Run these commands before starting unattended agents:"
    local skipped_profile
    for skipped_profile in "${TEAM_PROFILES[@]}"; do
      if [[ "${HERMES_AUTODEV_MODEL_PROVIDER}" == "openai-codex" ]]; then
        echo "  hermes -p ${skipped_profile} auth add openai-codex"
      else
        echo "  hermes -p ${skipped_profile} auth add anthropic --type oauth"
      fi
    done
    return 0
  fi

  if [[ "${HERMES_AUTODEV_MODEL_PROVIDER}" == "anthropic" ]]; then
    echo "Note: Hermes subscription OAuth requires Claude Max plus extra-usage credits; Claude Pro and the included Max allowance are not used by this path."
  fi

  local profile auth_failures=0
  for profile in "${TEAM_PROFILES[@]}"; do
    echo "Authenticating Hermes profile ${profile} with ${HERMES_AUTODEV_MODEL_PROVIDER}..."
    if [[ "${HERMES_AUTODEV_MODEL_PROVIDER}" == "openai-codex" ]]; then
      if ! hermes -p "${profile}" auth add openai-codex; then
        echo "Warning: subscription authentication failed for ${profile}. Retry with: hermes -p ${profile} auth add openai-codex" >&2
        auth_failures=$((auth_failures + 1))
      fi
    elif ! hermes -p "${profile}" auth add anthropic --type oauth; then
      echo "Warning: subscription authentication failed for ${profile}. Retry with: hermes -p ${profile} auth add anthropic --type oauth" >&2
      auth_failures=$((auth_failures + 1))
    fi
  done
  [[ "${auth_failures}" -eq 0 ]] || autodev_die \
    "subscription authentication failed for ${auth_failures} profile(s); correct the reported login problem and rerun setup."
}

maybe_generate_ssh_key() {
  local repo="${HERMES_AUTODEV_REPO_URL-}"
  [[ "${repo}" == git@* || "${repo}" == ssh://* ]] || return 0
  [[ ! -f "${HOME}/.ssh/id_ed25519.pub" ]] || return 0
  if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    echo "An existing id_ed25519 private key was found, but its .pub file is missing." >&2
    echo "The wizard will not overwrite it. Recover the public key with:" >&2
    printf '  ssh-keygen -y -f %q > %q\n' \
      "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_ed25519.pub" >&2
    return 0
  fi

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
  if [[ "${NON_INTERACTIVE}" -eq 0 ]]; then
    echo "Add the key to the repository host now. Press Enter here when the key is active."
    IFS= read -r _
  fi
}

maybe_verify_codex() {
  command -v codex >/dev/null 2>&1 || {
    local install_default="yes"
    [[ "${NON_INTERACTIVE}" -eq 0 ]] || install_default="no"
    prompt_yes_no HERMES_AUTODEV_INSTALL_CODEX \
      "Codex CLI is missing. Install it with OpenAI's official Linux installer?" \
      "${HERMES_AUTODEV_INSTALL_CODEX:-${install_default}}"
    if [[ "${HERMES_AUTODEV_INSTALL_CODEX}" == "1" ]]; then
      command -v curl >/dev/null 2>&1 || {
        echo "Warning: curl is required to install Codex CLI." >&2
        return 0
      }
      local codex_installer
      codex_installer="$(mktemp)"
      if curl -fsSL https://chatgpt.com/codex/install.sh -o "${codex_installer}" &&
         bash "${codex_installer}"; then
        export PATH="${HOME}/.local/bin:${PATH}"
      else
        echo "Warning: Codex CLI installation failed. Retry with the official installer documented at https://learn.chatgpt.com/docs/codex/cli" >&2
      fi
      rm -f "${codex_installer}"
    fi
    command -v codex >/dev/null 2>&1 || {
      echo "Warning: codex command not found. Install and authenticate Codex before assigning Developer tasks." >&2
      return 0
    }
  }

  local codex_logged_in=0
  if [[ -n "${CODEX_HOME-}" ]]; then
    CODEX_HOME="${CODEX_HOME}" codex login status >/dev/null 2>&1 && codex_logged_in=1
  else
    codex login status >/dev/null 2>&1 && codex_logged_in=1
  fi

  if [[ "${codex_logged_in}" -ne 1 ]]; then
    local auth_default="yes"
    [[ "${NON_INTERACTIVE}" -eq 0 || -n "${OPENAI_API_KEY-}" ]] || auth_default="no"
    prompt_yes_no HERMES_AUTODEV_AUTH_CODEX \
      "Authenticate the Developer's Codex CLI now?" \
      "${HERMES_AUTODEV_AUTH_CODEX:-${auth_default}}"
    if [[ "${HERMES_AUTODEV_AUTH_CODEX}" == "1" ]]; then
      if [[ -n "${OPENAI_API_KEY-}" ]]; then
        if [[ -n "${CODEX_HOME-}" ]]; then
          printf '%s\n' "${OPENAI_API_KEY}" | CODEX_HOME="${CODEX_HOME}" codex login --with-api-key
        else
          printf '%s\n' "${OPENAI_API_KEY}" | codex login --with-api-key
        fi
      elif [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
        echo "Codex ChatGPT login cannot run inside --non-interactive setup." >&2
        echo "Set HERMES_AUTODEV_AUTH_CODEX=0 and run 'codex login' afterward, or provide OPENAI_API_KEY." >&2
        exit 2
      elif [[ "$(autodev_detect_environment)" == *-ssh ]]; then
        if [[ -n "${CODEX_HOME-}" ]]; then
          CODEX_HOME="${CODEX_HOME}" codex login --device-auth
        else
          codex login --device-auth
        fi
      elif [[ -n "${CODEX_HOME-}" ]]; then
        CODEX_HOME="${CODEX_HOME}" codex login
      else
        codex login
      fi
    else
      echo "Codex authentication skipped. Run 'codex login' before assigning Developer tasks." >&2
    fi
  else
    echo "Codex CLI is already authenticated."
  fi

  prompt_yes_no HERMES_AUTODEV_VERIFY_CODEX "Run a quick Codex auth smoke test now?" "no"
  [[ "${HERMES_AUTODEV_VERIFY_CODEX}" == "1" ]] || return 0

  if codex exec "echo CODEX_OK"; then
    echo "Codex smoke test passed."
  else
    echo "Warning: Codex smoke test failed. Set OPENAI_API_KEY or run codex login before using Developer." >&2
    echo "On a remote server, codex login prints a browser sign-in flow that you complete from your own computer." >&2
  fi
}

bootstrap_project() {
  [[ "${SKIP_PROJECT}" -eq 0 ]] || return 0

  section "First project"

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

  prompt_text HERMES_AUTODEV_PROJECT_PATH "Project repo path (absolute, relative, or ~/...)" "${path_default}" 0 1
  prompt_text HERMES_AUTODEV_PROJECT_SLUG "Project board slug" "${slug_default}" 0 1
  prompt_text HERMES_AUTODEV_PROJECT_NAME "Human-readable project name" "${HERMES_AUTODEV_PROJECT_NAME-}" 0 0
  prompt_text HERMES_AUTODEV_PROJECT_DESCRIPTION "Project description" "${HERMES_AUTODEV_PROJECT_DESCRIPTION-}" 0 0
  prompt_text HERMES_AUTODEV_DELIVER "PM sweep delivery target (local, telegram, signal:+number)" "${HERMES_AUTODEV_DELIVER:-local}" 0 0
  prompt_yes_no HERMES_AUTODEV_CREATE_CRON "Create/resume watchdog and PM sweep cron jobs?" "${HERMES_AUTODEV_CREATE_CRON:-yes}"
  prompt_yes_no HERMES_AUTODEV_START_GATEWAY "Start the Project Manager gateway now?" "${HERMES_AUTODEV_START_GATEWAY:-yes}"

  maybe_generate_ssh_key

  local args=(--project-path "${HERMES_AUTODEV_PROJECT_PATH}" --project-slug "${HERMES_AUTODEV_PROJECT_SLUG}")
  [[ -n "${HERMES_AUTODEV_REPO_URL-}" ]] && args+=(--repo-url "${HERMES_AUTODEV_REPO_URL}")
  case "${HERMES_AUTODEV_SCM_PROVIDER:-auto}" in
    github|gitlab) args+=(--scm-provider "${HERMES_AUTODEV_SCM_PROVIDER}") ;;
    none) args+=(--scm-provider generic) ;;
    *) args+=(--scm-provider auto) ;;
  esac
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
  [[ "${NON_INTERACTIVE}" -eq 1 ]] && args+=(--non-interactive)

  bash "${ROOT_DIR}/scripts/setup-project.sh" "${args[@]}"
}

configure_gui() {
  [[ "${SKIP_GUI}" -eq 0 ]] || return 0

  section "Web dashboard"
  echo "The dashboard provides browser chat, profile settings, Kanban boards, and scheduled-job controls."
  echo "It always listens on this machine only; remote access uses an SSH tunnel."

  prompt_choice HERMES_AUTODEV_GUI_MODE \
    "How will you access the GUI?" \
    "${HERMES_AUTODEV_GUI_MODE:-auto}" \
    auto local ssh off

  if [[ "${HERMES_AUTODEV_GUI_MODE}" == "off" ]]; then
    echo "Dashboard setup skipped. Run 'hermes-autodev dashboard open' whenever you want to enable it."
    return 0
  fi

  prompt_text HERMES_AUTODEV_GUI_PORT \
    "Dashboard loopback port" \
    "${HERMES_AUTODEV_GUI_PORT:-9119}" 0 1
  if [[ ! "${HERMES_AUTODEV_GUI_PORT}" =~ ^[0-9]+$ ]] ||
     (( 10#${HERMES_AUTODEV_GUI_PORT} < 1024 || 10#${HERMES_AUTODEV_GUI_PORT} > 65535 )); then
    echo "Dashboard port must be a number between 1024 and 65535." >&2
    exit 2
  fi
  HERMES_AUTODEV_GUI_PORT="$((10#${HERMES_AUTODEV_GUI_PORT}))"

  local detected_environment persist_default start_default
  detected_environment="$(autodev_detect_environment)"
  persist_default="no"
  case "${detected_environment}" in
    *-ssh|container) persist_default="yes" ;;
  esac
  prompt_yes_no HERMES_AUTODEV_GUI_PERSIST \
    "Install a user service so the dashboard survives logout and restarts?" \
    "${HERMES_AUTODEV_GUI_PERSIST:-${persist_default}}"

  start_default="yes"
  [[ "${NON_INTERACTIVE}" -eq 0 ]] || start_default="no"
  prompt_yes_no HERMES_AUTODEV_GUI_START \
    "Start the dashboard now?" \
    "${HERMES_AUTODEV_GUI_START:-${start_default}}"

  local dashboard_args=(--mode "${HERMES_AUTODEV_GUI_MODE}" --port "${HERMES_AUTODEV_GUI_PORT}")
  if [[ "${HERMES_AUTODEV_GUI_PERSIST}" == "1" ]]; then
    dashboard_args+=(--persist)
  else
    dashboard_args+=(--no-persist)
  fi

  bash "${ROOT_DIR}/scripts/dashboard.sh" configure "${dashboard_args[@]}" >/dev/null
  echo "Dashboard configured on loopback port ${HERMES_AUTODEV_GUI_PORT}."
  if [[ "${HERMES_AUTODEV_GUI_START}" == "1" ]]; then
    if [[ "${detected_environment}" == *-ssh || "${HERMES_AUTODEV_GUI_MODE}" == "ssh" ]]; then
      bash "${ROOT_DIR}/scripts/dashboard.sh" restart "${dashboard_args[@]}" --no-open
    else
      bash "${ROOT_DIR}/scripts/dashboard.sh" restart "${dashboard_args[@]}"
    fi
  else
    echo "Dashboard configured but not started. Start it later with: hermes-autodev dashboard open"
    bash "${ROOT_DIR}/scripts/dashboard.sh" access "${dashboard_args[@]}"
  fi
}

if [[ -n "${CONFIG_FILE}" ]]; then
  load_config_file "${CONFIG_FILE}"
fi

validate_boolean_config \
  HERMES_AUTODEV_INSTALL_HERMES HERMES_AUTODEV_FORCE_PROFILE_INSTALL \
  HERMES_AUTODEV_AUTH_HERMES_SUBSCRIPTION HERMES_AUTODEV_AUTH_GH \
  HERMES_AUTODEV_AUTH_GLAB HERMES_AUTODEV_CONFIGURE_GIT \
  HERMES_AUTODEV_INSTALL_CODEX HERMES_AUTODEV_AUTH_CODEX \
  HERMES_AUTODEV_VERIFY_CODEX HERMES_AUTODEV_BOOTSTRAP_PROJECT \
  HERMES_AUTODEV_CREATE_CRON HERMES_AUTODEV_START_GATEWAY \
  HERMES_AUTODEV_GENERATE_SSH_KEY HERMES_AUTODEV_GUI_PERSIST \
  HERMES_AUTODEV_GUI_START HERMES_AUTODEV_RUN_DOCTOR HERMES_AUTODEV_SETUP_PORTAL

autodev_require_linux

if [[ "${NON_INTERACTIVE}" -eq 0 ]] && ! has_tty; then
  echo "No interactive terminal detected; continuing in non-interactive mode."
  echo "Use --config FILE to supply reproducible answers."
  NON_INTERACTIVE=1
fi

# Capture current model settings so the explicit "keep" choice can retain them
# even when the operator intentionally requests a forced profile reset.
capture_preinstall_models

if [[ "${FORCE_INSTALL_EXPLICIT}" -eq 0 && -n "${HERMES_AUTODEV_FORCE_PROFILE_INSTALL-}" ]]; then
  if autodev_is_true "${HERMES_AUTODEV_FORCE_PROFILE_INSTALL}"; then
    FORCE_INSTALL=1
  else
    FORCE_INSTALL=0
  fi
fi

package_version="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION" 2>/dev/null || printf 'development')"
echo "Hermes autonomous dev team setup ${package_version}"
echo "Environment: $(autodev_detect_environment) | user: $(id -un) | home: ${HOME}"
if [[ "$(id -u)" -eq 0 ]]; then
  echo "Warning: this will install credentials and services for root. A dedicated unprivileged account is safer." >&2
fi

if [[ "${SKIP_INSTALL}" -eq 0 ]]; then
  section "Hermes and team profiles"
  install_args=(-y)
  [[ "${FORCE_INSTALL}" -eq 1 ]] && install_args+=(--force)
  if ! autodev_is_true "${HERMES_AUTODEV_INSTALL_HERMES:-1}"; then
    install_args+=(--no-install-hermes)
  fi
  case "${HERMES_AUTODEV_UPDATE_HERMES:-auto}" in
    1|yes|Yes|YES|true|True|TRUE|on|On|ON) install_args+=(--update-hermes) ;;
    0|no|No|NO|false|False|FALSE|off|Off|OFF) install_args+=(--no-update-hermes) ;;
    auto|AUTO|Auto|'') ;;
    *)
      echo "HERMES_AUTODEV_UPDATE_HERMES must be auto, yes, or no." >&2
      exit 2
      ;;
  esac
  bash "${ROOT_DIR}/install.sh" "${install_args[@]}"
fi

set_default_from_profiles OPENROUTER_API_KEY OPENROUTER_API_KEY project-manager frontend-designer developer tester security-tester
set_default_from_profiles ANTHROPIC_API_KEY ANTHROPIC_API_KEY project-manager frontend-designer developer tester security-tester
set_default_from_profiles GITHUB_TOKEN GITHUB_TOKEN project-manager developer tester security-tester
set_default_from_profiles GITLAB_TOKEN GITLAB_TOKEN project-manager developer tester security-tester
set_default_from_profiles GITLAB_HOST GITLAB_HOST project-manager developer tester security-tester
set_default_from_profiles TELEGRAM_BOT_TOKEN TELEGRAM_BOT_TOKEN project-manager
set_default_from_profiles TELEGRAM_ALLOWED_USERS TELEGRAM_ALLOWED_USERS project-manager
set_default_from_profiles SIGNAL_HTTP_URL SIGNAL_HTTP_URL project-manager
set_default_from_profiles SIGNAL_ACCOUNT SIGNAL_ACCOUNT project-manager
set_default_from_profiles SIGNAL_ALLOWED_USERS SIGNAL_ALLOWED_USERS project-manager
set_default_from_profiles CODEX_HOME CODEX_HOME developer
set_default_from_profiles OPENAI_API_KEY OPENAI_API_KEY developer
set_default_from_profiles HERMES_LOG_LLM_OUTPUTS HERMES_LOG_LLM_OUTPUTS project-manager frontend-designer developer tester security-tester
set_default_from_profiles HERMES_LLM_OUTPUT_LOG_MAX_CHARS HERMES_LLM_OUTPUT_LOG_MAX_CHARS project-manager frontend-designer developer tester security-tester
HERMES_LOG_LLM_OUTPUTS="${HERMES_LOG_LLM_OUTPUTS:-0}"
HERMES_LLM_OUTPUT_LOG_MAX_CHARS="${HERMES_LLM_OUTPUT_LOG_MAX_CHARS:-20000}"
export HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS

section "Hermes model provider"
cat <<'EOF'
Choose how the seven Hermes orchestration profiles call their model:
  openrouter    API-key billing through OpenRouter.
  openai-codex  ChatGPT/Codex sign-in; availability and quota follow the account.
  anthropic     Anthropic API key, or Claude Max OAuth with extra-usage credits.
  keep          Preserve the provider/model already configured per profile.

Claude Pro/base Max allowance is not accepted by Hermes' current OAuth path.
Subscription OAuth is interactive and is never stored in the setup answer file.
EOF
pm_config="$(autodev_profile_dir project-manager)/config.yaml"
security_config="$(autodev_profile_dir security-tester)/config.yaml"
installed_provider="$(profile_model_value "${pm_config}" provider)"
installed_model="$(profile_model_value "${pm_config}" default)"
installed_security_provider="$(profile_model_value "${security_config}" provider)"
installed_security_model="$(profile_model_value "${security_config}" default)"
existing_provider="${PREINSTALL_PM_PROVIDER:-${installed_provider}}"
existing_model="${PREINSTALL_PM_MODEL:-${installed_model}}"
existing_security_provider="${PREINSTALL_SECURITY_PROVIDER:-${installed_security_provider}}"
existing_security_model="${PREINSTALL_SECURITY_MODEL:-${installed_security_model}}"

case "${existing_provider}" in
  openrouter|openai-codex|anthropic) provider_default="${existing_provider}" ;;
  "") provider_default="openrouter" ;;
  *) provider_default="keep" ;;
esac
prompt_choice HERMES_AUTODEV_MODEL_PROVIDER \
  "Provider for Hermes orchestration agents" \
  "${provider_default}" \
  openrouter openai-codex anthropic keep

case "${HERMES_AUTODEV_MODEL_PROVIDER}" in
  openrouter)
    model_default="xiaomi/mimo-v2.5-pro"
    [[ "${existing_provider}" != "openrouter" || -z "${existing_model}" ]] || model_default="${existing_model}"
    security_model_default="moonshotai/kimi-k3"
    [[ "${existing_security_provider}" != "openrouter" || -z "${existing_security_model}" ]] || security_model_default="${existing_security_model}"
    ;;
  openai-codex)
    model_default="gpt-5.6-terra"
    [[ "${existing_provider}" != "openai-codex" || -z "${existing_model}" ]] || model_default="${existing_model}"
    security_model_default="gpt-5.6-sol"
    [[ "${existing_security_provider}" != "openai-codex" || -z "${existing_security_model}" ]] || security_model_default="${existing_security_model}"
    ;;
  anthropic)
    model_default="claude-sonnet-4-6"
    [[ "${existing_provider}" != "anthropic" || -z "${existing_model}" ]] || model_default="${existing_model}"
    security_model_default="${model_default}"
    [[ "${existing_security_provider}" != "anthropic" || -z "${existing_security_model}" ]] || security_model_default="${existing_security_model}"
    ;;
  keep)
    model_default="${existing_model:-unchanged}"
    security_model_default="${existing_security_model:-unchanged}"
    ;;
esac

if [[ "${HERMES_AUTODEV_MODEL_PROVIDER}" == "keep" ]]; then
  HERMES_AUTODEV_HERMES_MODEL="${existing_model:-unchanged}"
  HERMES_AUTODEV_SECURITY_MODEL="${existing_security_model:-unchanged}"
  export HERMES_AUTODEV_HERMES_MODEL HERMES_AUTODEV_SECURITY_MODEL
  echo "Keeping the model blocks already installed in each profile."
else
  prompt_text HERMES_AUTODEV_HERMES_MODEL "Default Hermes model ID" "${model_default}" 0 1
  prompt_text HERMES_AUTODEV_SECURITY_MODEL "Security Tester model ID" "${security_model_default}" 0 1
fi

if [[ "${HERMES_AUTODEV_MODEL_PROVIDER}" == "openrouter" ]]; then
  prompt_text OPENROUTER_API_KEY "OpenRouter API key for Hermes profiles" "${OPENROUTER_API_KEY-}" 1 1
elif [[ "${HERMES_AUTODEV_MODEL_PROVIDER}" == "anthropic" ]]; then
  prompt_text ANTHROPIC_API_KEY "Anthropic API key (optional; leave blank for Claude Max OAuth)" "${ANTHROPIC_API_KEY-}" 1 0
fi

section "Repository hosting"
prompt_choice HERMES_AUTODEV_SCM_PROVIDER \
  "Repository hosts to configure" \
  "${HERMES_AUTODEV_SCM_PROVIDER:-auto}" \
  auto github gitlab both none

case "${HERMES_AUTODEV_SCM_PROVIDER}" in
  auto|github|both)
    prompt_text GITHUB_TOKEN "GitHub token for issues/PRs/CI (optional)" "${GITHUB_TOKEN-}" 1 0
    ;;
esac
case "${HERMES_AUTODEV_SCM_PROVIDER}" in
  auto|gitlab|both)
    prompt_text GITLAB_HOST "GitLab base URL" "${GITLAB_HOST:-https://gitlab.com}" 0 1
    normalize_gitlab_host
    prompt_text GITLAB_TOKEN "GitLab token for issues/MRs/CI (optional)" "${GITLAB_TOKEN-}" 1 0
    ;;
esac

section "Developer Codex credentials"
prompt_text OPENAI_API_KEY "OpenAI API key for Codex (optional when using codex login)" "${OPENAI_API_KEY-}" 1 0
prompt_text CODEX_HOME "Codex auth/config directory override (blank uses ~/.codex)" "${CODEX_HOME-}" 0 0
if [[ -n "${CODEX_HOME}" ]]; then
  case "${CODEX_HOME}" in
    "~") CODEX_HOME="${HOME}" ;;
    \~/*) CODEX_HOME="${HOME}/${CODEX_HOME:2}" ;;
  esac
  [[ "${CODEX_HOME}" == /* ]] || CODEX_HOME="${PWD}/${CODEX_HOME}"
  CODEX_HOME="$(readlink -m "${CODEX_HOME}")"
  export CODEX_HOME
fi

section "Owner messaging"
prompt_text TELEGRAM_BOT_TOKEN "Telegram bot token for PM gateway (optional)" "${TELEGRAM_BOT_TOKEN-}" 1 0
prompt_text TELEGRAM_ALLOWED_USERS "Telegram allowed user IDs, comma-separated (optional)" "${TELEGRAM_ALLOWED_USERS-}" 0 0
prompt_text SIGNAL_HTTP_URL "Signal REST bridge URL (optional)" "${SIGNAL_HTTP_URL-}" 0 0
prompt_text SIGNAL_ACCOUNT "Signal account identifier (optional)" "${SIGNAL_ACCOUNT-}" 0 0
prompt_text SIGNAL_ALLOWED_USERS "Signal allowed users (optional)" "${SIGNAL_ALLOWED_USERS-}" 0 0

write_profile_env "$(autodev_profile_dir project-manager)/.env" \
  OPENROUTER_API_KEY ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS \
  GITHUB_TOKEN GITLAB_TOKEN GITLAB_HOST \
  SIGNAL_HTTP_URL SIGNAL_ACCOUNT SIGNAL_ALLOWED_USERS \
  HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS
write_profile_env "$(autodev_profile_dir frontend-designer)/.env" \
  OPENROUTER_API_KEY ANTHROPIC_API_KEY \
  HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS
write_profile_env "$(autodev_profile_dir developer)/.env" \
  OPENROUTER_API_KEY ANTHROPIC_API_KEY GITHUB_TOKEN GITLAB_TOKEN GITLAB_HOST \
  CODEX_HOME OPENAI_API_KEY \
  HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS
write_profile_env "$(autodev_profile_dir tester)/.env" \
  OPENROUTER_API_KEY ANTHROPIC_API_KEY GITHUB_TOKEN GITLAB_TOKEN GITLAB_HOST \
  HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS
write_profile_env "$(autodev_profile_dir security-tester)/.env" \
  OPENROUTER_API_KEY ANTHROPIC_API_KEY GITHUB_TOKEN GITLAB_TOKEN GITLAB_HOST \
  HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS

for support_profile in support-agent support-manager; do
  write_profile_env "$(autodev_profile_dir "${support_profile}")/.env" \
    OPENROUTER_API_KEY ANTHROPIC_API_KEY \
    HERMES_LOG_LLM_OUTPUTS HERMES_LLM_OUTPUT_LOG_MAX_CHARS
done

echo "Profile env files updated under ${HERMES_HOME_DIR}/profiles/*/.env"

maybe_verify_codex
maybe_authenticate_hermes_subscription
configure_profile_models
maybe_configure_git
case "${HERMES_AUTODEV_SCM_PROVIDER}" in
  auto|github|both) maybe_configure_gh_cli ;;
esac
case "${HERMES_AUTODEV_SCM_PROVIDER}" in
  auto|gitlab|both) maybe_configure_glab_cli ;;
esac
bootstrap_project
configure_gui

section "Public website"
prompt_yes_no HERMES_AUTODEV_SETUP_PORTAL \
  "Set up the public support website and private team workspace?" \
  "${HERMES_AUTODEV_SETUP_PORTAL:-no}"
if [[ "${HERMES_AUTODEV_SETUP_PORTAL}" == "1" ]]; then
  prompt_text AUTODEV_PORTAL_DOMAIN "Website DNS name (for example team.example.com)" "${AUTODEV_PORTAL_DOMAIN:-}" 0 1
  bash "${ROOT_DIR}/scripts/portal.sh" setup --domain "${AUTODEV_PORTAL_DOMAIN}"
fi

section "Health check"
prompt_yes_no HERMES_AUTODEV_RUN_DOCTOR "Run setup doctor now?" "${HERMES_AUTODEV_RUN_DOCTOR:-yes}"
if [[ "${HERMES_AUTODEV_RUN_DOCTOR}" == "1" ]]; then
  if [[ -n "${HERMES_AUTODEV_PROJECT_SLUG-}" && "${HERMES_AUTODEV_BOOTSTRAP_PROJECT:-0}" == "1" ]]; then
    bash "${ROOT_DIR}/scripts/doctor.sh" --project-slug "${HERMES_AUTODEV_PROJECT_SLUG}" || autodev_die \
      "setup was applied, but required health checks failed. Correct the items above and rerun 'hermes-autodev doctor --project-slug ${HERMES_AUTODEV_PROJECT_SLUG}'."
  else
    bash "${ROOT_DIR}/scripts/doctor.sh" || autodev_die \
      "setup was applied, but required health checks failed. Correct the items above and rerun 'hermes-autodev doctor'."
  fi
fi

cat <<EOF

Setup wizard complete.

Host the public support portal and private team workspace:
  hermes-autodev portal setup --domain team.example.com

Open or inspect the advanced private GUI:
  hermes-autodev dashboard open
  hermes-autodev dashboard status

Update package profiles and Hermes safely:
  hermes-autodev update

Preview a complete uninstall:
  hermes-autodev uninstall --dry-run

Configure another project:
  hermes-autodev setup --skip-install

Unified command (installed when ~/.local/bin is on PATH):
  hermes-autodev help

Setup log:
  ${LOG_FILE:-disabled}
EOF
