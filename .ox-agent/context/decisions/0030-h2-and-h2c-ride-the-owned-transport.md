# ADR-0030 — h2 and h2c ride the owned transport via std/net/http2

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0013 (brainstorming)

## Context

oxl 0.26.0 ships `std/net/http2` (client `Conn`: preface/SETTINGS,
streams, flow control, HPACK) and `std/net/http`'s `Client` can route
`Request.http_version` `"2"`/`"2-prior-knowledge"` through it.

ADR-0003 pins our h1 transport as an owned port, and `Transport.send`
is vtable-dispatchable — it may never suspend (h1.oxl header note;
`net.dial_timeout`'s `lookup_ipv4` is the stack's only `msleep`).

Two properties of std's `Client` disqualify it for our exec path:
`do_once*` dials with `net.dial_timeout` (suspends), and its CONNECT
path sends **no** `Proxy-Authorization` while xh/reqwest does.

## Decision

1. `core/http` gains h2 branches inside the existing `Transport`
   implementation: TCP still comes from `dial_h1` (non-suspending);
   TLS still wraps via `tls_wrap`. h2 connections open with
   `http2.new_conn_timeout` over `asreadwriter()` of the plain or TLS
   conn — deadline I/O only, zero new suspension points.
2. The request/response exchange ports std's
   `do_once_h2`/`http2_exchange` shape (mirror, not adopt):
   `:method/:scheme/:authority/:path` pseudo-headers, caller headers
   lowercased, `accept-encoding: gzip` advertised only when
   decompress is on and absent, response headers/trailers/body into
   `model.Resp` with `version="2.0"`.
3. `--http-version 2` = ALPN hint: `alpn=["h2","http/1.1"]`; negotiated
   `h2` → h2; `http/1.1` or none → the existing h1 exchange on the
   same TLS conn. On cleartext `http://` the hint has no teeth → h1
   (std's exact semantics).
4. `2-prior-knowledge` on `http://` → h2c via `new_conn_timeout` on
   the raw conn. On `https://` → ALPN `["h2"]` only and require
   negotiated `h2`, else a transport error — the safe analog of
   hyper's blind prior knowledge (a 1.1-only peer gets a clean error
   instead of a garbage frame stream).
5. h2c through a proxy stays an error (`http: h2c through a proxy is
   not supported`, std's text); h2-over-CONNECT (https target via
   proxy) works — CONNECT tunnel first, then the same ALPN branch.
6. `3-prior-knowledge` keeps the feature-gate error (ADR-0029 stands).

## Consequences

- Parity matrix §4.6 `2*` rows can move to `done` where observable.
- `model.Req` gains protocol/proxy/cert fields; `Resp.version` may be
  `"2.0"`; request-head display for `-v`/`--offline` renders
  `GET / HTTP/2.0` (approximation — corpus pins no text form).
- h2 redirect hops ride the same `send` loop/jar/hop machinery.
