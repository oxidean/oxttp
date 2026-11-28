# WI-0022 spec — M4f OAuth2 authorization flow

Upstream: Posting `32c45669032342cf9b95d5758af47a0d93de0ad7`; corpus
`docs/corpus/corpus-posting.md` §5.2, §7.6, §7.7, §9. Discovery and decision
record: `artifacts/discovery.md`, `artifacts/brainstorm.md`, ADR-0059 through
ADR-0063. Pin: oxl 0.26.0.

## 1. Goal and scope

Implement Posting 3's OAuth2 authorization behavior in oxttp for ordinary
HTTP requests, the TUI, and `posting run`: authorization-code with PKCE,
client-credentials, token reuse/refresh/forget, strict callback handling, and
secret-safe integration.

### In scope

- `.posting.yaml` OAuth configuration semantics already decoded by
  `core/collection`; substitution, validation, and execution.
- New reusable `core/oauth` engine.
- Memory-only token cache/store with refresh rotation and Forget.
- Browser launch and loopback callback flow for interactive TUI sends.
- Token endpoint POSTs over the existing H1 transport, including request TLS
  and proxy settings, no redirects, 30s timeout, and response caps.
- Authorization header injection and origin-safe redirect behavior.
- TUI OAuth editing/status/Forget integration; blocking synchronous browser
  sign-in.
- Non-interactive OAuth in `posting run`.
- Tests for protocol, validation, storage/cache, callback security, TUI
  integration, and run behavior.

### Out of scope / rejected upstream-compatible surface

- Device authorization flow, resource-owner-password flow, implicit flow,
  and user-configured refresh-token grant. Upstream accepts only
  `authorization_code` and `client_credentials`; every other grant fails.
- Digest authentication, GraphQL/SSE behavior, gRPC transport, WebSocket
  transport. Those are separate work items. `core/oauth` must not prevent
  their later reuse, but WI-0022 acceptance is HTTP + Posting TUI/run.
- OS credential-store persistence. oxl 0.26.0 lacks a safe API (ADR-0059).
- Escape cancellation and fully asynchronous sends (ADR-0061).
- Correcting Basic/Bearer explicit-Authorization precedence outside OAuth
  (ADR-0062 scopes the correction to OAuth only).
- curl import of `--oauth2-bearer` changes: it remains bearer-token import.
  OAuth *export refusal* is required when export exists on this branch.

## 2. Configuration and substitution contract

1. OAuth fields are exactly corpus §5.2: `grant_type`, `authorization_url`,
   `token_url`, `client_id`, `client_secret`, `scope`, `redirect_uri`,
   `client_auth`. No generated token field may be added to request YAML.
2. Defaults match upstream `model.OAuth2.WithDefaults`:
   - empty `grant_type` → `authorization_code`
   - empty `client_auth` → `client_secret_post`
   - empty `redirect_uri` → `http://127.0.0.1:8765/oauth/callback`
3. `collection.plan_req` resolves variables in active fields before any
   validation/cache lookup/token request:
   - all grants: `token_url`, `client_id`, `client_secret`, `scope`
   - authorization-code only: `authorization_url`, `redirect_uri`
   Undefined variables in active fields are send errors before network I/O.
   Undefined values in inactive code-only fields do not block
   `client_credentials`.
4. Defaults are applied after substitution for validation/execution but the
   saved YAML retains the file's original empty/absent fields.
5. Parse-time collection behavior remains as today: unknown/invalid OAuth
   semantics are not malformed YAML; send-time validation reports them.

## 3. Validation contract

Validation errors should use these stable upstream messages exactly where
feasible:

- unsupported grant → `OAuth grant must be authorization_code or client_credentials`
- blank client id → `OAuth client ID is required`
- insecure/invalid token URL → `OAuth token URL must use HTTPS (HTTP is allowed only on loopback)`
- invalid client-auth → `OAuth client authentication must be client_secret_basic or client_secret_post`
- missing client-credentials secret → `OAuth client secret is required for client credentials`
- insecure/invalid authorization URL → `OAuth authorization URL must use HTTPS (HTTP is allowed only on loopback)`
- invalid redirect → `OAuth redirect URI must be an HTTP loopback IP with a port and path, e.g. http://127.0.0.1:8765/oauth/callback`

Rules:

- Token and authorization endpoints: HTTPS, or HTTP only when hostname is
  `localhost` or a loopback IP; no userinfo; no fragment; hostname non-empty.
- Resource URL for HTTP requests: HTTPS or loopback HTTP. Failure:
  `OAuth requests require HTTPS (HTTP is allowed only on loopback)`.
