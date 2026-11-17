# 0022 — stdin TTY detection via /dev/stdin realpath (oxl#125 gap)

Status: accepted (2026-11-17, WI-0006 specification)

oxl has no isatty. Upstream reads stdin whenever
`!stdin.is_terminal()`, and a non-TTY stdin counts as a Raw body —
even empty (`GET </dev/null` still sends json CT/Accept +
Content-Length: 0). Approximating this exactly matters more than
the corner cases it misses.

`os.fullpath("/dev/stdin")` resolves through /proc/self/fd/0:
`/dev/pts/<n>` (also `/dev/tty`, `/dev/console`) => terminal =>
do not read; a real path (regular file or /dev/null) or the empty
string (anonymous pipe) => redirected => read to EOF. Verified on
WSL Linux (pts, /dev/null, pipe, file). Non-POSIX targets fall back
to "always read" — matching non-TTY CI, the primary harness
environment.

Consequence: interactive use on a real terminal never blocks on
stdin; scripted use gets upstream's stdin-as-body semantics
including the surprising empty-stdin json-headers case.
