# ADR-0060 — `posting run` uses non-interactive OAuth

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0022 (M4f OAuth2 authorization flow)

## Context

Pinned upstream `cmd/posting/run.go` constructs an HTTP client without an
OAuth instance, so every OAuth2 request in `posting run` fails with `OAuth
2.0 is not configured`, even unattended `client_credentials` requests. That
behavior conflicts with the user-facing agent/run documentation saying saved
authentication is used, and would make the most automation-friendly grant
useless headlessly.

At the same time, a runner used by agents must never surprise-open a browser
or block for the three-minute interactive authorization budget.

## Decision

Wire `posting run` to `core/oauth` with `interactive=false`:

- `client_credentials` acquires/re-acquires tokens unattended.
- `authorization_code` may use or refresh an already valid cached token.
- If browser consent would be required, fail with the upstream
  non-interactive error `send the request to authorize OAuth in your browser
  first`; never open a browser from `run`.
- OAuth errors count as request failures under the normal run outcome and
  exit-code rules; sanitized error text goes to the per-request result, not
  raw token endpoint bodies.

## Consequences

This is a deliberate positive deviation from pinned upstream behavior: oxttp
supports client-credentials in `run` where upstream currently fails all
OAuth. With ADR-0059's memory-only store, browser-authorized tokens cannot
yet survive across separate run processes, so first-time authorization-code
use remains a TUI flow until persistent vault support exists.
