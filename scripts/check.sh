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
check_production_binary_is_current() {
  local shipped="bin/ownscribe-audio"
  if [[ ! -f "$shipped" ]]; then
    printf '    bin/ownscribe-audio is missing; the pipeline will fall back to a download. Run swift/build.sh\n'
    return 1
  fi
  local newer
  newer="$(find swift/Sources -name '*.swift' -newer "$shipped" -print -quit)"
  if [[ -n "$newer" ]]; then
    printf '    bin/ownscribe-audio is OLDER than %s\n' "$newer"
    printf '    The pipeline runs bin/, not .build/, so a Swift fix can pass every test and never\n'
    printf '    reach production. BUG5 shipped this way for three days. Run: bash swift/build.sh\n'
    return 1
  fi
  return 0
}

run_step "bin/ownscribe-audio is not stale" check_production_binary_is_current
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
