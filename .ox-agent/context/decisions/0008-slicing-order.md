# 0008 — Slicing: core-first serial, then cli, then tui

Status: proposed (2026-11-17, WI-0001 brainstorm — confirm at specification)

Work items decompose as:

1. `core` + `shared` tranche — designed against both corpora up front
   (transport, request model, `shared/args` parser, session/collection
   model, `Screen`/`Key` abstractions).
2. `cli` tranche — corpus-order slices; line-mode I/O exercises the
   domain and de-risks core before the harder terminal work.
3. `tui` tranche — corpus-order slices on the proven core.

Serial by design: parallel app streams would write `core/` concurrently
and blur the domain boundary the monorepo exists to protect.
