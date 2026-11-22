# WI-0006 spec — S5 CLI request path and golden harness

Upstream: WI-0001 plan S5 + spec; ADRs 0006/0007/0014/0015/0017–0023.
Corpus: `docs/corpus/corpus-xh.md` §1–9 — every behavior below cites
it; source-verified against a fetched tree (main.rs/request_items.rs/
printer.rs/formatting/headers.rs/session.rs/auth.rs/netrc.rs/
download.rs/error_reporting.rs/utils.rs @ 8b21cc0) and live probes
of `xh 0.26.3` (musl release tarball) against a local server.

## Intent

`cli/` gains the execution half of `run()`: `resolve()`'s populated
`Intent` becomes a `model.Req`, the h1 transport sends it, and the
printer emits xh-identical stdout/stderr/exit codes — plus the
committed-fixtures golden harness (ADR 0021) that proves it against
real xh captures. Deferred flags keep honest degrades (0006/0015);
TLS knobs stay parse-inert (upstream: unused on http://).

Non-goals: --curl translation, --generate, pretty/color/format
processing (no TTY this build — output is the non-TTY byte surface),
nested-JSON key paths (S6), proxying, h2/h3, unix sockets,
interface binding, real DNS overrides, RFC 6265-complete cookies
(ADR 0023), TTY-only behaviors (interactive prompts except
/dev/tty password read, progress bar glyphs → plain lines only).

## Files

- `cli/req.oxl` — pure-ish assembly: Intent+env+stdin → `ReqPlan`
  `{req: model.Req, warn: []str, err: str, host: str, port: int,
  version10: int, sess: own SessCtx}`. Covers headers merge
  (§sem-A), body build (§sem-B), URL+query (§sem-C), auth incl.
  session/netrc (§sem-D), compress (§sem-E), session load (§sem-F).
  File reads (item @file bodies, session, netrc) happen here —
  `err` carries the corpus text on failure.
- `cli/print.oxl` — the printer: `req_head()/resp_head()` renderers
  (titlecase, latin1 values, UTF-8 annotation), body emitters,
  meta line, separator, BINARY_SUPPRESSOR, reason canonical table,
  download filename + progress strings (HumanBytes fmt), -o/-d
  destinations. All byte-oriented (`[]byte` or str-builders).
- `cli/sess.oxl` — session load/persist (xhr §sem-F) + `netrc.oxl`
  — the ~/.netrc parser (§sem-D).
- `cli/exec.oxl` — `fn execute(i: ref Intent, env: []str,
  stdin: []byte, stdin_tty: int) -> own Run`; `Run{code:int,
  stdout:[]byte, stderr:[]byte}`. Orchestrates: ReqPlan → offline
  short-circuit → transport → per-print-set stream assembly →
  check-status → download/-o → session persist → degrade tails.
  Digest retry lives here (§sem-D).
- `cli/main.oxl` — wire exec: after resolve() + `o.exec`, detect
  stdin TTY (`/dev/stdin` realpath, ADR 0022), read stdin bytes
  when redirected, `execute()`, write streams, quit(code).
- `cli/sem.oxl` — `Out` gains `exec: int`; step-10 routing gains
  the S5 degrade table (§sem-G) and sets `exec` instead of the
  catch-all deferral.
- `core/model/model.oxl` — `Resp` gains `hops: own []Hop` +
  `version: str`; `Hop{req_head: own ReqHead, status: int,
  reason: str, version: str, headers: []Header, body: []byte,
  elapsed_ms: float, remote: str}`; `ReqHead{method: str, uri:
  str, headers: []Header}` (ADR 0020).
- `core/http/wire.oxl` — `serialize_head` takes `version: str`
  (`HTTP/1.0` when http-version=1.0); emits `Host` LAST (matches
  upstream wire order — observed `... Content-Length, Host`).
- `core/http/h1.oxl` — roundtrip records version; send() fills
  `hops` per redirect hop (request head + response, jar-lite
  cookie carry per ADR 0023 via the `Cookie`/`Set-Cookie` header
  fields already on Req/Resp).
- `cli/golden_test.oxl` — the differential harness: scripted
  server (Fx-adapted: per-request script incl. <ECHO>, <SLEEP:ms>,
  redirect/401-digest/set-cookie scripts), case-file parser,
  normalizer+comparator, `OXTPP_XH` live-diff mode.
- `tests/golden/` — `cases/*.case` + `fixtures/<case>.{stdout,
  stderr,exit}` committed captures (generator output).
- `scripts/golden-gen.sh` — regenerates fixtures via real `xh`
  ($OXTPP_XH or PATH) + built `oxttp` against a local scripted
  server; documented in `tests/golden/README.md`.
- `CHANGELOG.md` — Unreleased Added line.

## Semantics — request construction (sem-A..F)

### A. Header merge order (upstream run() — verified)

Build the wire header list in this exact order; a name compares
case-insensitively; display prints Title-Case names:

1. `Accept-Encoding: gzip, deflate` (deviation ADR 0017 — upstream
   `gzip, deflate, br, zstd`; `--download` → `identity` in-place).
2. `User-Agent: oxttp/<ver>` (version.get(); upstream `xh/0.26.3`).
3. `Connection: close` (deviation ADR 0019 — upstream
   `keep-alive`, emitted only when http-version ∈ {none,1.0,1.1};
   we emit close unconditionally).
4. Body-kind headers (§B): json → `Accept: application/json,
   */*;q=0.5` + `Content-Type: application/json`; form →
   `Content-Type: application/x-www-form-urlencoded`; multipart →
   `Content-Type: multipart/form-data; boundary=<MP_BOUNDARY>`;
   raw → form? CT-urlencoded : Accept-json+CT-json; file →
   `Content-Type: <;type=|mime|json>`; stdin → raw rules.
   Empty-json special cases (§B).
5. `Range: bytes=<n>-` when --continue resumes (§download).
6. `Authorization: Basic <b64>` / `Bearer <tok>` (§D).
7. Session+item headers merged (session first, items appended per
   name — §F), applied via replace_headers semantics: a name that
   already exists in the list gets ALL its values replaced by the
   merged list's values at the name's first position; new names
   append in first-seen order. Item values are NOT trimmed
   (`Cookie: a=b` item → wire `Cookie:  a=b` — the `:` separator
   leaves the leading space in the value; `name: " " + value`).
   `HeaderFromFile` values ARE trimmed. `key;` → empty value.
8. Unset names (HttpHeaderToUnset not cancelled by a later set)
   remove every occurrence — including 1/2/3 (e.g. `user-agent:`).
9. Synthesized (display + wire agree): `Accept: */*` appended iff
   accept absent; jar-lite `Cookie: n=v; n2=v2` (§F/D23) when jar
   non-empty — inserted after the accept line, before CL;
   `Content-Length: <n>` when body; `Host[:port]` LAST (port only
   when the URL carries one explicitly).

Wire order observed on real xh: `AE, UA, Conn, [body hdrs], [Range],
[Authorization], [item hdrs], Accept*?, Cookie?, Content-Length,
Host`. Our deviation: Host LAST here (wire.oxl change) — matches
upstream byte order for echo fixtures.

Unset ordering note: upstream applies unsets AFTER compress; CE
unset removes the compress header — order irrelevant to us since
unset precedes synthesis anyway; pin: unsets apply at step 8,
compress's `Content-Encoding: deflate` is a step-4-ish builder
header (compress applies after items in upstream but before unsets
— so a `Content-Encoding:` item suppresses compress w/ warning, and
`content-encoding:` unsets BOTH the item and the compress header).

### B. Body kinds (request_items.rs — verified)

- json (body_type 0): `key=v` → `{"key":"v"}` (jstr); `key=@f` →
  string from file bytes (utf8-lossy read — readfile_); `key:=j` →
  the parsed Json (already validated); `key:=@f` → jparse(file);
  keys insert flat at root (nested `[a][b]` paths = S6; the key
  text is taken literally — deviation: `a[b]` keys emit `{"a[b]":v}`
  rather than nested — corpus-visible only for path keys).
  Serialization via json.tojson (compact, no spaces — verified
  `{"name":"jo"}`).
- Json special: assembled object == `null` (no data items) AND
  `--json` explicitly passed → Accept-json+CT-json headers, EMPTY
  body; == null and --json absent → no body headers at all.
- form (1): `key=v`/`key=@f` → `k=v&` urlencoded (same queryescape
  as render_form); `:=` items → error `JSON values are not
  supported in Form fields`; `key@file` promotes to multipart.
- multipart (2 or form+FormFile): text parts `Content-Disposition:
  form-data; name="k"`; file parts + `; filename="<;filename=|
  basename>"` + `Content-Type: <;type=>` when given; boundary =
  our fixed MP_BOUNDARY (deviation — upstream random; normalized
  in fixtures).
- raw (`--raw`): verbatim; CT/Accept per §A.4.
- file (bare `@file`): `;type=` > suffix-mime (small table:
  .json/.txt/.html/.xml/.jpg/.png/.gif/.pdf/.bin fallback — pin
  the table; upstream mime_guess) > `application/json`; `;filename=`
  → warning `Ignoring ;filename= tag for single-file body. Consider
  --multipart.` Non-`@file` items + bare `@file` → error `Request
  body (from a file) and request data (key=value) cannot be mixed.`
  Two `@file` → `Can't read request from multiple files`.
  `key@file` under json → `Can't use file fields in JSON mode
  (perhaps you meant --form?)`.
- stdin (non-TTY, !--ignore-stdin): `is_body_empty()` false (items
  or --multipart present) → multipart? `Cannot build a multipart
  request body from stdin` : `Request body (from stdin) and request
  data (key=value) cannot be mixed. Pass --ignore-stdin to ignore
  standard input.`; `--raw` → `Request body from stdin and --raw
  cannot be mixed. Pass --ignore-stdin to ignore standard input.`;
  else `Body::Raw(stdin_bytes)` incl. EMPTY stdin → CL:0 +
  json headers (verified `</dev/null`).

### C. URL + query

`url_with_query`: UrlParam/UrlParamFromFile (`==`/`==@` — file
contents NOT trimmed) append `k=<formescaped v>` to existing query
(`?z=9&q=1` merge order: existing first). Escaping = the same
application/x-www-form-urlencoded set as render_form (space→`+`).
Url path stays as constructed (sem's construct_url output already
pins `://`, `:`, scheme rules). Request-target = path + `?` +
rawquery; display uses the same.

### D. Auth (arg → session → netrc precedence — verified)

1. Session auth first (§F) when no `--auth`/`--bearer`.
2. `-a USER:PASS`/`--bearer TOK`: auth-type basic → split FIRST
   colon → `Basic base64(user:pass)`; trailing `:` → password
   empty (`u:` → base64(`u:`)); NO colon → prompt via /dev/tty
   (`http: password for u@<host>: ` on the tty, read line) —
   /dev/tty open fails → error `<prog>: error: failed to prompt
   for password` (deviation: upstream rpassword error text).
   bearer → `Bearer <whole string>`. digest → §D3.
3. digest: send without Authorization; on 401 + `WWW-Authenticate:
   Digest ...` → compute MD5 digest response (realm/nonce/qop=auth
   → nc=00000001 + cnonce; opaque; uri=path[?query]; algorithm
   MD5 only — MD5-sess/auth-int degrade) and resend ONCE.
   `XH_TEST_DIGEST_AUTH_CNONCE` overrides cnonce (upstream hook —
   golden fixtures stay deterministic). No Digest header on the
   401 → response passes through as-is.
4. netrc: only when no explicit/session auth and !--ignore-netrc.
   `$NETRC` else `~/.netrc` else `~/_netrc` (first found); word
   scan: `machine <h>` (host match → collect), `default`
   (fallback; suppressed once any machine entry seen), `login`,
   `password`, `account` (login fallback), `macdef` → skip to
   blank line, `#` → comment to EOL; entry needs login+password.
   auth-type maps: basic→Basic(login,password); bearer→Bearer(
   password); digest→Digest. Not saved to session.

### E. --compress

zlib.deflate the rendered body; skip + warn `--compress can't be
used with a 'Content-Encoding:' header. --compress will be
disabled.` when that header exists (post-merge, pre-unset); skip
when out>=in unless -xx; else `Content-Encoding: deflate` header
added (builder slot — appended after body headers; unset can
remove it).

### F. Sessions (session.rs — verified)

- Path: value contains `/` → literal; else `<config_dir>/sessions/
  <host>[_<port>]/<name>.json` (host `.`/`..`/empty → `<prog>:
  error: couldn't extract host from url` exit 1).
- Load: absent → empty session (still persists at end);
  unparseable → `couldn't load session "<path>"` exit 1.
  HTTPie-format migration: headers {name:value map} → list;
  cookies map → list; `localhost.local` domain → `localhost`.
- Merge: session headers occupy the list FIRST, item headers
  append (both lists via §A.7 rule — session values precede item
  values for a repeated name); session auth applies when no
  explicit auth; session cookies seed jar-lite; a `Cookie:` item
  header in session mode parses into jar (removed from headers).
- `save_headers`: the merged request-side header set minus
  `cookie`/`content-*`/`if-*` names → persisted (lowercase names,
  upstream HeaderMap serializes lowercase — our save writes
  lowercase to match: deviation-minimize; note wire/display keep
  original case).
- Persist after ANY response (incl. 4xx/5xx, after --all hops):
  `{ "__meta__": {"about": "oxttp session file", "xh":
  "0.1.0-dev"}, "auth": {"type","raw_auth"}, "cookies": [{name,
  value, expires?, path, secure?, domain?}], "headers": [{name,
  value}] }` — 4-space indent + trailing `\n`; skip when
  read-only AND file exists (read_only + absent file → writes).
  auth saved only for explicit --auth/--bearer (not netrc);
  cookies = jar contents after final response.
- `--session-read-only`: same load; never writes.

## Semantics — response handling (sem-R)

Print dispatch on `intent.print_set` (already resolved):
`req_h → print_request_headers` (`METHOD uri HTTP/x.y\n` +
Title-Case headers + `\n`; jar Cookie + Accept*/CL/Host synthesis
same as wire), `req_b → print_request_body` (verbatim body + `\n\n`;
NUL byte → BINARY_SUPPRESSOR text instead — applies non-TTY too),
then transport, then `res_h → print_response_headers` (`HTTP/x.y
CODE reason\n` + titlecase headers + `\n`; reason = wire phrase if
non-empty else canonical else `<unknown status code>` — canonical
table pinned: 200 OK,201 Created,202 Accepted,203 Non-Authoritative
Information,204 No Content,205 Reset Content,206 Partial Content,
300 Multiple Choices,301 Moved Permanently,302 Found,303 See Other,
304 Not Modified,305 Use Proxy,307 Temporary Redirect,308 Permanent
Redirect,400 Bad Request,401 Unauthorized,402 Payment Required,
403 Forbidden,404 Not Found,405 Method Not Allowed,406 Not
Acceptable,407 Proxy Authentication Required,408 Request Timeout,
409 Conflict,410 Gone,411 Length Required,412 Precondition Failed,
413 Payload Too Large,414 URI Too Long,415 Unsupported Media Type,
416 Range Not Satisfiable,417 Expectation Failed,418 I'm a teapot,
421 Misdirected Request,422 Unprocessable Entity,423 Locked,
424 Failed Dependency,425 Too Early,426 Upgrade Required,
428 Precondition Required,429 Too Many Requests,
431 Request Header Fields Too Large,451 Unavailable For Legal
Reasons,500 Internal Server Error,501 Not Implemented,
502 Bad Gateway,503 Service Unavailable,504 Gateway Timeout,
505 HTTP Version Not Supported,506 Variant Also Negotiates,
507 Insufficient Storage,508 Loop Detected,
510 Not Extended,511 Network Authentication Required),
`res_b → verbatim body` (+ separator `\n` iff res_m also set),
`res_m → Elapsed time: %.5fs\nRemote address: <remote>\n\n`.

Header NAME display: titlecase (upper first + after `-`) for
HTTP/1.x — both directions. Header VALUE display: ASCII verbatim;
non-ASCII → latin1-decoded (bytes→codepoints→UTF-8 bytes) +
` (UTF-8: <utf8>)` when the bytes are also valid UTF-8.

Request head version: `HTTP/1.0` when --http-version=1.0 else
`HTTP/1.1`. Response version: wire version verbatim.

--all intermediates (per hop in resp.hops, order): hop_i resp_h,
hop_i resp_b + `\n` separator, hop_i res_m, hop_{i+1} req_h,
hop_{i+1} req_b — each gated by `hist_set` fields; then the final
response per print_set. (Upstream interleaves live; post-hoc emit
is byte-identical.)

--offline: print per print_set (HB default), no send, exit 0.
Request body for offline = the assembled bytes (same render).

check-status (`intent.check_eff`): 300–399 && !follow → code 3;
416 && resume → `Download <o> is already complete`/`Download is
already complete` (stderr), code 0; 400–499 → 4; 500–599 → 5.
Warning `HTTP <code> <reason>` to stderr when failure &&
(is_redirected || !res_h) — is_redirected = !(output file) &&
!download (piped stdout = true this build).

--quiet: print set already empty; warnings emit at -q, suppressed
at -qq (errors never suppressed).

-o FILE: all print-set output writes to the file (truncate);
stdout untouched. -d/--download: body → dest (see below), headers
(+progress) → stderr. -d dest: `-o` file (truncate, or append on
resume) else stdout (`dest_name="<stdout>"`; filename-from-
response only on TTY — never this build). Progress (quiet==0):
`Downloading <HumanBytes> to "<dest>"` when Content-Length known
else `Downloading to "<dest>"`; after copy `Done. <HumanBytes> in
%.5fs (<rate>/s)`; incomplete (uncompressed CL mismatch) →
`Interrupted. ...` + blank + `Incomplete download: size=<t>;
downloaded=<d>` error exit 1. --continue: `Range:` header present
→ warning + disabled; else -o file exists → send Range, resume
offset; non-206 → resume dropped (truncate). HumanBytes: `N B`
int for <1KiB else `%.2f KiB|MiB|GiB` (indicatif-compatible).

Session persist runs after response handling on any response —
never on transport error (upstream returns early).

## Exit codes + error surface (sem-X)

- 0 success · 1 `<prog>: error: <msg>` app error (transport
  errors strip the leading `http: ` for display; multi-line anyhow
  cause chains are approximated single-line — deviation noted for
  the rare session-load causes) · 2 timeout (transport `timed
  out` → exit 2 + `request timed out after <ms>ms` — deviation:
  upstream reqwest text) and all clap-shape parse errors · 3/4/5
  check-status · 6 `Too many redirects (--max-redirects=N)`
  (transport text maps; strip `http: `).
- Warnings `<prog>: warning: <msg>` stderr (-qq suppresses).

## Deferral routing update (sem-G — decision 0015 amended)

Step 10 becomes, in order, all `{prog}: error:` exit-1 unless
noted:
a. m-sig present → upstream's exact message (unchanged).
b. http-version=3-prior-knowledge → upstream's (unchanged).
c. URL scheme != http → `<scheme> URLs are unsupported in this
   build (TLS is not available)` (unchanged text).
d. `--generate` → unchanged earlier step-3 route.
e. `--curl`/`--curl-long` → `--curl is unsupported in this build`
   (S7 owns translation).
f. `--http-version` ∈ {2, 2-prior-knowledge} → `HTTP/2 requests
   are unsupported in this build`.
g. `--proxy` present OR proxy env captured → `proxies are
   unsupported in this build` (proxy affects the connection —
   silent honoring is worse than failing).
h. `--resolve` → `--resolve is unsupported in this build`.
i. `--interface` → `--interface is unsupported in this build`.
j. `--ipv6` → `IPv6 is unsupported in this build` (--ipv4 inert —
   v4-only matches).
k. `--unix-socket` → `--unix-socket is unsupported in this build`.
l. `--debug` → warning `--debug logging is unsupported in this
   build` (stderr, -qq hides) + proceed — its contract is log
   shape, not request semantics.
m. else → `o.exec = 1` (the request path).

Inert this build (upstream-unused-on-http or byte-identical
non-TTY output): --verify/+env, --cert, --cert-key, --ssl,
--native-tls, --default-scheme (already applied), --ipv4,
--stream, --response-charset, --response-mime, --style,
--history-print (implemented via hist_set), --ignore-stdin/
--ignore-netrc (honored). --pretty != none, --format-options:
degrade `--pretty is unsupported in this build` / `--format-
options is unsupported in this build` — upstream honors them on
pipes (colors/format) so inert is NOT fidelity (route as
step-10 entries between k and l — spec'd order: after
unix-socket, before debug warning).

## Golden harness (tests/golden + cli/golden_test.oxl)

- Case file (`tests/golden/cases/<name>.case`), line-oriented
  `key: value` (+`argv:` remainder verbatim, `stdin:` literal or
  `@file`, `script:` the server script id/inline lines, `env:`
  NAME=value repeats, `files:` pre-state `path<tab>content` lines):
  argv tokenized shell-lite (single/double quotes, backslash).
  A case may declare `norm:` extra normalizer names.
- Fixture capture (`fixtures/<name>.stdout|stderr|exit`) — author-
  time REAL `xh 0.26.3` output for the same argv+stdin+env against
  an equivalent scripted server; `req` fixture optional — the
  captured raw request when asserting wire shape.
- `cli/golden_test.oxl`: loads cases (repo-root relative
  `tests/golden/`), spins the scripted server per case (adapted
  Fx: `<ECHO>`, `<SLEEP:ms>`, script lines
  `STATUS|HEADERS|BODY|REDIRECT|SETCOOKIE|DIGEST` — server emits
  per-step response; port injected into argv as `{PORT}`), runs
  `execute()` with the case env/stdin, normalizes both sides,
  asserts stdout+stderr+exit; a failing diff prints the first
  divergence. `OXTPP_XH=<bin>` → live mode: for each case ALSO run
  the real binary via... no os.exec — live mode = the generator
  script, not the test (see below; env presence just selects which
  fixture is compared — actually: with OXTPP_XH set, generator
  wrote `.oxttp` captures too and the test diffs ours vs xh's).
- Normalizer (order): prog name `xh|oxttp`→`<PROG>`; UA
  `xh/0.26.3|oxttp/*`→`<UA>`; `gzip, deflate, br, zstd`→`gzip,
  deflate`... no — map BOTH to `<AE>`; `Connection: keep-alive|
  close`→`<CONN>`; `Elapsed time: <float>`→`<EL>`; `Remote
  address:` value→`<RA>`; `Date:`/`Server:` resp headers→drop
  (fixture server omits them anyway — our scripted server controls
  response bytes so fixtures stay byte-stable); `boundary=
  <alnum>`→`<BOUNDARY>`; cnonce/response digest values→`<DIG>`
  only when XH_TEST_DIGEST_AUTH_CNONCE absent; session xh version
  string→`<VER>`; elapsed/in-progress timings inside download
  progress→`<T>`.
- `scripts/golden-gen.sh` — builds oxttp, starts the python3
  scripted server (`scripts/golden-server.py` — same script
  language as the oxl one), runs `xh` per case + `oxttp` per case,
  writes `fixtures/<case>.{stdout,stderr,exit}` (xh) and
  `.oxttp.{stdout,stderr,exit}` (ours, informational). Idempotent;
  requires $OXTPP_XH or `xh` on PATH; documented header comment +
  tests/golden/README.md.
- Gate (this WI): every committed case's `execute()` output diff-
  clean vs the xh fixture under the normalizer — the corpus rows:
  GET/HEAD/POST/PUT/DELETE/PURGE methods; item kinds (header
  dup/empty/unset/file, param merge+encoding, json/form/multipart
  bodies, @file, raw); stdin {empty,pipe,mix-error}; --offline;
  print combos (-v,-vv,-h,-b,-m,-p,--history-print+--all,-q,-qq);
  redirects (follow, max, cross-origin strip, 301→GET rewrite,
  307 keeps POST); check-status {3,4,5}+warning; -o/-d/-c; session
  create/reuse/read-only + cookie roundtrip; auth basic/bearer/
  netrc/digest; gzip/deflate resp; CL:0 empty stdin; EOF-framed
  body; timeout (SLEEP script); 204/304 bodyless; too-many-redirects
  exit 6; binary suppressor (request side); latin1 header value.

## Test matrix (the S5 gate)

`cli/req_test.oxl` — header merge matrix (order, replace vs
append, unset-last, `key;`, `@file` trim, session merge position,
accept*/CL/Host synth, cookie slot); body kinds incl. empty-json
split, form promote, multipart parts+params, bare @file errors,
stdin mix errors; query merge/escape; auth arg/session/netrc
precedence; compress skip/-xx; version10 flag.

`cli/print_test.oxl` — req/resp head renders (titlecase, reason
table incl. unknown→`<unknown status code>`, version strings),
latin1+UTF-8 annotate, binary suppressor, meta fmt `%.5fs`,
separator rule, HumanBytes, download filename/progress strings,
history hop emit order.

`cli/sess_test.oxl` — path resolution (literal/host_port/`.` err),
load absent/malformed/HTTPie-migrate, save_headers exclusions,
persist shape (exact pretty JSON bytes), RO skip, cookie seed→
jar→persist roundtrip, `couldn't load session` error text.

`cli/netrc_test.oxl` — machine/default/suppress-default, login/
password/account, comments, macdef skip, NETRC env + ~/.netrc +
~/_netrc precedence, incomplete entries.

`cli/exec_test.oxl` — scripted-server cases (fixture-level, not
golden): offline, prints, check-status exits+warning, follow+
--all+hops emit, timeout exit 2, redirects-exit-6, -o/-d/-c
files, digest 401 flow (XH_TEST_DIGEST_AUTH_CNONCE), jar carry
across redirect, download progress text, quiet levels.

`cli/golden_test.oxl` — the committed-fixture differential (above)
— runs under `oxl test ./cli` in the dir-loop.

`core/http/h1_test.oxl` — extend: hops filled per redirect
(2-hop), version recorded, cookie header carried hop→hop,
Host-last wire order.

## Deviations recorded this stage

1. AE `gzip, deflate` (0017), UA `oxttp/<ver>` (product identity),
   Conn `close` (0019) — normalizer-mapped in golden diffs.
2. `/dev/stdin` realpath TTY heuristic (0022) vs is_terminal().
3. Jar-lite cookies (0023): no path/domain/expires match.
4. Multipart boundary fixed `oxttp-multipart-*` (was S3 decision —
   now visible in CLI output; normalized).
5. `--debug` degrades to warning; proxy/resolve/interface/ipv6/
   unix/http2/pretty!=none/format-options degrade to errors —
   all `{prog}: error:` exit 1 per 0006.
6. Session `__meta__` carries `oxttp session file` + our version
   in the `xh` key slot (loaders ignore it).
7. Nested-JSON item keys are literal this stage (S6).
8. Password prompt via /dev/tty open — error text deviates when
   no controlling terminal.
9. anyhow `Caused by:` chains flattened to single-line errors.
10. Timeout/redirect error text is our transport's (`request
    timed out after <ms>ms`, `Too many redirects...` stripped of
    `http:` prefix) — upstream's reqwest strings differ.
11. `-q` hides download progress entirely (matches upstream
    quiet>0 → hidden pb).
12. `--pretty`/`--format-options`/`--style`/`--response-*`/`--stream`
    — inert or degraded per §sem-G; byte-identical only where
    non-TTY upstream output is itself unprocessed.

## Corpus coverage (this stage)

§1–2 invocation+positionals: shipped S4 — consumed. §3 items:
FULL incl. file variants + part params + mixing errors. §4.1
body kinds: FULL incl. stdin rules. §4.2 printing: non-TTY
surface FULL (pretty=none pipeline); TTY-only arms deferred by
constraint (documented). §4.3 download: FULL (TTY filename-dedup
n/a). §4.4 sessions: FULL incl. migrate + persist. §4.5 auth:
basic/bearer/netrc/digest(qop=auth MD5); verify/cert/ssl inert-
documented; proxy degrades. §4.6 redirects/conn: follow/max/all/
history-print/timeout/1.0; resolve/interface/unix/ipv6 degrade.
§4.7 modes: offline + check-status + curl-degrade + generate-
degrade. §4.8 --no-*: engine's S4 semantics ride through (unset
paths verified). §5 curl map: deferred (degrade). §6 config:
sessions path honored. §7 env: NETRC/HOME/NO_COLOR/TERM/XH_*/
*_PROXY/CA bundles wired per level; RUST_*/SOURCE_DATE_EPOCH
inert; XH_TEST_DIGEST_AUTH_CNONCE honored. §8 exits: FULL
{0..6}. §9 misc: Accept*/Host/CL display-synthesis, titlecase,
reason fallback, meta format, jar-lite (deviation), save_headers
exclusions — FULL.
