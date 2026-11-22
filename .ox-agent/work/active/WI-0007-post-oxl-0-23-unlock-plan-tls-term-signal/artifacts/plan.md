# WI-0007 plan — follow-on work after oxl ≥ 0.23.2

Brainstorm: `artifacts/brainstorm.md`. Spec: `artifacts/spec.md`.
Sequencing: `context/decisions/0025-post-oxl-023-unlock-sequencing.md`
(IN-0005 = B).

## M0 — Toolchain bump (this PR)

**Deps:** none. **Out of scope:** feature work.

| Work | Gate |
|---|---|
| `.oxl-version` → `0.23.2` | `oxl build ./cli ./tui` green |
| Compat: `[T,err]` returns, `term.Size`, `writefile_` bytes | unit tests green |
| Refresh `oxl-toolchain.md` + CHANGELOG | docs match pin |
| Keep per-dir `oxl test` loop | oxidean/oxl#131 history |

## Track A — finish v0.1 CLI

| Stage | WI | Deps | Gate |
|---|---|---|---|
| S5 | WI-0006 request path + golden harness | M0 | xh diff basic HTTP rows |
| S6 | body & content kinds | S5 | request-item matrix |
| S7 | remaining flags + degradations | S6 | auth/session/download/print/curl; TLS split implement-now vs parked |

## Track B — HTTPS unlock

| Stage | WI | Deps | Gate |
|---|---|---|---|
| HTTPS | open after S5 (WI-0009) | M0, ideally S5 | local TLS fixture round-trip; `--verify=no` accept-all Verifier (IN-0005=B) |
| Parks | cite oxl | — | `#221` mTLS, `#222` CONNECT, `#224` TLS 1.2 |

ADR-0001 superseded when HTTPS WI lands; H1 codec stays.

## Track C — TUI driver (before S8)

| Stage | Work | Gate |
|---|---|---|
| ADR | supersede ADR-0005 with `std/os/term` + `std/os/signal` | ADR merged |
| S8+ | implement driver (no `stty`) | WI-0001 S8 intake |

## Track D — parked

- ADR-0003: keep own H1; gap-analyze `std/net/http` later.
- HTTP/2/#218, HTTP/3/#219, WS/#220, gRPC/#223: M5 / WI-0008 matrix.

## Opening order

1. Land M0 on this branch.
2. Drive WI-0006 S5.
3. Open HTTPS WI after S5 green.
4. ADR term/signal + S8 when TUI tranche starts.
