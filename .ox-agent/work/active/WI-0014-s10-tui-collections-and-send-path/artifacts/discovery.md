# WI-0014 discovery — S10 TUI collections and send path

Scope (program S10, parity-matrix rows §5 `.posting.yaml` collections,
§6 environments, §7.1 HTTP send → `next`): real collection loading
and browsing in the sidebar, environment file discovery/switching
with `$VAR` substitution, and wiring `send-request` through
`core/model` + `core/http` to real HTTP(S) responses rendered in the
response pane. Per WI-0008 discovery §C1: "S10 collections + send via
core — §5 `.posting.yaml`, §7.1 HTTP — byte-compat fixtures". §6 row
reads "Env S10/S11; captures M4" — environment *files + substitution*
are in; captures/generated values and the 40-key config file are not
(§2 config is S11). Cookies/history row spans S10–S11: session-scoped
jar + in-memory history fit S10; disk persistence is S11.

Sources: `docs/corpus/corpus-posting.md` §4.9 (browser keys), §4.11–15
(variables/response widgets), §5 (collections + history), §6 (envs +
substitution), §7.1 (HTTP send semantics), §9 caveats. Code surveyed:
`tui/{app,types,keymap,render,widgets,main}.oxl`, `core/collection`,
`core/model`, `core/http/{transport,h1,wire}`, `core/session`,
`cli/{exec,cfg,sem}.oxl` (plan()/exec reference), oxl 0.26.0 std
(`os`, `net/url`, `encoding/json`).

## Corpus inventory — what S10 must cover

### Collections (§5.1–5.2)

- Directory tree of `*.posting.yaml`; root = positional arg /
  `--collection` else `<data>/default` (auto-created 0755; data dir
  `$XDG_DATA_HOME/posting` else `~/.local/share/posting` — §2.1).
  Skip dot-directories, `__pycache__`, `node_modules`. Malformed
  files render as placeholder rows carrying the parse error — never
  abort the load. Sidebar sort: folders first, then requests,
  alphabetical.
- Request file schema: 17 top-level keys, `omitempty` write — types
  already live in `core/collection/collection.oxl` (WI-0003,
  ADR-0010 verbatim clone). Exactly-one-body rule (>1 of
  content/form_data/multipart/file = parse error; part needs exactly
  one of value|file). `method` uppercased+validated, default GET.
  `options` defaults: follow_redirects true (≤10), verify_ssl true,
  attach_cookies true, substitute_body_variables true, timeout 5s.
- Sidebar ops (§4.9 + §5.1): `enter` open (into preview tab —
  italic/dotted rules §8.6), `d` duplicate (`(copy)` name + copy
  beside original), `backspace`/`delete` delete file (confirm once),
  `/` search, save-request dialog (Name required, File, Folder,
  Description) → writes `<folder>/<slug>.posting.yaml`.
- `watch_collection_files` reload — default true upstream but needs
  a fs watcher thread; oxl std has no fsnotify → degrade path.
- Env files searched CWD → collection dir → config dir (§5.1);
  `posting.env`, `posting.local.env`, `<name>.env`,
  `<name>.local.env`.

### Environments & substitution (§6)

- dotenv syntax: `NAME=value`, optional `export `, `'`/`"` quoting,
  `#` comments, `KEY="${OTHER}"` refs. Layer order: `posting.env` →
  `posting.local.env` → `<name>.env` → `<name>.local.env` → session
  values. Missing files skipped. `use_host_environment` default
  false (config S11 — no host env exposure this stage).
  `POSTING_*` keys inside env files → warning.
- Substitution: `$NAME` + `${NAME}`; `$$` literal `$`. Unresolved:
  error in URL address/path + OAuth fields; literal passthrough
  elsewhere (incl. query). Expansion limits >10000 refs / >16 MiB
  aggregate = error. `substitute_body_variables` gates the body;
  URL/headers/auth always substitute. Generated values
  (`${$uuid}`/`${$timestamp}`/`${$timestampMs}`/`${$isoTimestamp}`/
  `${$randomInt}`) — §6.2; cheap candidates inside the same engine,
  but corpus marks generated values P3-only extras → option for
  brainstorm (default: include — they are part of the same pass).
- Captures (`captures:` map) — M4 per matrix; parse must not fail
  on the key (schema keeps it), execution deferred.
