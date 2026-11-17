# 0009 — Two binaries: oxttp + oxttp-tui

Status: accepted (2026-11-17, WI-0001 specification)

The CLI and TUI ship as separate `package main` modules
(`cli/` → `oxttp`, `tui/` → `oxttp-tui`) rather than one binary with
argv[0]/subcommand dispatch. Upstream ships two distinct installs
(`xh`, `posting`) — two binaries keeps each argv surface
corpus-identical and the drop-in claim literal.
