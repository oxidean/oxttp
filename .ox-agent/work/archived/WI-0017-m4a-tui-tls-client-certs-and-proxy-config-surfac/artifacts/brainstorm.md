# WI-0017 brainstorm — M4a TUI TLS client certs and proxy config surface

Discovery: `artifacts/discovery.md`. The transport and CLI already do
everything; this WI is a *surface* WI — wire posting's config keys onto
the existing `model.Req` fields and close the documented gaps. The real
questions are where the wiring lives, env-capture fidelity, and how much
degradation honesty oxl 0.26.0 forces.

## Q1 — where does `proxy_url`/env-proxy resolution live?

- **A. Inside `collection.plan_req`** (recommended). It already builds
  the whole `model.Req`, already imports `std/os`, and is the single
  choke point both the interactive send (`coll.oxl send_plan`) and the
  headless `run` (`cli.oxl`) flow through. Per-send `os.getenv` reads
  match Go's `http.ProxyFromEnvironment` (evaluated per request, not
  cached at startup). Removes the "proxy unsupported" warn branch.
- **B. Post-process `sp.req` at each send site.** Rejected: duplicates
  proxy+env logic in coll.oxl and cli.oxl, and plan_req's warn would
  still need removing — two edits for one behavior.
- **C. Inside `core/http` transport.** Rejected: `Req.proxies`/
  `proxy_env`/`no_proxy` are the explicit contract WI-0013 built;
  auto-reading env in the transport would change CLI semantics too
  (CLI deliberately captures env in sem.oxl so `--proxy` can suppress
  it and `--curl` can reason about it).

**Recommendation: A.**

## Q2 — `proxy_url` → `Req.proxies` normalization

