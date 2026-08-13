#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hermes-autodev-smoke.XXXXXX")"

cleanup() {
  local dashboard_test_pid=""
  if [[ -n "${HERMES_AUTODEV_STATE_DIR:-}" && -r "${HERMES_AUTODEV_STATE_DIR}/dashboard.pid" ]]; then
    dashboard_test_pid="$(tr -dc '0-9' < "${HERMES_AUTODEV_STATE_DIR}/dashboard.pid")"
    [[ -z "${dashboard_test_pid}" ]] || kill "${dashboard_test_pid}" 2>/dev/null || true
  fi
  case "${TEST_ROOT}" in
    "${TMPDIR:-/tmp}"/hermes-autodev-smoke.*) rm -rf -- "${TEST_ROOT}" ;;
    *) echo "Refusing to remove unexpected smoke-test path: ${TEST_ROOT}" >&2 ;;
  esac
}
trap cleanup EXIT

export HOME="${TEST_ROOT}/home"
export XDG_STATE_HOME="${TEST_ROOT}/state"
export HERMES_HOME="${HOME}/custom hermes's home"
export HERMES_AUTODEV_STATE_DIR="${HERMES_HOME}/autodev"
mkdir -p "${HOME}" "${TEST_ROOT}/bin" "${TEST_ROOT}/work"
FAKE_LOG="${TEST_ROOT}/hermes.log"
export FAKE_LOG
FAKE_CODEX_LOG="${TEST_ROOT}/codex.log"
export FAKE_CODEX_LOG
FAKE_HERMES_INSTALL_DIR="${TEST_ROOT}/fake-hermes"
export FAKE_HERMES_INSTALL_DIR

cat > "${TEST_ROOT}/bin/hermes" <<'FAKE_HERMES'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "${FAKE_LOG}"
printf '\n' >> "${FAKE_LOG}"

if [[ "${1:-}" == "--version" ]]; then
  cat <<EOF
Hermes Agent v2026.8.3 (smoke)
Install directory: ${FAKE_HERMES_INSTALL_DIR:-/tmp/fake-hermes}
Python: 3
EOF
  exit 0
fi

if [[ "${1:-}" == "profile" ]]; then
  action="${2:-}"
  case "${action}" in
    install)
      source_dir="${3}"
      shift 3
      profile=""
      while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--name" ]]; then
          profile="$2"
          shift 2
        else
          shift
        fi
      done
      [[ "${profile}" =~ ^(project-manager|frontend-designer|developer|tester|security-tester)$ ]]
      target="${HERMES_HOME}/profiles/${profile}"
      mkdir -p "${target}"
      cp "${source_dir}/config.yaml" "${source_dir}/distribution.yaml" "${source_dir}/SOUL.md" "${target}/"
      cp "${source_dir}/.env.EXAMPLE" "${target}/.env.EXAMPLE"
      mkdir -p "${HOME}/.local/bin"
      printf '#!/bin/sh\nexec %s -p %s "$@"\n' "$(command -v hermes)" "${profile}" \
        > "${HOME}/.local/bin/${profile}"
      chmod 0755 "${HOME}/.local/bin/${profile}"
      ;;
    update|alias|info|show)
      ;;
    delete)
      profile="${3}"
      [[ "${profile}" =~ ^(project-manager|frontend-designer|developer|tester|security-tester)$ ]]
      # Exercise the package's Hermes-unavailable/failing deletion fallback.
      [[ "${profile}" != "security-tester" ]] || exit 1
      rm -rf -- "${HERMES_HOME}/profiles/${profile}"
      if grep -Fq 'hermes -p' "${HOME}/.local/bin/${profile}" 2>/dev/null; then
        rm -f -- "${HOME}/.local/bin/${profile}"
      fi
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "backup" ]]; then
  output=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--output" ]]; then
      output="$2"
      shift 2
    else
      shift
    fi
  done
  [[ -n "${output}" ]]
  mkdir -p "$(dirname "${output}")"
  printf 'fake backup\n' > "${output}"
  exit 0
fi

if [[ "${1:-}" == "update" ]]; then
  exit 0
fi

if [[ "${1:-}" == "dashboard" ]]; then
  shift
  host="127.0.0.1"
  port="9119"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host) host="$2"; shift 2 ;;
      --port) port="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  exec "${FAKE_HERMES_INSTALL_DIR}/venv/bin/python" - hermes-dashboard "${host}" "${port}" <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import sys

