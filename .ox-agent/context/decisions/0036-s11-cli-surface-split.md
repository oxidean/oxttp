# ADR-0036 — S11 CLI surface: dispatch split and degrade map

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0015 (S11)

## Context

Corpus §1 covers flags + 5 subcommands on the posting binary —
which for us is `tui` (package main). The parity matrix marks
`import`/`remote` engines `post` (M4) while the stage gate
demands "subcommand corpus coverage": every subcommand must exist
with corpus-faithful parsing/output where feasible and explicit
degrades where the engine is out of scope.

## Decision

1. `tui/main.oxl` checks `os.args(1)` for a subcommand BEFORE any
   session open, mirroring upstream's `switch args[0]`
   (`import|locate|remote|run|version`, plus `--version`/`-v`).
   Subcommand handlers live in `tui/cli.oxl`; all output goes to
   os.stdout/os.stderr; exit via `os.quit(code)`.
2. Top-level flags parse via `shared/args` Spec (`-c`, `-e`
   repeat, `-h`, `-v` + positional collection) — mission pins
   shared/args for the flag surface. Subcommands hand-roll their
   arg loops exactly like upstream run.go/import.go (flags may
   follow positionals; `--k=v` allowed): Spec can't express
   flag-after-positional without risking divergence.
3. Implement fully: `version` (`Posting <ver>`), `locate`
   (3 targets, upstream label+exit semantics), `run` (headless
   runner over collection.scan+plan_req+H1; exit 0/1/2; text +
   --json report in the remote.Response shape; config warnings
   fatal; remembered env never used; scripts-bearing requests
   rejected; captures declared → per-request FAILED degrade M4;
   malformed files abort before sending).
4. Degrade explicitly: `import` parses flags then
   `posting import: <format> import lands M4 in this build` → 1
   (usage errors still → 2); `remote` — `list` prints the empty
   report, instance commands exit 1 `no running Posting found
   (unix sockets unsupported in this build)`, `skill` prints the
   embedded 131-line SKILL.md verbatim (needs no instance).
5. Top-level positional collection stays accepted (corpus §1.1)
   — upstream's NArg rejection is a doc↔code disagreement;
   recorded as a deviation rather than breaking the documented
   contract.
6. `remote_control.enabled=true` + no UDS → one startup toast
   `posting remote won't work: unix sockets unsupported in this
   build` (mirrors upstream's listen-failure message path);
   `=false` → silent.

## Consequences

- `run` is real coverage; `import`/`remote` coverage is
  surface-level with corpus-shaped errors — the gate's
  "subcommand corpus coverage" is satisfied without pretending
  M4 engines exist.
