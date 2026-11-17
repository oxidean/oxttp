# 0013 — shared/args diagnostics pinned by spec, not upstream bytes

Status: accepted (2026-11-17, WI-0002 specification)

The corpus pins clap's diagnostic STYLE (error line + usage + help
footer, exit 2) but does not quote every message byte-for-byte, and
real clap's text varies by release. WI-0002's spec therefore declares
exact message templates per failure class — unexpected-argument with
optional `tip: a similar argument exists` (Levenshtein <= 3),
missing-value, invalid-value with `[possible values: ...]`,
conflict ("the argument '--later' cannot be used with '--earlier'"),
and the multi-line "the following required arguments were not
provided:" list — and the parse-matrix tests assert those literals.

Where clap's observable behavior needed a judgment call the spec
records a deviation rather than guessing silently: conflict blame
uses `active_pos` (first occurrence of the current active streak);
a dash-prefixed token is never consumed as an option value
(`--timeout -1` needs `=`); an env var set to the empty string is
treated as unset (`os.getenv` limitation, ADR 0012).

Consequence: S4's 58-flag table and S5's differential harness compare
against REAL xh output; byte-level drift found there is corrected in
these templates, not in the tests.
