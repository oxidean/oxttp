# WI-0013 spec — protocol flags: h2, mTLS, ssl-version, CONNECT proxy

Direction locked by `artifacts/brainstorm.md` + ADR-0030/0031/0032.
Corpus: `docs/corpus/corpus-xh.md` §4.5/4.6/§5/§8. Surfaces verified in
`artifacts/discovery.md` against pinned oxl 0.26.0.

## Locked semantics (per flag)

### sem-S1 `--http-version`

| value | behavior |
|---|---|
| `1.0`,`1`,`1.1` | unchanged (h1 wire token) |
| `2` | ALPN hint. https: `tls.Config.alpn=["h2","http/1.1"]`; negotiated `h2` → h2 exchange; `http/1.1`/none → h1 on the same TLS conn. http: h1 (hint has no teeth cleartext — std's exact semantics). |
| `2-prior-knowledge` | http: h2c — `http2.new_conn_timeout` on the raw conn. https: `alpn=["h2"]` only; require `negotiated_alpn()=="h2"` else transport err `http: prior-knowledge HTTP/2 requires h2 negotiation` (D3). via any proxy → err `http: h2c through a proxy is not supported` (std text). |
| `3-prior-knowledge` | unchanged feature-gate defer (ADR-0029). |

### sem-S2 `--ssl`

| value | `tls.Config` | disposition |
|---|---|---|
| unset | min=V12,max=V13 | **default flips** (ADR-0032) |
| `auto`,`ssl2.3` | min=V12,max=V13 | executed |
| `tls1.3` | min=V13,max=V13 | executed |
| `tls1.2` | min=V12,max=V12 | executed |
| `tls1`,`tls1.1` | min=V12,max=V13 | warning-degrade (W1) |

All values inert-fidelity on `http://` (TLS never engages).

### sem-S3 `--cert` / `--cert-key`

- plan() reads both files eagerly when present (missing/unreadable →
  `p.err` exit 1 — corpus §8 "invalid --verify/--cert files"), on any
  scheme (xh loads them at client build — validation is scheme-blind).
- `req.cert_pem` = cert file text; `req.key_pem` = `--cert-key` text,
  else the cert PEM text (combined-PEM convention = xh's append).
- Transport: `tls.load_cert_pem(req.cert_pem, req.key_pem)` →
  `cfg.client_cert`; load err → app error exit 1.
- Post-handshake: `cert_pem` configured && `resp.tls_ver==V12` → W2
  once (upstream caveat: 1.2 sends empty certificate_list).

### sem-S4 `--native-tls`

- `https://` → W3 warning via `plan().warn` (ADR-0031); request runs.
- `http://` → inert (byte-identical).
- `--curl` → `Warning: Ignored --native-tls` (corpus §5 list).
- The stale `oxidean/oxl#221` exit-1 defer is removed from sem §10.

### sem-S5 `--proxy` + env

`model.Req` carries `proxies` (verbatim `--proxy` entries),
`proxy_env` ("NAME=value"), `no_proxy`. Resolution per hop in the
transport on `cur.url`:

1. `proxies` non-empty → first entry whose `PROTO` equals the hop
   scheme, else first `all:` entry; none match → direct. Env vars are
   not consulted (sem already suppresses capture under `--proxy`).
1.5. Multiple `--proxy` entries: the LAST entry matching the hop
   scheme wins (`scheme:` or `all:` at each position — upstream
   reqwest intercept order, `args.proxy.into_iter().rev()`). An
   `all:` placed after a `scheme:` entry shadows it.
2. `proxies` empty → `proxy_env` picked by scheme name
   (`HTTPS_PROXY`/`https_proxy` on https; `HTTP_PROXY`/`http_proxy` on
   http — **HTTP_PROXY skipped when `REQUEST_METHOD` present**, CGI
   guard), then `ALL_PROXY`/`all_proxy`; values whitespace-trimmed;
   NO_PROXY domain match cancels. **Upstream parity:** env proxies
   apply to loopback hosts too (reqwest has no Go-style loopback
   carve-out).
3. Selected URL parsed; scheme must be `http` — else error-degrade
   `http: proxy URL scheme "<sch>" is unsupported in this build`
   (covers `https://`, `socks5://`).
4. http target via proxy → absolute-form request target
   `GET http://authority/path` + `Proxy-Authorization: Basic ***
   when proxy URL has userinfo and caller didn't set it.
5. https target via proxy → `CONNECT host:port HTTP/1.1` with
   title-case `Host`, `User-Agent`, `Proxy-Authorization` (when
   userinfo) — upstream wire shape, no `proxy-connection`; tunnel
   establishes only on literal 200 (1xx preludes skipped; 101 and
   ≥300 fail) — then normal TLS+protocol branch on the tunnel.
   CONNECT auth derives from proxy-URL userinfo only: a caller-set
   `proxy-authorization` header passes through the tunnel to the
   origin (upstream passes user headers through).
6. Redirects re-resolve per hop (scheme may change); proxy-auth lands
   in the cross-origin strip list (corpus §4.6).

### sem-S6 curl map additions (corpus §5)

- `--http-version 2`→`--http2`; `2-prior-knowledge`→
  `--http2-prior-knowledge`; `3-prior-knowledge`→`--http3-only`.
  The h3 feature-gate defer does NOT reach the `--curl` path —
  upstream's `to_curl::print_curl_translation` short-circuit runs
  before client build (where the `#[cfg(not(feature="http3"))]` bail
  lives), so `--curl --http-version 3-prior-knowledge` emits
  `--http3-only` and exits 0. Amended post-review: the code was
  upstream-correct and this spec text was stale; pinned by golden
  case `curl-h3-prior`.
- `--ssl tlsX.Y`→`--tlsvX.Y --tls-max X.Y`; auto/ssl2.3→nothing.
- `--cert`→`-E`/`--cert`; `--cert-key`→`--key`.
- `--proxy all:URL`→**deviation:** env assignment `all_proxy=URL`
  prepended to the emitted line — NOT `-x`/`--proxy`. Rationale:
  `curl -x` overrides scheme-specific `*_proxy` env vars, so a
  combined `all:`+`http:` set would misroute under a literal -x
  emit; env prefixes compose correctly. `http:`/`https:`→ env
  assignments `http_proxy=URL`/`https_proxy=URL` prepended to the
  emitted line (corpus table). Explicit `--proxy` entries also emit
  `no_proxy= NO_PROXY=` clearing — oxttp never consults env under
  `--proxy`, and an ambient NO_PROXY would let curl skip a proxy
  oxttp used. Env-captured proxies: silent (curl inherits the same
  env). The `Warning: Ignored --proxy` line narrows to unreachable
  — remove (proxies now emit).

## Warning texts (stderr, `{prog}: warning:`, -qq hides)

- **W1** (`--ssl tls1`/`tls1.1`):
  `rustls does not support older TLS versions. This build's TLS stack requires TLS >= 1.2 — falling back to TLS 1.2+.`
  (corpus first clause verbatim; consequence adapted — D2)
- **W2** (cert negotiated under V12):
  `--cert client certificate was not presented: TLS 1.2 sends an empty certificate list in this build`
- **W3** (`--native-tls` on https):
  `--native-tls selects an alternate TLS backend; this build ships one TLS stack (oxl std/net/tls) — using it`

## Structural changes

- `core/model`: `Req` + `h2 str` (""|"hint"|"prior"), `ssl_min int`,
  `ssl_max int`, `cert_pem str`, `key_pem str`, `proxies []str`,
  `proxy_env []str`, `no_proxy str`. `Resp` + `tls_ver int` (0 none).
  Exhaustive literals updated (h1.oxl send-copy/bad, test `rq`).
- `cli/main.oxl` `envnames()` gains `REQUEST_METHOD`; sem skips
  `HTTP_PROXY` in `proxy_env` capture when present.
- `cli/sem.oxl` §10: delete native-tls-https defer, h2 defer, proxy
  defer; h3/msig/scheme/resolve/interface/ipv6/unix/fmt defers
  unchanged; curl short-circuit unchanged (before flag resolution).
- `cli/exec.oxl` `plan()`: populate new Req fields; cert file reads;
  W1/W3 warnings. `execute()`: W2 post-send; curl_emit/curl_ignored
  per sem-S6. `req_head_render`: version token `HTTP/2.0` when h2
  can reach the wire — `prior` always; `hint` only on https (ALPN
  may still pick 1.1, but h2 is possible); cleartext `hint` renders
  HTTP/1.1 (D1).
- `core/http/h1.oxl`: `tls_wrap` signature →
  `(c, host, req, tmo)` reading verify/ssl/alpn/cert off the Req;
  `roundtrip` gains proxy resolution + CONNECT + h2/h2c branches;
  ported `connect`/`exchange` helpers in-file (or wire.oxl).
- `Resp.version` = `"2.0"` under h2 (renders `HTTP/2.0`); `req_head`
  for h2 hops = synthesized `METHOD uri HTTP/2.0` + headers (D1).

## Deviations (called out, none silent)

- **D1** h2 has no wire text: `-v`/`--all`/`--offline` request heads
  render a synthesized `GET / HTTP/2.0` textual form (corpus pins no
  display contract; reqwest displays HTTP/2.0).
- **D2** W1 consequence clause adapted (no native-tls exists to
  enable); first clause is corpus-verbatim.
- **D3** `2-prior-knowledge` on https requires negotiated h2 —
  hyper speaks h2 blind; ours errors cleanly on a 1.1-only peer.
- **D4** `Proxy-Authorization` sent where std's client sends none —
  faithful to xh/reqwest (CONNECT header for https, request header
  for http target).
- **D5** W2 is an oxttp addition — upstream's 1.2-cert caveat is
  silent; ADR-0006 says say so.
- **D6** IPv6 proxy authorities (`--proxy 'all:http://[::1]:8080'`)
  degrade `http: IPv6 addresses not supported` — consistent with
  the --ipv6 deferral; upstream reqwest accepts them.
- **D7** `--curl` emits invented ambient-clearing env assignments
  (`http_proxy= HTTP_PROXY= …`, `no_proxy= NO_PROXY=`) for
  protos without explicit entries — upstream emits none, but its
  emitted curl can then inherit a proxy oxttp itself bypassed.
  Documented deviation per sem-S6.
- **D8** `proxy-connect` CONNECT tunnel accepts only literal
  `HTTP/1.x 200` — stricter than first drafted (any-2xx); matches
  upstream reqwest tunnel().

## Acceptance criteria

1. `oxl build ./cli` + `./tui` clean; per-dir `oxl test` loop green.
2. sem/exec tests pin: h3 defer unchanged; removed defers gone;
   W1/W3 texts; REQUEST_METHOD guard; curl emit additions.
3. `core/http` live tests: h2c fixture exchange (hand-rolled h2
   server via exported frame API); proxy absolute-form +
   Proxy-Authorization capture; CONNECT wire-shape capture;
   https spot-checks stay green on new [V12,V13] default.
4. Golden: `--curl` emit pins (h2/ssl/cert/proxy flags) +
   degrade-text cases for socks5/https proxy URLs.
5. Parity matrix: `--cert/--cert-key`, `--ssl tls1.2`/`--native-tls`,
   CONNECT, `--http-version 2*` rows → `done`; tls1/1.1 stays
   `oxl-blocked` noting warn-fallback.
6. Cert negative paths: missing file → exit 1; bad PEM → exit 1.
7. No regression in existing golden/exec/h1/live tests.
