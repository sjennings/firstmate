#!/usr/bin/env bash
# Live lab (adversarial): a polytoken spawn refused after claiming a REAL Treehouse
# pool slot, while a concurrent retry of the same id grabs the per-id spawn lock
# at the moment the abort closes its window. The abort must still close the window
# and return the slot, but must NOT delete per-id paths (task temp root) the retry
# may be reusing. A PATH tmux shim injects the race on kill-window, then execs real tmux.
# Real: bin/fm-spawn.sh, treehouse, tmux (private socket), git. Retries use a
# raw `bash` launch so no model login is needed for the pool proof.
set -u
ROOT=${1:?worktree}
REAL_TMUX=$(command -v tmux)
REAL_TREEHOUSE=$(command -v treehouse)
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); LAB=$(cd "$LAB" && pwd -P)
H="$LAB/fm"; U="$LAB/user-home"; ORIGIN="$LAB/origin.git"; PROJ="$LAB/project"; POOL="$LAB/pool"
LAB_TMUX_DIR=
cleanup() {
  [ -e "$LAB/holder.pid" ] && kill "$(cat "$LAB/holder.pid")" 2>/dev/null
  [ -z "$LAB_TMUX_DIR" ] || { TMUX_TMPDIR="$LAB_TMUX_DIR" "$REAL_TMUX" kill-server >/dev/null 2>&1; "$ROOT/bin/fm-lab-home.sh" teardown "$H" >/dev/null 2>&1; }
  rm -rf /tmp/fm-pt1 /tmp/fm-pt2 /tmp/fm-pt1+* /tmp/fm-pt2+* 2>/dev/null
  chmod -R u+w "$LAB" 2>/dev/null; rm -rf -- "$LAB"
}
trap cleanup EXIT
say() { printf '\n=== %s\n' "$*"; }
fails=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

"$ROOT/bin/fm-lab-home.sh" create "$H" >/dev/null || exit 1
LAB_TMUX_DIR=$("$ROOT/bin/fm-lab-home.sh" tmux-dir "$H") || exit 1
mkdir -p "$H/data" "$H/projects" "$U" "$POOL"; touch "$H/state/.last-watcher-beat"
printf 'tmux\n' > "$H/config/backend"; printf 'manual\n' > "$H/config/backlog-backend"
for id in pt1 pt2; do
  mkdir -p "$H/data/$id"
  printf '# Task\n## Captain'"'"'s intent\nlab %s\n\n## Firstmate spec\nPool lab.\n' "$id" > "$H/data/$id/brief.md"
done

# Stage a copy of the operator's polytoken config (minus MCP servers) and
# license acceptance so model validation passes and the refusal under test is
# the hook-layer one that fires after the slot claim. Never modifies the source.
mkdir -p "$U/.config/polytoken" "$U/.local/share/polytoken"
awk '/^[^[:space:]#][^:]*:/ {skip=($0 ~ /^mcp_servers:/)} !skip {print}' \
  "$HOME/.config/polytoken/config.yaml" > "$U/.config/polytoken/config.yaml"
chmod 600 "$U/.config/polytoken/config.yaml"
cp "$HOME/.local/share/polytoken/license-acceptance.json" "$U/.local/share/polytoken/"
git init -q --bare "$ORIGIN"
git -c init.defaultBranch=main init -q "$PROJ"
git -C "$PROJ" -c user.name=lab -c user.email=lab@example.invalid commit -q --allow-empty -m init
mkdir -p "$PROJ/.polytoken"; printf '[]\n' > "$PROJ/.polytoken/hooks.json"
printf 'root = "%s"\n' "$POOL" > "$PROJ/treehouse.toml"
git -C "$PROJ" add -A
git -C "$PROJ" -c user.name=lab -c user.email=lab@example.invalid commit -q -m "project tracks its own .polytoken/hooks.json"
git -C "$PROJ" remote add origin "$ORIGIN"; git -C "$PROJ" push -q -u origin main

export FM_HOME="$H" HOME="$U" TMUX_TMPDIR="$LAB_TMUX_DIR" TREEHOUSE_ROOT="$POOL"
unset TMUX NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
"$REAL_TMUX" -f /dev/null new-session -d -s firstmate -n lab -x 160 -y 50 "/bin/bash --noprofile --norc"
"$REAL_TMUX" set-option -g default-command "/bin/bash --noprofile --norc" >/dev/null


SHIMBIN="$LAB/shimbin"; mkdir -p "$SHIMBIN"
cat > "$SHIMBIN/tmux" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = kill-window ] && [ ! -e '$LAB/holder.pid' ]; then
  FM_HOME='$H' nohup bash -c '. "\$1"; fm_lock_try_acquire "\$2" || exit 1; : > "\$3"; exec /bin/sleep 120' _ \\
    '$ROOT/bin/fm-wake-lib.sh' '$H/state/.spawn-pt1.lock' '$LAB/holder.ready' >/dev/null 2>&1 &
  printf '%s\n' "\$!" > '$LAB/holder.pid'
  n=0; while [ ! -e '$LAB/holder.ready' ] && [ "\$n" -lt 100 ]; do /bin/sleep 0.05; n=\$((n + 1)); done
fi
exec '$REAL_TMUX' "\$@"
SH
chmod +x "$SHIMBIN/tmux"
claims() { find "$POOL" -name .fm-slot-owner -print 2>/dev/null; }
say "1. fm-spawn pt1 --harness polytoken; a stand-in retry takes the pt1 spawn lock as the abort closes the window"
out=$(PATH="$SHIMBIN:$PATH" FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-spawn.sh" pt1 "$PROJ" --mode local-only --yolo off --harness polytoken --model zai/glm-5.3-flash --effort low 2>&1); st=$?
printf '%s\nexit=%s\n' "$out" "$st"
check "refused spawn exits non-zero" '[ "$st" -ne 0 ]'
check "stand-in retry really held the per-id spawn lock" '[ -e "$LAB/holder.ready" ]'
check "abort reports it skipped per-id cleanup under contention" 'case "$out" in *"another spawn of pt1 holds its spawn lock"*) true;; *) false;; esac'
check "task temp root /tmp/fm-pt1 left for the lock holder" '[ -d /tmp/fm-pt1 ]'
check "no task record published" '[ ! -e "$H/state/pt1.meta" ]'
check "tmux window fm-pt1 still closed" '! "$REAL_TMUX" list-windows -a -F "#{window_name}" | grep -qx fm-pt1'
sleep 2
check "slot claim still dropped" '[ -z "$(claims)" ]'
say "pool after contended refusal (treehouse status)"; (cd "$PROJ" && "$REAL_TREEHOUSE" status 2>/dev/null)
check "treehouse reports the slot returned" '! (cd "$PROJ" && "$REAL_TREEHOUSE" status 2>/dev/null) | grep -Eq "in-use|leased"'
kill "$(cat "$LAB/holder.pid")" 2>/dev/null; sleep 0.5
say "2. after the holder exits, retry pt1 on raw bash"
out=$(FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-spawn.sh" pt1 "$PROJ" --mode local-only --yolo off --harness 'bash --noprofile --norc' 2>&1); st=$?
printf '%s\nexit=%s\n' "$out" "$st"
check "retry launches" '[ "$st" -eq 0 ]'
check "retry record exists" '[ -e "$H/state/pt1.meta" ]'
say "pool at end"; (cd "$PROJ" && "$REAL_TREEHOUSE" status 2>/dev/null)
say "RESULT: $fails failing checks"
exit "$fails"
