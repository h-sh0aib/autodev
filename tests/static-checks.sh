#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

mapfile -d '' shell_files < <(
  find . -type f \( -name '*.sh' -o -path './developer/bin/codex-network-exec' \) -print0
)

for file in "${shell_files[@]}"; do
  bash -n "${file}"
done
printf 'bash syntax: %s files\n' "${#shell_files[@]}"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --severity=warning --external-sources "${shell_files[@]}"
  printf 'shellcheck: %s files\n' "${#shell_files[@]}"
elif [[ "${REQUIRE_SHELLCHECK:-0}" == "1" ]]; then
  echo "shellcheck is required but was not found." >&2
  exit 1
else
  echo "shellcheck: skipped (install ShellCheck or set REQUIRE_SHELLCHECK=1 in CI)"
fi

python3 - <<'PY'
import os
from pathlib import Path
import subprocess

try:
    import yaml
except ImportError as exc:
    raise SystemExit("PyYAML is required for static config validation") from exc

files = sorted([*Path(".").rglob("*.yaml"), *Path(".").rglob("*.yml")])
for path in files:
    with path.open(encoding="utf-8") as handle:
        yaml.safe_load(handle)

required = ">=2026.8.3"
distributions = sorted(Path(".").glob("*/distribution.yaml"))
for path in distributions:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if data.get("hermes_requires") != required:
        raise SystemExit(
            f"{path}: hermes_requires must be {required}, found {data.get('hermes_requires')!r}"
        )

print(f"yaml: {len(files)} files ({len(distributions)} distributions)")

# `git diff --check` sees nothing in a clean CI clone and can misread CRLF when
# WSL Git inspects a checkout created by Windows Git. Scan every tracked and
# not-ignored package file directly, while still enforcing LF for Linux
# entrypoints.
listed = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
).split(b"\0")
text_files = 0
problems: list[str] = []
for raw_path in listed:
    if not raw_path:
        continue
    path = Path(os.fsdecode(raw_path))
    try:
        payload = path.read_bytes()
    except (OSError, IsADirectoryError):
        continue
    if b"\0" in payload:
        continue
    try:
        content = payload.decode("utf-8")
    except UnicodeDecodeError:
        continue
    text_files += 1
    for line_number, line in enumerate(content.splitlines(), 1):
        if line.endswith((" ", "\t")):
            problems.append(f"{path}:{line_number}: trailing whitespace")
    is_shell = path.suffix == ".sh" or path.as_posix() == "developer/bin/codex-network-exec"
    if is_shell and b"\r\n" in payload:
        problems.append(f"{path}: shell entrypoint contains CRLF line endings")

if problems:
    raise SystemExit("\n".join(problems))
print(f"text hygiene: {text_files} files")
PY
echo "static checks passed"
