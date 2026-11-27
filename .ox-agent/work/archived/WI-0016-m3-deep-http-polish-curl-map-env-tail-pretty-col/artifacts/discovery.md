# WI-0016 discovery — M3 deep HTTP polish

Pin: oxl **0.26.0**. Corpus: `docs/corpus/corpus-xh.md` sections 4.2/4.7/5/6/7.
Upstream source: partial clone at `/tmp/xh-src/` (src/*.rs @ 8b21cc0) plus
fetched `generation.rs`, `formatting/`, `doc/*-template.*`, `completions/`,
`doc/xh.1`, `doc/xh.1.md` from the pinned commit (all HTTP 200).
Parity rows this WI owns (matrix): 4.2 `next`, 4.7 `next`/`post`,
5 `next`, 7 `next`, 6 `post`.

## Verified upstream surfaces (read first-hand)

### 5. `--curl` map (`to_curl.rs`, 584 lines — full read)

Emit order is FIXED (translate()): ignored-warnings first, then
`-v`→`-v` | `-q`→`-s` | `--debug`→`--trace -` | `--stream`→`-N` |
`check_status==Some(true)`→`-f` | `--follow`→`-L` |
`max_redirects`(presence)→`--max-redirs N` | `-o`→`-o` else
`-d`→`-O` | `-c`→`-C -` | verify custom→`--cacert`/`no`→`-k` |
cert→`-E`, cert-key→`--key` | `--ssl tlsX.Y`→`--tlsvX.Y --tls-max X.Y`
(incl. 1.0/1.1) | proxies (all:→`-x`, http:/https:→env prefix) |
`--timeout`→`--max-time` | http-version flags | method
(HEAD→`-I`, OPTIONS→`-i -X OPTIONS`, `--headers`→`-I -X <m>`+warn,
other→`-X`, None→nothing) | URL+query items (`[ ] { }`→`-g`) |
`-4`/`-6` | `--interface` | `--unix-socket` | `--resolve h:port:a`
(+warn, port inferred from URL) | item headers (HttpHeader/FromFile;
unset→`-H 'k:'`; empty→`-H 'k;'`; names LOWERCASED via HeaderName) |
`--ignore-netrc`→`--no-netrc` | auth (`--basic -u`/`--digest -u`/
`--oauth2-bearer`) | payload (`--raw`+form→ct only else ct+accept+`-d`;
multipart→`-F 'k=v'`/`k=<f'`/`k=@f;type=;filename=`; form→
`--data-urlencode` name-encoded/empty-form→ct header only; Json→
ct+accept+`-d` compact-reserialized; bare --json→2 headers; File→
ct+`--data-binary @file`).

- Warnings print as bare `Warning: <msg>` (NO `xh: warning:` prefix),
  followed by a BLANK line when non-empty. Flag spellings:
  `-b/--body`, `-p/--print`, `-s/--style`, `-x/--compress`,
  `-P/--history-print`, `--unstable-m-sig-*`, `--response-charset`,
  `--response-mime`, `--all`, `--session`, `--native-tls`, `--offline`.
- follow+non-GET warns "Using a combination of -X/--request and
  -L/--location..."; `--headers`+non-GET warns
  "-I/--head is incompatible with sending data..."; resolve warns
  "Inferred port number in --resolve from request URL."
- Quoting = `os_display::Quotable::maybe_quote` (unix.rs read):
  quote iff empty OR first char is `~`, `#`, or `!` OR contains
  `|&;<>()$` backtick `"` `'` `*` `?` `[` `]` `=` `^` `{` `}` ` `
  OR unicode-ws/U+2800 OR zero-width-first;
  `'...'` preferred, `"..."` if contains `'`, `'\''` splice otherwise;
  ctrl/non-print → `$'...'` ANSI-C form.
- **Upstream test vectors embedded** in `to_curl.rs::tests` (~20
  input→expected pairs) — adopt as golden fixtures wholesale.

### 4.2 output pipeline (`printer.rs`, `headers_fmt.rs`, `buffer.rs`)

- `Printer::new`: `format_json = fo.json_format.or(pretty.format())`,
  `json_indent = fo.json_indent.or(4)` — **default indent 4** (ours 2);
  `format_xml`/`xml_indent(2)` same shape; `sort_headers =
  fo.headers_sort.or(pretty.format())` — **headers sort by default
  under all/format/colors**; `color = pretty.color()` (all|colors).
- Response body pipeline (`print_response_body`): content_type =
  `--response-mime ?: get_content_type` (substring map:
  json→Json, xml→Xml, html→Html, multipart, x-www-form-urlencoded,
  javascript→JS, css, event-stream→EventStream, text→Text);
  encoding = `--response-charset ?: charset= param ?: BOM/chardet`;
  decompress; stream = `--stream ?: EventStream`. **Non-TTY**: iff
  (color OR format_json OR format_xml) AND is_text → decode+format,
  else RAW bytes (binary flows freely — suppressor is TTY/format only).
  **TTY**: decode_blob (NUL in ASCII-compat enc → None →
  BINARY_SUPPRESSOR box — ours already byte-identical); stream →
  linewise decode, binary aborts w/ suppressor.
- `print_body_text` dispatch: Json→validate+indent-format;
  Xml→format_xml; Html/Css/Js→syntax only (colors); Text|JS w/
  valid_json→JSON path; rest → verbatim.
- `valid_json` = full `IgnoredAny` parse (not just leading `{`/`[`).
- Headers: `sort_by_key(name.as_str())`; titlecase only for
  HTTP/1.x (h2/h3 lowercase — ours always titlecases, deviation);
  non-ASCII value → latin1 display (sanitized on tty, error-color)
  + ` (UTF-8: <text>)` annotation when also valid UTF-8
  (hyperlink-elided offline).
- Request body print: NUL check is UNCONDITIONAL (suppressor even
  piped); response side is TTY-gated.
- `-m` meta = `Elapsed time: %.5fs\nRemote address: "<ip:port>"`.
- syntect colors: scope-palette per element (method=keyword.control,
  path=const.language, version/status=constant.numeric,
  reason=keyword.reason, hname=support.variable, colon=punct.sep,
  hval=string.other, error=error). Theme::Auto→syntect "ansi" theme.
  Exact palette = approximation slice (see brainstorm).

### 4.7/6 generate (`generation.rs` + templates)

- `run()` calls `generation::generate(&args.bin_name, kind)` BEFORE
  curl/request; conflicts with positional (already declared).
- completions = `clap_complete::generate(shell, app, bin_name)` —
  **prebuilt files vendored upstream** at `completions/{_xh,xh.bash,
  xh.elv,xh.fish,xh.nu,_xh.ps1}`; fish adds a `__{bin}_complete_data`
  preamble. Vendor + bin_name substitution = faithful.
- man = MAN_TEMPLATE.roff + `{{date}}` (SOURCE_DATE_EPOCH ?: now UTC,
  `YYYY-MM-DD`) + `{{version}}` + generated request_items/options
  roff; **prebuilt `doc/xh.1`** is the same artifact.
- man-markdown = MD_TEMPLATE + generated items; **prebuilt
  `doc/xh.1.md`** matches.
- Man ignores bin_name entirely; completions substitute it.

### 7. env tail (`main.rs`, `netrc.rs`, `cli.rs`)

- `verify` env fallback: `REQUESTS_CA_BUNDLE ?: CURL_CA_BUNDLE` only
  when `--verify` absent — args.env already does this exactly.
  `--native-tls`+custom bundle warns "Custom CA bundles with
  native-tls are broken" (N/A: single stack, W3 covers).
- netrc (`netrc.rs` full read) — parser is LINE-WORD hybrid with a
  real default-entry model ours lacks:
  - `default` collects a fallback Entry used only when no host entry
    completes AND `suppress_default==false` (set by ANY
    `machine <host>` match, even incomplete -> incomplete entry blocks
    the default for that host: INCOMPLETE_AND_DEFAULT).
  - Unknown word → `finish_entry()` (entry terminates; ours ignores
    unknown words → leaks the entry).
  - `#` word → skip rest of LINE only when at word position; arg
    position `#...` is a VALUE (OCTOTHORPE_IN_VALUE: login `#!@$`).
    Ours strips `#`→EOL in the tokenizer → eats values.
  - `macdef` → finish entry + skip to next BLANK line (ours skips one
    word only).
  - `machine` host match via `url::Host::parse` — IDNA
    (`É.com`==`xn--9ca.com`) + IPv4 int forms (`16843009`==`1.1.1.1`).
    Ours string-compares.
  - `login.or(account)` — login preferred, account fallback (ours ok).
  - Decode: UTF-16 BOM + lossy UTF-8 (ours raw bytes — minor).
  - `~/.netrc` then `~/_netrc` via get_home_dir ok; `$NETRC` ok.
- `RUST_LOG`/`RUST_BACKTRACE`: env_logger only — we have no logger;
  stays inert, document.
- `XH_HTTPIE_COMPAT_MODE`: upstream `var_os().is_some()` counts EMPTY;
  `os.getenv` can't distinguish → keep documented deviation.
- `XH_TEST_DIGEST_AUTH_CNONCE`: read in exec via `env_get` but absent
  from `envnames()` → **dead in real runs**; tests inject envpairs
  directly so it works there. Add to envnames.
- Env-proxy: capture order HTTP_PROXY,HTTPS_PROXY,ALL_PROXY,lower...
  → pick_proxy first-match-per-scheme = UPPERCASE wins for https/all.
  WI-0013 spec lists uppercase-first; std client wants lowercase-first
  for https/all — spec is the pin, leave as-is absent upstream evidence.
- Loopback env-proxy carve-out: deliberately rejected (reqwest parity,
  test-pinned at h1_test.oxl:678).

## Current code touchpoints

- `cli/spec.oxl`: full 58-opt table + `--generate` enum + conflicts;
  `args.env(verify,REQUESTS_CA_BUNDLE,CURL_CA_BUNDLE)`.
- `cli/sem.oxl`: resolves everything incl. `fmt_opts` merged list,
  `response_charset` (WHATWG-canonicalized), `proxies/proxy_env/
  no_proxy`. Section 10 routing: `--generate` defers exit-1; `--curl`
  short-circuits BEFORE h3/resolve/interface/ipv6/unix/fmtopts defers
  (so curl must EMIT those flags, not defer).
- `cli/exec.oxl`: `plan()` builds `model.Req` (+synth/jar/sess/digest);
  `curl_emit` (proxies env-prefix + ambient-clearing D7, follow,
  httpver flags, cert/key, ssl, -C/-o, `-X` non-GET, ALL plan headers
  as `-H`, `-d` body, URL last) + `curl_ignored` (offline/session/
  print/pretty/download/resolve/compress/native-tls — **two wrong**:
  download maps `-O`, resolve maps `--resolve`; spellings need
  `-b/--body` style; missing body/style/msig/charset/mime/all/
  history-print entries).
- `body_render`: NUL→suppressor always (response side should be
  TTY-gated); `json_pretty2` = 2-space, any `{`/`[` body (needs
  indent param + content-type gating + valid_json check).
- `req_head_render`/`resp_head_render`/`htitle`: no sort, always
  titlecase, no latin1/UTF-8 annotation, no colors.
- `cli/main.oxl`: envnames (add XH_TEST_DIGEST_AUTH_CNONCE);
  `guess_pretty` matches upstream incl. TERM-unset→format.
- `core/http/h1.oxl`: proxies/proxy_env/no_proxy → pick_proxy per
  hop; verify path→PEM roots; decode_body handles gzip/deflate.
- Golden harness `cli/golden_test.oxl` + `tests/golden/cases` —
  g_load parses argv/stdin/files/script only; `env:` lines are
  IGNORED by the harness (golden-gen.sh reads them). Test-side env
  support needs adding for env-var cases.
- Fixtures `tests/golden/fixtures/curl-*`: **derived, not captured** —
  embed `<AE>`/`<CONN>` normalizer tokens and OUR emit shape
  (URL-last, all-headers). Regenerate from upstream test vectors +
  corpus (mark provenance per ADR-0021).

## oxl feasibility notes

- `std/compress` is READ-ONLY (gzip/zlib/flate decompressors) —
  `--compress` (request deflate) stays warn-degraded.
- No syntect/highlighter in std — colors must be hand-rolled ANSI;
  exact syntect palette is unrepresentable → approximation + doc.
- `std/encoding/json` exists (jparse/jadd/jobj/jstr) — valid_json =
  `jparse` success check on body text.
- Charset decode: UTF-16LE/BE + windows-1252 tables hand-rollable;
  chardet/40-encoding coverage infeasible → bounded decode subset +
  degrade policy.
- `--generate` assets: fetch vendored bytes at pin → embed as oxl
  string literals (no embed mechanism; a `gen_assets.oxl` generated
  by a repo script keeps single-binary). Man date = today-or-SDE
  patch on `.TH` line; version = ours.
- Sort: check `std/sort`/`std/slices` API at spec time; else
  insertion sort is ~15 lines.

## Risks / watch-items

- `p.digest_pass`-style lines read fine on disk — the `***` seen in
  file views is display masking; never edit them via string replace.
- WI-0013 curl fixtures will be REPLACED by corpus-faithful ones —
  review F-series pins (`curl-proxy` D7 ambient-clearing) must be
  preserved inside the new emit order.
- Upstream `headers()` for curl uses ITEM headers only (HeaderName-
  lowercased), NOT the synthesized plan set — biggest visual diff vs
  current emit; also `-d` for form/multipart/json bodies replaced by
  `--data-urlencode`/`-F`/compact-JSON paths.
- `xrun` in exec_test passes stdin_tty=1 always; golden harness
  passes 0 — pretty/bracketed-paste gating tests must pick the right
  runner per fixture.
