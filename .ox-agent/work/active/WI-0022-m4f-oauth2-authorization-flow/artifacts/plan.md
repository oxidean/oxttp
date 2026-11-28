# WI-0022 plan — M4f OAuth2 authorization flow

Spec: `artifacts/spec.md`. Discovery/brainstorm: `artifacts/discovery.md`,
`artifacts/brainstorm.md`. Accepted decisions: ADR-0059 through ADR-0063.
Implementation follows the corpus and spec; deviations must remain explicit.

## Implementation strategy

Build and prove the protocol engine before touching UI. Keep `core/collection`
pure, inject transport/browser seams, and use deterministic loopback fixtures.
Each stage ends with a focused build/test gate; no stage may bypass secret
sanitization or listener caps to unblock itself. UI polish comes only after a
fake end-to-end authorization can pass in core.

## Dependency graph

```text
S1 oauth foundations ─┬─> S2 transport body cap ─> S3 token endpoint client
                       └─> S5 callback/browser primitives
S3 ─> S4 memory manager/client-credentials/refresh
S4 + S5 ─> S6 authorization orchestrator/browser flow
S1 ─> S7 collection planning/substitution
S6 + S7 ─> S8 TUI send/forget integration
S7 ──────> S9 TUI editor/status surface
S6 + S7 ─> S10 posting run integration
S8 + S9 + S10 ─> S11 export/docs/deviation polish
all ─> S12 conformance verification/fix cycle
```

Stages S2/S5 and parts of S7/S9 can be developed in parallel after S1, but
the expected single-agent order is numeric unless a gate reveals a dependency
problem.

## Stages

### S1 — `core/oauth` foundations and validation

Files: new `core/oauth/oauth.oxl`, `core/oauth/oauth_test.oxl`; possibly
small URL/form helpers in the same package.

Work:

- Define OAuth config/plan/runtime result types independent of collection
  YAML internals.
- Implement defaults, whitespace scope normalization, endpoint validation,
  redirect validation, resource URL validation, and exact upstream error
  strings from spec §§2–3.
- Implement canonical cache-key encoding and SHA-256 digest; include IPv6
  execution capability marker/result needed by ADR-0063 without attempting a
  socket bind.
- Implement query escaping/form encoding, raw-url-base64 helper, fixed-loop
  state comparison, and CSPRNG state/PKCE generation wrappers.
- No sockets, browser, UI, or collection mutation in this stage.

Gate:

- `oxl build`
- `oxl test core/oauth` (or repo leaf equivalent for the new package)
- validation matrix and cache-key partition tests pass; unsupported grants
  fail; no plaintext fallback or weak random path exists.

### S2 — bounded response-body support in HTTP transport

Files: `core/model/model.oxl`, `core/http/h1.oxl`, `core/http/h1_test.oxl`,
possibly `core/http/transport.oxl` if the option is transport-level.

Work:

- Add an opt-in maximum response body field/mechanism with zero meaning
  unchanged legacy behavior.
- Enforce the cap for both declared content length and streamed/read body
  where implementation permits; return a bounded, non-secret transport error.
- Preserve all existing resource behavior and tests.

Gate:

- `oxl build`
- `oxl test core/model`, `oxl test core/http` (leaf-per-command if required)
- fixture proves oversized OAuth-like body fails while ordinary uncapped
  response behavior is unchanged.

### S3 — token endpoint client and response parser

Files: `core/oauth/token.oxl`, `core/oauth/token_test.oxl`; uses
`core/http` fake transport patterns.

Work:

- Construct POST form requests for client-credentials and refresh grants;
  code-exchange parameters may be included behind an internal function even
  if browser orchestration is not wired yet.
- Implement `client_secret_post` and `client_secret_basic` exactly,
  including URL-query escaping before Basic base64.
- Copy verify/CA/client-cert/proxy fields from resource security context;
  force no redirects, 30s timeout, and 1 MiB response cap.
- Parse JSON and form responses, including `expires_in` semantics, endpoint
  errors in 200s, non-2xx status, malformed JSON/wrong types, and Bearer
  token validation.
- Classify results into sanitized error categories from spec §7; retain only
  non-secret status/code metadata internally.

Gate:

- `oxl build`
- `oxl test core/oauth`
- parser twin matrix passes; raw body/client secret/token never appears in
  returned error strings; fixture transport observes correct headers/body.

### S4 — memory manager, reuse, refresh, and client-credentials authorization

Files: `core/oauth/manager.oxl`, `core/oauth/manager_test.oxl`.

Work:

- Implement per-instance memory token entries and lookup/update/forget.
- Implement expiry minus 10 seconds, no-expiry behavior, refresh rotation,
  retain-old-refresh-on-omission, and client-credentials renewal semantics.
- Implement non-interactive mode: client-credentials may acquire; browser-
  required code grants return the specified refusal.
- Surface the memory-only warning through result notes/status rather than
  printing directly.
- Keep manager ownership session-local; no package-global token leakage.

Gate:

