# WI-0013 brainstorm — protocol flags on oxl 0.26.0

Discovery: `artifacts/discovery.md`. Every scope item is feasible on
the pinned toolchain; the questions are *where* each behavior lives
and which corpus deviations we write down, not whether to do them.

## Q1 — How does h2 ride the Transport port?

- **A. Port std's h2 path into core/http behind our own dial**
  (recommended). `dial_h1` keeps the suspend-free contract
  (vtable-dispatched `send` can never park — `net.dial_timeout`'s
  `lookup_ipv4` is the stack's only msleep). Then:
  `tls_wrap` gains `alpn`; `negotiated_alpn()=="h2"` or cleartext
  prior-knowledge → `http2.new_conn_timeout(...asreadwriter(), fd,
  tmo)`; a ported `http2_exchange` does open_stream/send_body/
  next_event until END_STREAM. Keeps ADR-0003 (own transport, mirror
  don't adopt) and preserves Proxy-Authorization control (std has
  none).
- **B. Delegate h2/proxy requests to `std/net/http.Client`.**
  Rejected: `do_once_h2`/`do_once` dial via `net.dial_timeout`
  (suspends — breaks the Transport contract), follows its own redirect
  loop outside our hop/jar model, and can't send Proxy-Authorization.
- **C. Keep error-degrading h2.** Rejected: parity row is explicitly
  `next`, and the surface exists.

**Recommendation: A.** `Resp.version="2.0"` renders `HTTP/2.0` like
reqwest's display. Request-head rendering for `-v`/`--offline`
becomes `GET / HTTP/2.0` — documented approximation (corpus pins no
text form for h2 display).

## Q2 — `--native-tls`: what does the single-stack build do?

xh's flag selects an *alternate backend*, is hidden unless built with
both, and is a **silent no-op on any single-backend build**. The
corpus reference build is `+native-tls +rustls` — there it is
functional. oxttp ships exactly one stack (oxl std/net/tls).

- **A. Warning-degrade on https, inert on http** (recommended).
  `{prog}: warning: --native-tls selects an alternate TLS backend;
  this build ships one TLS stack (oxl std/net/tls) — using it` —
  emitted once via `plan().warn`. Cleartext stays byte-identical
  (TLS never engages anywhere). Replaces the stale `(oxidean/oxl#221)`
  exit-1 defer.
- **B. Full inert.** Justifiable literalism (single-backend xh is
  silent) but hides that the ask could not be honored — against
  ADR-0006's say-so spirit on the reference config.
- **C. Keep error-degrade.** Safe but needlessly breaks scripts that
  carry the flag harmlessly; xh itself never errors for this on
  single-backend builds.

## Q3 — `--ssl` mapping and the default range

| value | mapping | disposition |
|---|---|---|
| `tls1.3` | min=max=V13 | executed (== behavior today) |
| `tls1.2` | min=max=V12 | executed |
| `auto`,`ssl2.3` | min=V12,max=V13 | executed (rustls "auto" analog) |
| `tls1`,`tls1.1` | warn + min=V12,max=V13 | warning-degrade — <V12 inexpressible; corpus warns identically |

- **A. Also flip the no-flag default to [V12,V13]** (recommended).
  xh's default (rustls) negotiates 1.2+1.3; today oxttp is 1.3-only
  so a real xh succeeds where we fail on 1.2-only servers. One-line
  change in `tls_wrap` default; spec calls it out.
- **B. Keep default 1.3-only**, `--ssl auto` → [V12,V13]. Upstream's
  deliberate zero-config choice honored; leaves a parity gap only a
  flag can close.

**Recommendation: A** — corpus fidelity over upstream default taste;
the 1.2 fallback is already shipped code (ECDHE-GCM suites only —
narrowness is upstream's, not ours to extend).

## Q4 — Proxy resolution placement

- **A. Per-hop inside `roundtrip`** (recommended). `model.Req` carries
  `proxies`/`proxy_env`/`no_proxy`; each redirect hop re-resolves on
  the new URL's scheme — reqwest applies proxies per request, and a
  cross-scheme redirect (http→https) genuinely changes which entry
  applies.
- **B. Resolve once in `plan()` for the initial URL.** Simpler;
  wrong for scheme-changing redirect chains.

Explicit `--proxy`: first entry whose protocol matches the hop scheme
(`all:` matches any) wins; no match → direct (reqwest matcher
semantics). No `--proxy`: env vars (already captured —
`--proxy` suppresses them at sem). NO_PROXY + loopback carve-out
apply to env-selected proxies only.

On the wire: http target → absolute-form `GET http://authority/path`
+ `Proxy-Authorization` when the proxy URL has userinfo; https target
→ own CONNECT (host:port authority, `host`/`proxy-authorization`/
`proxy-connection` headers, 1xx-tolerant 200 check, port of std's
`connect_proxy` + auth) then TLS on the tunnel.

Reject (error-degrade): `https://` proxy (`--proxy ... proxies must
be http:` — TLS-to-proxy unimplemented), `socks5://` (no socks stack)
→ `"<scheme> proxies are unsupported in this build"`. h2c through a
proxy → `"http: h2c through a proxy is not supported"` (std's text).

`REQUEST_METHOD` CGI guard on HTTP_PROXY: cheap fidelity — add
`REQUEST_METHOD` to `envnames()` and skip capturing `HTTP_PROXY`
when set (curl/env_proxy convention, std mirrors it).

## Q5 — `--cert`/`--cert-key`

Files read in `plan()` (missing/unreadable → `p.err` → exit 1; corpus
§8 "invalid --verify/--cert files"). `key_pem` = `--cert-key` content,
else the cert PEM itself (combined PEM carries both — mirrors xh's
append). `tls.load_cert_pem` at `tls_wrap` time; load errors →
exit-1 app error. Warn once post-handshake when a cert is configured
and `tc.s.ver == V12` (upstream caveat: empty certificate_list sent).
Inert on `http://` (TLS never engages — byte-identical, ADR-0024).

## Q6 — `--http-version` edges

- `2` on `http://` → h1 (std's exact semantics; the hint only has
  teeth under ALPN).
- `2-prior-knowledge` on `https://` → TLS with `alpn=["h2"]`,
  `negotiated_alpn()=="h2"` required else error — closest safe analog
  to "forced h2" (hyper speaks h2 blind; we get a clean error instead
  of garbage on a 1.1-only peer — noted deviation).
- `2-prior-knowledge` on `http://` → h2c via `new_conn_timeout`.
- `3-prior-knowledge` → unchanged feature-gate error (ADR-0029).
- `--curl` + `2*` → emit `--http2`/`--http2-prior-knowledge` (§5 map).

## Q7 — Warnings text

- `tls1`/`tls1.1`: corpus pins "rustls does not support older TLS
  versions." verbatim; consequence clause adapted honestly (no
  native-tls to enable): `— this build's TLS stack requires TLS >=
  1.2; falling back to TLS 1.2+`. Deviation recorded in spec.
- `--native-tls`: per Q2-A.
- `--curl`: corpus §5 Ignored list gains `--native-tls`; `--cert`/
  `--ssl`/`--proxy` aren't ignored — they emit curl flags instead.

## Consensus summary (feeds specify)

1. Own-transport h2+h2c via `http2.Conn` behind `dial_h1`/`tls_wrap`
   (port `do_once_h2`+`http2_exchange` shape; A1).
2. `--native-tls` → warning-degrade on https, inert cleartext (A2→ADR).
3. `--ssl` table per Q3 incl. default flip to [V12,V13] (A3→ADR).
4. Per-hop proxy resolution in transport; CONNECT+Proxy-Authorization
   is ours; socks5/https-proxy/h2c-proxy error-degrade (A4).
5. `--cert*` plan-time files, `load_cert_pem`, V12-cert warn (Q5).
6. `3-prior-knowledge` unchanged; curl map extended (Q6).
7. Warnings: corpus text where truthful, adapted where not (Q7).
8. Tests: h2 fixture server (exported frame API), CONNECT capture,
   exec/golden degrade pins, live-https spot checks.
