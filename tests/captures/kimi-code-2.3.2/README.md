# Kimi Code CLI 2.3.2 composer captures

These files are the visible pane of the real Kimi Code CLI 2.3.2 with model `kimi-code/k3.1-pro`, one per composer state `test_matrix_kimi_232_footer_under_the_box` in `../../fm-composer-lib.test.sh` classifies through the cursorless read every non-tmux backend performs.
They were recorded on 2026-10-25 on macOS with tmux, from `kimi -m kimi-code/k3.1-pro --auto` in a 100x30 pane of a private tmux server, logged in, in a trusted scratch git directory.

## Capture provenance

Each capture is `tmux capture-pane -p` output with trailing spaces and trailing blank rows dropped, cut to its last eleven rows, and the login name replaced by `fmuser`.

| File | State | What the pane shows |
| --- | --- | --- |
| `idle.pane` | Idle after a finished turn | The empty `│ > │` box over the two-row footer: the `Never Ask  K3.1 Pro thinking: high  …` bar and a right-aligned `context: 3% (26.4k/1M)` row |
| `typed.pane` | Pointer typed, not submitted | The pointer wrapped over three box rows |
| `newline.pane` | Pointer typed, then Enter within 120ms | The pointer plus an empty fourth box row: Kimi inserted a newline instead of submitting |
| `busy.pane` | Just after a submit | The `❯ Read the brief at` echo, a moon-phase spinner, and the empty box |
| `delivered.pane` | The turn finished | The echo, the tool call, the reply, and the empty box |

Kimi draws the same two footer rows at 60 to 220 columns; without `--auto` the bar has no permission-mode label and opens with the model name.
2.3.2 echoes a submitted message with `❯` rather than the `✨` earlier releases used.
Its editor (`packages/pi-tui/src/paste-burst.ts` in the bundled binary) treats eight or more characters arriving at most 8ms apart as a paste and turns an Enter within `PASTE_ENTER_SUPPRESS_WINDOW_MS = 120` of it into a newline, which `newline.pane` shows.

## Replay limits

The replays prove how the shared classifier reads these exact panes.
Whether the installed Kimi still renders them is the live guard's question: `tests/fm-composer-matrix-live-e2e.test.sh` with `FM_COMPOSER_MATRIX_LIVE=1`.
