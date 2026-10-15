#!/usr/bin/env bash
# Credentialed Polytoken worker guard. Opt in with FM_POLYTOKEN_SIGNALS_LIVE=1.
# Drives the real Firstmate verbs end to end in a private tmux server: the
# launch is bin/fm-spawn.sh's generated polytoken command (so a broken launch
# template fails here), the steer is bin/fm-send.sh, the interrupt, relaunch,
# and exit are bin/fm-control.sh, and liveness is the tmux backend's own
# agent-state read. Only worktree allocation uses a fixture (a `treehouse`
# stand-in that enters a prepared worktree). Also proves `polytoken print
# models` discovery, detection from a real tool subprocess, and the hook-driven
# busy open/close on real turns. Runs the cheap zai/glm-5.3-flash model at low
# effort, per the adapter's verification plan.
set -u

# shellcheck source=tests/fixtures.sh
. "/Users/wire2k/.no-mistakes/worktrees/306eb1dde12e/01M4YDAN9CAV47ZF3SVMVFSDJA/tests/fixtures.sh"

fm_live_gate opt-in FM_POLYTOKEN_SIGNALS_LIVE polytoken tmux jq curl git

# shellcheck source=bin/fm-polytoken-lib.sh
. "$ROOT/bin/fm-polytoken-lib.sh"
# shellcheck source=bin/fm-busy-lib.sh
. "$ROOT/bin/fm-busy-lib.sh"
# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"
# shellcheck source=bin/fm-composer-lib.sh
. "$ROOT/bin/fm-composer-lib.sh"

POLYTOKEN_BIN=$(fm_polytoken_binary 2>/dev/null) || POLYTOKEN_BIN=
[ -n "$POLYTOKEN_BIN" ] || fail "polytoken is not installed"
VERSION=$("$POLYTOKEN_BIN" --version 2>/dev/null || echo unknown)
REAL_TMUX=$(command -v tmux)
LAB_HOME_HELPER="$ROOT/bin/fm-lab-home.sh"
LAB_TMUX_DIR=
ID=ptrefuse
LAB=

cleanup() {
  local meta sid
  if [ -n "$LAB" ]; then
    meta="$LAB/fm/state/$ID.meta"
    sid=$(awk -F= '$1 == "polytoken_session" { v = substr($0, index($0, "=") + 1) } END { print v }' "$meta" 2>/dev/null)
    if [ -n "$sid" ]; then
      HOME="$LAB/user-home" "$POLYTOKEN_BIN" --config-dir "$LAB/fm/state/$ID.polytoken-config" \
        reap "$sid" --force --sessions-dir "$LAB/fm/state/$ID.polytoken-sessions" >/dev/null 2>&1 || true
    fi
  fi
  if [ -n "$LAB_TMUX_DIR" ]; then
    TMUX_TMPDIR="$LAB_TMUX_DIR" "$REAL_TMUX" kill-server >/dev/null 2>&1 || true
    "$LAB_HOME_HELPER" teardown "$LAB/fm" || exit 1
  fi
  [ -z "$LAB" ] || { chmod -R u+w "$LAB" 2>/dev/null; rm -rf -- "$LAB"; }
}

fail() {
  printf 'not ok - %s: %s\n' "$VERSION" "$1" >&2
  exit 1
}

# Model discovery is part of the verified surface: the guard launches on the
# cheap model's low-effort reference, which a live catalog must still list as
# a selectable form (the exact validation fm-spawn performs at intake).
discovered_ref=$(fm_polytoken_model_ref "$POLYTOKEN_BIN" zai/glm-5.3-flash low 2>/dev/null)
[ "$discovered_ref" = 'zai/glm-5.3-flash(low)' ] \
  || fail "'polytoken print models' no longer lists zai/glm-5.3-flash(low) (got '${discovered_ref:-none}')"
pass "$VERSION: the live model catalog still lists the cheap low-effort reference"

