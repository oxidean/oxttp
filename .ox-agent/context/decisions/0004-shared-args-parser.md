# 0004 — Custom clap-shaped argument parser in shared/args

Status: accepted (2026-11-17, WI-0001 brainstorm)

`shared/args` hosts a custom argument parser modeling the xh clap
surface: short/long flags, enum values, conflicts and requirements,
`--flag`/`--no-flag` negation pairs, repeated options, `--` separator,
env-var fallbacks, and `METHOD URL [REQUEST_ITEM…]` positionals.

`std/flag` (Go-flag-style int/string/bool) cannot express this grammar;
a bespoke parser inside `cli/` would be untestable and unshareable.

The parser is table-driven: `cli` declares the 58-flag option table from
the corpus; the parser owns tokenization, validation, usage text, and
diagnostics in xh's shape.
