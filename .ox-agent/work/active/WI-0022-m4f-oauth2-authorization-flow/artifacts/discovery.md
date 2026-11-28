# WI-0022 discovery — M4f OAuth2 authorization flow

Pin: oxl **0.26.0** (`.oxl-version`). Corpus: `docs/corpus/corpus-posting.md`
§5.2 (auth schema), §7.6 (Auth), §7.7 (curl export refusal), §9 (P3-only
caveat). Upstream pinned commit `32c45669032342cf9b95d5758af47a0d93de0ad7`
(`v3.0.0-beta.1`) was fetched read-only to `/tmp/posting-oauth-src`; primary
sources are `internal/client/oauth.go`, `internal/client/oauth_test.go`,
`internal/model/request.go`, `internal/model/resolve.go`,
`internal/client/http.go`, `internal/ui/oauth.go`, `internal/ui/curl.go`,
`cmd/posting/run.go`, and `docs/guide/requests.md`. The upstream Go library
version is `golang.org/x/oauth2 v0.36.0` (`go.mod`), inspected read-only in
`/tmp/oauth-gomod` for token-parse/refresh/PKCE details.

## Verified upstream semantics

### Configuration surface and substitution

- `model.OAuth2` is configuration only, never a token cache
  (`internal/model/request.go:124-150`): `grant_type`,
  `authorization_url`, `token_url`, `client_id`, `client_secret`, `scope`,
  `redirect_uri`, `client_auth`.
- Defaults (`WithDefaults`): grant `authorization_code`, client-auth
  `client_secret_post`, redirect `http://127.0.0.1:8765/oauth/callback`.
- `.posting.yaml` carries the same nested block (corpus §5.2;
  `internal/collection/format.go:64-73,191-195,293-295`). Round-trip test
  pins all fields verbatim (`collection_test.go:128-158`).
- Variable substitution happens before authorization/cache-keying
  (`model/resolve.go:95-107`): token URL, client id/secret, scope always;
  auth URL and redirect URI only for `authorization_code`. Undefined
  variables in active fields fail before any token request. Unused code-grant
  fields may remain undefined when grant is `client_credentials`
  (`oauth_test.go:118-124`).
- Only `authorization_code` and `client_credentials` are valid
  (`oauth.go:225-245`). Device authorization, password, implicit, and
  refresh-token-as-user-configured grants are rejected:
  `OAuth grant must be authorization_code or client_credentials`.

### Endpoint/resource validation and authorization-code browser flow

- `client_id` must be nonblank. Token URL must be HTTPS, or HTTP only on
  loopback/localhost, with no userinfo or fragment (`oauth.go:230-235,
  259-268`). Authorization URL has the same rule for code grants
  (`oauth.go:247-250`). Exact user-facing errors are stable and should be
  mirrored closely.
- `client_auth` must be `client_secret_basic` or `client_secret_post`;
  client-credentials requires a non-empty secret (`oauth.go:236-245`).
  Public PKCE clients use post with an empty secret (model comment
  `request.go:134-136`).
- Resource URLs using HTTP/GraphQL/WebSocket must be HTTPS except loopback
  (`oauth.go:115-122`); WebSocket is tested after mapping `ws`→`http` /
  `wss`→`https`. OAuth gRPC requires TLS (`oauth.go:123-130`).
- Redirect URI must be HTTP on a loopback **IP**, with explicit port and
  non-empty path, and no userinfo/query/fragment (`oauth.go:270-278`).
  `localhost` is not accepted here even though endpoint validation allows
  it. Port `0` means ephemeral and is substituted into the authorization URL
  (`oauth.go:289-297`; docs `requests.md:167-171`).