- Env switcher modal exists (MEnvSwitch); needs a real env-name list
  from `*.env` files + active selection persisted in-app (the
  `<data>/environments.json` memory file is S11-adjacent; session
  scope acceptable in S10 — call out in spec).
- Variables screen (§4.11) lists effective vars w/ source labels;
  wiring it to the loaded env layers is in scope (rows + source).

### HTTP send (§7.1) & response render (§4.14–4.15)

- Methods GET..OPTIONS; scheme-less URL → `http://`; `User-Agent:
  posting/<ver>` unless caller set one — oxttp drop-in question:
  upstream sends its own product token; our equivalent is the
  binary's own UA (spec decides exact token — `posting/` matches
  wire-compat intent vs `oxttp-tui/` honesty; brainstorm option).
- `path_params` fill `:name` URL placeholders; `params` rows append
  query (enabled only); `headers` rows (enabled only; disabled rows
  persist-but-don't-send).
- Options map onto `model.Req`: `follow_redirects`→follow +
  max_redirects ≤10; `timeout` seconds→timeout_ms (default 5s —
  posting default unlike xh's none); `verify_ssl` false→
  `req.verify="no"` (AcceptAll, IN-0005=B landed in H1);
  `proxy_url` — env/proxy wiring is WI-0013 territory: degrade with
  warning if set (corp §7.1 proxy resolution partial).
  `attach_cookies` → app-session jar (cookie-jar-lite ADR-0023
  pattern, session-scoped shared by tabs).
- Auth from file: `basic`→Authorization Basic, `bearer_token`→Bearer;
  `digest` → degrade (challenge/response is post); `oauth2` →
  degrade (M4).
- Bodies: `content`→Raw (content_type or Content-Type header
  fallback); `form_data`→Form; `multipart`→Multipart (parts w/ file
  read from collection-relative disk — corpus: paths vs collection
  root); `file`→FileBody (pre-connect file check exists in
  wire.RenderBody). All already wire-renderable via
  `http.RenderBody`. GraphQL/gRPC/WS kinds open fine but send
  degrades (§7.2 GraphQL `post`/M4 per matrix; gRPC/WS oxl-blocked).
- **Send is synchronous**: `Transport.send` is a vtable call that
  cannot suspend; H1 deliberately blocks the calling thread
  (h1.oxl:10-17). The TUI loop freezes during the exchange —
  upstream sends async with Escape-cancel. S10 spec must record the
  deviation: Escape cannot abort an in-flight send this stage.
- Response render: StatusClass colors (<300 success / <400 redirect
  / else error — `model.status_class` exists); Body tab = decoded
  body (prettify_json default → re-indent via `encoding/json` when
  Content-Type json); Headers tab = `resp_rows` table;
  Cookies tab = Set-Cookie rows; Trace tab = `resp.trace` 7 stages;
  pane title gains size+elapsed (response.show_size_and_time
  default). `focus.on_response` unset → no focus steal.
- Errors (DNS/connect/TLS/timeout/malformed) → error toast +
  response pane shows the failure text — never a silent no-op.

### History (§5.3, S10 subset)

- Upstream: `<data>/history/<sha256-of-collection-path>.json`,
  MaxEntries=100, MaxBytes=50MiB, lock sidecar. S10 subset:
  in-memory ring (100) feeding the existing MHistory modal
  (enter opens entry into preview tab, backspace removes);
  disk persistence + sha256 naming lands with S11 config/paths.
  Brainstorm option to cut entirely if scope tightens.

## Existing substrate (S9/WI-0012)

- `tui/app.oxl`: dispatch layered modal>widget>global>fixed;
  `send-request`, `tree-open`, `tree-dup`, `tree-delete`,
  `search-requests`, env-pick, hist-open, save-confirm all currently
  `degrade()` toasts — the S10 wiring points are already named.
  Per-tab `RDraft` snapshots exist (url/method/kind/kv tables/body/
  resp_view/resp_rows) — opening a file = filling a draft;
  `RTab{title, preview, draft}` + `tab_select` manage preview tabs.
- `tui/types.oxl`: `TreeNode{name,depth,is_dir,open,stub}` — needs a
  payload link to the backing file (path + parsed request ref) and
  probably a `bad` flag for malformed placeholders. `App.env_name`
  exists; needs env layers + jar + history storage.
- `core/collection`: schema structs only — parse/scan/marshal all
  new (the file itself says "parse/serialize land in S10").
- `core/model`: `Req` covers follow/max_redirects/timeout_ms/
  verify/synth/httpver; `Resp` carries trace/hops/req_head.
- `core/http`: `Transport` port + `H1` impl (h1+h2? no — H1 only;
  TLS via `req.verify`). `RenderBody` handles all 5 Body kinds.
- `cli/exec.oxl` `plan()`: reference for header merge/cookie/
  session semantics — but it's Intent-coupled; TUI gets its own
  draft→Req builder (probably `tui/send.oxl` or `core/plan`?

  placement is a brainstorm question — `cli` code is `package main`
  so it cannot be imported: reuse = port, not import).
- `shared/version`: UA token source.

## oxl constraints that shape the design

- **No YAML in std 0.26.0** (`encoding/` = base64, binary, csv,
  gob, hex, json, xml only). `.posting.yaml` needs a repo-local
  YAML-subset reader + writer: block maps/sequences, nested maps,
  `key:`/`key: value`, `- ` items, scalars (plain/single/double
  quotes, `|`/`>` block scalars, `!!binary`?), bools/ints/floats/
  null. Posting writes "plain/!!binary-safe YAML scalars"
  (§5.2 Marshal) — emitter can stay minimal (plain scalars +
  double-quoted fallback). Scope the subset in the spec; fixtures
  pin the accepted grammar.
- `os` surface: `ls` (sorted names), `isdir`, `exists`,
  `readfile_` (conflates unreadable/empty — use `exists` first),
  `writefile_` (returns count; <0 = errno), `mkdir_all`, `getenv`,
  `fullpath`, `remove`. No fsnotify, no `stat` size/mtime surface
  (needed only for file-resend identity — not in scope).
- `os.nargs()/args(i)` for the collection positional; flag surface
  (`-c/-e/-v/-h` + subcommands) is S11 — S10 takes argv[1]
  positional only if non-flag, documented.
- `str` maps don't exist → ordered `[]model.KV` for env layers
  (insertion order = display order on the variables screen).
- package rules: `tui/` is `package main` (tests in `*_test.oxl`
  same-dir work); new IO-free logic should live in `core/` leaf
  pkgs for testability — collection IO in `core/collection`, env in
  `core/env` (new leaf), substitution maybe `core/env` too.
- `[v,err]` multi-return only; `mkslice(Qualified.Type)` broken —
  push/append patterns. Interface methods can't suspend.
- No `stat`/mtime → file-body resend verification (§7.1 "verifies
  file identity/size/mtime") can't be honored — H1 is single-shot
  anyway (ADR-0019); file bodies still send once, fine.

## Degradation surface to enumerate in spec

Implemented: load/scan/tree, open request, duplicate, delete
(confirm), save (marshal), env discover/switch/substitute, variables
list, send (+redirect/timeout/verify_ssl/jar), response body/headers/
cookies/trace tabs, in-memory history, request search (`/`), `enter`
on sidebar multi-select opens all.

Degrade (explicit toast, never silent): gRPC/WS/GraphQL-kind sends,
digest/oauth2 auth, `proxy_url`, fs-watch reload, curl import/export
(§7.7 post), captures execution (M4), multipart *editor* UI (file
bodies still send from disk), `substitute_body_variables` UI toggle,
history persistence, `environments.json` memory, `use_host_environment`
(config S11), async send/Escape-cancel (oxl transport is blocking —
upstream finding), body>64MB stream caps, image preview (§4.14 post).

## Open questions for brainstorm/spec

1. YAML subset shape: dedicated `core/yaml`-ish mini package vs
   private parser inside `core/collection` — grammar surface to pin
   (block scalars? flow `[]`/`{}`? anchors? — Posting files never
   emit them, but hand-edited files might).
2. Collection root: argv positional + `<data>/default` autocreate —
   do we also honor `--collection`/`-c`/`--env` now or leave flag
   surface to S11 entirely?
3. Send UX under a blocking transport: synchronous-with-toast
   ("sending…" painted before blocking) vs attempt a task spawn —
   spawn buys nothing (send can't suspend; a spawned task would
   still block its thread) but may let the UI repaint; spec the
   simpler honest option.
4. UA token: `posting/<ver>` (wire-identical) vs `oxttp-tui/<ver>`
   (honest product) — corpus compat argues the former.
5. History: in-memory ring in S10 vs defer wholesale to S11.
6. Generated values `${$uuid}` etc. inside substitution — include
   (same engine) or defer with captures.
7. Env persistence: session-only active env (S10) vs write
   `environments.json` now.
