# WI-0012 spec — S9 TUI app shell and keymap dispatch

Direction: ADR-0028 (flat App + region renderers + layered dispatch;
incremental `core/term` Decoder). Contract: corpus-posting.md §1.6,
§3, §4.1–§4.15, §9 caveats. **S9 = shell + keymap.** Send dispatch,
collection/env file IO, config loading, real history are S10/S11 —
every such binding lands an explicit degrade, per ADR-0006/0024.

## Files (all `tui/` = `package main` unless noted)

- `core/term/decode.oxl` — `Decoder` FSM + `Key`/`KeyEvent` emit
- `core/term/decode_test.oxl`, `core/term/term_test.oxl` (+cases)
- `core/term/ansi.oxl` — Session: enable SGR mouse (1002/1006) +
  kitty disambiguate flags at open, disable at close
- `tui/keymap.oxl` — binding tables + `dispatch`
- `tui/app.oxl` — App state, focus enum, modal stack, toasts
- `tui/widgets.oxl` — line editor, list cursor, tab strip, KV table
- `tui/render.oxl` — layout rects + pane renderers
- `tui/main.oxl` — session loop (replaces S8 banner body)
- tests: `tui/keymap_test.oxl`, `tui/app_test.oxl`,
  `tui/widgets_test.oxl`, `tui/render_test.oxl`

## Input decode (core/term/decode.oxl)

`struct Decoder{ buf: []byte }`; `feed(bytes) -> []KeyEvent`
consumes a byte chunk, emits events, keeps a partial tail.

Grammar:
- UTF-8 printable → `Key.Rune` (decode multibyte by lead-byte
  length; malformed byte → skipped).
- C0: `0x0D`→enter, `0x09`→tab, `0x08`→backspace **and** `ctrl+h`
  (two KeyEvents? no — one event `Named{backspace}`; the keymap
  layer resolves the collision, see §9 rule below), `0x7F`→
  backspace, `0x00`→ctrl+space, `0x01–0x1A`→ctrl+letter
  (`0x0A`→ctrl+j — corpus send-request; distinct from enter),
  `0x1B` alone→escape (see alt rule), `0x1C–0x1F`→ctrl+\ | ] ^ _.
- `ESC [ …` CSI: `A/B/C/D` arrows, `H/F` home/end, `Z` shift+tab,
  `N~`-family `2=insert 3=delete 5=pgup 6=pgdown 7/1=home 8/4=end
  11-24=f1..f12` per xterm table, `;mod` parameter modifier =
  1+(shift 1|alt 2|ctrl 4). `ESC [ < b ; x ; y M/m` → SGR mouse
  (press/release/scroll-up/down, button, coords 1-based→0-based).
- `ESC O …` SS3: `P-S` f1..f4, `A-D` arrows, `H/F` home/end.
- `ESC [ code ; mod u` kitty CSI-u → rune+mods (ctrl+shift+v,
  ctrl+shift+s, ctrl+shift+z reachable).
- `ESC <x>` non-CSI: alt+key (same-chunk rule); `ESC ESC` →
  alt+escape.
- Partial sequence at chunk end stays buffered; lone trailing ESC →
  `escape` event immediately (same-chunk rule, documented deviation
  from upstream's timer — a read-poll loop cannot time out mid-
  sequence; consequence: alt keys require the terminal to deliver
  ESC+key in one read, which terminals do).
- `shift+letter` arrives as the uppercase rune (shift flag inferred
  when rune is upper ASCII — KeyEvent.shift set for `A-Z`).

Session changes (`ansi.oxl`): at `open_session`, write
`\x1b[?1002h\x1b[?1006h\x1b[>1u` (button-event + SGR mouse + kitty
disambiguate); `close` writes `\x1b[?1002l\x1b[?1006l\x1b[<u` before
leaving alt screen. Mouse scroll drag kinds map onto existing
`Mouse*` consts; add `MouseMove` not needed (1002 not 1003).

## App state (tui/app.oxl)

