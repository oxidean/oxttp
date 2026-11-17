# WI-0002 discovery — S1 shared/args table-driven parser

Scope (plan S1): option-table model (kind, default, env fallback,
conflicts, requires, `--no-*` pair, repeat), tokenizer, `--` separator,
positional capture, usage/diagnostic rendering. Test-table driven, not
cli-driven. Gate: parse-matrix tests green (shorts, enums, conflicts,
negations, repeats, positionals, env). The 58-row xh table itself is S4
(decision 0011); S1 proves the engine can express it.

## Corpus surface the table model must express (corpus-xh.md sections 1-4, 8)

- 56 declared options + `--help` + `-V/--version` = 58 flags.
- Kinds: bool, count (`-v`, `-q`, `-x`), string, float (`--timeout`),
  usize (`--max-redirects`), enum (`--pretty`, `--style`, `--auth-type`,
  `--ssl`, `--http-version`, `--generate`, `--unstable-m-sig-alg`) with
  aliases (`1` -> `1.0`, `ssl2.3` -> `auto`), repeatable strings
  (`--proxy`, `--resolve`, `--format-options`, `--unstable-m-sig-comp`).
- `args_override_self`: later occurrence wins; repeats accumulate.
- `--no-<long>` synthesized for EVERY non-positional arg (incl.
  `--no-help`, `--no-version`); SetTrue + overrides_with means last
  occurrence wins, `--no-proxy` clears accumulated values;
  `--check-status`/`--stream` are tri-state `Option<bool>`.
- `conflicts_with`: `--multipart` conflicts `--raw`,`--compress`;
  `--session-read-only` conflicts `--session`; `--generate` conflicts
  the positional.
- `requires`: `--continue` requires `--download` AND `--output`.
- `overrides_with_all` radio group: `--json`/`--form`/`--multipart`.
- env fallback: `--verify` <- `REQUESTS_CA_BUNDLE` then `CURL_CA_BUNDLE`
  (ordered list, first present wins). `XH_CONFIG_DIR`-driven
  `default_options` argv-prepend is a cli concern (S4+), not engine.
- hidden flags: `--bearer`, `--default-scheme`, `--native-tls`,
  `--unstable-m-sig-*` — parse but absent from help.
- Positionals: `raw_method_or_url` (required), `raw_url` (optional),
  `raw_request_items` (variadic). Method detection (all-alpha) and the
  `help` positional literal are cli logic — the engine captures
  positionals only.
- Actions: `--help` = HelpShort (disable_help_flag means custom),
  `-V/--version` = version; action fires at argv position (errors
  before it still error; it stops parsing).
- Diagnostics clap-shaped: `error: <msg>` + `Usage:` line +
  `For more information, try '--help'.`; parse errors exit 2
  (corpus section 8 — man page's "1" is wrong).

## oxl v0.15.0 constraints discovered (language repo is read-only ref)

- `oxl test` runs `fn test_*` in `<name>_test.oxl` files beside library
  sources in the same `package <dirname>` — VERIFIED empirically
  (`/tmp/args` experiment). Layout: `shared/args/*.oxl`,
  `shared/args/args_test.oxl`, all `package args`.
- Package name must equal its dir name; `oxl build/test` take leaf
  package dirs. `test_command` in config enumerates `git ls-files`
  dirs — `shared/args` is picked up automatically.
- `oxl test` passes no user argv, so `parse` MUST take argv as a
  parameter (`parse(spec, argv, envpairs)`); a thin `parse_os(spec)`
  wrapper reads `os.args`/`os.nargs` for the real binaries.
- `os.getenv(name)` returns `""` for unset; no `setenv`, no
  enumeration. Env is carried into `parse` as a `[]str` of `KEY=value`
  pairs (fully test-injectable). DEVIATION (documented): an env var set
  to the empty string is indistinguishable from unset via `parse_os`,
  so it is treated as unset; corpus-relevant only for pathological
  `REQUESTS_CA_BUNDLE=""`.
- `std/collections.Map` is str->int only; `[]str` pair lists suffice.
- No slice literals in the language — the table is built through
  builder calls (`args.flag`, `args.enum_`, `args.env`, ...), not
  literal syntax. `own`/`ref`/`mut` move semantics; slices stored in
  heap structs must be `own []T` fields (`new(slice)`), arena slices
  must not escape into `own` structs.
- `std/flag` confirmed insufficient (decision 0004) — Go-flag-style
  int/string/bool, argv-bound, no shorts/enums/negation/positionals.
- No `std/env` module; env access is `std/os.getenv`. `std/strconv`
  covers atoi/parseint/parsefloat; `std/strings` covers
  split/join/trim/upper/contains.

## Prior decisions cited (not re-litigated)

- 0004 parser in `shared/args`, table-driven, xh-shaped diagnostics.
- 0011 full table lands in S4 on top of this engine.
- 0006 parser is corpus-complete; deferred behaviors degrade in the
  app's shape (engine concern: every surface must be expressible).
- 0007 differential verification is S5+; S1's gate is the unit
  parse-matrix.

## Stage-level open questions (to resolve at spec/plan)

- Exact clap error-text shape for conflicts/requires/values — corpus
  pins style, not byte-exact strings; spec fixes chosen shapes.
- Did-you-mean tips (`tip: a similar argument exists: '--x'`) —
  cheap Levenshtein over declared longs; include if it stays small.
