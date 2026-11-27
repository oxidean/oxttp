# ADR-0043 — color palettes extracted verbatim from vendored `.tmTheme`, not approximated

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0016 (specification)
- Amends: ADR-0040's "hand-rolled ANSI approximation" assumption

## Context

ADR-0040 assumed syntect palettes were unrecoverable (compiled
`.themedump` binary in upstream) and scoped colors to a hand-picked
ANSI-16 approximation. Specification-time reading of upstream
`build.rs`/`formatting/palette.rs` showed the theme *sources* are
vendored in `assets/themes/{ansi,solarized,monokai,fruity}.tmTheme`
at the pinned commit, every foreground uses the `#RR000000`
palette-index encoding (`convert_color`: alpha 0 → R is the ANSI
slot), and header-element styles resolve through a fixed, enumerable
scope-stack list (`palette!{}` macro — 11 header elements).

## Decision

Extract, don't approximate: `scripts/gen-assets.sh` resolves each
element scope-stack against each vendored `.tmTheme` offline (syntect
prefix-match semantics, document-order override) and emits
`cli/gen_styles.oxl` — a static `{theme, element} → SGR` table.
Runtime ports `convert_color` exactly: index 0–6 → SGR 30–36;
7 → uncolored (upstream quirk); else `38;5;<n>`; `a!=0` →
`38;2;r;g;b`; fontStyle → bold/underline/italic SGR.

Remaining approximation (documented, spec S4): body-highlight
*grammars* — our hand-rolled tokenizers for json/xml/html/css/js vs
upstream's syntect grammar sets. Palette values are exact; token
boundaries are ours.

## Consequences

- Header coloring reaches byte-exact SGR parity for all four themes;
  body JSON tokens colored with exact palette values.
- `assets/themes/*.tmTheme` join the vendored set under
  `scripts/gen-assets.sh` (same provenance header, @8b21cc0).
- ADR-0040 stands otherwise (FmtOpts plumbing, pipeline semantics).
