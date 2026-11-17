# WI-0004 brainstorm - S3 core/http h1 transport

Scope: one stage of the WI-0001 plan. ADR-settled calls (0003 own
transport behind the port, 0006 explicit degradation, 0012 layout)
are not reopened — this brainstorm covers stage-level design.

## Q1 - Response reader architecture

- **A: bufio.Reader + per-framing body decode** (chosen). Parse status
  line + headers via `readline`, then read the body per its framing:
  exact-count for Content-Length, streamed chunk loop for TE: chunked,
  read-to-EOF only as the no-length fallback. Decoders take
  `io.Reader` — unit-testable on `bytes.Buffer` fixtures without a
  socket (the TDD seam). Truncation is detected precisely (short read
  vs expected count), keep-alive remains possible later.
- **B: read-until-EOF + split** (std Client shape). Simpler but forces
  `connection: close` on the wire, can't see a keep-alive response's
  real end, and folds truncation handling into post-hoc CL checks.
- **C: raw byte scanning** — re-implements what bufio already gives.

With A, `connection: keep-alive` stays wire-faithful to xh (closing
an idle keep-alive conn after one response is legal); v0.1 just does
not pool. Truncation per corpus §4.3 (`Incomplete download`) is
detectable from the short read.

## Q2 - File layout inside `core/http`

- **A: `transport.oxl` (port, exists) + `h1.oxl` (H1 impl + send +
  redirect loop) + `wire.oxl` (serialize/parse helpers)** (chosen).
  Wire helpers are pure functions over `io.Reader`/strings — the unit
  matrix hits them directly; live tests cover the socket path.
- **B: one h1.oxl** — mixes port/impl/codec; harder to review.
- **C: sub-package `core/http/h1`** — a whole package for one impl is
  premature; TLS/h2 land beside it later without nesting.

## Q3 - Redirect loop placement + visibility

- **A: inside `send()`, per the port contract** (chosen) — "impls own
  redirect following". Loop to `max_redirects`; `Req.follow=false`
  returns the 3xx untouched. Final Resp returned; intermediate hops
  are discarded in v0.1 (`--all`/`--history-print` need a hop chain —
  model extension deferred to S7, noted as a gap not silent).
- **B: caller loops** — pushes policy into cli/tui; port comment says
  the impl owns it.

Method/header rewrite rules (corpus §4.6, redirect.rs): 301/302/303 →
GET (HEAD kept), body + content-* dropped; 307/308 preserve.
Cross-origin (scheme/host/port change): strip authorization, cookie,
cookie2, proxy-authorization, www-authenticate; signature +
signature-input always stripped. Relative `Location` resolves via
`url.resolve_reference`; unparseable → `Redirect to invalid URL: ...`.
https targets → explicit unsupported-TLS error (decision 0001/0006).
Exceeded → `Too many redirects (--max-redirects=N)`.

## Q4 - Accept-Encoding + decompression scope

- **A: inject `Accept-Encoding: gzip, deflate` when caller didn't
  supply one; decode gzip/x-gzip/deflate/x-compress; error on
  anything else** (chosen). Honest advertisement — only encodings we
  can decode. Corpus deviation: xh advertises `br, zstd` too; no
  std decoders exist (upstream gap). `deflate` decodes zlib-wrapped,
  raw-flate fallback (reqwest behavior). Empty compressed body
  tolerated (HEAD). Content-Encoding header is left in place (xh
  keeps it too); decoded bytes replace body.
- **B: advertise all four** — a server may then legally answer br:
  undecodable by construction. Rejected.
- **C: no injection** — pushes a client-fixed header to every caller.

## Q5 - Body enum → wire bytes

- **A: transport renders every Body variant** (chosen). Wire encoding
  is transport knowledge: Empty→none; Raw→ctype+text; Json→
  `json.tojson` + application/json; Form→query-escaped k=v& +
  application/x-www-form-urlencoded; Multipart→boundary assembly +
  multipart/form-data; FileBody→os.readfile + declared ctype.
  Content-Length synthesized from rendered bytes; caller-supplied
  Content-Type/Content-Length headers win (explicit beats derived).
- **B: accept Raw/FileBody only** — makes S6 re-flatten the model the
  domain already typed. Rejected.

## Q6 - Fixture server for the live gate

- **A: hand-rolled `net.listen(0)` accept loop serving scripted raw
  responses** (chosen). Full control: chunked, trailers, gzip bodies,
  redirect chains, weird casing, LF-only lines, truncated bodies,
  HTTP/1.0, mid-response close. Requests are captured for assertions
  (method, target, Host, headers, body echo). `std/net/http serve()`
  is out — fixed headers, no chunked/redirect control (see
  references/std-net-transport-surface.md).
- **B: canned byte fixtures only** — no live round-trip; the gate
  demands live.

## Q7 - Trace + elapsed fill-in

- **A: `now_ms()` deltas per phase** (chosen): connect_ms (dial),
  send_headers_ms, send_body_ms, recv_headers_ms (first byte→headers
  done), recv_body_ms, closed_ms; tls_ms=0 always (no TLS).
  elapsed_ms = total wall. Cheap, honest, posting-Trace-shaped.
- **B: zeros** — wastes the field S2 reserved.

## Q8 - Timeout semantics

- **A: `timeout_ms<=0` → `net.dial` (its own 30s connect cap) and no
  socket timeouts; `>0` → `dial_timeout(tmo)` + re-armed
  `set_rcvtimo_ms(remaining)` per read + `set_sndtimo` for writes**
  (chosen). Mirrors std Client's deadline bookkeeping — no timeout
  sentinel exists, expiry is detected by deadline math, not error
  sniffing.
- **B: `dial_timeout(0)` for none** — std treats 0 as "expired now";
  would break the no-timeout case. Rejected.

## Edge cases carried to spec

- 1xx informational status lines skipped (100 Continue / 103).
- HEAD / 204 / 304 → no body read even with Content-Length present.
- Request must call `rt_sigpipe_ignore()` once (reset peer mid-write
  otherwise kills the process).
- Expect: 100-continue upload flow out of v0.1 scope (note, not
  implemented — cli doesn't send Expect yet).
- Response `HTTP/1.0` tolerated; LF-only lines tolerated in parse.

## Recommendation

A across the board. Residual deviations to spec: Accept-Encoding
advertises only decodable pair (no br/zstd); intermediate redirect
hops not yet exposed (`--all` chain is an S7 model extension);
connection pooled nowhere in v0.1.
