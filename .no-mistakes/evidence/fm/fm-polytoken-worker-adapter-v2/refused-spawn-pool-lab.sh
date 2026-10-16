#!/usr/bin/env bash
# Live lab: a polytoken spawn refused after it claimed a REAL Treehouse pool
# slot must leave the pool and task records as it found them, so a retry of the
# same task and a second task each land on their own slot.
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

claims() { find "$POOL" -name .fm-slot-owner -print 2>/dev/null; }
say "pool before anything (treehouse status)"; (cd "$PROJ" && "$REAL_TREEHOUSE" status 2>/dev/null)

say "1. fm-spawn pt1 --harness polytoken (project tracks .polytoken/hooks.json)"
out=$(FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-spawn.sh" pt1 "$PROJ" --mode local-only --yolo off --harness polytoken --model zai/glm-5.3-flash --effort low 2>&1); st=$?
printf '%s\nexit=%s\n' "$out" "$st"
check "refused spawn exits non-zero" '[ "$st" -ne 0 ]'
check "refusal names the project hook layer" 'case "$out" in *"not firstmate'"'"'s to clobber"*) true;; *) false;; esac'
check "refusal does not point at a window to inspect" 'case "$out" in *"inspect window"*) false;; *) true;; esac'
check "no task record published" '[ ! -e "$H/state/pt1.meta" ]'
check "tmux window fm-pt1 closed" '! "$REAL_TMUX" list-windows -a -F "#{window_name}" | grep -qx fm-pt1'
sleep 2
echo "slot claims in pool after refusal: $(claims | wc -l | tr -d " ")"
check "no slot claim left anywhere in the pool" '[ -z "$(claims)" ]'
check "treehouse reports every pool slot available (none leased or in use)" '! (cd "$PROJ" && "$REAL_TREEHOUSE" status 2>/dev/null) | grep -Eq "in-use|leased"'
check "task temp root /tmp/fm-pt1 removed" '[ ! -e /tmp/fm-pt1 ]'
REFUSED_SLOT=$(printf "%s\n" "$out" | sed -n "s|.*error: \(.*\)/.polytoken/hooks.json already exists.*|\1|p")
echo "refused spawn had acquired slot: $REFUSED_SLOT"
sleep 2
say "pool after refusal (treehouse status)"; (cd "$PROJ" && "$REAL_TREEHOUSE" status 2>/dev/null)
echo "lab tmux windows:"; "$REAL_TMUX" list-windows -a -F '#{window_name}'

say "2. retry pt1 on another harness (raw bash launch)"
out=$(FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-spawn.sh" pt1 "$PROJ" --mode local-only --yolo off --harness 'bash --noprofile --norc' 2>&1); st=$?
printf '%s\nexit=%s\n' "$out" "$st"
check "retry launches" '[ "$st" -eq 0 ]'
W1=$(awk -F= '$1=="worktree"{print substr($0,index($0,"=")+1)}' "$H/state/pt1.meta" 2>/dev/null); echo "pt1 worktree=$W1"

say "3. spawn a different task pt2 (raw bash launch)"
out=$(FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-spawn.sh" pt2 "$PROJ" --mode local-only --yolo off --harness 'bash --noprofile --norc' 2>&1); st=$?
printf '%s\nexit=%s\n' "$out" "$st"
check "second task launches" '[ "$st" -eq 0 ]'
W2=$(awk -F= '$1=="worktree"{print substr($0,index($0,"=")+1)}' "$H/state/pt2.meta" 2>/dev/null); echo "pt2 worktree=$W2"
check "retry reused the slot the refused spawn returned" '[ "$W1" = "$REFUSED_SLOT" ]'
check "the two task records name different worktrees" '[ -n "$W1" ] && [ -n "$W2" ] && [ "$W1" != "$W2" ]'
for w in "$W1" "$W2"; do echo "claim $(dirname "$w")/.fm-slot-owner:"; cat "$(dirname "$w")/.fm-slot-owner" 2>/dev/null; done
check "pt1's slot is claimed by pt1" 'grep -qx "task=pt1" "$(dirname "$W1")/.fm-slot-owner"'
check "pt2's slot is claimed by pt2" 'grep -qx "task=pt2" "$(dirname "$W2")/.fm-slot-owner"'
say "pool at end (treehouse status)"; (cd "$PROJ" && "$REAL_TREEHOUSE" status 2>/dev/null)
echo "lab tmux windows:"; "$REAL_TMUX" list-windows -a -F '#{window_name}'
say "RESULT: $fails failing checks"
exit "$fails"
