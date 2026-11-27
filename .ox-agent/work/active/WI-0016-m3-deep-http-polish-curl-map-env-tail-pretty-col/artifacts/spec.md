# WI-0016 spec — M3 deep HTTP polish

Direction locked by `artifacts/brainstorm.md` + ADR-0039/0040/0041/0042.
Corpus: `docs/corpus/corpus-xh.md` §4.2/§4.7/§5/§6/§7. All upstream
details verified first-hand in `artifacts/discovery.md` against
ducaale/xh @8b21cc0 (v0.26.3 source: `to_curl.rs`, `printer.rs`,
`formatting/{mod,headers,palette}.rs`, `netrc.rs`, `cli.rs`).

## S1 — `--curl` emit rewrite (ADR-0039)

Rewrite `curl_emit`/`curl_ignored` in `cli/exec.oxl` to mirror
`translate()` (`to_curl.rs`) verbatim. Emit order is FIXED:

1. **Warnings block** (stderr, bare `Warning: <msg>` lines — NO
   `xh: warning:` prefix — then one blank line iff any warning).
   Upstream emit order (translate() runs these in sequence):
   a. Ignored-flag warnings FIRST, in the ignored-table order —
      `--offline`, `-b/--body`, `-p/--print`, `--pretty`,
      `-s/--style`, `--unstable-m-sig-id`, `--unstable-m-sig-key`,
      `--unstable-m-sig-alg`, `--unstable-m-sig-comp`,
      `-x/--compress`, `--response-charset`, `--response-mime`,
      `--all`, `-P/--history-print`, `--session`, `--native-tls`
      → each `Warning: Ignored <flag>`.
      Silently ignored: `--ignore-stdin`, `--curl`, `--curl-long`.
   b. `follow && explicit method not in {GET,unset}` →
      `Using a combination of -X/--request and -L/--location which may cause unintended side effects.`
      (explicit args.method only — an implicit POST from data does
      NOT warn)
   c. `--headers` with effective non-GET method →
      `-I/--head is incompatible with sending data. Consider omitting -h/--headers.`
   d. any `--resolve` → `Inferred port number in --resolve from request URL.`
      (once, emitted when the resolve block runs).
2. **Flag block** in exact upstream sequence (short/long per
   `--curl-long`; `opt()` picks one):
   `verbose>0`→`-v/--verbose` · `quiet>0`→`-s/--silent` ·
   `debug`→`--trace -` (literal, no short form) ·
   `stream`→`-N/--no-buffer` · `check_status==on`→`-f/--fail` ·
   `follow`→`-L/--location` · `max_redirects` present→`--max-redirs N` ·
   `output`→`-o/--output FILE` else `download`→`-O/--remote-name` ·
   `resume`→`-C/--continue-at -` · `verify=<path>`→`--cacert P` ·
   `verify=no`→`-k/--insecure` · `cert`→`-E/--cert F` ·
   `cert_key`→`--key F` · `ssl`: tls1→`--tlsv1.0 --tls-max 1.0`,
   tls1.1→`--tlsv1.1 --tls-max 1.1`, tls1.2→`--tlsv1.2 --tls-max 1.2`,
   tls1.3→`--tlsv1.3 --tls-max 1.3`, auto/ssl2.3→none ·
   proxies (see env block) · `has_timeout`→`--max-time <secs-f64>` ·
   `http_version`: 1.0→`--http1.0`, 1/1.1→`--http1.1`, 2→`--http2`,
   2-prior→`--http2-prior-knowledge`, 3-prior→`--http3-only` ·
   method: HEAD→`-I/--head`; OPTIONS→`-i/--include -X/--request OPTIONS`;
   `--headers`→`-I/--head -X/--request <eff-method>` (+warn 1c if
   non-GET); explicit other→`-X/--request M`; implicit→nothing.
3. **URL** = url_with_query (url-param items baked in — existing
   helper); URL containing any of `[ ] { }` → prepend
   `-g/--globoff` BEFORE the URL arg.
