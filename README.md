# oxttp

HTTP tooling written in [oxl](https://github.com/oxidean/oxl):

- **`oxttp`** — drop-in replacement for [xh](https://github.com/ducaale/xh),
  the friendly terminal HTTP client (curl/HTTPie-style surface).
- **`oxttp-tui`** — drop-in replacement for [Posting](https://github.com/darrenburns/posting),
  the terminal API client (Postman-style TUI).

Both apps share one domain core and a shared utility layer in a single
oxl workspace — write the HTTP engine once, drive it from a CLI and a TUI.

## Status

Early scaffold. The compatibility surface contracts are pinned as source-
cited corpora under `docs/corpus/` and the feature work is driven through
ox-agent work items. HTTP/1.1 only for now — HTTPS lands when oxl std
gains TLS support.

## Layout

```
oxl.work            workspace: four modules
shared/             shared kernel — version, arg/env/output primitives
core/               domain — request/response model, transport, sessions
cli/                oxttp        — xh-compatible CLI app (package main)
tui/                oxttp-tui    — Posting-compatible TUI app (package main)
docs/corpus/        per-app compatibility contracts (source-cited)
```

## Build & run

Requires the [oxl toolchain](https://github.com/oxidean/oxl/releases)
(`oxl` on PATH, `std/` next to the binary).

```sh
oxl run  ./cli          # oxttp
oxl run  ./tui          # oxttp-tui
oxl build ./cli  -o oxttp
oxl build ./tui  -o oxttp-tui
oxl test ./...
```

## Development

Commits and PR titles follow `type(scope): subject` and carry no AI
attribution — enforced by `scripts/commit-check.sh` (opt in locally with
`git config core.hooksPath .githooks`). Planning and implementation run
through [ox-agent](https://github.com/oxidean/Ox-Agent) work items; see
`.ox-agent/` for pipeline state.
