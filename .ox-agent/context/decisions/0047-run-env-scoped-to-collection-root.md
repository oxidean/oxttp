# ADR-0047 — `run` env scoping pinned to the collection root

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0019 (M4c)

## Context

Upstream `run.go` resolves environments differently from the TUI:
default is `env.Stack(root, BaseName)` — the collection ROOT's
`posting.env` + `posting.local.env` only; `-e` specs resolve via
`environmentFiles(specs, []string{root})` — named envs in the root
only, file args relative to CWD, base auto-included only through a
named env's stack. Our S11 `run_env` searches CWD → collection dir →
config dir and defaults to the CWD base stack — a deviation from both
upstream `run` and the corpus §6.1 layering (which describes the TUI,
not `run`).

## Decision

`run_exec` resolves env exactly as upstream `run.go`:

- No `-e`: file list = root's `posting.env`, `posting.local.env`
  (whichever exist), root = `-c` dir or target dir/file parent.
- With `-e`: reuse `env_file_list`/`env_file_list_mode` semantics but
  with `dirs = [collection_root]` — named envs resolve in the root
  only; file specs probe CWD-relative then root; any spec suppresses
  the implicit base.
- `settingsInEnvironmentFiles` port: each loaded env file is scanned
  for `POSTING_*` names → stderr
  `posting run: <basename> sets <names>, but settings aren't read
  from environment files. Set them in config.yaml or your shell
  instead.`
- Parse/usage/load errors, the always-printed report (incl. `error`
  field under `--json`), `-c` without PATH (`target="."`), and the
  verbatim `runUsage` text all port from `cmd/posting/run.go`.

## Consequences

- `run` env behavior now matches upstream `run.go` exactly; the TUI's
  wider env-dir search is untouched (different upstream function —
  `appConfig`'s `envDirs` — correctly stays as-is).
- `run` and TUI intentionally diverge on env scoping, as upstream does.
