# WI-0014 spec — S10 TUI collections + environments + send path

Direction: ADR-0030 (`core/yaml` DOM subset), ADR-0031 (`core/env`
dotenv + substitution), ADR-0032 (synchronous send via `ESend`;
PRequest pivot). Contract: corpus-posting.md §4.9–4.15, §5
(collections), §6 (environments), §7.1 (HTTP send). **S10 = real
collection IO + env layers + real HTTP(S) send rendered in the
response pane.** Config file (40 keys), flag surface, disk history,
captures, streaming kinds, OAuth/digest, GraphQL send are
S11/M4/post — each keeps an explicit degrade (ADR-0006/0024).

## Files

New core leaves (ADR-0016 layout):
- `core/yaml/yaml.oxl` — DOM (`YNode`/`YPair`), `parse`, `emit`.
- `core/yaml/yaml_test.oxl` — grammar + emit round-trip tests.
- `core/env/env.oxl` — `parse_dotenv`, `EnvSet`/`EnvLayer`,
  `scan_envs`, `substitute`, generated values.
- `core/env/env_test.oxl`.

Grown packages:
- `core/collection/collection.oxl` — + `decode(YNode)->PRequest`,
  `encode(PRequest)->YNode`, `load_file`, `save_file`,
  `scan(dir)->CollScan`, `plan_req(PRequest,EnvSet,jar)->SendPlan`.
- `core/collection/load_test.oxl` — fixtures + decode/plan tests.

TUI (`package main`):
- `tui/coll.oxl` — draft↔PRequest, tree build from `CollScan`,
  open/dup/delete/save file ops, env set assembly, jar, history
  store, `exec_send`, response install. + `tui/coll_test.oxl`.
- `tui/types.oxl` — App/TreeNode/RDraft field additions.
- `tui/app.oxl` — replace S10 degrade branches; `ESend` effect.
- `tui/render.oxl` — sidebar req rows, response tabs, env list,
  variables rows, URL preview substitution, response pane title.
- `tui/main.oxl` — argv collection resolution, `ESend` handling.
- `tui/send_test.oxl` — plan/response-install/preview cases.

Fixtures: `tests/tui-fixtures/` — a small collection tree (nested
folder, several `.posting.yaml` covering every body kind + auth +
options + malformed file, `posting.env`, `dev.env`,
`dev.local.env`).

## YAML subset (core/yaml)

DOM: `YNode{kind:int(0=scalar,1=map,2=list), s:str,
pairs:[]YPair{key:str,val:own YNode}, items:[]own YNode,
line:int}`. Ordered pairs (no str-maps in oxl).

`parse(text) -> [own YNode, err]` — pinned grammar:
- block map: `key:` / `key: value` at consistent indent; deeper
  indent = child; a `key:` with nothing deeper → empty scalar
  (`s=""`, kind scalar — decode coerces).
- block seq: `- ` items at an indent; item may be scalar, `key: v`
  inline-map-start (continuation lines at item indent+2 merge into
  the item map), or a nested block.
- scalars: plain (trimmed, stops before ` #`), `'…'` (verbatim,
  `''`→`'`), `"…"` (escapes `\n \t \" \\ \r`), `|` literal +
  `>` folded block scalars (indent-determined, chomp per YAML:
  keep trailing newline for `|`, single-space join for `>`).
- comments: `#` at line start or after whitespace ends content.
- tabs in indentation = parse error. Anything else YAML-legal but
  out-of-subset (anchors `&`/`*`, tags `!`, flow `[`/`{`,
  multi-doc `---`/`...`) = parse error carrying line number.
- scalars keep lexical text; no implicit typing in the DOM —
  `true`/`5`/`5.0`/`null` decode at the schema layer.

`emit(node) -> str`: maps as `key:`/`key: value` by indent,
seqs as `- `, scalars plain when safe (`[A-Za-z0-9]`-ish charset,
no leading/trailing space, not a bool/null lookalike when a
string is intended — encode marks string-ness), else
double-quoted; multi-line strings as `|` block scalars.
Emit never wraps lines and preserves key insertion order — the
omitempty marshal relies on it.

## Collection package (core/collection)

