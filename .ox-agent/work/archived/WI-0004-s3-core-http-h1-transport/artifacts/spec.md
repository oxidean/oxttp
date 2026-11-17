# WI-0004 spec - S3: core/http HTTP/1.1 transport

Upstream: WI-0001 plan.md S3, WI-0001 spec, ADRs 0001/0003/0006/0016/
0017/0018. Corpus: `docs/corpus/corpus-xh.md` §4.5-4.6, §8.
Std surface: `context/references/std-net-transport-surface.md`.
Design: `artifacts/brainstorm.md` (all Q resolved to option A).

## Scope

IN: HTTP/1.1 client transport in `core/http` on `std/net` sockets —
request serialization for every `model.Body` variant, response parse
(status line incl. 1xx skip, headers, Content-Length + chunked +
EOF-terminated bodies, trailers), redirect policy per corpus §4.6,
gzip/deflate response decompression, `timeout_ms` enforcement,
Trace/elapsed fill-in. Live round-trip tests on a hand-rolled
`net.listen` fixture server.

OUT: TLS/https (decision 0001), proxy env/`--proxy` (S7), auth flags
and digest (S7), sessions/cookies (S7), connection pooling/reuse
(v0.1 closes each conn), Expect: 100-continue (cli never sends it
yet), HTTP/2-3, `--all` intermediate-hop visibility (needs a model
hop-chain — S7 model extension), `Accept-Encoding` br/zstd (no std
decoders — ADR-0017), request-body compression `--compress` (S6/S7).

## Package contract (`core/http`)

```oxl
// transport.oxl (exists, unchanged)
interface Transport { send(req: ref model.Req) -> [model.Resp, err] }

// h1.oxl — the S2 port's HTTP/1.1 implementation. Stateless; zero
// value usable.
struct H1 {}
fn (t H1) send(req: ref model.Req) -> [model.Resp, err]

// package-level convenience on a shared H1 (std get/post shape)
fn send(req: ref model.Req) -> [model.Resp, err]
```

`H1` must satisfy `Transport` — the test suite pins it:
`let tr: Transport = H1{}` compiles and dispatches.

### wire.oxl — pure helpers (the TDD seam, no sockets)

- `fn lwr(s: str) -> str` — ASCII case-fold.
- `fn hdr_get(hs: []model.Header, name: str) -> str` — first value,
  case-insensitive name, "" absent. `fn hdr_has(...) -> bool`.
- `fn render_body(b: model.Body) -> [str, str, err]` — returns
  `[content_type, bytes]`: Empty→("",""); Raw→ctype+text;
  Json→"application/json"+`json.tojson`; Form→"application/x-www-
  form-urlencoded"+query-escaped `k=v&` (enabled fields only);
  Multipart→"multipart/form-data; boundary=<gen>"+assembly
  (enabled parts only; file parts read via `os.readfile_`,
  Content-Type per part when set); FileBody→ctype+`os.readfile_`
  bytes. Content-type "" when variant doesn't fix one.
- `fn read_head(r: io.Reader) -> [str, err]` — status line +
  header block through `\r\n\r\n` (raw head text, 64KiB cap).
- `fn parse_head(head: str) -> [int, str, []model.Header, err]` —
  status line `HTTP/<d>.<d> SP <3dig> [SP reason]`; skips 1xx blocks
  by looping read_head at the caller; header lines `name: value`,
  order+dupes preserved, value SP/TAB-trimmed, LF-only tolerated,
  `:`-less line → `http: malformed response header`.
- `fn unchunk(r: io.Reader, trailers: mut []model.Header) -> [[]byte,
  err]` — hex size line (+`;ext` ignored), data+CRLF, 0-chunk then
  trailer fields appended to `trailers`; 16-hex-digit size cap; bad
  size/truncation/missing CRLF → `http: ...` errors.
- `fn read_body(r: io.Reader, n: int) -> [[]byte, err]` — exactly n.
- `fn read_eof(r: io.Reader) -> [[]byte, err]` — until io.eof().
- `fn decode_body(raw: []byte, ce: str) -> [[]byte, err]` —
  identity/""→raw; gzip|x-gzip→`gzip.decompress`;
  deflate|x-compress→`zlib.decompress` then `flate.inflate` fallback;
  len==0→raw (empty compressed body tolerated, HEAD); else
  `http: unsupported content-encoding: <ce>`.

## send() behavior contract

