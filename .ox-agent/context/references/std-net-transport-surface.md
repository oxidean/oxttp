# std transport surface for S3 (verified WI-0004 discovery)

Verified against `~/wsl-projects/oxidean-org/language/std` (read-only)
on pinned toolchain v0.15.0 — supersedes the "name resolution stays
parked" note in the std/net header comment (dial resolves names).

## std/net — sockets

- `dial(host, port) -> [Conn, err]` (30s cap), `dial_timeout(host,
  port, tmo_ms) -> [Conn, err]` — resolves dotted IPv4 AND hostnames
  via `lookup_ipv4` (getaddrinfo on a detached helper thread, bounded
  by tmo_ms). Sequential phases: worst case 2*tmo_ms.
- `Conn`: `read(b)->[int,err]` (0+io.eof() on orderly close),
  `write(b)->[int,err]` (may write short — caller loops), `close()`
  (shared-latch, safe twice/across iface-boxed copies), `rawfd()->int`.
- `listen(port)->[Listener,err]`, `l.port()`, `l.accept()->[Conn,err]`,
  `l.rawfd()`, `l.close()` — basis for the fixture server (accept on a
  `spawnBlocking` task; `set_rcvtimo` on the listen fd doubles as an
  accept deadline).

## Socket timeouts (runtime builtins, not extern'd)

`set_rcvtimo(fd, secs)`, `set_rcvtimo_ms(fd, ms)`, `set_sndtimo(fd,
secs)` — SO_RCVTIMEO/SO_SNDTIMEO wrappers (rt.c:3567+). The std http
client pattern: re-arm `set_rcvtimo_ms(fd, remaining)` before every
read so the budget is a whole-request deadline, not per-read.
Read on expiry returns a normal `err` from `Conn.read` (no dedicated
timeout sentinel — timeout detection is by deadline bookkeeping, not
error sniffing).

## std/net/http — reference impl, not the transport

- `serve(port, Handler)` — `route(method, path, body)->Resp{status,
  body, ctype}`. Too limited for fixture duty: fixed header set,
  content-length only (400s on TE: chunked requests), no chunked/
  trailer/redirect control. Use a hand-rolled listener for fixtures.
- `Client.request(method,url,ctype,body)` — the API ADR-0003 rejects
  (no outgoing headers/redirects/etc.), BUT its body is the best
  in-std reference for status-line parse, `hdr_of`, `unchunk`
  (size-line/`;ext`/trailers/0-CRLF-CRLF), read-until-EOF, and the
  deadline re-arm loop. Mirror, don't copy.
- `rt_sigpipe_ignore()` extern — a client must call this or a reset
  peer kills the process on write (EPIPE->SIGPIPE default).

## std/bufio, std/bytes, std/io

- `bufio.Reader`: `readline()->[str,err]` (incl. `\n`-less last line),
  `peek(n)`, `read(p)` — status-line + header-block parsing.
- `bufio.Writer`: `write`, `flush` — request serialization.
- `bytes.Buffer` — io.Reader+Writer over memory; feed compressed bytes
  to gzip.Reader, or capture decoded output.
- `io.copy/readall/limitreader`, `io.eof()` interned sentinel.

## std/compress — decode only

- `gzip.newreader(io.Reader)->[Reader,err]` (streaming, multi-member)
  and `gzip.decompress(b)` one-shot returning `[own []byte, err]`.
- `flate.newreader`/`flate.inflate(b)` — raw RFC 1951.
- `zlib.newreader`/`zlib.decompress(b)` — RFC 1950 (the wire `deflate`
  per spec; many servers send raw flate — try zlib then flate, like
  reqwest).
- NO compressors — fixtures embed pre-compressed byte literals
  generated offline. NO br/zstd decoders — corpus accept list
  `gzip, deflate, br, zstd` is not fully implementable in v0.1.

## std/net/url — RFC 3986 (Go net/url port)

`parse(raw)->[own URL,err]`, `u.hostname()`, `u.port()` (str, "" when
absent), `u.request_uri()` (path?query for the request line),
`u.isabs()`, `resolve_reference(base, ref)->own URL` — everything a
Location-header redirect needs. `u.scheme`, `u.host` decoded fields;
userinfo halves exposed for proxy creds later.

## std/os, std/time, std/strconv

`os.getenv(name)->str` ("" absent — HTTP_PROXY/NO_PROXY for S7),
`time.unix_ms()`, builtins `now_ms()`, `msleep/usleep`, `exit`,
`println`. `strconv.parseint(s,16)` for chunk sizes, `atoi`, `itoa`.
No `lower()` in std/strings — byte-loop lwr is a per-package helper.

## Language notes for this layer

- `own T` fields/`== nil` work; iface boxes (`asreader()`) share the
  Conn close-latch so wrapping a Conn in bufio doesn't double-close.
- `spawnBlocking f(args)` + `scope{}` for the fixture accept loop.
- `s as []byte` / `b as str` casts; `mkslice(byte,n)`, `push`, slice
  ranges `b[i:j]` all verified patterns in std.
- No `Option`, no string-keyed maps — ordered Header lists per model.
