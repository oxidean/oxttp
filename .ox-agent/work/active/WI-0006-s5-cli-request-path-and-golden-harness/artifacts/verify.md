# WI-0006 verification — S5 CLI request path + golden harness

## test_command (per-dir `oxl test` loop)

All 12 package dirs pass: cli (136 test fns — spec/sem/exec/golden/
netrc/sess/print/req), core/{item,model,session,collection,term,http},
shared/{args,version}, tui. Zero failures.

## Incidents found and fixed during this verification pass

1. **Build broken at handoff** — `digest_authorization` used
   `-> [str, str]` with `return "", "..."` list-returns; oxl requires
   the last multi-return element to be `err`. Re-typed to `[str, err]`
   with `errors.new`/`nil`.
2. **`***` literal corruption** at 3 sites (`p.digest_pass = substr...`
   lines) — surfaced as `undefined '*'/'+'` lexer errors; restored
   from pre-edit state.
3. **§D3 unimplemented** — helpers existed but `execute()` never
   called them; spec §4.5 requires the 401-digest retry. Wired the
   transparent retry: 401 + `WWW-Authenticate: Digest` → MD5
   response → resend once (no hop record, matching reqwest);
   unsupported algorithm/qop → `{prog}: error: ... unsupported in
   this build` exit 1; no challenge → passthrough.
4. **Stale test contradicted spec** — `test_exec_digest_defers`
   expected a "digest is unsupported" deferral that exists nowhere
   in spec or code. Replaced with live coverage:
   `test_exec_digest_401_retry` (scripted 401→ECHO, asserts the
   resent Authorization) and `test_exec_digest_no_challenge`
   (401 passthrough → exit 4).
5. **oxl destructure shadowing** — `[resp, te] = t.send(...)` inside
   a block declares fresh bindings rather than reassigning outer
   vars; retry result assigned via `resp = resp2`.

## Criteria spot-checks vs spec corpus coverage

- §4.5 auth: basic/bearer live-tested; netrc 5 tests; digest retry
  live-tested incl. passthrough. XH_TEST_DIGEST_AUTH_CNONCE wired.
- §4.6 redirects: follow/max/--all hops live-tested (golden + exec).
- §8 exits: 0/1/2/4/5/6 covered by exec tests + golden fixtures.
- Golden harness: 13 cases × fixtures, all green; python server
  scripts cover echo/scripted/sleep arms.
- Degrade routing (0006/0024): error-degrades emit `{prog}: error:
  <flag> is unsupported in this build` exit 1 — pinned in
  sem_test test_deferrals + golden-adjacent exec tests.

## Deferred-by-design (documented in spec, not bugs)

TTY-only print arms, --curl/--generate/--http2/proxy family
error-degrades, TLS knobs inert on cleartext, jar-lite cookie
deviation (ADR 0023), anyhow-chain flattening.
