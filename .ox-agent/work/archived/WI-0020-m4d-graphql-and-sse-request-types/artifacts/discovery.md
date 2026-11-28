# WI-0020 discovery — M4d GraphQL and SSE request types

Scope: implement Posting §7.2 (GraphQL `kind: graphql`) and §7.5 (SSE
`text/event-stream` responses) for the oxttp TUI/CLI, flipping the
parity matrix rows `§7.2 GraphQL` and `§7.5 SSE` from `post` to done.
Corpus source: `docs/corpus/corpus-posting.md`; upstream verified
against the pinned Posting 3 clone (`v3.0.0-beta.1` @ 32c4566):
`internal/model/graphql.go`, `internal/client/sse.go`,
`internal/client/http.go`, `internal/model/response.go`,
`internal/model/substitute.go`, `internal/ui/kind_graphql.go`,
`internal/ui/response_messages.go`. oxl language facts verified against
toolchain v0.26.0 sources + `docs/semantics/concurrency.md` in the
oxidean/oxl repo.

## Corpus contract (verified vs upstream source)

### §7.2 GraphQL

- `kind: graphql`; request is POST of JSON `{query, variables,
  operationName}`; `Accept: application/graphql-response+json,
  application/json` (the corpus summary says `application/json`; the
  upstream `document()`/`wire` code emits the full
  `application/graphql-response+json, application/json` pair — follow
  the source).
- Params tab replaces Body in the request panel; upstream Query tab =
  Operation input + document textarea; Variables tab = JSON textarea
  with variable completion.
- Variable substitution differs per field (`substitute.go`):
  `SubstituteBraced` (`${NAME}` only) for the **query document** — so
  `$name` GraphQL variables are NOT Posting variables — while the
  **variables** text uses full `Substitute` (`$NAME`, `${NAME}`, `$$`,
  `${$gen}`). `operationName` is not substituted. All honour
  `substitute_body_variables`.
- Warning status: 2xx response whose JSON body has a non-empty
  top-level `errors` array → `StatusClassWarning` (transport-OK but
  app-level errors), surfaced in the status line.
- Body `variables` JSON: compacted (whitespace-stripped) if it parses
  as JSON, otherwise spliced verbatim into the document (upstream
  keeps it a raw string to preserve e.g. GraphQL variable shorthand).
- Collection decode already accepts `kind: graphql` strictly
  (`core/collection/collection.oxl` `PGraphQL` with `query`,
  `variables`, `operation_name`) — BUT `variables` is currently decoded
  as a JSON/YAML node, not the raw text upstream treats it as. Verify
  against `internal/model/collection.go` whether upstream stores it as
  a string; the TUI Params editor edits it as text.

### §7.5 SSE

- Response with `Content-Type: text/event-stream` (non-HEAD) streams:
  events parsed incrementally (`event:`/`data:`/`id:`/`retry:` fields,
  comments, multi-line data, CRLF), each event → a Messages row
  (sent/received/info/error kinds per `model/response.go`).
- `event:`/`id:` metadata captured; `id` retained for `f` resume-follow
  semantics; `streamError` recorded on truncation/parse failure; raw
  body retained.
- Limits: per-event 1 MiB (`maxSSEEventBytes`), total events capped
  (`maxLogEvents`), 64 MB body cap — truncation records
  `CANCELLED`/"response truncated at 64.00 MB".
- SSE **lifts the request timeout after response headers** — the
  deadline applies to connect+headers only; the stream may run
  indefinitely.
- Messages log UI (`response_messages.go`): rows have kind glyphs
  (↓ received / · info / ! error / ↑ sent) + timestamps; `f` toggles
  follow-latest; `enter` inspects an event body; `escape` back.
- Decompression: `sseBody` handles gzip/deflate (zlib-vs-raw detection)
  — our h1 already decodes Content-Encoding for bodies; SSE must reuse
  the same decode path.

## Current codebase state (verified)

- `core/collection/collection.oxl`: `PGraphQL{query,variables,
  operation_name}` decode/encode already strict; `plan_req` errors on
  non-HTTP kinds ("kind <k> sends land M4").
- `core/model/model.oxl`: `Body` enum has Raw/Form/Multipart — no
  GraphQL notion; `Resp` has no `events`/`stream_error` fields.
- `core/http/h1.oxl` `finish_roundtrip` reads the whole body to EOF —
  no incremental streaming; request deadline (`TmoReader.deadline`)
  covers headers+body.
- `tui/`: `KGraphql=1` kind exists with tab set
  Headers/Params/Path/Query/Auth/Info/Options (upstream: Query,
  Variables, Headers, Path, Params, Auth, Info, Options — own tabs
  first, Body absent); method menu index 7 + `kind-graphql` action sets
  method=POST; `plan_req`/`begin_send_preq`/`exec_send_t` in
  `tui/coll.oxl` don't handle graphql yet; `RDraft` lacks GraphQL fields.
- Response tabs: Body/Headers/Cookies/Trace — no Messages tab.
- Jump letters are positional (`jump-0..6` = q w e r t y u) — upstream
  GraphQL letters are per-tab fixed (`i`=Query doc, `o`=Variables,
  `r`=Params…); will need per-kind letter mapping or accept positional
  mapping as a documented deviation.
- `core/env/env.oxl` `substitute` is the full form; need a braced-only
  variant for the GraphQL query document.

## Key technical findings

- oxl has real channels/`select`/`spawn` (`docs/semantics/concurrency.md`,
  `chan own T` carries owned payloads) — a spawned SSE reader could
  stream events into the TUI, but `Transport.send` is a synchronous
  interface method (interface methods cannot suspend), and the send
  path runs inside the UI thread. Two candidate designs:
  (a) buffered: `send` parses the complete decoded SSE body into
  `Resp.events` at EOF (timeout lifted post-headers, 64 MB cap, per-
  event caps enforced by the parser) — semantics-faithful, no live
  incremental paint; (b) spawned reader + channel into the UI — true
  "followed live" but requires restructuring send off the UI thread.
  Decision deferred to brainstorm/ADR; default lean is (a) with a
  recorded deviation unless (b) proves cheap.
- `poll(2)` is callable via `extern fn` with an `[]int` slice trick
  (slice len becomes `nfds`, elements pack pollfd bitfields) — viable
  but fragile; not needed for design (a).
- `time.unix_ms()` exists; no obvious local-time formatter in
  `std/time` — event timestamps may need `time.local` formatting or a
  small formatter; verify during implementation.

## Open questions for brainstorm

1. Live-follow (b) vs buffered (a) for SSE — cost of moving send off
   the UI thread vs corpus "followed live" wording.
2. `PGraphQL.variables` representation: raw string vs JSON node —
   upstream treats it as text (compacted only at document build).
3. Jump-letter mapping for GraphQL's 8 tabs (positional vs upstream
   fixed letters).
4. Warning-status plumbing: `Resp.status_class` needs a Warning value
   + render mapping (upstream `StatusClassWarning`).
5. Whether CLI `--json`/headless paths also emit events/stream_error
   (upstream `run --json` Response shape includes `streamError`).

## Findings summary

Collection decode/encode for `kind: graphql` already exists and is
strict; the gap is (1) `plan_req` lowering GraphQL → HTTP request
(document JSON + Accept + braced-vs-full substitution + warning
status), (2) `PGraphQL.variables` text representation, (3) TUI
Query/Variables editors + Params tab, (4) SSE parser + `Resp.events` +
Messages tab + timeout lift + caps, (5) parity-matrix flips.
