#!/usr/bin/env bash

# Shared helpers for Linux/WSL setup and lifecycle scripts. This file is
# sourced; callers choose their own shell strictness.

# Keep the package on Hermes Agent 0.20.0, published as release tag v2026.8.3,
# which is the first stable release that includes the current dashboard auth
# gate and unified machine-level dashboard lifecycle. Hermes --version reports
# the package version (0.20.x), not the calendar-based release tag (2026.8.3).
# These constants are consumed by scripts that source this library.
# shellcheck disable=SC2034
AUTODEV_MIN_HERMES_VERSION="0.20.0"
# shellcheck disable=SC2034
AUTODEV_TEAM_PROFILES=(project-manager frontend-designer developer tester security-tester support-agent support-manager)

# A stable pointer outside HERMES_HOME lets lifecycle commands rediscover a
# custom runtime directory in fresh shells. It is generated with shell-safe
# values and owner-only permissions by install-team.sh.
AUTODEV_INSTALL_POINTER="${HOME}/.config/hermes-autodev/install.env"
if [[ -z "${HERMES_HOME:-}" && -r "${AUTODEV_INSTALL_POINTER}" && -O "${AUTODEV_INSTALL_POINTER}" ]]; then
  # shellcheck disable=SC1090
  source "${AUTODEV_INSTALL_POINTER}"
  if [[ -n "${HERMES_AUTODEV_HERMES_HOME:-}" ]]; then
    export HERMES_HOME="${HERMES_AUTODEV_HERMES_HOME}"
  fi
  if [[ -z "${HERMES_AUTODEV_STATE_DIR:-}" && -n "${HERMES_AUTODEV_STATE_DIR_VALUE:-}" ]]; then
    export HERMES_AUTODEV_STATE_DIR="${HERMES_AUTODEV_STATE_DIR_VALUE}"
  fi
fi

# Non-login SSH/cloud-init shells often omit the standard per-user binary
# directory even though both Hermes and this package install launchers there.
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) export PATH="${HOME}/.local/bin:${PATH}" ;;
esac

autodev_die() {
  echo "Error: $*" >&2
  exit 1
}

autodev_is_true() {
  case "${1:-}" in
    1|yes|Yes|YES|true|True|TRUE|on|On|ON) return 0 ;;
    *) return 1 ;;
  esac
}

autodev_has_tty() {
  [[ -t 0 && -t 1 ]]
}

autodev_detect_environment() {
  if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then
      printf 'wsl-ssh'
    else
      printf 'linux-ssh'
    fi
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    printf 'wsl-local'
  elif [[ -f /.dockerenv ]] || grep -Eq '(docker|containerd|kubepods|podman)' /proc/1/cgroup 2>/dev/null; then
    printf 'container'
  else
    printf 'linux-local'
  fi
}

autodev_require_linux() {
  local kernel
  kernel="$(uname -s 2>/dev/null || true)"
  [[ "${kernel}" == "Linux" ]] || autodev_die \
    "this package currently supports Linux and WSL2; detected ${kernel:-unknown}."
}

autodev_hermes_version() {
  command -v hermes >/dev/null 2>&1 || return 1
  hermes --version 2>/dev/null | sed -n 's/^Hermes Agent v\([0-9][0-9.]*\).*/\1/p' | head -n 1
}

autodev_version_at_least() {
  local actual="$1"
  local required="$2"
  [[ -n "${actual}" && -n "${required}" ]] || return 1
  [[ "$(printf '%s\n%s\n' "${required}" "${actual}" | sort -V | head -n 1)" == "${required}" ]]
}

autodev_hermes_install_dir() {
  command -v hermes >/dev/null 2>&1 || return 1
  hermes --version 2>/dev/null | sed -n \
    -e 's/^Install directory:[[:space:]]*//p' \
    -e 's/^Project:[[:space:]]*//p' | head -n 1
}

