# OpenCode

Verified on 2026-06-11 across versions 1.15.7 through 1.17.6, with busy-queue behavior re-verified on 2026-07-20 using 1.18.4.

## Operating facts

| Fact | Value |
|---|---|
| Busy state | The Firstmate-owned plugin's semantic `session.status` on 1.x (`busy` and `retry` are active, `idle` is inactive) or `session.execution.*` on 2.x (`started` is active; `succeeded`, `failed`, and `interrupted` are inactive), latched to the worker's own session. |
| Exit command | `/exit`. |
| Interrupt | Double Escape; it is known to be flaky while a long shell command runs, so use `../../../bin/fm-control.sh <task-id> relaunch` for a wedged pane. |
| Skill invocation | No separate verified form beyond normal slash-command behavior; use natural language when the exact command is uncertain. |
| Resume | Relaunch with `--continue` to resume the most recent session for the current directory, then send the next instruction after the TUI is ready because `--prompt` does not auto-submit alongside `--continue`. |
| Model flag | `--model <provider/model>`. |
| Effort flag | None for Firstmate's interactive `opencode --prompt` launch; `opencode run` has `--variant`, but that is not this path. The effort instead rides the launch's `OPENCODE_CONFIG_CONTENT` JSON as the `build` agent's `variant` keyed to the resolved model, the config schema's per-model reasoning-effort field verified on 1.18.32. It is emitted only when the resolved model's provider is known to expose that effort as a variant (`anthropic/*`: high, max; `openai/*`: low, medium, high, xhigh); with no model resolved, another provider, or an effort outside its family's list, the variant is omitted and the permission-only launch is unchanged. |
| Model discovery | Run `opencode models [provider]` to list available provider/model identifiers. |
| Trust dialog | None. |
| Marker | None; OpenCode publishes no identity marker, so `../../../bin/fm-harness.sh` identifies it from process ancestry. |

OpenCode can auto-upgrade in the background, and the running TUI can exit mid-task.
That behavior was observed live during an upgrade from 1.15.7 to 1.17.3.
If the pane shows the exit banner, use the verified resume path above.

## Busy-queued Enter

While OpenCode 1.18.4 is mid-turn, its composer accepts Enter as a "send when the turn ends" keystroke but does not clear the typed text until the turn finishes.
Without a conversion, every typed-plane send to a busy OpenCode pane falsely reports "Enter swallowed", and a daemon escalation that lands while the primary is mid-turn appears wedged.

Tmux and Herdr delegate this exception to the one `fm_composer_queued_enter_verdict` policy in `../../../bin/fm-composer-lib.sh`.
Backend-specific signals are documented in `../../../docs/tmux-backend.md` and `../../../docs/herdr-backend.md`.
Regression coverage is `../../../tests/fm-tmux-submit-busy.test.sh`, `../../../tests/fm-composer-lib.test.sh`, and `../../../tests/fm-backend-herdr.test.sh`.
The live Herdr guard is `FM_HERDR_SUBMIT_CONFIRM_LIVE=1 ../../../tests/fm-herdr-submit-confirm-live-e2e.test.sh`.

## Primary integration

The primary integration was verified on 2026-07-08 with OpenCode 1.17.6.
`.opencode/plugins/fm-primary-turnend-guard.js` listens for `session.idle`.
Throwing from `session.idle` does not block `opencode run`, so the primary adapter treats the event as passive and uses `client.session.promptAsync` to force one follow-up turn when `../../../bin/fm-turnend-guard.sh` returns 2.
The follow-up was verified in the interactive TUI.
In a home with `config/supervision-host` and no `config/supervision-host-off` the watch-arm plugin spawns the supervision host instead of `../../../bin/fm-watch-arm.sh`, with Claude's print mode as its headless engine; [`supervision-host.md`](../../../../../docs/supervision-host.md) owns the host.
`opencode run` can exit before displaying a queued follow-up, so the adapter steps aside in headless mode.
On native Windows, the operational-input adapter runs its Bash helper through `bash`; macOS and Linux invoke it directly.

The companion `.opencode/plugins/fm-primary-watch-arm.js` owns normal TUI watcher supervision, wakes it with `client.session.promptAsync`, and coordinates with the guard before a blind-turn follow-up.
The PreToolUse-equivalent watcher-arm seatbelt blocks by throwing from `tool.execute.before`.

## Worker busy-state plugin

`../../../bin/fm-spawn.sh` writes the per-worker `.opencode/plugins/fm-busy-state.js`, whose `opencode-plugin` busy state supervision reads; the semantic contract is owned by [`fm-busy-lib.sh`](../../../../../bin/fm-busy-lib.sh).
Its export shape follows the OpenCode major that `opencode --version` reports at spawn, because the two loaders cannot share one shape.
On 2.x it carries the v1 named function plus an object default export, because OpenCode 2.x's loader never calls the v1 named function.
On 1.x, or when the probe fails or prints no parseable version, it carries only the v1 named function, because a 1.x loader calls every module export as a plugin function and fails on an object default export.
The 2.x loader loads the module and calls the default export's `setup(ctx)`, so a file exporting only the v1 named function installs no hook at all and the worker silently loses its semantic busy state and falls back to pane heuristics.
Verified live on 2026-10-08 using 2.0.24: a v1-only copy was loaded with its module body evaluated and neither hook installed.

The v2 event surface differs in kind, not only in shape.
A v2 event carries its payload under `data` rather than `properties`, and v2 publishes neither `session.status` nor `session.idle`.
A turn opens with `session.execution.started` and closes with a terminal `session.execution.succeeded`, `failed`, or `interrupted`.
The default export replays those onto the v1 `session.status` and `session.idle` shapes the v1 handler already implements, so the session latch and the busy/idle semantics have one implementation rather than two that can drift.
An in-turn provider retry needs no event of its own: the session stays latched busy because no terminal execution event has fired yet.

The generated file must be self-contained, because fm-spawn writes it into an arbitrary project's worktree, which carries none of firstmate's own plugin code.
The stream stays open for the plugin's lifetime and the returned teardown aborts it; an unexpected stop would freeze the busy record silently, so it is reported on stderr instead.
Regression coverage is `../../../tests/fm-busy-adapter-wiring.test.sh`, which drives the 2.x shape's default export the way the v2 loader does, over a real async event stream, and loads the 1.x and unknown-version shapes the way the v1 loader does.
