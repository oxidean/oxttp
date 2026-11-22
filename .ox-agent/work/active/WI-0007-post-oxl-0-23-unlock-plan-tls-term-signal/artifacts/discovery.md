# WI-0007 discovery — post-oxl-0.23 unlock surface

## Intent

Map what oxttp can do after bumping the oxl pin from 0.15.0 to the
latest release (v0.23.2 as of 2026-11-22), without implementing the
bump in this work item.

## Project standards / decisions in force

- Corpus fidelity (`context/standards/corpus-fidelity.md`) — HTTPS and
  TLS flags are corpus items; today they degrade under ADR-0001.
- Toolchain pin (`.oxl-version` → 0.15.0; CI follows the pin).
- ADR-0001 HTTP-only until oxl TLS — **upstream blocker closed**; this
  WI plans the supersession path, does not supersede yet.
- ADR-0003 own H1 transport — still the dial/codec home; TLS should
  join behind `core/http.Transport`.
- ADR-0005 stty TUI — **upstream termios/signal blockers closed**; S8
  should not build the stty path.
- ADR-0006 explicit degradation — remaining parks (mTLS, TLS≤1.2,
  CONNECT) stay as diagnostics, not silent no-ops.
- WI-0001 plan S5–S11 still the v0.1 spine; WI-0006 (S5) is open at
  intake.

## Upstream evidence (oxidean/oxl @ v0.23.2)

| Issue | Surface landed |
|---|---|
| #128 | `std/net/tls`, `std/crypto/x509`, `https://` in `std/net/http` (`docs/tls.md`) |
| #125 | `std/os/term` — isatty, size, raw/restore |
| #126 | `std/os/signal` — arm/disarm/take |
| #127 | richer `std/net/http` client |
| #131 | multi-arg `oxl test`/`build` no longer silently drops dirs |

## Local code constraints

- `core/http/h1.oxl` still rejects `https://` with an explicit error.
- Transport port already exists (`core/http/transport.oxl`).
- CI/README still document the per-dir test loop for #131.

## Out of scope for discovery

Language/API break audit of the 0.15→0.23 jump (belongs in the bump
chore WI), and implementation of HTTPS or the TUI driver.
