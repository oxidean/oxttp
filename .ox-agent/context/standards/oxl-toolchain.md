# oxl toolchain constraints (oxttp)

Pinned toolchain: `.oxl-version` → v0.15.0. `oxl` on PATH resolves the pin;
bump pin and CI together. CI installs `oxl-toolchain-linux-x86_64.tar.gz`
from oxidean/oxl releases.

**Pending bump:** latest oxl is v0.23.2. WI-0007 plans the post-bump
unlock sequence; WI-0008 (not yet opened) is the chore PR that moves
the pin. Capability notes below still describe the **pinned** 0.15.0
surface; a “≥0.23.2” subsection records what the bump unlocks so
docs are not silently stale.

## Build / test

- `oxl build <pkg-dir> -o <bin>` emits binaries only for `package main` dirs;
  building `./cli` or `./tui` transitively compiles `shared/` and `core/`.
- `oxl test <pkg>...` accepts dirs and `./...` globs. On 0.15.0 only the
  first package-dir arg was honored (oxidean/oxl#131) — CI loops
  per-dir; re-check after bumping past the fix.
- Workspace: `oxl.work` `use ./<dir>` members; each module has `oxl.mod`
  (`module <path>`, `oxl 0.3`, `require <path> v0.0.0` for in-workspace deps).
- Imports: `import "<module>/<subdir>"` (subdir = package); `as` aliases exist.

## std capabilities that shape oxttp (pinned 0.15.0)

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

## Unlocked on oxl ≥ 0.23.2 (after WI-0008)

- `std/net/tls` — TLS 1.3 client (`dial`/`dial_timeout`/`client`);
  `std/crypto/x509` trust + hostname verify; `https://` seam on
  `std/net/http` (`Url.secure`, `Client.tlscfg`). See oxl `docs/tls.md`.
  Parks: mTLS, TLS≤1.2, HTTPS via HTTP-proxy CONNECT, no
  `insecure_skip_verify`.
- `std/os/term` — `isatty`, `size`, `raw`/`restore` (replaces planned
  `stty` TUI driver).
- `std/os/signal` — poll-style `arm`/`take` for SIGINT / SIGWINCH.
- Richer `std/net/http` client — still evaluate against the corpus
  before replacing oxttp's own H1 (ADR-0003).
