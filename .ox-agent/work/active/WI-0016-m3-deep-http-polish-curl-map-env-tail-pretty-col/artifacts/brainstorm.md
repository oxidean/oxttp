# WI-0016 brainstorm — M3 deep HTTP polish

Discovery: `artifacts/discovery.md` (upstream read first-hand @8b21cc0).
Everything in scope is feasible on pinned oxl 0.26.0 except request-side
`--compress` (std/compress is decode-only — stays warn-degraded, already
documented). The real questions are fidelity-vs-effort tradeoffs on four
independent workstreams plus harness plumbing.

## Q1 — `--curl`: rewrite against upstream `translate()` or patch?

Current `curl_emit` diverges structurally: it prints ALL synthesized plan
headers (UA/Accept-Encoding/Accept/Connection), puts the URL last, uses
`-d` for every body kind, and misclassifies `--download`/`--resolve` as
ignored. Upstream emits item-only headers (lowercased via HeaderName),
URL before headers, and per-kind payload emitters.

- **A. Faithful rewrite** (recommended). Reorder to upstream's fixed
  translate() order: bare `Warning:` lines + blank separator →
  flag-mappings in upstream order → URL(+query items, `-g` on glob
  chars) → `-4`/`-6`/`--interface`/`--unix-socket`/`--resolve` →
  item headers → `--no-netrc` → auth → payload. `Intent` already
  carries everything: `items`+`ikinds` (re-derive per-item header ops
  incl. unsets/FromFile/empty-`;`), `resolves`, `interface`,
  `unix_socket`, `ipv4/6`, `fmt_opts`, `stream`, `debug`,
  `ignore_netrc`, auth, verify/cert/ssl, proxies. Routing already
  short-circuits `--curl` before the resolve/interface/unix/ipv6
  defers — those become EMITTED flags, not errors. `--download` maps
  `-O` and upstream's `-d` implies `-f -L -O` via the existing
  download→follow+check_status rule (sem L1165). Payload emitters:
  form→`--data-urlencode 'k=v'` (name pre-encoded; empty form → ct
  header only), multipart→`-F 'k=v'/'k=<f'/'k=@f;type=T;filename=F'`,
  json→ct+accept+`-d` compact-reserialized, raw→ct(+accept)+`-d`,
  file→ct+`--data-binary @file`. Quoting: port
  `os_display::Quotable::maybe_quote` unix path (special-char set,
  `'…'`→`"…"`→`'\''` splice→`$'…'` ANSI-C for ctrl bytes).
  `curl_ignored` rewritten verbatim per corpus L253 spellings
  (`-b/--body`, `-p/--print`, `-s/--style`, `-x/--compress`,
  `--pretty`, `--unstable-m-sig-*`, `--response-charset`,
  `--response-mime`, `--all`, `-P/--history-print`, `--session`,
  `--native-tls`, `--offline`) + silent-ignored set
  (`--ignore-stdin`, `--curl`, `--curl-long`). Adopt the 23 upstream
  test vectors (to_curl.rs::tests, incl. the `xhs` bin-name case)
  as golden fixtures.
- **B. Incremental patch.** Rejected: order, header sourcing, and
  payload emit all differ — patching produces a third emit dialect
  that matches neither upstream nor the old fixtures.
- Keep: the `all:`→`all_proxy=` env-prefix deviation (corpus L226
  pins it deliberately) and D7 ambient-clearing (`no_proxy= NO_PROXY=`
  when explicit proxies present — WI-0013 review F-pin).

**Recommendation: A.**

## Q2 — `--pretty`/`--format-options`/colors: how faithful?

sem already parses+validates `--format-options` into `fmt_opts` with
upstream-exact diagnostics (sem_test L175–186) then defers at routing.
Upstream defaults that differ from ours: `json.indent=4` (ours 2),
`sort_headers = fo.headers_sort or pretty.format()` (ours never sorts),
titlecase only for HTTP/1.x heads (ours always), response binary
suppressor TTY-gated (ours unconditional), `valid_json` = full parse
(ours first-char `{`/`[`), content-type dispatch incl. event-stream
auto-stream, latin1 header display + ` (UTF-8: <text>)` annotation.

