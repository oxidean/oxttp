# WI-0001 plan — oxttp v0.1 staged decomposition

Spec: `artifacts/spec.md`. Slicing per ADR-0008 (core+shared → cli →
tui, serial). Every stage is one work item: bounded, dependency-ordered,
testable, ships via squash-merged PR with `oxl test` green.

## Tranche 0 — foundations (`shared/`, `core/`)

**S1 `shared/args` table-driven parser** — deps: none
Option-table model (kind, default, env fallback, conflicts, requires,
`--no-*` pair, repeat), tokenizer, `--` separator, positional capture,
usage/diagnostic rendering. Driven by a test table, not the cli.
Gate: parse-matrix tests green (shorts, enums, conflicts, negations,
repeats, positionals, env).

**S2 `core` domain model** — deps: none
Request/response/header/body-kind types; REQUEST_ITEM grammar — 9-sep
longest-match scan, 12 variants, escaping rules, `;type=`/`;filename=`
right-scan params; session model; `.posting.yaml` collection types
(schema verbatim, no IO yet); `Screen`/`Key` abstractions (types only).
Gate: grammar unit matrix green incl. corpus edge cases (escaped seps,
empty-key `@file`, `key;` empty header).

**S3 `core/http` h1 transport** — deps: S2
On `std/net` sockets: request serialization, response decode (status
line, headers, content-length, chunked, trailers), redirect policy,
gzip/deflate via `std/compress`, timeouts. Transport behind the port
interface from S2.
Gate: live round-trip tests vs a local `std/net/http` server —
methods, headers, chunked, redirects, compressed bodies.

## Tranche 1 — `cli` (oxttp)

**S4 CLI flag surface** — deps: S1
All 58 corpus flags declared in the option table; `METHOD URL
[REQUEST_ITEM…]` positionals; `--help`/usage shape; every flag parses
and validates (execution may be unwired).
Gate: `--help` covers all 58; parse conformance vs corpus table.

**S5 request path + golden harness** — deps: S2, S3, S4
METHOD/URL/items → `core` request → execute → xh output shape (status
line, headers, body), exit codes. `tests/golden/` differential harness:
local server + request matrix through `xh` and `oxttp`, diffing output.
Gate: basic GET/POST/header/param rows diff-clean vs real xh.

**S6 body & content kinds** — deps: S5
`--json`/`--form`/`--multipart` modes, file uploads (`@file`,
`;type=`/`;filename=` params), `--raw`, stdin, `--print`/`--offline`
variants, nested-JSON key paths.
Gate: full request-item matrix diff-clean vs xh.

**S7 remaining flags + degradation** — deps: S6
Auth kinds, `--session`, `--download`/`--output`, `--verbose`/`--trace`,
`--pretty`/`--style`, `--check-status` exit semantics, env vars (all
14), deferred surfaces (`--verify`, `--cert`, `--http2`, `https://`)
emitting xh-shaped "unsupported" diagnostics.
Gate: 58/58 flags behave or explicitly degrade; matrix green;
zero unknown-flag regressions.

## Tranche 2 — `tui` (oxttp-tui)

**S8 terminal driver** — deps: S2
`stty raw -echo` enter/restore, ANSI input decode (keys, arrows,
modifiers, SGR mouse), output render (alt-screen, cursor addressing,
SGR styles), `stty size` polling, tty detection via stty failure.
Gate: driver smoke harness — scripted input → decoded `Key` stream;
render → expected ANSI.

**S9 app shell + keybinding dispatch** — deps: S8
Screen layout per corpus (URL bar, method selector, request panes,
response pane), focus model, modal stack, all ~114 corpus keybindings
routed — unimplemented actions degrade explicitly.
Gate: headless transcript test — every binding dispatches to its
corpus-named action (or documented deferral).

**S10 collections + request execution** — deps: S9, S3
`.posting.yaml` load/save verbatim, collection tree navigation,
request editing, send-through-`core`, response render.
Gate: round-trip byte-compat vs a Posting fixture file; end-to-end
request via transcript.

**S11 config + polish** — deps: S10
All 40 config keys, theme/styling corpus, remaining modals and
bindings live, startup flags + 5 subcommands.
Gate: config checklist 40/40; subcommand corpus coverage; full
transcript suite green.

## Cross-stage gates (every stage)

- `oxl test ./cli ./tui ./core/... ./shared/...` green
- `oxl build ./cli`, `oxl build ./tui` succeed on pinned toolchain
- Corpus coverage list updated — every touched item mapped
- Squash-merged PR, `type(scope):` title, green CI (build + commit-lint)

## Risks

- `stty`/ANSI TUI is the least-proven surface (S8–S11); mitigate by
  keeping the driver thin behind `Screen`/`Key` and building the
  transcript harness early in S9.
- `std/net` socket API depth unverified for the full h1 feature set —
  S3 spikes first; blockers become upstream oxl issues, not workarounds.
- xh differential harness needs `xh` installed in CI — single static
  binary, download in workflow.
- Upstream gaps tracked: oxidean/oxl#125 (termios/isatty), #126
  (signals), #127 (richer http client), #128 (TLS); none block v0.1
  scope. Ox-Agent docs drift: oxidean/Ox-Agent#78.
