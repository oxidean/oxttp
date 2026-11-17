# 0003 — Own HTTP/1.1 transport on std/net sockets

Status: accepted (2026-11-17, WI-0001 brainstorm)

`core/` implements its own HTTP/1.1 client on `std/net` sockets instead
of wrapping `std/net/http.Client`. The std client exposes only
`request(method,url,ctype,body) -> Resp{status,body,ctype}` — no
outgoing headers, redirect control, chunked-decode visibility,
compression, auth, or proxy env — and the xh corpus requires all of
those.

The transport sits behind a port interface in `core/http`: the domain
model (request, response, headers, body kinds) is transport-agnostic,
so TLS and HTTP/2 join later without touching `cli` or `tui`.

Consequences: header model, status-line/chunked/content-length decoders,
redirect policy, gzip/deflate via `std/compress`, Basic/Bearer auth, and
`HTTP_PROXY` handling all land in `core/` work items.
