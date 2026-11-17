# 0014 — cli owns post-clap semantics; engine stays kind-generic

Status: accepted (2026-11-17, WI-0005 brainstorm)

Upstream `try_parse_from` does more than token matching: positional
method/URL resolution, request-item parsing, bin-name detection,
`process_relations` implications, per-option value parsers with their
own messages, and `construct_url`. WI-0005 puts ALL of that in `cli/`
as a semantic pass over `shared/args` Matches — the engine
(decisions 0004/0012/0013) stays app-agnostic and is not extended.

Consequences:

- Options whose clap value parsers carry xh-specific messages are
  declared KSTR (repeat where upstream repeats) and validated in cli
  post-parse: `timeout`, `print`, `history-print`, `format-options`,
  `proxy`, `resolve`, `unstable-m-sig-comp`, `verify`,
  `response-charset`. `--timeout` is NOT KFLOAT so cli can emit
  "Connection timeout is ..." verbatim. `--max-redirects` stays
  KUINT — the engine's `invalid digit found in string` already
  matches clap's usize error.
- Positional slots are exactly upstream's two: `murl` (required,
  `<[METHOD] URL>`) + `rest` (variadic, `[REQUEST_ITEM]...`). Missing
  URL, item errors, raw+body conflicts, and `Invalid <URL>` are
  cli-side clap-shaped diagnostics (exit 2) — pinned text in the spec.
- Post-loop value checks run in table-declaration order, not argv
  order (the engine exposes no per-token callback); races between two
  invalid values are a recorded deviation.
- Deferred behaviors degrade in cli per decision 0006 with
  corpus-pinned messages where they exist (m-sig, http3); everything
  else gets a uniform "unsupported in this build" error (exit 1)
  until request execution lands (S5+).
