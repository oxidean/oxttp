# ADR-0044 — SSE events parsed at stream end (buffered), live-follow deferred

- Status: accepted
- Date: 2026-11-27
- Work item: WI-0020 (brainstorm)
- Amends: none — extends the explicit-degradation convention (ADR-0006)
  to streaming responses

## Context

Corpus §7.5 (Posting `v3.0.0-beta.1` @ 32c4566,
`internal/client/sse.go`, `internal/ui/response_messages.go`) requires
SSE (`Content-Type: text/event-stream`) responses to stream events
into a Messages tab *live*: incremental parse, follow-latest default,
`f` resume-follow, `enter` inspect, `streamError` on failure, 64 MB
body cap, per-event 1 MiB cap, timeout lifted after response headers.

`Transport.send` is a synchronous interface method; the TUI invokes it
on the UI thread (`exec_send_t` → `plan_req` → `send`). oxl channels/
`select`/`spawn` exist, but making send asynchronous touches every
transport implementation and every send call site (history write,
capture evaluation, `run --json` completion). M4e (grpc/websocket,
WI-0021) will need that machinery regardless — interactive streams
cannot be buffered.

## Decision

Parse SSE **buffered at EOF**: `finish_roundtrip` detects
`text/event-stream`, lifts the post-header deadline, reads the decoded
body under the 64 MB cap, then runs a pure incremental-compatible
SSE parser producing `Resp.events` (`[]StreamEvent`) plus
`Resp.stream_error`. The Messages tab renders the complete list with
the corpus row format (kind glyph + timestamp + preview), `f` follow
toggle, `enter` inspect, `escape` back; raw body retained on the Body
tab.

Recorded deviation (spec + corpus-fidelity rule): upstream "followed
live" becomes "complete on close/cap" — events appear when the stream
ends or truncates. Never-closing streams behave like any long request
under the lifted deadline (unbounded until close; same exposure class
as upstream's watched stream minus the paint). Live incremental
follow is deferred to the M4e async-send work item.

Secondary decisions folded in:

- `PGraphQL.variables` becomes raw `str` (upstream `yamlString`),
  not a JSON node — matches upstream representation and simplifies
  the Variables editor + document builder.
- GraphQL 2xx-with-top-level-`errors` maps to a new
  `status_class` warning (3) rendered yellow with an error-count
  suffix — upstream `StatusClassWarning`.
- Request-panel jump letters stay positional (`jump-0..6`); upstream's
  fixed per-kind letters (`i`/`o` for GraphQL's own tabs) are a
  recorded deviation.
- CLI `run --json` emits `streamError` and the `events` array when
  present.

## Consequences

- Parser is pure → unit-testable without sockets; event semantics
  (event/data/id/retry, comments, multi-line data, CRLF, caps) are
  corpus-faithful even though delivery timing is not.
- No transport interface changes; h1 deadline lift needs a mutable
  deadline cell shared between `roundtrip` and the timeout reader.
- Follow-up: M4e should revisit live delivery when designing the
  async send path for gRPC/WebSocket.