```
enum Focus = Sidebar | Url | Method | ReqTabs | ReqPane
           | RespTabs | RespPane          // corpus focus targets
enum Modal = Palette | Help | Variables | Confirm{msg,action}
           | SaveReq | SearchTabs | History | MethodMenu | Jump
           | EnvSwitch                    // §4.12 overlay stack
struct App {
  focus: Focus, modals: []Modal,
  url: LineEdit, method: str, kind: int,   // http|graphql|grpc|ws
  req_tab: int, resp_tab: int,             // per-kind tab sets
  sidebar_on: bool, sidebar_pos: int,      // left=0 right=1
  layout: int,                             // vertical=0 horiz=1
  expanded: int,                           // 0 none,1 req,2 resp
  tabs: []RTab, cur_tab: int,              // open request tabs
  coll: Tree, env_name: str,
  toasts: []Toast, status: str,
}
```

Defaults = corpus config defaults: `focus.on_startup`→`Url`,
`layout`→vertical, sidebar on, position left, `heading.visible`.
Env shown `(none)`; host via `$USER`+`$HOSTNAME` env probe
(no gethostname in std — degrade to omitting `@host`, documented).

## Keymap tables & dispatch (tui/keymap.oxl)

`struct Binding{ key: KeyPat, action: str }`; `KeyPat` = normalized
KeyEvent matcher. `dispatch(app, ev)` order:

1. top modal's table (escape always closes/cancels first),
2. focused widget's table (per-Focus pane table),
3. global rebindable table (18 actions),
4. fixed globals (escape/ctrl+c/ctrl+z/ctrl+shift+s).

Collision rule (§9 ctrl+h/backspace): the byte 0x08 decodes once;
widget tables that bind `backspace` consume it at layer 2; the
global `ctrl+h` binding is expressed as `ctrl|Named{backspace}`
which only reaches layer 3 when the widget didn't take `backspace`
— reproduces upstream behavior (Backspace deletes in collection
browser; ctrl+h toggles sidebar elsewhere).

## THE TABLE — every corpus binding → S9 disposition

Dispositions: **I** = implemented · **D** = explicit toast degrade
("unsupported in this build — lands S<n>") · **P** = opens real
placeholder panel/overlay.

### Fixed globals (4)
| key | corpus effect | S9 |
|---|---|---|
| escape | cancel/stop/close | I (modal close, jump/search exit, selection clear; no in-flight yet) |
| ctrl+c | quit | I |
| ctrl+z | suspend / undo in fields | D global "suspend unsupported in this build"; I single-level undo in URL/kv inputs |
| ctrl+shift+s | text screenshot → CWD | I (`posting-screenshot.txt`, cell-text dump via os.writefile_) |

### Rebindable actions (18 ids / 19 keys)
| id | keys | S9 |
|---|---|---|
| send-request | ctrl+j, alt+enter | D "send lands S10" |
| stream | alt+j | D "streams land M4 (gRPC/WS)" |
| jump | ctrl+o | I |
| commands | ctrl+p | I |
| save-request | ctrl+s | P save dialog skeleton; confirm → D (S10) |
| new-request | ctrl+n | I (new editor tab) |
| close-tab | alt+w | I |
| keep-tab | — | listed, unbound (corpus-exact) |
| next-tab | alt+right | I |
| previous-tab | alt+left | I |
| search-tabs | alt+down | I (tab-switcher overlay) |
| search-requests | ctrl+g | D (collection lands S10) |
| focus-url | ctrl+l | I |
| focus-method | ctrl+t | I |
| toggle-collection | ctrl+h | I (sidebar show/hide) |
| expand-section | alt+z | I (+ §9 quirk: also bound in req/resp widget tables) |
| variables | ctrl+shift+v | P variables screen (real overlay) |
| help | f1 | P help overlay (renders live keymap) |

### Jump mode (9)
`q w e r t y u`→request tabs I · `a`→resp body I · `4`→history P ·
`escape` I. (Per-kind letter remap for gRPC/GraphQL noted; kinds
selectable, tabs re-map like corpus.)

### Method selector/menu (12)
`enter`/`space` open menu I · `g p u a d h o` methods I ·
`q` GraphQL / `r` gRPC / `w` WebSocket → kind switch I (tab set
re-maps; send still D). Menu nav `up/down enter escape` I.

