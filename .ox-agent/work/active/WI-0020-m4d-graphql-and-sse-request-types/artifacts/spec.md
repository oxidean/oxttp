# WI-0020 spec — M4d GraphQL and SSE request types

Implements corpus-posting §7.2 (GraphQL) and §7.5 (SSE) per ADR-0044.
Upstream references: `internal/model/graphql.go`, `internal/client/
sse.go`, `internal/client/http.go`, `internal/model/response.go`,
`internal/ui/response_messages.go`, `internal/collection/ckind.go`
@ 32c4566. Code-level details: `context/references/posting-graphql-
sse-semantics.md`.

## S1 — Collection: `PGraphQL.variables` becomes raw text

`core/collection/collection.oxl`:

- `PGraphQL.variables: own json.Json` → `variables: str` (own handle
  dropped; struct stays `own PGraphQL` elsewhere).
- `gql_dec`: `variables` decodes via `scal(pv, "graphql.variables")`
  (scalar-only — upstream `yamlString`; a map/seq node is now a decode
  error, matching upstream strictness). `query`/`operation_name`
  unchanged.
- Encode (`graphql` block writer ~L1297): `yput_str(gm, "variables",
  r.graphql.variables)` when non-empty (upstream `omitempty` — empty
  string omits the key).
- `jnode`/`yjson` helpers: `jnode` loses its only graphql caller —
  remove if unused; `yjson` stays (used elsewhere? verify; keep if
  referenced).
- Tests (`load_test.oxl`, `collection_test.oxl`): update variables
  cases to scalar strings (`variables: '{"id": "1"}'`), assert str
  round-trip; map-form input now expects a decode error.

## S2 — env: braced-only substitution

`core/env/env.oxl`:

- Add `substitute_braced(text, set) -> [str, err]`: identical scanner
  to `substitute` but only `${NAME}` refs expand (`$NAME` stays
  literal); `$$`→`$` and `${$gen}` behave as in `substitute`;
  unresolved → literal passthrough (never `in_url` error — upstream
  `SubstituteBraced` has no error path; callers that need strictness
  check `undefined` separately, which plan_req does not for bodies).
  Implementation: refactor shared scan or duplicate the loop with a
  `braced_only` flag — keep one code path.

## S3 — plan_req: GraphQL lowering (§7.1/§7.2)

`core/collection/collection.oxl` `plan_req`:

- `r.kind == "graphql"` proceeds; `grpc`/`websocket` keep the degrade
  error. GraphQL `r.method`/`r.body` are ignored (upstream `Normalize`
  resets Method/Body for the kind).
- After options parse (need `subbody`), build the document:
  - `gql_document(query, variables, operation_name) -> str` —
    `{"query":` + `json.tojson(json.jstr(query))` + optional
    `,"variables":` + (trimspace-empty omitted; `json.jparse` success →
    `json.tojson` compact; parse failure → raw spliced) + optional
    `,"operationName":` + `json.tojson(json.jstr(op))` + `}`.
    `json.tojson` does not HTML-escape — matches upstream
    `jsonString` (`SetEscapeHTML(false)`).
  - Substitution (only when `subbody`, upstream `resolve`):
    query → `env.substitute_braced`; variables → `env.substitute`;
    operation_name → none.
- `b = model.Body.Raw{ctype: "application/json", text: doc}`.
- Method: `rq.method = "POST"` for graphql regardless of `r.method`.
- Accept: after the jar-cookie block, if `!hdr_named(hdrs, "Accept")`
  push `model.Header{name:"Accept", value:"application/
  graphql-response+json, application/json"}` (upstream appends enabled
  Accept at Lower time = last among headers).
- URL/params/headers/auth/options/jar/proxy-degrade paths unchanged —
  GraphQL keeps FieldQuery ("Params"), FieldPathParams, FieldHeaders,
  FieldAuth, redirects/cookies/proxy per `Kind.Fields`.

## S4 — model: StreamEvent + warning class

`core/model/model.oxl`:

- `struct StreamEvent { at_ms: int, kind: int, title: str, body: []byte,
  content_type: str, event: str, id: str }` — kind: 0 sent, 1
  received, 2 info, 3 error (upstream MessageEventKind order differs;
  document ours). `at_ms` = `time.unix_ms()`; display formats
  `HH:MM:SS.mmm` local — implement `tui`-side or model-side formatter
  from unix_ms (civil-from-days algorithm; no std local-time helper —
  verify `std/time` during impl, else small formatter + test).