4. `-4/--ipv4` / `-6/--ipv6` (both-set → neither — spec conflicts
   make that unreachable anyway) · `--interface X` ·
   `--unix-socket P` · per `--resolve h:a` → `--resolve h:<port>:a`
   (port from URL: explicit port else 443 https / 80 http;
   warn 1d once).
5. **Item headers** — from `Intent.items`+`ikinds` ONLY (never the
   synthesized plan set): HttpHeader→`-H/--header 'name: value'`
   with name **lowercased** (HeaderName semantics — strip nothing
   else); `FromFile`→read file, trim, same emit (missing file →
   error, upstream propagates); empty value→`-H 'name;'`;
   ToUnset→`-H 'name:'` (also lowercased); last-write-wins per
   name: a later HttpHeader cancels a pending unset of the same name
   (upstream `headers_to_unset.remove(&key)` on insert); unsets emit
   after all headers, in encounter order.
6. `--ignore-netrc`→`--no-netrc`.
7. Auth: basic→`--basic -u/--user 'u:p'`; digest→`--digest -u 'u:p'`;
   bearer→`--oauth2-bearer tok`. (Session/netrc-sourced auth does NOT
   emit — upstream emits only `args.auth`.)
8. **Payload** by body kind:
   - `--raw` set: form mode → `-H 'content-type: application/x-www-form-urlencoded'`
     only; else `-H 'content-type: application/json' -H 'accept: application/json, */*;q=0.5'`;
     then `-d/--data RAW`.
   - multipart items: per item — DataField→`-F/--form 'k=v'`;
     DataFieldFromFile→`-F 'k=<file'`; FormFile→`-F 'k=@file'`
     (+`;type=T` then `;filename=F` when set); JsonField*→
     **hard error** `JSON values are not supported in multipart fields`
     (exit 1, upstream anyhow text verbatim).
   - form body: empty → `-H 'content-type: application/x-www-form-urlencoded'`;
     per field → `--data-urlencode 'k=v'` where `k` is
     urlencoded-with-trailing-`=` (`serde_urlencoded (k,"")` →
     `name%3D=`), value appended RAW.
   - JSON body non-null → ct+accept headers + `-d '<compact>'`
     (insertion order preserved — upstream uses preserve_order; our
     jobj matches); null body + explicit `--json` → the two headers
     only; null + no --json → nothing.
   - `@file` body → `-H 'content-type: <detected|application/json>'`
     + `--data-binary @file`.
9. **Env prefixes** for proxies (before `curl`, display
   `NAME=<quoted> `): `http:`→`http_proxy=`, `https:`→`https_proxy=`.
   **DevD1 (kept, corpus §5 L226):** `all:`→`all_proxy=` (upstream
   `-x` — would shadow scheme envs).
   **DevD2 (kept, ADR-0021-era D7):** when ≥1 explicit `--proxy`
   present, also emit clearing `no_proxy= NO_PROXY=` so the emitted
   curl can't bypass a proxy oxttp itself would use. (Existing emit
   clears `no_proxy= NO_PROXY=` plus the unset scheme vars
   `http_proxy= HTTP_PROXY=` `https_proxy= HTTPS_PROXY=`
   `all_proxy= ALL_PROXY=` — the WI-0013 D7 documented deviation;
   upstream emits none. Keep the documented clearing as-is; do NOT
   expand it further.)
10. **Quoting** = `os_display::Quotable::maybe_quote` unix rules:
    quote iff value is empty ∨ first byte ∈ {`~`,`#`,`!`} ∨ contains
    any of `|&;<>()$` backtick `"` `'` `*` `?` `[` `]` `=` `^` `{` `}`
    space/tab ∨ unicode-whitespace ∨ U+2800 ∨ leading zero-width
    char. Form: `'…'`; if contains `'` → `"…"`; if contains `'"`
    both → `'…'\''…'` splice; ctrl/non-printable bytes →
    `$'…'` ANSI-C escapes (`\n`→`\\n`, `\x00`→`\\0`, etc.). URL,
    flag args, header args, env values all pass through it.

Errors: header-value/file-read failures and the multipart-JSON error
propagate as app errors (exit 1) — `translate() -> Result` shape.

