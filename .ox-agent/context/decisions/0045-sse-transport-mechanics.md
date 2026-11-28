# ADR-0045 — SSE transport mechanics: shared deadline cell, unconditional lift, h1-first

- Status: accepted
- Date: 2026-11-27
- Work item: WI-0020 (specification)
- Amends: ADR-0044 (mechanics detail, same decision)

## Context

ADR-0044 chose buffered-at-EOF SSE. Specifying the transport mechanics
surfaced three sub-decisions: how the post-header timeout lift is
expressed in `core/http/h1.oxl`, whether the lift applies to headless
sends, and how the 64 MB cap is enforced.

Upstream (`internal/client/http.go`) lifts the request timer for SSE
only when the call is watched (`call.OnUpdate != nil`); a headless
`run` keeps the whole-body deadline. Our `Transport.send` has no
watched/unwatched distinction.

## Decision

- `TmoReader`/`TmoTlsReader` hold `deadline: shared` (an `mkshared`
  int cell) instead of a plain `int`; `roundtrip` creates the cell and
  `finish_roundtrip` `sset`s it to 0 when the response is
  `text/event-stream` (method != HEAD), before body reads begin. All
  reads through the same `bufio.Reader` see the lift — buffered bytes
  are preserved, no reader rebuild.
- The lift is **unconditional** (TUI and `run` alike): a deviation
  from upstream's watched-only lift, folded into ADR-0044's D1/D6 —
  a headless infinite SSE stream now runs until close/cap rather than
  the request timeout. Bounded by the 64 MiB raw-read cap.
- 64 MiB cap enforced on the raw body read for SSE (upstream caps the
  decoded stream at 64 MiB+1 via `io.LimitedReader`); decoded output
  is additionally truncated to 64 MiB post-`decode_body`. Truncation
  sets `stream_error = "SSE response exceeded 64.00 MB"`. Pathological
  compression (raw >64 MiB decoding to <64 MiB) truncates early —
  recorded deviation D5.
- h2: `h2_exchange` keeps its int deadline — SSE over negotiated h2
  parses events but does not lift the timeout (D6). Cleartext h2c and
  HTTP/1.1 both lift.
- Event parsing lives in `core/http/sse.oxl` as a pure function
  `parse_sse(body: []byte) -> [events, stream_error]`
  shared by h1 and h2 paths; seed/terminal events match upstream.

## Consequences

- No transport interface change; `shared` cell read cost is one
  `sget` per socket read — negligible.
- `run --json` and TUI both surface `streamError`/events; headless
  SSE timeout behavior differs from upstream (documented).
- M4e (gRPC/WS) should revisit: interactive streams need the async
  send path ADR-0044 deferred.
