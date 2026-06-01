#!/usr/bin/env bash
set -euo pipefail

# Usage: run-codex-review.sh <working_dir> [review_prompt] [--base <branch>] [--commit <sha>]
#
# Implementation note (v1.6.2 fix):
#   The old version called the `codex review` subcommand with exec-only flags
#   (--ephemeral/--color/-m/-o/-p), NONE of which it accepts → EXIT 2 at arg-parse
#   ("unexpected argument '--ephemeral'"). `codex review` also refuses a scope flag
#   together with a custom PROMPT and has no -o to capture the report.
#   A naive rewrite to `codex exec -s read-only` that let codex spawn `git diff`
#   itself re-triggered the Windows "sandbox: spawn setup refresh" bug and hung
#   until timeout (EXIT 124).
#   Final fix: the SCRIPT computes the diff and feeds it as TEXT to codex exec
#   read-only. codex spawns no child process → no Windows sandbox spawn bug, truly
#   zero-write, and the -o capture + token-economy IO model match run-codex-task.sh.
#
# Token-economy design:
#   - `-o OUTPUT_FILE`: final review report (the ONLY thing Claude sees on success)
#   - stdout (event stream/reasoning): → STDOUT_LOG, discarded on success
#   - stderr (diagnostics): → STDERR_LOG, tail-dumped only on failure

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
# Review defaults to xhigh effort: depth > speed for diagnostic work.
# NOTE: codex has NO "max" effort — that is a Claude-only level. See effort guard below.
CODEX_EFFORT="${CODEX_EFFORT:-xhigh}"
CODEX_PROFILE="${CODEX_PROFILE:-}"
MAX_DIFF_BYTES="${MAX_DIFF_BYTES:-200000}"

# ── Effort guard: codex's model_reasoning_effort enum ≠ Claude's effort levels ──
# codex 0.133.0 accepts: none|minimal|low|medium|high|xhigh. A Claude-style "max"
# (or any future enum drift) crashes codex at config-load time (EXIT 1) before the
# API is even called. Downgrade unknown values to xhigh instead of hard-failing.
case "$CODEX_EFFORT" in
  none|minimal|low|medium|high|xhigh) ;;
  *)
    echo "[WARN] CODEX_EFFORT='$CODEX_EFFORT' not supported by codex (valid: none/minimal/low/medium/high/xhigh). Falling back to xhigh." >&2
    CODEX_EFFORT="xhigh"
    ;;
esac

# ── Parse arguments ──────────────────────────────────────────
CUSTOM_PROMPT=""
BASE_BRANCH=""
COMMIT_SHA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --commit) COMMIT_SHA="$2"; shift 2 ;;
    *) CUSTOM_PROMPT="$1"; shift ;;
  esac
done

cd "$WORKDIR"

# ── Must be a git repo (review operates on a diff) ───────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "[ERROR] run-codex-review.sh requires a git repository (it reviews a diff)." >&2
  echo "        For non-git review, use: run-codex-task.sh read-only <dir> \"<review prompt>\"" >&2
  exit 1
fi

# ── Collect the diff TEXT ourselves (codex must NOT spawn git) ──
if [ -n "$BASE_BRANCH" ]; then
  DIFF=$(git diff "$BASE_BRANCH"...HEAD 2>/dev/null || true)
  REVIEW_SCOPE="against base: $BASE_BRANCH"
elif [ -n "$COMMIT_SHA" ]; then
  DIFF=$(git show "$COMMIT_SHA" 2>/dev/null || true)
  REVIEW_SCOPE="commit: $COMMIT_SHA"
else
  DIFF=$(git diff HEAD 2>/dev/null || true)
  # Append untracked files as additions so they are reviewed too.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    DIFF+=$'\n'"diff --git a/$f b/$f (untracked new file)"$'\n'
    DIFF+="$(sed 's/^/+/' "$f" 2>/dev/null || true)"$'\n'
  done < <(git ls-files --others --exclude-standard 2>/dev/null)
  REVIEW_SCOPE="uncommitted changes"
fi