- `oxl build`
- `oxl test core/oauth`
- fake clock/time injection or boundary-constructed entries prove the 10s
  rule; cache isolation across collection/scope/proxy/config passes;
  Forget exact-key behavior passes.

### S5 — loopback callback listener and browser opener primitives

Files: `core/oauth/callback.oxl`, `core/oauth/browser.oxl`,
`core/oauth/callback_test.oxl`.

Work:

- Implement bounded HTTP callback accept/read/response loop using
  `std/net.listen`/`rawfd` as required: 16 KiB head cap, 5s connection
  deadline, 64 extraneous connections, exact method/Host/path, state
  validation, duplicate/first-outcome behavior, no-store/no-referrer body,
  and guaranteed close.
- Implement explicit IPv6-loopback unsupported execution error per ADR-0063.
- Implement injectable argv browser opener: `xdg-open` then `open` on
  non-Windows; Windows argv launcher without shell interpolation.
- Keep the 3-minute total budget in orchestration, but expose timing/cancel
  outcome types needed by S6.

Gate:

- `oxl build`
- `oxl test core/oauth`
- loopback tests prove wrong path 404, bad state 400, missing code 400,
  denial outcome, first valid outcome wins, header cap, cleanup, and no real
  browser dependency.

### S6 — authorization orchestrator and browser flow

Files: `core/oauth/flow.oxl`, `core/oauth/flow_test.oxl`; small integration
exports in `core/oauth/oauth.oxl` if needed.

Work:

- Implement public `authorize`/`forget` operations and result classification.
- For authorization-code: validate, create listener before opening browser,
  expand port 0 into actual redirect URI, build exact authorization query,
  launch browser once, wait at most 180s, exchange code with verifier and
  actual redirect URI, store token, and return bearer.
- On refresh failure, follow upstream behavior (notably invalid_grant) and
  fall back/refuse according to interactive mode.
- Ensure listener closes on success, denial, timeout, opener failure, token
  exchange failure, and malformed callback outcome.
- Produce only sanitized user-facing errors; internal test fixtures may
  inspect classifications.

Gate:

- `oxl build`
- `oxl test core/oauth`
- deterministic fake browser can drive callback; end-to-end code+PKCE flow
  passes against fake token endpoint; timeout/opener failure/cleanup tests
  pass; no real network beyond loopback fixture.

### S7 — collection planning and substitution integration

Files: `core/collection/collection.oxl`, `core/collection/collection_test.oxl`,
`core/collection/load_test.oxl`; may adjust `SendPlan` in the same package.

Work:

- Substitute active OAuth fields after defaults/variables rules and attach a
  resolved OAuth plan to `SendPlan` without network side effects.
- Remove/replace the current hard error `oauth2 auth lands M4 — unsupported
  in this build` for valid OAuth requests while preserving errors for invalid
  configuration.
- Ensure inactive authorization-code-only fields do not block client
  credentials.
- Keep saved YAML schema unchanged; no runtime token or generated field is
  encoded.
- Validate plan data sufficiently to fail before transport where spec says
  send-time validation must occur.

Gate:

- `oxl build`
- `oxl test core/collection`
- planner tests cover substitution matrix, YAML round-trip, cache-key input
  completeness, validation errors, and no socket/browser side effects.

### S8 — TUI send, bearer injection, Forget, and safe status

Files: `tui/coll.oxl`, `tui/app.oxl`, `tui/types.oxl`, `tui/keymap.oxl` or
actual palette owner, `tui/send_test.oxl`, `tui/coll_test.oxl`.

Work:

- Add app-session OAuth manager ownership.
- After `plan_req`, call `authorize` before resource transport send; on
  failure do not send and render safe failure.
- Inject exactly one Bearer Authorization header for OAuth requests,
  replacing enabled explicit Authorization rows without mutating saved YAML.
  Preserve disabled rows as disabled.
- Implement Forget OAuth token palette item for OAuth requests and remove
  the fake/degraded `OAuth sign-in` row or wire it to the real send path.
- Display memory-only warning and waiting/success/failure-safe notes without
  claiming Escape cancellation.
- Ensure history/response rendering stores response data only, never token
  endpoint traffic or secrets.

Gate:

- `oxl build`
- `oxl test tui`
- fake transport/manager tests prove authorization failure prevents send,
  success emits exactly one bearer header, cross-origin redirect behavior
  remains correct, Forget works, and no fake sign-in row remains.

### S9 — TUI OAuth editor surface

Files: `tui/render.oxl`, `tui/widgets.oxl`, `tui/types.oxl`,
`tui/render_test.oxl`, `tui/widgets_test.oxl`; only touch editor plumbing
already present.

Work:

- Add OAuth 2.0 auth-type selection and conditional rows per spec §10.
- Implement draft-state editing that survives tab switches and saves nested
  YAML through the existing save path.
- Keep client secret masked only in read-only/summary contexts; editable
  form behavior follows upstream. No runtime token field.
- Ensure variable highlighting/completion behavior remains consistent where
  those hooks already exist.

Gate:

