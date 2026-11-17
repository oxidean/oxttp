# oxl toolchain constraints (oxttp)

Pinned toolchain: `.oxl-version` → v0.15.0. `oxl` on PATH resolves the pin;
bump pin and CI together. CI installs `oxl-toolchain-linux-x86_64.tar.gz`
from oxidean/oxl releases.

## Build / test

- `oxl build <pkg-dir> -o <bin>` emits binaries only for `package main` dirs;
  building `./cli` or `./tui` transitively compiles `shared/` and `core/`.
- `oxl test <pkg>...` accepts dirs and `./...` globs.
- Workspace: `oxl.work` `use ./<dir>` members; each module has `oxl.mod`
  (`module <path>`, `oxl 0.3`, `require <path> v0.0.0` for in-workspace deps).
- Imports: `import "<module>/<subdir>"` (subdir = package); `as` aliases exist.

## std capabilities that shape oxttp

- `std/net/http`: HTTP/1.1 client — `Client{tmo:}` +
  `.request(method,url,ctype,body) -> [Resp,err]`, `.get`, `.post`;
  `Resp{status,body,ctype}`. String bodies; no structured headers,
  redirects, compression, or auth surface. **No TLS — HTTPS unsupported.**
- `std/flag`: Go-flag-style int/string/bool only — insufficient for xh's
  clap surface (shorts, enums, conflicts, `--no-*`, positional request
  items); a custom parser lives in `shared/`.
- No termios / TUI library in std — the TUI layer needs raw ANSI +
  whatever input layer the plan defines (FFI is a later decision; not
  needed for the std-only slice).
- Errors as `[v, err]` tuples; struct literals `Type{field: v}`.
