# Changelog

All notable changes to codex-delegate are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/), versions follow [SemVer](https://semver.org/).

## [1.6.3] — 2026-06-02

### Fixed
- **Hardened `run-codex-review.sh`'s diff collection** — three issues found by dogfooding the v1.6.2 review on its own fix commit:
  - **Silent error swallowing**: `--base` / `--commit` used `git diff … 2>/dev/null || true`, so an invalid base branch or commit silently became an empty diff and a false "nothing to review" success. Now `git diff` / `git show` failures print the git error and exit 1.
  - **Newline-unsafe untracked paths**: untracked files were read via newline-delimited `git ls-files --others`, mis-splitting paths that contain newlines. Now uses `git ls-files -z` + `read -r -d ''` (NUL-delimited).
  - **Unbounded untracked reads**: untracked file contents were fully read into the diff *before* the `MAX_DIFF_BYTES` cap applied. Now each untracked file is capped with `head -c`, binary/empty files are skipped (`grep -Iq`), and collection stops once the diff already exceeds the cap — so one huge or binary untracked file can't hang the review.

### Note
- All three were surfaced by running v1.6.2's own `run-codex-review.sh` against commit `50c5518` — the freshly-fixed review feature reviewing its own fix, then fixing what it found. Validates that cross-review actually works.

---

## [1.6.2] — 2026-06-01

### Fixed
- **`run-codex-review.sh` was broken on every invocation** — two stacked bugs introduced by v1.6.0's "explicit model lock", masked by how rarely cross-review runs (`run-codex-task.sh` / `run-codex-testfix.sh` were fine: their `xhigh` effort is valid).
  1. **Invalid effort `max`**: codex 0.133.0's `model_reasoning_effort` enum is `none|minimal|low|medium|high|xhigh` — there is **no `max`** (that is a Claude-only level). v1.6.0 hardcoded `max` for review, so codex aborts at config-load with `error: unknown variant 'max'` (EXIT 1) before the API is even called. Fix: review default reverted to `xhigh`, and **all three scripts now validate `CODEX_EFFORT` against the enum**, downgrading unknown values to `xhigh` with a stderr warning (guards against future enum drift).
  2. **Exec-only flags fed to the `codex review` subcommand**: the script passed `--ephemeral/--color/-m/-o/-p`, none of which `codex review` accepts → `error: unexpected argument '--ephemeral'` (EXIT 2) at arg-parse. `codex review` is a minimal subcommand (`-c/--uncommitted/--base/--commit/--title` only), cannot combine a scope flag with a custom prompt, and has no `-o` to capture the report.

### Changed
- **`run-codex-review.sh` rewritten to run as `codex exec -s read-only`** instead of the `codex review` subcommand. The script now computes the diff itself (`git diff HEAD` + untracked files, or `--base` / `--commit`) and **feeds it to codex as text**, so codex spawns no child process. This (a) preserves the `-o` capture + token-economy IO model shared with the other scripts, (b) keeps the structured `[SEVERITY] file:line` output, (c) avoids the Windows "sandbox: spawn setup refresh" bug that would otherwise hang a read-only review at EXIT 124 when codex tries to spawn `git diff` itself, and (d) is truly zero-write. The CLI interface (`run-codex-review.sh <dir> [prompt] [--base|--commit]`) is unchanged.
- **New `MAX_DIFF_BYTES` env var** (default 200000): caps the diff size fed into the review prompt; oversized diffs are truncated with a note.
- **Version sync**: `marketplace.json` bumped 1.5.0 → 1.6.2 (it had lagged behind `plugin.json` / SKILL).

### Note
- The `[1.6.1]` entry claimed "`run-codex-review.sh` left untouched … not affected by the Windows bug." That was wrong on two counts (the effort + flag bugs above); resolved here.

---

## [1.6.1] — 2026-05-26

### Fixed
- **Windows sandbox spawn bug — auto-bypass on Windows**. codex-cli 0.128.0+ on Windows fails every PowerShell subprocess spawn with `ERROR codex_core::exec: exec error: windows sandbox: spawn setup refresh`. Files get created via apply-patch fallback, but every verification step retries the broken sandbox layer, accumulating timeouts until EXIT 124. This is the same error pattern from the V1.3 era — not a regression here, an unfixed upstream issue. Fix: `run-codex-task.sh` and `run-codex-testfix.sh` now detect `OSTYPE=msys*|cygwin*|win32*` or `OS=Windows_NT` and replace `-s workspace-write` with `--dangerously-bypass-approvals-and-sandbox`. The bypassed "sandbox" is one that was broken anyway; safety is retained via Claude's git auto-stash + rollback layer.

### Changed
- **Replaced deprecated `--full-auto`** with explicit `-s workspace-write` (or `-s read-only`). codex-cli 0.128.0+ prints `warning: --full-auto is deprecated; use --sandbox workspace-write instead.` Scripts now use the modern flag; future codex releases that drop `--full-auto` won't break.
- **`run-codex-review.sh` left untouched** — `codex review` is read-only, doesn't spawn PowerShell sandboxes, not affected by the Windows bug.

### Added
- **`CODEX_BYPASS_SANDBOX` env var**: forces or disables the sandbox bypass. Default: `1` on Windows, `0` elsewhere. Set explicitly to override OS detection.
- **`Sandbox:` line in banner output**: displays `workspace-write` / `read-only` / `bypassed (Windows default …)` per invocation. Users can visually confirm which sandbox mode ran.
- **New SKILL.md section "Windows Sandbox Bypass (v1.6.1+)"**: documents the upstream bug, the fix, the safety reasoning, and override examples.

---

## [1.6.0] — 2026-05-24

### Added
- **Explicit model & effort locking** across all three scripts. Every invocation now passes `-m "$CODEX_MODEL"` (default `gpt-5.5`) and `-c model_reasoning_effort="$CODEX_EFFORT"` (default `xhigh` for task/testfix, `max` for review). No more silent inheritance from `~/.codex/config.toml` — any environment-level drift is now visible at the script boundary.
- **Banner output** at the start of every invocation: prints model, effort, mode, timeout, workdir, profile (if set), add-dir (if set). Lets the user visually verify what's about to run before Codex starts reasoning. Symptom-driven: prior versions had no way for the user to confirm which model was being used.
- **`CODEX_PROFILE` env var**: pass through `-p <profile>` to switch among configurations in `~/.codex/config.toml` (e.g., separate API key + model combos for different clients).
- **`CODEX_ADD_DIR` env var**: pass through `--add-dir <path>` for monorepo scenarios where Codex needs write access beyond the primary workspace.
- **Diagnosis Mode prompt template scaffold** in SKILL.md: TODO placeholder for user to fill in their preferred bug-diagnosis output shape.
- New SKILL.md section **"Model & Effort Configuration"**: documents defaults table, env var overrides, and banner output as a verifiability tool.

### Changed
- **SKILL.md `description` rewritten from keyword-list to semantic-trigger style**. Prior version stacked 10+ Chinese/English trigger phrases inside `description:`, which Claude interprets as a keyword list rather than a semantic intent description — diluting trigger reliability. New form: a single coherent sentence describing scenarios where delegation adds value, with 5 representative trigger phrases.
- **"When NOT to Delegate" loosened from hard blockers to soft hints**. Prior version had 5 strict refusal conditions ("Architecture/design discussions", "Tasks requiring deep cross-file context", etc.) that Claude would self-apply to refuse delegation even when the user explicitly asked. v1.6.0: if the user explicitly asks for Codex, delegate. Hints remain to flag cases where Codex offers little value — but they are no longer veto.
- **`/codex` slash command consolidated as explicit entry → skill**. Prior versions had two parallel routing paths (slash command + skill) with subtly different behavior; the command file now declares it routes through the skill. Single source of truth for collaboration logic.
- **`plugin.json` version sync**: bumped to 1.6.0 (was stuck at 1.4.2 even after SKILL bumped to 1.5.0 — version drift fixed).
- **`run-codex-review.sh` default effort upgraded to `max`** (was `xhigh` via inherited config). Reasoning: review is diagnostic; depth matters more than throughput. User can still override via `CODEX_EFFORT=xhigh` if cost-sensitive.

### Fixed
- **Trigger reliability**: combined effect of description rewrite + loosened refusal conditions targets the "skill won't trigger" symptom reported by the user. Prior keyword-list form made Claude treat trigger phrases as literal-match rules, causing both false negatives (semantic asks for delegation not matching exact phrases) and false positives (delegation refused due to over-strict "When NOT to Delegate" conditions).
- **Model drift**: explicit `-m` flag eliminates the silent fallback to whatever `model = ...` happens to be in `~/.codex/config.toml`. If a profile or another tool changes the global default, scripts here are unaffected.

### Token cost impact
- Banner output adds ~50-80 tokens per invocation to Claude's view. Negligible vs the 400-800 token v1.5.0 baseline and the ~10-30× reduction it already delivered.

---

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

[1.6.1]: https://github.com/Rubbish0-A/codex-delegate/releases/tag/1.6.1
[1.6.0]: https://github.com/Rubbish0-A/codex-delegate/releases/tag/1.6.0
[1.5.0]: https://github.com/Rubbish0-A/codex-delegate/releases/tag/1.5.0
[1.4.2]: https://github.com/Rubbish0-A/codex-delegate/releases/tag/1.4.2
[1.4.0]: https://github.com/Rubbish0-A/codex-delegate/releases/tag/1.4.0
