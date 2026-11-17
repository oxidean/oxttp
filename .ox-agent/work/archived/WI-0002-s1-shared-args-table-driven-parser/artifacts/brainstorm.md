# WI-0002 brainstorm — parser engine shape

Umbrella calls already settled: parser lives in `shared/args`,
table-driven, xh-shaped diagnostics (0004); engine now, 58-row table at
S4 (0011); corpus-complete parse surface (0006). This brainstorm picks
the ENGINE architecture — how occurrences become results — plus two
api-shape calls.

## Option A — per-option folded state (CHOSEN)

Table `Spec{opts, poss}` + `Matches{spec, states, pos, diag, act}`.
Tokenize left-to-right; each occurrence folds into that option's state
immediately (`seen`, `vals`, `negated`, `active_pos`, `last_pos`).
Overrides reset the named option's state in place; negation resets +
marks; conflicts/requires evaluated post-loop on net state +
`active_pos` (the argv position of the first occurrence in the current
active streak — determines which name the conflict error blames:
clap faults the later-seen arg).

Pros: one left-to-right pass, O(1) getters, state machine mirrors clap's
own occurrence model, override/negation semantics land as simple reset
rules. Cons: eager folding means ordering edge cases must be handled in
the fold (mitigated by `active_pos` bookkeeping + the matrix tests).

## Option B — value bag (REJECTED)

Parse into `name -> []values`, getters interpret. Loses occurrence
ORDER, which is exactly what `--no-*` last-wins, override groups, and
conflict-blame need. Can't express tri-state without re-adding an
order channel. Rejected.

## Option C — pure event log, replaying getters (REJECTED)

Record `[]Event{opt, polarity, value, pos}`; every getter replays.
Most faithful model of clap occurrences, but each read is O(events),
the replay rules duplicate the same fold logic anyway, and the
diagnostics still need positions — it is Option A wearing a second
encoding. Rejected; A keeps the same ordering fidelity via
`active_pos`/`last_pos` directly.

## Sub-decisions

1. **Spec ownership**: `newspec -> own Spec`; `parse(spec: own Spec,
   argv, envpairs) -> own Matches` consumes the spec into the result —
   every post-parse read (getters, `help`, `usage_line`) hangs off
   `Matches`, which is the only thing apps/tests hold. Free
   `usage_line(ref Spec)`/`help(ref Spec)` also exist for pre-parse
   rendering if ever needed. If the `own`-into-field move fights the
   checker, fall back to `spec: ref Spec` field + separate spec param —
   decided at implementation, recorded in findings.
2. **Diagnostic text**: clap 4 shape fixed in spec — `error: <msg>`,
   blank, `Usage: <prog> [OPTIONS] <pos...>`, blank,
   `For more information, try '--help'.`; specific message forms per
   failure class enumerated in the spec so tests pin them.
3. **Did-you-mean**: include — small bounded Levenshtein over declared
   longs + synthesized `no-*` names; clap emits
   `tip: a similar argument exists: '--verbose'` for near misses and it
   is user-visible corpus shape.
4. **Env**: `parse` takes `envpairs []str` (`KEY=value`); `parse_os`
   builds it from each option's declared env names via `os.getenv`
   (empty == unset, documented deviation).
5. **API flavor**: builder fns (`flag`, `count`, `str_`, `int_`,
   `uint`, `float_`, `enum_`, `pos`, `env`, `conflicts`, `requires`,
   `overrides`, `repeat`, `hidden`, `alias`, `action`, `nono`,
   `default`) — comma-lists for multi-name attrs; kind-specific
   defaults as strings parsed through the option's own validator.

## Open questions for spec

- Exact `Usage:` line shape when spec has zero options (TUI side has
  13 flags + subcommands — `[OPTIONS]` always emitted when any
  non-hidden option exists; subcommands are out of engine scope v0.1,
  TUI parses its 5 subcommands as positionals).
- Whether `--help`/`--version` are declared options (yes — action
  field) vs engine-builtins (no — keeps engine table-pure).
