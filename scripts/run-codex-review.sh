#!/usr/bin/env bash
set -euo pipefail

# Usage: run-codex-review.sh <working_dir> [review_prompt]
#   working_dir: absolute path to project root
#   review_prompt: optional custom review instructions

WORKDIR="${1:-.}"
PROMPT="${2:-Review the code for bugs, security issues, performance problems, and suggest improvements}"

echo "=== Codex Code Review ==="
echo "Working Dir: $WORKDIR"
echo "Instructions: $PROMPT"
echo "========================="
echo ""

cd "$WORKDIR"

# Execute Codex review on uncommitted changes
codex review --uncommitted "$PROMPT" 2>&1
EXIT_CODE=$?

echo ""
echo "=== REVIEW EXIT CODE: $EXIT_CODE ==="

exit $EXIT_CODE
