# WI-0007 spec — post-oxl-0.23 unlock

## Intent

After pinning oxl ≥0.23.2, unlock HTTPS and term/signal adoption paths
without blocking the HTTP S5 golden harness.

## Locked decisions

- IN-0005 → **B**: bump → S5/S6 HTTP → HTTPS WI; `--verify=no` via
  local accept-all `tls.Verifier`.
- Decision 0020 sequencing stands.
- ADR-0001 superseded when the HTTPS WI ships; ADR-0005 superseded
  before S8 by a term+signal ADR.

## Contracts

### Toolchain bump (M0)

- `.oxl-version` = `0.23.2`; CI installs that release.
- `oxl build ./cli` / `./tui` green; full per-dir test matrix green.
- Compat fixes for `[T,err]` multi-returns, `Screen.Size`,
  `writefile_` byte counts documented in `oxl-toolchain.md`.

### HTTPS WI (follow-on)

- H1 accepts `https://` via `tls.dial_timeout` / `tls.client`.
- `--https` / https-bin-name default scheme live.
- `--verify=yes` (default) and `--verify=<pem>` wired to roots.
- `--verify=no` implemented with accept-all Verifier (corpus fidelity).
- Still degraded (cite oxl issues): `--cert`/`--cert-key` (#221),
  `--ssl`<1.3 (#224), HTTPS+`--proxy` (#222), h2/h3 (#218/#219).

### TUI driver (before S8)

- ADR superseding 0005: `std/os/term` + `std/os/signal` only.

## Acceptance

1. Bump merged or green on this branch.
2. Specs for HTTPS + term ADR drafts exist or WIs opened.
3. Upstream protocol deps recorded under
   `context/references/oxl-protocol-deps.md`.