- Redirect URI: scheme `http`, loopback IP literal, explicit port, non-empty
  path, no userinfo/query/fragment. `localhost` is not accepted. Port `0` is
  valid and means ephemeral.
- IPv6 loopback redirect URIs are an explicit oxl limitation: validation may
  accept them semantically but execution must fail clearly as unsupported if
  the listener cannot bind them. Do not silently bind another address.
- Scope is split on whitespace for execution and rejoined with single spaces
  in authorization/token parameters.

## 4. Core architecture contract

Add `core/oauth`, independent of `core/collection` parsing internals. The
public shape may be adjusted for oxl ownership syntax, but must provide these
operations and seams:

```
validate_config(cfg, resource_url) -> err
authorize(manager, cfg, resource, security/plan, interactive, browser, transport)
    -> bearer token/status notes/error
forget(manager, cfg, resource) -> err
```

Required structural properties:

- `core/collection.plan_req` remains pure: it substitutes and packages an
  OAuth plan on `SendPlan`; it does not open sockets or browsers.
- Execution layers (`tui/coll.oxl`, `tui/cli.oxl`) call `authorize` after
  planning and before `Transport.send`.
- `core/oauth` token POSTs use the injected `core/http.Transport` in tests
  and `http.H1{}` in production.
- Browser opening is an injectable function/interface. Tests never depend on
  a real browser.
- The TUI owns one OAuth manager for the app session; each `posting run`
  process owns one manager shared by all requests in that run.
- Future gRPC/WebSocket callers can reuse the manager/config validation and
  token cache without depending on collection decode.

## 5. Cache, storage, reuse, refresh, and Forget

1. Cache entries are keyed by a SHA-256 digest of an unambiguous canonical
   encoding of: collection root, resource origin, fully resolved OAuth config
   after defaults, request `verify_ssl` boolean, and resolved `proxy_url`.
   Changing credentials, endpoints, scopes, collection, or proxy/TLS choice
   must not reuse the prior token.
2. Resource origin for HTTP is `<scheme>://<host>` exactly as parsed
   (case-normalized by URL parsing where upstream would normalize; default
   ports remain part of the URL host when explicit).
3. Token fields: access token, token type, refresh token, expiry time or
   no-expiry. Store values only in memory for this milestone (ADR-0059).
4. A token is valid when access token is non-empty and either no expiry is
   present or current time is before expiry minus 10 seconds. Expiry equality
   inside the 10-second window is invalid.
5. On invalid/expired token:
   - `client_credentials` always performs a new client-credentials grant,
     even if a refresh token exists.
   - `authorization_code` with a refresh token performs a refresh grant.
   - otherwise interactive callers run browser authorization;
     non-interactive callers fail `send the request to authorize OAuth in
     your browser first`.
6. Refresh request uses the latest refresh token. If the refresh response
   omits `refresh_token`, retain the prior refresh token; if present, rotate
   and store the new one.
7. Since oxttp execution is synchronous, one-entry-at-a-time behavior is
   sufficient; the cache representation must not depend on global mutable
   state that leaks across independent app/run instances.
8. `Forget` computes the same key after substitution, removes the in-memory
   token, and succeeds. It does not contact the provider and does not revoke
   consent. UI text must make clear that the next send authorizes again.
9. Whenever a token is acquired or reused from the memory-only store, surface
   the warning once per acquisition path/status channel:
   `OAuth token is kept for this session only (OS credential store unsupported in this build).`
   Do not spam once per redirect or per header render.

## 6. Token endpoint contract

1. Token requests are POSTs with `Content-Type:
   application/x-www-form-urlencoded`, form keys encoded with query escaping
   and sorted deterministically where the implementation builds them
   manually.
2. `client_secret_post`: include `client_id`; include `client_secret` only
   when non-empty. `client_secret_basic`: use HTTP Basic over the
   URL-query-escaped client id and secret and do not duplicate the secret in
   the form.
3. Client-credentials form: `grant_type=client_credentials`, optional
   space-joined `scope`.
4. Refresh form: `grant_type=refresh_token`, `refresh_token`.
5. Code exchange form: `grant_type=authorization_code`, `code`,
   `redirect_uri` (the actual expanded redirect, including ephemeral port),
   `code_verifier`.
6. Token request security settings copy the resource plan: verify mode/CA,
   client certificate/key material, proxy fields, and proxy semantics. Token
   endpoint redirects are never followed. Timeout is 30s and independent of
   the resource request timeout.
