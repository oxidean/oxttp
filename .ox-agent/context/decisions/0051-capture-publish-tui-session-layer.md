# ADR-0051 — TUI capture publish mirrors upstream `captureResponse`

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0018 (M4b response captures)

## Context

Upstream `App.captureResponse` (internal/ui/environments.go:137,
called from app.go:682 on every completed send) evaluates captures
against the response body **regardless of HTTP status class**, using
the request snapshot; failure → `toastWarning` "Couldn't capture
response: …" and **no** session mutation; success → merge into the
session variable map (highest layer). Docs (environments.md):
captures don't run on intermediate stream updates, history loads, or
requests that fail without a response; cancelled/replaced requests
never publish.

## Decision

1. `tui/coll.oxl install_resp` evaluates `a.pending_preq.captures`
   against the **raw** `resp.body` (pre-prettify) after a successful
   transport exchange — i.e. any status class, matching upstream.
   `send_failed` (transport error, no response) never captures.
2. Failure → warning toast `Couldn't capture response: <err>`; success
   → each pair upserted via the `session_set` path, but with a single
   `rebuild_env` + `var_rows_build` after the batch (upstream merges
   the whole map atomically; per-set rebuilds would be O(n²) and could
   flash intermediate env states).
3. Session layer stays highest-precedence (env.build_set appends
   session last — unchanged). Captured strings are literal: no
   re-substitution (upstream same; substitution only reads the layer).
4. History preview (`hist_open`) renders stored responses without
   re-capturing — matches upstream "don't run when loading history".

## Consequences

- `posting run` capture gating (skip on Error/Warning class) is a
  *run-loop* rule for WI-0019, not an engine rule — `capture_values`
  itself is status-agnostic, exactly like upstream `CaptureValues`.
- No new keybindings/config keys: captures are file-declared only
  (corpus §6.4; upstream has no UI editor for them either — "edited
  in the file and preserved when saving", which `draft_to_request`
  already does via `r.captures = a.preq.captures`).