autodev_find_hermes_python() {
  local candidate hermes_command install_dir launcher_target hermes_home_dir
  hermes_home_dir="$(autodev_hermes_home)"
  install_dir="$(autodev_hermes_install_dir || true)"

  if [[ -n "${AUTODEV_PYTHON:-}" && -x "${AUTODEV_PYTHON}" ]]; then
    printf '%s' "${AUTODEV_PYTHON}"
    return 0
  fi

  # Official installs run the checked-in Hermes entrypoint with this venv.
  # Check it before system Python: dashboard extras must be installed into the
  # interpreter that will actually import them when `hermes dashboard` starts.
  for candidate in \
    "${install_dir:+${install_dir}/venv/bin/python}" \
    "${hermes_home_dir}/hermes-agent/venv/bin/python" \
    "${hermes_home_dir}/venvs/hermes/bin/python" \
    "${hermes_home_dir}/venv/bin/python" \
    "/usr/local/lib/hermes-agent/venv/bin/python"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  # Current official launchers use: exec "/path/venv/bin/python" ...
  # Parsing that also covers explicit --dir installations outside HERMES_HOME.
  hermes_command="$(command -v hermes 2>/dev/null || true)"
  if [[ -n "${hermes_command}" && -r "${hermes_command}" ]]; then
    launcher_target="$(sed -n \
      's/^[[:space:]]*exec[[:space:]]*"\([^"]*\/bin\/python[0-9.]*\)".*/\1/p' \
      "${hermes_command}" 2>/dev/null | head -n 1)"
    if [[ -n "${launcher_target}" && -x "${launcher_target}" ]]; then
      printf '%s' "${launcher_target}"
      return 0
    fi
  fi

  return 1
}

autodev_find_python() {
  local candidate

  if [[ -n "${AUTODEV_PYTHON:-}" && -x "${AUTODEV_PYTHON}" ]]; then
    printf '%s' "${AUTODEV_PYTHON}"
    return 0
  fi

  if candidate="$(autodev_find_hermes_python)"; then
    printf '%s' "${candidate}"
    return 0
  fi

  for candidate in "$(command -v python3 2>/dev/null || true)" "$(command -v python 2>/dev/null || true)"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  return 1
}

autodev_hermes_home() {
  readlink -m "${HERMES_HOME:-${HOME}/.hermes}"
}

autodev_profile_dir() {
  printf '%s/profiles/%s' "$(autodev_hermes_home)" "$1"
}

autodev_remote_host() {
  local value="$1"
  local authority host rest
  value="${value%/}"

  case "${value}" in
    *://*)
      authority="${value#*://}"
      authority="${authority%%/*}"
      authority="${authority##*@}"
      ;;
    *@*:*)
      rest="${value#*@}"
      if [[ "${rest}" == \[*\]*:* ]]; then
        host="${rest#\[}"
        host="${host%%\]*}"
        printf '%s' "${host,,}"
        return 0
      fi
      authority="${rest%%:*}"
      ;;
    *:*) authority="${value%%:*}" ;;
    *) authority="${value%%/*}" ;;
  esac

  if [[ "${authority}" == \[*\]* ]]; then
    host="${authority#\[}"
    host="${host%%\]*}"
  else
    host="${authority%%:*}"
  fi
  [[ -n "${host}" ]] || return 1
  printf '%s' "${host,,}"
}

autodev_python() {
  local python_command
  python_command="$(autodev_find_python)" || autodev_die \
    "Python 3 was not found. Install Hermes first or install python3, then retry."
  "${python_command}" "$@"
}