7. Response handling mirrors x/oauth2 v0.36.0:
   - JSON responses by default; form/query parsing for
     `application/x-www-form-urlencoded` or `text/plain`.
   - success fields `access_token`, `token_type`, `refresh_token`,
     `expires_in`; error fields `error`, `error_description`, `error_uri`.
   - non-2xx or any non-empty `error` is an endpoint rejection, even when
     HTTP status is 200.
   - JSON `expires_in` accepts integer or integer-string; null/omitted means
     no expiry; wrong type/non-integer/invalid JSON is an invalid response.
     Large positive values may saturate rather than overflow.
   - form `expires_in` parses as integer; absent/zero/unparseable means no
     expiry in the form parser, matching upstream's `Atoi` behavior.
8. Response body cap is 1 MiB. Add an opt-in maximum-body mechanism to the
   request/transport path if needed; ordinary resource behavior is unchanged.
9. Validate acquired tokens: access token non-empty, token type empty or
   case-insensitive `Bearer`, and access token contains no CR/LF. Otherwise
   fail `OAuth endpoint did not return a usable Bearer token`.

## 7. Error sanitization contract

Raw endpoint bodies, transport errors containing userinfo, proxy passwords,
token values, authorization codes, refresh tokens, or client secrets must not
reach UI, stderr, history, or logs. Use these upstream-safe outcomes:

- cancellation/deadline → `OAuth authorization cancelled or timed out; send again to retry`
- endpoint error `invalid_grant` → `OAuth grant expired or was revoked; use Forget OAuth token and sign in again`
- other endpoint rejection → `OAuth token endpoint rejected the request (HTTP <status>); check the client credentials, scope and client authentication method`
- network/proxy/TLS/unreachable endpoint → `OAuth token endpoint could not be reached; check its URL, proxy and TLS settings`
- malformed/noncompliant success response → `OAuth token endpoint returned an invalid response`
- browser opener absent/fails → `could not open the browser for OAuth; check your system browser configuration`

Internal result classification may carry status/error code, but never raw
secret-bearing descriptions or bodies.

## 8. Authorization-code browser and callback contract

1. Generate state and PKCE verifier independently from
   `std/crypto/rand.bytes(32)` and encode with raw URL-safe base64 (43 chars).
   Challenge is raw URL-safe base64 of SHA-256(verifier), method `S256`.
2. Authorization URL query contains `response_type=code`, `client_id`,
   actual `redirect_uri`, optional space-joined `scope`, `state`,
   `code_challenge`, `code_challenge_method=S256`, and
   `access_type=offline`. Existing query in the authorization endpoint is
   preserved and parameters are appended with `&`.
3. Bind/listen before browser launch. Port `0` is replaced by the actual
   listener port in both authorization URL and code-exchange `redirect_uri`.
4. Production browser launcher is injected and argv-based. Non-Windows tries
   `xdg-open` then `open`; Windows uses a non-shell argv launcher. No shell
   interpolation of the URL.
5. Wait budget is 3 minutes from beginning the browser flow. This budget is
   outside the resource request timeout. Since the TUI is synchronous, the UI
   text must say waiting up to three minutes and must not claim Escape works.
6. Callback HTTP behavior:
   - only GET at the exact redirect path and exact Host is eligible; other
     method/host/path → 404
   - missing/duplicate/wrong state → 400 `Invalid OAuth state. Return to the original authorization page.`
   - after valid state, any `error` parameter yields denial result
   - missing/duplicate/empty code without error → 400 `Missing authorization code.`
   - eligible success/denial response is plain text
     `Authorization response received. Return to Posting.` with
     `Cache-Control: no-store` and `Referrer-Policy: no-referrer`
   - first valid outcome wins; duplicate callbacks do not overwrite it
7. Listener caps: request head ≤16 KiB, connection activity deadline ≤5s,
   at most 64 extraneous/nonmatching connections, total wait ≤180s, listener
   closed on every outcome. No request body is needed or retained.
8. State comparison uses a fixed-loop byte-wise comparison when lengths are
   equal; different lengths reject before comparison. Random generation
   failure is an authorization failure, never a fallback to weak randomness.
9. oxl limitation: `std/net.listen` binds IPv4 `INADDR_ANY`; strict Host,
   state, and lifetime caps are required, and the limitation is documented
   (ADR-0061). IPv6 loopback redirect execution may explicitly degrade.

## 9. Resource request integration

1. Authorization happens after `plan_req` and before resource transport send.
   The resource request timeout starts only after OAuth completes.
2. On success, remove/replace every enabled user-supplied `Authorization`
   header and emit exactly one `Authorization: Bearer <access-token>` for an
   OAuth2 request. Disabled rows remain saved but unsent.