- Browser flow (`oauth.go:281-361`):
  - bind the redirect host/port before opening the browser;
  - generate two independent 32-byte random base64url values: `state` and
    PKCE verifier (`x/oauth2/pkce.go`); challenge is
    `base64url-no-pad(sha256(verifier))`, method `S256`;
  - authorization query is `response_type=code`, `client_id`, `redirect_uri`,
    optional space-joined `scope`, `state`, PKCE challenge/method, and
    `access_type=offline` (`x/oauth2/oauth2.go:159-181`);
  - callback accepts only GET with exact Host and path. Wrong/missing state,
    duplicate state, or missing/duplicate/empty code is HTTP 400. Wrong
    method/host/path is 404. `error` in query becomes denial after state
    validation. Successful/denied callback responses include
    `Cache-Control: no-store`, `Referrer-Policy: no-referrer`, plain-text
    body `Authorization response received. Return to Posting.`
  - browser wait has its own 3-minute budget outside the resource request
    timeout; upstream Escape cancellation comes from the send context.
  - after callback, exchange POST is `grant_type=authorization_code`, `code`,
    `redirect_uri`, `code_verifier` (`x/oauth2/oauth2.go:222-233`).
- Browser-open failure, denial, cancellation, and timeout are sanitized to
  stable errors (`oauth.go:342-359,370-371`).

### Token endpoint requests, parsing, refresh, and validation

- Token endpoint requests inherit the resource request's TLS/proxy settings
  through the upstream HTTP transport (`oauth.go:151-162`; docs
  `requests.md:193-195`). Redirects are never followed because a 307/308
  could forward secrets. Token endpoint timeout is 30s.
- Client credentials request body: `grant_type=client_credentials` plus
  optional space-joined `scope` (`x/oauth2/clientcredentials/...
  clientcredentials.go:89-112`).
- Refresh request body: `grant_type=refresh_token`, `refresh_token=<latest>`
  (`x/oauth2/oauth2.go:267-293`). Client credentials never use a refresh
  token; a fresh client-credentials grant is acquired instead
  (`oauth.go:167-175`).
- Client authentication style is explicit, so no auth-style fallback probe:
  `client_secret_post` puts `client_id` and non-empty `client_secret` in the
  form; `client_secret_basic` uses HTTP Basic with URL-query-escaped id and
  secret (`x/oauth2/internal/token.go:171-214`).
- Response parsing accepts JSON by default and form/text responses
  (`x/oauth2/internal/token.go:264-331`): `access_token`, `token_type`,
  `refresh_token`, `expires_in` (number or numeric string; null means no
  expiry). Error bodies may contain secrets and must never be copied into
  UI errors (`oauth.go:364-386`). Token response body is capped by upstream
  library at 1 MiB.
- Tokens are valid when access token is non-empty and expiry, if present,
  is more than 10s in the future (`x/oauth2/token.go:17-23,138-154`).
  Missing/zero expiry means reuse forever.
- A refresh response without `refresh_token` retains the prior refresh token
  (`x/oauth2/internal/token.go:250-256`); a rotated one replaces it.
- After any acquisition the token must be a Bearer token: non-empty access,
  empty or case-insensitive `Bearer` type, and no CR/LF in the access token
  (`oauth.go:184-186`). Upstream then returns wire-only bearer auth; runtime
  tokens never mutate request YAML/history/export configuration.
- Error sanitization (`oauth.go:364-386`): cancellation/deadline →
  `OAuth authorization cancelled or timed out; send again to retry`;
  `invalid_grant` → `OAuth grant expired or was revoked; use Forget OAuth
  token and sign in again`; other HTTP rejection → status-only generic
  credentials/scope/client-auth message; transport failure → generic
  URL/proxy/TLS message; malformed success → `OAuth token endpoint returned
  an invalid response`.

### Token cache, storage, concurrency, and forget

- Cache key is SHA-256 of JSON tuple `[collection root, resource origin,
  resolved OAuth config with defaults, verify_ssl, proxy_url]`
  (`oauth.go:61-83`). Keys contain no secret material in cleartext but do
  depend on resolved secret values through the tuple hash. Resource origin
  for HTTP-ish kinds is `scheme://host`; gRPC appends authority.
- One entry per key has a cancellable lock so concurrent sends cannot spend
  the same rotating refresh token twice (`oauth.go:48-55,78-90`). oxttp's
  current TUI and run paths are synchronous, but the core design should not
  preclude concurrency.
- Upstream persistent store is the OS credential store under service
  `posting.oauth2` (`oauth.go:36-46`): macOS Keychain, Windows Credential
  Manager, Linux Secret Service. On store failure upstream warns
  `OS credential store unavailable: OAuth token is kept for this session
  only.` and uses memory only; it never writes plaintext token files
  (`docs/guide/requests.md:180-184`).
