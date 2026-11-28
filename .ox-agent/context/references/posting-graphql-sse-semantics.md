# Posting GraphQL + SSE code-level semantics (M4d reference)

Verified against `/tmp/oxttp-corpus/posting-src` HEAD 32c4566
(v3.0.0-beta.1) — `internal/model/graphql.go`, `internal/client/
sse.go`, `internal/client/http.go`, `internal/model/response.go`,
`internal/model/substitute.go`, `internal/ui/kind_graphql.go`,
`internal/ui/response_messages.go`. Corpus: docs/corpus/
corpus-posting.md §7.2, §7.5, §4.1/4.2/4.15.

## GraphQL document build (model/graphql.go)

- POST JSON `{"query":<json-str>,"variables":<compact-or-raw>,
  "operationName":<json-str>}`; `Accept:
  application/graphql-response+json, application/json`.
- `variables`: trimspace empty → field omitted; parses as JSON →
  compacted; else spliced verbatim (string value kept raw).
- Substitution: query → `SubstituteBraced` (`${NAME}` only — `$name`
  GraphQL vars untouched); variables text → full `Substitute`
  (`$NAME`/`${NAME}`/`$$`/`${$gen}`); operationName → none. All gated
  by `substitute_body_variables`.
- Warning: 2xx + JSON body with non-empty top-level `errors` array →
  StatusClassWarning; status text = `<n> error(s)`.
- Request panel: Query tab (Operation line + document textarea),
  Variables tab (JSON textarea); no Body; Params tab replaces Body's
  slot in shared tabs. Jump letters: own tabs `i`/`o` first, then
  shared `q e r t y u` (Headers/Path/Params/Auth/Info/Options).
- `.posting.yaml`: `kind: graphql`, `graphql: {query, variables,
  operation_name}` — variables is a scalar string upstream
  (`yamlString`); strict decode rejects other keys.

## SSE receive (client/sse.go, http.go, model/response.go)

- Trigger: response `Content-Type: text/event-stream` and method !=
  HEAD; body read via `receiveSSE` (incremental parse, not buffered).
- Parser: `event:`/`data:`/`id:`/`retry:` fields, `:` comments,
  multi-line `data:` joined with `\n`, CRLF tolerated, dispatch on
  blank line.
- Limits: `maxSSEEventBytes` = 1 MiB per event; `maxLogEvents` caps
  retained events; whole body 64 MB (`maxBodyBytes`) — over-cap →
  stream cancelled, `streamError` set, raw body truncated.
- `sseBody`: Content-Encoding decode incl. raw-deflate vs zlib
  detection.
- Timeout: request deadline covers connect+headers; SSE **lifts** it
  once headers arrive (stream may run unbounded).
- MessageEvent kinds: sent/received/info/error (`model/response.go`);
  each row: kind + timestamp + preview; `event:`/`id:` shown as
  metadata.
- Messages tab UI: `f` toggles follow-latest; `enter` inspects event
  body; `escape` returns to log; unread badge while unfollowed.
- `streamError` recorded on parser/transport failure; raw body always
  retained for the Body tab.

## oxttp integration notes

- `core/collection` already decodes `kind: graphql` strictly —
  `PGraphQL.variables` is a JSON node today; upstream treats it as
  text → likely needs `str` + raw-scalar decode.
- `core/env` has full `substitute` only — add braced-only variant for
  the query document.
- `core/http/h1.oxl` `finish_roundtrip` reads body to EOF under a
  single deadline — SSE needs post-header deadline lift (shared
  deadline cell or post-hoc parse) + 64 MB cap + event parse.
- `Transport.send` is synchronous; TUI send runs on UI thread —
  live-follow needs either buffered events at EOF or send off-thread.
- Jump letters currently positional (`jump-0..6`); upstream GraphQL
  letters are per-tab fixed — deviation candidate.