host = sys.argv[2]
port = int(sys.argv[3])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/status":
            payload = json.dumps({"version": "2026.8.3-smoke"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        else:
            self.send_error(404)

    def log_message(self, *_args):
        pass


ThreadingHTTPServer((host, port), Handler).serve_forever()
PY
fi

if [[ "${1:-}" == "-p" ]]; then
  profile="${2:-}"
  shift 2
  if [[ "${1:-}" == "gateway" && "${2:-}" == "status" ]]; then
    echo "Gateway: stopped"
    exit 1
  fi
  if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    echo "${3:-provider}: logged in"
    exit 0
  fi
  if [[ "${1:-}" == "project" && "${2:-}" == "show" ]]; then
    [[ -f "${HERMES_HOME}/autodev/fake-project-${profile}-${3:-missing}" ]]
    exit $?
  fi
  if [[ "${1:-}" == "project" && "${2:-}" == "create" ]]; then
    shift 2
    slug=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--slug" ]]; then
        slug="$2"
        shift 2
      else
        shift
      fi
    done
    [[ -n "${slug}" ]]
    mkdir -p "${HERMES_HOME}/autodev"
    : > "${HERMES_HOME}/autodev/fake-project-${profile}-${slug}"
    exit 0
  fi
  exit 0
fi

exit 0
FAKE_HERMES
chmod 0755 "${TEST_ROOT}/bin/hermes"
cat > "${TEST_ROOT}/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "${FAKE_CODEX_LOG}"
printf '\n' >> "${FAKE_CODEX_LOG}"
cat >/dev/null || true
FAKE_CODEX
chmod 0755 "${TEST_ROOT}/bin/codex"
export PATH="${TEST_ROOT}/bin:/usr/bin:/bin"
mkdir -p "${FAKE_HERMES_INSTALL_DIR}/venv/bin"
cat > "${FAKE_HERMES_INSTALL_DIR}/venv/bin/python" <<'FAKE_PYTHON'
#!/usr/bin/env bash
if [[ "${1:-}" == "-c" && "${2:-}" == "import fastapi, uvicorn, ptyprocess" ]]; then
  exit 0
fi
exec /usr/bin/python3 "$@"
FAKE_PYTHON
chmod 0755 "${FAKE_HERMES_INSTALL_DIR}/venv/bin/python"

# Windows-origin archives must not install CRLF shebangs onto Linux.
# shellcheck source=scripts/lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"
[[ "$(autodev_find_hermes_python)" == "${FAKE_HERMES_INSTALL_DIR}/venv/bin/python" ]]
[[ "$(autodev_find_python)" == "${FAKE_HERMES_INSTALL_DIR}/venv/bin/python" ]]
printf '#!/usr/bin/env bash\r\nprintf "normalized\\n"\r\n' > "${TEST_ROOT}/crlf-launcher"
autodev_install_executable "${TEST_ROOT}/crlf-launcher" "${TEST_ROOT}/bin/normalized-launcher"
[[ "$("${TEST_ROOT}/bin/normalized-launcher")" == "normalized" ]]

CONFIG_FILE="${TEST_ROOT}/client.env"
cat > "${CONFIG_FILE}" <<'EOF'
HERMES_AUTODEV_INSTALL_HERMES=0
HERMES_AUTODEV_UPDATE_HERMES=auto
HERMES_AUTODEV_FORCE_PROFILE_INSTALL=0
HERMES_AUTODEV_MODEL_PROVIDER=openai-codex
HERMES_AUTODEV_HERMES_MODEL=gpt-smoke
HERMES_AUTODEV_SECURITY_MODEL=gpt-smoke-sec
HERMES_AUTODEV_AUTH_HERMES_SUBSCRIPTION=0
HERMES_AUTODEV_SCM_PROVIDER=both
GITHUB_TOKEN=
GITLAB_TOKEN=smoke-token-with-'quote
GITLAB_HOST=gitlab.example.test/
HERMES_AUTODEV_CONFIGURE_GIT=0
HERMES_AUTODEV_INSTALL_CODEX=0
HERMES_AUTODEV_AUTH_CODEX=0
OPENAI_API_KEY=
CODEX_HOME=~/.codex smoke's
TELEGRAM_BOT_TOKEN=
TELEGRAM_ALLOWED_USERS=
SIGNAL_HTTP_URL=
SIGNAL_ACCOUNT=
SIGNAL_ALLOWED_USERS=
HERMES_AUTODEV_BOOTSTRAP_PROJECT=0
HERMES_AUTODEV_GUI_MODE=ssh
HERMES_AUTODEV_GUI_PORT=19119
HERMES_AUTODEV_GUI_PERSIST=0
HERMES_AUTODEV_GUI_START=0
HERMES_AUTODEV_RUN_DOCTOR=0
EOF

"${ROOT_DIR}/wizard.sh" --config "${CONFIG_FILE}" --non-interactive --skip-project --no-log

for profile in project-manager frontend-designer developer tester security-tester; do
  [[ -f "${HERMES_HOME}/profiles/${profile}/config.yaml" ]]
  [[ -f "${HERMES_HOME}/profiles/${profile}/.env" ]]
done
grep -q 'provider: "openai-codex"' "${HERMES_HOME}/profiles/project-manager/config.yaml"
grep -q 'default: "gpt-smoke-sec"' "${HERMES_HOME}/profiles/security-tester/config.yaml"
[[ "$(autodev_dotenv_value "${HERMES_HOME}/profiles/developer/.env" CODEX_HOME)" == "${HOME}/.codex smoke's" ]]
[[ "$(autodev_dotenv_value "${HERMES_HOME}/profiles/developer/.env" GITLAB_TOKEN)" == "smoke-token-with-'quote" ]]
grep -Fq 'GITLAB_HOST=https://gitlab.example.test' "${HERMES_HOME}/profiles/project-manager/.env"
grep -q 'HERMES_AUTODEV_GUI_MODE=ssh' "${HERMES_HOME}/autodev/dashboard.env"
[[ -x "${HOME}/.local/bin/hermes-autodev" ]]
SSH_CONNECTION='2001:db8::2 50123 2001:db8::1 2222' \
  env -u HERMES_HOME -u HERMES_AUTODEV_STATE_DIR \
  "${HOME}/.local/bin/hermes-autodev" dashboard access > "${TEST_ROOT}/ipv6-access.txt"
grep -Fq "ssh -N -p 2222 -L 19119:127.0.0.1:19119 $(id -un)@2001:db8::1" \
  "${TEST_ROOT}/ipv6-access.txt"
if grep -Fq '@[' "${TEST_ROOT}/ipv6-access.txt"; then
  echo "Dashboard emitted URL-style brackets in an OpenSSH destination." >&2
  exit 1
fi
env -u HERMES_HOME -u HERMES_AUTODEV_STATE_DIR \
  "${HOME}/.local/bin/hermes-autodev" dashboard start \
  --mode ssh --port 19119 --no-persist --no-open >/dev/null
env -u HERMES_HOME -u HERMES_AUTODEV_STATE_DIR \
  "${HOME}/.local/bin/hermes-autodev" dashboard status >/dev/null
curl --fail --silent 'http://127.0.0.1:19119/api/status' | grep -q '2026.8.3-smoke'
env -u HERMES_HOME -u HERMES_AUTODEV_STATE_DIR \
  "${HOME}/.local/bin/hermes-autodev" dashboard stop >/dev/null
if env -u HERMES_HOME -u HERMES_AUTODEV_STATE_DIR \
  "${HOME}/.local/bin/hermes-autodev" dashboard status >/dev/null 2>&1; then
  echo "Dashboard still reported healthy after a managed stop." >&2
  exit 1
fi

INVALID_CONFIG="${TEST_ROOT}/invalid.env"
cp "${CONFIG_FILE}" "${INVALID_CONFIG}"
sed -i 's/HERMES_AUTODEV_RUN_DOCTOR=0/HERMES_AUTODEV_RUN_DOCTOR=maybe/' "${INVALID_CONFIG}"
if "${ROOT_DIR}/wizard.sh" --config "${INVALID_CONFIG}" --non-interactive \
  --skip-install --skip-project --skip-gui --no-log >/dev/null 2>&1; then
  echo "Wizard accepted an invalid unattended boolean." >&2
  exit 1
fi

: > "${FAKE_LOG}"
sed -i '/provider: "openai-codex"/a\  reasoning_effort: "high"' \
  "${HERMES_HOME}/profiles/project-manager/config.yaml"
"${ROOT_DIR}/wizard.sh" --config "${CONFIG_FILE}" --non-interactive --skip-project --skip-gui --no-log
[[ "$(grep -c '^profile update ' "${FAKE_LOG}")" -eq 5 ]]
grep -q 'reasoning_effort: "high"' "${HERMES_HOME}/profiles/project-manager/config.yaml"
if grep -q -- '--force' "${FAKE_LOG}"; then
  echo "Safe wizard rerun unexpectedly forced a profile install." >&2
  exit 1
fi

git -C "${TEST_ROOT}/work" init -q project
# The path deliberately contains "github.com"; detection must inspect only
# the hostname and still classify this as GitLab.
git -C "${TEST_ROOT}/work/project" remote add origin git@gitlab.example.test:group/github.com-mirror.git
git -C "${TEST_ROOT}/work/project" -c user.name=Smoke -c user.email=smoke@example.test \
  commit --allow-empty -q -m initial
git -C "${TEST_ROOT}/work/project" worktree add -q -b smoke-worktree "${TEST_ROOT}/work/project-linked"
mkdir -p "${TEST_ROOT}/work/project-linked/packages/app"
(
  cd "${TEST_ROOT}/work"
  bash "${ROOT_DIR}/scripts/setup-project.sh" \
    --project-path project-linked/packages/app \
    --project-slug smoke-project \
    --no-cron \
    --no-start-gateway
)
grep -q 'project create' "${FAKE_LOG}"
for profile in project-manager frontend-designer developer tester security-tester; do
  [[ -f "${HERMES_HOME}/autodev/fake-project-${profile}-smoke-project" ]]
done
[[ "$(grep -c -- ' project create ' "${FAKE_LOG}")" -eq 5 ]]
bash -n "${HERMES_HOME}/scripts/autodev_watchdog_smoke-project.sh"

bash "${ROOT_DIR}/scripts/setup-project.sh" \
  --project-path "${TEST_ROOT}/work/project-linked" \
  --project-slug smoke-project \
  --no-cron \
  --no-kickoff \
  --no-start-gateway >/dev/null
[[ "$(grep -c -- '^-p project-manager project create ' "${FAKE_LOG}")" -eq 1 ]]
[[ "$(grep -c -- ' project create ' "${FAKE_LOG}")" -eq 5 ]]
[[ "$(grep -c -- ' project add-folder ' "${FAKE_LOG}")" -eq 5 ]]

# A server administrator may pre-create an empty, correctly owned destination.
# Project setup should clone into it instead of rejecting the directory.
mkdir -p "${TEST_ROOT}/work/precreated-empty"
bash "${ROOT_DIR}/scripts/setup-project.sh" \
  --repo-url "${TEST_ROOT}/work/project" \
  --project-path "${TEST_ROOT}/work/precreated-empty" \
  --project-slug precreated-clone \
  --no-cron \
  --no-kickoff \
  --no-start-gateway >/dev/null
[[ "$(git -C "${TEST_ROOT}/work/precreated-empty" rev-parse --is-inside-work-tree)" == "true" ]]

printf 'smoke prompt\n' > "${TEST_ROOT}/prompt.md"
"${HERMES_HOME}/profiles/developer/bin/codex-network-exec" \
  "${TEST_ROOT}/work/project-linked" "${TEST_ROOT}/prompt.md"
grep -q -- '--ask-for-approval never exec --sandbox danger-full-access' "${FAKE_CODEX_LOG}"

# Owner-only generated files contain shell-safe %q assignments.
# shellcheck disable=SC1090
source "${HERMES_HOME}/autodev/projects/smoke-project.env"
[[ "${HERMES_AUTODEV_REPO}" == "${TEST_ROOT}/work/project-linked" ]]
[[ "${HERMES_AUTODEV_SCM_PROVIDER}" == "gitlab" ]]
[[ "${HERMES_AUTODEV_REMOTE_HOST}" == "gitlab.example.test" ]]

bash "${ROOT_DIR}/scripts/doctor.sh" --project-slug smoke-project >/dev/null
bash "${ROOT_DIR}/update.sh" --check --skip-package --skip-hermes >/dev/null

# Exercise the mutating updater against a real local upstream without touching
# the source checkout used to run this test.
UPDATE_PUBLISHER="${TEST_ROOT}/update-publisher"
UPDATE_REMOTE="${TEST_ROOT}/update-remote.git"
UPDATE_INSTALL="${TEST_ROOT}/update-install"
UPDATE_HOME="${TEST_ROOT}/update-home"
mkdir -p "${UPDATE_PUBLISHER}" "${UPDATE_HOME}"
tar -C "${ROOT_DIR}" --exclude=.git -cf - . | tar -C "${UPDATE_PUBLISHER}" -xf -
git -C "${UPDATE_PUBLISHER}" init -q -b main
git -C "${UPDATE_PUBLISHER}" add -A
git -C "${UPDATE_PUBLISHER}" -c user.name=Smoke -c user.email=smoke@example.test \
  commit -q -m initial
git init -q --bare "${UPDATE_REMOTE}"
git --git-dir="${UPDATE_REMOTE}" symbolic-ref HEAD refs/heads/main
git -C "${UPDATE_PUBLISHER}" remote add origin "${UPDATE_REMOTE}"
git -C "${UPDATE_PUBLISHER}" push -q -u origin main
git clone -q "${UPDATE_REMOTE}" "${UPDATE_INSTALL}"

UPDATE_HERMES_HOME="${UPDATE_HOME}/runtime with spaces"
UPDATE_STATE_HOME="${UPDATE_HOME}/state"
HOME="${UPDATE_HOME}" HERMES_HOME="${UPDATE_HERMES_HOME}" \
  HERMES_AUTODEV_STATE_DIR="${UPDATE_HERMES_HOME}/autodev" \
  XDG_STATE_HOME="${UPDATE_STATE_HOME}" \
  bash "${UPDATE_INSTALL}/install.sh" -y --no-install-hermes --no-update-hermes >/dev/null

printf '1.5.1-smoke\n' > "${UPDATE_PUBLISHER}/VERSION"
git -C "${UPDATE_PUBLISHER}" add VERSION
git -C "${UPDATE_PUBLISHER}" -c user.name=Smoke -c user.email=smoke@example.test \
  commit -q -m update
git -C "${UPDATE_PUBLISHER}" push -q

HOME="${UPDATE_HOME}" XDG_STATE_HOME="${UPDATE_STATE_HOME}" \
  env -u HERMES_HOME -u HERMES_AUTODEV_STATE_DIR \
  bash "${UPDATE_INSTALL}/update.sh" --yes >/dev/null
[[ "$(tr -d '[:space:]' < "${UPDATE_INSTALL}/VERSION")" == "1.5.1-smoke" ]]
[[ "$(git -C "${UPDATE_INSTALL}" status --porcelain)" == "" ]]
find "${UPDATE_STATE_HOME}/hermes-autodev/backups" -maxdepth 1 -type f -name '*.zip' | grep -q .

if HERMES_HOME=/ bash "${ROOT_DIR}/uninstall.sh" --dry-run >/dev/null 2>&1; then
  echo "Uninstaller accepted an unsafe HERMES_HOME." >&2
  exit 1
fi
if bash "${ROOT_DIR}/scripts/backup-runtime.sh" --output "${HERMES_HOME}/unsafe.zip" >/dev/null 2>&1; then
  echo "Backup manager accepted an output inside HERMES_HOME." >&2
  exit 1
fi

# A user may replace a profile-named wrapper after installation. Neither
# Hermes nor the package fallback may delete a command that is no longer a
# recognizable Hermes profile alias.
printf '#!/bin/sh\nprintf "user-owned tester command\\n"\n' > "${HOME}/.local/bin/tester"
chmod 0755 "${HOME}/.local/bin/tester"
env -u HERMES_HOME -u HERMES_AUTODEV_STATE_DIR \
  "${HOME}/.local/bin/hermes-autodev" uninstall --dry-run > "${TEST_ROOT}/uninstall-preview.txt"
grep -Fq "${HERMES_HOME}/autodev" "${TEST_ROOT}/uninstall-preview.txt"
grep -Fq "${HOME}/.local/bin/security-tester" "${TEST_ROOT}/uninstall-preview.txt"
env -u HERMES_HOME -u HERMES_AUTODEV_STATE_DIR \
  "${HOME}/.local/bin/hermes-autodev" uninstall --yes >/dev/null
[[ -d "${TEST_ROOT}/work/project/.git" ]]
[[ -f "${TEST_ROOT}/work/project-linked/.git" ]]
[[ ! -d "${HERMES_HOME}/profiles/project-manager" ]]
[[ ! -e "${HOME}/.local/bin/security-tester" ]]
[[ "$("${HOME}/.local/bin/tester")" == "user-owned tester command" ]]
[[ ! -e "${HOME}/.config/hermes-autodev/install.env" ]]
find "${XDG_STATE_HOME}/hermes-autodev/backups" -maxdepth 1 -type f -name '*.zip' | grep -q .

echo "lifecycle smoke test passed"
