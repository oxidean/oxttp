# oxl toolchain constraints (oxttp)

Pinned toolchain: `.oxl-version` → **v0.23.2**. `oxl` on PATH resolves the pin;
bump pin and CI together. CI installs `oxl-toolchain-linux-x86_64.tar.gz`
from oxidean/oxl releases.

## Build / test

- `oxl build <pkg-dir> -o <bin>` emits binaries only for `package main` dirs;
  building `./cli` or `./tui` transitively compiles `shared/` and `core/`.
- Prefer per-dir `oxl test` loops in CI (historically oxidean/oxl#131 silently
  dropped trailing package-dir args; re-verify before collapsing the loop).
- Workspace: `oxl.work` `use ./<dir>` members; each module has `oxl.mod`
  (`module <path>`, `oxl 0.3`, `require <path> v0.0.0` for in-workspace deps).
- Imports: `import "<module>/<subdir>"` (subdir = package); `as` aliases exist.
- Multi-return signatures must be `[T, err]` (oxl ≥0.23) — use a struct when
  returning two non-err values (e.g. `term.Size` for screen dimensions).
- `os.writefile_` returns **bytes written** on success (not `0`); negative errno
  on failure.

## std capabilities that shape oxttp (pinned ≥0.23.2)

- `std/net/http`: HTTP/1.1 client with richer surface; `https://` via
  `Url.secure` + `Client.tlscfg` (`docs/tls.md`).
- `std/net/tls`: TLS 1.3 client (`dial`/`client`); `std/crypto/x509` trust.
  Parks: mTLS (#221), TLS≤1.2 (#224), HTTPS CONNECT (#222).
- `std/os/term`: `isatty`, `size`, `raw`/`restore` — TUI driver substrate.
- `std/os/signal`: `arm`/`take` for SIGINT / SIGWINCH.
- `std/flag`: still insufficient for xh clap surface — custom parser in `shared/`.
- Errors as `[v, err]` tuples; struct literals `Type{field: v}`.

## Still blocked upstream (see `context/references/oxl-protocol-deps.md`)

HTTP/2 (#218), HTTP/3 (#219), WebSocket (#220), gRPC (#223), mTLS (#221),
CONNECT (#222), TLS 1.2 (#224).
