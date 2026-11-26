# WI-0012 brainstorm — TUI app shell + keymap dispatch architecture

Settled upstream: corpus-posting.md §3/§4 is the contract; driver is
S8 `core/term` Session/AnsiScreen (ADR-0027); degrade explicitly
(ADR-0006/0024); send = S10, collections IO = S10, config files = S11.
This brainstorm picks: input decode placement, app/dispatch
architecture, keymap table shape, and the degradation model.

## Option A — flat App state + region renderers + layered dispatch (CHOSEN)

- `core/term/decode.oxl` — incremental `Decoder` struct:
  `feed([]byte) -> []KeyEvent`. Driver-level, headless-testable; owns
  the byte grammar (runes, C0 control bytes → ctrl keys, ESC-prefix →
  alt, CSI/SS3 named keys + `;mod` params, kitty CSI-u, SGR mouse).
- `tui/keymap.oxl` — binding tables + dispatch:
  `[]Binding{ctx, action, key-pat}`; `dispatch(app, ev)` walks
  modal stack → focused widget table → global table → fixed keys.
  Widget tables are the ~95 §4 bindings; globals the 18 rebindable
  actions; fixed = escape/ctrl+c/ctrl+z/ctrl+shift+s evaluated per
  layer per corpus precedence.
- `tui/app.oxl` — `App` struct: focus target, modal/overlay stack,
  per-pane state (sidebar tree rows, url-bar line editor, request/
  response tab indices, KV row cursor), toast queue, placeholder
  collection/env data.
- `tui/render.oxl` — layout math (header/url/sidebar/panels/footer
  rects, vertical vs horizontal, expand-section maximize) + pane
  renderers writing cells into `Screen` sub-rects.
- `tui/widgets.oxl` — reusable focused widgets: single-line text
  input (corpus §4.8 editing keys), list cursor, tab strip, KV table
  rows — each a struct + `handle_key` + `render`.
- `tui/main.oxl` — session loop: `stdin.read` → `decoder.feed` →
  `dispatch` per event → `render` → `present`; SIGINT/SIGWINCH via
  Session; `ctrl+c` also arrives as byte 0x03.

Pros: every piece testable headless (`Decoder.feed`, `dispatch` on an
App, render into MockScreen); mirrors corpus structure (actions vs
widget bindings vs fixed keys); no oxl gymnastics. Cons: `App` grows
— mitigated by per-widget structs + per-pane state blocks.

## Option B — retained widget tree with interface dispatch (REJECTED)

A `Widget` interface (handle_key/render/focus) with a focus-walking
tree like upstream Terma. oxl interfaces + `mut` receivers through
interfaces are workable but the tree adds ownership complexity
(every pane `own`-ed, parent pointers impossible) for zero fidelity
gain — corpus behavior is observable (keys→effects), not structural.
Rejected: flat state + switch dispatch expresses the same contract.

## Option C — keymap as data file now (REJECTED for S9)

Load `keymap:` overrides from config.yaml in this stage — config
loading is S11 (parity matrix §2 `next`). The *table shape* admits
entry-replaces-defaults (rebind semantics) now so S11 is a loader
only; shipping the YAML loader early would pull config-file
precedence (`POSTING_*` env, XDG paths) into S9 scope. Rejected.

## Sub-decisions

1. **Alt vs Escape disambiguation**: ESC followed by ≥1 byte *in the
   same feed call* = alt-prefixed sequence; lone ESC at chunk end =
   Escape. Upstream relies on terminal timing; a polling read loop
   can't suspend mid-sequence — same-chunk rule is deterministic and
   documented in spec (CSI/SS3 continuations in-chunk decode as the
   sequence, not alt+keys).
2. **Modifiers**: decode both conventions — legacy `ESC [ 1 ; m X` /
   `ESC [ X ; m ~` (modifier = 1+bitmask: shift=1 alt=2 ctrl=4) and
   kitty CSI-u `ESC [ code ; m u`. `ctrl+shift+v` is unreachable
   without CSI-u on most terminals — decode supports it; spec notes
   the kitty-protocol caveat (corpus §9 already documents
   ctrl+shift+z's kitty dependency).
3. **Mouse**: Session enables SGR 1006 + button-event 1002 at open,
   disables at close; decoder emits `Key.Mouse`; dispatch = click →
   focus pane / activate row where the corpus defines clickables
   (KV checkbox/✕), scroll → list scroll; else explicit degrade.
4. **ctrl+z**: no SIGTSTP raise in std (signal pkg is arm/take only)
   — global suspend = explicit degrade toast "suspend unsupported in
   this build"; inside text fields the corpus assigns undo — single-
   level undo for the URL line editor is cheap, included; deeper
   fields are S10+ placeholders.
5. **ctrl+shift+s screenshot**: implemented — dump visible cell text
   to `posting-screenshot.txt` in CWD (`os.writefile_` #137: use
   byte-count return). Corpus pins the *behavior* (text screenshot
   to CWD), not a filename — recorded in spec.
6. **ctrl+h vs Backspace (0x08)**: corpus §9 flags the collision.
   Rule: focused widget binding `backspace` wins (collection browser
   delete-confirm is widget-level); otherwise falls through to
   global `ctrl+h` (toggle-collection). Same precedence layering,
   just a shared byte.
7. **keep-tab**: exists in the rebindable table with no default key —
   present in the action list (palette/vars surfaces can reference
   it) but unreachable by default, matching corpus exactly.
8. **expand-section quirk (§9)**: `alt+z` stays bound inside
   Request/Response panel widget tables *and* as the global default —
   both layers implement it now, so the quirk is free; S11 rebinds
   only rewrite the global entry.
9. **Focus targets**: enum Focus{Collection, UrlBar, ReqTabs,
   ReqContent, RespTabs, RespContent} + modal frames; startup =
   UrlBar (corpus `focus.on_startup` default `url`).
10. **Placeholder panes**: sidebar shows "no collection loaded —
    lands S10" + heading env "(default)"; response panel shows
    empty-state ("send a request — lands S10"); variables screen and
    help screen are real overlays with real content (help lists the
    actual keymap — cheap, high fidelity).
11. **Command palette**: implement the *overlay + dispatch
    mechanics* (open/close/nav/run) with a curated command list;
    entries whose behavior is out of stage run their degrade action.
12. **Jump mode**: implemented — letter overlay per §4.2
    (`q w e r t y u` request tabs, `a` response body, `4` history),
    `escape` exits.
13. **Toasts**: §4.12 info/success/error levels; degrade class =
    error-level toast "…unsupported in this build…".
14. **Undo/redo in URL bar**: single-level undo buffer (ctrl+z /
    ctrl+y per §4.8, ctrl+shift+z redo); deep fields S10.
15. **Layout**: `layout=vertical` default (request over response);
    horizontal mode is a layout-math branch, included since it's
    arithmetic only; `expand-section` maximizes focused of the two.

## Degradation philosophy

Every corpus binding resolves to one dispatch outcome; the spec's
keymap table is the canonical coverage list (~114 rows). Degrade
toasts name the stage ("send lands in S10") — never a silent no-op,
never an unknown-key beep.
