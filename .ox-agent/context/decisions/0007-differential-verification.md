# 0007 — Differential golden verification

Status: proposed (2026-11-17, WI-0001 brainstorm — confirm at specification)

The one-to-one corpus match is proven by differential testing, not
checklists alone:

- `cli`: a harness runs request matrices against a local `std/net/http`
  server through real `xh` and `oxttp`, diffing status line, headers,
  body, exit code, and stderr shape. xh is a single static binary — CI
  can install it.
- `tui`: scripted key-input transcripts drive both `oxttp-tui`'s
  headless screen buffer and captured Posting behavior; corpus
  keybinding/config checklists define coverage.

Specs enumerate which corpus items each stage covers; the harness
proves the covered items behave identically.
