# WI-0011 implementation record

Diff: `.oxl-version` 0.23.2→0.26.0 + parity-matrix.md row updates.
Zero compat changes needed — the 0.23.2→0.26.0 std surface is
source-stable for everything oxttp consumes.

Evidence (this branch):
- `oxl build ./cli` / `./tui` — clean
- `oxl test` × 8 dirs — all green (cli incl. 13 golden cases +
  exec/digest, core/{collection,http,item,model,session,term},
  shared/args)
- `oxttp --version`/`--help` — xh-faithful banner/options unchanged
- `oxl build` now hard-errors on multi-dir args (was silent-first,
  oxl#131 class) — CI already invokes per-app, unaffected
