# ADR-0040 — pretty/format pipeline parity; colors via hand-rolled ANSI approximation

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0016 (brainstorming)

## Context

`--format-options` is already parsed+validated in sem (upstream-exact
diagnostics) then deferred at routing; `--pretty=colors|all` and
`--style` warn-degrade. Reading `printer.rs`/`buffer.rs`/`headers_fmt.rs`
surfaced upstream defaults our formatter diverges on: `json.indent`
defaults to **4** (ours emits 2), `sort_headers` defaults to
`pretty.format()` (headers sort under all/format/colors — ours never
sorts), titlecase applies to HTTP/1.x heads only (h2/h3 keep
lowercase — ours always titlecases), the response-body binary
suppressor is TTY-gated (ours unconditional), `valid_json` is a full
parse (ours checks the first byte), and bodies dispatch on
ContentType with event-stream auto-streaming. Header values with
non-ASCII bytes render latin1 + ` (UTF-8: <text>)`.

Upstream colors come from syntect `.tmTheme` palettes compiled into
the binary — no oxl std equivalent exists, so byte-exact palettes are
unobtainable; the element set is small (~13 classes: method, path,
version, status, reason, header name, colon, header value, JSON
punct/string/number/bool/null/key, error).

## Decision

- Un-defer `--format-options`: plumb `fmt_opts` into effective
  `{json_indent or 4, json_format or pretty.format(), xml_indent or 2,
  xml_format or pretty.format(), headers_sort or pretty.format()}`.
- Port the format pipeline: ContentType dispatch (incl.
  `--response-mime` substring map), `jparse`-based `valid_json`,
  indent-parameterized JSON pretty, bounded XML indent formatting
  (approximation — documented), header sort by lowercase name,
  h1-only titlecase, latin1+UTF-8 annotation, TTY-gated response
  suppressor (request side stays unconditional — upstream asymmetry),
  `--stream` + event-stream → raw passthru.
- Colors: hand-rolled SGR emission under effective `pretty.color()`
  with a per-element palette approximating syntect's `ansi` theme
  (ANSI-16 slots; same quantization spirit as ADR-0035).
  `--style`: `auto`→ansi palette; `solarized`/`monokai`/`fruity` →
  per-theme ANSI-16 approximations of the same element classes.
  Fidelity bar documented: colored, element-correct, theme-selectable
  — not RGB-exact.

## Alternatives considered

- Format-only, keep colors degraded — fallback only; the element set
  is small enough that approximation is honest.
- Port syntect palettes exactly — rejected: palettes are compiled
  assets; extraction cost exceeds parity value.

## Consequences

- `sem_test` defer expectations for `--format-options` flip to
  exec-bound; golden fixtures regenerated at indent=4 / sorted heads.
- Deviation list gains: approximate palettes, bounded XML formatter,
  bounded charset-decode subset for `--response-charset` output.