- Stored unreadable JSON → `stored OAuth token is unreadable; use Forget
  OAuth token to reset it` (`oauth.go:137-143`).
- `Forget` resolves variables, computes the same key, clears memory first,
  deletes vault best-effort, and reports when vault deletion failed
  (`oauth.go:205-222`). It does not revoke provider consent. Palette label is
  **Forget OAuth token**, shown only for OAuth2 requests
  (`internal/ui/overlays.go:129-133`); docs describe the same behavior.
- 401 responses are never retried/replayed automatically
  (`docs/guide/requests.md:173-178`; `oauth_test.go:365-413`).

### Header and redirect behavior

- OAuth authorization runs before the resource request timeout starts
  (`internal/client/http.go:84-99`).
- The generated bearer Authorization is set after user headers and therefore
  replaces an explicit `Authorization` row for the OAuth request
  (`internal/client/http.go:149-171`; docs `requests.md:146-148`). This is a
  correction to the S10 assumption in oxttp, where explicit rows currently
  win for all auth types (`core/collection/collection.oxl:2210-2234`).
- Redirects to a different origin must not receive the OAuth token
  (`internal/client/http.go:193-197`; test `oauth_test.go:365-394`). oxttp's
  H1 redirect logic already strips all `Authorization` cross-origin in
  `redirect_headers` (`core/http/h1.oxl:226`), satisfying the token-leak
  requirement; same-origin redirects retain it.
- curl/grpccurl export refuses OAuth requests rather than leaking/generated
  tokens: `OAuth tokens aren't exported; use Posting to send this request,
  or export its YAML configuration` (`internal/ui/curl.go:110-118`).

### TUI and headless integration

- Upstream Auth editor is editable: grant tab strip (Code + PKCE / Client
  credentials), auth URL and redirect fields visible only for code grant,
  token URL/client id/secret/scope inputs, client-auth Body/Basic tab strip,
  and explanatory text (`internal/ui/oauth.go:14-87`). Values save into the
  same YAML block.
- Upstream response view can show `Waiting for the OAuth callback · esc
  cancels`; cancellation is context-driven (`internal/ui/response_view.go`).
- Upstream `posting run` constructs `client.NewHTTP` but does **not** attach
  an OAuth instance (`cmd/posting/run.go:194-200`). Since `authorize` on a
  nil OAuth returns `OAuth 2.0 is not configured` (`oauth.go:99-105`),
  pinned upstream headless run currently fails every OAuth2 request,
  including client_credentials. No docs carve-out was found. This is an
  upstream-behavior decision point for WI-0022, not an accidental oxttp gap.
- OAuth also integrates with GraphQL, TLS gRPC, and WebSocket upstream;
  gRPC reflection is non-interactive and never opens a browser
  (`oauth.go:95-99,176-179`; docs `requests.md:193-197`). Those kinds are
  owned by WI-0020/WI-0021 in oxttp and are not present on this branch.

## oxttp repo state today

- `.posting.yaml` decode/encode already has `POAuth2` with all eight corpus
  fields (`core/collection/collection.oxl:46-56,736-777,1394-1422`) and
  round-trip tests (`core/collection/load_test.oxl:98-100`). No semantic
  validation is applied at parse time, matching upstream (validation happens
  at send).
- `plan_req` currently rejects OAuth: `oauth2 auth lands M4 — unsupported
  in this build` (`core/collection/collection.oxl:2230-2233`). It also
  performs no OAuth-specific substitution because it never reaches those
  fields.
- TUI Auth pane is a read-only text rendering; OAuth display currently
  omits grant-dependent endpoint/redirect/client-auth fields
  (`tui/coll.oxl:490-516`). There is no editable OAuth form and no Forget
  palette command. Auth/Options editing was explicitly deferred in S10.
- `tui/cli.oxl` headless `posting run` uses `collection.plan_req` then H1
  synchronously (`tui/cli.oxl:523-631`), so OAuth currently fails at plan
  time before transport.
- H1 is synchronous and already owns redirect following, proxy selection,
  TLS verification/client certs, timeout budget, and cross-origin auth
  stripping (`core/http/h1.oxl`). Token exchange can reuse a `model.Req`
  through this transport instead of adopting std/net/http.
