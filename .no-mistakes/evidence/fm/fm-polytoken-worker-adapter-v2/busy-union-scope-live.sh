#!/usr/bin/env bash
# Live: a real tmux pane rendering Polytoken's "Running for <n>s" footer is busy
# only under the polytoken harness; the harness-less union (used for every
# other pane) still reads it idle, and main's union line is byte-identical.
set -u
ROOT=${1:?worktree}; cd "$ROOT"
D=$(mktemp -d "${TMPDIR:-/tmp}/fm-busy.XXXXXX"); export TMUX_TMPDIR="$D"; unset TMUX
trap 'tmux kill-server >/dev/null 2>&1; rm -rf "$D"' EXIT
echo "union line main vs head:"; diff <(git show ce697402:bin/fm-composer-lib.sh | grep '^FM_DELIVERY_BUSY_REGEX_DEFAULT=') <(grep '^FM_DELIVERY_BUSY_REGEX_DEFAULT=' bin/fm-composer-lib.sh) && echo "  identical"
tmux -f /dev/null new-session -d -s lab -x 120 -y 30 "printf '  ⠋ thinking\n  Running for 3.03s\n'; exec sleep 600"
sleep 1
echo "pane:"; tmux capture-pane -p -t lab | sed '/^$/d'
. bin/fm-backend.sh 2>/dev/null; . bin/fm-composer-lib.sh; . bin/fm-tmux-lib.sh
echo "harness-less fm_pane_busy_state: $(fm_pane_busy_state lab:0.0)"
echo "polytoken    fm_pane_busy_state: $(fm_pane_busy_state lab:0.0 polytoken)"
echo "claude       fm_pane_busy_state: $(fm_pane_busy_state lab:0.0 claude)"