### URL bar (§4.4)
`enter` send → D (S10); curl-paste import → D · `down`→req tabs I ·
`ctrl+y` copy URL → D (no clipboard API in std) · `ctrl+shift+z`
redo I · `$` var suggestions → D (S10/S11) · segment/path
autocomplete → D (S10).

### Text editing — URL/kv line inputs (§4.8, 17)
`ctrl+left`,`alt+b` word-back I · `ctrl+right`,`alt+f` word-fwd I ·
`home`,`end`,`ctrl+e` I · `shift+move` select I · `ctrl+a`
select-all I · `ctrl+z` undo I (1 level) · `ctrl+y`/`ctrl+shift+z`
redo I · `ctrl+w`,`alt+backspace` del-word I · `ctrl+u`,`ctrl+k`
del-to-start/end I · `ctrl+d`,`delete` del-char I.
(gRPC `ctrl+r` re-list — D, gRPC oxl-blocked.)

### Request tab strip (§4.5, 6)
`left/h`,`right/l` switch I · `down/j/enter` into content I ·
`up/k` back out I — over the per-kind tab sets (HTTP 7: Headers,
Body, Path, Query, Auth, Info, Options).

### KV tables — Headers/Query (§4.6, 6+)
`up/down` row move I · `ctrl+r` toggle enabled I · `ctrl+x` delete
I · type-in-last-row appends I · `enter`/`e` edit cell (inline
line-edit) I · header-name suggestions → D (S10 needs header
lexicon) · mouse click checkbox/✕ I (toggle/delete row).
### Path table (§4.6)
Names derive from `:name` segments in URL text I; values editable
I; read-only names I.

### Body editor (§4.7)
Multiline text area: insert/enter/backspace/arrows I · bracket/
quote auto-pair + 2-space auto-indent + dedent-on-close I ·
content-type selector (JSON/Text/XML/HTML) I · `f3` pager → D ·
`f4` $EDITOR → D (term handoff + exec) · multipart pane = P w/
inspector fields listed; `insert ctrl+r ctrl+x alt+up/down f5
enter/escape` all → D (S10).

### Collection browser (§4.9, ~24)
Nav over stub tree (empty-state row "no collection — S10"):
`up/k down/j` move I · `left/h right/l` collapse/expand,
parent/child I · `home/g end/G` first/last I · `space` toggle
folder I · `shift+up/down/k/j shift+home/end` extend-selection I ·
`enter` open → D (S10) · `/` search input I (filters stub) ·
`escape` clear-sel-then-search I · `d` duplicate → D ·
`backspace/delete` delete-confirm → P confirm dialog; confirm → D.

### History (§4.10, ~13) — overlay via jump `4`/palette
`up/k down/j home/g end/G shift+… pgup/ctrl+u pgdown/ctrl+d` nav I
over empty list · `enter` open → D · `backspace` delete → D ·
`escape` close I.

### Variables screen (§4.11, 6)
Overlay listing session vars (empty): `enter` edit → D (S11) ·
`a` add → D · `d` revert → D · `/` filter I · `ctrl+r` mask
toggle I · `escape` close I.

### Command palette (§4.13, ~28 entries)
`up/down`/`ctrl+p/ctrl+n` nav I · `enter` run/submenu I ·
`escape` back/close I · `backspace`-on-empty back I. Commands:
New request I · Close/Pin(keep-tab)/Search tabs I · Quit I ·
Toggle collection I · Toggle layout I · Variables I · History P ·
Help P · Send request → D · Save request → P(dialog)·
Open/Duplicate/Delete request(s), Search collection, env switch,
reload collection, OAuth sign-in, gRPC stream open/end, WS
disconnect, Import curl cmd/clipboard, Export curl/grpcurl/YAML,
Theme…, Sidebar gradient…, Open docs, response copy commands → all
D with per-stage labels (OAuth2 M4, themes M4, exports S10, docs
launch unsupported).

