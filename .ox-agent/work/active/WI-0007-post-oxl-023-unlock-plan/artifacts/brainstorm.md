# WI-0007 brainstorm — work unlocked by oxl ≥ 0.23.2

Context: oxttp pins **oxl 0.15.0**. Latest release is **v0.23.2**
(2026-11-22). Between those tags (~60 commits, 257 files) oxl closed
the four upstream blockers named in WI-0001's plan risks:

| Upstream | Status | What landed |
|---|---|---|
| oxidean/oxl#128 TLS/HTTPS | closed (completed) | Milestone X: `std/crypto/*`, `std/crypto/x509`, `std/net/tls` (TLS 1.3 client), `https://` seam in `std/net/http` (`Url.secure`, `Client.tlscfg`) — see `docs/tls.md` |
| oxidean/oxl#125 termios | closed (completed) | `std/os/term`: `isatty`, `size`, `raw`/`restore` |
| oxidean/oxl#126 signals | closed (completed) | `std/os/signal`: `arm`/`disarm`/`take` (SIGINT, SIGWINCH, …) |
| oxidean/oxl#127 richer http | closed (completed) | Expanded `std/net/http` client surface (`client.oxl`) |
| oxidean/oxl#131 multi-arg test | closed (completed) | Multi package-dir `oxl test`/`build` no longer silently drop args |

This brainstorm asks what oxttp should do **after** (and including)
bumping the pin. It does not implement the bump.

## Current oxttp position

Shipped on main: S1–S4 (shared args, domain model, h1 transport, CLI
flag table). Open: **WI-0006 (S5)** request path + golden harness at
`intake`. S6/S7 and TUI S8–S11 remain on the WI-0001 plan. ADR-0001
still says HTTP-only; `core/http/h1.oxl` still rejects `https://`.
ADR-0005 still plans `stty` raw mode for the TUI.

## Q1 — Sequencing relative to the unfinished v0.1 CLI path

- **A. Bump first, then finish S5→S7 as written (HTTPS still degrades).**
  Lowest disruption; unlocks compile-time/CI cleanup immediately;
  leaves the biggest corpus gap (`https://`) for a post-v0.1 tranche.
- **B. Bump first, then fold HTTPS into S5–S7 scope.** S5 golden
  harness becomes more valuable (real https targets); S7 no longer
  plans TLS as "unsupported". Bigger S5/S7 WIs; risks delaying the
  first end-to-end CLI ship.
