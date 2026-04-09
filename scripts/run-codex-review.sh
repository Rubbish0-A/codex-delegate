#!/usr/bin/env bash
set -euo pipefail

# Usage: run-codex-review.sh <working_dir> [review_prompt] [--base <branch>] [--commit <sha>]
#   working_dir: absolute path to project root
#   review_prompt: optional custom review instructions
#   --base <branch>: review changes against a base branch (e.g., main)
#   --commit <sha>: review a specific commit

WORKDIR="${1:-.}"
shift || true

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
REVIEW_FLAGS=""
if [ -n "$BASE_BRANCH" ]; then
  REVIEW_FLAGS="--base $BASE_BRANCH"
  echo "=== Codex Branch Review ==="
  echo "Comparing against: $BASE_BRANCH"
elif [ -n "$COMMIT_SHA" ]; then
  REVIEW_FLAGS="--commit $COMMIT_SHA"
  echo "=== Codex Commit Review ==="
  echo "Reviewing commit: $COMMIT_SHA"
else
  REVIEW_FLAGS="--uncommitted"
  echo "=== Codex Code Review ==="
  echo "Reviewing: uncommitted changes"
fi

echo "Working Dir: $WORKDIR"
echo "Instructions: $PROMPT"
echo "========================="
echo ""

codex review $REVIEW_FLAGS "$PROMPT" 2>&1
EXIT_CODE=$?

echo ""
echo "=== REVIEW EXIT CODE: $EXIT_CODE ==="

exit $EXIT_CODE
