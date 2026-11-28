# WI-0022 brainstorm — M4f OAuth2 authorization flow

Discovery: `artifacts/discovery.md`. Upstream semantics are pinned and rich;
the design questions are how to map them onto oxttp's synchronous pure-oxl
architecture and oxl 0.26.0's missing browser/keyring/loopback-bind APIs.

## Decision frame

Non-negotiables from corpus/upstream:

- Support exactly `authorization_code` with PKCE and `client_credentials`.
  Device authorization, password, implicit, and user-configured refresh
  grants are out of scope and must fail with the upstream validation error.
- Tokens are runtime secrets, never serialized into request YAML, history
  request configuration, curl/grpccurl export, logs, or error text.
- Token endpoint redirects are never followed; resource redirects to another
  origin never carry the OAuth token; 401 does not replay.
- Endpoint/resource validation and sanitized errors are security behavior,
  not cosmetic behavior.
- No plaintext token file fallback.

Open trade-offs are below. Recommendation first, then alternatives and the
reasoning preserved.

## D1 — token persistence: memory-only for oxl 0.26.0

**Recommendation:** implement a `core/oauth` token-store port with an
in-memory store for this milestone. Warn explicitly that OS credential-store
persistence is unsupported in this build. Do not shell out to password tools
and do not write tokens to disk.

Why:

- oxl 0.26.0 has no keyring/Secret Service/Keychain/Credential Manager API.
- `std/os/exec` cannot supply stdin to a child. Linux `secret-tool store`
  would require the secret on stdin; putting it in argv or environment would
  expose it. macOS `security` and Windows PowerShell helper paths have the
  same or worse secret-in-argv/problematic quoting properties.
- Upstream forbids plaintext-token fallback. A hand-rolled D-Bus/Secret
  Service implementation is a separate security-sensitive project, not an
  M4f implementation detail.
- Memory-only still exercises correct cache keying, reuse, refresh rotation,
  Forget, and warning behavior within a TUI session or one `run` process.

Consequences/deviations:

- Tokens do not survive restart. Authorization-code users sign in again per
  TUI session/process; client-credentials grants re-acquire per process.
- Warning text should be honest rather than impersonating an OS-store failure:
  `OAuth token is kept for this session only (OS credential store unsupported
  in this build).`
- Keep a narrow `TokenStore` interface (`get/set/delete`) so a future oxl
  keyring API or audited platform integration can restore upstream parity
  without redesigning the engine.

Rejected alternatives:

1. **Plaintext file with 0600 permissions** — simplest persistence but a
   direct upstream/security violation.
2. **Platform CLI vault helpers** — secret cannot be passed safely with the
   current exec API; platform matrix is uneven and unaudited.
3. **No cache at all** — would make refresh rotation and concurrent/repeated
   send semantics impossible to test meaningfully.

## D2 — headless `posting run`: non-interactive OAuth, deliberate positive deviation

**Recommendation:** wire OAuth into `posting run` with `interactive=false`.
Client-credentials works unattended. Authorization-code may reuse or refresh
an already valid cached token, but if acquisition requires browser consent it
fails with the upstream non-interactive error `send the request to authorize
OAuth in your browser first` rather than opening a browser or waiting three
minutes.

Why:

- Pinned upstream `posting run` forgets to attach an OAuth instance, making
  every OAuth request fail as `OAuth 2.0 is not configured`. That behavior
  conflicts with the user-facing docs/agents contract that `run` uses the
  authentication defined in files, and it makes client-credentials pointless
  in the place it is most useful.
- A headless/agent-facing runner must never surprise-open a browser or block
  for three minutes.
- Because D1 makes storage memory-only, authorization-code reuse across
  separate run processes will not exist until persistent vault support lands.
  This limitation is explicit, not hidden.

Deviation recorded: oxttp intentionally improves on pinned upstream's nil
OAuth wiring by supporting non-interactive client-credentials in `run`, while
still refusing browser acquisition headlessly.

Rejected alternatives:

1. **Byte-match upstream and fail all OAuth run requests** — maximally
   source-faithful but codifies what looks like an upstream integration bug
   and fails the user's requested CLI/run integration.
2. **Allow browser flow in run** — dangerous for automation/agents, no
   cancellation path in oxlp, and can stall for three minutes.

## D3 — TUI interaction: synchronous blocking browser wait, no Escape cancellation in this build