3. H1 redirect behavior already strips Authorization cross-origin. Tests must
   pin that OAuth tokens reach the original origin and same-origin redirects
   but never a different origin. No automatic retry/replay on 401.
4. Token acquisition must not mutate the saved `PRequest`, marshaled YAML,
   history request payload, curl export model, or future response history
   beyond the actual response content. Runtime tokens are wire-only.
5. If OAuth authorization fails, the resource request is not sent; failure is
   rendered/recorded as a send failure, not as an HTTP response.

## 10. TUI contract

1. Auth editor supports choosing OAuth 2.0 in the auth-type control. Existing
   non-OAuth editing scope may remain unchanged except as needed for the
   shared type selector.
2. When OAuth2 is selected, render/edit:
   - grant selector: `Code + PKCE` / `Client credentials`
   - `Auth URL` only for code grant
   - `Token URL`
   - `Client ID`
   - `Client secret` (masked in read-only/summary rendering but editable as
     text in the form, consistent with upstream)
   - space-separated `Scopes`
   - `Redirect URI` only for code grant
   - client-auth selector `Body` / `Basic header`
3. Explanatory text matches upstream substance: send fetches/refreshes a
   token; code grants open the browser; variables should be used for secrets;
   literal credentials are saved in request YAML.
4. Edits live in per-tab draft state, survive tab switches, and save back to
   the same nested YAML block through the normal save path. Runtime tokens
   never appear in the editor/draft/save data.
5. During browser authorization the response/status area shows waiting text
   and the Auth status line receives progress/failure/success-safe notes.
   Because sends are synchronous, text is best-effort around the blocking
   call; do not advertise Escape cancellation.
6. Palette contains **Forget OAuth token** for OAuth requests. It clears the
   current resolved configuration's session token, reports success/failure
   safely, and does not claim provider consent revocation. Remove the current
   fake/degraded `OAuth sign-in` row; if a sign-in alias is kept, it must
   invoke the real send path.
7. Memory-only warning is visible in Auth status/toast when tokens are used.
8. curl/grpccurl export of an OAuth request refuses with:
   `OAuth tokens aren't exported; use Posting to send this request, or export its YAML configuration`
   (implementation only where export exists in this branch).

## 11. `posting run` contract

Per ADR-0060:

- Run uses non-interactive OAuth. Client-credentials acquires/reuses/refreshes
  tokens within the run process.
- Authorization-code may reuse/refresh an already valid entry in that
  process. If browser consent is required, the request fails with `send the
  request to authorize OAuth in your browser first`; no browser opens and no
  three-minute wait occurs.
- Since the store is memory-only, a fresh process has no persisted TUI token.
  This is documented and is not treated as a test failure of the ADR-0059
  deviation.
- OAuth authorization failures are per-request failures and participate in
  `--fail-fast`, text output, JSON output, and exit codes exactly like other
  send failures.
- Token endpoint traffic must not appear as extra run results; only resource
  requests produce report entries.

## 12. xh CLI boundary

The xh-compatible CLI (`cli/`) has no Posting OAuth2 configuration surface.
It is unchanged in this WI. `posting run` support lives in `tui/cli.oxl`,
not in xh flag parsing. `--oauth2-bearer` in xh/curl interop remains ordinary
bearer-token behavior and does not invoke OAuth flows.

## 13. Security and resource caps summary

Required caps/rules:

- callback head ≤16 KiB; callback connection ≤5s; extraneous callback
  connections ≤64; browser wait ≤180s; listener always closed
- token endpoint timeout ≤30s; body ≤1 MiB; no redirects
- state/verifier 32 CSPRNG bytes each; no weak fallback
- no plaintext token persistence; no token in YAML/history/export/log/error
- no token cross-origin redirect; no automatic 401 replay
- token endpoint/resource URLs obey HTTPS/loopback rules
- client secrets never echoed in validation or endpoint errors
- request body/header sizes otherwise retain existing transport limits and
  synchronous-send constraints

## 14. Explicit deviations to record in implementation/review

1. Memory-only tokens; no OS credential-store persistence in oxl 0.26.0
   (ADR-0059).
2. `posting run` intentionally supports non-interactive client-credentials
   where pinned upstream fails all OAuth; browser-required code grants refuse
   rather than opening a browser (ADR-0060).
3. No Escape cancellation because the TUI send/event loop is synchronous and
   oxl lacks poll/select/cancellable stdin (ADR-0061).
4. Callback listener binds IPv4 `INADDR_ANY`, not the exact loopback host;
   IPv6 loopback may explicitly degrade (ADR-0061 + implementation note).
5. Exact upstream vault key byte format is not reproduced because no vault
   interop exists; logical cache-key partitioning is preserved.