- **C. Finish S5 on 0.15.0, bump later.** Avoids mixing toolchain
  churn with request-path work — but leaves known-fixed CI workarounds
  (#131 loop) and blocks any accidental https exploration.

**Recommendation: A, with a narrow exception.** Bump as its own PR
(WI-0008), keep S5–S6 scope HTTP-only so the golden harness lands
fast, then open an **S5b/S7-TLS** WI that flips ADR-0001 before S7
closes the 58-flag matrix — so v0.1 either ships HTTPS for the
supported TLS 1.3 subset, or S7's deferral list is rewritten against
the real remaining parks (mTLS, TLS≤1.2, HTTPS-via-HTTP-proxy
CONNECT), not "oxl has no TLS".

## Q2 — How to adopt TLS in `core/http`

- **A. Wrap `tls.Conn` inside the existing H1 dial path.**
  `check_url` accepts `https`; after TCP connect (or via
  `tls.dial_timeout` / `tls.client` on the socket), speak h1 over the
  TLS conn. Keep owning headers/redirects/compression
  (ADR-0003 still holds — std client remains thinner than the corpus).
- **B. Switch the transport to `std/net/http.Client` now that it is
  richer and https-capable.** Deletes a lot of `h1.oxl`, but re-opens
  every gap ADR-0003 listed unless the new client covers them all;
  needs a fresh gap analysis vs corpus.
- **C. Dual transports:** keep H1 for http, add `H1TLS` (or
  `StdHttps`) selected by scheme. Clear seam; two code paths for
  redirects/headers risk drift.

**Recommendation: A.** ADR-0003 anticipated this exact seam
("TLS/h2 join later behind the same port"). Prefer
`tls.dial_timeout`/`tls.client` as the socket upgrade, keep H1 wire
codec. Do **not** wholesale adopt std Client without a dedicated
gap-analysis WI — oxl#127 closed, but oxttp's corpus still drives
outgoing header control, print/offline modes, and xh-shaped errors.

## Q3 — TLS flag surface vs upstream parks

oxl TLS is **client-only TLS 1.3**, verify-required (no
`insecure_skip_verify` flag — custom `Verifier` instead), system/env
roots (`OXL_SSL_CERT_FILE` / `SSL_CERT_FILE` / platform bundles).
Parked upstream: mTLS/client certs, TLS≤1.2, session resumption,
HTTPS through HTTP proxy (CONNECT), revocation.

Corpus flags that become **implementable** after the bump:

- `https://` URLs and `--https` / invoked-as-https default scheme
- `--verify=yes` (default path) and `--verify=<pem>` (custom CA via
  `x509.Roots.load_pem` / env override story)
- Trust failures surfaced with actionable `errors.is(..., x509.err_*)`

Corpus flags that **remain deferred** (rewrite S7 deferral text):

- `--verify=no` / skip-verify — no first-class insecure mode in oxl;
  options: custom Verifier that accepts-all (policy decision), or keep
  explicit unsupported diagnostic
- `--cert` / `--cert-key` — mTLS parked upstream
- `--ssl` versions below 1.3 / `--native-tls` — TLS 1.2+ backends
  parked
- HTTPS + `--proxy` — CONNECT parked in oxl http seam

**Open disagreement:** whether `--verify=no` should grow a local
accept-all Verifier (corpus fidelity) or stay an explicit degradation
(security posture matching oxl's deliberate omission). Needs a human
decision before the TLS WI specs.

## Q4 — TUI terminal layer (S8) after `std/os/term` + `signal`

- **A. Rewrite ADR-0005 now; S8 ships on `term`+`signal` from day one.**
  Drops the fragile `stty` plan; SIGWINCH + SIGINT restore become
  real. Best long-term.
- **B. Keep `stty` for S8, migrate later.** Wastes the unlock; keeps
  the known-bad restore-on-Ctrl-C failure mode.
- **C. Abstract both behind `Screen` (already planned) and implement
  the `term` driver as the only driver.** Same as A operationally.

**Recommendation: A/C.** No reason to build the `stty` path now that
#125/#126 shipped. Update ADR-0005 before S8 intake.

## Q5 — Scope of the bump PR itself

The bump is not free: 0.15→0.23.2 is a large std+runtime jump. Treat
it as **WI-0008** with gates:

1. `.oxl-version` → `0.23.2`; CI curl URL follows the pin (already).
2. `oxl build ./cli ./tui` and full `oxl test` green (and simplify the
   per-dir test loop if #131's fix is confirmed on 0.23.2).
3. Refresh `.ox-agent/context/standards/oxl-toolchain.md` (capabilities
   section currently claims "No TLS" / "No termios").
4. No feature work in the same PR — unlock PRs follow.

## Recommended work graph (post-bump)

```
WI-0008  bump pin → 0.23.2 (+ CI/docs hygiene)
    │
    ├─► WI-0006  S5 request path + golden harness (HTTP)   [already open]
    │       └─► S6 body/content kinds
    │
    ├─► WI-0009  HTTPS transport on H1 + verify/CA subset
    │       └─► revises S7 deferrals; may merge into S7
    │
    └─► (before S8 intake) supersede ADR-0005 → term+signal driver
            └─► S8–S11 TUI tranche as planned, lower terminal risk
```

## Findings preserved (disagreement)

- Whether v0.1 must include HTTPS before calling the CLI tranche done
  (Q1 A vs B).
- Whether `--verify=no` is implemented via accept-all Verifier or
  stays degraded (Q3).
- Whether a future WI should re-evaluate ADR-0003 against the new
  std Client (Q2 B) — parked unless gap analysis shows net deletion
  without corpus loss.