`pick_proxy` splits each entry on the FIRST colon as `PROTO:URL`
(h1.oxl ~L1074). A bare `http://proxy:8080` would misparses as
proto=`http`, url=`//proxy:8080`. posting's `proxy_url` is a single
scheme-full URL with no protocol tag and corpus scopes it to *all*
requests (§5.2: one `proxy_url`, gRPC can't have one). Wrap as
`"all:" + proxy_url` — last-match-wins ordering is irrelevant with one
entry. Trim surrounding whitespace (yaml scalars can carry it;
`pick_proxy` trims env values but not `proxies` entries).

Alternative considered: split into `http:`/`https:` entries — rejected,
`all:` is exactly equivalent and simpler.

**Recommendation: `proxies = ["all:" + trim(proxy_url)]`, and when set
the env capture is skipped entirely** (corpus "proxy_url *else* env";
mirrors xh `--proxy` disabling ALL/HTTP/HTTPS_PROXY, corpus-xh §4.5).

## Q3 — env fallback fidelity

Corpus §7.1/§1.1: `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` (Go also honors
lowercase + `ALL_PROXY`; posting inherits Go's `ProxyFromEnvironment`
which checks both cases and ALL_PROXY). Capture per send:

- `HTTPS_PROXY`/`https_proxy`, `HTTP_PROXY`/`http_proxy`,
  `ALL_PROXY`/`all_proxy` → `proxy_env` as `NAME=value` (both cases —
  pick_proxy lowercases names and prefers exact scheme match; keeping
  both entries preserves upstream's case-insensitive env semantics).
  Skip empty values? Go treats set-but-empty as unset — `pick_proxy`
  already treats explicit-empty `*_proxy` as unset and falls through to
  `all_proxy`, so push only non-empty-after-trim values to keep
  `proxy_env` clean. NO_PROXY has no "empty = unset" subtlety issue;
  push `NO_PROXY=`/`no_proxy=` verbatim when non-empty.
- **CGI guard**: Go's `httpproxy` ignores `HTTP_PROXY` when
  `REQUEST_METHOD` is set (httpoxy). xh's sem does the same
  (spec sem-S5: "sem skips HTTP_PROXY in proxy_env capture when
  REQUEST_METHOD present"). Port it: `os.getenv("REQUEST_METHOD")`
  non-empty ⇒ skip the HTTP_PROXY entries (both cases). Cheap, and
  keeps the two binaries' env semantics aligned.
- `no_proxy` → `req.no_proxy` verbatim (transport matches host/
  subdomain/`*`, port-suffix entries).

Disagreement preserved: whether `NO_PROXY` should still apply when
`proxy_url` is set. Corpus "else" reads as full replacement (Go's
per-request Proxy func would return the configured proxy regardless of
NO_PROXY only if posting bypasses ProxyFromEnvironment — which it does
for explicit config). Going with full replacement; noted as DevD-lite
since upstream source for posting's proxy wiring wasn't re-read this
pass (corpus is the contract and it says "else").

**Recommendation: as above.**

## Q4 — `ssl.password`: degrade or implement?

oxl 0.26.0 `x509.parse_key_pem` rejects `ENCRYPTED PRIVATE KEY` and has
no password parameter; legacy `Proc-Type: 4,ENCRYPTED` PEM isn't
decoded at all. Decrypting PKCS#8 (PBES2) would mean porting crypto —
out of scope and against "thin honest wrappers". Keep the degrade;
reword the toast (current text promises "lands with mTLS M4" — this IS
M4a) to state unsupported-in-build. DevD entry in spec. Not an oxl bug
(feature gap); not filing an issue — revisit if a later WI needs it.

**Recommendation: degrade + reword.**

## Q5 — TLS-1.2-negotiated-with-client-cert warning

oxl client certs are TLS 1.3-only; on a 1.2 negotiation the cert list
is empty (matrix already notes). CLI warns once (W2, quiet<2). Corpus
posting is silent (Go sends certs on 1.2 fine — a real behavioral gap,
not just wording). Options:

- **A. Toast on response** when `cert_pem` configured &&
  `resp.tls_ver == tls.V12` (recommended) — explicit-degradation ADR;
  cheap; `exec_send_t` has `resp` and `a.pending`… note `a.pending` is
  nil'd before resp handling — capture `had_cert` before send.
- B. Silent — rejected: user configured mTLS and it silently didn't
  happen; ADR-0006 says say so.

Same toast in headless `run`? It already prints FAILED only on errors;
a cert-on-1.2 send "passes" upstream semantics-wise but ours didn't
present the cert → print a `warning:` line to stderr/report when json
is off (stderr channel exists: `rep.stderr`). Keep symmetric.

**Recommendation: A + headless stderr note.**

## Q6 — cert PEM pre-validation at plan time?

CLI `plan()` pre-runs `tls.load_cert_pem` so a bad cert/key pair fails
before connect (exit 1, corpus §8 "invalid --cert files"). TUI
currently discovers PEM errors inside the transport at send
(`tls_wrap` → send err → `send_failed` toast). Corpus §2.2: "Client-
cert/password problems are reported at send time" — transport failure
IS send time and produces a clean toast. Pre-validating in send_plan
would need `core/collection`→`net/tls` import ( layering smell:
collection is schema+plan, tls is transport). Keep transport-level;
the error text already names the problem (`tls: …`).

**Recommendation: no pre-validation; DevD note that PEM errors surface
as send failures, not plan toasts.**

## Q7 — scope check: TLS version pins

WI title mentions TLS version pins (the CLI's `--ssl`). Posting has
NO config surface for them (corpus §2.2 = 4 ssl keys; §5.2 options has
none). Inventing `ssl.min_version` keys would violate corpus fidelity
(decision 0010 verbatim schema). Transport default `[V12,V13]` already
applies. **Out of scope — documented absence, not a deviation.**

## Convergent plan

1. `core/collection.plan_req`: replace proxy warn with
   `proxy_url`→`["all:"+trim]` into `req.proxies`; else capture env
   (`HTTPS_PROXY`/`https_proxy`, `HTTP_PROXY`/`http_proxy` w/ CGI
   guard, `ALL_PROXY`/`all_proxy`, `NO_PROXY`/`no_proxy`) into
   `proxy_env`/`no_proxy`.
2. `tui/coll.oxl`: reword ssl.password toast; capture cert-configured
   flag for post-send TLS1.2 warning.
3. `tui/cli.oxl run`: same proxy fix comes free via plan_req; add
   ssl.password warn parity + TLS1.2-cert stderr note.
4. Tests: plan_req proxy/env unit tests (core/collection), send_plan
   ssl fold + proxy (tui), cli run regression, transport proxy tests
   already exist.
5. Spec DevDs: ssl.password unsupported; TLS1.2 empty cert list
   (warn added); proxy_url env-replacement reading; no TLS-version
   keys (absence, not deviation).