1. Parse `req.url` via `url.parse`; scheme must be `http` (""→
   explicit error; `https`→`http: unsupported scheme "https" (TLS is
   not supported in this build)` — xh's unsupported-feature shape);
   hostname required; bracketed/literal IPv6 → `http: IPv6 addresses
   not supported` (std dial is AF_INET); port default 80; `u.port()`
   atoi-checked 1-65535.
2. URL userinfo → synthesize `Authorization: Basic base64(user:pass)`
   when caller sent none (reqwest behavior; base64 via
   `std/encoding/base64`).
3. Serialize: `<METHOD> <request_uri> HTTP/1.1` + headers:
   `Host` = `u.host` verbatim first (caller-supplied Host wins, sent
   in caller position instead), caller headers in order, then
   synthesized defaults for absent names — `Accept-Encoding:
   gzip, deflate` (ADR-0017), `Connection: close` (see Deviations),
   `Content-Length: <n>` when rendered body non-empty (caller CL
   wins). No TE/chunked request bodies in v0.1.
4. Dial: `timeout_ms<=0` → `net.dial` (std 30s connect cap); `>0` →
   `net.dial_timeout(tmo)` + `set_sndtimo` + per-read re-armed
   `set_rcvtimo_ms(remaining)` against a `now_ms()+tmo` deadline;
   expiry → `http: request timed out after <ms>ms` (dial errors from
   std propagate verbatim). `rt_sigpipe_ignore()` once at first send.
5. Read head (skipping 1xx blocks: each head whose status ∈ 100-199
   is dropped and the next read); parse; then body per RFC 7230
   §3.3.3: method HEAD or status ∈{1xx,204,304} → none; `TE:
   chunked` (case-insensitive, last coding) → unchunk+trailers;
   `Content-Length` (all instances must agree after trim → else
   `http: conflicting content-length` smuggling guard; bad/empty
   value → `http: bad content-length`) → exactly N (short read →
   `http: response truncated: content-length <n>, got <m>`);
   otherwise → read until EOF. Then `decode_body` on
   `content-encoding`.
6. Resp fill: `status`, `reason`, `headers` (wire order + appended
   trailers), `body` decoded bytes, `elapsed_ms` wall,
   `remote` = dialed `host:port`, `trace` populated per phase
   (connect/send_headers/send_body/recv_headers/recv_body/closed;
   tls_ms=0). Conn closed every path.
7. Redirects: `req.follow` false → return 3xx untouched. Else while
   status ∈{301,302,303,307,308} and `Location` present: parse+resolve
   via `url.resolve_reference` (failure → `http: Redirect to invalid
   URL: <loc>`); https target → the same unsupported-scheme error;
   301/302/303 → method GET unless HEAD (HEAD kept), body dropped +
   `content-*` request headers stripped; 307/308 → method+body
   preserved; origin change (scheme/host/port any differ) → strip
   authorization, cookie, cookie2, proxy-authorization,
   www-authenticate; signature, signature-input stripped ALWAYS.
   `n > max_redirects` (0 or negative = 0) → `http: Too many
   redirects (--max-redirects=N)`. 3xx without Location, and codes
   outside the five, return as-is.

## Deviations (recorded, never silent)

1. `Accept-Encoding: gzip, deflate` (not corpus's four) — ADR-0017;
   br/zstd responses → explicit error.
2. `Connection: close` (corpus: keep-alive) — v0.1 single-shot, no
   pool; honest unframed-body fallback; a close-honoring server may
   echo `connection: close` in response headers.
3. Intermediate redirect hops discarded — `model.Resp` carries only
   the final hop; `--all`/`--history-print` need a chain field (S7).
4. xh sends `user-agent: xh/<ver>` — app-layer header, cli (S5+)
   supplies it; transport never invents UA.
5. Empty compressed body suppressed-tolerated per corpus.

## Acceptance criteria

1. `oxl build` green on `core/http` and every consuming dir
   (`cli`, `tui` still build); `oxl test` per-dir green everywhere.
2. `H1` satisfies `Transport` (compile-pinned in tests).
3. Wire unit matrix green: serialization (request line, Host order,
   CL synth, AE default/override, Conn close, all 6 Body variants,
   userinfo→Authorization, header order preserved); head parse
   (1.0/1.1, missing reason, LF-only, malformed); unchunk (multi,
   ;ext, trailers, bad/truncated); framing select; decode (gzip,
   zlib-deflate, raw-flate, identity, br→err, empty).
4. Live fixture matrix green vs hand-rolled `net.listen` server:
   GET/HEAD/POST round-trips (method/target/Host/headers/body verified
   at the server), chunked response, trailers surfaced, gzip +
   deflate bodies decoded, 301/302 relative+absolute to GET rewrite,
   307 preserve method+body, cross-origin header strip (two
   listeners), follow=false returns 3xx, max-redirects error, bad
   Location error, https-redirect error, 1xx-then-200 skip, 204
   no-body, CL-truncation error, timeout_ms against a silent fixture.
5. `send()` closes every conn (no fd leak across error paths — fixture
   server sees orderly closes).
6. All spec deviations listed above; upstream gaps reported:
   no br/zstd decoders, no timeout error sentinel, no compressors.

## Test files

- `core/http/wire_test.oxl` — pure-fn matrix (AC3), no sockets.
- `core/http/fixture_test.oxl` — scripted `net.listen` server
  helpers (accept, capture request, write raw response bytes,
  multi-response chains, second listener for cross-origin).
- `core/http/h1_test.oxl` — live matrix (AC4-5) + port-satisfaction
  compile pin.
