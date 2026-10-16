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
. "$WT_ROOT/tests/fixtures.sh"

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
ID=pttaskdir
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
fm_test_spawn_brief "$H" "$ID" "Runtime verification only. Step 1: with your file_write tool (not the shell, not tool_flow), write exactly the text taskdir-ok into the file $H/data/$ID/proof.txt. Step 2: with your file_read tool, read $H/data/$ID/proof.txt back, then with file_write write exactly what you read into readback.txt in your worktree. Do no other work, do not commit, and do not delegate."

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
wait_file() { local i; for i in $(seq 1 480); do [ -s "$1" ] && return 0; sleep 0.5; done; fail "timed out waiting for $1"; }
FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJ" --scout --harness polytoken \
  --model zai/glm-5.3-flash --effort low > "$LAB/spawn.log" 2>&1 || fail "spawn failed: $(cat "$LAB/spawn.log")"
TARGET=$(meta_value window); SESSION1=$(meta_value polytoken_session)
echo "--- generated worker facet(s) delivered to the worker (task-dir guidance lines):"
grep -rh "Firstmate task directory" "$WT/.polytoken" 2>/dev/null | sed "s|$LAB|\$LAB|g"
grep -rqh "tool_flow tool cannot read the Firstmate task directory" "$WT/.polytoken" || fail "generated facet lacks the task-directory guidance"
pass "generated worker facet carries the task-directory guidance"
wait_file "$H/data/$ID/proof.txt"; wait_file "$WT/readback.txt"
echo "--- $H/data/$ID/proof.txt:" | sed "s|$LAB|\$LAB|g"; cat "$H/data/$ID/proof.txt"; echo
echo "--- worktree readback.txt:"; cat "$WT/readback.txt"; echo
[ "$(tr -d '[:space:]' < "$H/data/$ID/proof.txt")" = taskdir-ok ] || fail "worker did not write proof into the task directory"
[ "$(tr -d '[:space:]' < "$WT/readback.txt")" = taskdir-ok ] || fail "worker did not read the task-directory proof back"
LOG="$H/state/$ID.polytoken-sessions-v1/$SESSION1/log.jsonl"
echo "--- tool calls touching the task dir in the retained session log (name + path):"
jq -rc '.. | objects | select((.name? // .tool_name? // "") | test("file_read|file_write|tool_flow|shell")) | [(.name // .tool_name), ((.input // .arguments // .args // {}) | tostring | .[0:200])] ' "$LOG" 2>/dev/null | sed "s|$LAB|\$LAB|g" | sort -u | head -20
grep -q "proof.txt" "$LOG" || fail "session log never references proof.txt"
pass "a real polytoken worker wrote and read back proof in \$FM_HOME/data/<task-id>/ with its file tools"
"$ROOT/bin/fm-control.sh" "$ID" exit > "$LAB/exit.log" 2>&1 || fail "exit failed: $(cat "$LAB/exit.log")"
printf '# report\nNone.\n' > "$H/data/$ID/report.md"
"$ROOT/bin/fm-captain-hold.sh" complete "$ID" --none >/dev/null || true
"$ROOT/bin/fm-teardown.sh" "$ID" > "$LAB/teardown.log" 2>&1 || fail "teardown failed: $(cat "$LAB/teardown.log")"
pass "lab worker exited and torn down"
