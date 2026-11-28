# ADR-0061 — synchronous browser flow, strict callback caps, documented oxl listener limit

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0022 (M4f OAuth2 authorization flow)

## Context

Upstream authorization-code sign-in opens the browser, listens on the exact
loopback redirect host, waits up to three minutes, and lets Escape cancel
through the send context. oxttp's TUI send path is synchronous (ADR-0032).
oxl 0.26.0 has no poll/select API and no cancellable stdin read, while
`std/net.listen` binds `INADDR_ANY` rather than a caller-selected loopback
address.

## Decision

1. Keep OAuth authorization synchronous with the existing send path and keep
   upstream's three-minute authorization budget outside the resource request
   timeout. Do not claim Escape cancellation in UI text; this build cannot
   process Escape while blocked.
2. Implement the upstream callback contract strictly: loopback-IP redirect
   validation, port `0` expansion, GET-only, exact Host/path, exactly one
   constant-time-style checked state, exactly one non-empty code, valid-state
   denial handling, no-store/no-referrer/plain-text response, first outcome
   wins, listener closes immediately.
3. Add bounded resource caps: request head at most 16 KiB, each accepted
   connection bounded to 5 seconds, at most 64 nonmatching/extraneous
   connections before login failure, token endpoint bodies at most 1 MiB,
   token endpoint exchange timeout 30 seconds, token endpoint redirects never
   followed.
4. Record the platform limitation explicitly: the socket is exposed on
   `INADDR_ANY` because oxl 0.26.0 cannot bind a specific loopback address.
   The unguessable state plus Host/path strictness and short lifetime are
   mitigations, not full parity.

## Consequences

- Users can complete normal browser sign-in, denial, and timeout flows, but
  cannot cancel with Escape in this build.
- The callback attack surface is small and time-bounded, yet loopback-only
  binding remains a required future oxl/std improvement for exact upstream
  security parity.
- A future async terminal/poll runtime can add cancellation without changing
  OAuth protocol semantics.