Sem touchpoints: the `--curl` short-circuit already precedes the
resolve/interface/unix/ipv6/h3 defers — keep. `Intent` already
captures every needed field. No new sem work beyond ensuring
`resolves`/`interface`/`unix_socket`/`ipv4`/`ipv6`/`fmt_opts` are
populated (they are) and that `--generate` un-defers (S5).

## S2 — `--format-options` un-defer (ADR-0040)

sem already parses+validates into `intent.fmt_opts` with
upstream-exact diagnostics (sem_test L175–186 pins them — keep tests,
flip expectations from defer to exec). Delete the routing defer.
New `cli/fmt.oxl` (or exec-internal) `FmtOpts`:

```
json_indent  = last(fmt_opts["json.indent"])  or 4
json_format  = last(fmt_opts["json.format"])  or pretty.format()
xml_indent   = last(fmt_opts["xml.indent"])   or 2
xml_format   = last(fmt_opts["xml.format"])   or pretty.format()
headers_sort = last(fmt_opts["headers.sort"]) or pretty.format()
```

`pretty` resolves via existing `guess_pretty` (env-correct) +
`--pretty` override + `--no-pretty`. `--pretty=none` → all five off.

## S3 — pretty/format pipeline (ADR-0040)

Response body (`print_response_body` analog, in exec/body_render):

```
ct      = --response-mime ?: content-type header  → ContentType
          (substring map json|xml|html|multipart|x-www-form-urlencoded|
           javascript|css|event-stream|text → else Unknown)
enc     = --response-charset ?: charset= param ?: BOM sniff
body    = already-decoded (decode_body gzip/deflate upstream of us)
stream  = --stream ?: (ct == EventStream)

buffer NOT tty:
  (color || json_format || xml_format) && ct.is_text():
     stream → linewise-decode stream path
     else   → decode (BOM-strip, bounded charset) → print_body_text
  stream → raw copy
  else   → RAW BYTES (binary flows freely — suppressor does NOT apply)
buffer tty:
  stream → linewise decode; NUL-in-decoded-or-raw → BINARY_SUPPRESSOR
  else   → NUL check per S3-binary rules → suppressor | print_body_text + "\n"
```

`ct.is_text()` = Json|Html|Xml|JavaScript|Css|Text|EventStream
(NOT Unknown|UrlencodedForm|Multipart — upstream is_text() table).

`print_body_text` dispatch (upstream L231–245 verbatim):
- Json → format+indent if json_format (valid_json full-parse gate —
  invalid → syntax-color only); syntax "json" coloring when color.
- Xml → xml_format ? bounded re-indent (xml_indent, strip ws-only
  text nodes; malformed → fall back raw) : syntax "xml".
- Html/Css → syntax only (colors).
- Text|JavaScript → valid_json ? JSON path (no re-check) : JS →
  syntax "js"; Text → verbatim.
- Multipart|UrlencodedForm|Unknown → verbatim.

Binary rules: ascii-compatible encodings (utf-8, w1252, us-ascii —
everything in our decode set except UTF-16) → raw NUL ⇒ binary.
UTF-16* → decode then check for U+0000 (padding NULs legal).
Bounded decode set: `utf-8` (lossy), `utf-16le`, `utf-16be`,
`windows-1252`(+latin1/us-ascii aliases — WHATWG labels already
canonicalized in sem), UTF-8/16 BOM sniff+strip. Other valid labels
→ decode as UTF-8-lossy, **documented** (no chardet).

Request body (print path): unchanged UNCONDITIONAL NUL → suppressor
(upstream asymmetry — corpus §4.2 binary-guard row).

Heads (`req_head_render`/`resp_head_render`):
- sort headers by lowercase name when `headers_sort` effective —
  req and resp, verbose + normal paths.
- titlecase ONLY when version is HTTP/1.x (h1 `Resp.version` + h1
  request heads); `2.0`/`3` → lowercase names as sent.
- non-ASCII header value bytes → latin1 display; if also valid
  UTF-8 → append ` (UTF-8: <decoded>)`.
- reason phrase: upstream canonical-table fallback +
  `<unknown status code>` (verify ours matches — keep if already).

