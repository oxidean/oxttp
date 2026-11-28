# WI-0017 spec — M4a TUI TLS client certs and proxy config surface

Direction locked by `artifacts/brainstorm.md` + ADR-0044/0045/0046/0047.
Corpus: `docs/corpus/corpus-posting.md` §1.1/§2.2/§5.2/§7.1,
`docs/corpus/corpus-xh.md` §4.5. Transport machinery verified
first-hand in `artifacts/discovery.md` (oxl 0.26.0 std sources +
core/http/h1.oxl WI-0013 wiring).

## Scope

Surface WI: no transport changes. `model.Req` already carries
`proxies`/`proxy_env`/`no_proxy`, `cert_pem`/`key_pem`,
`ssl_min`/`ssl_max`. This spec wires posting's config leaves onto
those fields and fixes degrade honesty. TLS version pins have NO
posting surface (corpus §2.2/§5.2 define none) — documented absence.

## S1 — `options.proxy_url` + env proxy in `plan_req` (ADR-0044)

File: `core/collection/collection.oxl` (or a sibling file in the same
package — implementer's choice; keep `collection.oxl` cohesive).

1. New pure helper `proxy_pick(proxy_url: str, pairs: []str)`
   returning the three `model.Req` proxy fields via a small struct
   (e.g. `ProxyPick{proxies: []str, env: []str, no_proxy: str}`) —
   pure over `"NAME=value"` pairs so tests need no real env:
   - `trim(proxy_url)` non-empty → `proxies = ["all:" + trimmed]`,
     `env = nil`, `no_proxy = ""`. Env is NOT consulted (corpus
     "proxy_url else env"; xh `--proxy` parity).
   - else scan `pairs` for the canonical Go `httpproxy` names and
     build (ADR-0047 — posting is a Go application):
     - `HTTPS_PROXY`/`https_proxy` → one canonical lowercase
       `https_proxy=<value>` entry; lowercase wins when both cases
       are non-empty (`getEnvAny`), uppercase is fallback only.
     - `HTTP_PROXY`/`http_proxy` → one canonical lowercase
       `http_proxy=<value>` entry with the same precedence. A raw
       non-empty `REQUEST_METHOD` sets the transport CGI flag instead
       of suppressing capture; the transport errors before using that
       proxy on an `http:` hop (Go `proxyForURL` behavior).
     - `ALL_PROXY`/`all_proxy` are not captured — Go `httpproxy` has
       no ALL_PROXY variable (they remain xh/reqwest-only).
     - Schemeless values normalize to `http://host[:port]`; complete
       URLs pass through.
     - `NO_PROXY`/`no_proxy` → `no_proxy` = first non-empty value
       (lowercase preferred, uppercase fallback);
       empty/whitespace-only counts unset.
   - Only non-empty-after-trim values are pushed to `env` (Go treats
     set-but-empty as unset; pick_proxy also skips explicit-empty
     `*_proxy` but keeping `env` clean preserves intent).
   - `pairs` entries without `=` or with empty names are ignored.
2. New `collect_proxy_env() -> []str`: emits `"NAME=value"` pairs for
   the fixed name list via `os.getenv` — `REQUEST_METHOD`,
   `https_proxy`, `HTTPS_PROXY`, `http_proxy`, `HTTP_PROXY`,
   `no_proxy`, `NO_PROXY`. `os.getenv` can't distinguish unset from
   empty; empty ⇒ omit (repo convention, cli/main.oxl `os_envpairs`
   doc). `proxy_url` is substituted through the scoped env layers like
   URL/headers before `proxy_pick` runs; substitution errors are plan
   errors.
3. `plan_req` replaces the warn branch (~L2097):
   `pk := proxy_pick(proxy, collect_proxy_env())` then
   `rq.proxies = pk.proxies`, `rq.proxy_env = pk.env`,
   `rq.no_proxy = pk.no_proxy`. The warn "proxy unsupported in this
   build — sending direct" is DELETED.
4. `proxy_url` applies to whatever reaches `plan_req` — HTTP-family
   sends only in practice (non-http kinds never produce a send plan);
   no kind gating added (ADR-0044 consequence note).
5. Whitespace-only `proxy_url` → treated as unset → env path.

## S2 — mTLS degrade honesty (ADR-0045)

1. `tui/coll.oxl` `begin_send_preq` (~L1047): reword the
   `ssl.password` toast — the "lands with mTLS M4" promise is void.
   New text states the build limitation, e.g.
   `ssl.password: encrypted private keys unsupported in this build`.
   Toast level stays 2 (error-ish) — it only fires when a cert is
   configured AND password set.
2. TLS1.2 client-cert warning (CLI W2 parity, ADR-0006):
   - `exec_send_t` captures `had_cert := len(a.pending.cert_pem) > 0`
     BEFORE `a.pending = nil`.
   - On successful response (`e == nil`) with
     `resp.tls_ver == tls.V12 && had_cert` →
     `a.toast(1, "client certificate was not presented: TLS 1.2 sends an empty certificate list in this build")`.
     Requires `import "std/net/tls"` in coll.oxl (or compare against
     the literal 771 — prefer the named constant).
   - Fires once per send; cleartext (`tls_ver==0`) and V13 unaffected.
3. `tui/cli.oxl` headless `run`:
   - `ssl.password`: when `cr.s.ssl_password` non-empty AND
     `ssl_certificate_path` non-empty, append one
     `warning: ssl.password is set but encrypted private keys are
     unsupported in this build` line to `rep.stderr` before the loop
     (once per run, not per request).
   - TLS1.2 cert note: after a PASSED/FAILED-with-response send where
     `sp.req.cert_pem` non-empty and `resp.tls_ver == tls.V12`, append
     `warning: <rel>: client certificate was not presented (TLS 1.2
     sends an empty certificate list in this build)` to `rep.stderr`.
     Requires `std/net/tls` import in cli.oxl.
   - Proxy wiring needs NO cli.oxl change — `plan_req` covers it.
   - `ssl.key_file` without `certificate_path`: unchanged (ignored —
     bare key is meaningless upstream).

## S3 — tests

New `*_test.oxl` coverage (existing suites must stay green):

- `core/collection` (extend `collection_test.oxl` or new
  `proxy_test.oxl` in same dir):
  - `proxy_pick` explicit: `proxy_url="http://p:8080"` →
    `proxies==["all:http://p:8080"]`, env/no_proxy empty EVEN when
    pairs contain proxy vars; whitespace-padded url trimmed;
    whitespace-only url → env path.
  - env path: scheme-specific canonical selection; lowercase names;
    empty values skipped; lowercase-first `getEnvAny` precedence;
    `REQUEST_METHOD=GET` sets the CGI flag while HTTP_PROXY capture
    remains for the send-time error; ALL_PROXY is ignored;
    NO_PROXY/no_proxy precedence (lowercase first, first non-empty);
    pairs without `=` ignored.
  - `plan_req` end-to-end: a `PRequest` with `options.proxy_url` set
    yields `req.proxies==["all:..."]`; with options absent yields env
    capture (env-dependent — assert shape not values, or factor so
    the test env is clean; CI env may carry proxies — prefer testing
    `proxy_pick` purely and asserting plan_req delegates by checking
    `proxies`/`proxy_env` fields are populated consistently with a
    stubbed pairs path if exposed).
- `tui` (`coll_test.oxl`/`cfg_test.oxl`/`send_test.oxl` patterns):
  - `begin_send_preq` on a staged request with `proxy_url` →
    `a.pending.proxies` populated, no "proxy unsupported" toast.
  - ssl.password toast text updated (assert new substring).
  - TLS1.2-cert toast: drive `exec_send_t` with a fake Transport
    returning `Resp{tls_ver: tls.V12}` and a pending req with
    `cert_pem` set → toast contains "empty certificate list";
    `tls_ver: tls.V13` → no toast; `cert_pem:""` → no toast.
- `tui/cli_test.oxl`: headless run with ssl.password+cert configured
  emits the stderr warning once; TLS1.2 resp emits per-request
  warning (fake transport seam if present, else factor the warning
  into a testable helper).
- Regression: existing `h1_test` proxy/CONNECT suite untouched and
  green (transport unchanged).

## Acceptance criteria (verify-checkable)

1. `oxl test` green in every leaf dir (`git ls-files '*.oxl'` dirs).
2. A `.posting.yaml` request with `options.proxy_url: http://127.0.0.1:P`
   routes through the proxy (absolute-form for http targets; CONNECT
   for https) in BOTH interactive send and `oxttp-tui run`.
3. With no `proxy_url`, `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` env
   vars are honored per send under Go `httpproxy` semantics;
   `REQUEST_METHOD` set makes use of `HTTP_PROXY` on an `http:` hop a
   send-time error. `ALL_PROXY` is intentionally ignored (not a Go
   variable).
4. `ssl.certificate_path`/`key_file`/`ca_bundle` behavior unchanged
   (already landed); missing files still abort the send with the
   corpus send-time error.
5. `ssl.password` configured → explicit unsupported warning (new
   wording) in interactive toast and headless stderr; no crash.
6. Client cert + TLS1.2 negotiation → warning surfaced (toast /
   stderr note); TLS1.3 or no-cert → silent.
7. No new config keys, no schema changes to `.posting.yaml`
   decode/encode (`POptions` untouched), no CLI (`oxttp`) changes.
8. Parity matrix rows updated: §7.1 client certs → `done` (with
   DevDs), §7.1 proxy → `done`.

## Deviations (DevDs — documented, none silent)

- **D1** `ssl.password` unsupported: oxl 0.26.0 `x509.parse_key_pem`
  rejects `ENCRYPTED PRIVATE KEY`, no password parameter; legacy
  `Proc-Type: 4,ENCRYPTED` PEM undecoded. Corpus §2.2 lists the key —
  degrade with explicit warning (ADR-0045). Not an oxl bug.
- **D2** Client certs are TLS1.3-only in this build: a TLS1.2
  negotiation sends an empty certificate_list (oxl std tls doc).
  Warning added (S2.2/S2.3); upstream posting/Go presents certs on
  1.2 — real behavioral gap, surfaced not silent.
- **D3** `proxy_url` is scoped `all:` — corpus defines one proxy for
  all requests; per-scheme proxy config doesn't exist upstream either.
- **D4** Env proxy capture is per-send `os.getenv` of the canonical
  Go names (both cases) — Go's `ProxyFromEnvironment` equivalent;
  `os` has no environ iteration so only named vars are read (same
  limitation class as cli `os_envpairs`). Unlike the xh CLI path,
  `ALL_PROXY` is not read because Go `httpproxy` does not define it.
- **D5** `NO_PROXY` is not consulted when `proxy_url` is set —
  corpus "proxy_url else env" reads as full env replacement
  (preserved brainstorm disagreement; upstream posting source not
  re-read this pass — corpus is the contract).
- **D6** No TLS-version config surface exists in posting (corpus
  §2.2/§5.2) — the CLI's `--ssl` pins have no TUI equivalent;
  transport `[V12,V13]` default applies. Documented absence.
- **D7** Cert PEM parse/key-mismatch errors surface as transport
  send failures (toast `send_failed` / run FAILED row), not plan-
  time toasts — corpus "reported at send time" holds; layering kept
  (`core/collection` gains no `net/tls` import).

- **D8** `NO_PROXY` matching differs by client: posting/TUI uses the
  Go matcher (localhost/loopback bypass, port-aware entries, CIDR,
  leading-dot subdomain-only); xh keeps the reqwest matcher. Both
  support IPv4 CIDR entries.