### Response panel (§4.14)
Tabs Body/Headers/Cookies/Trace — placeholders ("no response —
send lands S10") with real nav:
- text view: `k j h l`, `w b`, `0 ^ $`, `g G`, `%`, `pgup ctrl+b
  pgdn`, `ctrl+u/d`, `ctrl+f`,`/` + `n/N` search over buffer I ·
  `v`,`V`,`f6`,`f7`,`shift+hjklwb` selection I · `ctrl+a` line-start
  I · `y/c` copy → D (no clipboard) · `f3`/`f4` → D.
- JSON tree keys `e/E/Y`, JSONPath filter → D (needs a response).
- Headers/Cookies tables: `up/k down/j home/g end/G` I ·
  `shift+up/down`,`ctrl+a` multi-select I · `y/c/n/b` copy → D.
- Messages tab not rendered (streams post) — `f/enter/escape`
  bindings present → D.
- Image: `f2`,`s` → D.

### Toasts/status
`app.toast(level, msg)`; level info/success/error per §4.12;
degrades are error-level with "unsupported in this build — lands
S<n>" text. Toast queue renders above footer, newest last.

## Render/layout (tui/render.oxl)

Rows: `0` header (`oxttp-tui vX · env (none) · user@host`); `1..3`
URL bar = method cell + URL line + preview line (preview = url
verbatim until vars land S10); body region split: sidebar (w≈24 or
cols/4, position per `sidebar_pos`, hidden when `sidebar_on`=false)
+ main; main split per `layout` (vertical: req ⌈h/2⌉ over resp;
horizontal: side-by-side); `expanded` maximizes req or resp.
Request pane: tab strip (per-kind set) + content area (KV table /
path table / body editor / placeholder). Response pane: tab strip +
placeholder text view. Footer: context-key hints for focus + modal.
Panes show focused border (AttrReverse title or fg accent).

## Terminal lifecycle

open: alt-screen + raw + signals (S8) **+ mouse 1002/1006 + kitty
`>1u`** → shell draw → loop{stdin.read→feed→dispatch→render→
present; SIGINT take→quit; SIGWINCH take→resize+rebuild screen}
→ close restores (mouse/kitty off, alt off, raw restore). `q` in
shell (non-widget focus) quits — matches corpus quit path only via
ctrl+c/palette Quit: **deviation** — keep `q`→quit only when focus
is a pane that binds no `q` (sidebar) else it's a text char; verify
vs corpus (Posting has no `q` global quit — quit is ctrl+c or
palette; so `q` stays a normal char/command char — remove the S8
banner's q-quit).

## Deviations recorded (explicit, per corpus-fidelity standard)

1. alt/escape = same-chunk rule (upstream: input timer).
2. `user@host` from `$USER`/`$HOSTNAME` env (no gethostname in
   std); absent → omitted.
3. `ctrl+z` suspend → degrade (no SIGTSTP raise in std); field
   undo = single level.
4. Clipboard ops (`y/c/n/b`, ctrl+y) degrade — no clipboard API.
5. `f3`/`f4` pager/editor degrade — no safe terminal handoff for
   exec'd pager in S9.
6. Screenshot filename `posting-screenshot.txt` (corpus pins
   "to CWD", not the name).
7. ctrl+shift+{s,v,z} require kitty keyboard protocol (we push
   `>1u`); corpus §9 already documents this dependency.
8. Sidebar/history/variables show empty-state placeholder content
   (collection/env IO is S10/S11).
9. No `q` global quit — corpus has none; ctrl+c/palette Quit only.
10. Request tabs carry in-memory demo rows so navigation is
    exercisable; send/save degrade.

## Acceptance criteria

- `oxl build ./tui` + `./cli` clean; `oxl test` per-dir green.
- Decoder tests: every grammar class + partial-tail buffering.
- Dispatch tests: all ~114 bindings resolve; precedence (modal >
  widget > global) proven; ctrl+h/backspace collision; expand quirk.
- Render tests on MockScreen: layout rects for vertical/horizontal/
  expanded/sidebar-off; header/url/footer presence; per-kind tabs.
- Manual smoke: run `oxttp-tui` in a tty — navigate, open palette/
  help/variables/jump, degrade toasts visible, resize clean, exit
  restores terminal.
- Keymap coverage table in this spec = the canonical list; verify
  counts in code tests (each table row has a binding entry).