## S4 — colors + `--style` (ADR-0040, upgraded to exact palettes)

Upstream palettes ARE recoverable: `assets/themes/*.tmTheme` are
vendored upstream (fetched — all four parse, every color uses the
`#RR000000` palette-index encoding). `scripts/gen-assets.sh`
(S5) ALSO emits `gen_styles.oxl` — per theme, resolved style for a
fixed scope-stack list (the palette!{} element map, computed by
applying theme rules in document order with syntect prefix-match
semantics):

```
http_keyword   [keyword.other.http]
http_separator [punctuation.separator.http]
http_version   [constant.numeric.http]
method         [keyword.control.http]
path           [const.language.http]
status_code    [constant.numeric.http]
status_reason  [keyword.reason.http]
header_name    [source.http http.requestheaders support.variable.http]
header_colon   [source.http http.requestheaders punctuation.separator.http]
header_value   [source.http http.requestheaders string.other.http]
error          [error]
json_key       [keyword.other.name.jsonkv]
json_string    [string.quoted …]
json_number    [constant.numeric …]
json_constant  [constant.language …]     (true/false/null)
markup_tag     [entity.name.tag]         (html/xml)
markup_attr    [entity.other.attribute-name]
comment        [comment]
default        theme foreground
```

Runtime `convert_color` port: `a==0` → `r` is palette index:
0–6 → SGR 30–36 fg (Black..Cyan); 7 → UNCOLORED (xh quirk);
else → `38;5;<n>`. `a!=0` → `38;2;r;g;b`. fontStyle →
bold(1)/underline(4)/italic(3). Application order per
`headers_fmt.rs`: each element's color set before its text, plain
text via reset-spec, `reset` at end of head. Body highlighting:
hand-rolled lexers per syntax (json: strings/keys/numbers/
true-false-null/punct; xml/html: tags/attrs/strings/comments;
css/js: bounded token classes) — grammar coverage is the documented
approximation (palette values are exact, tokenization is ours).
`--pretty=colors` → colors only (no format/sort); `all` → both.
`--style auto`→`ansi` table; solarized/monokai/fruity → their
tables.

## S5 — `--generate` (ADR-0041)

`scripts/gen-assets.sh` (new) fetches pinned artifacts and emits
`cli/gen_assets.oxl` (string literals, provenance header
`upstream-vendored @8b21cc0` + URLs): `completions/{_xh,xh.bash,
xh.elv,xh.fish,xh.nu,_xh.ps1}`, `doc/xh.1`, `doc/xh.1.md`, plus the
`assets/themes/*.tmTheme` files consumed by the style-extraction
pass (S4 — same script run).

sem: delete the `--generate` defer (conflict-with-positional already
declared). exec: `--generate <kind>` → emit to stdout, exit 0:

- completions → vendored file with the registered command name
  substituted: occurrences of the `xh` command token → resolved
  `i.prog` bin name (upstream passes `args.bin_name` to
  clap_complete — same contract). Substitution targets: fish
  `complete -c xh`, bash `complete -F _xh xh`+fn names `_xh`→
  `_<bin>` + `_xh_`→`_<bin>_` prefixes, zsh `#compdef xh`, nu
  `export extern "xh"`, elvish `edit:completion:arg-completer[xh]`,
  ps1 `Register-ArgumentCompleter -Native -CommandName 'xh'`.
  (Script substitutes conservatively; spec pins the list.)
- man → vendored `doc/xh.1` with `.TH` title date →
  SOURCE_DATE_EPOCH ?: today (`YYYY-MM-DD`, upstream format) and
  the version line → our version string.
- man-markdown → vendored `doc/xh.1.md` with same version sub.

## S6 — netrc EntryState port (ADR-0042)

Rewrite `core/net` (or cli) netrc reader as the upstream machine:

- Tokenize per LINE into words (whitespace-sep; NO `#`-stripping at
  tokenize time — `#` starts a comment only when it begins a WORD,
  then skips to EOL; `#…` in value position is a literal value).
- EntryState {Wrong,Correct,Default} + finish_entry() on `machine`/
  `default`/`macdef`/unknown-word. Entry = {machine,login,password,
  account}.
