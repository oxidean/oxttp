# WI-0012 discovery — S9 TUI app shell and keymap dispatch

Scope (program S9, parity-matrix rows §3 + §4 → `next`): Posting app
shell — layout, panes, focus model, modal/overlay stack — and the full
keymap dispatch, on the S8 `core/term` driver. Request dispatch
(send) is **S10**; collections IO is **S10**; config file loading
(40 keys, `keymap` overrides) is **S11**. This stage wires every corpus
key to a dispatch entry: implemented shell behavior or explicit
in-UI "not implemented" degradation (ADR-0006/0024 — never silent).

Sources: `docs/corpus/corpus-posting.md` §1.6, §3 (actions+keymap),
§4.1–§4.15 (screens/widgets), §9 caveats, §10 counts. Code surveyed:
`core/term/{term,ansi}.oxl`, `tui/main.oxl`, `core/model/model.oxl`,
`core/collection/collection.oxl`, `core/http/h1.oxl` (transport port),
std `os/term`, `os/signal`, `strings` (7 fns only), `os` (getenv,
no hostname API).

## Corpus inventory — what S9 must cover

### Keymap (§3 + §4, §10 counts)

- **18 rebindable action IDs, 19 default keys** (§3 table). Defaults:
  send-request `ctrl+j`,`alt+enter` · stream `alt+j` · jump `ctrl+o` ·
  commands `ctrl+p` · save-request `ctrl+s` · new-request `ctrl+n` ·
  close-tab `alt+w` · keep-tab *(none)* · next-tab `alt+right` ·
  previous-tab `alt+left` · search-tabs `alt+down` ·
  search-requests `ctrl+g` · focus-url `ctrl+l` · focus-method `ctrl+t` ·
  toggle-collection `ctrl+h` · expand-section `alt+z` ·
  variables `ctrl+shift+v` · help `f1`. Rebind table format:
  `action-id: key[,key]` — entry *replaces* defaults; `jump` uses only
  first key. Key format `ctrl/alt/shift/meta/super+key`, named keys
  `enter tab space backspace delete insert escape up down left right
  home end pgup pgdown f1..f12`, case-insensitive. (Config-file
  keymap overrides are an S11 loader concern — the dispatch table
  shape must admit replacement now.)
- **4 fixed global keys** (not rebindable): `escape` (cancel
  in-flight / stop stream / close dialog), `ctrl+c` (quit),
  `ctrl+z` (suspend; undo inside text fields), `ctrl+shift+s` (text
  screenshot to CWD).
- **~95 widget-level bindings** across §4 — jump-mode letters
  (`q w e r t y u` request tabs, `a` response body, `4` history,
  `escape` exit); method selector (`enter`/`space` open; `g p u a d h
  o` methods; `q r w` → GraphQL/gRPC/WebSocket); URL bar (`enter`
  send/curl-import, `down`, `ctrl+y` copy, `ctrl+shift+z` redo, `$`
  var suggestions, path-segment autocomplete); request-tab strip
  (`left/h right/l down/j/enter up/k`); KV tables (append-on-last-row,
  `up/down`, `ctrl+r` toggle, `ctrl+x` delete); body editor (smart
  pairs/auto-indent, `f3`/`f4`; multipart `insert ctrl+r ctrl+x
  alt+up/down f5 enter/escape`); text inputs (~18 editing keys +
  suggestion-list `up/down enter escape`); collection browser (~25
  nav/select/search/delete keys); history (~13); variables screen (6);
  command palette (5+submenu); response text view (~30 vi-style);
  JSON tree (7); header/cookie/trailer tables (~10); messages log (3);
  image preview (`f2`, `s`).
- Precedence rule (§3): **focused widgets take precedence over
  globals** — dispatch must be layered (modal > focused widget >
  global), never a flat map.

### App shell (§4.1 layout)

Header row (app name/version, active env, `user@host` or
`heading.hostname`) · URL bar (method selector + URL input + value
preview line) · sidebar/collection browser (left default,
`collection_browser.position` right option — S11 config; default on
at startup) · **Request** panel 7 tabs: Headers, Body, Path, Query,
Auth, Info, Options · **Response** panel tabs: Body, Headers,
Cookies, Trace (+Messages for streams — stream kinds are
oxl-blocked/post) · footer with context keys · `layout`
vertical(default)/horizontal · `expand-section` maximizes focused
panel (+ §9 quirk: `alt+z` still works inside Request/Response even
if rebound — the fixed-vs-rebindable split matters).

### Focus model (§2.2 `focus.*`, §4)

Startup focus default `url` (`focus.on_startup`: url|method|
collection — config S11, default applies now). `focus.on_response`,
`focus.on_request_open` are S10 concerns. Focus targets = widgets;
each pane owns a sub-focus (e.g. request panel → active tab).

### Terminal behaviors (§1.6, §4, S8 driver)