GLOBAL_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/polytoken/config.yaml"
LICENSE_ACCEPT="${XDG_DATA_HOME:-$HOME/.local/share}/polytoken/license-acceptance.json"
[ -f "$GLOBAL_CFG" ] || fail "no global polytoken config at $GLOBAL_CFG to stage for the lab"
# The license acceptance the operator already granted lives in the data home
# keyed by revision. This lab isolates HOME, so the operator's existing record
# is staged as a copy - never extended, and never answered by pressing the
# dialog - because a lab without it would park on exactly the blocker the
# fleet treats as blocked.
[ -f "$LICENSE_ACCEPT" ] \
  || fail "no operator license acceptance at $LICENSE_ACCEPT; the fleet itself would be blocked on the first-start dialog, and the guard refuses to accept anything on the operator's behalf"

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-polytoken-signals.XXXXXX") || fail "could not create the isolated polytoken lab"
LAB=$(cd "$LAB" && pwd -P)
trap cleanup EXIT

H="$LAB/fm"
U="$LAB/user-home"
PROJ="$LAB/project"
WT="$LAB/wt"
"$LAB_HOME_HELPER" create "$H" >/dev/null || fail "could not mark the lab home"
LAB_TMUX_DIR=$("$LAB_HOME_HELPER" tmux-dir "$H") || fail "could not isolate tmux"
export TMUX_TMPDIR="$LAB_TMUX_DIR"
fm_test_spawn_home "$H" polytoken
printf 'tmux\n' > "$H/config/backend"
printf 'manual\n' > "$H/config/backlog-backend"
fm_git_init_commit "$PROJ"
git clone -q "$PROJ" "$WT" || fail "could not prepare the scratch clone"
git -C "$WT" checkout -qb polytoken-live || fail "could not branch the scratch clone"
mkdir -p "$U/.config/polytoken" "$U/.local/share/polytoken" "$LAB/bin"
# Keep provider/model configuration, but do not start operator MCP services
# from a disposable lab (those services may write outside the isolated HOME).
awk '/^[^[:space:]#][^:]*:/ {skip=($0 ~ /^mcp_servers:/)} !skip {print}' \
  "$GLOBAL_CFG" > "$U/.config/polytoken/config.yaml" || fail "could not stage the polytoken config copy"
chmod 600 "$U/.config/polytoken/config.yaml"
cp "$LICENSE_ACCEPT" "$U/.local/share/polytoken/license-acceptance.json" \
  || fail "could not stage the operator license acceptance copy"
fm_test_spawn_brief "$H" "$ID" "Runtime verification only: compute 12345 plus 67890 using your shell tool and write only the result into answer.txt. Then use your shell tool to run 'bash $ROOT/bin/fm-harness.sh' and write its output to harness.txt. Do no other work, do not commit, and do not delegate."

# Every backend read and write lands on this guard's private server, and the
# pane's `treehouse get` enters the prepared worktree in a subshell exactly as
# the real tool does.
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_TMUX" > "$LAB/bin/tmux"
# shellcheck disable=SC2016 # the single-quoted shim expands its own argument
printf '#!/bin/sh\n[ "${1:-}" = get ] || exit 0\ncd "%s" && exec /bin/bash --noprofile --norc\n' "$WT" > "$LAB/bin/treehouse"
chmod +x "$LAB/bin/tmux" "$LAB/bin/treehouse"
export PATH="$LAB/bin:$PATH" FM_HOME="$H" HOME="$U" XDG_CONFIG_HOME="$U/.config" XDG_DATA_HOME="$U/.local/share" XDG_STATE_HOME="$U/.local/state" XDG_CACHE_HOME="$U/.cache"
unset TMUX FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
tmux -f /dev/null new-session -d -s firstmate -n lab -x 160 -y 50 "/bin/bash --noprofile --norc" \
  || fail "could not start the isolated tmux server"
tmux set-option -g default-command "/bin/bash --noprofile --norc" >/dev/null \
  || fail "could not pin the lab shell"

