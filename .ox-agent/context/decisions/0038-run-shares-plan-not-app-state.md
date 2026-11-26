# ADR-0038 — `run` shares the plan, not App state

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0015 (S11)

## Context

`posting run` reuses collection.scan + plan_req + H1, but the
corpus pins differences from the interactive path: "Cookies and
response captures carry forward during this run only", "No
history is written", "The UI's remembered environment is never
used", config warnings are fatal, and any malformed request file
aborts the run before anything is sent (the TUI instead renders
malformed files as sidebar placeholders).

## Decision

1. The run loop keeps its own request-scoped jar (`[]JarEnt`
  shape — same origin scoping as the App jar) threaded through
  the request sequence; nothing touches `a.jar`, `a.history`,
  disk history, or `environments.json`.
2. Selection ordering is lexical by collection-relative path —
  `collection.scan` output order is retained (scan already emits
  sorted rel paths; run re-sorts defensively on the rel key) and
  requests execute sequentially on the same goroutine (sends are
  synchronous — ADR-0032).
3. Validation differs intentionally from the TUI: any node with
  `err != ""` aborts with exit 1 before a single send; requests
  with `scripts` or empty `url` abort likewise. The TUI's
  placeholder-row rule is presentation — run.go's abort rule is
  authoritative for headless.
4. `plan_req` output maps onto the remote.Response JSON shape at
  report time (status/headers/body|bodyBase64/size/elapsedMs);
  a declared `captures` map → per-request FAILED degrade (M4) —
  never silently skipped, matching upstream's
  all-captures-must-succeed failure rule.

## Consequences

- No shared mutable state between run and TUI paths; the only
  shared code is decode/plan/transport, which are stateless.
