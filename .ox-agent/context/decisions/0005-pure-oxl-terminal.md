# 0005 — Pure-oxl terminal layer via stty + ANSI

Status: superseded (2026-11-23 by ADR-0027 — `std/os/term` + `std/os/signal`)

`tui/` drives the terminal in pure oxl: `std/os/exec` runs
`stty raw -echo` to enter raw mode (restore on exit); input is the stdin
byte stream decoded as ANSI sequences (keys, arrows, modifiers, SGR
mouse); rendering is ANSI output (alternate screen, cursor addressing,
SGR styles); size polls via `stty size`.

Constraints discovered: no termios/isatty/ioctl/signals in std; `extern
fn` binds compiled-in runtime symbols, not user C — true FFI is
unavailable today. `stty` failure doubles as tty detection; resize
detection is poll-lagged (no SIGWINCH).

The TUI's internals sit behind `Screen`/`Key` abstractions in `core/` so
a future termios driver (or an oxl std feature) swaps in without
touching app code. Upstream tracking: oxidean/oxl#125 (termios/isatty),
oxidean/oxl#126 (signals).
