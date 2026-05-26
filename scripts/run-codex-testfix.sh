#!/usr/bin/env bash
set -euo pipefail

# Usage: run-codex-testfix.sh <working_dir> <test_command> [max_rounds] [focus_hint]
#
# Token-economy design (v1.5.0):
# testfix is the HEAVIEST script — N rounds of test output flow through Codex's stdout.
# Keeping 2>&1 here would be catastrophic for Claude's context.
#   - `-o OUTPUT_FILE`: final structured report (what Claude sees)
#   - stdout (full test runs + reasoning): → STDOUT_LOG, discarded on success
#   - stderr (diagnostics): → STDERR_LOG, tail-dumped only on failure

# ── Pre-flight ───────────────────────────────────────────────
if ! command -v codex &>/dev/null; then
  echo "[ERROR] codex CLI not found. Install: npm install -g @openai/codex" >&2
  exit 1
fi

WORKDIR="${1:-.}"
TEST_CMD="${2:?Error: test command is required (e.g., 'npm test', 'pytest')}"
MAX_ROUNDS="${3:-3}"
FOCUS="${4:-}"
CODEX_TIMEOUT="${CODEX_TIMEOUT:-600}"
CODEX_VERBOSE="${CODEX_VERBOSE:-0}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.5}"
CODEX_EFFORT="${CODEX_EFFORT:-xhigh}"
CODEX_PROFILE="${CODEX_PROFILE:-}"
CODEX_ADD_DIR="${CODEX_ADD_DIR:-}"

# ── OS detection: Windows bypass sandbox (see run-codex-task.sh for rationale)
IS_WINDOWS=false
case "${OSTYPE:-}" in msys*|cygwin*|win32*) IS_WINDOWS=true ;; esac
[ "${OS:-}" = "Windows_NT" ] && IS_WINDOWS=true
DEFAULT_BYPASS=0
[ "$IS_WINDOWS" = true ] && DEFAULT_BYPASS=1
CODEX_BYPASS_SANDBOX="${CODEX_BYPASS_SANDBOX:-$DEFAULT_BYPASS}"

OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-testfix-XXXXXX.md")
STDOUT_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-testfix-stdout-XXXXXX.log")
STDERR_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-testfix-stderr-XXXXXX.log")
STASHED=false
SCRIPT_COMPLETED=false

cleanup() {
  rm -f "$OUTPUT_FILE" "$STDOUT_LOG" "$STDERR_LOG" 2>/dev/null
  if [ "$SCRIPT_COMPLETED" = false ] && [ "$STASHED" = true ]; then
    echo "" >&2
    echo "=== INTERRUPTED — STASH WARNING ===" >&2
    echo "[WARN] Changes saved in git stash. Restore: cd \"$WORKDIR\" && git stash pop" >&2
  fi
}
trap cleanup EXIT

cd "$WORKDIR"

# ── Pre-flight: git safety (silent on clean tree) ────────────
IS_GIT=false
HEAD_BEFORE=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
  IS_GIT=true
  if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "[INFO] Uncommitted changes detected. Auto-stashing..."
    git stash push -m "codex-testfix-auto-stash-$(date +%s)" --include-untracked >/dev/null
    STASHED=true
  fi
  HEAD_BEFORE=$(git rev-parse HEAD)
fi

# ── Build prompt ─────────────────────────────────────────────
FOCUS_CLAUSE=""
[ -n "$FOCUS" ] && FOCUS_CLAUSE="Focus on these files/modules: $FOCUS."

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
- If after $MAX_ROUNDS rounds some tests still fail, STOP and report.

---
Final report format (keep concise, under 400 words):
- Result: PASS | PARTIAL | FAIL
- Rounds used: N / $MAX_ROUNDS
- Passed / failed test counts (from final run)
- Files modified: <list, one per line>
- Remaining failures (if any): <test name> — <one-line diagnosis>
- Next steps for developer (only if PARTIAL or FAIL)

Do NOT include full test output, stack traces, or per-round narration — those are already visible in the event log if needed."

# ── Execute ──────────────────────────────────────────────────
# Note: --full-auto deprecated → use explicit -s workspace-write; on Windows
# the bypass flag replaces -s entirely (see SKILL.md "Windows sandbox bypass").
FLAGS=(--ephemeral --color never -m "$CODEX_MODEL" -c "model_reasoning_effort=\"$CODEX_EFFORT\"")
[ -n "$CODEX_PROFILE" ] && FLAGS+=(-p "$CODEX_PROFILE")
[ -n "$CODEX_ADD_DIR" ] && FLAGS+=(--add-dir "$CODEX_ADD_DIR")
[ "$IS_GIT" = false ] && FLAGS+=(--skip-git-repo-check)

SANDBOX_LABEL=""
if [ "$CODEX_BYPASS_SANDBOX" = "1" ]; then
  FLAGS+=(--dangerously-bypass-approvals-and-sandbox)
  SANDBOX_LABEL="bypassed (Windows default — set CODEX_BYPASS_SANDBOX=0 to disable)"
else
  FLAGS+=(-s workspace-write)
  SANDBOX_LABEL="workspace-write"
fi

# ── Banner ───────────────────────────────────────────────────
echo "=== CODEX TEST-FIX ==="
echo "Model:    $CODEX_MODEL"
echo "Effort:   $CODEX_EFFORT"
echo "Sandbox:  $SANDBOX_LABEL"
echo "TestCmd:  $TEST_CMD"
echo "Rounds:   $MAX_ROUNDS"
echo "Timeout:  ${CODEX_TIMEOUT}s"
[ -n "$CODEX_PROFILE" ] && echo "Profile:  $CODEX_PROFILE"
[ -n "$CODEX_ADD_DIR" ] && echo "AddDir:   $CODEX_ADD_DIR"
[ -n "$FOCUS" ] && echo "Focus:    $FOCUS"
echo "Workdir:  $WORKDIR"
echo ""

EXIT_CODE=0
timeout "$CODEX_TIMEOUT" codex exec "${FLAGS[@]}" -C "$WORKDIR" -o "$OUTPUT_FILE" "$PROMPT" \
  < /dev/null > "$STDOUT_LOG" 2> "$STDERR_LOG" \
  || EXIT_CODE=$?

# ── Output ───────────────────────────────────────────────────
echo "=== CODEX TEST-FIX RESULT ==="
if [ -s "$OUTPUT_FILE" ]; then
  cat "$OUTPUT_FILE"
else
  echo "(No final response captured)"
fi
echo ""

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "=== CODEX TEST-FIX FAILURE (exit $EXIT_CODE) ==="
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

# ── Post-flight ──────────────────────────────────────────────
if [ "$IS_GIT" = true ]; then
  DIFF_OUTPUT=$(git diff --stat 2>/dev/null || true)
  UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || true)

  if [ -n "$DIFF_OUTPUT" ] || [ -n "$UNTRACKED" ]; then
    echo "=== FILES CHANGED ==="
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
    echo "[STASH] Prior changes stashed. Review diff, then: git stash pop"
  fi
fi

echo "=== EXIT: $EXIT_CODE ==="
SCRIPT_COMPLETED=true
exit $EXIT_CODE
