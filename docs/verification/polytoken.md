# Polytoken CLI worker verification

Audience: maintainer verification.

The [adapter reference](../../.agents/skills/harness-adapters/references/harness/polytoken.md) owns operating facts; executable owners carry launch and state mechanics.
The adapter selects capabilities from the installed binary and has no Polytoken version gate.
The release numbers below identify evidence, not requirements.
This record covers crewmates and scouts on the tmux TUI-pane-plus-REST-control path, plus the Herdr-lab brief and doorbell delivery evidence below.
Primary, secondmate, and native Herdr pane placement are outside this guarantee.

## Refresh commands

```sh
polytoken --version
polytoken new --help
polytoken print models
polytoken models --format json
polytoken print openapi
bash bin/fm-test-run.sh tests/fm-polytoken-harness.test.sh
FM_POLYTOKEN_SIGNALS_LIVE=1 bash bin/fm-test-run.sh tests/fm-polytoken-signals-live-e2e.test.sh
```

The credentialed guard uses a marked disposable `FM_HOME` and the private tmux socket directory supplied by `bin/fm-lab-home.sh`.
It stages a copy of provider/model configuration without operator MCP services, and copies the operator's existing license acceptance into an isolated HOME.
No license acceptance is created or extended, and no trust or license dialog is answered.
All Polytoken session, configuration, cache, and log writes stay in that lab.
The guard uses a scratch clone and a `treehouse` stand-in rather than touching a shared worktree pool.
Its real Firstmate verbs cover spawn, durable inbox delivery and acknowledgement, interrupt, relaunch, exit, and teardown.
Failures identify the installed Polytoken version.

## Brief and doorbell delivery

On 2026-10-17, macOS arm64 with `polytoken 0.9.1`, herdr 0.9.5, and tmux 3.7c, the 0.9.1 TUI never rendered in a Herdr lab pane or a default tmux pane.
Its last write before blocking in `read()` was an OSC 52 clipboard-read probe, `ESC ] 52 ; c ; ? BEL` (inside a tmux DCS passthrough under tmux), which neither pane host answers.
The TUI log ended at `tui attached to daemon session` and `terminal lifecycle entered`, and the session `log.jsonl` held no prompt, because `new --prompt` is submitted only after the first render.
Writing a synthetic reply into the stuck pane with `tmux send-keys -H 1b 5d 35 32 3b 63 3b 07` unblocked it at once, and the TUI then submitted its `--prompt` turn.
No config key controls the probe; the binary's test-only `POLYTOKEN_TEST_CLIPBOARD_PROBE_DISABLE=1` let the same TUI render and submit normally.
The launch sets that knob only so the pane renders for watching and `/quit`; if a release removes it, delivery is unaffected and only rendered surfaces regress.

The brief and the steering doorbell therefore ride `POST /prompt` (`{"content": ...}`, answered 202 and queued behind a running turn by the daemon, per `polytoken print openapi`).
With no license acceptance record, the TUI attached to an already-running daemon and then rendered the License Agreement dialog, and it emitted no OSC 52 probe before the dialog.
While that dialog showed, the session was listed and its REST API answered, `GET /tui-attachment`, `/client-context`, `/sync/summary`, and `/state` matched a session stuck on the probe, and `polytoken doctor --format json` had no license check.
`polytoken new --no-attach` with no acceptance record printed `session_id=... port=...` and exited 0.
The only acceptance evidence is `$XDG_DATA_HOME/polytoken/license-acceptance.json`, for example `{"schema_version":1,"accepted_revision":"3"}`; no surface exposes the current revision.
So delivery requires a record naming a revision and refuses while the pane shows `License Agreement`; a revision bump with an older record on file is caught only by that rendered check.

A Herdr pane whose TUI has not rendered reads as an exited agent to Herdr's screen detection (`agent get` reports no agent), so the doorbell posts to a bound session before any pane liveness read.

The Herdr-lab proof used `bin/fm-herdr-lab.sh` for a named session, a lab `FM_HOME` with `config/backend` set to `herdr`, a scratch clone entered by a `treehouse` stand-in, and `XDG_DATA_HOME` pointing at a copy of the operator's acceptance record:

```sh
FM_HOME=<lab> HERDR_SESSION=<fm-lab-session> FM_SPAWN_NO_GUARD=1 bin/fm-spawn.sh ptherdr <scratch-project> --scout --harness polytoken --model zai/glm-5.3-flash --effort low --backend herdr
FM_HOME=<lab> HERDR_SESSION=<fm-lab-session> bin/fm-send.sh ptherdr "<acknowledge the inbox, then write steered into steer.txt>"
FM_HOME=<lab> HERDR_SESSION=<fm-lab-session> bin/fm-control.sh ptherdr exit
```