- **A. Format pipeline port + hand-rolled ANSI colors** (recommended).
  Un-defer `--format-options` (delete the routing defer; plumb
  effective values through a small `FmtOpts` struct built in sem or
  exec). json_pretty2 → indent param (default 4), call only under
  Json content-type+valid_json (jparse) or pretty.format() on text/
  types per upstream dispatch; XML formatting bounded (indent-only
  pretty-printer — upstream uses quick_xml; approximation documented).
  Header render: sort by lowercase name when effective, titlecase
  h1-only, latin1+UTF-8 annotation. Response NUL guard → tty-only;
  request-side stays unconditional (upstream asymmetry — keep).
  Stream flag + event-stream → skip format/binary-check (raw passthru
  — linewise decode only if cheap; else raw, documented).
  Colors: hand-rolled SGR table — syntect "ansi" theme maps each
  scope to a 16-color slot; approximate per element class
  (method/path/version/status/reason/hname/colon/hval/error +
  JSON punct/string/number/bool/null/key). `--style`: `auto`→ansi
  palette; solarized/monokai/fruity → per-theme approximations of the
  same element classes. Palette is inherently approximate (upstream
  embeds binary .tmTheme via syntect) — spec documents the table,
  corpus fidelity = "colored, sensible, theme-selectable" not exact
  RGB. Apply colors only under effective `color=true` (all|colors),
  tty per guess_pretty; `--pretty=colors` = colors without
  format/sort.
- **B. Format-only; keep colors warn-degraded.** Fallback if the
  palette surface balloons — but the element set is ~13 classes and
  SGR is trivial; A is achievable.
- **C. Port syntect palette exactly.** Rejected: .tmTheme assets are
  compiled into syntect upstream; extraction cost >> parity value.

**Recommendation: A.**

## Q3 — `--generate`: vendor prebuilt artifacts or park?

Corpus marks §4.7 `post`, but discovery showed upstream's generated
outputs are themselves vendored files fetchable at the pinned commit —
the cost asymmetry favors landing now.

- **A. Vendor + patch at emit time** (recommended). Fetch
  `completions/{_xh,xh.bash,xh.elv,xh.fish,xh.nu,_xh.ps1}`,
  `doc/xh.1`, `doc/xh.1.md` @8b21cc0 (all verified 200). A repo
  script (`scripts/gen-assets.sh`) regenerates `cli/gen_assets.oxl`
  with the bytes as string literals — keeps single-binary, no
  embed mechanism needed. At emit: completions substitute the
  command word with `i.prog`-derived bin name (upstream passes
  `args.bin_name` to clap_complete → the registered command name);
  man substitutes `.TH` title date (SOURCE_DATE_EPOCH ?: today
  YYYY-MM-DD — upstream format) and `\fIversion\fR` line with our
  version; man ignores bin_name upstream — same here. Un-defer
  routing: `--generate` conflicts with positional (already declared
  in spec.oxl) → exec writes to stdout, exit 0. Provenance header in
  gen_assets.oxl: `upstream-vendored @8b21cc0` (ADR-0021 analog).
  Golden cases: one fixture per kind with normalized date.
- **B. Park** (keep exit-1 defer). Defensible per corpus `post`, but
  leaves a visible gap when vendoring is this cheap.
- **C. Port clap_complete + man generation.** Rejected: ~500 lines
  of clap internals to regenerate bytes already vendored upstream;
  no differential oracle without clap.

**Recommendation: A.**

## Q4 — netrc: port the EntryState machine or patch?

Upstream `netrc.rs` semantics ours lacks: `default` fallback entry
suppressed by ANY host match (incl. incomplete →
INCOMPLETE_AND_DEFAULT), unknown word terminates the entry, `#` is a
comment only at word position (else literal value — OCTOTHORPE_IN_VALUE),
`macdef` skips to next blank line, host match via `url::Host`
(IDNA + IPv4-int forms).