**Recommendation:** run authorization inside the existing synchronous send
path. Preserve the upstream three-minute browser budget, listener behavior,
status text, and denial/timeout errors. Document that Escape does not cancel
OAuth in oxttp because the terminal event loop is already blocked for sends
under ADR-0032 and oxl has no poll/select or cancellable stdin-read primitive.

Why:

- The current TUI paints `Sending…` then blocks in `exec_send`; there is no
  async response machinery to reuse.
- A proper OAuth-only async state machine cannot poll both stdin and the
  listener in oxl 0.26.0: stdin reads block, listener accepts block, and no
  select/poll API exists. Spawned stdin readers cannot be cancelled and would
  keep consuming input after OAuth finishes.
- Correctness and token security are more important than pretending the Esc
  hint is functional.

Mitigations:

- Do not display the upstream suffix `(Esc cancels)` unless cancellation is
  actually implemented; display `waiting up to 3 minutes` instead.
- Keep the browser-wait logic isolated behind a function/interface so a
  future terminal async/runtime poll API can add cancellation without
  changing token semantics.
- Keep the listener accept bounded with short socket timeouts, total 3-minute
  deadline, 5-second per-connection header/read cap, small header cap, and a
  bounded number of extraneous connections.

Rejected alternatives:

1. **Redesign all sending as asynchronous in this WI** — large cross-cutting
   rework of input, rendering, cancellation, ownership, and test harness;
   not justified by OAuth alone.
2. **Fake cancellation by closing the listener only** — does not stop the
   blocked token exchange/browser wait cleanly and can leak goroutine-like
   workers in oxl.
3. **Shorten to 30s** — violates upstream user behavior for a normal sign-in.

## D4 — callback listener exposure: strict validation plus documented INADDR_ANY limitation

**Recommendation:** implement the upstream callback semantics exactly at the
HTTP layer, but record an upstream-limited deviation that oxl `net.listen`
binds all interfaces rather than the requested loopback host.

Required mitigations:

- Accept only redirect URIs that are loopback IP + explicit port + non-empty
  path, as upstream does.
- Prefer and document port `0` support; bind ephemeral ports where possible.
- Exact Host and path checks before parsing; only GET; exactly one state;
  fixed-loop state comparison after length check; exactly one non-empty code;
  denial only after valid state.
- Constant small caps: request head ≤16 KiB, per-connection read/write deadline
  ≤5s, at most 64 nonmatching/extraneous connections before failing the login,
  one callback result wins, listener closes immediately after outcome.
- No-store/no-referrer/plaintext response body.

This is not full parity with loopback-only binding. It is acceptable only
because state is 256-bit random, Host/path/state are strict, and the listener
is short-lived. A future oxl bind-address API should close the gap.

Rejected alternative: using redirect hostnames other than loopback or skipping
Host validation because the listener is already exposed — both weaken the
upstream security contract.

## D5 — architecture: `core/oauth` engine, collection plan resolves config, app layer authorizes

**Recommendation:** add a pure-core package shaped approximately as:

```
core/oauth
  OAuth2Config   // resolved cfg + defaults, no token
  Token          // access/refresh/type/expiry
  TokenStore     // get/set/delete port; memory implementation here
  Manager        // entries keyed by resolved config/resource/security tuple
  validate_config(...)
  authorize(...) -> bearer token + notes + err
  forget(...)
  browser_flow(...) // injectable browser opener for tests
  token_post(...)   // uses core/http.Transport seam
```

`collection.plan_req` should continue to be pure but gain an OAuth plan:
it substitutes active OAuth fields, applies defaults, validates nothing
network-dependent, and carries the resolved config/resource/security inputs
on `SendPlan`. The TUI/run execution layer then calls `oauth.authorize`
before `Transport.send`, and on success overrides/adds the bearer header.

Why this boundary:

- Keeps YAML/env planning testable without sockets.
- Reuses H1's TLS verification/client-cert/proxy implementation for token
  POSTs instead of adopting the separate std/net/http client.
- Leaves a transport seam for fixture tests and future gRPC/WebSocket users.
- Keeps tokens out of `model.Req` and collection state except for the final
  wire Authorization header created immediately before send.

Important design correction: upstream OAuth's generated bearer header is set
after user headers and therefore replaces an explicit `Authorization` row.
WI-0022 should implement that for OAuth even though the S10 plan currently
says explicit rows win. Do not change Basic/Bearer behavior in this WI;
record the broader mismatch as a follow-up rather than expanding scope.

