# 0002 — Monorepo layout: shared / core / cli / tui

Status: decided (owner: Jesse, 2026-11-17)

One oxl workspace (`oxl.work`), four modules, domain-driven split:

- `shared/` — shared kernel: version, argument-parsing primitives,
  output/terminal helpers, env access. No domain knowledge.
- `core/` — domain: request/response model, request-item grammar,
  headers/body kinds, transport (h1 on `std/net`), session & collection
  model consumed by both apps. Transports hide behind `core/http` so
  TLS/h2 can join later.
- `cli/` — `oxttp` binary: the xh-compatible flag + request-item
  surface (`package main`).
- `tui/` — `oxttp-tui` binary: the Posting-compatible terminal app
  (`package main`).

Module paths are `github.com/oxidean/oxttp/<mod>`; `require … v0.0.0` +
workspace `use` resolves locally (Go-workspace shape). `cli` and `tui`
depend on `core` + `shared`; `core` depends on `shared`; `shared`
depends on nothing project-internal.
