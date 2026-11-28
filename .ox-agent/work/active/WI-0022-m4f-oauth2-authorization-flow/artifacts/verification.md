# WI-0022 verification

Verdict: pass with notes.

Evidence:

- Local `oxl test ./core/oauth` completed rc=0 after the final source state; browser/PKCE, callback, manager, validation, cache-key, token-parser, and transport-sanitization suites passed.
- Local full `oxl test ./cli` completed rc=0 before the CI-only workflow/state commits; it includes the dependency closure and golden harness. The OAuth branch does not modify CLI production code.
- CI on head `b4448d9` passed `core/oauth`, `core/collection`, `tui`, and the other completed leaf legs; the workflow now includes a dedicated `core/oauth` matrix leg.
- Independent review artifact `review.md` records no blocking security/correctness finding.

Acceptance-criteria spot checks:

1. Touched packages compile/tests green in local focused suites and CI legs.
2. OAuth upstream-applicable behaviors are twinned in `core/oauth` tests: client auth styles, cache reuse/refresh/forget/isolation, PKCE/state/callback, token parsing, sanitization.
3. Unsupported grants and insecure endpoints fail validation; only authorization-code PKCE and client-credentials execute.
4. Browser-flow tests cover S256, state validation, callback outcomes, code exchange, listener cleanup, and no token redirects.
5. Tokens are memory-only; warning is explicit; no plaintext token persistence exists.
6. TUI integration covers edit/save/send/refresh/reuse/forget paths in `tui` tests.
7. `posting run` client-credentials/reuse/refusal/warning paths are covered in `tui/cli_test.oxl`.
8. OAuth bearer injection replaces explicit Authorization for OAuth requests; transport redirect tests cover cross-origin stripping and no 401 replay behavior remains absent.
9. Endpoint errors and transport failures are sanitized; tests assert secrets do not propagate.
10. Deviations are documented in spec §14 and review.md.

Notes:

- `oxl build` remains represented by the PR CI build leg rather than a second local memory-heavy compile.
- OS credential-store persistence, asynchronous cancellation, and IPv6 loopback execution remain documented degradations, not hidden gaps.
