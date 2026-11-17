# WI-0001 spec — oxttp v0.1

## Intent

Two drop-in HTTP tools in pure oxl on one domain core:

- `oxttp` — xh-compatible CLI (corpus: `docs/corpus/corpus-xh.md`,
  xh v0.26.3 @ 8b21cc0)
- `oxttp-tui` — Posting-compatible TUI (corpus:
  `docs/corpus/corpus-posting.md`, Posting 3 v3.0.0-beta.1 @ 32c4566)

HTTP/1.1 only — every TLS/h2/h3 surface parses but degrades explicitly
(ADRs 0001, 0006).

## Resolved at specification (was open in brainstorm)

1. **Two binaries.** `oxttp` and `oxttp-tui` ship as separate `package
   main` modules — mirrors upstream (`xh`, `posting` are distinct
   installs) and keeps argv surfaces corpus-identical.
2. **`.posting.yaml` cloned verbatim.** The collection schema is the
   corpus; no oxttp-native keys in v0.1.
3. **Full flag surface first.** `shared/args` consumes a declared
   option table; the `cli` table covers all 58 corpus flags + 10
   request-item operators from day one (a table, not 58 features).
   Execution lands behind it incrementally.

## Architecture contract

```
shared/   args, version, env, output primitives — no domain knowledge
core/     domain: request model, request-item grammar, header model,
          body kinds, response model, redirect policy, auth, sessions,
          collections, transport port, Screen/Key abstractions
cli/      oxttp main — flag table + request-item parse → core → render
tui/      oxttp-tui main — screens, keybindings, collections → core
```

- `core/http` owns the transport port; the h1 implementation sits on
  `std/net` sockets (ADR-0003). Apps never see sockets.
- `shared/args` is table-driven: `cli` declares the corpus option table;
  the parser owns tokenization, validation, usage, diagnostics
  (ADR-0004).
- The TUI terminal layer is pure oxl: `stty` raw mode + ANSI I/O behind
  `Screen`/`Key` abstractions so a future termios driver swaps in
  (ADR-0005).

## Surface contracts

**`oxttp`** — per `corpus-xh.md`: all 58 flags (kinds, defaults, env
fallbacks, conflicts, `--no-*` pairs), the full REQUEST_ITEM grammar —
9 separators in longest-match scan order (`==@` `=@` `:=@` `:@` `==`
`:=` `=` `@` `:`) producing 12 item variants, plus escaping and
file-upload `;type=`/`;filename=` param rules — 14 env vars, xh-shaped
diagnostics and exit codes, output format (status line, headers, body,
syntax coloring where tty).

**`oxttp-tui`** — per `corpus-posting.md`: all 13 flags + 5 subcommands,
~114 keybindings (every binding exists; unsupported-in-v0.1 actions
degrade explicitly), 40 config keys, `.posting.yaml` collection schema
verbatim, screen layout and modal behavior per corpus.

## Degradation contract

- Corpus surfaces always parse/validate (ADR-0006).
- Deferred-in-v0.1 behavior emits the target app's diagnostic shape:
  `https://` URLs, `--verify`/`--cert`/TLS flags, `--http2`/`--http3`,
  Posting keys without backing features.
- A deferral is a spec-tagged item, never absent from the table.

## Verification contract (ADR-0007)

- Coverage: every spec lists the corpus items it implements.
- Proof: differential harness — request matrices through real `xh` and
  `oxttp` against a local `std/net/http` server, diffing status line,
  headers, body, exit code. `tui`: scripted key-input transcripts
  against the headless screen buffer vs captured Posting behavior.
- `oxl test ./cli ./tui ./core/... ./shared/...` green; CI lints
  commit grammar + attribution and builds both binaries on the pinned
  toolchain.

## Acceptance criteria

1. `oxl build ./cli` and `oxl build ./tui` produce working binaries on
   pinned toolchain v0.15.0.
2. `oxttp --help` documents all 58 corpus flags; every flag parses and
   applies its declared kind/default/env fallback.
3. `oxttp` performs real HTTP/1.1 requests through `core/` — headers,
   request items, redirects, compression, auth, proxy env — diff-clean
   vs `xh` on the harness matrix for supported surfaces.
4. `oxttp-tui` launches a full-screen ANSI UI; all ~114 corpus
   keybindings dispatch; `.posting.yaml` collections load/save
   verbatim; requests execute through `core/`.
5. Deferred surfaces produce target-shaped "unsupported" diagnostics
   with zero silent no-ops.
6. Every corpus item maps to a spec-stage entry; none are silently
   dropped.

## Out of scope (v0.1)

- TLS/HTTPS everywhere (blocked on oxl std — decision 0001)
- HTTP/2, HTTP/3, QUIC
- FFI of any kind (unavailable in oxl today)
- `.oxl` package publication, install channels beyond `oxl build`
- Windows/macOS terminal quirks beyond what ANSI+`stty` covers (WSL/Linux
  first; portability is a later milestone)
