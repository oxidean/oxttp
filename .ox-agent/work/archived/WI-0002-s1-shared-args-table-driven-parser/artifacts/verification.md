# WI-0002 verification — shared/args parse-matrix gate

Commands run on branch feat/wi-0002-args-parser in the s1 worktree.
All output below is real, captured this run.

## Gate commands

`oxl test ./shared/args` — EXIT 0, 15/15:

```
  test_defaults ... ok
  test_longs_and_values ... ok
  test_shorts ... ok
  test_enums ... ok
  test_numbers ... ok
  test_negations ... ok
  test_overrides ... ok
  test_conflicts ... ok
  test_requires ... ok
  test_positionals ... ok
  test_env ... ok
  test_actions ... ok
  test_render ... ok
  test_tip ... ok
  test_edges ... ok
```

Per-package loop (`oxl test ./cli`, `./core/http`, `./shared/version`,
`./tui`) — each EXIT 0 (no test fns; packages untouched by this WI).

`oxl build ./cli -o /tmp/oxttp` — EXIT 0.
`oxl build ./tui -o /tmp/oxttp-tui` — EXIT 0.

Smoke:

```
$ /tmp/oxttp       -> oxttp 0.1.0-dev GET http://localhost
$ /tmp/oxttp-tui   -> oxttp-tui 0.1.0-dev
```

## Toolchain caveat found while verifying

`oxl test` consumes only its FIRST package argument:
`oxl test ./cli ./shared/args` printed nothing (cli has no tests and
the args package never ran); `oxl test ./shared/args ./cli` ran the
15 args tests. The configured `test_command`
(`oxl test $(git ls-files '*.oxl' | xargs -n1 dirname | sort -u)`)
therefore exercises only the alphabetically-first dir (`cli` — no
tests). Multi-package CI testing must loop per-directory or the
test_command should be revisited; flagged as an upstream oxl gap
(one-arg runner), with the per-dir loop used here as the working gate.

## Spec-matrix traceability (spec.md "Test matrix" -> test fns)

- shorts (clusters -jf/-fj, -vv/-v -v, -sauto/-s=fruity/-s monokai,
  -of.out, unknown -z) -> test_shorts
- longs (--x, --x=v, --x v, missing value incl. argv-end,
  flag-with-value, unknown) -> test_longs_and_values
- enums (valid, alias, invalid+possible-values, next-arg form)
  -> test_enums
- numbers (uint ok/negative/garbage, float ok/garbage, kint negative)
  -> test_numbers + test_edges
- counts (-vv, -v -v, --no-verbose reset, -vv --no-verbose -v -> 1)
  -> test_shorts + test_negations
- negations (set/unset both orders, tri-state -1/0/1, --no-proxy clears
  + re-add, --no-raw clears, --no-help parses, --no-x=v rejected,
  nono opt-out) -> test_negations + test_edges
- overrides (both orders, three-cycle, j-f-j) -> test_overrides
- repeats (--proxy a --proxy b list incl. =-form, last-wins single
  KSTR) -> test_env (list rows) + test_longs_and_values
- conflicts (later-arg blame both orders, session pair,
  negated-then-free, generate-vs-positional) -> test_conflicts
- requires (--continue -> both missing; +download -> output only;
  full set ok; negated requirement still missing) -> test_requires
- positionals (order/interspersed, required missing, extras overflow,
  -- separator, lone dash) -> test_positionals + test_edges(fix2)
- env (fallback, argv beats env, ordered pair first-wins, validated,
  empty pair == empty value, negation blocks env, override cancels
  env, env sets flag) -> test_env
- defaults -> test_defaults
- actions (--help -> help_short, error-before-help, help
  short-circuits, --version/-V, --man -> help_long, required skipped)
  -> test_actions + test_edges
- render (usage_line exact, Arguments/Options sections, hidden
  absent, no- forms absent, short-vs-long help suffixes, diag_of,
  version_string, help_extra) -> test_render + test_edges
- did-you-mean tip (near hit both directions, far miss) -> test_tip

## Rollback readiness

The package is new and additive; revert = delete shared/args/ — no
other package imports it yet (cli/tui untouched, builds green).
