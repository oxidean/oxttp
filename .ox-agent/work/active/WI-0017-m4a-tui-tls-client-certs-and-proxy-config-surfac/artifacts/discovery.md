# WI-0017 discovery — M4a TUI TLS client certs and proxy config surface

Pin: oxl **0.26.0**. Corpus: `docs/corpus/corpus-posting.md` §1.1/§2.2/§5.2/§7.1,
`docs/corpus/corpus-xh.md` §4.5 (flag semantics the CLI ported in WI-0013).
Parity rows this WI owns (matrix): posting §7.1 client certs (`next`),
posting §7.1 HTTP proxy (currently "proxy warns"), §2 config `ssl.*` +
`options.proxy_url`/`verify_ssl` leaves.

## Verified upstream/toolchain surfaces (read first-hand)

### Transport already complete (`core/http/h1.oxl`, WI-0013)

- `model.Req` carries `ssl_min`/`ssl_max` (int, tls.V12=771/V13=772, 0 =
  default), `cert_pem`/`key_pem` (combined-PEM convention: empty key_pem
  ⇒ cert_pem is the combined file), `proxies []str` (verbatim
  `PROTO:URL` entries), `proxy_env []str` ("NAME=value"), `no_proxy str`.
- `tls_wrap` (~L951–1009): `cfg.min_ver/max_ver` ← req pins, 0 ⇒
  `[V12,V13]` auto range (ADR-0032); `tls.load_cert_pem(cert_pem,
  key_pem ?: cert_pem)` → `cfg.client_cert`.
- `pick_proxy` (~L1065): explicit `proxies` win (last match per hop);
  else `proxy_env` scheme match (`<scheme>_proxy` then `all_proxy`,
  case-insensitive names, trimmed values, explicit-empty = unset) then
  `no_proxy` bypass (`*` or host/subdomain match). Per-hop re-resolution
  across redirects.
- http-via-proxy → absolute-form target + `Proxy-Authorization` from
  proxy-URL userinfo; https-via-proxy → CONNECT tunnel
  (`proxy_connect`), non-http(s) proxy schemes degrade with
  `http: proxy URL scheme "<sch>" is unsupported in this build`.
- `Resp.tls_ver` (0 cleartext / V12 / V13) is populated — the TUI can
  detect the TLS-1.2-negotiated-with-cert case.
- oxl 0.26.0 `std/net/tls`: `Config.client_cert` is **TLS 1.3-only** —
  the 1.2 fallback answers CertificateRequest with an empty
  certificate_list (std comment, tls.oxl L7–9). Matrix already notes:
  "negotiated 1.2 sends empty cert list".
