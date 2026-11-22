# 0025 — Post-oxl-0.23 unlock sequencing

Status: proposed (2026-11-22, WI-0007 (ox-agent) brainstorm — confirm at
specification / when opening follow-on WIs)

oxl v0.23.2 closed the upstream blockers that shaped oxttp v0.1
deferrals (TLS/HTTPS, termios, signals, multi-arg `oxl test`). After
bumping the pin:

1. **Bump is its own PR** (no feature work mixed in). Refresh
   `.oxl-version`, CI, and `oxl-toolchain.md` capability claims.
2. **Finish S5→S6 on HTTP** so the golden harness lands without
   waiting on TLS policy decisions.
3. **Open an HTTPS WI** that upgrades `core/http` H1 via
   `std/net/tls` (keep owning the h1 codec — ADR-0003 stands) and
   rewrites S7's TLS deferral list against remaining upstream parks
   (mTLS, TLS≤1.2, HTTPS+HTTP-proxy CONNECT, and the
   `--verify=no` policy choice).
4. **Supersede ADR-0005 before S8**: TUI driver uses `std/os/term` +
   `std/os/signal`, not `stty`.

This decision does not by itself supersede ADR-0001; the HTTPS WI
does that when it ships. It does retire the assumption that those
upstream issues are still open.
