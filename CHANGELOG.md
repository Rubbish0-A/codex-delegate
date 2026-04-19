# Changelog

All notable changes to codex-delegate are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/), versions follow [SemVer](https://semver.org/).

## [1.5.0] — 2026-04-19

### Added
- **Token-economy IO isolation** across all three scripts. Codex's event stream (reasoning, tool calls, partial output) is now redirected to a discarded log file on the success path. Claude's context only sees the `-o FILE` final response plus a compact diff summary.
- `CODEX_VERBOSE=1` environment variable: dump the full suppressed stdout event stream when you need to debug what Codex actually did.
- `--color never` flag on all codex invocations: strips ANSI escape codes from captured output.
- Automatic prompt-length constraint in `run-codex-task.sh`: final response nudged to under 300 words unless the user explicitly asked for detail.
- Structured review output contract in `run-codex-review.sh`: single-line `[SEVERITY] file:line — issue (fix: ...)` format, MEDIUM-or-higher only by default.
- Structured test-fix report schema in `run-codex-testfix.sh`: `Result / Rounds / counts / files modified / remaining failures / next steps`. No per-round narration or test-output dumps.
- `CHANGELOG.md`: this file.
- New SKILL.md section **"Prompt Economy (token-cost awareness)"**: guidance for future delegations to shape the `-o FILE` payload at the prompt level.

### Changed
- Failure diagnostics are now surgical: stderr last 80 lines + stdout last 40 lines, only on non-zero exit. Prior versions tail-dumped the full 2>&1 stream unconditionally.
- Success-path pre-flight output is silent when the working tree is clean. Rollback info only appears when changes actually occurred.
- Rollback hint upgraded from `git checkout -- . && git clean -fd` to `git reset --hard $HEAD_BEFORE && git clean -fd` (captured SHA, safer across mixed tracked/untracked changes).

### Fixed
- **`set -euo pipefail` + `timeout` interaction bug**: previous versions used `timeout ...; EXIT_CODE=$?`, which under `set -e` aborts the script before reaching the `$?` assignment when timeout triggers (exit 124). Replaced with `... || EXIT_CODE=$?` so timeout failures now surface the proper exit code, run the failure-diagnostics branch, and invoke the stash-restore warning as designed.

### Token cost impact (estimated, one medium-complexity `codex exec` task)
- Before v1.5.0: ~8,000-25,000 tokens flowed into Claude's context (stderr + stdout + duplicated final response).
- After v1.5.0: ~400-800 tokens (final response + diff stat + exit code).
- ~10-30× reduction on the Claude side. Codex-side cost unchanged (that was never the problem).

---

## [1.4.2] — 2026-04-14
Stability hardening for all scripts: codex CLI pre-flight check, `trap cleanup EXIT`, `timeout $CODEX_TIMEOUT` (default 300s task/review, 600s testfix), FLAGS arrays instead of string concatenation, review output capture to file, `SCRIPT_COMPLETED` flag to suppress duplicate stash warnings on normal exit.

## [1.4.1] — 2026-04-14
Fixed stdin hang on Windows: all `codex exec` and `codex review` invocations now close stdin explicitly via `< /dev/null`.

## [1.4.0] — 2026-04-10
Flexible collaboration modes: Cautious (default, plan-then-execute) / Quick / Diagnosis.

## [1.3.0] — 2026-04-10
Plugin discovery fix: added `.claude-plugin/marketplace.json`. Updated install guide.

## [1.2.1] — 2026-04-09
Quality pass: SKILL.md trimmed 42%, five bugs fixed.

## [1.2.0] — 2026-04-09
Development-workflow integration: cross review, test-fix loop, bug diagnosis scripts.

## [1.1.0] — 2026-04-08
Conflict-prevention mechanism (three layers) and install documentation.

## [1.0.0] — 2026-04-08
Initial release: on-demand delegation, `/codex` slash command, git safety checks.

[1.5.0]: https://github.com/Rubbish0-A/codex-delegate/releases/tag/1.5.0
[1.4.2]: https://github.com/Rubbish0-A/codex-delegate/releases/tag/1.4.2
[1.4.0]: https://github.com/Rubbish0-A/codex-delegate/releases/tag/1.4.0