- oxl 0.26.0 `std/crypto/x509.parse_key_pem` **rejects**
  `ENCRYPTED PRIVATE KEY` ("x509: encrypted private keys unsupported")
  and has no password parameter; legacy `Proc-Type: 4,ENCRYPTED` PEM
  isn't decoded either. ⇒ `ssl.password` cannot be honored this WI —
  stays a documented degrade (was toasted "lands with mTLS M4"; this IS
  M4a, so the message/DevD must be re-worded to "unsupported in this
  build"). Candidate upstream gap (missing feature, not a bug).
- `std/os` exposes `getenv(name)` only — no environ iteration. Enough:
  proxy env fallback needs exactly HTTP_PROXY/HTTPS_PROXY/ALL_PROXY/
  NO_PROXY (+ lowercase twins). `core/collection` already imports
  `std/os`.

### TUI state today

- `core/collection.plan_req` (L1812+): builds `model.Req` from
  `PRequest` — `verify_ssl:false` → `verify="no"`; **`proxy_url`
  non-empty → warn "proxy unsupported in this build — sending direct"
  and drops it** (L2097). No env proxy capture anywhere in TUI.
- `tui/coll.oxl` `send_plan` (~L982–1053): calls `plan_req`, toasts
  warns, then folds app settings — `ssl_ca_bundle` → `verify` (gated on
  `verify != "no"`), `ssl_certificate_path`/`ssl_key_file` read eagerly
  into `cert_pem`/`key_pem` with file-not-found toasts that abort the
  send; `ssl.password` non-empty → toast "unsupported — encrypted keys
  land with mTLS M4". Runs at send time ⇒ corpus "client-cert/password
  problems are reported at send time" already holds.
- `tui/cli.oxl` headless `run` (~L548–590): same ssl.* fold inline
  (ca_bundle gated on verify, cert/key reads, FAILED rows on missing
  files). Does NOT handle `ssl.password` at all and drops `proxy_url`
  via the same plan_req warn.
- `tui/types.oxl` App carries `ssl_ca/ssl_cert/ssl_key/ssl_pass`;
  `tui/cfg.oxl` L1326–1329 loads them from `config.Settings`
  (`ssl.*` leaves already decode in core/config — 4 keys only).
- `draft_to_request` carries `r.options` verbatim from the file ⇒
  `proxy_url` survives draft edits; `opts_render` already prints it.
- TLS version pins: **no posting surface exists** — corpus §2.2 `ssl.*`
  is exactly 4 keys (ca_bundle, certificate_path, key_file, password);
  §5.2 `options` has no TLS-version key. Default `[V12,V13]` range
  applies. ⇒ nothing to add; document as corpus-faithful absence (the
  WI title's "TLS version pins" maps to the CLI's `--ssl`; posting has
  no equivalent — DevD/note, not invented config).

## Corpus semantics to honor

- §7.1: "Proxy: `proxy_url` else env `HTTP(S)_PROXY`/`NO_PROXY`." —
  explicit `proxy_url` replaces env lookup entirely (mirror of xh
  `--proxy` disabling env proxies, corpus-xh §4.5). `NO_PROXY` is part
  of the env fallback; when `proxy_url` is set the env set (incl.
  NO_PROXY) is not consulted — decision to pin in spec.
- §7.1: "TLS: system roots + `ssl.ca_bundle`; client cert; per-request
  `verify_ssl`." — verify_ssl=false must also suppress ca_bundle
  (already gated) and presumably still allow client cert (mTLS with
  self-signed server cert + verify off is a real posting use).
- §2.2: `ssl.key_file` — "Client key PEM (else read from
  certificate_path)" ⇒ combined-PEM fallback already correct in
  transport; `ssl.key_file` without `certificate_path` is meaningless
  upstream (key has no cert to pair) — keep ignoring it, note it.
- §1.1: `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` are launch env vars ⇒
  env fallback applies to every send, interactive and `run`.
- `proxy_url` value shape: posting stores a URL (`http://host:port`,
  possibly with userinfo). Transport expects the `scheme://…` URL after
  the `PROTO:` prefix is stripped? — CHECK: `pick_proxy` parses entries
  as `--proxy` "PROTO:URL" form. `proxy_url` has NO protocol prefix ⇒
  plan must normalize to `all:<url>` (or scheme-mapped entries) before
  stuffing `proxies`. Verify exact expectation in h1.oxl pick_proxy
  during spec/impl.
- proxy_url + gRPC requests: corpus §5.2 says gRPC requests can't have
  `proxy_url` — decode should already reject/ignore; verify.

## Test surface

- `core/http/h1_test.oxl` already covers proxy selection, CONNECT,
  env capture semantics, scheme degrades — reusable fixture `Fixture`
  acts as the proxy.
- New coverage needed: `core/collection` plan_req proxy wiring
  (collection_test/load_test or new plan test), `tui/coll` send_plan
  ssl fold + proxy env (coll_test/cfg_test patterns), `tui/cli` run
  path parity, app-settings ssl.password wording.
- oxl test loop is per-leaf-dir (`oxl test ./<dir>`); run
  `git ls-files '*.oxl'` dirs.

## Risks / open questions for brainstorm

1. `proxy_url` normalization: bare URL vs `PROTO:URL` — pick_proxy
   input contract must be confirmed; likely wrap as `all:`+url.
2. Env capture timing: read `os.getenv` inside plan_req (per-send,
   picks up runtime changes — matches "env vars at launch" closely
   enough; posting reads them per-request via Go http.ProxyFromEnvironment
   anyway).
3. TLS1.2+cert silent-empty-list: add a send-time warning mirroring
   CLI W2 (`resp.tls_ver==V12 && cert_pem!=""`)? CLI warns once at
   quiet<2; TUI toast seems right — corpus silent ⇒ DevD note.
4. `ssl.password`: keep degrade; reword toast (no "lands with M4"
   promise); DevD entry. Consider oxl issue? Missing feature, not a
   bug — likely not worth an issue; decide at ship.
5. `use_host_environment`-style gating: none needed.