Alternate screen + raw mode (done in S8 `Session`), SIGWINCH resize
(done), clean restore on exit (done). **Mouse**: corpus §4.6
checkbox/`✕` clickables and scroll imply SGR mouse — `Key.Mouse`
shape already defined in term.oxl; S9 should enable mouse reporting
(1002/1006) + decode clicks/scroll into `Key.Mouse` events and give
them a defined dispatch (focus pane / scroll list / explicit
degrade). `ctrl+z` = suspend → SIGTSTP via `std/os/exec`? std has no
`kill`/SIGTSTP raise — needs check; fallback = documented degrade.
`ctrl+shift+s` text screenshot to CWD — pure file write, feasible.

## Existing substrate (S8/WI-0010)

- `core/term`: `Screen` port (size/set_cell/present/cursor), `Key`
  enum (Rune/Named/Mouse), `KeyEvent` (5 modifier bools — no bitwise
  ops in oxl), `AnsiScreen` cell grid + ANSI flush (full repaint each
  present — dirty-rect is a polish item), `Session` (raw mode, size
  probe, SIGINT/SIGWINCH arm/take, close = leave-alt + disarm +
  restore). `open_session` non-tty → err → banner fallback.
- `tui/main.oxl`: 78 LOC banner + poll loop (q/Ctrl-C/SIGINT/resize).
- `core/model`: `Req`, `Resp`, `Header`, `KV`, `Part`, `Body`,
  `Trace`, `status_class` — response viewer has types already; send
  wiring is S10.
- `core/collection`: `.posting.yaml` schema types (parse IO is S10 —
  sidebar tree has no file source yet; use in-memory placeholder
  rows).
- `shared/args`: xh-shaped parser — Posting's own flag surface
  (`-c/-e/-v/-h` + subcommands) is S11; TUI keeps argv minimal.

## oxl constraints that shape the design

- All files in `tui/` are `package main`; testable pure units live in
  `*_test.oxl` in the same dir (`oxl test ./tui` works on package
  main — proven by cli tests). Key decode can live in `core/term`
  (driver-level, headless-testable); keymap/app state in `tui/`.
- `[v, err]` is the only multi-return; `[x,e]=f()` in a block
  **shadows** — assign to fresh names then copy. `mkslice(Qualified.
  Type)` broken (#136) → push/append patterns or same-package
  builders. Interface methods can't suspend (#135) — keep Screen
  methods synchronous (they are).
- No `Option[T]`; nil = `own T` pointers; `has_` bools for optional
  scalars. No str-keyed maps → ordered KV slices / parallel arrays.
- strings pkg is tiny (startswith/endswith/contains/trim/split/join/
  upper) — key parsing needs manual byte loops; `itoa`/`substr`/`len`
  are builtins. No `lower` — uppercase for case-insensitive compare.
- `os.writefile_` returns byte count (#137). `asreader()` boxes a
  borrow (#138). os has `getenv` (env name / `$EDITOR`), `readfile_`,
  `lsdir` — **no `gethostname`** → `user@host` heading needs env
  fallback (`$HOSTNAME`/`hostname` via exec?) or degrade; check
  `os/exec` surface.
- Input decode: stdin `read` in raw mode delivers byte chunks —
  ESC-prefixed sequences need a stateful incremental decoder
  (alt = ESC prefix ambiguity vs lone Escape key — upstream uses
  timing; we must pick a defined rule, e.g. ESC followed by more
  bytes in the same read chunk = alt).

## Degradation surface to enumerate in spec

Every §3/§4 binding lands one of: **implemented** (shell navigation,
focus, tabs, quit, palette/help/variables placeholders that open/close,
method selector, jump mode, sidebar toggle, expand, text editing in
URL bar, screenshot), **placeholder-panel** (opens a real panel with
" arrives in S10/S11" body), or **explicit degrade** (toast/status:
"not implemented in this build — <reason/stage>"). Corpus §9 no-ops
(spacing, P2 settings) stay no-ops only where upstream is a no-op —
documented in spec, per ADR-0024 inert rule.

## Open questions for brainstorm/spec

1. Decoder granularity: incremental byte-stream FSM in `core/term`
   (testable headless) — alt-vs-escape disambiguation rule.
2. Mouse reporting: enable 1002/1006 at session open, or lazy? Corpus
   clickables land with KV tables — minimal = decode + pane-focus on
   click + scroll lists.
3. Focus/widget tree: flat focus ring vs per-pane sub-focus state
   machine — pick the shape that admits `focus.*` config in S11.
4. Where the keymap table lives: `tui/keymap.oxl` (app-owned) with
   `core/term` decode feeding KeyEvents.
5. `ctrl+z` suspend feasibility under oxl (no signal raise in std?);
   screenshot = `os.writefile_` of rendered cell text — cheap, do it.
6. Toast/status model for degradations — single status bar vs toast
   queue (corpus §4.12 toasts info/success/error).