`decode(YNode) -> [own PRequest, err]`:
- Unknown top-level keys → error (upstream strict-ish decode is
  schema-known keys; corpus lists 17). Nested strictness per
  corpus: `graphql`/`grpc`/`websocket` unknown key = error; other
  blocks tolerate… no — corpus pins strict decode only for those
  three; remaining blocks decode known fields and ignore unknown
  ones (matches `format.go`'s per-block decoders).
- `method` uppercased + validated ∈ {GET,POST,PUT,PATCH,DELETE,
  HEAD,OPTIONS} else error; missing → "" (default applied by
  consumer = GET).
- `body`: >1 of `content`/`form_data`/`multipart`/`file` present
  (has_ markers) → error "more than one body kind"; each multipart
  part needs exactly one of `value`|`file` → else error.
- `headers`/`params`/`path_params`: `[{name,value(,enabled)}]`
  rows; `enabled` default true.
- `options` defaults applied AT DECODE (corpus defaults are
  semantic, not schema): follow_redirects true, verify_ssl true,
  attach_cookies true, substitute_body_variables true,
  timeout 5.0 — explicit `false`/`0` honored. Track which were
  set so `encode` writes only non-defaults back (store a
  `set_mask: int` on POptions — additive field, ADR-0010 keeps
  the corpus keys verbatim, the mask is internal).
- `kind` ∈ {"",graphql,grpc,websocket} else error.
- `captures`/`variable_scope`/`scripts`/`auth` decode into the
  existing structs (auth blocks per `type`).

`encode(PRequest) -> own YNode` + `marshal(PRequest) -> str`:
omitempty — only non-default fields, corpus key order (name,
description, kind, method, url, headers, params, path_params,
body, graphql, grpc, websocket, auth, scripts, options, captures,
variable_scope).

`scan(dir) -> CollScan`: recursive walk, skipping dot-dirs,
`__pycache__`, `node_modules` (§5.1); entries = folders +
`*.posting.yaml` files; sort folders-first-then-alpha at each
level (corpus). `CollScan{root: str, nodes: []CollNode{path, rel,
depth, is_dir, req: own PRequest, err: str}}` — `err != ""` marks
a malformed placeholder row (§5.1). `load_file(path)` reads +
yaml.parse + decode (empty file → error row "empty file").
`save_file(path, req)` marshals + `writefile_` (parent dirs via
`mkdir_all`).

`plan_req(PRequest, env: EnvSet, jar: []str, coll_dir: str) ->
SendPlan{req: own model.Req, warns: []str, err: str}`:
- `kind != ""` → err "kind <k> sends land M4" (degrade path).
- URL: `substitute(url)`; empty after sub → err; scheme-less →
  `http://` prefix (§7.1); `:name` segments replaced by
  substituted path_params values (queryescape per segment);
  enabled `params` appended as `?k=v&` (queryescape both halves),
  values substituted (passthrough-allowed per §6.2 query rule).
- headers: enabled rows, names/values substituted; then auth:
  basic → `Authorization: Basic b64(user:pass)`, bearer_token →
  `Bearer <token>` (both substituted); digest/oauth2 →
  err degrade. Caller-supplied `Authorization` row wins over
  auth block (matches h1's userinfo rule shape).
- body: content→`Raw{ctype: content_type else Content-Type
  header else ""}`; form_data→`Form`; multipart→`Multipart`
  (file paths resolved vs `coll_dir`); file→`FileBody` (exists
  pre-check via RenderBody). `substitute_body_variables` gates
  body substitution; file contents never substituted.
- options: `follow` + `max_redirects` (≤10; follow false → 0);
  `timeout` s → `timeout_ms` (×1000, ≤0 → 0 = transport default);
  `verify_ssl` false → `verify = "no"`; `proxy_url` non-empty →
  warn "proxy unsupported in this build — sending direct"
  (§7.1 proxy partial; CONNECT is WI-0013).
- `attach_cookies` → append jar `Cookie: n=v; …` unless an
  enabled Cookie header row exists (explicit wins).
- `User-Agent: posting/<shared/version.get()>` via `req.synth`
  when no UA header (ADR Q5 — corpus product token, oxttp
  version; deviation noted below).

## Env package (core/env)

`parse_dotenv(text) -> []model.KV`: `NAME=value` lines; `export `
prefix ok; `#` comments; `'`/`"` quoting (`"` allows `${REF}`);
unquoted values trim; `NAME` bare → `NAME=""`. `POSTING_*` names
→ warning row (§6.1) returned as `warns` list. `${OTHER}` in
values resolves against already-parsed vars in the same file then
prior layers (caller passes context).

`EnvLayer{name, source: str(file|session|host), vars: []model.KV}`;
`EnvSet{layers: []EnvLayer}` — `lookup(name)` walks layers
top-down (last-added wins = session layer appended last).

`scan_envs(coll_dir) -> EnvScan{base: []str(names of base files
present: posting.env/posting.local.env), named: []str}`: named
envs from `X.env`/`X.local.env` pairs — a name appears once even
when both exist.

`build_set(coll_dir, active: []str, session: []model.KV) -> EnvSet`:
posting.env → posting.local.env → for each active name: `<n>.env`
→ `<n>.local.env` → session layer. Missing files skipped (§6.1).
Env files searched: collection dir (S10; CWD-for-`--env`-file and
config-dir search noted as S11 completion).

`substitute(text, set, in_url) -> [str, err]`:
- `$NAME` (`[A-Za-z_][A-Za-z0-9_]*`), `${NAME}`, `$$`→`$`.
- `${$uuid}`→v4-shaped hex from `crypto/rand`; `${$timestamp}`→
  `time.unix()`; `${$timestampMs}`→`unix_ms`; `${$isoTimestamp}`→
  RFC3339 UTC from unix (civil-from-days); `${$randomInt}`→
  rand uint32 decimal.
- Unresolved name: `in_url` → err "unresolved variable $NAME";
  else passthrough literal. Expansion >10000 refs or >16 MiB →
  err.

## TUI glue (tui/coll.oxl)

- `resolve_coll_dir(argv)` → positional non-flag arg | `-c DIR` |
  `--collection DIR` | `<data>/default` (mkdir_all 0755); `-e`/
  `--env NAME|FILE` seeds `App.env_active` (repeatable, file
  paths load directly); `-v`/`--version`/`-h`/`--help` → banner
  text + quit. Unknown `-`-flags → startup toast "flag surface
  lands S11 — ignored: <f>".
- `load_collection(a)`: `scan` → rebuild `a.coll.nodes`
  (TreeNode + `path`,`kind`,`err` fields); envs → `scan_envs` +
  `build_set` into `a.env`; `env_name` = active names joined or
  "(none)". Preserves open folders by path across reloads.
- `tree-open`: request node → `load_file` → `open_into_draft`:
  fills url/method/kind/req_tab-safe/headers/query/path tables/
  body lines/body_ct + auth + options display fields on RDraft.
  Malformed node → error toast with `err`. Preview-tab rule:
  current tab preview → replace in place; else push new preview
  tab. Multi-select → first reuses preview, rest new non-preview
  tabs. `open` marks tab title = request `name` else file stem.
- `tree-dup`: request node(s incl. selection) → copy file beside
  original as `<base> (copy)[ N].posting.yaml` first-free-name,
  rewriting `name:` += ` (copy)`; folder → degrade.
- `tree-delete`: MConfirm → `os.remove` file + reload; an open
  tab for the file stays (unsaved, §5.2). Folder → degrade.
- `save-confirm`: name required (toast else); slug =
  lower alnum-keep else `-`; folder field → mkdir_all under coll;
  filename = `File` field else `<slug>.posting.yaml`; marshal
  draft→PRequest; exists → MConfirm overwrite first (dialog
  refuses silent clobber — deviation note); write + toast +
  reload; tab gains `path` + title = name, preview=false.
- `send-request`/`url-enter` (non-curl): `draft_to_request` →
  `plan_req` → err → toast; warns → info toasts; else stash
  `a.pending` and return `ESend`. URL bar text edits mark the
  tab non-preview.
- `exec_send(a)`: `H1.send(pending.req)` → on err install
  "request failed: <err>" into resp_view + error toast; on resp:
  resp_view = decoded body text (re-indent when
  `Content-Type: application/json`/ `+json` — `json.jparse` ok),
  resp_headers = resp.headers, resp_cookies = `set-cookie` rows,
  resp_trace = `resp.trace` + hop count; status_meta =
  `<code> <reason>`; jar update when attach_cookies; history
  append; title/statusline `size · elapsed` (FormatBytes/
  FormatDuration shapes). Then normal render.
- `hist entries`: `App.history: []HistEnt{title, req: PRequest,
  status: int, reason: str, elapsed_ms, size, resp_text}` cap 100
  (drop oldest). MHistory lists newest-first; `enter` opens a new
  preview tab w/ as-sent draft + response installed; `backspace`
  removes.
- `env-pick` (MEnvSwitch): rows = `(none)` + discovered names;
  pick → `env_active` replaced → `build_set` rerun → env_name
  updated → toast listing effective var count. `(none)` clears.
- variables screen rows: flattened EnvSet — `NAME = value
  [source]`; mask secret-looking names (NAME contains
  SECRET|TOKEN|PASSWORD|PASS|KEY — case-insens.) unless
  `vars_reveal`; `enter`/`a`/`d` still degrade (session-var ops
  S11).
- URL preview: resolved through `substitute(url_text, env,
  in_url=false)` — unresolved shows `(unresolved $NAME)`;
  secret-looking values masked (`hide_secrets_in_value_preview`
  default).
- Auth/Options request tabs: render read-only summaries of the
  loaded `PRequest.auth`/`options` blocks (type + masked fields /
  the 6 options + values); direct edits → degrade "edit lands
  S11".

## Response tabs content (§4.14–4.15)

- Body: decoded body → `resp_view` lines; JSON re-indented 2sp;
  non-UTF-8/large bodies → body as-is (64MB stream cap noted).
- Headers: `resp.headers` into `resp_rows` data.
- Cookies: `set-cookie` rows.
- Trace: 7 stage rows (connect/tls/send headers/send body/recv
  headers/recv body/closed) + `hops` count line when >0.
- Title: `response · <status> <reason> · <fmt-size> · <fmt-ms>`
  colored by `status_class` (green/yellow/red — draw_pane title
  color param).

## Updated degradation table (changes from S9)

Now **I**: send-request, url-enter send, tree-open/dup/delete,
save-confirm, env-pick, search-requests (→ sidebar focus +
search), reload-collection palette cmd, variables list,
history list/open/delete (in-memory), response body/headers/
cookies/trace tabs, url preview substitution.

Still **D** (explicit): kind sends (graphql/grpc/ws), digest +
oauth2 auth, proxy_url execution (warn-and-direct), clipboard
copies, f3/f4 handoffs, JSON tree view (e/E/Y + ctrl+f filter —
text view only this stage), image preview f2/s, response
search-input (ctrl+f — n/N nav works on last search), curl
import/export, auth/options pane editing, session-var add/edit/
revert, watch_collection_files/watch_env_files reload (no
fsnotify — reload-collection is manual), environments.json,
use_host_environment, capture execution (parsed, never run),
digest retry inside send (degrade), multipart/GraphQL/WS editor
panes (files open → their fields show read-only), histories on
disk, `keep-tab` unbound, `stream` (M4), `suspend`.

## Deviations recorded (explicit, per corpus-fidelity standard)

1. **Synchronous send** — no Escape-cancel; input queues (ADR-
   0032; freeze bounded by 5s default timeout / 30s dial cap).
2. **YAML subset** — anchors/aliases/tags/flow/multi-doc are
   malformed-file errors (corpus placeholder path), not
   constructs (ADR-0030); byte-compat scope = Posting-emitted
   shape + the corpus grammar.
3. **UA token** `posting/<ver>` with oxttp's version (ADR Q5).
4. **Jar-lite** — no domain/path scoping (ADR-0023 shape).
5. **History** memory-only, cap 100, no sha256/lock sidecar.
6. **Env persistence** session-only; `environments.json` S11;
   env-file search limited to collection dir this stage (§5.1
   CWD/config-dir legs noted).
7. **Save overwrites** require confirm (upstream UI saves
   directly; remote refuses — we pick the safer uniform rule).
8. **Auth/Options panes read-only** — edits degrade to S11.
9. **`--env` startup seeds session env**; full flag surface S11.
10. **Body send limit**: substitute limits enforced (§6.2);
    file bodies read whole (no streaming progress UI).
11. **64MB response cap** not enforced at transport — display
    holds full body (corpus caps streams; H1 closes per
    ADR-0019 anyway).
12. **Generated values** supported in substitution (P3-only
    extras upstream — fidelity-positive inclusion).

## Acceptance criteria

- `oxl build ./tui` + `oxl build ./cli` clean; `oxl test <dir>`
  green for every leaf dir (loop, not multi-arg).
- `core/yaml`: fixture corpus — every `.posting.yaml` in
  `tests/tui-fixtures/` parses; marshal(decode(x)) stable;
  block scalars/quotes/comments/nesting covered; each
  out-of-subset construct errors with a line number.
- `core/env`: dotenv edge cases (export/quotes/comments/refs/
  POSTING_* warn); layer precedence; substitute rules incl.
  `$$`, unresolved-in-url error vs passthrough, limits,
  generated values shape (uuid hex/ts digits/randomInt int).
- `core/collection`: decode every schema block; defaults applied;
  exactly-one-body errors; encode omitempty; plan_req maps
  options/auth/body kinds/params/path params/cookies; digest/
  oauth2/grpc errors.
- `tui`: open-into-draft round trip; preview-tab reuse rule;
  dup/delete/save file ops on fixture copy; tree filter;
  env-switch rebuild; send plan → `ESend`; exec_send installs
  body/headers/cookies/trace + jar + history into tab state;
  response tab content; URL preview masking.
- Golden: spin a loopback h1 test? — oxl tests can't bind a
  socket cheaply → `exec_send` is exercised via a stub
  Transport? Transport is an interface — tests use a fake
  `send()`? Interface dispatch is fine: `tui` tests build the
  plan path + response-install on a fabricated `model.Resp`.
  A real-network smoke is manual (documented in verify).
- Parity matrix rows §5/§6/§7.1 flip to `done` (or annotated
  partials) at ship; degrades that remain all carry toasts.
