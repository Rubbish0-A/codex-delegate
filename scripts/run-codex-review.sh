#!/usr/bin/env bash
set -euo pipefail

# Usage: run-codex-review.sh <working_dir> [review_prompt] [--base <branch>] [--commit <sha>]
#   working_dir: absolute path to project root
#   review_prompt: optional custom review instructions
#   --base <branch>: review changes against a base branch (e.g., main)
#   --commit <sha>: review a specific commit

# ── Pre-flight: Codex CLI Check ──────────────────────────────
if ! command -v codex &>/dev/null; then
  echo "[ERROR] codex CLI not found. Install: npm install -g @openai/codex"
  exit 1
fi

WORKDIR="${1:-.}"
shift || true
CODEX_TIMEOUT="${CODEX_TIMEOUT:-300}"
OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-review-XXXXXX.md")

# ── Cleanup on exit ──────────────────────────────────────────
cleanup() {
  rm -f "$OUTPUT_FILE" 2>/dev/null
}
trap cleanup EXIT

# Parse arguments
PROMPT="Review the code for bugs, security issues, performance problems, and suggest improvements. For each finding, report: severity (CRITICAL/HIGH/MEDIUM/LOW), file and location, description, and suggested fix."
BASE_BRANCH=""
COMMIT_SHA=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      BASE_BRANCH="$2"
      shift 2
      ;;
    --commit)
      COMMIT_SHA="$2"
      shift 2
      ;;
    *)
      PROMPT="$1"
      shift
      ;;
  esac
done

cd "$WORKDIR"

# Build review flags
REVIEW_FLAGS=(--ephemeral)
if [ -n "$BASE_BRANCH" ]; then
  REVIEW_FLAGS+=(--base "$BASE_BRANCH")
  echo "=== Codex Branch Review ==="
  echo "Comparing against: $BASE_BRANCH"
elif [ -n "$COMMIT_SHA" ]; then
  REVIEW_FLAGS+=(--commit "$COMMIT_SHA")
  echo "=== Codex Commit Review ==="
  echo "Reviewing commit: $COMMIT_SHA"
else
  REVIEW_FLAGS+=(--uncommitted)
  echo "=== Codex Code Review ==="
  echo "Reviewing: uncommitted changes"
fi

echo "Working Dir: $WORKDIR"
echo "Instructions: $PROMPT"
echo "========================="
echo ""

timeout "$CODEX_TIMEOUT" codex review "${REVIEW_FLAGS[@]}" -o "$OUTPUT_FILE" "$PROMPT" < /dev/null 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 124 ]; then
  echo "[ERROR] Codex review timed out after ${CODEX_TIMEOUT}s. Set CODEX_TIMEOUT env var to increase."
fi

echo ""

# ── Review Output ────────────────────────────────────────────
echo "=== CODEX REVIEW RESULT ==="
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
  cat "$OUTPUT_FILE"
else
  echo "(No review output captured)"
fi

echo ""
echo "=== REVIEW EXIT CODE: $EXIT_CODE ==="

exit $EXIT_CODE