- curl import maps `--oauth2-bearer` to bearer-token auth (`tui/curlimp.oxl`);
  there is no export implementation yet in this branch for OAuth refusal.

## oxl 0.26.0 API surface relevant to design

Verified read-only under
`/home/jesse/.oxl/versions/v0.26.0/oxl-toolchain/std`:

- `std/crypto/rand.bytes(n)` and `fill`; `std/crypto/sha256.sum256`;
  `std/encoding/base64.url_encode_raw` — enough for state, PKCE verifier,
  challenge, and cache keys.
- `std/net/url.parse`, `hostname`, `port`, query escape/unescape,
  `parsequery`, `vadd/vencode` — enough for validation and form encoding,
  though some helpers are value-oriented and need local wrappers.
- `std/net.listen(port)`, `Listener.port/rawfd/accept/close`, socket
  `set_rcvtimo_ms` — enough for a bounded callback listener. **Important
  limitation:** `net.listen` binds `INADDR_ANY` (`std/net/net.oxl:313-339`),
  not the redirect loopback host. Host/path/state checks mitigate misuse but
  cannot make the socket loopback-only in oxl 0.26.0.
- `std/os/exec.cmd(...).run/output` passes argv arrays without a shell —
  enough for a best-effort platform browser launcher (`xdg-open`, `open`,
  Windows shell resolution). There is no cross-platform `openURL` API.
- There is **no OS credential-store/keyring/Secret Service API** in std.
  Persistent-token parity therefore needs either a new explicit degrade
  (memory-only) or a carefully bounded platform-helper strategy; plaintext
  token files are forbidden by upstream semantics.
- `std/encoding/json` exists but does not expose convenient typed object
  member access or integer-preserving dynamic access beyond `jget`; token
  JSON parsing can use it plus manual extraction/validation. Its numeric
  coercion means `expires_in` needs careful handling; form-encoded token
  responses are straightforward string parsing.
- No constant-time compare helper is exposed. State comparison can be a
  fixed-loop byte-wise compare over equal-length 43-char verifier strings;
  length mismatch is rejected before comparison.
- `std/sync` is spinlock-only and the app is synchronous. Per-entry locking
  is mostly architectural future-proofing; implementation should not bake in
  a blocking concurrent model oxlp cannot express cleanly.

## Constraints, gaps, and decision points

1. **Vault gap:** no oxl keyring API. Choices: memory-only explicit degrade
   vs platform-helper vault (`secret-tool`/`security`/PowerShell) vs defer
   persistence upstream. Plaintext files are not acceptable.
2. **Headless run mismatch:** exact upstream behavior fails OAuth in
   `posting run`; product usefulness argues for non-interactive support
   (client_credentials and reuse/refresh, no browser) as a documented
   deviation. Needs ADR.
3. **Synchronous TUI:** oxttp send blocks the event loop (ADR-0032). Upstream
   browser authorization waits up to 3 minutes and Escape cancels through
   context. A synchronous implementation cannot process Escape unless the
   send architecture changes. Choices: accept no-Esc blocking degrade, or
   scope an OAuth-specific event-loop/state-machine integration.
4. **Loopback listener:** oxl `net.listen` binds all interfaces, unlike
   upstream `net.Listen("tcp", redirect.Host)`. State+Host validation and a
   short-lived listener mitigate but do not eliminate exposure. Needs ADR.
5. **Auth precedence correction:** upstream OAuth bearer overrides an
   explicit Authorization row; S10 implemented explicit-row-wins. Decide
   whether WI-0022 corrects only OAuth (minimal) or all auth types
   (upstream-faithful but broader regression surface).
6. **Cross-kind dependency:** GraphQL/SSE and gRPC/WS are separate active
   work items. This item should expose a reusable core OAuth engine and wire
   HTTP/run/TUI now; cross-kind calls should either be integration-ready
   hooks or explicit follow-ups, not silent omissions.
7. **Editable Auth UI:** upstream supports editing OAuth fields. oxttp's
   Auth pane is read-only by prior milestone deferral. Decide whether M4f
   implements full editing or the minimum runtime flow plus Forget command;
   the corpus parity matrix marks Auth as a major §7.6 feature, so silent
   read-only behavior is not acceptable.
