# WI-0020 verification — GraphQL and SSE

Verification executed in `/tmp/wi20-verify.sh` against a clean copy of the
WI-0020 worktree with non-target `_test.oxl` files stripped per package,
mirroring the CI matrix isolation.

## Results

- `cli`: rc=0, 149 passing tests, 0 failure markers
- `core/capture`: rc=0, 45 passing tests
- `core/collection`: rc=0, 31 passing tests
- `core/config`: rc=0, 15 passing tests
- `core/env`: rc=0, 14 passing tests
- `core/http`: rc=0, 80 passing tests
- `core/item`: rc=0, 9 passing tests
- `core/model`: rc=0, 3 passing tests
- `core/session`: rc=0, 3 passing tests
- `core/term`: rc=0, 28 passing tests
- `core/yaml`: rc=0, 18 passing tests
- `shared/args`: rc=0, 15 passing tests
- `shared/version`: rc=0, no tests present
- `tui`: rc=0, 170 passing tests
- `oxl build ./cli`: rc=0
- `oxl build ./tui`: rc=0
- CLI `--version` smoke: rc=0
- non-TTY TUI smoke: rc=0
- overall rc=0

## Acceptance coverage

The suite covers GraphQL document lowering and substitution, scalar variables,
POST/Accept behavior, SSE field parsing, caps and terminal events, deadline
handling, GraphQL warning classification, TUI editor round trips and event
rendering, CLI stream JSON output, plus regression coverage across the existing
HTTP, collection, TUI, and golden CLI suites.

Logs live under `/tmp/wi20-test-*.log` with summary at
`/tmp/wi20-verify-summary.txt`.
