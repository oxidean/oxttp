# WI-0004 discovery - S3 core/http h1 transport

## Deliverable (WI-0001 plan.md S3)

HTTP/1.1 transport on `std/net` sockets behind the `core/http`
`Transport` port from S2: request serialization, response decode
(status line, headers, content-length, chunked, trailers), redirect
policy, gzip/deflate via `std/compress`, timeouts.

Gate: live round-trip tests vs a local `std/net` server — methods,
headers, chunked, redirects, compressed bodies.

## Contract already in the tree

- `core/http/transport.oxl` — `interface Transport { send(req: ref
  model.Req) -> [model.Resp, err] }`; impls own redirect following,
  decompression visibility, Trace fill-in.
- `core/model/model.oxl` — `Req{method,url,headers,body,timeout_ms,
  follow,max_redirects}` / `Resp{status,reason,headers,body:[]byte,
  elapsed_ms,remote,trace:own Trace}`. Body enum covers
  Empty/Raw/Json/Form/Multipart/FileBody — serialization must render
  every variant (Form url-encode, Multipart boundary assembly are
  body-assembly concerns; the transport renders the model it is
  handed).

## Corpus requirements (docs/corpus/corpus-xh.md)

- §4.6 redirects: 301/302/303 → GET rewrite (HEAD kept), body +
  content-headers dropped; 307/308 preserve method+body. Cross-domain
  (host or port change) strips authorization/cookie/cookie2/
  proxy-authorization/www-authenticate; signature/signature-input
  always stripped. `--max-redirects` default 10 → error
  `Too many redirects (--max-redirects=N)`; bad Location →
  `Redirect to invalid URL: ...`.
- §4.6 client-fixed: sends `accept-encoding: gzip, deflate, br, zstd`;
  decodes gzip/deflate internally (x-gzip/x-compress aliases honored;
  empty compressed body tolerated). oxl std has NO br/zstd decoders —
  corpus deviation to spec.
- `--timeout` SEC f64 → `Req.timeout_ms` int (0 = none).
- HTTP/1.x sends `connection: keep-alive` — v0.1 has no conn pool;
  `connection: close` per request is the honest wire behavior.
  Deviation to spec.

## std surface (context/references/std-net-transport-surface.md)

- `std/net`: `dial_timeout(host,port,ms)` (DNS via getaddrinfo helper,
  seq-phase budget 2*tmo), `Conn` r/w/close/`rawfd`; `listen`/`accept`
  for fixtures.
- Socket timeouts exist as runtime builtins `set_rcvtimo_ms(fd,ms)` /
  `set_sndtimo(fd,s)` — the earlier "socket timeouts may be missing"
  worry is resolved: timeout_ms is fully implementable.
- `std/bufio` Reader (`readline`,`peek`) / Writer (`flush`) — parse
  and serialize on top of Conn.
- `std/compress/{gzip,zlib,flate}`: Readers + one-shots, DECODE ONLY.
  `deflate` on the wire needs zlib-then-raw-flate fallback (reqwest
  behavior). No compressors → fixtures embed pre-compressed bytes.
- `std/net/url`: full RFC 3986 parse + `resolve_reference` — Location
  resolution and request-target building need nothing hand-rolled.
- `std/net/http`: serve() too limited for fixtures (fixed headers,
  no chunked/redirect); `Client` is a good reference for unchunk +
  deadline re-arm. Fixture server = hand-rolled `net.listen` accept
  loop writing raw response bytes.
- `rt_sigpipe_ignore()` extern is REQUIRED for a socket client (a
  reset peer mid-write otherwise kills the process).

## Upstream gaps (report, do not file)

- No br/zstd decoders in std/compress → corpus accept-encoding list
  cannot be fully served (advertise gzip+deflate only, or degrade).
- No TLS anywhere (oxidean/oxl#128, known — HTTP only).
- No dedicated timeout error sentinel — deadline bookkeeping required.
- `Conn.write` can short-write; callers must loop (same as std).

## Settled (cite, do not re-litigate)

- 0003: own h1 transport, behind `core/http` port; apps never see
  sockets. 0006: degrade explicitly. 0016: package layout core/http.
- S3 scope per plan: serialization, decode, redirects, gzip/deflate,
  timeouts. Proxy env, auth kinds, session cookies are S7.
