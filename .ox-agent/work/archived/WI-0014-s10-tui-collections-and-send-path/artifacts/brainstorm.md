# WI-0014 brainstorm — S10 collections + envs + send path

Settled upstream: corpus-posting.md §5/§6/§7.1 is the contract;
schema types exist (`core/collection`, ADR-0010 verbatim); the
Transport port + H1 impl exist; every S10 wiring point is a named
degrade toast from S9 (ADR-0006/0024 — replaces, never removes).
This brainstorm picks: YAML parser shape, package layout for
collection/env IO, draft↔file↔wire translation layering, send UX
under a blocking transport, UA token, history scope, generated
values, env persistence, and argv handling.

## Q1 — YAML engine shape

### Option A — generic DOM subset parser in `core/yaml` (CHOSEN)

New leaf `core/yaml`: `parse(text) -> [own YNode, err]` producing a
small DOM (`YNode{kind: scalar|map|list, s, pairs: []YPair, items:
[]own YNode}` — ordered pairs since oxl has no str-maps), plus
`emit(node) -> str` for marshal. Subset pinned to what Posting 3
reads/writes: block maps by indent, `- ` sequences, plain +
`'…'`/`"…"` scalars, `|`/`>` block scalars, `key:` empty-value
(= empty map/null), comments, `#` inside plain scalars only after
space, bools/ints/floats/null as string-typed scalars (decode side
coerces per field — DOM keeps the lexical text + tag hint). No
anchors/aliases/tags/flow `[]`/`{}`/multi-doc — encountering them
is a *parse error* which upstream also surfaces as a malformed file
(node placeholder), not a crash.

`core/collection` gains `decode(node)->[own PRequest,err]` +
`encode(req)->YNode` (omitempty marshal per §5.2) + `scan(dir)`
+ `load_file(path)` + `save_file(path,req)`. S11's `config.yaml`
(40 keys) reuses the same DOM parser — paying the generic cost
once. Fixtures in `tests/` pin the grammar.

Pros: testable DOM, one grammar for two consumers, parse errors
localize to file (corpus §5.1 placeholder rule needs error-with-
position anyway). Cons: larger than a purpose-built reader.

### Option B — purpose-built `PRequest` reader inside collection (REJECTED)

A single-pass indent walker emitting PRequest directly: smaller
today, but S11 config + any future `remote`/run surfaces re-parse
YAML; decode errors couple grammar to schema. Rejected: the DOM
split costs little and matches corpus layering (format.go ↔
kinds.go).

## Q2 — package layout for env + substitution

### Option A — new leaf `core/env` (CHOSEN)

`core/env`: dotenv reader (`parse_dotenv(text) -> []model.KV` —
`export `, `'`/`"` quoting, `#` comments, `${OTHER}` refs resolved
against earlier layers), layer stack (`EnvSet{layers: []EnvLayer{
name, source, vars}}` — posting.env → posting.local.env →
`<name>.env` → `<name>.local.env` → session, insertion order kept
for the variables screen), discovery (`scan_envs(dir)` finds env
names + base files), and `substitute(text, set, in_url) ->
[str, err]` implementing §6.2: `$NAME`/`${NAME}`, `$$` literal,
>10000 refs or >16 MiB aggregate = error, unresolved → err when
in_url else literal passthrough. Generated values (`${$uuid}`,
`${$timestamp}`, `${$timestampMs}`, `${$isoTimestamp}`,
`${$randomInt}`) resolve in the same pass via `crypto/rand` +
`time.unix*` (isoTimestamp needs a small civil-from-days formatter —
no RFC3339 in std).