Rejected alternatives:

1. **Put token acquisition inside H1** — mixes transport with a complex
   interactive protocol and makes gRPC/WS reuse harder.
2. **Perform OAuth inside collection.plan_req** — makes a pure planner do
   network/browser work and blocks CLI tests.
3. **Store resolved config or tokens in request YAML/history** — violates
   upstream secrecy boundaries.

## D6 — TUI surface: implement OAuth editing + Forget; no fake sign-in command

**Recommendation:** implement the OAuth portions of the upstream Auth editor:
auth-type selection sufficient to choose OAuth2, grant selector, conditional
auth/redirect fields, token/client/scope inputs, client-auth selector,
status line, and variable completion/highlighting where existing widget
infrastructure permits. Add **Forget OAuth token** to the palette for OAuth
requests. Replace the current degraded `OAuth sign-in` row: sending is the
upstream sign-in path; do not keep a fake/degraded command. If an explicit
sign-in row remains as a convenience, it must perform the same send/authorize
path and never claim separate behavior, but the preferred corpus-faithful
surface is Forget plus send.

Why:

- Pinned upstream source does not expose a separate "OAuth sign-in" command;
  it exposes Forget and implicitly signs in on send. Corpus §7.6's wording
  appears to summarize sign-in rather than name an exact command. Implementing
  a fake palette row would preserve oxttp's current degrade, not upstream.
- Without editing, OAuth is technically runnable only by hand-editing YAML,
  falling short of the TUI feature even though runtime flow works.

Scope control:

- Implement OAuth editor controls; do not rebuild the entire Basic/Digest/
  Bearer editor in this WI unless the shared auth-type strip requires minimal
  wiring. Existing non-OAuth panes may remain read-only with explicit
  degradation already recorded by S10/S11.
- Save edited OAuth configuration back through the normal draft/save path;
  defaults omitted where upstream omits them.

## D7 — browser launcher and testability

**Recommendation:** implement an injectable `open_url(url) -> err` port.
Production uses argv-only executables, never a shell string: Windows
`rundll32 url.dll,FileProtocolHandler <url>`; non-Windows first `xdg-open
<url>` and then `open <url>` as a fallback. Tests inject a fake opener that
captures the URL and drives the loopback callback.

Caveat: oxl exposes `rt_is_windows` but not a Darwin probe, so the
non-Windows fallback chain is intentionally best-effort. Failure returns the
upstream sanitized browser-open error.

## D8 — token response parsing/resource caps

**Recommendation:** mirror x/oauth2 behavior closely, with explicit caps:

- POST form `application/x-www-form-urlencoded`, 30s timeout, no redirects.
- Accept JSON token responses and form/text responses. JSON `expires_in` may
  be number or numeric string; null/omitted means no expiry; wrong types are
  invalid responses. Form responses parse as query values.
- Response body cap 1 MiB. Because H1 currently reads complete bodies, add a
  bounded opt-in `max_body_bytes` field to `model.Req`/H1 or an equivalent
  transport hook and use it for token POSTs. Do not change ordinary request
  behavior.
- Valid Bearer check exactly as upstream; error body never propagates.
- Expiry uses a 10s early-expiry window. Refresh response without
  `refresh_token` preserves the old one.

## Converged design summary

Build a reusable synchronous `core/oauth` engine with memory-only secure
session storage, exact upstream validation/cache/refresh/PKCE/callback/error
semantics, H1-backed no-redirect token POSTs, TUI editing + Forget + blocking
browser flow, and non-interactive `posting run` support. Deviations are
explicit: no OS vault persistence, no Escape cancellation, listener binds
INADDR_ANY due to oxl, headless run intentionally improves upstream for
client-credentials but never opens a browser, and cross-kind wiring waits for
WI-0020/WI-0021 integration points.

## Questions intentionally left for implementation tickets, not blocking planning

- Exact reusable widget decomposition for conditional OAuth form rows; choose
  the smallest pattern consistent with existing `LineEdit`/tab-strip widgets.
- Whether browser opener order should include `wsl-open` before `xdg-open`;
  implementation can probe availability conservatively without changing the
  error contract.
- Future persistent vault API design belongs upstream in oxl/std or a separate
  oxttp work item once a safe interface exists.
