# Implementation — S3 core/http h1 transport

## Shape

`H1` is a stateless `Transport` on `std/net` sockets — zero value is a
complete client, one connection per request (`Connection: close` on the
wire). `request(req)` is the package-level convenience on a shared
zero-value H1 (the bare name `send` collides with the channel builtin).

- `core/http/h1.oxl` — `H1.send` (redirect loop + policy), `roundtrip`
  (one exchange incl. stage timings), `check_url` (http-only gate),
  `TmoReader` (whole-request deadline re-armed per read), `dial_h1` /
  `lookup_nosusp` (non-suspending dial + DNS), `write_all`, `bodyless`.
- `core/http/wire.oxl` — socket-free wire helpers: header lookup
  (`lwr`/`hdr_get`/`hdr_has`), `render_body` (+form/multipart/file
  helpers), `serialize_head`, `read_head`/`parse_head`,
  `content_length`, `read_exact`/`read_eof`/`read_chunked`,
  `decode_body` (gzip/x-gzip/deflate zlib→raw-flate/x-compress),
  redirect helpers (`is_redirect`/`redirect_headers`/
  `resolve_location`/`same_origin`/`eff_port`).

## Key semantics (per spec.md)

- Request: `METHOD uri HTTP/1.1`, `Host` first (caller Host wins, never
  duplicated), caller headers in order, synthesized
  `Accept-Encoding: gzip, deflate`, `Connection: close`,
  `Content-Length` — each only when absent. URL userinfo becomes Basic
  Authorization when caller did not set one.
- Response: 1xx blocks skipped (except 101), ordered+dup-preserving
  headers, trailers appended after chunked bodies, Content-Length
  conflict/malformed rejected, chunked wins over CL, no framing reads
  to EOF, HEAD/1xx/204/304 bodyless.
- Redirects: 301/302/303 → GET + body/content-* drop (HEAD kept);
  307/308 preserve method+body; signature pair always stripped; the
  five auth-ish headers stripped on cross-origin hops; bounded by
  max_redirects with the corpus-shaped error; bad Location and non-http
  targets are explicit errors.
- Timeouts: whole-request deadline (dial + send + all reads);
  timeout<=0 gets a 30s dial cap, reads unbounded.
- https and non-http schemes are rejected with the scheme named —
  TLS is parked on oxidean/oxl#128.

## Non-suspension constraint

`Transport.send` dispatches through an interface vtable — "vtable
calls carry no task frame", so the whole path must be suspend-free.
std's `net.dial_timeout` suspends (`lookup_ipv4` parks on `msleep`),
so dialing/DNS run on the raw `rt_*` externs with `usleep` backoff —
blocking the calling thread, correct for a sequential exchange.

## Test surface (all green)

`oxl test ./core/http` — 3 model dep tests + 41 http tests:
live socket matrix (port satisfaction, request-line/header echo, POST
CL, userinfo, multipart, chunked+trailers, gzip+deflate, HEAD/204,
1xx skip, HTTP/1.0 EOF body, truncation, 7 redirect cases, timeout,
bad URLs, refused conn) + pure wire matrix (13 fns). Fixture is a
scripted serial `net.listen` server with `<ECHO>`/`<SLEEP:n>` tokens.
