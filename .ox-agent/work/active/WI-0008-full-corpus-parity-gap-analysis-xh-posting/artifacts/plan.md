# WI-0008 plan — parity program stages

Spec: `artifacts/spec.md`. Matrix: `context/specs/parity-matrix.md`.

## Stages → work items

| Stage | WI (proposed title) | Deps | Gate |
|---|---|---|---|
| M0 | Bump oxl to 0.23.2 (may ship in-branch) | — | build+test green on pin |
| M1a | S5 CLI request path + golden harness | M0, S2–S4 | WI-0006; xh diff basic rows |
| M1b | S6 body & content kinds | M1a | request-item matrix |
| M1c | S7a non-TLS remaining flags | M1b | auth/session/download/print/curl |
| M1d | HTTPS on H1 + verify Verifier | M0, M1a | https fixture; parks cite #221/#222/#224 |
| M2a | ADR term+signal supersede 0005 | M0 | ADR merged |
| M2b–e | S8–S11 TUI | M2a, M1a, M1d preferred | transcript + collection fixtures |
| M3 | Deep HTTP polish | M1* | pooling, generate, sockets… |
| M4 | Posting long-tail HTTP | M2* | GraphQL/SSE/OAuth/import/run/remote |
| M5 | Protocols | oxl #218–#224 | reopen when upstream ships |

## Immediate next actions

1. Land M0 bump (this agent run).
2. Drive WI-0006 S5 through ox-agent.
3. Open HTTPS WI after S5 green (IN-0005=B).
