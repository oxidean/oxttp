# ADR-0032 — synchronous send via pending `ESend` effect

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0014 (S10)

## Context

`core/http`'s `Transport.send` is an interface vtable call that
cannot suspend (h1.oxl:10-17) — H1 deliberately blocks the calling
thread on raw externs for the whole exchange. Posting sends
asynchronously: `send-request` starts a spinner and `escape`
cancels in-flight (§1.6/§3). S9's dispatch is pure (returns effect
codes); running the blocking send inside `dispatch` would freeze
the UI with no painted busy state and bury the deviation.

## Decision

1. **Plan and IO split**: `send-request`/`url-enter` build
   `draft → PRequest → model.Req` inside dispatch (pure,
   headless-testable). Plan errors → error toast, no send. A valid
   plan is stashed on `App` and dispatch returns a new `ESend`
   effect.
2. **The main loop owns the block**: on `ESend` it pushes a
   "Sending …" toast, renders + presents a busy frame, then calls
   `exec_send(app)` — the single blocking `H1.send` — which
   installs the response (or error text) into the current tab's
   response state and appends in-memory history. A normal render
   presents the result.
3. **No in-flight cancel in S10**: input arriving mid-exchange
   queues and processes after the response lands; the spec records
   the deviation vs upstream Escape-cancel. A spawned worker was
   rejected — the vtable call still cannot suspend, so a second
   thread buys cancel plumbing that can't actually interrupt the
   socket; streaming kinds (SSE/WS, M4) will force the real async
   design then.
4. **Draft state is PRequest-pivoted**: open/save/send share one
   representation — `tui` translates widget-state ↔ `PRequest`;
   `core/collection.plan_req(PRequest, EnvSet, jar)` produces the
   `model.Req` (enabled rows only, options defaults, substitution,
   auth, UA synth, cookie jar).

## Consequences

- Honest busy frame with zero concurrency; every plan path is
  testable without a socket.
- Blocking is bounded by the corpus 5s default timeout and H1's
  30s dial cap — worst-case freeze is known.
- `focus.on_response` is unset by default so response arrival
  doesn't steal focus; pane title shows status/size/elapsed per
  §4.15.