6. Basic/Bearer explicit-Authorization precedence remains the pre-existing
   oxttp behavior; only OAuth is corrected in this WI (ADR-0062).
7. Browser launcher is a best-effort argv chain rather than terma/OpenURL;
   failure uses the upstream safe error.
8. Cross-kind OAuth integration waits for WI-0020/WI-0021, though core APIs
   are designed for reuse.

## 15. Test strategy

No heavy external provider is required. Use loopback fixture transports and
injected browser openers.

### `core/oauth` unit tests

- defaults/validation matrix: grants, blank id, endpoint schemes, userinfo,
  fragments, redirect host/scheme/port/path/query, client auth modes,
  missing secret, resource HTTP-vs-loopback.
- cache key partition: collection, origin, every config field, verify flag,
  proxy value; same resolved config reuses.
- client_credentials: post-vs-basic secret placement, scope encoding,
  reuse until inside 10s expiry window, renewal after expiry, undefined
  inactive code fields not blocking.
- refresh: uses latest token, rotation stored, missing refresh token retains
  prior, invalid_grant safe error, no refresh token falls to browser/refusal.
- token response parsing: JSON numeric/string/null expires_in, wrong types,
  form response, error-in-200, non-2xx, malformed JSON, missing access token,
  non-Bearer type, CRLF token, 1 MiB cap.
- token endpoint transport: no redirects, 30s timeout fields, TLS/proxy fields
  copied, raw error sanitization.
- browser flow: deterministic injected randomness/opener where possible;
  authorization query exact, wrong state 400, missing code 400, wrong path
  404, denial success-page + safe error, first outcome wins, listener closes,
  port 0 expansion, timeout/cleanup, caps.
- store/forget: same-key forget, different scope unaffected, memory-only
  warning, restart equivalent (new manager) has no token.

### `core/collection` / planner tests

- active-field substitution and inactive-field exemption for client
  credentials.
- OAuth plan attached without network side effects.
- unsupported OAuth validation errors surface as send errors.
- YAML round-trip remains unchanged and contains no token fields.

### H1/transport tests

- token POST body cap honored; redirects not followed when follow=false.
- cross-origin resource redirect strips OAuth Authorization; same-origin
  retains it; no 401 replay.

### TUI tests

- OAuth form renders all fields conditionally; editing survives tab switch;
  save/load YAML round-trip.
- Send uses fake OAuth manager/transport seam: success injects exactly one
  bearer header; explicit Authorization row is replaced; authorization
  failure prevents transport send and shows safe error.
- Forget palette appears only for OAuth and clears same-configuration token.
- No fake `OAuth sign-in` degrade remains.
- Secret masking in static/summary rendering; no token in screenshot/history
  fixture data.

### `posting run` tests

- client_credentials fake endpoint + fake resource: passes and exit 0.
- reuse across two same-configuration requests in one run; changed scope
  acquires separately.
- authorization-code without usable token fails with non-interactive error,
  no browser opener invoked.
- failure participates in fail-fast/text/JSON/exit codes.
- token endpoint response body/secrets never appear in stderr/stdout JSON.

## 16. Acceptance criteria

1. `oxl build` and per-leaf `oxl test` are clean for every touched package
   (`core/oauth`, `core/collection`, `core/http` if capped, `tui`; plus
   normal impacted leaf loop), without multi-arg test invocation.
2. Every upstream `oauth_test.go` behavior applicable to HTTP, memory store,
   synchronous execution, and ADR deviations has an oxttp twin:
   client-credentials styles/reuse/forget/isolation, PKCE rotation,
   cancellation/denial equivalents, redirect/no-replay, safe errors.
3. Device/password/implicit/unknown grants fail validation; only code+PKCE
   and client-credentials execute.
4. Browser flow test proves S256 challenge, exact state validation, callback
   response semantics, code exchange verifier/redirect match, listener
   cleanup, and no token endpoint redirect following.
5. Token storage is memory-only, warning is explicit, refresh rotation works
   in-session, Forget works, and no plaintext token file exists.
6. TUI can edit/save OAuth configuration, authorize/send, refresh/reuse, and
   forget; status/error text is safe and no Escape claim appears.
7. `posting run` executes client_credentials non-interactively and refuses
   browser-required authorization-code acquisition with the specified error.
8. OAuth bearer replaces explicit Authorization for OAuth requests and never
   crosses resource origins; 401 is not replayed.
9. Secrets/tokens do not appear in YAML, history request configuration,
   exports, logs, stderr/stdout reports, or sanitized errors.
10. All deviations in §14 are explicitly documented in review artifacts; no
    silent mismatch remains.
