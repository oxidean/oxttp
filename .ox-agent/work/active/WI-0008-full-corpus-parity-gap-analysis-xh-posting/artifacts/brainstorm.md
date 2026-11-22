# WI-0008 brainstorm — how to reach full corpus parity

Discovery: `artifacts/discovery.md`. Goal: every item in
`corpus-xh.md` + `corpus-posting.md` either works like upstream or is
an explicit, corpus-shaped degradation with a tracked reopen path
(ADR-0006) — including surfaces that need further oxl work.

## Q1 — Definition of "full parity"

- **A. Behavioral parity where oxl can support it; upstream parks stay
  degraded.** Closest honest reading of "drop-in" today: finish all
  HTTP/1.1 + TLS-1.3-client surfaces for both apps; keep h2/h3/mTLS/
  CONNECT/gRPC/WS as xh/Posting-shaped errors until oxl grows.
- **B. Literal every corpus line, including gRPC/WS/h2/h3.** Requires
  multi-year language work or FFI (FFI still unavailable). Not a single
  program milestone.
- **C. CLI-first full xh parity, TUI "HTTP subset" only.** Shrinks
  Posting scope vs corpus.

**Recommendation: A**, with an explicit **parity matrix** in
`context/specs/` that tags each corpus row: `done` / `next` /
`oxl-blocked` / `wont-until-trigger`. That is what "full parity
including corpus" means operationally without lying about oxl gaps.

## Q2 — Milestone slicing after S1–S4

Recommended program (each bullet = one or more ox-agent WIs):

### Milestone M0 — Toolchain
1. Bump oxl **0.15.0 → 0.23.2** (chore; CI/docs; enable term/TLS).
2. Answer WI-0007 **IN-0005** (HTTPS sequencing + `--verify=no`).

### Milestone M1 — CLI HTTP complete (v0.1 CLI closeout)
3. **S5** request path + golden harness (WI-0006).
4. **S6** body/content kinds.
5. **S7a** non-TLS remaining flags (auth basic/bearer/digest?,
   session, download, print/pretty, curl map, exits, env).
6. **S7b / HTTPS** — `tls` behind H1; `--https`/`https://`/
   `--verify=yes|<pem>`; rewrite deferrals for still-parked TLS.

### Milestone M2 — TUI HTTP complete (v0.1 TUI closeout)
7. ADR superseding 0005 → **term + signal** driver.
8. **S8–S11** as planned (driver, shell/bindings, collections+send,
   config/polish) on HTTP(+HTTPS once M1.6 lands).

### Milestone M3 — Deep HTTP parity (post-v0.1)
9. Connection pooling / keep-alive (revisit ADR-0019).
10. Digest auth, cookie jar edge cases, compress-request, unix-socket,
    interface bind, ipv4/ipv6 filters if not in S7.
11. `--generate` completions/man; config completeness; HTTPie compat
    polish.
12. Golden matrix expansion to full xh integration suite.

### Milestone M4 — Posting long-tail (still HTTP-shaped)
13. GraphQL UI + SSE streams.
14. OAuth2 (+ OS browser open).
15. `import` / `run` / `remote` / themes completeness / captures /
    scripts / curl interop in TUI.

### Milestone M5 — Protocol expansion (oxl-blocked today)
16. HTTP/2 (+ then gRPC).
17. HTTP/3/QUIC.
18. WebSocket / WSS.
19. mTLS + HTTPS CONNECT proxy.
20. Message signatures (`--unstable-m-sig-*`) if product wants the
    feature gate.

## Q3 — Parallelism vs serial

- **A. Strict WI-0001 serial (core→cli→tui).** Safest for one agent.
- **B. After M1.3 (S5), parallel HTTPS WI with S6.** Faster wall clock;
  merge risk on `core/http`.
- **C. Start S8 after bump even before S7.** Possible once Screen/Key
  exist; send still needs S5+.

**Recommendation: A with narrow B** — bump first; S5 then S6 serial;
HTTPS WI may overlap late S6 if IN-0005 chose A/B; do not open S8
until M1 HTTPS policy is settled so the TUI does not learn a second
degradation story.

## Q4 — Tracking artifact

- **A. One living parity matrix markdown** under
  `context/specs/parity-matrix.md`, updated every shipped WI.
- **B. Only WI plan checklists.** Drift risk.
- **C. Separate matrices per app.** Fine once large; start as one.

**Recommendation: A** — produced at specify stage of this WI; every
implementation WI cites rows it closes.

## Open disagreements (preserve)

1. Whether M1 must include HTTPS before calling "v0.1 CLI done"
   (IN-0005 / WI-0007).
2. `--verify=no` policy (IN-0005).
3. Whether digest auth / `--generate` belong in M1 S7 or M3.
4. Whether gRPC/WS are ever in-scope for oxttp vs a future sibling
   binary — corpus says Posting has them; product may still carve
   them out with permanent degradations.

## Recommendation summary

Adopt definition **A**, milestones **M0→M5**, tracking matrix **A**,
sequencing **A+B**. Next skill: specify the parity matrix + acceptance
gates per milestone; then multi-stage-plan into concrete WIs (bump,
S5–S7, HTTPS, S8–S11, then M3+ backlogs).
