# ADR-0027 — TUI driver via std/os/term + std/os/signal

- Status: accepted
- Date: 2026-11-23
- Supersedes: ADR-0005 (pure-oxl terminal via stty + ANSI)

## Context

ADR-0005 chose `stty raw -echo` / `stty size` because oxl lacked
termios, isatty, and signals. oxl ≥0.23.2 closed those gaps
(`std/os/term`, `std/os/signal`). ADR-0025 step 4 required superseding
ADR-0005 before deepening Posting screens (S9+).

## Decision

`core/term` owns an `AnsiScreen` + `Session` driver that:

1. Enters raw mode with `std/os/term.raw(stdin)`
2. Probes size with `std/os/term.size(stdout)`
3. Observes `SIGINT` / `SIGWINCH` via `std/os/signal` poll (`arm`/`take`)
4. Flushes a cell buffer as ANSI CSI (alternate screen)

`tui/main` opens a `Session` when stdin is a tty; non-tty falls back to
a one-line version banner (CI-safe). Full key decode and screens stay S9.

## Consequences

- No `stty` subprocess; restore is `Raw.restore()` + leave alt screen.
- Resize is event-driven (SIGWINCH), not poll-lagged `stty size`.
- ADR-0005 remains historical; do not implement its stty path.