# ── Nothing to review? exit cleanly ──────────────────────────
if [ -z "${DIFF//[$'\n\t ']/}" ]; then
  echo "=== CODEX REVIEW ==="
  echo "Scope:    $REVIEW_SCOPE"
  echo ""
  echo "(No changes in scope — nothing to review.)"
  echo "=== EXIT: 0 ==="
  exit 0
fi

# ── Truncate oversized diffs (guard prompt size) ─────────────
DIFF_TRUNCATED=false
if [ "${#DIFF}" -gt "$MAX_DIFF_BYTES" ]; then
  DIFF="${DIFF:0:$MAX_DIFF_BYTES}"
  DIFF_TRUNCATED=true
fi

OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-review-XXXXXX.md")
STDOUT_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-review-stdout-XXXXXX.log")
STDERR_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-review-stderr-XXXXXX.log")
cleanup() { rm -f "$OUTPUT_FILE" "$STDOUT_LOG" "$STDERR_LOG" 2>/dev/null; }
trap cleanup EXIT

# ── Build review prompt (diff embedded as text) ──────────────
STRUCT="For each finding, report on a single structured line: [SEVERITY] <file>:<line> — <issue> (fix: <suggestion>). Severity is one of CRITICAL/HIGH/MEDIUM/LOW. Skip findings below MEDIUM unless they are safety-relevant. End with a one-line summary of total findings per severity."
INSTR="${CUSTOM_PROMPT:-Review the diff below for bugs, security issues, and performance problems.}"
TRUNC_NOTE=""
[ "$DIFF_TRUNCATED" = true ] && TRUNC_NOTE=" (NOTE: diff truncated to ${MAX_DIFF_BYTES} bytes; review the portion shown.)"
REVIEW_PROMPT="$INSTR Analyze ONLY the diff text below — do not run any commands.$TRUNC_NOTE $STRUCT

\`\`\`diff
$DIFF
\`\`\`"

# ── Build flags (read-only exec, text-only → no child spawn, no Windows bypass) ──
FLAGS=(--ephemeral --color never -m "$CODEX_MODEL" -c "model_reasoning_effort=\"$CODEX_EFFORT\"" -s read-only --skip-git-repo-check)
[ -n "$CODEX_PROFILE" ] && FLAGS+=(-p "$CODEX_PROFILE")

# ── Banner ───────────────────────────────────────────────────
echo "=== CODEX REVIEW ==="
echo "Model:    $CODEX_MODEL"
echo "Effort:   $CODEX_EFFORT"
echo "Scope:    $REVIEW_SCOPE"
echo "Sandbox:  read-only (diff fed as text)"
echo "Timeout:  ${CODEX_TIMEOUT}s"
[ "$DIFF_TRUNCATED" = true ] && echo "Note:     diff truncated to ${MAX_DIFF_BYTES} bytes"
[ -n "$CODEX_PROFILE" ] && echo "Profile:  $CODEX_PROFILE"
echo "Workdir:  $WORKDIR"
echo ""

# ── Execute ──────────────────────────────────────────────────
EXIT_CODE=0
timeout "$CODEX_TIMEOUT" codex exec "${FLAGS[@]}" -C "$WORKDIR" -o "$OUTPUT_FILE" "$REVIEW_PROMPT" \
  < /dev/null > "$STDOUT_LOG" 2> "$STDERR_LOG" \
  || EXIT_CODE=$?

# ── Output: final report only (success path) ─────────────────
echo "=== CODEX REVIEW REPORT ==="
if [ -s "$OUTPUT_FILE" ]; then
  cat "$OUTPUT_FILE"
else
  echo "(No review output captured)"
fi
echo ""

# ── Failure diagnostics (only when needed) ───────────────────
if [ "$EXIT_CODE" -ne 0 ]; then
  echo "=== CODEX REVIEW FAILURE (exit $EXIT_CODE) ==="
  if [ "$EXIT_CODE" -eq 124 ]; then
    echo "[TIMEOUT] Exceeded ${CODEX_TIMEOUT}s. Increase CODEX_TIMEOUT, or check network to the codex provider."
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
