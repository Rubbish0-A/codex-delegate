#!/usr/bin/env bash
set -euo pipefail

# Usage: run-codex-review.sh <working_dir> [review_prompt] [--base <branch>] [--commit <sha>]
#
# Token-economy design (v1.5.0):
#   - `-o OUTPUT_FILE`: final review report (what Claude sees)
#   - stdout: event stream → STDOUT_LOG, discarded on success
#   - stderr: diagnostics → STDERR_LOG, tail-dumped only on failure

# ── Pre-flight ───────────────────────────────────────────────
if ! command -v codex &>/dev/null; then
  echo "[ERROR] codex CLI not found. Install: npm install -g @openai/codex" >&2
  exit 1
fi

WORKDIR="${1:-.}"
shift || true
CODEX_TIMEOUT="${CODEX_TIMEOUT:-300}"
CODEX_VERBOSE="${CODEX_VERBOSE:-0}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.5}"
# Review tasks default to max effort: depth > speed for diagnostic work.
CODEX_EFFORT="${CODEX_EFFORT:-max}"
CODEX_PROFILE="${CODEX_PROFILE:-}"

OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-review-XXXXXX.md")
STDOUT_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-review-stdout-XXXXXX.log")
STDERR_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-review-stderr-XXXXXX.log")

cleanup() {
  rm -f "$OUTPUT_FILE" "$STDOUT_LOG" "$STDERR_LOG" 2>/dev/null
}
trap cleanup EXIT

# ── Parse arguments ──────────────────────────────────────────
# Review prompts deliberately enforce structured output (severity + file:line + fix)
# so that Claude can parse and surface only CRITICAL/HIGH findings if context is tight.
PROMPT="Review the code for bugs, security issues, performance problems, and suggest improvements. For each finding, report on a single structured line: [SEVERITY] <file>:<line> — <issue> (fix: <suggestion>). Severity: CRITICAL/HIGH/MEDIUM/LOW. Skip findings below MEDIUM unless they are safety-relevant. End with a one-line summary of total findings per severity."
BASE_BRANCH=""
COMMIT_SHA=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --commit) COMMIT_SHA="$2"; shift 2 ;;
    *) PROMPT="$1"; shift ;;
  esac
done

cd "$WORKDIR"

# ── Build flags ──────────────────────────────────────────────
REVIEW_FLAGS=(--ephemeral --color never -m "$CODEX_MODEL" -c "model_reasoning_effort=\"$CODEX_EFFORT\"")
[ -n "$CODEX_PROFILE" ] && REVIEW_FLAGS+=(-p "$CODEX_PROFILE")
if [ -n "$BASE_BRANCH" ]; then
  REVIEW_FLAGS+=(--base "$BASE_BRANCH")
  REVIEW_SCOPE="against base: $BASE_BRANCH"
elif [ -n "$COMMIT_SHA" ]; then
  REVIEW_FLAGS+=(--commit "$COMMIT_SHA")
  REVIEW_SCOPE="commit: $COMMIT_SHA"
else
  REVIEW_FLAGS+=(--uncommitted)
  REVIEW_SCOPE="uncommitted changes"
fi

# ── Banner ───────────────────────────────────────────────────
echo "=== CODEX REVIEW ==="
echo "Model:    $CODEX_MODEL"
echo "Effort:   $CODEX_EFFORT"
echo "Scope:    $REVIEW_SCOPE"
echo "Timeout:  ${CODEX_TIMEOUT}s"
[ -n "$CODEX_PROFILE" ] && echo "Profile:  $CODEX_PROFILE"
echo "Workdir:  $WORKDIR"
echo ""

# ── Execute ──────────────────────────────────────────────────
EXIT_CODE=0
timeout "$CODEX_TIMEOUT" codex review "${REVIEW_FLAGS[@]}" -o "$OUTPUT_FILE" "$PROMPT" \
  < /dev/null > "$STDOUT_LOG" 2> "$STDERR_LOG" \
  || EXIT_CODE=$?

# ── Output ───────────────────────────────────────────────────
echo "=== CODEX REVIEW REPORT ==="
if [ -s "$OUTPUT_FILE" ]; then
  cat "$OUTPUT_FILE"
else
  echo "(No review output captured)"
fi
echo ""

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "=== CODEX REVIEW FAILURE (exit $EXIT_CODE) ==="
  if [ "$EXIT_CODE" -eq 124 ]; then
    echo "[TIMEOUT] Exceeded ${CODEX_TIMEOUT}s. Set CODEX_TIMEOUT to increase."
  fi
  echo "--- stderr (last 80 lines) ---"
  tail -n 80 "$STDERR_LOG" 2>/dev/null || echo "(empty)"
  echo "--- stdout (last 40 lines) ---"
  tail -n 40 "$STDOUT_LOG" 2>/dev/null || echo "(empty)"
elif [ "$CODEX_VERBOSE" = "1" ]; then
  echo "=== CODEX STDOUT (verbose mode) ==="
  cat "$STDOUT_LOG"
fi

echo "=== EXIT: $EXIT_CODE ==="
exit $EXIT_CODE
