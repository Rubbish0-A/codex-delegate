#!/usr/bin/env bash
set -euo pipefail

# Usage: run-codex-task.sh <mode> <working_dir> <prompt>
#   mode: full-auto (default) | read-only
#   working_dir: absolute path to project root
#   prompt: task description for Codex

MODE="${1:-full-auto}"
WORKDIR="${2:-.}"
PROMPT="${3:?Error: prompt is required}"

OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-output-XXXXXX.md")
STASHED=false

cd "$WORKDIR"

# ── Pre-flight: Git Safety Check ──────────────────────────────
echo "=== Pre-flight Check ==="

if git rev-parse --is-inside-work-tree &>/dev/null; then
  IS_GIT=true

  # Check for uncommitted changes
  if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "[WARN] Uncommitted changes detected. Auto-stashing..."
    git stash push -m "codex-delegate-auto-stash-$(date +%s)" --include-untracked
    STASHED=true
    echo "[OK] Changes stashed safely."
  else
    echo "[OK] Working tree is clean."
  fi

  # Record current HEAD for rollback
  HEAD_BEFORE=$(git rev-parse HEAD)
  echo "[OK] HEAD before Codex: ${HEAD_BEFORE:0:8}"
else
  IS_GIT=false
  echo "[INFO] Not a git repo. Will use --skip-git-repo-check."
fi

echo ""

# ── Execute Codex ─────────────────────────────────────────────
FLAGS="--ephemeral"

# Non-git directories need skip flag
if [ "$IS_GIT" = false ]; then
  FLAGS="$FLAGS --skip-git-repo-check"
fi

case "$MODE" in
  full-auto)
    FLAGS="$FLAGS --full-auto"
    ;;
  read-only)
    FLAGS="$FLAGS --full-auto -s read-only"
    ;;
  *)
    FLAGS="$FLAGS --full-auto"
    ;;
esac

echo "=== Codex Task Delegation ==="
echo "Mode: $MODE"
echo "Working Dir: $WORKDIR"
echo "Prompt: $PROMPT"
echo "=============================="
echo ""

codex exec $FLAGS -C "$WORKDIR" -o "$OUTPUT_FILE" "$PROMPT" < /dev/null 2>&1
EXIT_CODE=$?

echo ""

# ── Codex Output ──────────────────────────────────────────────
echo "=== CODEX FINAL RESPONSE ==="
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
  cat "$OUTPUT_FILE"
else
  echo "(No final response captured)"
fi
rm -f "$OUTPUT_FILE"

echo ""

# ── Post-flight: Diff & Status ────────────────────────────────
if [ "$IS_GIT" = true ]; then
  echo "=== FILES CHANGED BY CODEX ==="
  DIFF_OUTPUT=$(git diff --stat 2>/dev/null || true)
  UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || true)

  if [ -n "$DIFF_OUTPUT" ]; then
    echo "$DIFF_OUTPUT"
  fi
  if [ -n "$UNTRACKED" ]; then
    echo ""
    echo "New files:"
    echo "$UNTRACKED"
  fi
  if [ -z "$DIFF_OUTPUT" ] && [ -z "$UNTRACKED" ]; then
    echo "(No file changes detected)"
  fi

  echo ""

  # Provide rollback info
  if [ -n "$DIFF_OUTPUT" ] || [ -n "$UNTRACKED" ]; then
    echo "=== ROLLBACK INFO ==="
    echo "To undo Codex changes: git checkout -- . && git clean -fd"
    echo "HEAD before Codex: $HEAD_BEFORE"
  fi

  # Restore stashed changes if we stashed earlier
  if [ "$STASHED" = true ]; then
    echo ""
    echo "=== STASH RESTORE ==="
    echo "[INFO] Claude's prior changes were auto-stashed."
    echo "To restore: git stash pop"
    echo "[WARN] Review Codex changes before restoring to avoid conflicts."
  fi
fi

echo ""
echo "=== CODEX EXIT CODE: $EXIT_CODE ==="

exit $EXIT_CODE
