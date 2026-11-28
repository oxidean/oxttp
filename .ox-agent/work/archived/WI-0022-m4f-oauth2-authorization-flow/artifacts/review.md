# WI-0022 independent implementation review

Scope: implementation artifacts listed by the implementation run, with emphasis on OAuth security boundaries, secret handling, callback validation, transport caps, cache isolation, and run/TUI integration.

Outcome: pass with notes. No blocking correctness or security finding was identified in the reviewed paths.

Evidence reviewed:

- `core/oauth/token.oxl` sanitizes endpoint and transport failures, fixes a 30s token timeout, disables redirects/cookie carry, and caps token responses at 1 MiB.
- `core/oauth/callback.oxl` bounds callback head size, per-connection time, total wait, and extraneous connections; it enforces method, Host, path, and single-state matching before consuming an authorization result.
- `core/oauth/manager.oxl` keeps token state session-local, partitions entries by the fully resolved configuration identity, refreshes with rotation, and requires explicit re-login after `invalid_grant`.
- `core/oauth/flow.oxl` uses CSPRNG state/PKCE material, argv browser launch, loopback listener setup before browser open, and explicit IPv6-loopback degradation.
- `core/collection/collection.oxl`, `tui/coll.oxl`, and `tui/cli.oxl` wire the engine into collection planning, interactive send/forget, and noninteractive `posting run` behavior with warnings kept off stdout.

Notes carried forward rather than blockers:

- OS credential-store persistence remains intentionally absent; users receive the memory-only warning (ADR-0059).
- OAuth browser authorization is synchronous and Escape cancellation remains out of scope (ADR-0061).
- IPv6 loopback redirect URIs validate semantically but explicitly degrade at execution because the pinned runtime listeners are IPv4-only (ADR-0063).

Validation evidence: local `oxl test ./core/oauth` passed rc=0, including callback, manager, token, browser-flow, validation, and cache-isolation suites. CI matrix now includes `core/oauth`.
