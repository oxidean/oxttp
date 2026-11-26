# ADR-0028: Toolchain upgrades land as pin-only PRs ahead of consumers

Status: accepted (2026-11-25, WI-0011)

## Context
oxl 0.26.0 ships the surfaces WI-0013+ consume (h2/h2c, mTLS, TLS
version pins, CONNECT, WebSocket, gRPC). In-flight work (WI-0012 S9)
holds a worktree on the 0.23.2 pin; AGENTS.md requires pin and CI move
together, which they do automatically since CI reads `.oxl-version`.

## Decision
Bump `.oxl-version` alone on its own branch+PR; consumers branch off
post-bump main. Never fold a global pin change into a feature branch —
the pin is the unit of revert. No opportunistic migration to std client
APIs in the same diff (ADR-0003 keeps our h1 transport a port).

## Consequences
- Bump diff = one line; revert = same line.
- S9 (0.23.2 worktree) merges clean either order — it doesn't touch the
  pin and its consumed APIs are source-stable across the gap.
- `oxl build`'s new single-package hard-error is a no-op for CI
  (already per-app invocations).
- h3 exception documented: oxl#219 closed COMPLETED but ships no
  consumable package — `--http-version 3*` stays `oxl-blocked` in
  parity-matrix.md until a real surface exists.
