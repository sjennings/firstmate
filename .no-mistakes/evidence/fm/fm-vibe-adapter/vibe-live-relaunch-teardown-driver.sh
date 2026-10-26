#!/usr/bin/env bash
# Live: real Vibe worker relaunch keeps journal generations; real fm-teardown removes them incl. read-only plugin cache.
set -eu
ROOT=$1
. "$ROOT/tests/fixtures.sh"
VIBE_BIN=$(command -v vibe); MODEL=zai-glm-5-3-flash
LAB=$(mktemp -d "${TMPDIR:-/tmp}/vibe-td.XXXXXX"); LAB=$(cd "$LAB" && pwd -P); H="$LAB/home"; SOCKET_DIR=
cleanup() { [ -n "$SOCKET_DIR" ] && { TMUX_TMPDIR="$SOCKET_DIR" tmux kill-server >/dev/null 2>&1 || true; "$ROOT/bin/fm-lab-home.sh" teardown "$H" || true; }; chmod -R u+w "$LAB" 2>/dev/null || true; rm -rf "$LAB"; }
trap cleanup EXIT
"$ROOT/bin/fm-lab-home.sh" create "$H" >/dev/null
SOCKET_DIR=$("$ROOT/bin/fm-lab-home.sh" tmux-dir "$H"); export TMUX_TMPDIR="$SOCKET_DIR"; unset TMUX
ID=vibe-td; WT="$LAB/worker-project"; PROJ="$LAB/source-project"
fm_git_init_commit "$PROJ"; fm_git_add_origin "$PROJ" "$LAB/origin.git"
fm_git_init_commit "$WT"; git -C "$WT" remote add origin "$LAB/origin.git"
fm_test_spawn_home "$H" vibe
fm_test_spawn_brief "$H" "$ID" "Runtime verification only. Reply exactly VIBE_TD_READY and do no other work."
fakebin=$(make_spawn_fakebin "$LAB/fake" claude); ln -s "$VIBE_BIN" "$fakebin/vibe"
FM_FAKE_LAUNCH_LOG="$LAB/launch.sh" FM_HOME="$H" FM_ROOT_OVERRIDE='' \
  FM_STATE_OVERRIDE="$H/state" FM_DATA_OVERRIDE="$H/data" FM_CONFIG_OVERRIDE="$H/config" FM_PROJECTS_OVERRIDE="$H/projects" \
  FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$WT" TMUX=fake,1,0 PATH="$fakebin:$PATH" \
  "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJ" --scout --harness vibe --model "$MODEL" --backend tmux > "$LAB/spawn.log" 2>&1
export FM_HOME="$H"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE HERDR_SOCKET_PATH HERDR_PANE_ID
TARGET="firstmate:fm-$ID"
tmux new-session -d -s firstmate -n "fm-$ID" -c "$WT" -x 120 -y 40
. "$ROOT/bin/fm-backend.sh"
agent() { fm_backend_agent_state tmux "$TARGET"; }
wait_for() { local d=$((SECONDS+120)) v=; while [ $SECONDS -lt $d ]; do v=$("$@" 2>/dev/null) || v=; [ "$v" = yes ] && return 0; sleep 0.3; done; echo "TIMEOUT $*"; tmux capture-pane -p -t "$TARGET"; exit 1; }
seen() { tmux capture-pane -p -t "$TARGET" | grep -Eq "^[[:space:]]*$1[[:space:]]*$" && echo yes; }
isdead() { [ "$(agent)" = dead ] && echo yes; }
tmux send-keys -t "$TARGET" "bash '$LAB/launch.sh'" Enter
wait_for seen VIBE_TD_READY
echo "== gen1 reply seen; exiting"
"$ROOT/bin/fm-control.sh" "$ID" exit >/dev/null; wait_for isdead
"$ROOT/bin/fm-control.sh" "$ID" relaunch --note 'Runtime verification only: reply exactly VIBE_TD_RELAUNCH and do no other work.' >/dev/null
wait_for seen VIBE_TD_RELAUNCH
"$ROOT/bin/fm-control.sh" "$ID" exit >/dev/null; wait_for isdead
S="$H/state/$ID.vibe-sessions"
echo "== after relaunch: generation dirs in state/$ID.vibe-sessions"; ls -1 "$S"
echo "generations=$(ls -1 "$S" | wc -l | tr -d ' ')"
echo "session journal files=$(find "$S" -type f -name '*.json*' | wc -l | tr -d ' ')"
echo "read-only entries (no owner write)=$(find "$S" ! -perm -u+w | wc -l | tr -d ' ')"
echo "== plain rm -rf on a copy (proves the read-only cache needs chmod):"
cp -Rp "$S" "$LAB/copy"; rm -rf "$LAB/copy" 2>&1 | head -2; [ -e "$LAB/copy" ] && echo "plain rm left copy behind" || echo "plain rm succeeded"
mkdir -p "$H/data/$ID"; printf '# Report\nRuntime verification.\n' > "$H/data/$ID/report.md"
echo "== fm-teardown.sh $ID --force"
set +e; PATH="$fakebin:$PATH" "$ROOT/bin/fm-teardown.sh" "$ID" --force > "$LAB/td.log" 2>&1; rc=$?; set -e
echo "teardown exit=$rc"; sed "s#$LAB#<lab>#g" "$LAB/td.log" | tail -8
[ -e "$S" ] && { echo "FAIL: $S still present"; find "$S" | head; exit 1; } || echo "PASS: state/$ID.vibe-sessions removed by teardown"
