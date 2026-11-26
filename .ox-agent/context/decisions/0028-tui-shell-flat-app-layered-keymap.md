# ADR-0028 — TUI shell: flat App state + layered keymap dispatch

- Status: accepted
- Date: 2026-11-25
- Work item: WI-0012 (S9)

## Context

Posting's corpus (§3/§4) defines ~114 keybindings in three precedence
layers — fixed globals, 18 rebindable actions, ~95 widget-level
bindings — where focused widgets take precedence over globals, plus a
modal/overlay stack (palette, help, variables, dialogs, jump mode)
that takes precedence over everything beneath it. The S8 driver
(ADR-0027) gives `Session`/`AnsiScreen`/`Key`/`KeyEvent`; S9 needs the
app-shell architecture on top.

## Decision

1. **Input decode lives in `core/term`** as an incremental byte-
   stream FSM (`Decoder.feed([]byte) -> []KeyEvent`): runes, C0
   control bytes, ESC-prefixed alt, CSI/SS3 named keys with `;mod`
   params, kitty CSI-u, SGR mouse. Alt-vs-Escape disambiguation is
   **same-chunk**: ESC followed by more bytes in the same `feed` call
   is an alt/escape sequence; a lone trailing ESC is `Escape`
   (upstream uses input timing; a poll loop cannot — documented in
   the spec).
2. **App architecture is flat state, not a widget tree**: one `App`
   struct in `tui/` holds focus target, modal stack, per-pane state,
   and a toast queue; `render` walks region renderers that write
   cells into `Screen` sub-rects. A retained `Widget`-interface tree
   (upstream Terma's shape) was rejected — corpus fidelity is
   observable keys→effects, and oxl ownership makes tree structures
   costly for no behavioral gain.
3. **Dispatch is a three-layer walk**: modal stack → focused-widget
   binding table → global rebindable table (with the four fixed
   global keys evaluated in-layer per corpus precedence). Binding
   tables are `[]Binding` slices; the rebindable table's entry-
   replaces-defaults shape is fixed now so S11's `keymap:` config
   loader is additive only.
4. **Degradation is a first-class dispatch outcome**: every corpus
   binding resolves to implemented behavior, a real placeholder
   panel, or an error-level toast "…unsupported in this build (lands
   S<n>)". Corpus §9 quirks (`alt+z` expand inside panels, `ctrl+h`/
   Backspace byte collision) are expressed *by* the layering, not
   special-cased.

## Consequences

- `Decoder` is headless-testable; `App.dispatch`/`render` test on a
  MockScreen — no tty needed for ~all coverage.
- `Session` opens SGR mouse reporting (1002/1006) and disables it on
  close; `Key.Mouse` click/scroll dispatch lands with the shell.
- `ctrl+z` suspend is a documented degrade (std has no SIGTSTP
  raise); `ctrl+shift+s` screenshot implemented via cell-text dump.
- `focus.on_startup=url`, `layout=vertical`,
  `collection_browser.show_on_startup=true` defaults are baked into
  App init; S11 config flips them without re-shaping state.
