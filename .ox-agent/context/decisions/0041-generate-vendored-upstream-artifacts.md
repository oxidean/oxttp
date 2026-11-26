# ADR-0041 — `--generate` lands via vendored upstream artifacts + emit-time substitution

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0016 (brainstorming)

## Context

Corpus §4.7 marks `--generate` `post`, but discovery showed upstream's
own generated outputs are committed files — `completions/{_xh,
xh.bash, xh.elv, xh.fish, xh.nu, _xh.ps1}` (fish includes a
`__xh_complete_data` preamble), `doc/xh.1`, `doc/xh.1.md` — fetchable
at the pinned commit (all HTTP 200). Upstream generation is
`clap_complete::generate(shell, app, bin_name)` for completions and a
roff/markdown template pass (`{{date}}` = SOURCE_DATE_EPOCH ?: now,
`{{version}}`, generated options list) for man; man ignores bin_name.

## Decision

Vendor the upstream artifacts at @8b21cc0: `scripts/gen-assets.sh`
fetches + emits `cli/gen_assets.oxl` holding the bytes as string
literals (no embed mechanism in oxl — keeps the single-binary rule;
provenance header names commit + source URLs). Un-defer the routing;
`--generate` conflicts-with-positional already stands in spec.oxl.
Emit-time substitution mirrors upstream inputs: completions replace
the `xh` command token with the resolved bin name; man patches the
`.TH` date (SOURCE_DATE_EPOCH ?: today `YYYY-MM-DD`) and the version
string with ours (documented — upstream emits its own version);
man-markdown likewise. Output → stdout, exit 0.

## Alternatives considered

- Park (`post` row) — viable but leaves a visible gap when the
  faithful bytes already exist upstream.
- Port clap_complete/man generation — rejected: ~500 lines of clap
  internals to reproduce bytes upstream itself vendors; no
  differential oracle without clap.

## Consequences

- §4.7 moves to done-with-documented-substitution; §6 completions/man
  row satisfied by the same assets.
- Golden: one fixture per kind with normalized date; the generation
  script is repo-tooling, not shipped code.