- `Resp` gains `events: own []StreamEvent` and `stream_error: str`
  (nil/"" for unary — `omitempty` parity).
- Warning status: `status_class` stays 0/1/2; add
  `graphql_status(resp) -> int` helper? Better: keep transport pure —
  add `fn warning_class(status: int, body: []byte, kind: str) -> int`
  in collection or model: returns 3 when `kind=="graphql"` (pass kind
  explicitly — Resp doesn't know the request kind) && 200<=status<300
  && body parses as JSON object with non-empty top-level `errors`
  array. Count errors for the title suffix (`1 error`/`N errors`).
  Implementation site: wherever status_class is consumed for display —
  `install_resp` (tui/coll.oxl) and `run` outcome (tui/cli.oxl). Store
  the error count on... simplest: helper returns `[class, count]` or
  the caller re-parses; spec: `collection.graphql_warn(body) -> int`
  returns error count (0 = none/not-graphql-body); callers compute
  `cls := model.status_class(resp.status); if kind==graphql && cls==0
  { n := collection.graphql_warn(resp.body); if n>0 { cls=3;
  title += " · "+itoa(n)+" error(s)" } }`.
  Class 3 renders yellow (same attr as class 1) — render.oxl maps
  `resp_class==3 → tf=3` (extend the `>=2→1` chain: 3→yellow too).

## S5 — core/http: SSE receive (buffered per ADR-0044)

`core/http/h1.oxl` + `core/http/wire.oxl` + new `core/http/sse.oxl`:

- **Deadline lift**: `TmoReader.deadline`/`TmoTlsReader.deadline`
  `int` → `shared` cell (`mkshared`); readers `sget` per read.
  `roundtrip` creates `dl := mkshared(deadline)` and passes it to
  `finish_roundtrip`; h2 path unchanged (h2_exchange keeps int
  deadline — SSE-over-h2 keeps the deadline; document as limitation
  OR lift there too if cheap — spec: h1 only, h2 SSE parses events but
  keeps timeout; note deviation... actually simplest correct: pass the
  shared cell into h2_exchange too if its reads go through a deadline
  param — check during impl; fallback = h2 keeps deadline, recorded).
- In `finish_roundtrip`, after head parse: `sse :=
  media_type(hdr_get(h.headers,"content-type")) == "text/event-stream"
  && req.method != "HEAD"`. If sse → `sset(dl, 0)` (lift) BEFORE body
  read.
- Body read: for sse, cap at 64 MiB — add `read_eof_cap`/`read_chunked`
  limit or post-truncate: spec = wrap reads so `len(body) > 64MiB` →
  truncate to 64MiB and set `stream_error = "SSE response exceeded
  64.00 MB"` (upstream `model.FormatBytes` → "64.00 MB"). Implement a
  `max_body` param variant: `read_eof(r, cap)` — change signatures of
  read_eof/read_chunked/read_exact? Minimal diff: add `read_eof_limited`
  used only for SSE EOF framing; chunked SSE rare but must cap too —
  simplest uniform: read fully then if sse && len>64MiB truncate +
  flag (memory exposure accepted? 64MB+ unbounded read is bad — a
  malicious stream could OOM. Compromise: for sse use a bounded
  reader wrapper `cap_reader{br, remaining}` that returns eof at cap —
  then existing read_* work unchanged and body stops at 64MiB; flag
  truncation when the cap hit before natural EOF. For chunked, cap
  applies to DECODED bytes — wrapper on br caps compressed bytes;
  chunked decoded ≤ compressed-ish; acceptable: cap raw reads at
  64MiB, decoded could exceed slightly for tiny chunks — note edge).
  Simpler still and faithful enough: since upstream caps the DECODED
  stream at 64MiB+1 via LimitedReader on sseBody output, our
  decode_body output is what matters — cap post-decode: read raw
  unbounded→ decode → if decoded >64MiB truncate+flag. Raw unbounded
  is the risk; SSE bodies are text, typically small; a hostile peer
  could send 10GB. Mitigate: cap raw read at, say, 64MiB for sse too
  (compressed could legitimately exceed? gzip of repetitive SSE could
  compress 64MB→small; raw cap 64MB could truncate a legit large
  stream whose decoded is <64MB? decoded>raw for gzip? No — gzip
  decoded ≥ raw typically for text? Not guaranteed. Upstream caps
  DECODED at 64MB regardless of raw size. To be safe: cap raw at 64MB
  AND decoded at 64MB — a >64MB-raw stream gets truncated early; mark
  stream_error either way. Deviation: raw>64MB truncated even if
  decoded would fit — acceptable, note it.)
- After `decode_body`: if sse → `parse_sse(db)` → events + optional
  stream_error; store on Resp. Seed events with `{kind:info,
  title:"Stream connected"}` FIRST and append terminal event:
  `{kind:info, title:"Stream ended"}` on clean EOF;
  `{kind:error, title:"Stream interrupted: <err>"}` +
  `stream_error=<err>` on parse error. (Upstream also has "Stream
  stopped" for cancel — N/A buffered.)
- `parse_sse` port (`sse.go` semantics): line scanner over decoded
  text — implement without bufio.Scanner (oxl): split decoded body on
  `\n`, handle `\r` strip + LF-after-CR (the skipLF trick ≈ strip one
  trailing `\r` per line; upstream's scanner consumes `\r` then
  optional `\n` — equivalent to trimming a single trailing `\r`),
  BOM strip on first line, `:` comments skipped, fields `data:`/
  `event:`/`id:` (`retry:`+unknown ignored), `data` lines joined `\n`,
  blank line dispatches only when accumulated data non-empty,
  `id` rejects `\x00`, event name defaults `message`, per-event size
  cap 1 MiB (sum of line lengths per event), total events cap 10 000
  (`maxLogEvents`), content_type `application/json` when body parses
  as JSON else `text/plain`. `at` = now per event.
- Non-SSE bodies: 64MB cap — upstream caps ALL bodies at maxBodyBytes;
  our current h1 reads unbounded — keep existing behavior for non-SSE
  (out of scope; note).
- h2 path (`h2_exchange`): detect event-stream after HEADERS; keep
  deadline (no lift — documented) OR lift if the deadline is a param
  — implement events parse post-body identically via shared
  `sse_finish(resp)` helper so both transports emit events.

## S6 — TUI: GraphQL editors + send path

`tui/types.oxl`, `tui/app.oxl`, `tui/coll.oxl`, `tui/render.oxl`:

- `RDraft`+`App` gain `gql_query: TextView`, `gql_vars: TextView`,
  `gql_op: LineEdit` (operation name single-line). Snapshot/restore
  (`app.oxl` ~L160-210) copies them (`copy_tv`, LineEdit copy —
  check existing copy helper or add).
- `req_tabs(KGraphql)` → upstream order: `Query`, `Variables`,
  `Headers`, `Path`, `Params`, `Auth`, `Info`, `Options` (own tabs
  first per `requestTabList`; "Query" tab = document+operation,
  "Variables" = JSON textarea; "Params" = URL query KV — the old
  "Query" KV slot is renamed "Params"). Wait — verify upstream order:
  `tabs = append(tabs, e.tabs()...)` then shared tabs — own first.
  Jump letters stay positional (deviation, ADR-0044).
- Tab content: `Query` → operation LineEdit row + gql_query TextView;
  `Variables` → gql_vars TextView; `Headers`/`Params`/`Path` → KV
  tables; Auth/Info/Options static. `req_pane_bindings`: treat
  Query/Variables like Body (tv-* + enter newline + f3/f4 optional —
  upstream has external-editor/pager on text areas; bind f3/f4 same as
  body for parity-lite); `Params` joins the KV branch (rename check
  `name == "Query"` → `"Params"` for graphql, keep "Query" for http).
- Render (`render.oxl` req pane): add cases for the two new tab names
  when `a.kind==KGraphql` — draw `gql_op` LineEdit + `gql_query`
  lines, or `gql_vars` lines. Reuse existing tv render helpers.
- `draft_to_request`: for KGraphql, build `r.graphql =
  PGraphQL{query: join_lines(gql_query.lines), variables:
  join_lines(gql_vars.lines), operation_name: gql_op.text}` — create
  fresh `own PGraphQL` each send (don't alias preq's). Non-graphql
  kinds: `r.graphql = nil`? Currently `r.graphql = a.preq.graphql`
  verbatim — keep for loaded files; for KGraphql override with live
  fields. Also `r.body` must NOT be written for graphql (upstream
  Normalize drops Body) — the `locked` logic already skips body for
  non-http kinds? `locked` checks preq.body.has_content — graphql
  files have no body block → fine; but ensure `(a.kind == KHttp ||
  a.kind == KWs)` gate already excludes graphql — yes it does.
- Loading a graphql file into a draft: populate gql_* widgets from
  `preq.graphql` (find the draft-fill path — `open_request`/load —
  add graphql branch).
- Kind switch: entering KGraphql seeds empty gql fields; leaving
  keeps them (per-tab draft state already handles).
- `install_resp`: compute warning — needs request kind: use
  `a.pending_preq.kind` (still set at install time? `install_resp`
  runs before `a.pending_preq = nil` — yes, capture kind early) or
  stash `a.last_kind`. `resp_class` 3 path + title suffix.
- `send_failed` unchanged.

## S7 — TUI: Messages/Events response tab (SSE)

`tui/types.oxl`, `tui/app.oxl`, `tui/coll.oxl`, `tui/render.oxl`,
`tui/keymap`-adjacent bindings in app.oxl:

- `App`+`RDraft` gain `resp_events: []model.StreamEvent` (or `own`),
  `msg_detail: int` (-1 = list), `msg_following: bool`. Snapshot/
  restore copies (events slice copy).
- Tab label rule (upstream `responseTabs`): when `len(resp_events)>0`,
  first tab label = `"Events"` if response CT is `text/event-stream`
  else `"Messages"`. Implement `resp_tab_label(a, i)` helper used by
  `render_tabstrip` call site + `resp_tabs()` consumers that compare
  names — cleaner: keep `resp_tabs()` names static and special-case
  index 0 in render + bindings via `has_events(a)`.
- Content: tab 0 with events && `msg_detail < 0` → message rows:
  format per upstream — `<glyph> <preview>    <HH:MM:SS.mmm>` where
  glyph: received `↓`, sent `↑`, error `!`, info `·`; preview =
  `event + " · " + title-or-body[:256]` whitespace-collapsed; SSE seed
  events (Stream connected/ended) have empty event/id. Rows render
  through the same selection-rows path as Headers (reuse
  `resp_rows_active`/`resp_row_count` returning `msg_rows(a)` when
  tab0+events+!detail). Colors: our renderer is single-fg; use attr
  dim for info rows? Keep monochrome + glyph (note simplification).
- `msg_detail >= 0` → tab 0 renders event body: first line
  `<glyph> <Kind> · #<n>      <time>` + optional `event · ID: x`
  metadata line + body text via `resp_view` (reuse: on enter, set
  `resp_view` to event body lines — but resp_view is shared; store
  `msg_saved_view`? Simpler: detail renders `a.msg_detail_body: str`
  lines through the same resp_view lines mechanism — set
  `a.resp_view = new_text_view(detail_text)` on enter and restore on
  escape? Restoration cost: rebuild from `resp_body`. Acceptable:
  detail enter → `a.resp_view` = detail text; escape → resp_view =
  prettified resp_body again (recompute via same code path — extract
  `resp_body_text(a)` helper). Hmm — resp_body for SSE = raw SSE
  text; restoring is just re-join. OK.)
- Keys (resp pane, tab0+events): `up/k down/j` move `resp_rows.sel`
  (unfollow when moving off bottom), `enter` → detail, `f` → follow
  (sel=last, top=bottom, following=true), `escape` → detail=-1 (when
  in detail) else normal. `g/G` optional.
- Follow semantics (buffered): install sets sel=last & following=true;
  any sel move upward sets following=false; `f` repins. Unread count
  always 0 post-install (no live arrivals) — omit unread badge
  (deviation note: meaningless without live stream).
- History: `HistEnt` gains nothing — events don't persist to disk
  history (upstream does via JSON events; our disk format stores
  response text — record deviation). Session history reopen shows
  body text only.

## S8 — CLI `run` subcommand + --json

`tui/cli.oxl`:

- plan_req now returns graphql reqs — run picks them up free.
- `resp_json`: add `"streamError"` when `resp.stream_error` non-empty
  and `"events":[{at,kind,title?,body?,contentType?,event?,id?}]`
  when `len(resp.events)>0` (upstream remote.Response shape;
  `at` = unix ms, body as string when UTF-8 else base64 — match
  bodyBase64 convention per event? upstream MessageEvent.Body is
  []byte → JSON marshals base64 automatically! Check: Go []byte →
  base64 string in encoding/json. So event body = base64 ALWAYS.
  Match that.)
- GraphQL warning in run outcome: upstream `run` fails on
  status_class error/warning — "a GraphQL/gRPC 'error' status still
  passes unless a declared capture fails" (corpus §line 63) — wait,
  re-read: failures = status_class error OR warning → `failed`?
  Corpus line 63: "failures; a GraphQL/gRPC 'error' status still
  passes unless a declared capture fails" — ambiguous; upstream run.go
  decides. Check upstream run outcome code during impl; default:
  warning counts as failed like error (StatusClassWarning is not OK).
  TUI toast equivalent n/a.
- `resp_json` `status` string: upstream Status.Text for warning =
  "N error(s)" — our status field is `"<code> <reason>"`; keep HTTP
  reason (deviation ok? upstream remote.Response.status is int +
  separate text... keep simple: statusCode/status unchanged; add
  `"statusClass":3`? Upstream JSON has no class field — skip).

## S9 — parity matrix + docs

- `.ox-agent/context/specs/parity-matrix.md`: §7.2 GraphQL `post`→
  `done` (M4d), §7.5 SSE `post`→`done` — with deviation footnote
  pointing at ADR-0044.
- `docs/corpus/corpus-posting.md` stays untouched (corpus is the
  contract, not the status board).

## Deviations (all recorded in ADR-0044/spec)

1. SSE events materialize at stream end/cap, not live (D1).
2. Jump letters positional, not upstream fixed per-tab (D2).
3. Session history doesn't persist events/streamError (D3).
4. `unread` badge omitted (no live arrivals) (D4).
5. SSE raw-body cap 64MiB may truncate before decoded cap on
   pathological compression (D5).
6. h2 SSE keeps request deadline (no post-header lift) unless impl
   shows the shared cell reaches h2 cheaply (D6).
7. Message rows monochrome (glyph-only kind distinction) (D7).
8. `variables:` map form now rejected (upstream-faithful tightening,
   not a deviation — call out in spec notes).
9. `run --json` emits an `events` array upstream's `remote.Response`
   does not carry (upstream emits `streamError` only; verified
   `internal/remote/protocol.go` @ 32c4566). Additive extension —
   upstream-shaped consumers ignore it; kept because the spec
   originally called for it and it aids headless stream debugging.
   Event wire shape is ours: `at` unix-ms int, `kind` int
   (0 sent/1 received/2 info/3 error), `body` base64 (matches
   upstream `[]byte` JSON marshaling).

## Test plan (per leaf package, `oxl test`)

- `core/collection`: gql_dec str variables + strict map rejection;
  encode round-trip; plan_req graphql → POST + document JSON exact
  (query/variables/operationName order, compaction, verbatim invalid
  JSON, omission rules, Accept append vs explicit Accept, substitution
  braced-vs-full + substitute_body_variables=false); grpc/ws still
  degrade.
- `core/env`: substitute_braced ($NAME literal, ${NAME} expands, $$→$,
  ${$gen}, unresolved passthrough).
- `core/model`: status_class unchanged; StreamEvent shape.
- `core/http`: SSE fixture tests — event/data/id/retry/comments/
  multi-line/CRLF/BOM/empty-data-drop/1MiB event cap/10k event cap/
  64MB cap/stream_error/seed+terminal events; non-SSE unaffected;
  deadline lift (slow SSE body past timeout_ms still completes);
  content-encoding gzip SSE.
- `tui`: draft_to_request graphql fields; draft snapshot; install_resp
  warning class 3 + title; message rows formatting; tab label swap;
  msg_detail enter/escape; cli resp_json streamError/events.
- Golden/e2e: existing suites must stay green.