```text
spawned ptherdr harness=polytoken kind=scout window=fm-lab-fm-polytoken-han-42789-7113:w1:p2 ...
brief delivered into session 0dvfce-boxer (session log carries the FIRSTMATE_OP launch brief)
brief executed: answer.txt=80235
steer delivered and acknowledged: steer.txt=steered, handled=001.msg
pane renders the TUI (worker facet visible)
stopped ptherdr harness=polytoken backend=herdr ...
```

The same run with the knob stripped by a wrapper left the pane blank (0 nonblank rows) and still delivered the brief (`answer.txt=80235`) and the steer (`steer.txt=steered`, `handled=001.msg`).
The tmux live guard passed all ten checks on 0.9.1, including relaunch, interrupt, exit, and teardown.

## Session model proof

On 2026-10-14, macOS arm64 with `polytoken 0.9.0`, a canonical spawn used `--model zai/glm-5.3-flash --effort low`.
The daemon's `GET /state` returned this projection:

```json
{"active_model":"zai/glm-5.3-flash","active_reasoning_effort":"low","active_facet":"firstmate-worker"}
```

The retained session log recorded a model selection before the user prompt:

```json
{"index":1,"selection":{"from_model":"anthropic/claude-opus-5-5","to_model":"zai/glm-5.3-flash","reasoning_effort":"low","assignments":{},"effective_options":{},"nondefault_explicit":{},"quarantined":false,"created_seq":2}}
```

The sessions listing and `session.json` initial model still described the boot default on this binary.
They do not prove the model used after the explicit launch override.
The live guard checks the daemon state and retained selection, not just the TUI footer.
The catalog offered `low`, `high`, and `max` for `zai/glm-5.3-flash`, and `low`, `medium`, and `high` for `ogo/deepseek-v4.1-flash`.
The portable regression verifies nearest-level mapping and refusal of an unavailable catalog or unlisted base model.

## Lifecycle evidence

The same live task wrote `80235` from a shell calculation, and a real tool subprocess running `bin/fm-harness.sh` wrote `polytoken`.
The semantic record became `idle polytoken-hook stop`, and the turn-ended marker existed.
A lab watcher emitted both the task status and turn-ended marker as a signal; `bin/fm-crew-state.sh` reported `state: done` from the task's completion status.
A durable `fm-send` message was read and moved into `handled/` before interrupt verification.
`fm-control interrupt` reported `verified=agent-alive cancel=cancelled`, and the semantic record became `idle fm-interrupt interrupt`.
Relaunch bound a different session and completed the requested calculation with `493`.
Exit reported `stopped`; teardown removed task metadata and generated Polytoken artifacts.
No license or trust prompt blocked this run; the existing operator acceptance was sufficient.
That 0.9.0 run delivered the brief through `new --prompt`; the delivery section above supersedes it.

## Earlier surface evidence

The original 2026-10-07 verification used Polytoken 0.8.19.
It established that hook handlers receive event JSON and `POLYTOKEN_*` variables without handler argv, a failing hook can fail the turn, and `post_model_turn` fires between tool phases.
Those findings explain the self-contained, failure-tolerant busy writer and the use of `stop` for normal idle closure.
REST cancellation did not emit `stop`, which is why the interrupt owner closes the semantic record after the typed settle while guarding against a reopened turn.
A root `--config-dir` supplied a complete runtime config, while hook and facet discovery used the cwd's `.polytoken/` layer.
The session tree used the versioned `<root>-v1` sibling of `--sessions-dir`.
The 2026-10-14 lifecycle run exercised those same generated config, hook, facet, session discovery, and interrupt paths on the installed binary.

## Task-directory file access

On 2026-10-15, macOS arm64 with `polytoken 0.9.0`, Polytoken offered no launch-time grant that lets its file tools reach a directory outside the session's project root.
Each run below used `polytoken --config-dir <cfg> --working-dir <project> exec --model zai/glm-5.3-flash`, where `<cfg>` mirrored the operator config with `default_permission_matcher: bypass`, and read a file in a sibling directory outside `<project>`.
A direct `file_read` and `file_write` on that outside path succeeded with no rules configured.
A `tool_flow` script calling `file_read` on the same path failed with:

```text
[ToolCallError] path is outside this session's allowed paths: <outside>/in.txt. This session is anchored at <project>; file access is confined to the project root and paths the user has granted.
```

That refusal held after adding `<cfg>/permissions.yaml` with `filesystem.allow` access `[read, write]` (and, separately, `[read, write, chdir]`) for `<outside>{,/**}` or `<outside>/**`, under the `bypass`, `bypass_plus`, and `standard` matchers, and after a successful `pushd` into the directory followed by `popd`.
`polytoken doctor` with a deliberately invalid key in that file failed its permissions check, so the file was loaded in every run; under `standard` the rule did let a direct `file_read` through.
`tool_flow` refuses `file_write` outright (`tool 'file_write' is not eligible for tool_flow`).
`polytoken new --help`, `polytoken print schema app-config`, `polytoken print schema facet-frontmatter`, and `polytoken print openapi` expose no other session path grant.
The worker facet therefore tells the model to use the direct file tools or the shell for the Firstmate task directory.