META="$H/state/$ID.meta"
meta_value() { awk -F= -v k="$1" '$1 == k { v = substr($0, index($0, "=") + 1) } END { print v }' "$META"; }
record() { fm_busy_record_read "$H/state" "$ID" 2>/dev/null || true; }
wait_file() {
  local path=$1 i
  for i in $(seq 1 480); do [ -s "$path" ] && return 0; sleep 0.5; done
  fail "timed out waiting for ${path##*/}"
}
wait_record() {  # <prefix> <what>
  local i
  for i in $(seq 1 240); do
    case "$(record)" in "$1"*) return 0 ;; esac
    sleep 0.5
  done
  fail "$2 (last record '$(record)')"
}

# The launch is fm-spawn's own generated command; its readiness gate already
# requires the session to surface in `polytoken sessions` and a hook-written
# busy record before the spawn reports success.
FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJ" --scout --harness polytoken \
  --model zai/glm-5.3-flash --effort low > "$LAB/spawn.log" 2>&1 \
  || fail "fm-spawn's generated polytoken launch failed: $(cat "$LAB/spawn.log")"
TARGET=$(meta_value window)
SESSION1=$(meta_value polytoken_session)
[ -n "$TARGET" ] || fail "the spawn recorded no endpoint"
[ -n "$SESSION1" ] && [ -n "$(meta_value polytoken_port)" ] && [ -n "$(meta_value polytoken_credential)" ] \
  || fail "the spawn did not bind the session id, port, and credential into task metadata"
capture() { tmux capture-pane -p -t "$TARGET" -S -200 2>/dev/null || true; }
[ "$(fm_backend_agent_state tmux "$TARGET")" = alive ] \
  || fail "the tmux backend does not classify the spawned polytoken worker alive"
screen=$(capture)
case "$screen" in *firstmate-worker*) ;; *) fail "the spawned pane never showed the generated worker facet" ;; esac
case "$screen" in *"perms: bypass"*) ;; *) fail "the spawned pane never rendered the enforced bypass posture" ;; esac
# Session listing model is the boot default on some binaries. The retained
# selection event and daemon state prove the effective pin before inference.
TOKEN=$(fm_polytoken_credential_token "$(meta_value polytoken_credential)") || fail "cannot read lab credential"
state=$(fm_polytoken_rest_json GET "$(meta_value polytoken_port)" "$TOKEN" /state) || fail "cannot read daemon state"
printf '%s' "$state" | jq -e '.active_model == "zai/glm-5.3-flash" and .active_reasoning_effort == "low"' >/dev/null \
  || fail "daemon state does not match the model and effort pin"
selection="$H/state/$ID.polytoken-sessions-v1/$SESSION1/log.jsonl"
jq -se 'any(.[]; .message.selection.to_model == "zai/glm-5.3-flash" and .message.selection.reasoning_effort == "low")' "$selection" >/dev/null \
  || fail "retained session has no matching model selection"
pass "$VERSION: generated launch starts a bound worker; daemon state and retained selection prove the model and effort pin"

wait_file "$WT/answer.txt"
wait_file "$WT/harness.txt"
[ "$(tr -d '[:space:]' < "$WT/answer.txt")" = 80235 ] || fail "the launch brief did not execute"
[ "$(tr -d '[:space:]' < "$WT/harness.txt")" = polytoken ] \
  || fail "fm-harness.sh did not detect polytoken from a real tool subprocess (got '$(cat "$WT/harness.txt")')"
pass "$VERSION: the brief ran and fm-harness.sh detects polytoken from a real tool subprocess"
wait_record "idle polytoken-hook " "the finished brief turn never closed the busy record through the stop hook"
[ -f "$H/state/$ID.turn-ended" ] || fail "the stop hook never touched the turn-ended marker"
pass "$VERSION: the stop hook closes the busy record and touches the turn-ended marker"

