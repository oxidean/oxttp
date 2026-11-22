# WI-0007 plan — follow-on work after oxl ≥ 0.23.2

Brainstorm: `artifacts/brainstorm.md`. Sequencing decision:
`context/decisions/0025-post-oxl-023-unlock-sequencing.md`.

## Prerequisite — WI-0008 Toolchain bump

**Deps:** none. **Out of scope:** feature work.

- `.oxl-version`: `0.15.0` → `0.23.2`
- Confirm `oxl build ./cli ./tui` and the test matrix on 0.23.2
- If oxidean/oxl#131's fix holds: simplify CI/README from the
  per-dir `for d in …; oxl test "$d"` loop to a multi-arg form (or
  keep the loop if still clearer)
- Rewrite `.ox-agent/context/standards/oxl-toolchain.md` capability
  bullets (TLS, term, signal, http client) to match `docs/tls.md` /
  `std/os/term` / `std/os/signal` on the new pin
- Gate: CI green on the bump PR; no corpus behavior change

## Track A — finish v0.1 CLI (unchanged order)

| WI | Stage | Notes after bump |
|---|---|---|
| WI-0006 | S5 request path + golden harness | Keep HTTP-only matrix for the first harness; do not block on TLS |
| (next) | S6 body & content kinds | Unchanged |
| (next) | S7 remaining flags + degradation | **Deferral text changes**: TLS items split into "implement now" vs "still parked upstream" per brainstorm Q3 |

## Track B — HTTPS unlock (new)

**Proposed WI-0009 — HTTPS on H1 transport**

Deps: WI-0008; ideally after S5 so golden rows can grow https cases.

Scope:

1. Supersede ADR-0001 (HTTP-only) with an ADR that adopts
   `std/net/tls` behind `core/http.Transport`.
2. H1 dial path: accept `https://`; handshake via
   `tls.dial_timeout` / `tls.client`; keep h1 codec, redirects,
   compression.
3. Wire `--https` / default-scheme and `--verify=yes|<pem>` to
   `tls.Config` / `x509.Roots` (and document env interplay with
   `OXL_SSL_CERT_*` vs xh's `REQUESTS_CA_BUNDLE`/`CURL_CA_BUNDLE`).
4. Explicit remaining degradations: `--cert`/`--cert-key`,
   `--ssl`<1.3, `--native-tls`, HTTPS+`--proxy` (CONNECT), and
   whatever decision is made on `--verify=no`.
5. Tests: unit handshake against oxl's TLS fixtures pattern; golden
   rows against a local TLS server.

Gate: `https://example`-style local fixture round-trip green;
deferred TLS flags still parse and emit xh-shaped unsupported
diagnostics where chosen.

## Track C — TUI driver unlock (before S8)

**Docs/ADR only until S8 opens**

- Draft ADR-0021 superseding ADR-0005: `std/os/term` raw/restore +
  `isatty`/`size`; `std/os/signal` for SIGINT restore and SIGWINCH
  resize; keep `Screen`/`Key` abstractions.
- When S8 intake starts, implement that driver — do not build the
  `stty` path.

## Track D — optional / parked

- **ADR-0003 revisit:** gap-analyze new `std/net/http` client vs
  corpus before considering deleting `h1.oxl`. Default: keep own
  stack.
- **HTTP/2 / HTTP/3:** still out of scope (no oxl std surface).
- **mTLS / TLS 1.2:** wait for upstream reopen triggers in
  `docs/tls.md`.

## Suggested WI opening order

1. WI-0008 bump (chore)
2. Continue WI-0006 S5 (feat)
3. WI-0009 HTTPS (feat) — can overlap late S6 if staffing allows
4. ADR-0021 + S8 when entering TUI tranche
