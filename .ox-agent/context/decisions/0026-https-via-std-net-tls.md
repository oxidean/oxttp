# ADR-0026 — HTTPS via std/net/tls behind H1

- Status: accepted
- Date: 2026-11-22
- Supersedes: ADR-0001 (HTTP-only until oxl TLS)

## Context

oxl ≥ 0.23.2 ships `std/net/tls` (TLS 1.3 client) and x509 roots.
IN-0005 = B: finish S5 HTTP then unlock HTTPS; `--verify=no` via a
local accept-all `Verifier`.

## Decision

1. H1 dials TCP with the existing non-suspending `dial_h1`, then wraps
   with `tls.client` for `https://` (avoids suspendable `net.dial_timeout`).
2. `model.Req.verify`: `""`/`yes` → system roots; `no` → `AcceptAll`
   Verifier; otherwise a PEM path into `x509.Roots`.
3. Explicit parks remain: mTLS (`--cert`, oxl#221), CONNECT proxy
   (oxl#222), TLS ≤1.2 (oxl#224).

## Consequences

- ADR-0001 is superseded for scheme gating; corpus HTTPS rows move to
  `next`/`done` as S7 verify flags finish wiring.
- Golden harness can grow HTTPS rows against public or local TLS fixtures.
