# WI-0013 discovery — protocol flags: h2, mTLS, ssl-version, CONNECT proxy

Pin: oxl **0.26.0** (`~/.oxl/versions/v0.26.0/oxl-toolchain/std` read
first-hand — authoritative). Corpus: `docs/corpus/corpus-xh.md` §4.5/4.6/§5/§8.
Parity rows this WI unlocks: `--cert/--cert-key`, `--ssl`, `--native-tls`,
HTTPS+`--proxy` CONNECT, `--http-version` 2/2-prior-knowledge.

## Verified oxl 0.26.0 surfaces

### `std/net/tls` (tls.oxl)
- `Config{server_name, roots, alpn []str, verify, min_ver, max_ver, client_cert}`.
  `V12=771`, `V13=772`. Default (0/0) = **TLS 1.3 only**. `minv>V12` or
  `maxv<V13` bounds check in `client_tmo`; `minv< V12` → `"tls: bad
  min_ver/max_ver"` — **TLS ≤1.1 is inexpressible**, matches the WI scope.
- `min=V12,max=V12` pins 1.2; `min=V12,max=V13` = 1.2+1.3 auto range.
- `client_cert: ClientCert` via `load_cert_pem(cert_pem, key_pem)` —
  cert chain (leaf first) + key (PKCS#8/RSA/SEC1); key-vs-leaf mismatch
  is a load-time err. **TLS 1.3 only**: under a negotiated 1.2 session
  the fallback answers CertificateRequest with an empty
  certificate_list (verified caveat — warn when this happens).
- `tls.Conn` exposes `.negotiated_alpn()` and `.s.ver` (V12/V13
  post-handshake) — both compile-verified cross-package this session.

### `std/net/http2` (conn.oxl / http2.oxl)
- Client `Conn`: `new_conn_timeout(rw io.ReadWriter, timeout_fd,
  timeout_ms) -> [own Conn, err]` does preface+SETTINGS exchange on ANY
  ReadWriter (plain `net.Conn.asreadwriter()` or `tls.Conn.asreadwriter()`
  both fine — compile-verified). Methods: `open_stream(headers,
  end_stream)`, `send_body(id, payload)` (handles WINDOW_UPDATE waits),
  `next_event()`, `ack_data`, `cancel_stream`, `close`.
- `dial_tls_config`/`dial_tls_over(socket, host, tmo, cfg) ->
  TLSDialResult{conn, transport, closer, protocol}` — ALPN offers
  ["h2","http/1.1"] by default, falls back to h1 transport when ALPN
  yields http/1.1/none. `dial_h2c(host,port,tmo)` = cleartext prior.
- All read/write paths use `set_rcvtimo` deadline I/O — **no msleep**
  (only suspension point in the whole stack is `lookup_ipv4` inside
  `net.dial_timeout`, which our `dial_h1` already avoids). The
  suspend-free `Transport.send` contract (h1.oxl header comment)
  survives h2 adoption.

### `std/net/http` client (client.oxl) — reference, not the transport
- `Request{proxy, http_version}` — `"2"`/`"2-prior-knowledge"` route to
  `do_once_h2`; `proxy: ""` = env lookup, `"direct"` = bypass, else
  http:// proxy URL. Semantics worth mirroring:
  - `proxy_from_env(host, secure)`: `https_proxy`/`HTTPS_PROXY` on
    https; `HTTP_PROXY`/`http_proxy` on http (HTTP_PROXY skipped when
    `REQUEST_METHOD` set — CGI-header-injection defense, curl's rule);
    then `all_proxy`/`ALL_PROXY`. `NO_PROXY`/`no_proxy` domain+subdomain
    match, `"*"` disables all, `host:port` strips port, leading `.`
    cosmetic. **Loopback carve-out**: localhost/::1/127.x never proxied
    via env.
  - Plain http via proxy → absolute-form request target
    `http://authority/path`. https via proxy → `connect_proxy` (CONNECT
    + 1xx-tolerant response parse). h2c through a proxy → error
    `"h2c through a proxy is not supported"`. `https://`/`socks5://`
    proxy URLs rejected (`"proxy url must be http"`).
  - **No Proxy-Authorization anywhere in std** — proxy userinfo is not
    honored by `connect_proxy`. xh/reqwest DOES send
    `Proxy-Authorization: Basic` (CONNECT for https targets, request
    header for http targets) — we implement CONNECT ourselves.

## Current code touchpoints

- `cli/spec.oxl`: all flags already declared (58-flag table) —
  `--proxy` (repeat), `--cert`, `--cert-key`, `--ssl` enum
  (auto,tls1,tls1.1,tls1.2,tls1.3 + ssl2.3→auto alias), `--native-tls`
  (hidden), `--http-version` enum. `args.env(s,"verify",...)` shows the
  env-fallback pattern.
- `cli/sem.oxl`: `Intent` already carries `proxies []str`,
  `proxy_env []str` (captured only when --proxy absent — corpus
  "--proxy disables env"), `no_proxy`, `cert`, `cert_key`, `ssl`,
  `http_version`, `native_tls`. Deferral routing (§10) currently
  error-degrades: h3 (keep), scheme!=http(s) (keep), `native_tls && https`
  (`--native-tls is unsupported in this build (oxidean/oxl#221)` —
  stale cite, #221 shipped), then `--curl` short-circuit, then
  h2 (`HTTP/2 requests are unsupported`), proxy (`proxies are
  unsupported`), resolve/interface/ipv6/unix-socket/format-options.
- `cli/exec.oxl`: `plan()` populates `model.Req` (verify, httpver,
  timeout, follow); `ReqPlan.warn []str` → execute() emits
  `{prog}: warning:` lines (-qq hides). `curl_ignored()` already warns
  `Ignored --proxy`/`--resolve`; `curl_emit` maps http1.0 etc.
- `core/http/h1.oxl`: `Transport.send` — redirect loop + jar-lite +
  `roundtrip` per hop. `dial_h1` = non-suspending raw-extern dial
  (mandatory: `Transport.send` can be vtable-dispatched — see
  h1_test.oxl `let tr: Transport = H1{}`). `tls_wrap(c, host, verify,
  tmo)` builds `tls.Config` today (server_name, verify modes).
- `core/model/model.oxl`: `Req`/`Resp` are exhaustive literals —
  adding fields means updating literals in h1.oxl (`send` copy,
  `bad` Resps) and `h1_test.oxl` `rq()`.

## Flag-by-flag feasibility

| Flag | Feasibility | Shape |
|---|---|---|
| `--http-version 2` | **feasible** | https→ALPN h2 (fallback h1.1 when ALPN≠h2 — matches std+reqwest hint semantics); http→h1 (hint has no teeth on cleartext, std's exact choice) |
| `--http-version 2-prior-knowledge` | **feasible** | cleartext→h2c `new_conn_timeout`; https→TLS+ALPN `["h2"]` only + require negotiated=="h2" (hyper prior-knowledge shape); through proxy→error |
| `--http-version 3-prior-knowledge` | stays blocked | existing `"built without support for HTTP/3"` defer = xh's own feature-gate error; ADR-0029 stands |
| `--cert`/`--cert-key` | **feasible** | plan-time file reads (missing/unreadable→exit 1, xh "invalid --cert files"); `load_cert_pem`; warn when negotiated V12 with cert configured |
| `--ssl tls1.2` | **feasible** | min=max=V12 |
| `--ssl tls1.3` | inert-fidelity | == current default |
| `--ssl auto`/`ssl2.3` | feasible | map to V12..V13 auto range (rustls "auto" analog) |
| `--ssl tls1`/`tls1.1` | warn-degrade | <V12 inexpressible → corpus-style warning + widest fallback (V12..V13); corpus cites both warning texts (§8) |
| `--native-tls` | warn-degrade | single oxl stack; can't honor "other backend". On https: warn + use our stack. On http: inert (TLS never engages — byte-identical). Replaces stale #221 exit defer. ADR justified. |
| `--proxy` + env | **feasible** | per-hop scheme resolution in transport; explicit > nothing (env disabled); http target→absolute-form+optional Proxy-Authorization; https→own CONNECT (+auth) → normal path; socks5/https proxy URLs→error degrade |
| `--curl` interplay | feasible | corpus §5 map: `--http-version`→`--http2*`/`--http3-only`(blocked), `--ssl`→`--tlsvX.Y --tls-max`, `--cert`→`-E/--cert`,`--key`, `--proxy all:`→`-x`, `http:`/`https:`→env prefix; `--native-tls`→`Warning: Ignored` (corpus lists it) |

## Testability

- **Fixture-able (cleartext)**: h2c exchange — hand-roll a minimal h2
  fixture server in tests using exported `http2.read_frame`/
  `write_frame`/`encode_headers` (read preface+SETTINGS→write SETTINGS
  →read client frames→write HEADERS+DATA). http proxy: absolute-form
  request + Proxy-Authorization captured by existing fixture.
  CONNECT capture test: fixture replies 200 to CONNECT then observes
  the (doomed) TLS handshake bytes — asserts CONNECT wire shape +
  host:port authority.
- **Live-network**: https through CONNECT + ALPN-h2 + mTLS + ssl
  pins need a TLS server — std has none, so these ride real hosts
  (example.com pattern already in h1_test; keep assertions
  server-tolerant where ALPN outcome isn't guaranteed).
- Golden/exec-level: degrade routing text changes are
  stdout/stderr-observable → golden/exec tests pin them; sem tests
  update for the removed defers.

## Risks / decisions to settle at brainstorm+spec

1. `--ssl` DEFAULT range: keep V13-only default or move to [V12,V13]
   (xh/rustls negotiate 1.2 by default — a 1.2-only server works in xh
   today, fails in oxttp). Recommendation: flip default to [V12,V13] —
   corpus-faithful, one line in tls_wrap.
2. `--native-tls` warn text + placement (exec warn vs sem defer).
3. `REQUEST_METHOD` CGI guard for HTTP_PROXY — cheap fidelity add to
   envnames + proxy_env capture.
4. Model field plumbing: `Req{proxies, proxy_env, no_proxy, cert_pem,
   key_pem, ssl_min, ssl_max, h2}` + `Resp{tls_ver}` — exhaustive
   literals updated everywhere.
5. h2 request-head rendering for -v/--offline: `GET / HTTP/2.0`
   approximation (corpus doesn't pin a text form; reqwest displays
   HTTP/2.0).
6. Proxy-Authorization on redirects: corpus §4.6 strips
   proxy-authorization cross-domain — our injected header joins the
   strip list naturally if carried as a request header; for CONNECT
   it's per-connection (no leak).