- `default` words collect the fallback entry; `suppress_default` set
  when ANY `machine <host>` matches the URL host (incl. incomplete
  entries → INCOMPLETE_AND_DEFAULT: incomplete match blocks both
  the entry AND the default).
- `macdef` → finish entry + skip to next blank line.
- Lookup: first complete Correct entry, else Default (unless
  suppressed). `login.or(account)` for the user field.
- Host match: `url::Host` analog — casefold + trailing-dot strip +
  IPv4-int expansion (`16843009`==`1.1.1.1`, octal/hex forms per
  WHATWG host parse). IDNA → **deviation** (no punycode codec —
  non-ASCII hosts match literally).
- Decode: UTF-16BE/LE BOM → decode; else lossy UTF-8.
- File order: `$NETRC` → `~/.netrc` → `~/_netrc` (existing).
  `--ignore-netrc` skips entirely (existing).

## S7 — env tail

- `envnames()` += `XH_TEST_DIGEST_AUTH_CNONCE` (read in exec via
  env_get but absent from the list → dead in real runs today).
- `RUST_LOG`/`RUST_BACKTRACE`: no logger exists → inert; spec
  documents (corpus-faithful: only log output affected).
- `XH_HTTPIE_COMPAT_MODE` empty-string: upstream counts it via
  `var_os().is_some()`; `os.getenv` can't distinguish → documented
  deviation (already recorded).
- `REQUESTS_CA_BUNDLE`/`CURL_CA_BUNDLE`, `REQUEST_METHOD` guard,
  proxy env order, `NO_PROXY` matching: verified correct — no work.
- `SOURCE_DATE_EPOCH` honored by S5 man emit.

## S8 — harness + fixtures

- `cli/golden_test.oxl` `g_load` gains `env:` line → merge into the
  run's envpairs (same mechanism `files:` already uses) — needed for
  NO_PROXY/NO_COLOR/TERM/proxy-env fixtures.
- `curl-*` fixtures: re-derive against the new emit; add the 23
  upstream `to_curl.rs::tests` vectors as cases (adapted to our
  normalizer — no `<AE>`/`<CONN>` tokens anymore since synthesized
  headers don't emit; keep `xhs`-bin-name coverage via `rb`-style
  runner if cheap, else note). Provenance marker in each case
  header: `# source: upstream-test-vector to_curl.rs::tests` vs
  `# source: derived` (ADR-0021).
- Binary-suppressor TTY cases must run through a tty-buffered path —
  `xrun` (stdin_tty=1) in exec_test or an added `out_tty` param on
  `execute`; confirm plumbing in plan (execute signature may need
  an `out_tty` param — check during plan; xrun today can't fake
  stdout-tty).

## Structural changes

- `cli/exec.oxl`: `curl_emit`/`curl_ignored` rewritten (S1); new
  `curl_quote` (os_display port); `body_render` split into
  head-render + body-dispatch honoring FmtOpts/color/stream (S3);
  `htitle` gated to h1 + sort insertion point; latin1/UTF-8
  annotation; `generate` emit (S5); SGR color helpers (S4).
- `cli/sem.oxl`: delete `--generate` defer; delete fmt-opts defer;
  `FmtOpts` resolution (S2) — lives in sem or exec (pick in plan).
- `cli/fmt.oxl` (new, small): FmtOpts + palette table type +
  `convert_color` SGR emission + body lexers (S3/S4).
- `cli/gen_assets.oxl` + `cli/gen_styles.oxl` (generated by
  `scripts/gen-assets.sh`; committed; provenance header).
- `cli/main.oxl`: envnames += XH_TEST_DIGEST_AUTH_CNONCE.
- `cli/netrc*.oxl` (or wherever netrc lives — locate in plan):
  EntryState rewrite (S6).
- `cli/golden_test.oxl`: `env:` merge (S8).
- `tests/golden/cases|fixtures`: regenerated curl-*, new generate-*
  cases, new env-var cases.
