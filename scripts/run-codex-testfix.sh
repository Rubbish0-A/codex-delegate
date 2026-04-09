#!/usr/bin/env bash
set -euo pipefail

# Usage: run-codex-testfix.sh <working_dir> <test_command> [max_rounds] [focus_hint]
#   working_dir: absolute path to project root
#   test_command: the test command to run (e.g., "npm test", "pytest", "go test ./...")
#   max_rounds: maximum fix attempts (default: 3)
#   focus_hint: optional hint about which files/modules to focus on

WORKDIR="${1:-.}"
TEST_CMD="${2:?Error: test command is required (e.g., 'npm test', 'pytest')}"
MAX_ROUNDS="${3:-3}"
FOCUS="${4:-}"

OUTPUT_FILE=$(mktemp /tmp/codex-testfix-XXXXXX.md)
STASHED=false

cd "$WORKDIR"

# ── Pre-flight ────────────────────────────────────────────────
echo "=== Codex Test-Fix Cycle ==="
echo "Working Dir: $WORKDIR"
echo "Test Command: $TEST_CMD"
echo "Max Rounds: $MAX_ROUNDS"
if [ -n "$FOCUS" ]; then
  echo "Focus: $FOCUS"
fi
echo "============================="
echo ""

IS_GIT=false
if git rev-parse --is-inside-work-tree &>/dev/null; then
  IS_GIT=true
  if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "[WARN] Uncommitted changes detected. Auto-stashing..."
    git stash push -m "codex-testfix-auto-stash-$(date +%s)" --include-untracked
    STASHED=true
    echo "[OK] Changes stashed safely."
  fi
  HEAD_BEFORE=$(git rev-parse HEAD)
  echo "[OK] HEAD before test-fix: ${HEAD_BEFORE:0:8}"
fi

echo ""

# ── Build prompt ──────────────────────────────────────────────
FOCUS_CLAUSE=""
if [ -n "$FOCUS" ]; then
  FOCUS_CLAUSE="Focus on these files/modules: $FOCUS."
fi

PROMPT="Run the test suite with: $TEST_CMD

If all tests pass, report success and stop.

If any tests fail:
1. Read the test output carefully to understand each failure
2. Identify the root cause in the source code (not in the test files, unless the tests themselves are wrong)
3. Fix the source code to make the failing tests pass
4. Re-run the tests to verify
5. Repeat up to $MAX_ROUNDS rounds total

$FOCUS_CLAUSE

Rules:
- Do NOT modify test files unless they contain clear bugs (wrong assertions, typos)
- Do NOT skip or delete failing tests
- If after $MAX_ROUNDS rounds some tests still fail, STOP and report:
  - Which tests still fail
  - What you tried
  - Your diagnosis of why they fail
  - Suggested next steps for the developer"

# ── Execute ───────────────────────────────────────────────────
FLAGS="--ephemeral --full-auto"
if [ "$IS_GIT" = false ]; then
  FLAGS="$FLAGS --skip-git-repo-check"
fi

echo "=== Starting Test-Fix (max $MAX_ROUNDS rounds) ==="
echo ""

codex exec $FLAGS -C "$WORKDIR" -o "$OUTPUT_FILE" "$PROMPT" 2>&1
EXIT_CODE=$?

echo ""

# ── Results ───────────────────────────────────────────────────
echo "=== CODEX TEST-FIX RESULT ==="
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
  cat "$OUTPUT_FILE"
else
  echo "(No final response captured)"
fi
rm -f "$OUTPUT_FILE"

echo ""

# ── Post-flight ───────────────────────────────────────────────
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

  if [ -n "$DIFF_OUTPUT" ] || [ -n "$UNTRACKED" ]; then
    echo "=== ROLLBACK INFO ==="
    echo "To undo all fixes: git checkout -- . && git clean -fd"
    echo "HEAD before test-fix: $HEAD_BEFORE"
  fi

  if [ "$STASHED" = true ]; then
    echo ""
    echo "=== STASH RESTORE ==="
    echo "[INFO] Prior changes were auto-stashed."
    echo "To restore: git stash pop"
  fi
fi

echo ""
echo "=== TEST-FIX EXIT CODE: $EXIT_CODE ==="

exit $EXIT_CODE