Pros: headless-testable, single home for §6 semantics; session
layer is just another EnvLayer. Cons: none vs. inlining into
collection (env files aren't collection files — separate concerns).

### Option B — env code inside `core/collection` (REJECTED)

Corpus keeps `internal/env` separate from `internal/collection`;
folding them makes the package do two jobs and hides the S11
config consumer (config.yaml keys are not collection either).

## Q3 — draft ↔ file ↔ wire layering

### Option A — PRequest as the pivot (CHOSEN)

`core/collection` gains `to_draft`-adjacent helpers... concretely:
`tui/coll.oxl` holds `open_into_draft(PRequest)->RDraft` and
`draft_to_request(RDraft)->PRequest` (widget-state ↔ schema —
TUI types, lives in tui). `core/collection` gains
`plan_req(PRequest, env-set, jar) -> [model.Req, warns, err]` —
the send-time translation: scheme-less URL → `http://`, `:name`
path-param fill from path_params (values substituted), enabled
params → query string, enabled headers, body variant map
(content→Raw, form_data→Form, multipart→Multipart with
collection-relative file paths, file→FileBody), auth basic/bearer
→ Authorization (digest/oauth2 → degrade error), options →
follow/max_redirects/timeout_ms(×1000, default 5000)/verify
(verify_ssl false → "no"), `User-Agent` synth, Cookie from jar
when attach_cookies. Substitution runs inside plan_req against
the active EnvSet (URL/headers/auth always; body gated by
`substitute_body_variables`; never file contents).

Pros: file semantics + send semantics both headless-testable in
core; open/save/send share one representation; matches upstream
`model.Request → client` split. Cons: two translations (draft↔
PRequest, PRequest→Req) vs one — worth it, save+send reuse.

### Option B — draft → model.Req direct (REJECTED)

Skip PRequest at send: faster but splits file semantics
(enabled/options/exactly-one) from send semantics, duplicates them
in the save path, and puts corpus rules behind `package main`.

## Q4 — send UX under a blocking transport

### Option A — pending-send effect + painted "Sending…" frame (CHOSEN)

`send-request`/`url-enter` run plan-only inside dispatch: build
PRequest→Req; on plan error → error toast (no send); else stash a
pending plan on App and return a new effect `ESend`. The main loop
on ESend: pushes a "Sending …" status toast, renders + presents
(feedback before the freeze), then calls `exec_send(app)` which
blocks in `H1.send`, installs the response (or error text) into
the current tab's response state, appends in-memory history, then
the normal render presents it. Escape arriving mid-send sits in
the input queue — spec'd deviation vs upstream cancel (transport
can't suspend; §1.6/§3 documents the intent).

Pros: dispatch stays pure/testable (plan vs IO split); user sees
honest busy state; zero concurrency. Cons: UI freezes for the
exchange — bounded by the 5s default timeout + 30s dial cap.

### Option B — spawned worker thread (REJECTED)

Spawn a task for the send so input stays live: Transport.send
still cannot suspend (vtable), so the worker blocks its thread
while the UI thread would need channel/own-plumbing for the Resp
and an "in-flight/cancel" state machine — large complexity for a
cancel that still can't interrupt the socket. Defer to M4
(streaming kinds need async anyway — SSE/WS force the design).

## Q5 — User-Agent token

### Option A — `posting/<ver>` with OUR version string (CHOSEN)

Corpus §7.1 pins the product token (`posting/<ver>`); `<ver>` is
`shared/version.get()` — the oxttp build's version. Wire-identical
product token keeps the drop-in contract (a server that gates on
`posting/` sees one); spec calls out the version is oxttp's.

### Option B — `oxttp-tui/<ver>` (REJECTED)

Honest branding but deviates from the corpus-cited wire surface;
the corpus is the compat contract, not the product's self-name.

## Q6 — in-memory history in S10 (CHOSEN, bounded)

`App.history: []HistEntry{req snapshot, resp, file/context}` capped
at 100 (corpus MaxEntries — memory-only since `history.enabled`
config is S11 and always-on here, noted). MHistory modal lists
entries (method + URL + status + elapsed); `enter` opens the
as-sent request + its response into a preview tab; `backspace`
removes. No `<data>/history/<sha256>.json` persistence, no lock
sidecar — §5.3 disk format lands S11 with paths/config.

### Option B — defer history entirely (REJECTED)

The modal + bindings exist and every send already produces a
Req+Resp pair — the marginal cost is a slice + a render loop;
upstream-faithful v0.1 wants *some* history per the S10–S11 split.

## Q7 — env persistence

### Option A — session-only active env (CHOSEN)

`MEnvSwitch` lists discovered env names (`(none)` + `<name>` rows
from `*.env` files); picking sets `App.env_name` + rebuilds the
EnvSet for the session. `<data>/environments.json` remembered-env
file is S11 (paths/config territory); startup `--env`/`POSTING_*`
are S11 flags. Corpus-visible behavior in-session is identical.

### Option B — write environments.json now (REJECTED)

Drags `<data>` path resolution + a write schema into S10 for a
restart-convenience S11 owns anyway.

## Q8 — collection root resolution

### Option A — argv positional + `<data>/default` (CHOSEN)

`os.args(i)`: first non-`-`-prefixed arg = collection dir;
`-c`/`--collection DIR` also accepted since it's the same surface
(cheap: scan for the flag pair); `-e`/`--env` accepted for startup
named-env (same machinery the switcher uses). Other flags
(`-v`/`--version`, `-h`/`--help`, subcommands) keep the §1 surface
stubbed for S11 — `-v`/`--version`/`-h`/`--help` print the one-line
banner + usage and exit (current non-tty path already prints the
banner). Missing collection → `<data>/default` auto-created 0755
(`os.mkdir_all`), where `<data>` = `$XDG_DATA_HOME/posting` else
`~/.local/share/posting` (corpus §2.1). Env file search order per
§5.1: CWD → collection dir → config dir — S10 scans collection dir
(+CWD for `--env` file paths).

### Option B — no argv, always `<data>/default` (REJECTED)

Testing/dogfooding needs to point at fixture collections; the
positional is the corpus's primary interface anyway.

## Sub-decisions

1. **TreeNode payload**: add `path: str` (collection-relative file)
   + `kind: int` (dir/request/bad) + `err: str` (parse error text
   for placeholders). `stub` flag stays for the no-collection case.
   Tree build = `collection.scan` → sorted folder-first rows;
   filter `coll_search` narrows by name substring (already a Tree
   concern — extend `visible()` or rebuild nodes).
2. **Open/preview semantics (§8.6)**: `tree-open` on a request node
   loads PRequest→RDraft into the *current preview tab* if one is
   current else pushes a new preview tab; any draft-mutating edit
   flips `preview=false`; `keep-tab` pins. Multi-select opens all
   (one tab each, non-preview? — corpus: "multi-select opens all";
   choose preview-tab for the first, real tabs for the rest…
   simpler: all preview except upstream pins multi-open — spec
   picks: first selection reuses preview tab, rest get new
   non-preview tabs; documented).
3. **Save**: `save-confirm` marshals draft→PRequest→YAML at
   `<coll>/<folder>/<slug>.posting.yaml` (slug = name lowercased,
   non-alnum → `-`; `File` field overrides name when given —
   corpus dialog semantics), `Folder` may be new (mkdir_all);
   refuse overwrite? Corpus §8.3 save refuses to clobber only via
   remote; UI save writes over same-named file — spec: warn-and-
   overwrite via MConfirm when target exists.
4. **Duplicate/delete**: `d` writes a copy beside original
   (`<base> (copy).posting.yaml`, bumping `(copy N)` on collision)
   with `name:` gaining ` (copy)` per §5.2; `backspace`/`delete`
   MConfirm → `os.remove` + tree reload; open-tab for a deleted
   file stays as unsaved (§5.2). Folder delete/dup → degrade.
5. **Jar**: `App.jar: []str` (`name=value`), fed from Set-Cookie of
   every response when the sending request had attach_cookies —
   jar-lite (ADR-0023): no domain/path scoping, document in spec;
   explicit `Cookie:` header wins over jar rows for same names.
6. **Response tabs**: Body = decoded body (JSON re-indent via
   `encoding/json` when Content-Type json — prettify_json default);
   Headers = `resp.headers` rows; Cookies = `set-cookie` rows;
   Trace = the 7 `resp.trace` stages + hop count when redirects
   were followed. Pane title gains `<status> <reason> ·
   <size> · <elapsed>` (§4.15 FormatBytes/FormatDuration shapes:
   "1.23 KB", "45.67 ms"/"1.20 s").
7. **Variables screen**: rows from the active EnvSet —
   `name = value (source)`; `ctrl+r` reveal toggles masking
   (secret-looking names mask by default per §6.3 +
   `hide_secrets_in_value_preview`); `/` filter exists; `a`/`d`/
   `enter` (session-var ops) stay degrade toasts — session values
   layer is S11 config-adjacent.
8. **URL-bar preview**: resolve the URL text through the active
   EnvSet live (unresolved → `(unresolved $NAME)`), masking
   secret-looking values; `substitute_body_variables` doesn't
   affect the preview (URL always substitutes).
9. **Auth pane**: render loaded auth (type + masked fields);
   editing degrades "auth editing lands S11" — Auth tab content is
   file-driven this stage. Options pane likewise renders the
   request's options block read-only.
10. **oxl quirks**: `mkslice(Qualified.Type)` broken → build
    `[]own YNode` via push into locally-declared slices;
    `[v,e]=f()` shadows in blocks → fresh names + copy. `os.ls`
    returns sorted names — sort order for tree is ours anyway
    (folders-first needs a custom pass).
11. **`no row left behind`**: every previously-degraded binding
    that S10 makes real gets its toast removed; anything still
    deferred keeps an explicit toast — spec enumerates final
    degradation table.

## Risks / disagreements preserved

- Blocking send vs upstream async+cancel — largest UX deviation;
  escape-queues behavior documented in spec + findings.
- YAML subset WILL reject valid-YAML constructs (anchors, flow
  collections, multi-doc) that upstream's parser accepts —
  placeholder-row degrade matches §5.1's malformed-file path so
  the failure mode is corpus-shaped, but a spec caveat records it
  + upstream finding for a real YAML port.
- Jar-lite lacks RFC 6265 scoping (same-shape gap as ADR-0023 —
  consistent, documented).
- Generated values included: corpus marks them P3-only extras, but
  they ride the same substitution pass; cost = `crypto/rand` +
  small formatters. Disagreement noted: strictly they're extras —
  keeping them is fidelity-positive for hand-authored files.