# ---- Adversarial: refused relaunch profiles must leave the running worker untouched ----
PORT1=$(meta_value polytoken_port)
daemon_state() { fm_polytoken_rest_json GET "$(meta_value polytoken_port)" "$(fm_polytoken_credential_token "$(meta_value polytoken_credential)")" /state; }
snapshot() {
  printf 'session=%s port=%s harness=%s model=%s effort=%s pane_pid=%s state=%s\n' \
    "$(meta_value polytoken_session)" "$(meta_value polytoken_port)" "$(meta_value harness)" \
    "$(meta_value model)" "$(meta_value effort)" \
    "$(tmux display-message -p -t "$TARGET" '#{pane_pid}')" "$(fm_backend_agent_state tmux "$TARGET")"
}
BEFORE=$(snapshot); echo "before: $BEFORE"
attempt() {  # <label> <expected refusal substring> <relaunch args...>
  local label=$1 want=$2 out rc after st; shift 2
  out=$("$ROOT/bin/fm-control.sh" "$ID" relaunch "$@" 2>&1); rc=$?
  echo "--- $label: fm-control $ID relaunch $* -> rc=$rc"; echo "$out"
  [ "$rc" -ne 0 ] || fail "$label: relaunch was not refused"
  case "$out" in *"$want"*) ;; *) fail "$label: refusal did not name '$want'" ;; esac
  after=$(snapshot); echo "after:  $after"
  [ "$after" = "$BEFORE" ] || fail "$label: worker/session/record changed (before '$BEFORE' after '$after')"
  [ "$(meta_value polytoken_port)" = "$PORT1" ] || fail "$label: port moved"
  st=$(daemon_state) || fail "$label: daemon REST no longer answers"
  printf '%s' "$st" | jq -e '.active_model == "zai/glm-5.3-flash" and .active_reasoning_effort == "low"' >/dev/null \
    || fail "$label: daemon profile changed"
  echo "daemon: $(printf '%s' "$st" | jq -c '{active_model,active_reasoning_effort,active_facet}')"
  pass "$VERSION: $label refused before stop; same pane, session, daemon, and record"
}
attempt "default effort" "requires concrete --model and --effort" --effort default --note 'refusal probe'
attempt "default model" "requires concrete --model and --effort" --model default --note 'refusal probe'
attempt "unlisted model" "is not listed by 'polytoken print models'" --model zai/not-a-real-model --effort low --note 'refusal probe'
attempt "parenthesized model ref" "polytoken" --model "zai/glm-5.3-flash(low)" --effort low --note "refusal probe"
screen=$(capture); case "$screen" in *firstmate-worker*) ;; *) fail "worker pane no longer shows the worker facet" ;; esac
echo "=== pane after refusals ==="; tmux capture-pane -p -t "$TARGET" -S -40

"$ROOT/bin/fm-control.sh" "$ID" relaunch --effort high \
  --note 'Runtime relaunch verification: compute 6 times 7 with your shell tool and write only the result to ok.txt. Do no other work.' \
  > "$LAB/relaunch.log" 2>&1 || fail "valid relaunch failed: $(cat "$LAB/relaunch.log")"
SESSION2=$(meta_value polytoken_session)
[ -n "$SESSION2" ] && [ "$SESSION2" != "$SESSION1" ] || fail "valid relaunch did not rebind a session"
[ "$(meta_value effort)" = high ] || fail "valid relaunch did not record effort high"
wait_file "$WT/ok.txt"; [ "$(tr -d '[:space:]' < "$WT/ok.txt")" = 42 ] || fail "relaunched worker did not act"
st=$(daemon_state)
echo "relaunched daemon: $(printf '%s' "$st" | jq -c '{active_model,active_reasoning_effort}')"
printf '%s' "$st" | jq -e '.active_reasoning_effort == "high"' >/dev/null || fail "relaunch effort not pinned"
pass "$VERSION: a valid relaunch after the refusals rebinds a fresh session with the requested effort"

wait_record "idle polytoken-hook " "relaunched turn never closed"
"$ROOT/bin/fm-control.sh" "$ID" exit > "$LAB/exit.log" 2>&1 || fail "exit failed"
printf '# probe report\nNo unresolved decisions.\n' > "$H/data/$ID/report.md"
"$ROOT/bin/fm-captain-hold.sh" complete "$ID" --none >/dev/null || fail "hold complete failed"
"$ROOT/bin/fm-teardown.sh" "$ID" > "$LAB/teardown.log" 2>&1 || fail "teardown failed: $(cat "$LAB/teardown.log")"
pass "$VERSION: probe worker exited and torn down"
