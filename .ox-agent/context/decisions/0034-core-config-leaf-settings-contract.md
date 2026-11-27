# ADR-0034 — core/config leaf and the settings contract

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0015 (S11)

## Context

S11 wires all 40 corpus config keys (corpus-posting.md §2). The
loader is consumed by two surfaces: the TUI startup path and the
`run` subcommand (which treats config warnings as fatal for
unattended use — cmd/posting/run.go). Verified upstream semantics
(config.go) are non-obvious and must not drift: file
wrong-typed-value → whole file ignored; one bad POSTING_* env
value → ALL env overrides dropped; enumerated keys reset to
defaults with warnings; `keymap` replaces whole default key lists.

## Decision

New leaf `core/config` (ADR-0016 layout):

1. `Settings` struct carries all 40 leaf keys as typed fields
   (nested sections flattened into prefixed fields:
   `history_enabled`, `heading_visible`, `ssl_ca_bundle`,
   `focus_on_startup`, …) plus `keymap: []KV` (ordered pairs —
   oxl has no str-map) and `nerd_fonts: int` tri-state
   (-1 unset, 0 false, 1 true — `*bool` upstream).
2. `defaults()` reproduces config.go `Defaults()` verbatim,
   including `$PAGER`/`$EDITOR` env reads.
3. `load(file, probe) -> Settings + warns[]`: read file when it
   exists (unreadable non-ENOENT → warn, defaults survive); DOM
   decode — any parse error OR any wrong-typed known key → whole
   file ignored + `Couldn't read <file>: <err>`; unknown keys
   tolerated silently. Then POSTING_* env merge — `__` nesting,
   skip empty + `config_file`; bool spellings 1/yes/on/true
   0/no/off/false; ANY env decode error → drop ALL env overrides
   + `Ignoring POSTING_ environment settings: <err>`. Then
   `validate()` resets the 6 enumerated keys with `Unknown <k>
   %q; using %q` warnings. File path resolution follows
   paths.go (POSTING_CONFIG_FILE→abs; XDG only when absolute).
4. `keys_for(action, defaults) -> []str`: comma-split,
   lower+trim each key — replaces the whole default list.
5. Paths helpers (`config_dir`, `config_file`, `data_dir`,
   `theme_dir`, `history_dir`, `env_memory`, `default_coll_dir`)
   live here too — paths.go is one source with config.go.

## Consequences

- TUI + run share one loader; no Settings reaches App widgets
  directly — `apply_settings(App, Settings)` maps fields onto
  shell state so tests can drive either side.
- Env probing goes through a `getenv(name)->str` function value
  injected by callers (os.getenv in prod, tables in tests).
