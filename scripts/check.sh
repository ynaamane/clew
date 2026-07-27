#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FAILURES=()

run_step() {
  local label="$1"
  shift
  printf '\n\033[1m==> %s\033[0m\n' "$label"
  if "$@"; then
    printf '\033[32m    ok\033[0m\n'
  else
    printf '\033[31m    FAILED\033[0m\n'
    FAILURES+=("$label")
  fi
}

run_step "ruff check" uv run ruff check src/ tests/ scripts/
run_step "ruff format --check" uv run ruff format --check src/ tests/
run_step "pytest (skipping hardware)" uv run pytest -q -m "not hardware"
run_step "swift build (debug)" swift build --package-path swift
run_step "swift build (release, what ships)" swift build -c release --package-path swift
run_step "swift test" swift test --package-path swift
run_step "shellcheck rec.sh" bash -n rec.sh
run_step "shellcheck swift/build-app.sh" bash -n swift/build-app.sh
run_step "shellcheck swift/build.sh" bash -n swift/build.sh

printf '\n'
if [[ ${#FAILURES[@]} -eq 0 ]]; then
  printf '\033[32mAll checks passed.\033[0m\n'
  exit 0
fi

printf '\033[31m%d check(s) failed:\033[0m\n' "${#FAILURES[@]}"
for f in "${FAILURES[@]}"; do
  printf '  - %s\n' "$f"
done
exit 1