- `docs/corpus/parity-matrix.md`: rows to `done`: §4.2 pretty/
  format-options/style/colors/response-*/stream-decode; §4.7
  generate; §5 curl map; §6 completions/man; §7 netrc defaults/
  `XH_TEST_*` note. `--compress` stays degraded (unchanged).

## Deviations (called out, none silent)

- **DevD1** `all:`→`all_proxy=` env prefix (upstream `-x`) — corpus
  §5 L226 already pins this as ours.
- **DevD2** ambient clearing in the curl env block — `no_proxy=
  NO_PROXY=` plus unset-scheme-var clears (`http_proxy= HTTP_PROXY=`
  `https_proxy= HTTPS_PROXY=` `all_proxy= ALL_PROXY=`); upstream emits
  none — kept from WI-0013 D7.
- **DevD3** charset decode bounded to {utf-8, utf-16le/be,
  windows-1252(+latin1/ascii)} + BOM sniff; other WHATWG labels →
  UTF-8-lossy (upstream: encoding_rs, all labels + chardet).
- **DevD4** body-highlight grammars are hand-rolled approximations;
  palette values are exact tmTheme extracts.
- **DevD5** XML formatter = bounded re-indent (strip ws-text +
  re-indent); malformed XML falls back raw like upstream, but our
  parser ≠ quick_xml on edge inputs.
- **DevD6** netrc IDNA host equivalence absent (no punycode in std);
  IPv4-int + casefold + dot-strip covered.
- **DevD7** `XH_HTTPIE_COMPAT_MODE` empty-string not counted
  (os.getenv limitation; already documented).
- **DevD8** `RUST_LOG`/`RUST_BACKTRACE` inert — no logger.
- **DevD9** `--compress` stays warn-degraded (std/compress decode-
  only; unchanged from WI-0013 disposition).
- **DevD10** h2/h3 heads render lowercase header names (upstream
  sends h2 names lowercased); our h2 support is ALPN-display-only,
  so only affects `req_head` synthesized h2 forms + future resp.
- **DevD11** event-stream linewise decode = bounded charsets (DevD3);
  `--stream`+binary abort → suppressor message (upstream identical).

## Acceptance criteria

1. `oxl build ./cli` clean; per-dir `oxl test` green; golden suite
   green on regenerated fixtures.
2. `--curl`: all 23 upstream `to_curl.rs::tests` vectors pass as
   golden cases (modulo documented DevD1/D2 + `<V>` normalization);
   `--curl-long` spellings; warnings order incl. blank separator;
   resolve/interface/unix/ipv4/ipv6 emit; multipart-JSON error text;
   follow+`-X` and `-h`+non-GET warnings.
3. `--format-options`: executes; indent/sort/format keys honored
   (sem_test defer expectations flipped); upstream diagnostics
   unchanged for bad values.
4. Pretty: json indent 4 default; header sort under `--pretty=format`
   and `all`; h1-only titlecase; UTF-8 annotation; TTY-gated
   suppressor (non-tty binary passes raw); event-stream auto-stream;
   `--pretty=colors` emits SGR without format.
5. Colors: `--style` × element table matches extracted tmTheme
   values (unit test asserts SGR for pinned elements per theme —
   e.g. ansi method=`\x1b[32m` (#02→Green), path=`\x1b[4;36m`
   (#06+underline)); NO_COLOR/TERM paths unchanged.
6. `--generate`: 8 kinds emit; completions contain substituted bin
   name; man `.TH` honors SOURCE_DATE_EPOCH; conflict-with-positional
   unchanged.
7. netrc: upstream vector tests port — INCOMPLETE_AND_DEFAULT,
   OCTOTHORPE_IN_VALUE, ENTRY_AFTER_DEFAULT, macdef-skip,
   IPv4-int host match, login-or-account fallback.
8. Env: `XH_TEST_DIGEST_AUTH_CNONCE` effective end-to-end (env
   capture → digest cnonce); proxy/netrc/CA paths unchanged.
9. Golden harness runs an `env:`-driven case (e.g. NO_PROXY bypass
   pin or NO_COLOR pretty-guess pin).
10. Parity matrix updated per §Structural-changes list; ship-stage
    findings on file: os.getenv empty/unset, std/compress decode-only.