- **A. Port the machine** (recommended). ~150 lines oxl: per-line
  word scanner (preserve `#` handling by position), EntryState
  {Wrong,Correct,Default}, finish_entry on unknown word/`machine`/
  `default`/`macdef`, suppress_default flag, `login.or(account)`.
  Host normalization bounded: casefold + trailing-dot strip +
  IPv4-int expansion (dotted/int forms); IDNA/punycode has no std
  codec → documented deviation (host entries stay literal).
  UTF-16-BOM + lossy-UTF8 decode of the file — cheap, port it.
  File order: `$NETRC` → `~/.netrc` → `~/_netrc` (already right).
- **B. Patch the current line-parser.** Rejected: five interacting
  semantics bolted onto a different tokenization model — the state
  machine is the cheaper faithful path.

**Recommendation: A.**

## Q5 — env tail: what actually changes?

Verified in discovery: `REQUESTS_CA_BUNDLE`/`CURL_CA_BUNDLE` wiring is
already exact (`args.env` chain); `REQUEST_METHOD` CGI guard on
HTTP_PROXY already present (sem L1262); NO_PROXY matching in
`pick_proxy` done (WI-0013); proxy env order is spec-pinned (keep).

- envnames += `XH_TEST_DIGEST_AUTH_CNONCE` — read via env_get in
  exec but absent from the env list → dead in real runs today.
- `RUST_LOG`/`RUST_BACKTRACE`: inert — we have no logger; document
  in spec (corpus-faithful: only affects log output we don't produce).
- `XH_HTTPIE_COMPAT_MODE` empty-string: upstream `var_os().is_some()`
  counts it; `os.getenv` can't distinguish unset→keep documented
  deviation (already recorded).
- `--debug` + `RUST_BACKTRACE` interplay: N/A (no backtraces).

## Q6 — harness + fixture work

- `g_load` ignores `env:` case lines today (golden-gen.sh consumes
  them for real-xh capture only). Add env merge → envpairs so
  NO_PROXY/proxy-env/NO_COLOR/TERM cases are exercisable in-test.
- Regenerate `curl-*` fixtures against the new emit — they were
  derived fixtures; after the rewrite they must reflect upstream
  vectors (mark provenance `# source: upstream-test-vector` in case
  headers per ADR-0021's provenance rule; the 23 to_curl.rs vectors
  become cases wholesale, adapted to our `<V>`-style normalizer where
  needed).
- `xrun` passes stdin_tty=1, golden passes 0 — pretty-gating fixtures
  (binary suppressor TTY-gated) must go through the right runner.

## Consensus summary (feeds specify)

1. `--curl`: faithful rewrite per Q1-A — upstream order, item-only
   lowercased headers, per-kind payload emitters, os_display quoting,
   verbatim ignored-list, -O/--resolve un-deferred; keep all_proxy
   deviation + D7 clearing; adopt 23 upstream vectors as fixtures.
2. Pretty: format pipeline port per Q2-A — fmt-opts un-deferred,
   indent 4 default, sorted headers under format, h1-only titlecase,
   UTF-8 annotation, valid_json gating, TTY-gated suppressor,
   event-stream auto-stream; colors = hand-rolled SGR approximation,
   `--style` theme table (documented approximation).
3. `--generate`: vendor upstream artifacts + emit-time substitution
   per Q3-A (gen_assets.oxl generated by script; SDE date; our
   version; completions bin-name sub).
4. netrc: port EntryState machine per Q4-A; IDNA bounded deviation.
5. Env: XH_TEST_DIGEST_AUTH_CNONCE → envnames; rest documented-inert.
6. Harness: `env:` merge in g_load; curl fixtures re-derived with
   provenance markers; binary-suppressor fixtures on tty runner.
7. ADR candidates (0039+): curl-emit rewrite + deviations; color
   approximation policy; generate-vendoring; netrc state-machine
   port + IDNA bound. Ship-stage findings: os.getenv empty/unset;
   std/compress decode-only (already on file).
