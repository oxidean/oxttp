# Contributing

oxttp is a young project — an xh-compatible HTTP CLI and a
Posting-compatible TUI written in [oxl](https://github.com/oxidean/oxl),
sharing one domain core in a single oxl workspace. Expect rough edges;
the upstream language is still growing the stdlib this project needs
(gaps are filed against `oxidean/oxl`, not patched around silently).

## Build & test

Requires the [oxl toolchain](https://github.com/oxidean/oxl/releases)
matching `.oxl-version` — `oxl` on PATH resolves the pin.

```sh
oxl build ./cli -o oxttp        # the CLI (package main)
oxl build ./tui -o oxttp-tui    # the TUI (package main)

# `oxl test` honors only its first package-dir arg (oxidean/oxl#131) —
# invoke once per package dir, same as CI:
for d in $(git ls-files '*.oxl' | xargs -n1 dirname | sort -u); do
  oxl test "$d"
done
```

`oxl build` emits binaries only for `package main` dirs; building the
two apps transitively compiles `shared/` and `core/`. Tests are
`*_test.oxl` files with `fn test_*` cases.

## Layout

- `shared/` — shared kernel: args parser, version/output primitives
- `core/` — domain: request/response model, item grammar, h1 transport,
  sessions, collections, terminal ports
- `cli/` — `oxttp`, the xh-compatible CLI (`package main`)
- `tui/` — `oxttp-tui`, the Posting-compatible TUI (`package main`)
- `docs/corpus/` — per-app compatibility contracts, source-cited against
  pinned upstream revisions. The corpus is the spec: implementations
  match it, deviations are declared in specs, never silent.

## Commits and PRs

- Subjects are `type(scope): subject`; PR titles the same —
  `scripts/commit-check.sh` enforces it (CI `commit-lint` on every PR,
  `.githooks/commit-msg` locally — opt in with
  `git config core.hooksPath .githooks`).
- No AI attribution anywhere on commits or PRs — no `Co-authored-by` /
  `Generated with` / `Made-with` trailers, bot signatures, or invisible
  markers. The rule lives in `.cursor/rules/no-ai-attribution.mdc` and
  the gate scans commits, PR titles, and PR bodies.
- Commit with the repo's configured git identity — never an agent
  identity or `-c user.*` overrides.

## Workflow

Planning and implementation run through
[ox-agent](https://github.com/oxidean/Ox-Agent) work items — see
`AGENTS.md` and `.ox-agent/` for the pipeline. Each plan stage is one
work item and one PR; stages declare their dependencies in the v0.1
plan (`.ox-agent/work/`).
