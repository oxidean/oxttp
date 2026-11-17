# 0012 — shared/args engine: folded per-option state, parse consumes Spec

Status: accepted (2026-11-17, WI-0002 brainstorm)

`shared/args` parses a declared `Spec{opts, poss}` into
`Matches{spec, states, pos, diag, act}` in one left-to-right fold:
each occurrence updates that option's state (`seen`, `vals`,
`negated`, `active_pos`, `last_pos`) immediately. `--no-*` resets and
marks negated; `overrides` reset the named option in place; conflicts
and `requires` evaluate post-loop on net state, blaming the option
with the later `active_pos` — clap's behavior of faulting the
later-seen argument.

Alternatives weighed (WI-0002 brainstorm): a flat name→values bag
loses the occurrence ordering that negation, override groups, and
conflict-blame all need; a pure event log with replaying getters
re-encodes the same fold at O(events) per read.

`parse(spec: own Spec, argv, envpairs) -> own Matches` consumes the
spec so every post-parse read — typed getters, `help`, `usage_line` —
hangs off the one result object apps hold; `oxl test` passes no argv,
so `argv` and `envpairs` (`KEY=value` `[]str`) are parameters and a
thin `parse_os(spec)` wraps `os.args`/`os.getenv` for binaries.
`os.getenv` cannot distinguish empty-set from unset: env vars set
empty are treated as unset (documented deviation, no corpus case).

Consequence: S4's 58-flag table is pure data declared through builder
functions; all ordering semantics live in the fold and are pinned by
the parse-matrix tests.
