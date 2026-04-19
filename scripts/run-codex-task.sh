#!/usr/bin/env bash
set -euo pipefail

# Usage: run-codex-task.sh <mode> <working_dir> <prompt>
#   mode: full-auto (default) | read-only
#   working_dir: absolute path to project root
#   prompt: task description for Codex
#
# Token-economy design (v1.5.0):
#   - `-o OUTPUT_FILE`: final response (the ONLY thing Claude sees on success)
#   - stdout (event stream, reasoning, tool calls): redirected to STDOUT_LOG, discarded on success
#   - stderr (diagnostics): redirected to STDERR_LOG, tail-dumped only on failure
# Rationale: "2>&1" in previous versions leaked Codex's internal reasoning (~5-20k tokens)
# back into Claude's context, defeating the whole point of delegation.

# ── Pre-flight: Codex CLI Check ──────────────────────────────
if ! command -v codex &>/dev/null; then
  echo "[ERROR] codex CLI not found. Install: npm install -g @openai/codex" >&2
  exit 1
fi

MODE="${1:-full-auto}"
WORKDIR="${2:-.}"
PROMPT="${3:?Error: prompt is required}"
CODEX_TIMEOUT="${CODEX_TIMEOUT:-300}"
CODEX_VERBOSE="${CODEX_VERBOSE:-0}"

OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-output-XXXXXX.md")
STDOUT_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-stdout-XXXXXX.log")
STDERR_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-stderr-XXXXXX.log")
STASHED=false
SCRIPT_COMPLETED=false

cleanup() {
  rm -f "$OUTPUT_FILE" "$STDOUT_LOG" "$STDERR_LOG" 2>/dev/null
  if [ "$SCRIPT_COMPLETED" = false ] && [ "$STASHED" = true ]; then
    echo "" >&2
    echo "=== INTERRUPTED — STASH WARNING ===" >&2
    echo "[WARN] Script was interrupted. Your changes are saved in git stash." >&2
    echo "To restore: cd \"$WORKDIR\" && git stash pop" >&2
  fi
}
trap cleanup EXIT

cd "$WORKDIR"

# ── Pre-flight: Git Safety (silent on clean working tree) ────
IS_GIT=false
HEAD_BEFORE=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
  IS_GIT=true
  if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "[INFO] Uncommitted changes detected. Auto-stashing..."
    git stash push -m "codex-delegate-auto-stash-$(date +%s)" --include-untracked >/dev/null
    STASHED=true
  fi
  HEAD_BEFORE=$(git rev-parse HEAD)
fi

# ── Build flags ──────────────────────────────────────────────
FLAGS=(--ephemeral --color never)
[ "$IS_GIT" = false ] && FLAGS+=(--skip-git-repo-check)

case "$MODE" in
  read-only) FLAGS+=(--full-auto -s read-only) ;;
  full-auto|*) FLAGS+=(--full-auto) ;;
esac

# ── Prompt length constraint (always appended) ───────────────
# Rationale: Codex's default final-response length often blows past what Claude needs.
# This nudge shortens the OUTPUT_FILE that gets read back into context.
FINAL_PROMPT="$PROMPT

---
Response constraint: Keep the final summary concise (under 300 words) and focus on what changed and why. Skip narration of routine edits. If the user explicitly asked for a detailed report, ignore this constraint."

# ── Execute ──────────────────────────────────────────────────
EXIT_CODE=0
timeout "$CODEX_TIMEOUT" codex exec "${FLAGS[@]}" -C "$WORKDIR" -o "$OUTPUT_FILE" "$FINAL_PROMPT" \
  < /dev/null > "$STDOUT_LOG" 2> "$STDERR_LOG" \
  || EXIT_CODE=$?

# ── Output: final response only (success path) ───────────────
echo "=== CODEX FINAL RESPONSE ==="
if [ -s "$OUTPUT_FILE" ]; then
  cat "$OUTPUT_FILE"
else
  echo "(No final response captured)"
fi
echo ""

# ── Failure diagnostics (only when needed) ───────────────────
if [ "$EXIT_CODE" -ne 0 ]; then
  echo "=== CODEX FAILURE (exit $EXIT_CODE) ==="
  if [ "$EXIT_CODE" -eq 124 ]; then
    echo "[TIMEOUT] Exceeded ${CODEX_TIMEOUT}s. Set CODEX_TIMEOUT to increase."
  fi
  echo "--- stderr (last 80 lines) ---"
  tail -n 80 "$STDERR_LOG" 2>/dev/null || echo "(empty)"
  echo "--- stdout (last 40 lines) ---"
  tail -n 40 "$STDOUT_LOG" 2>/dev/null || echo "(empty)"
  echo ""
elif [ "$CODEX_VERBOSE" = "1" ]; then
  echo "=== CODEX STDOUT (verbose mode) ==="
  cat "$STDOUT_LOG"
  echo ""
fi

# ── Post-flight: diff summary (only if changes exist) ────────
if [ "$IS_GIT" = true ]; then
  DIFF_OUTPUT=$(git diff --stat 2>/dev/null || true)
  UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || true)

  if [ -n "$DIFF_OUTPUT" ] || [ -n "$UNTRACKED" ]; then
    echo "=== FILES CHANGED BY CODEX ==="
    [ -n "$DIFF_OUTPUT" ] && echo "$DIFF_OUTPUT"
    if [ -n "$UNTRACKED" ]; then
      echo "New files:"
      echo "$UNTRACKED"
    fi
    echo ""
    echo "=== ROLLBACK ==="
    echo "git reset --hard $HEAD_BEFORE && git clean -fd"
  fi

  if [ "$STASHED" = true ]; then
    echo ""
    echo "[STASH] Prior changes stashed. Review Codex diff, then: git stash pop"
  fi
fi

echo "=== EXIT: $EXIT_CODE ==="
SCRIPT_COMPLETED=true
exit $EXIT_CODE
