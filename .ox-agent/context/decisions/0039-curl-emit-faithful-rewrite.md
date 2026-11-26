# ADR-0039 — `--curl` emit: faithful rewrite against upstream `translate()`

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0016 (brainstorming)
- Supersedes: the WI-0013 first-pass emit (URL-last, plan-header set)

## Context

WI-0013 shipped `--curl` as a best-effort mapping: proxies as env
prefixes, a fixed flag subset, *all* synthesized plan headers as `-H`
(UA/Accept-Encoding/Accept/Connection included), `-d` for every body
kind, and the URL last. First-hand reading of `to_curl.rs` @8b21cc0
shows the real contract is a fixed-order translation with materially
different semantics:

- headers come from `RequestItems::headers()` — **item headers only**,
  names lowercased via `HeaderName`, unsets → `-H 'k:'`, empties →
  `-H 'k;'`, `key:@file` reads the file;
- the URL (with query items baked in) is emitted **before** headers,
  after the flag block;
- payload emits per body kind: form → `--data-urlencode`, multipart →
  `-F`, JSON → `-H content-type` + `-H accept` + compact `-d`,
  `@file` body → `--data-binary @file`, `--raw` → `-d` (+ct/accept);
- `--download` maps `-O` (and implies `-f -L` upstream via
  download→follow+check_status — our sem already mirrors this);
  `--resolve`/`--interface`/`--unix-socket`/`-4`/`-6` map to flags,
  not ignores;
- warnings print as bare `Warning: <msg>` (no `xh: warning:` prefix)
  + a blank separator line; ignored list uses `-b/--body`-style
  spellings; `os_display::Quotable` quoting incl. `$'…'` ANSI-C form.

## Decision

Rewrite `curl_emit`/`curl_ignored` to mirror `translate()`'s order
verbatim: ignored-warning block (blank line after) → flag mappings in
upstream sequence → URL(+query, `-g` when `[ ] { }` present) →
`-4`/`-6`/`--interface`/`--unix-socket`/`--resolve` (port inferred,
warning) → item headers → `--no-netrc` → auth → payload emitter.
The `--curl` routing short-circuit stays ahead of the
resolve/interface/unix/ipv6 defers so those resolve cleanly into the
emit. Shell-quoting ports `maybe_quote`'s unix rule set. The 23
upstream `to_curl.rs::tests` vectors become golden fixtures.

Kept deviations (documented): `all:`→`all_proxy=` env prefix (corpus
§5 L226 pins it — `-x` would shadow scheme envs) and the D7 ambient
`no_proxy= NO_PROXY=` clearing when explicit proxies are present.

## Alternatives considered

- Incremental patch — rejected: order, header sourcing, and payload
  emit all differ; patching yields a third dialect.
- Keep first-pass emit + document — rejected: corpus §5 is a `next`
  row; the fixture set upstream ships makes fidelity cheap to verify.

## Consequences

- `curl-*` fixtures are re-derived from upstream vectors with
  provenance markers (ADR-0021); `<AE>`/`<CONN>` normalizer tokens
  disappear from curl fixtures (item-only headers emit neither).
- Spec owns the full emit-order table + quoting ruleset.
