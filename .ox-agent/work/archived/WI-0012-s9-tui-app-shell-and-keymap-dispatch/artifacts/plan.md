# WI-0012 plan — S9 TUI app shell and keymap dispatch

Spec: `artifacts/spec.md` (canonical keymap table + deviations).
Architecture: ADR-0028. TDD: red tests first per stage; `oxl test`
runs per leaf dir (oxl#131 — loop `core/term` then `tui`).

## S9.1 — Input decoder (`core/term/decode.oxl` + tests)

Red: `decode_test.oxl` cases per grammar class — runes/UTF-8, C0
ctrl bytes (0x0D enter, 0x0A ctrl+j, 0x08 backspace, 0x01–0x1A
ctrl+letter, 0x03 ctrl+c), CSI arrows/`~`-keys/`;mod` params, SS3
f1..f4/arrows, kitty CSI-u (ctrl+shift+v/s/z), SGR mouse
(press/release/scroll, coords→0-based), ESC-prefix alt, partial-
tail buffering (feed split mid-CSI), lone-ESC→escape, upper-rune
shift inference. Green: `struct Decoder{tail: []byte}` +
`feed()->[]KeyEvent`.
Gate: `oxl test core/term` green incl. existing S8 tests.

## S9.2 — Session enablement (`core/term/ansi.oxl` + tests)

Write mouse 1002/1006 + kitty `>1u` at `open_session`; emit
`\x1b[?1002l\x1b[?1006l\x1b[<u` in `close` before alt-screen leave.
Test: capture close-stream bytes via a wrap seam — factor the
teardown string into a `fn close_seq() -> str` unit-tested
constant; open seq likewise (`open_seq()`), asserted in tests.
Gate: build + tests green; manual tty check deferred to S9.6 smoke.

## S9.3 — Keymap tables + dispatch skeleton (`tui/`)

Red: `keymap_test.oxl` — tables contain all 18 rebindable ids w/
corpus default keys (19 keys; keep-tab unbound), 4 fixed globals;
`dispatch` precedence: modal > widget > global > fixed;
ctrl+h/backspace collision rule; expand-section in both global and
req/resp widget tables; every table row → `I|P|D` outcome string.
Green: `tui/keymap.oxl` (`Binding`, `KeyPat`, `match`, `dispatch`
returning an `Effect` enum: Run action id / Toast(level,msg) /
PushModal / PopModal / Focus(t) / Quit / Nop) + `tui/app.oxl`
skeleton (Focus/Modal enums, App struct, init defaults, toast
queue, `apply(effect)`).
Gate: `oxl test tui` green on dispatch resolution + precedence.

## S9.4 — Widgets (`tui/widgets.oxl` + tests)

Red: `widgets_test.oxl` — `LineEdit` (insert/del/word-move/home/
end/select-all/sel-shift/undo-redo-1lvl/ctrl+u/k/w/d), `ListCur`
(move/home/end/pgup/pgdn/half-page/select-extend), `TabStrip`
(left/right/into/out-of), `KVTable` (rows, toggle, delete, append-
on-type, cell edit), `Tree` (fold/move/parent-child/first-last/
extend-sel). Green: implement widgets; each `handle_key(ev)`
returns widget-level outcome consumed by dispatch layer 2.
Gate: `oxl test tui` green.

## S9.5 — App wiring + render (`tui/app.oxl`, `render.oxl`, `main.oxl`)

Red: `app_test.oxl` (focus transitions, modal push/pop, tab
lifecycle new/close/next/prev, jump-mode letter map, palette open/
nav/run incl. degrade entries, toasts, method menu, kind switch
re-maps req tabs, screenshot writes file to temp CWD,
sidebar toggle, expand maximize+quirk) and `render_test.oxl`
(MockScreen 80x24: header/url/footer present, sidebar visible/
hidden/right, vertical vs horizontal split, expanded maximize,
per-kind tab sets, focused-border attr).
Green: render.rs rects + pane renderers; main.oxl session loop:
`open_session` → open/mouse seq → loop{read→feed→dispatch→render→
present; SIGINT/0x03 quit; SIGWINCH rebuild} → close seq.
Gate: all dirs' tests green; `oxl build ./tui`.

## S9.6 — Smoke + coverage audit

Run binary on a real tty (manual): nav, palette, help, variables,
jump, degrade toasts, resize, clean exit. Count bindings in tables
vs spec (~114) — assert in `keymap_test` that every spec row has a
dispatch entry. Update `parity-matrix.md` rows §3/§4 → done/partial
notes; commit work-in-progress slices per stage (feat(tui) commits).

## Risk notes

- Line editor word ops: ASCII-only word chars (document).
- `posting-screenshot.txt` write failure (ro CWD) → error toast.
- Decoder must never drop bytes silently — unmatched sequences emit
  a Rune replacement? No: skip + status hint "(ignored seq)" dev-
  level; keep silent-skip minimal (bytes are never user-visible).
- Interface `#135`: no suspend in Screen methods — none needed.