autodev_dotenv_value() {
  local file="$1"
  local key="$2"
  [[ -f "${file}" ]] || return 1
  autodev_python - "${file}" "${key}" <<'PY'
from pathlib import Path
import codecs
import re
import sys

path = Path(sys.argv[1])
target = sys.argv[2]


def decode_quoted(value: str, quote: str) -> str:
    if len(value) < 2 or value[-1] != quote:
        return value
    inner = value[1:-1]
    allowed = {"\\", "'"} if quote == "'" else {"\\", "'", '"', "a", "b", "f", "n", "r", "t", "v"}
    out = []
    index = 0
    while index < len(inner):
        if inner[index] == "\\" and index + 1 < len(inner) and inner[index + 1] in allowed:
            out.append(codecs.decode(inner[index:index + 2], "unicode_escape"))
            index += 2
        else:
            out.append(inner[index])
            index += 1
    return "".join(out)


for raw in path.read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    if line.startswith("export "):
        line = line[7:].lstrip()
    name, value = line.split("=", 1)
    if name.strip() != target:
        continue
    value = value.strip()
    if value.startswith(("'", '"')):
        value = decode_quoted(value, value[0])
    else:
        value = re.sub(r"\s+#.*$", "", value).rstrip()
    print(value)
    break
PY
}

autodev_state_dir() {
  printf '%s' "${HERMES_AUTODEV_STATE_DIR:-$(autodev_hermes_home)/autodev}"
}

autodev_external_state_dir() {
  printf '%s' "${XDG_STATE_HOME:-${HOME}/.local/state}/hermes-autodev"
}

autodev_install_pointer() {
  printf '%s' "${AUTODEV_INSTALL_POINTER}"
}

autodev_path_is_within() {
  local target="$1"
  local parent="$2"
  local target_abs parent_abs
  target_abs="$(readlink -m "${target}")"
  parent_abs="$(readlink -m "${parent}")"
  [[ "${target_abs}" == "${parent_abs}/"* ]]
}

autodev_pid_running() {
  local pid="$1"
  [[ "${pid}" =~ ^[1-9][0-9]*$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  if [[ -r "/proc/${pid}/status" ]] &&
     grep -Eq '^State:[[:space:]]*[ZX]' "/proc/${pid}/status" 2>/dev/null; then
    return 1
  fi
  return 0
}

autodev_write_env_file() {
  local output="$1"
  shift
  mkdir -p "$(dirname "${output}")"
  chmod 0700 "$(dirname "${output}")" 2>/dev/null || true
  local previous_umask
  previous_umask="$(umask)"
  umask 077
  local temporary
  temporary="$(mktemp "${output}.tmp.XXXXXX")" || autodev_die \
    "could not create a temporary state file beside ${output}"
  local assignment key value
  for assignment in "$@"; do
    key="${assignment%%=*}"
    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      rm -f "${temporary}"
      umask "${previous_umask}"
      autodev_die "invalid state key for ${output}: ${key}"
    fi
  done
  if ! {
    for assignment in "$@"; do
      key="${assignment%%=*}"
      value="${assignment#*=}"
      printf '%s=%q\n' "${key}" "${value}"
    done
  } > "${temporary}"; then
    rm -f "${temporary}"
    umask "${previous_umask}"
    autodev_die "could not write state file: ${output}"
  fi
  chmod 0600 "${temporary}" || true
  if ! mv -f -- "${temporary}" "${output}"; then
    rm -f "${temporary}"
    umask "${previous_umask}"
    autodev_die "could not publish state file: ${output}"
  fi
  umask "${previous_umask}"
}

autodev_install_executable() {
  local source="$1"
  local destination="$2"
  local temporary
  [[ -f "${source}" ]] || autodev_die "executable source not found: ${source}"
  mkdir -p "$(dirname "${destination}")"
  temporary="$(mktemp "${destination}.tmp.XXXXXX")"
  if ! sed 's/\r$//' "${source}" > "${temporary}" ||
     ! chmod 0755 "${temporary}" ||
     ! mv -f -- "${temporary}" "${destination}"; then
    rm -f "${temporary}"
    autodev_die "could not install executable: ${destination}"
  fi
}

autodev_user_systemd_available() {
  command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

autodev_warn_linger() {
  [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]] || return 0
  command -v loginctl >/dev/null 2>&1 || return 0
  local linger
  linger="$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)"
  if [[ "${linger}" == "no" ]]; then
    echo "Warning: user services may stop after the SSH session ends." >&2
    echo "Ask an administrator to run: sudo loginctl enable-linger $(id -un)" >&2
  fi
}
