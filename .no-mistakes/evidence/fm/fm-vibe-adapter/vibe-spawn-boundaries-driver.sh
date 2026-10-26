#!/usr/bin/env bash
# Drive fm-spawn.sh vibe refusal/accept boundaries with real vibe binary.
set -u
ROOT=$1
. "$ROOT/tests/fixtures.sh"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/vibe-bound.XXXXXX"); LAB=$(cd "$LAB" && pwd -P)
trap 'chmod -R u+w "$LAB"; rm -rf "$LAB"' EXIT
VIBE_BIN=$(command -v vibe)
PROJ="$LAB/src"; WT="$LAB/wt"
fm_git_init_commit "$PROJ"; fm_git_add_origin "$PROJ" "$LAB/origin.git"
fm_git_init_commit "$WT"; git -C "$WT" remote add origin "$LAB/origin.git"
fakebin=$(make_spawn_fakebin "$LAB/fake" claude); ln -s "$VIBE_BIN" "$fakebin/vibe"
shimbin="$LAB/shim"; mkdir -p "$shimbin"; printf '#!/bin/sh\n[ "$1" = --version ] && { echo "vibe 3.0.3"; exit 0; }\nexec %s "$@"\n' "$VIBE_BIN" > "$shimbin/vibe"; chmod +x "$shimbin/vibe"
n=0
run() { # <label> <pathprefix> args...
  local label=$1 pre=$2; shift 2; n=$((n+1))
  local H="$LAB/h$n" ID="vb$n"
  fm_test_spawn_home "$H" vibe; fm_test_spawn_brief "$H" "$ID"
  FM_FAKE_LAUNCH_LOG="$LAB/launch$n.sh" FM_HOME="$H" FM_ROOT_OVERRIDE='' \
  FM_STATE_OVERRIDE="$H/state" FM_DATA_OVERRIDE="$H/data" FM_CONFIG_OVERRIDE="$H/config" FM_PROJECTS_OVERRIDE="$H/projects" \
  FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$WT" TMUX=fake,1,0 PATH="$pre:$fakebin:$PATH" \
  "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJ" "$@" > "$LAB/out$n" 2>&1; rc=$?
  printf '=== %s\n$ fm-spawn.sh %s %s %s\nexit=%s\n' "$label" "$ID" "<proj>" "$*" "$rc"
  grep -E '^error' "$LAB/out$n" || true
  if [ -s "$LAB/launch$n.sh" ]; then echo "launch command:"; sed -E "s#$LAB#<lab>#g; s#\"\\\$\\(.*\\)\"#\"<brief>\"#" "$LAB/launch$n.sh" | tail -1 | cut -c1-600; fi
  echo
}
run 'accept: configured alias model on tmux' "" --scout --harness vibe --model zai-glm-5-3-flash --backend tmux
run 'accept: no model (Vibe default)' "" --scout --harness vibe --backend tmux
run 'refuse: unknown model pin (no silent fallback)' "" --scout --harness vibe --model mistral-does-not-exist --backend tmux
run 'refuse: provider-qualified name from another tool' "" --scout --harness vibe --model mistral/glm-5.3 --backend tmux
run 'refuse: explicit non-default effort' "" --scout --harness vibe --model zai-glm-5-3-flash --effort high --backend tmux
run 'accept: effort default' "" --scout --harness vibe --effort default --backend tmux
run 'refuse: unverified backend' "" --scout --harness vibe --backend zellij
run 'refuse: unverified vibe version 3.0.3' "$shimbin" --scout --harness vibe --backend tmux
