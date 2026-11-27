# ADR-0035 — themes quantize to ANSI-8 slots

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0015 (S11)

## Context

Corpus §8.1 pins the theme/styling corpus: 37 builtins (terma
v0.27.0 registry — names verified), user-theme YAML format,
picker semantics, `sidebar_gradient`, `load_*_themes`,
`theme_preview`. Our AnsiScreen paints fg∈0..7 + attrs only;
truecolor emission would mean a driver change mid-stage.

## Decision

1. `Theme` = `{name, is_light, primary, secondary, accent,
   warning, error, success, text}` where each slot is an ANSI-8
   fg id produced by nearest-RGB quantization of the source hex.
   The builtin catalog embeds all 37 terma entries (names + hex
   values verbatim from terma v0.27.0 theme.go); order is the
   registry order (28 dark then 9 light).
2. User themes decode the posting-2 YAML fields through
   `core/yaml`; unset colors inherit galaxy (dark) /
   catppuccin-latte (light); `panel`→Surface2 slot source;
   `foreground`/`text`→text; same-name user theme replaces the
   builtin row; files sort by name; bad file → `Couldn't load
   theme <file>: <err>` startup toast + skip; load at startup
   only (watch_themes is a P2 no-op anyway).
3. Render reads slots off `a.theme` instead of hardcoded fg ids:
   method cell/accent highlights → accent|primary, body text →
   text, warn/error/success toasts + response status classes →
   their slots, header → primary, hints/jump → warning.
   `bg` stays `-1` everywhere (deviation: no background painting).
4. Pickers are MThemePicker/MGradientPicker modals: `Yours`
   group, then Dark, then Light (gradient picker lists
   `theme`/`off`/each theme). Cursor move live-applies when
   `command_palette.theme_preview`; `enter` commits for the
   session; `escape` restores the entry snapshot.
   `load_builtin_themes=false` + ≥1 user theme → only Yours.
5. `sidebar_gradient`: `theme`/`off`/`<theme-name>` — approximated
   by an AttrDim→normal vertical ramp on the sidebar title/accent
   rows (deviation: 8-color palette can't do real gradients).

## Consequences

- Theme fidelity is name/file/picker-exact; color fidelity is
  quantized and documented — a truecolor driver upgrade is an
  M4-era follow-up.
