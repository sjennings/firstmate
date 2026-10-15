#!/usr/bin/env bash
# Live probe: a real Claude scout spawned by fm-spawn in a marked lab FM_HOME
# on a private tmux server; `fm-control relaunch --harness polytoken` with no
# --model/--effort (the reviewed repro) must refuse BEFORE the Claude worker is
# stopped. Polytoken is never invoked on this path, so no Polytoken store is
# touched; Claude keeps the operator's existing login (HOME is not changed).
set -u
: "${ROOT:?set ROOT to the gate worktree}"
. "$ROOT/tests/fixtures.sh"
. "$ROOT/bin/fm-backend.sh"
REAL_TMUX=$(command -v tmux)
ID=clswitch
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); LAB=$(cd "$LAB" && pwd -P)
H="$LAB/fm"; PROJ="$LAB/project"; WT="$LAB/wt"; LAB_TMUX_DIR=
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
cleanup() {
  [ -z "$LAB_TMUX_DIR" ] || { TMUX_TMPDIR="$LAB_TMUX_DIR" "$REAL_TMUX" kill-server >/dev/null 2>&1 || true; "$ROOT/bin/fm-lab-home.sh" teardown "$H" || true; }
  chmod -R u+w "$LAB" 2>/dev/null; rm -rf -- "$LAB"
}
trap cleanup EXIT
"$ROOT/bin/fm-lab-home.sh" create "$H" >/dev/null || fail "lab home"
LAB_TMUX_DIR=$("$ROOT/bin/fm-lab-home.sh" tmux-dir "$H") || fail "lab tmux"
export TMUX_TMPDIR="$LAB_TMUX_DIR"
fm_test_spawn_home "$H" claude
printf 'tmux\n' > "$H/config/backend"; printf 'manual\n' > "$H/config/backlog-backend"
fm_git_init_commit "$PROJ"; git -C "$PROJ" worktree add -q -b claude-live "$WT"
mkdir -p "$LAB/bin"
fm_test_spawn_brief "$H" "$ID" "Runtime verification only: write the word ready into ready.txt using your shell tool, then stop. Do no other work, do not commit."
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_TMUX" > "$LAB/bin/tmux"
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ "${1:-}" = get ] || exit 0\ncd "%s" && exec /bin/bash --noprofile --norc\n' "$WT" > "$LAB/bin/treehouse"
chmod +x "$LAB/bin/tmux" "$LAB/bin/treehouse"
export PATH="$LAB/bin:$PATH" FM_HOME="$H"
unset TMUX FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
tmux -f /dev/null new-session -d -s firstmate -n lab -x 160 -y 50 "/bin/bash --noprofile --norc" || fail "tmux"
tmux set-option -g default-command "/bin/bash --noprofile --norc" >/dev/null
META="$H/state/$ID.meta"
meta_value() { awk -F= -v k="$1" '$1 == k { v = substr($0, index($0, "=") + 1) } END { print v }' "$META"; }

FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJ" --scout --harness claude --model haiku --effort low \
  > "$LAB/spawn.log" 2>&1 || fail "claude spawn failed: $(cat "$LAB/spawn.log")"
TARGET=$(meta_value window)
for _ in $(seq 1 240); do [ -s "$WT/ready.txt" ] && break; sleep 0.5; done
[ -s "$WT/ready.txt" ] || fail "claude worker never acted on its brief"
echo "ok - real claude scout spawned via fm-spawn and acted (ready.txt written)"
snap() { printf 'harness=%s model=%s effort=%s pane_pid=%s pane_cmd=%s state=%s\n' "$(meta_value harness)" "$(meta_value model)" "$(meta_value effort)" \
  "$(tmux display-message -p -t "$TARGET" '#{pane_pid}')" "$(tmux display-message -p -t "$TARGET" '#{pane_current_command}')" "$(fm_backend_agent_state tmux "$TARGET")"; }
BEFORE=$(snap); echo "before: $BEFORE"
out=$("$ROOT/bin/fm-control.sh" "$ID" relaunch --harness polytoken --note 'switching runtime' 2>&1); rc=$?
echo "--- fm-control $ID relaunch --harness polytoken --note 'switching runtime' -> rc=$rc"; echo "$out"
[ "$rc" -ne 0 ] || fail "switch onto polytoken with default axes was not refused"
case "$out" in *"requires concrete --model and --effort"*) ;; *) fail "refusal did not name the missing profile" ;; esac
sleep 2
AFTER=$(snap); echo "after:  $AFTER"
[ "$AFTER" = "$BEFORE" ] || fail "claude worker or record changed"
[ "$(fm_backend_agent_state tmux "$TARGET")" = alive ] || fail "claude worker was stopped"
[ ! -e "$WT/.polytoken" ] || fail "polytoken wiring was written"
echo "=== claude pane after refused switch ==="; tmux capture-pane -p -t "$TARGET" -S -25
echo "ok - refused claude->polytoken switch left the real claude worker running, record unchanged, no polytoken wiring"
"$ROOT/bin/fm-control.sh" "$ID" exit > "$LAB/exit.log" 2>&1 || fail "exit failed: $(cat "$LAB/exit.log")"
[ "$(fm_backend_agent_state tmux "$TARGET")" = dead ] || fail "exit did not stop claude"
echo "ok - lab claude worker exited; lab torn down on exit"
