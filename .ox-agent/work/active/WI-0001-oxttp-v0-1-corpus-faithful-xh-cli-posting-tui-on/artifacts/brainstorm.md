# WI-0001 brainstorm — oxttp v0.1

Scope: corpus-faithful `oxttp` CLI (xh v0.26.3 @ 8b21cc0) + `oxttp-tui`
(Posting 3 v3.0.0-beta.1 @ 32c4566) on a shared domain core. HTTP-only —
no TLS until oxl std gains it (decision 0001). Monorepo layout fixed
(decision 0002). Everything below is what remains genuinely open.

## Q1 — How to slice the port into work items

- **A. Core-first, then per-app corpus order.** Build `core` + `shared`
  as one tranche (transport, request model, arg parser primitives,
  session/collection model), then `cli` slices, then `tui` slices, each
  in corpus order. Serial; every WI verifiable.
- **B. Vertical per app.** `cli` WI builds whatever `core` it needs;
  `tui` follows and refactors. Less upfront design, but the second app
  inherits a core shaped by the first app's biases — the thing the
  monorepo split exists to prevent.
- **C. Parallel app streams over a minimal core stub.** Faster
  wall-clock, but two streams writing `core/` concurrently invites
  merge friction and a mushy domain boundary.

**Recommendation: A.** The whole point of the layout is one domain core
serving two surfaces; that argues for designing it against *both*
corpora up front rather than letting the CLI shape it alone. CLI first
within the app tranche: it exercises the domain through line-mode I/O
and de-risks core before the TUI's harder terminal problems.

## Q2 — HTTP transport inside `core/`

- **A. Wrap `std/net/http.Client`.** Free, but the surface is
  `request(method,url,ctype,body) -> Resp{status,body,ctype}`: no
  outgoing headers, no redirect control, no chunked decode visibility,
  no compression, no auth, no proxy env. The xh corpus requires every
  one of those. Not viable as the engine.
- **B. Own HTTP/1.1 stack on `std/net` sockets.** Write the real client:
  request serialization, header model, status-line/chunked/content-
  length decoding, redirects, gzip/deflate via `std/compress`, Basic/
  Bearer auth, `HTTP_PROXY` env handling. Full corpus coverage for h1.
- **C. Hybrid.** std Client for the simple path, own stack for flagged
  requests. Two engines to keep honest — drift risk for zero gain.

**Recommendation: B.** Forced by the corpus. Keep transports behind a
port interface in `core/http` so TLS/h2 join without touching apps.

## Q3 — CLI argument surface

- **A. Extend `std/flag`.** int/string/bool Go-style only. Cannot
  express shorts (`-F`), enums, conflicts, `--no-*` negations, repeated
  flags, or positional request items. Out.
- **B. Custom clap-shaped parser in `shared/args`.** Model xh's real
  grammar: option table with kinds, defaults, env fallbacks,
  conflicts/requires, `--flag`/`--no-flag` pairs, `--` separator,
  `METHOD URL [REQUEST_ITEM…]` positionals. Reusable by any future CLI.
- **C. Hand-rolled parse in `cli/main.oxl`.** Quickest, but the grammar
  is 58 flags + 10 operators — a bespoke parser in the app dir becomes
  untestable slush and can't be shared.

**Recommendation: B.** Forced by the corpus; `shared/args` is where it
belongs by construction.

## Q4 — TUI terminal layer (the hard one)

Facts: `std/os` gives `stdin()` + files + `getenv`; `std/os/exec` can run
`stty`/`tput`/`tty`; no termios/isatty/ioctl/signals in std; `extern fn`
binds to compiled-in runtime symbols, not arbitrary user C — true FFI is
not an available escape hatch today.

- **A. Pure-oxl terminal via `stty` + ANSI.** Enter raw mode with
  `stty raw -echo`, restore on exit; read stdin bytes; decode ANSI
  input (keys, arrows, modifiers, mouse SGR); render via ANSI output
  (alt-screen, cursor addressing, styles); poll size via `stty size`
  (no SIGWINCH available). Zero new dependencies — ships with the
  toolchain. Limitations: input is byte-stream polling (no signal-
  driven wakeup), resize detection is poll-lagged, `stty` failure is
  the tty-detection signal (no isatty).
- **B. FFI termios.** Unavailable — externs resolve runtime symbols
  only. Would need an oxl feature request first.
- **C. Headless core + minimal ANSI shell.** Build the full domain
  (collections, navigation, keybinding dispatch) against a
  screen-buffer abstraction with a plain-terminal fallback renderer;
  defer the polished renderer. Keeps progress unblocked but ships a
  degraded first TUI.
- **D. External helper binary** (tiny C termios shim shipped with
  oxttp). Breaks the pure-oxl story; adds a second toolchain to the
  repo. Last resort.

**Recommendation: A, with C's screen abstraction.** Option A is the only
one that ships a real drop-in TUI in pure oxl today. Borrow C's shape —
`core/tui` gets a `Screen`/`Key` abstraction — so if oxl later lands
termios, only the terminal driver swaps. File upstream issues for
termios/isatty/signal support regardless.

## Q5 — Policy for features oxl can't do yet (TLS, h2/h3)

- **A. Parse everything, degrade explicitly.** Every corpus flag parses
  and validates; unsupported behavior produces xh-shaped diagnostics
  ("feature unsupported in this build") rather than silent no-ops or
  missing-flag errors. Preserves the drop-in claim at the surface level.
- **B. Omit unsupported flags.** Breaks corpus parity at the parser —
  scripts that run on xh fail on oxttp with "unknown flag". Violates
  the brief.
- **C. Stub no-op.** Flags accepted but silently ignored — the worst
  option; silent security degradation (`--verify=no` is fine,
  `--verify` silently off is a lie).

**Recommendation: A.** Corpus parity at the parser, honest degradation
at the behavior. Deferrals get tagged per-flag in specs.

## Q6 — Verifying "one-to-one" (how the corpus match gets proven)

- **A. Corpus-driven checklists in specs.** Every spec stage lists the
  corpus items it covers; verification walks the list. Cheap, but
  checklists don't catch behavioral drift.
- **B. Differential golden testing.** A `tests/` harness runs request
  matrices against a local `std/net/http` server through real `xh` and
  `oxttp`, diffing status line, headers, body, exit code. Same idea for
  posting: scripted key-input transcripts vs reference captures.
  Requires xh (and ideally Posting) in CI — both are single binaries.
- **C. Port upstream test suites.** xh's Rust tests and Posting's
  snapshots don't translate mechanically to oxl; high cost, partial
  coverage of the CLI surface.

**Recommendation: B over A.** Checklists define coverage; differential
runs prove it. The local `std/net/http` server makes the harness
self-contained. TUI: keybinding/config checklist + scripted input
transcripts against a headless screen buffer.

## Open questions for specification

- Scope of v0.1's `cli` milestone: full 58-flag parse surface first, or
  request-execution core + flag slice grown incrementally?
- Session/collection persistence format for `tui`: clone
  `.posting.yaml` schema verbatim (corpus-faithful) — confirm no
  oxttp-native additions in v0.1.
- `oxttp` binary name: Posting ships `posting`; xh ships `xh`. Ours:
  `oxttp` + `oxttp-tui`, or single `oxttp` binary whose argv[0]/subcommand
  selects TUI (like `git`)? Corpus-parallel suggests two binaries.