- `oxl build`
- `oxl test tui`
- render/editor fixture proves conditional fields, tab-state retention,
  save/load round-trip, masking, and no token persistence.

### S10 — `posting run` integration

Files: `tui/cli.oxl`, `tui/cli_test.oxl`.

Work:

- Create one OAuth manager per run process and use non-interactive authorize
  before each planned request.
- Client-credentials acquisition/reuse/refresh participates in normal run
  results; token endpoint traffic is not a separate report row.
- Browser-required authorization-code fails with exact non-interactive
  refusal; no browser opener is invoked.
- OAuth failure participates in fail-fast, text/JSON output, and exit status
  like other send failures.

Gate:

- `oxl build`
- `oxl test tui`
- CLI fixture tests prove client-credentials success/reuse, changed-scope
  separation, code-grant refusal/no opener, output shape, fail-fast and exit
  codes.

### S11 — export boundary, documentation, and deviation polish

Files: export implementation if present on branch (`tui/curlimp.oxl` or
export-related files), README/docs only where an existing OAuth surface is
documented, plus final artifacts/review notes.

Work:

- Add/refine OAuth export refusal with exact spec message where export exists;
  do not alter xh `--oauth2-bearer` bearer semantics.
- Document memory-only token behavior, no-Escape limitation, IPv4 listener
  limitation, IPv6 degradation, and run behavior in user-facing text only if
  the branch already has an appropriate documentation surface.
- Audit strings for secret leakage and stale “OAuth2 lands M4” degradation.
- Update spec/plan annotations only if implementation exposes a genuine
  mismatch; otherwise leave corpus/deviation statements stable.

Gate:

- `oxl build`
- focused tests for touched leaf packages
- grep/audit finds no fake OAuth sign-in row, no stale unsupported message
  on the implemented path, and no export/log token leakage.

### S12 — conformance verification and fix cycle

Files: test fixes only unless a conformance gap requires scoped production
fix.

Work:

- Compare implementation tests one-by-one with upstream `oauth_test.go` and
  spec §15; add missing applicable twins.
- Run per-leaf test loop for all impacted packages; do not use multi-arg
  `oxl test` invocation.
- Run full `oxl build`.
- Perform security checklist: caps, listener close, state entropy, sanitizers,
  no cross-origin token, no 401 replay, no plaintext token file.
- Fix failures in small cycles; escalate if a spec contradiction or oxl
  blocker is discovered rather than silently deviating.

Gate:

- all impacted leaf tests pass and `oxl build` is clean
- every spec §16 acceptance criterion is demonstrably satisfied or explicitly
  tied to an accepted ADR deviation
- ready for implementation-review/verification stage, not shipping.

## Test fixtures and seams

- Reuse `core/http/fixture_test.oxl` patterns for fake transports and
  loopback servers. Do not require external OAuth providers.
- Inject clock/random/browser opener where oxl ownership permits. If direct
  injection is awkward, use narrow internal helper functions overridden only
  in test compilation patterns available in the repo; do not weaken CSPRNG in
  production.
- Browser opener tests assert argv construction only; no real browser is
  launched.
- Callback tests use real loopback sockets because they validate socket
  lifecycle, but all token/resource endpoints remain fixtures unless already
  loopback.
- TUI tests use the existing fake transport/session harness; no terminal
  interactive test is required.

## Risks and mitigations

1. **oxl ownership friction around token entries and interface injection.**
   Mitigate by keeping manager data flat/owned inside `core/oauth` and by
   adapting public signatures during S1/S4 before UI integration.
2. **`std/net.listen` cannot bind exact loopback or IPv6.** Accepted in
   ADR-0061/0063; do not attempt unsafe workarounds. Tests must pin strict
   Host/state/path mitigation and explicit IPv6 failure.
3. **Synchronous TUI blocking means waiting text may not repaint.** Accepted
   in ADR-0061; implement best-effort text but do not invest in async rewrite.
4. **Token response parser nuances.** Mirror x/oauth2 behavior from spec,
   especially `expires_in`; table-driven tests before integration.
5. **Response cap may require transport surgery.** Keep it opt-in and small;
   if H1 architecture makes exact streaming enforcement costly, enforce at
   the OAuth read boundary while preserving transport behavior and document
   the precise mechanism.
6. **Run behavior intentionally diverges from upstream.** ADR-0060 controls;
   do not “fix” it back to upstream's headless failure.
7. **Secret leakage through errors.** Sanitization is centralized in
   `core/oauth`; UI/run layers must display returned safe messages rather
   than formatting raw transport errors themselves.
8. **Scope creep into digest/gRPC/websocket.** Explicitly out of scope;
   design reusable seams but do not implement those milestones here.

## Commit/implementation notes for the future implementer

- Use small conventional commits by stage, explicit paths only, repo identity,
  no push/PR unless asked.
- Do not edit materialized `.ox-agent` skill assets.
- Do not persist runtime tokens in tests or fixtures. Redact even fake values
  if they resemble real provider tokens.
- If implementation reveals a spec error, stop and amend spec/ADR through the
  ox-agent process rather than silently changing behavior.
