# WI-0002 spec — shared/args table-driven parser (S1)

Plan: WI-0001 plan S1. Decisions: 0004 (parser home/shape), 0011 (table
first, 58 rows at S4), 0006 (corpus-complete surface), 0012 (folded
engine, parse consumes Spec). Corpus: `docs/corpus/corpus-xh.md`
sections 1, 4.8, 8 — this spec pins the ENGINE; xh's concrete table
lands in S4.

## Intent

`shared/args` (`package args`, module `github.com/oxidean/oxttp/shared`)
is a declaration-driven argv parser expressing xh's clap-4 surface:
typed options, `--no-*` negation pairs, conflicts/requires/overrides,
repeats, counts, enums+aliases, env fallbacks, hidden flags,
positionals, `--` separator, clap-shaped usage/diagnostics, and
help/version actions. Driven by a test table — no cli dependency.

## Non-goals (S1)

- The 58-row xh table, `METHOD/URL` method detection, `help` positional
  literal, `default_options` config-file argv prepend (all S4+).
- Subcommand machinery (TUI's 5 subcommands parse as positionals).
- REQUEST_ITEM grammar (S2). Executing parsed intent (never engine).

## Model

```
Spec  { prog: str, version: str, about: str,
        opts: own []Opt, poss: own []Pos }
Opt   { name: str,            // long name, no dashes
        short: str,           // "" or one char
        kind: int,            // KFLAG KCOUNT KSTR KINT KUINT KFLOAT KENUM
        action: int,          // ANONE AHELP_SHORT AHELP_LONG AVERSION
        metavar: str, help: str, def: str,     // def parsed via kind
        env: own []str,       // ordered fallback names, first wins
        conflicts: own []str, requires: own []str, overrides: own []str,
        vals: own []str,      // KENUM canonical values
        aliases: own []str,   // "alias=canonical" pairs
        repeat: int, hidden: int, nono: int } // nono default 1
Pos   { name: str, metavar: str, help: str, required: int, variadic: int }
State { seen: int, neg: int, vals: own []str, active_pos: int,
        last_pos: int, env: int }
Matches { spec: own Spec, states: own []State, pos: own []str,
          poslen: own []int,   // per-slot flat range start, -1 absent
          diag: str, act: str, ok: int }
```

- Kinds: KFLAG (bool set-true), KCOUNT (occurrence count), KSTR,
  KINT (any int), KUINT (>=0), KFLOAT, KENUM (value in `vals` or
  `aliases`, canonicalized).
- Action options are ordinary KFLAGs plus `action`; a positive
  occurrence records `m.act` and stops the token loop at that argv
  position (clap HelpShort/Version fire at occurrence).
- `--no-<long>`: synthesized for every opt with `nono!=0` at lookup
  time — exact long names win first, then `no-` prefix resolves to a
  negation. Negating takes no value.

## Builder API (all on `mut Spec`)

`newspec(prog, version, about) -> own Spec`; `flag(s,name,short,help)`;
`count(s,...)`; `str_(s,name,short,metavar,help)`; `int_`; `uint`;
`float_`; `enum_(s,name,short,metavar,vals_csv,help)`;
`pos(s,name,metavar,required,variadic,help)`; `env(s,name,csv)`;
`conflicts(s,name,csv)`; `requires(s,name,csv)`;
`overrides(s,name,csv)`; `alias(s,name,alias,canonical)`;
`repeat(s,name)`; `hidden(s,name)`; `nono(s,name)` (opt OUT);
`action(s,name,act)`; `def(s,name,value)`; `help_extra(s,line)` for
trailer text. Multi-name attrs are comma-separated, split+trimmed.

## Parse API

```
parse(spec: own Spec, argv: []str, envpairs: []str) -> own Matches
parse_os(spec: own Spec) -> own Matches   // argv=os.args[1:], envpairs
                                          // from declared env names
```

Getters on `ref Matches`: `get_flag(m,name)->bool`,
`get_count->int`, `get_str->str`, `get_int->int`, `get_float->float`,
`get_enum->str` (canonical), `get_list(m,name)->own []str`,
`present(m,name)->bool` (net positive OR env-applied),
`negated(m,name)->bool`, `state(m,name)->int` (1 set / -1 negated /
0 absent — the Option<bool> tri-state), `src_env(m,name)->bool`,
`pos(m,name)->[str,int]` (present flag 2nd), `pos_all(m,name)->own []str`
(variadic), `npos(m)->int`, `pos_at(m,i)->str`.
Renderers: `usage_line(spec|m)->str`, `help(spec|m)->str`,
`diag_of(m)->str` (`""` when `ok`).

## Tokenize semantics (in argv order)

1. `--` → every later token is positional.
2. `--name`, `--name=v`: exact long match; else `no-` prefix → negation
   of matching opt; else unknown →
   `unexpected argument '--x' found` + optional `tip: a similar
   argument exists: '--y'` (Levenshtein <= 3 over longs + `no-*`
   forms + `-s` shorts).
3. `-xyz`: short cluster — KFLAG/KCOUNT shorts apply and the scan
   continues; a value-kind short takes the cluster REST as value
   (stripping a leading `=`), or the next argv token when the cluster
   ends — but only if that token does not start with `-` or is exactly
   `-` (clap: `-1` is a flag, not a value). Unknown short →
   `unexpected argument '-z' found`.
4. Lone `-` → positional. Any other token → positional (interspersed
   with options freely).
5. Value via `=` always allowed on value kinds; `=` or attached value
   on KFLAG/KCOUNT/negation → `unexpected value 'v' for '--x' found`.
6. Missing value (end of argv or next token is a flag) →
   `a value is required for '--x <META>' but none was supplied`.
7. Value validation at occurrence, first failure wins:
   KINT/KUINT → `invalid value 'v' for '--x <META>': invalid digit
   found in string`; KFLOAT NaN/garbage → `... : not a valid number`;
   KENUM → `invalid value 'v' for '--x <META>'` +
   `\n  [possible values: a, b, c]` (+aliases accepted, canonicalized).
8. Positive occurrence fold: neg=0; seen++ (KCOUNT: that is the count);
   repeat → push `vals`; else `vals={v}` last-wins; `active_pos` =
   argv index if streak empty; `last_pos` = argv index; then each name
   in `overrides` resets as if never seen (`seen=0, neg=0, vals=nil,
   active_pos=-1`), then the option's own `action` may end the loop.
9. Negation fold (`--no-x`): `seen=0, neg=1, vals=nil, active_pos=-1`.
10. Positional fold: fills declared slots in order — each non-variadic
    slot takes one flat value; the variadic slot takes the remainder.
    Extra positionals beyond a non-variadic declaration tail →
    `unexpected argument 'tok' found` (clap's excess-positional form).
    Conflicts/requires may name positional slots; a slot counts as
    present when it captured a value.

## Post-loop (skipped when `act != ""` or an error already fired)

- Env pass, in table order: option net-absent → first present name in
  `env` wins, value validated like an argv value (errors here say
  `for '--x'` too), `env=1` marked. Net-absent = never seen OR
  overridden/negated back to zero.
- `requires`: for each present option, each required name must be
  present (option or positional) → missing collect into one error:
  `the following required arguments were not provided:` + indented
  list of `--name` / `<META>` lines.
- `conflicts`: pairwise on net-present args; offender = later
  `active_pos`: `the argument '--later' cannot be used with
  '--earlier'`. Positional offenders print their metavar.
- Required positional slots with no captured value → same
  `required arguments` error listing their metavars.
- `def`: each unset option falls back to `def` parsed through its kind
  at getter time (declared string; KFLAG "0"/"1").

## Diagnostics (clap 4 shape; `m.diag` holds the full block, exit 2)

```
error: <message>
[<blank>\n  tip: a similar argument exists: '--y'\n]
\n
Usage: <prog> [OPTIONS] <pos-metas...>
\n
For more information, try '--help'.
```

`[OPTIONS]` appears when any non-hidden option exists; positional
metavars appear in declaration order. `ok=1` with `act` carries
"help_short"/"help_long"/"version"; the app prints `help()` or
`version` and exits 0.

`help()` renders: about line, `Usage:` line, `Arguments:` section
(each declared positional: metavar + help), `Options:` section —
`  -s, --name <META>` per visible opt aligned to a help column,
`[possible values: ...]`, `[aliases: ...]`, `[default: v]`,
`[env: NAME=]` suffixes; hidden opts never listed; `--no-*` forms are
not listed (clap hides them too). Long vs short shape is a
`help(long:int)` flag: long adds the suffixes, short omits them.

## Test matrix (the S1 gate — `shared/args/args_test.oxl`, package args)

Fixture spec exercising every engine feature incl. a mini-xh core
(json/form/multipart override trio, verify env pair, session pair,
continue requires, proxy repeat, verbose count, pretty enum,
timeout float, max-redirects uint, generate enum conflicts positional,
hidden bearer, help/version actions, 3 positionals).

Rows (each asserts values AND, for errors, the diagnostic text):
shorts (cluster `-jv`, `-pHBb`, `-p HBb`, `-p=HBb`, unknown `-z`),
longs (`--x`, `--x=v`, `--x v`, missing value, flag-with-value),
enums (valid, alias, invalid+possible-values), counts (`-vv`, `-v -v`,
`--no-verbose` reset, `-vv --no-verbose -v` →1), negations
(`--x --no-x` unset, `--no-x --x` set, tri-state -1/0/1, `--no-proxy`
clears repeats, `--no-help`), overrides (`--form --json` → json,
`--json --form` → form, three-cycle), repeats (`--proxy a --proxy b`
list, last-wins single KSTR), conflicts (error names later arg,
negated-then-conflict free, generate⊥positional), requires
(`--continue` alone → both missing; `+--download` → output missing;
full set ok; negated requirement still missing), positionals
(order, interspersed, required missing, extras, `--` separator —
`-- --json` is positional), env (fallback applies, argv beats env,
ordered pair first-wins, env value validated), defaults, actions
(`--help` → act, `--bogus --help` errors first, `--version` stops),
usage_line/help smoke (metavars, hidden absent, possible values,
`[env:` in long help), did-you-mean tip.

## Corpus coverage (this stage)

corpus-xh §1: override-self, disable_help_flag custom help, `--` —
engine implements all; §4.8 `--no-*` semantics incl. tri-state — full;
§8 exit-2 diagnostics shape — engine implements; §4.x per-flag rows —
S4's table consumes this engine. Posting corpus: `oxttp-tui` flags
(13 + 5 subcommands) — same engine, table at its stage.

## Deviations (documented, corpus-checked)

- Empty env var == unset (`os.getenv` cannot distinguish; ADR 0012).
- Conflict blame uses `active_pos` (first occurrence of current active
  streak); clap faults the later token — equivalent on real argv.
- `--timeout -1`-style flag-shaped next tokens are never consumed as
  values (clap parity — negative floats need `=` form).
- `requires`/`missing-positional` diagnostics use clap's multi-line
  "the following required arguments were not provided:" list form.
