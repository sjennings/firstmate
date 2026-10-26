#!/usr/bin/env bash
# Live Herdr lab: real Vibe 3.0.2 in a guarded fm-lab-* session; production
# fm_backend_herdr_pane_agent_state classifies it live while running and
# no-agent after /exit, and non-Vibe metas keep Herdr's catalog semantics.
set -u
ROOT=$1
H=$ROOT/bin/fm-herdr-lab.sh
fail() { printf 'not ok - %s\n' "$1"; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
REAL_HERDR=$(command -v herdr); ORIG_PATH=$PATH
T=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/vibe-herdr.XXXXXX")
mkdir -p "$T/fakebin" "$T/home/state" "$T/proj" "$T/vibe-sessions"
git -C "$T/proj" init -q; git -C "$T/proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
S=$("$H" name vibe-adapter)
export HERDR_LAB_HELPER=$H HERDR_LAB_SESSION=$S REAL_HERDR HERDR_ORIGINAL_PATH=$ORIG_PATH
cleanup() { local st=$?; env PATH="$ORIG_PATH" "$H" teardown "$S" && echo "lab teardown ok (default-session tripwire unchanged)" || st=1; chmod -R u+w "$T"; rm -rf "$T"; exit $st; }
trap cleanup EXIT
"$H" provision "$S" >/dev/null || fail provision
cat > "$T/fakebin/herdr" <<'SH'
#!/usr/bin/env bash
set -u
args=("$@"); last=$((${#args[@]} - 1)); flag=$((last - 1))
if [ "${#args[@]}" -ge 2 ] && [ "${args[$flag]}" = --session ] && [ "${args[$last]}" = "$HERDR_LAB_SESSION" ]; then unset "args[$last]" "args[$flag]"; fi
set -- "${args[@]}"
for a in "$@"; do case "$a" in --session|--session=*) exit 9 ;; esac; done
[ "${1:-}" = --version ] && exec env PATH="$HERDR_ORIGINAL_PATH" "$REAL_HERDR" "$@" --session "$HERDR_LAB_SESSION"
exec env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" "$@"
SH
chmod +x "$T/fakebin/herdr"
screen() { lab pane read "$P" --source visible --format text 2>/dev/null | { out=$(cat); printf "%s" "$out" | jq -er ".result.text // empty" 2>/dev/null || printf "%s\n" "$out"; }; }
lab() { env PATH="$ORIG_PATH" "$H" run "$S" "$@"; }
W=$(lab workspace create --cwd "$T/proj" --label vibe-worker --no-focus) || fail 'workspace create'
P=$(printf '%s' "$W" | jq -r '.result.root_pane.pane_id')
echo "lab session=$S pane=$P"
state() { # <harness>
  printf 'backend=herdr\nwindow=%s:%s\nharness=%s\n' "$S" "$P" "$1" > "$T/home/state/task.meta"
  FM_HOME="$T/home" STATE="$T/home/state" PATH="$T/fakebin:$ORIG_PATH" bash -c '. "$1/bin/fm-backend.sh"; . "$1/bin/backends/herdr.sh"; fm_backend_herdr_pane_agent_state "$2" "$3"' _ "$ROOT" "$S" "$P"
}
waitstate() { local h=$1 want=$2 i=0 v; while [ $i -lt 150 ]; do v=$(state "$h"); [ "$v" = "$want" ] && { echo "$v"; return 0; }; sleep 0.4; i=$((i+1)); done; echo "$v"; return 1; }
sleep 1
v=$(waitstate vibe no-agent) || fail "idle shell recorded as vibe should be no-agent, got $v"; pass "shell-only pane recorded harness=vibe -> $v"
cmd="VIBE_SESSION_LOGGING__SAVE_DIR='$T/vibe-sessions' VIBE_ACTIVE_MODEL=zai-glm-5-3-flash vibe --trust --auto-approve -- 'Reply exactly HERDR_VIBE_OK and do no other work.'"
lab pane send-text "$P" "$cmd" >/dev/null && lab pane send-keys "$P" Enter >/dev/null || fail 'send launch'
i=0; until screen | grep -q '^ *HERDR_VIBE_OK *$'; do i=$((i+1)); [ $i -gt 300 ] && { screen | tail -20; fail 'no Vibe reply'; }; sleep 0.4; done
pass 'real Vibe replied HERDR_VIBE_OK inside the lab pane'
lab pane process-info "$P" | jq -c '[.result.foreground_processes[]?.name // empty] // .result' 2>/dev/null | sed 's/^/  pane process-info foreground: /'
ag=$(lab agent get "$P" 2>&1); printf '  herdr agent get: %s\n' "$(printf '%s' "$ag" | jq -c '.error.code // .result.agent.agent_status' 2>/dev/null || echo "$ag")"
v=$(state vibe); [ "$v" = live ] || fail "running Vibe recorded harness=vibe should be live, got $v"; pass "running Vibe, recorded harness=vibe -> $v"
v=$(state claude); echo "  same pane recorded harness=claude -> $v (Herdr catalog semantics unchanged for other harnesses)"
[ "$v" = no-agent ] || fail "non-vibe harness semantics changed: $v"
pass 'non-Vibe recorded harness keeps agent_not_found -> no-agent'
lab pane send-text "$P" "/exit" >/dev/null && lab pane send-keys "$P" Enter >/dev/null
v=$(waitstate vibe no-agent) || fail "after /exit expected no-agent, got $v"; pass "after /exit, recorded harness=vibe -> $v"
