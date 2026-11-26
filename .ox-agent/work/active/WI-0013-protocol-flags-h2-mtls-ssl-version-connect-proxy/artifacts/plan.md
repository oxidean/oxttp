# WI-0013 plan — protocol flags: h2, mTLS, ssl-version, CONNECT proxy

Spec: `artifacts/spec.md`. ADRs: 0030/0031/0032. All stages run on this
branch in order; each gate is `oxl build ./cli` + affected-dir `oxl test`
green before the next stage starts.

| Stage | Work | Depends | Gate |
|---|---|---|---|
| **P1 model** | `core/model.oxl`: Req + `h2/ssl_min/ssl_max/cert_pem/key_pem/proxies/proxy_env/no_proxy`; Resp + `tls_ver`. Update every exhaustive Req literal (h1.oxl send-copy + bad-request resp, cli tests `rq`, tui if any). No behavior change. | — | build + `oxl test` model/http/cli |
| **P2 ssl+cert+native-tls** | sem: delete native-tls-https defer (W3 moves to plan). exec plan(): map `--ssl`→ssl_min/max (default [V12,V13]); read cert files eagerly (missing→exit 1); W1 (tls1/1.1) + W3 (native-tls+https) warnings; populate cert_pem/key_pem. h1: `tls_wrap` reads verify/ssl/alpn/cert off req; `resp.tls_ver` post-handshake; W2 in execute(). | P1 | cli+http tests green; live https spot-check on V12+V13 |
| **P3 h2** | h1.oxl: port `http2_exchange` (preface via `new_conn_timeout`, HEADERS via `encode_headers`, DATA loop, `ack_data`, trailers, RST/GOAWAY); alpn wiring per sem-S1; `2-prior-knowledge` → h2c on http / alpn-`h2`-only + require on https; drop `Connection` etc. from h2 header list; `resp.version="2.0"`; `req_head_render` + h2 hop heads render `HTTP/2.0` (D1). sem: delete h2 defer. | P1 | new h2c fixture test green (hand-rolled h2 server via exported frame API); http/cli dirs green |
| **P4 proxy** | sem: envnames + `REQUEST_METHOD`; proxy_env capture skips HTTP_PROXY under it; delete proxy defer. h1: per-hop `pick_proxy` (flag list → env → NO_PROXY → loopback carve-out); http→absolute-form + Proxy-Authorization; https→`CONNECT` helper (1xx skip, 200 require, proxy-auth, keep-alive); socks5/https-scheme degrade err; redirect re-resolves. | P1, P3 (shares roundtrip) | proxy capture tests (absolute-form, CONNECT head, auth header) green; http+cli dirs green |
| **P5 curl emit + golden + matrix** | exec `curl_emit`/`curl_ignored`: `--http2`/`--http2-prior-knowledge`, `--tlsvX.Y --tls-max X.Y`, `-E`/`--key`, `-x` + env-prefix proxies; remove now-unreachable `Ignored --proxy`. Golden cases for curl emit + degrade texts. `docs/xh-flag-parity-matrix.md`: flip cert/ssl/native-tls/CONNECT/2* rows → `done`. | P2–P4 | golden harness green; matrix diff matches spec §AC5 |
| **P6 full verify** | per-dir `oxl test` loop all dirs; `oxl build ./cli` + `./tui`; `git status` clean; parity-matrix committed. | P5 | whole-tree green |

## Order rationale

- P1 first: exhaustive struct literals mean every later stage's Req
  use sites compile only after fields exist.
- P2 before P3/P4: smallest diff touching `tls_wrap` signature once;
  proxy stage reuses the new signature for CONNECT→TLS.
- P4 after P3: both edit `roundtrip`'s dial→branch skeleton; doing
  proxy second lets CONNECT land on the already-branched h2/h1 path.
- P5 last: emit strings and matrix rows pin final texts only after
  behavior exists to observe.

## Risks

- **h2 exchange complexity** (P3): body streaming + trailers + RST —
  fixture test covers happy path + RST; GOAWAY-mid-body treated as
  transport err (matches std framing, corpus-silent).
- **CONNECT + h2 order interplay** (P4): CONNECT establishes tunnel
  before TLS, so h2 ALPN branch is unchanged — verified in fixture.
- **Env-proxy capture** (P4): `REQUEST_METHOD` guard is sem-side;
  packet pins so tests can't regress it silently.
- **Big-single-commit risk**: commit after each stage gate (P1..P6)
  rather than one giant commit — history matches gate table.
