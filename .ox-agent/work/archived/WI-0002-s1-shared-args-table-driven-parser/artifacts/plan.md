# WI-0002 plan — shared/args engine build order

Spec: `artifacts/spec.md` (model/API/semantics/diagnostics/test matrix).
Decisions: 0012 (folded state, parse consumes Spec), 0013 (pinned
diagnostic templates). One work item = one PR; no sub-decomposition —
the "stages" below are file-level build order inside the single
implementation stage.

## Files (all `package args`, dir `shared/args/`)

1. `spec.oxl` — Opt/Pos/Spec structs, kind+action constants, builders
   (`newspec`, `flag`, `count`, `str_`, `int_`, `uint`, `float_`,
   `enum_`, `pos`, `env`, `conflicts`, `requires`, `overrides`,
   `alias`, `repeat`, `hidden`, `nono`, `action`, `def`,
   `help_extra`), name→index lookup, `no-` resolution helper.
2. `parse.oxl` — State/Matches, `parse`, `parse_os`, tokenize fold
   (longs, `=` values, `no-` negation, short clusters, `--`,
   interspersed positionals, actions), env pass, requires/conflicts
   post-loop, validators (KINT/KUINT/KFLOAT/KENUM), did-you-mean
   Levenshtein, diagnostic assembly per spec templates, all getters.
3. `usage.oxl` — `usage_line`, `help(long)` renderer (arguments +
   options sections, alignment, suffixes), `diag_of`.
4. `args_test.oxl` — `fn test_*` matrix per spec §Test matrix;
   fixture spec builder shared across tests.

## TDD order (red → green per batch)

- B1 model+defaults: spec build, flag/count/str/enum getters,
  defaults, positionals order → first compile of the package.
- B2 tokenize: longs/shorts/`=`/clusters/missing+flag-value errors.
- B3 fold semantics: negation, overrides, repeats, counts, tri-state.
- B4 cross-refs: conflicts, requires, env pass, required positionals.
- B5 actions + render: help/version act, usage_line/help/diag_of,
  did-you-mean.
- B6 matrix fill: every spec row green; `oxl fmt` all files.

## Gates

- `oxl build ./shared/args` and `oxl test ./shared/...` green
  (test_command picks the dir up via `git ls-files`).
- `oxl build ./cli ./tui` still green (no app changes required —
  engine is test-table driven per the S1 gate).
- Matrix covers every spec row; deviations in spec §Deviations stay
  the only silent-vs-corpus gaps.

## Risks

- `own` move semantics (Spec→Matches, `own []T` fields) — mitigated by
  B1 landing first; fallback is `ref Spec` param threading (spec
  notes it; ADR 0012 stays, api shape only).
- Levenshtein over 58+58 names — bounded, no alloc concerns.
- Env "present but empty" — documented deviation, parse_os-only.
